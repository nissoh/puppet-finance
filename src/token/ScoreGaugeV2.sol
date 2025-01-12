// // SPDX-License-Identifier: AGPL-3.0-only
// pragma solidity 0.8.19;

// // ==============================================================
// //  _____                 _      _____ _                        |
// // |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// // |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// // |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
// //           |_| |_|                                            |
// // ==============================================================
// // ========================= ScoreGaugeV1 ==============================
// // ==============================================================
// // Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// // Primary Author
// // Curve Finance: https://github.com/curvefi
// // johnnyonline: https://github.com/johnnyonline

// // Reviewers
// // itburnz: https://github.com/nissoh

// // ==============================================================

// import {IScoreGauge} from "src/interfaces/IScoreGauge.sol";
// import {IGaugeController} from "src/interfaces/IGaugeController.sol";

// /// @title ScoreGauge. Modified fork of Curve's LiquidityGauge
// /// @author johnnyonline (Puppet Finance) https://github.com/johnnyonline
// /// @notice Used to measure scores of Traders and Puppets, according to pre defined metrics with configurable weights, and distributes rewards to them
// contract ScoreGaugeV1 is IScoreGauge {

//     event UpdateLiquidityLimit(address user, uint256 original_balance, uint256 working_balance, uint256 working_supply);
//     event CommitOwnership(address admin);
//     event ApplyOwnership(address admin);

//     uint256 public constant TOKENLESS_PRODUCTION = 40;
//     uint256 public constant BOOST_WARMUP = 2 * 7 * 86400;
//     uint256 public constant WEEK = 604800;

//     address public minter;
//     address public crv_token;
//     address public lp_token;
//     address public controller;
//     address public voting_escrow;

//     uint256 public totalSupply;
//     uint256 public future_epoch_time;

//     mapping(address => uint256) public balanceOf;
//     mapping(address => mapping(address => bool)) public approved_to_deposit; // caller -> recipient -> can deposit?

//     mapping(address => uint256) public working_balances;
//     uint256 public working_supply;

//     // The goal is to be able to calculate ∫(rate * balance / totalSupply dt) from 0 till checkpoint
//     // All values are kept in units of being multiplied by 1e18
//     int128 public period;
//     uint256[100000000000000000000000000000] public period_timestamp;

//     // 1e18 * ∫(rate(t) / totalSupply(t) dt) from 0 till checkpoint
//     uint256[100000000000000000000000000000] public integrate_inv_supply; // bump epoch when rate() changes

//     // 1e18 * ∫(rate(t) / totalSupply(t) dt) from (last_action) till checkpoint
//     mapping(address => uint256) public integrate_inv_supply_of;
//     mapping(address => uint256) public integrate_checkpoint_of;


//     // ∫(balance * rate(t) / totalSupply(t) dt) from 0 till checkpoint
//     // Units: rate * t = already number of coins per address to issue
//     mapping(address => uint256) public integrate_fraction;

//     uint256 public inflation_rate;

//     address public admin;
//     address public future_admin; // Can and will be a smart contract
//     bool public is_killed;

//     mapping(uint256 => Score) public scores;

//     uint256 public contractCreationTimestamp;

//     // ============================================================================================
//     // Constructor
//     // ============================================================================================

//     /// @notice Contract constructor
//     /// @param _minter Minter contract address
//     /// @param _admin Admin who can kill the gauge
//     constructor(address _minter, address _admin) {
//         if (_minter != address(0)) revert ZeroAddress();
//         if (_admin != address(0)) revert ZeroAddress();

//         minter = _minter;
//         admin = _admin;

//         address _token = IMinter(_minter).token();
//         address _controller = IMinter(_minter).controller();

//         token = _token;
//         controller = _controller;
//         voting_escrow = IGaugeController(_controller).voting_escrow();
//         contractCreationTimestamp = block.timestamp;
//     }

//     // ============================================================================================
//     // View Functions
//     // ============================================================================================

//     // function integrate_checkpoint() external view returns (uint256) {
//     //     return period_timestamp[period];
//     // }

//     // ============================================================================================
//     // Mutative Functions
//     // ============================================================================================

//     // external

//     /// @notice Record a checkpoint for `_user`
//     /// @param _user User address
//     /// @return bool success
//     function userCheckpoint(address _user) external override returns (bool) {
//         if (msg.sender != _user && msg.sender != minter) revert("unauthorized");

//         _update_liquidity_limit(_user, balanceOf[_user], totalSupply);

//         return true;
//     }

//     // todo
//     // /// @notice Get the number of claimable tokens per user
//     // /// @dev This function should be manually changed to "view" in the ABI
//     // /// @return uint256 number of claimable tokens per user
//     // function claimableTokens(address _user) external override returns (uint256) {
//     //     _checkpoint(_user);
//     //     return integrate_fraction[_user] - Minter(minter).minted(_user, address(this));
//     // }

//     /// @notice Kick `_addr` for abusing their boost
//     /// @dev Only if either they had another voting event, or their voting escrow lock expired
//     /// @param _addr Address to kick
//     function kick(address _addr) external {
//         // address _voting_escrow = voting_escrow;
//         // uint256 _t_last = integrate_checkpoint_of[_addr];
//         // uint256 _t_ve = VotingEscrow(_voting_escrow).user_point_history__ts(
//         //     _addr, VotingEscrow(_voting_escrow).user_point_epoch(_addr)
//         // );
//         uint256 _balance = balanceOf[_addr];

//         // require (ERC20(_voting_escrow).balanceOf(_addr) == 0 || _t_ve > _t_last) revert("kickNotAllowed");
//         if (working_balances[_addr] <= _balance * TOKENLESS_PRODUCTION / 100) revert("kick not needed");

//         // _checkpoint(_addr);
//         _update_liquidity_limit(_addr, balanceOf[_addr], totalSupply);
//     }

//     // todo
//     function claim(uint256 _epoch) external {
//         if (_epoch >= IGaugeController(controller).epoch()) revert("Cannot claim for ongoing or future epoch");
//         if (claimedEpochs[msg.sender] >= _epoch) revert("Already claimed for this epoch");

//         EpochInfo storage _epochInfo = epochInfo[_epoch];
//         uint256 _userProfitScore = _epochInfo.userProfit[msg.sender] * 1e18 / _epochInfo.totalProfit;
//         uint256 _userCvgScore = _epochInfo.userCvg[msg.sender] * 1e18 / _epochInfo.totalCvg;
//         uint256 _userScore = (((_userProfitScore * _epochInfo.profitWeight + _userCvgScore * _epochInfo.cvgWeight) / 10000) * 1e18) / _epochInfo.totalScore;

//         if (epochScore.isTrader(msg.sender)) {
//             _userScore = (_userScore * traderWeight) / 10000;
//         } else {
//             _userScore = (_userScore * puppetWeight) / 10000;
//         }

//         uint256 userAdjustedRewardMultiplier = (working_balances[msg.sender] * 1e18) / working_supply;
//         _userScore = (_userScore * userAdjustedRewardMultiplier) / 1e18; // scale down after multiplication

//         // Update user's balance
//         balanceOf[msg.sender] += userReward;
//         balanceOf[address(this)] -= userReward;

//         // Mark the epoch as claimed for this user
//         claimedEpochs[msg.sender] = _epoch;

//         // Emit an event or perform other necessary actions (like transferring tokens if needed)
//     }

//     /// @inheritdoc IScoreGauge
//     function updateUserScore(uint256 _volumeGenerated, uint256 _profit, address _user, bool _isTrader) external {
//         Score storage _score = scores[IGaugeController(controller).epoch()];
//         if (_isTrader) {
//             _score.tradersScore[_user].cumulativeVolumeGenerated += _volumeGenerated;
//             _score.tradersScore[_user].profit += _profit;
//             _score.totalCumulativeVolumeGenerated += _volumeGenerated;
//             _score.totalProfit += _profit;
//         } else {
//             _score.puppetsScore[_user].cumulativeVolumeGenerated += _volumeGenerated;
//             _score.puppetsScore[_user].profit += _profit;
//             _score.totalCumulativeVolumeGenerated += _volumeGenerated;
//             _score.totalProfit += _profit;
//         }
//     }

//     function kill_me() external {
//         if (msg.sender != admin) revert("unauthorized");
//         is_killed = !is_killed;
//     }

//     /// @notice Transfer ownership of GaugeController to `_addr`
//     /// @param _addr Address to have ownership transferred to
//     function commit_transfer_ownership(address _addr) external {
//         if (msg.sender != admin) revert("unauthorized");
//         future_admin = _addr;
//         emit CommitOwnership(_addr);
//     }

//     /// @notice Apply pending ownership transfer
//     function apply_transfer_ownership() external {
//         if (msg.sender != admin) revert("unauthorized");
//         address _admin = future_admin;
//         if (_admin == address(0)) revert("admin not set");
//         admin = _admin;
//         emit ApplyOwnership(_admin);
//     }

//     // internal

//     /// @notice Calculate limits which depend on the amount of CRV token per-user.
//     ///         Effectively it calculates working balances to apply amplification
//     ///         of CRV production by CRV
//     /// @param _addr User address
//     /// @param _l User's amount of liquidity (LP tokens)
//     /// @param _L Total amount of liquidity (LP tokens)
//     function _update_liquidity_limit(address _addr, uint256 _l, uint256 _L) internal {
//         // To be called after totalSupply is updated
//         address _voting_escrow = voting_escrow;
//         uint256 _voting_balance = IERC20(_voting_escrow).balanceOf(_addr);
//         uint256 _voting_total = IERC20(_voting_escrow).totalSupply();

//         uint256 _lim = _l * TOKENLESS_PRODUCTION / 100;
//         // if (_voting_total > 0 && block.timestamp > period_timestamp[0] + BOOST_WARMUP) {
//         if (_voting_total > 0 && block.timestamp > contractCreationTimestamp + BOOST_WARMUP) {
//             _lim += _L * _voting_balance / _voting_total * (100 - TOKENLESS_PRODUCTION) / 100;
//         }

//         _lim = _lim <= _l ? _lim : _l;
//         uint256 _old_bal = working_balances[_addr];
//         working_balances[_addr] = _lim;
//         uint256 _working_supply = working_supply + _lim - _old_bal;
//         working_supply = _working_supply;

//         emit UpdateLiquidityLimit(_addr, _l, _L, _lim, _working_supply);
//     }
// }

// // @internal
// // def _checkpoint(addr: address):
// //     """
// //     @notice Checkpoint for a user
// //     @param addr User address
// //     """
// //     _token: address = self.crv_token
// //     _controller: address = self.controller
// //     _period: int128 = self.period
// //     _period_time: uint256 = self.period_timestamp[_period]
// //     _integrate_inv_supply: uint256 = self.integrate_inv_supply[_period]
// //     rate: uint256 = self.inflation_rate
// //     new_rate: uint256 = rate
// //     prev_future_epoch: uint256 = self.future_epoch_time
// //     if prev_future_epoch >= _period_time:
// //         self.future_epoch_time = CRV20(_token).future_epoch_time_write()
// //         new_rate = CRV20(_token).rate()
// //         self.inflation_rate = new_rate
// //     Controller(_controller).checkpoint_gauge(self)

// //     _working_balance: uint256 = self.working_balances[addr]
// //     _working_supply: uint256 = self.working_supply

// //     if self.is_killed:
// //         rate = 0  # Stop distributing inflation as soon as killed

// //     # Update integral of 1/supply
// //     if block.timestamp > _period_time:
// //         prev_week_time: uint256 = _period_time
// //         week_time: uint256 = min((_period_time + WEEK) / WEEK * WEEK, block.timestamp)

// //         for i in range(500):
// //             dt: uint256 = week_time - prev_week_time
// //             w: uint256 = Controller(_controller).gauge_relative_weight(self, prev_week_time / WEEK * WEEK)

// //             if _working_supply > 0:
// //                 if prev_future_epoch >= prev_week_time and prev_future_epoch < week_time:
// //                     # If we went across one or multiple epochs, apply the rate
// //                     # of the first epoch until it ends, and then the rate of
// //                     # the last epoch.
// //                     # If more than one epoch is crossed - the gauge gets less,
// //                     # but that'd meen it wasn't called for more than 1 year
// //                     _integrate_inv_supply += rate * w * (prev_future_epoch - prev_week_time) / _working_supply
// //                     rate = new_rate
// //                     _integrate_inv_supply += rate * w * (week_time - prev_future_epoch) / _working_supply
// //                 else:
// //                     _integrate_inv_supply += rate * w * dt / _working_supply
// //                 # On precisions of the calculation
// //                 # rate ~= 10e18
// //                 # last_weight > 0.01 * 1e18 = 1e16 (if pool weight is 1%)
// //                 # _working_supply ~= TVL * 1e18 ~= 1e26 ($100M for example)
// //                 # The largest loss is at dt = 1
// //                 # Loss is 1e-9 - acceptable

// //             if week_time == block.timestamp:
// //                 break
// //             prev_week_time = week_time
// //             week_time = min(week_time + WEEK, block.timestamp)

// //     _period += 1
// //     self.period = _period
// //     self.period_timestamp[_period] = block.timestamp
// //     self.integrate_inv_supply[_period] = _integrate_inv_supply

// //     # Update user-specific integrals
// //     self.integrate_fraction[addr] += _working_balance * (_integrate_inv_supply - self.integrate_inv_supply_of[addr]) / 10 ** 18
// //     self.integrate_inv_supply_of[addr] = _integrate_inv_supply
// //     self.integrate_checkpoint_of[addr] = block.timestamp