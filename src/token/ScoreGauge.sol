// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ========================= Route ==============================
// ==============================================================
// Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// Primary Author
// Curve Finance: https://github.com/curvefi
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================
// interface CRV20:
//     def future_epoch_time_write() -> uint256: nonpayable
//     def rate() -> uint256: view

// interface Controller:
//     def period() -> int128: view
//     def period_write() -> int128: nonpayable
//     def period_timestamp(p: int128) -> uint256: view
//     def gauge_relative_weight(addr: address, time: uint256) -> uint256: view
//     def voting_escrow() -> address: view
//     def checkpoint(): nonpayable
//     def checkpoint_gauge(addr: address): nonpayable

// interface Minter:
//     def token() -> address: view
//     def controller() -> address: view
//     def minted(user: address, gauge: address) -> uint256: view

// interface VotingEscrow:
//     def user_point_epoch(addr: address) -> uint256: view
//     def user_point_history__ts(addr: address, epoch: uint256) -> uint256: view

import {IScoreGauge} from "src/interfaces/IScoreGauge.sol";
import {IGaugeController} from "src/interfaces/IGaugeController.sol";

/// @title ScoreGauge. Modified fork of Curve's LiquidityGauge
/// @author johnnyonline (Puppet Finance) https://github.com/johnnyonline
/// @notice Used to measure scores of Traders and Puppets, according to pre defined metrics with configurable weights, and distributes rewards to them
contract ScoreGauge is IScoreGauge {

    event UpdateLiquidityLimit(address user, uint256 original_balance, uint256 working_balance, uint256 working_supply);
    event CommitOwnership(address admin);
    event ApplyOwnership(address admin);

    uint256 public constant TOKENLESS_PRODUCTION = 40;
    uint256 public constant BOOST_WARMUP = 2 * 7 * 86400;
    uint256 public constant WEEK = 604800;

    address public minter;
    address public crv_token;
    address public lp_token;
    address public controller;
    address public voting_escrow;

    uint256 public totalSupply;
    uint256 public future_epoch_time;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => bool)) public approved_to_deposit; // caller -> recipient -> can deposit?

    mapping(address => uint256) public working_balances;
    uint256 public working_supply;

    // The goal is to be able to calculate ∫(rate * balance / totalSupply dt) from 0 till checkpoint
    // All values are kept in units of being multiplied by 1e18
    int128 public period;
    uint256[100000000000000000000000000000] public period_timestamp;

    // 1e18 * ∫(rate(t) / totalSupply(t) dt) from 0 till checkpoint
    uint256[100000000000000000000000000000] public integrate_inv_supply; // bump epoch when rate() changes

    // 1e18 * ∫(rate(t) / totalSupply(t) dt) from (last_action) till checkpoint
    mapping(address => uint256) public integrate_inv_supply_of;
    mapping(address => uint256) public integrate_checkpoint_of;


    // ∫(balance * rate(t) / totalSupply(t) dt) from 0 till checkpoint
    // Units: rate * t = already number of coins per address to issue
    mapping(address => uint256) public integrate_fraction;

    uint256 public inflation_rate;

    address public admin;
    address public future_admin; // Can and will be a smart contract
    bool public is_killed;

    mapping(uint256 => Score) public scores;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    /// @notice Contract constructor
    /// @param _minter Minter contract address
    /// @param _admin Admin who can kill the gauge
    constructor(address _minter, address _admin) {
        if (_minter != address(0)) revert ZeroAddress();
        if (_admin != address(0)) revert ZeroAddress();

        minter = _minter;
        admin = _admin;

        address _crv_addr = Minter(_minter).token();
        address _controller = Minter(_minter).controller();

        crv_token = _crv_addr;
        controller = _controller;
        voting_escrow = Controller(_controller).voting_escrow();
        period_timestamp[0] = block.timestamp;
        inflation_rate = CRV20(crv_addr).rate();
        future_epoch_time = CRV20(crv_addr).future_epoch_time_write();
        lp_addr = address(0); // todo remove?
    }

    // ============================================================================================
    // View Functions
    // ============================================================================================

    // external

    // internal

    // ============================================================================================
    // Mutative Functions
    // ============================================================================================

    // external

    // @external
    // @nonreentrant('lock')
    // def deposit(_value: uint256, addr: address = msg.sender):
    //     @notice Deposit `_value` LP tokens
    //     @param _value Number of tokens to deposit
    //     @param addr Address to deposit for
    //     if addr != msg.sender:
    //         assert self.approved_to_deposit[msg.sender][addr], "Not approved"

    //     self._checkpoint(addr)

    //     if _value != 0:
    //         _balance: uint256 = self.balanceOf[addr] + _value
    //         _supply: uint256 = self.totalSupply + _value
    //         self.balanceOf[addr] = _balance
    //         self.totalSupply = _supply

    //         self._update_liquidity_limit(addr, _balance, _supply)

    //         assert ERC20(self.lp_token).transferFrom(msg.sender, self, _value)

    //     log Deposit(addr, _value)
    function deposit

    /// @notice Record a checkpoint for `_user`
    /// @param _user User address
    /// @return bool success
    function userCheckpoint(address _user) external override returns (bool) {
        if (msg.sender != _user && msg.sender != minter) revert("unauthorized");

        _checkpoint(_user);
        _updateLiquidityLimit(_user, balanceOf[_user], totalSupply);

        return true;
    }

    /// @notice Get the number of claimable tokens per user
    /// @dev This function should be manually changed to "view" in the ABI
    /// @return uint256 number of claimable tokens per user
    function claimableTokens(address _user) external override returns (uint256) {
        _checkpoint(_user);
        return integrate_fraction[_user] - Minter(minter).minted(_user, address(this));
    }

    /// @notice Kick `_addr` for abusing their boost
    /// @dev Only if either they had another voting event, or their voting escrow lock expired
    /// @param _addr Address to kick
    function kick(address _addr) external {
        if (msg.sender != admin) revert("unauthorized");

        address _voting_escrow = voting_escrow;
        uint256 _t_last = integrate_checkpoint_of[_addr];
        uint256 _t_ve = VotingEscrow(_voting_escrow).user_point_history__ts(
            _addr, VotingEscrow(_voting_escrow).user_point_epoch(_addr)
        );
        uint256 _balance = balanceOf[_addr];

        if (ERC20(_voting_escrow).balanceOf(_addr) == 0 || _t_ve > _t_last) revert("kickNotAllowed");
        if (working_balances[_addr] <= _balance * TOKENLESS_PRODUCTION / 100) revert("kickNotNeeded");

        _checkpoint(_addr);
        _updateLiquidityLimit(_addr, balanceOf[_addr], totalSupply);
    }

    /// @notice Set whether `_addr` can deposit tokens for `msg.sender`
    /// @param _addr Address to set approval on
    /// @param _can_deposit bool - can this account deposit for `msg.sender`?
    function set_approve_deposit(address _addr, bool _can_deposit) external {
        approved_to_deposit[_addr][msg.sender] = _can_deposit;
    }

    /// @inheritdoc IScoreGauge
    function updateUserScore(uint256 _volumeGenerated, uint256 _profit, address _user, bool _isTrader) external {
        Score storage _score = scores[IGaugeController(controller).epoch()];
        if (_isTrader) {
            _score.tradersScore[_user].cumulativeVolumeGenerated += _volumeGenerated;
            _score.tradersScore[_user].profit += _profit;
            _score.totalCumulativeVolumeGenerated += _volumeGenerated;
            _score.totalProfit += _profit;
        } else {
            _score.puppetsScore[_user].cumulativeVolumeGenerated += _volumeGenerated;
            _score.puppetsScore[_user].profit += _profit;
            _score.totalCumulativeVolumeGenerated += _volumeGenerated;
            _score.totalProfit += _profit;
        }
    }

    // internal

    /// @notice Calculate limits which depend on the amount of CRV token per-user.
    ///         Effectively it calculates working balances to apply amplification
    ///         of CRV production by CRV
    /// @param _addr User address
    /// @param _l User's amount of liquidity (LP tokens)
    /// @param _L Total amount of liquidity (LP tokens)
    function _update_liquidity_limit(address _addr, uint256 _l, uint256 _L) internal {
        // To be called after totalSupply is updated
        address _voting_escrow = voting_escrow;
        uint256 _voting_balance = IERC20(_voting_escrow).balanceOf(_addr);
        uint256 _voting_total = IERC20(_voting_escrow).totalSupply();

        uint256 _lim = _l * TOKENLESS_PRODUCTION / 100;
        if (_voting_total > 0 && block.timestamp > period_timestamp[0] + BOOST_WARMUP) {
            _lim += _L * _voting_balance / _voting_total * (100 - TOKENLESS_PRODUCTION) / 100;
        }

        _lim = min(_l, _lim);
        uint256 _old_bal = working_balances[_addr];
        working_balances[_addr] = _lim;
        uint256 _working_supply = working_supply + _lim - _old_bal;
        working_supply = _working_supply;

        emit UpdateLiquidityLimit(_addr, _l, _L, _lim, _working_supply);
    }
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a <= b ? a : b;
    }
}


// @internal
// def _checkpoint(addr: address):
//     """
//     @notice Checkpoint for a user
//     @param addr User address
//     """
//     _token: address = self.crv_token
//     _controller: address = self.controller
//     _period: int128 = self.period
//     _period_time: uint256 = self.period_timestamp[_period]
//     _integrate_inv_supply: uint256 = self.integrate_inv_supply[_period]
//     rate: uint256 = self.inflation_rate
//     new_rate: uint256 = rate
//     prev_future_epoch: uint256 = self.future_epoch_time
//     if prev_future_epoch >= _period_time:
//         self.future_epoch_time = CRV20(_token).future_epoch_time_write()
//         new_rate = CRV20(_token).rate()
//         self.inflation_rate = new_rate
//     Controller(_controller).checkpoint_gauge(self)

//     _working_balance: uint256 = self.working_balances[addr]
//     _working_supply: uint256 = self.working_supply

//     if self.is_killed:
//         rate = 0  # Stop distributing inflation as soon as killed

//     # Update integral of 1/supply
//     if block.timestamp > _period_time:
//         prev_week_time: uint256 = _period_time
//         week_time: uint256 = min((_period_time + WEEK) / WEEK * WEEK, block.timestamp)

//         for i in range(500):
//             dt: uint256 = week_time - prev_week_time
//             w: uint256 = Controller(_controller).gauge_relative_weight(self, prev_week_time / WEEK * WEEK)

//             if _working_supply > 0:
//                 if prev_future_epoch >= prev_week_time and prev_future_epoch < week_time:
//                     # If we went across one or multiple epochs, apply the rate
//                     # of the first epoch until it ends, and then the rate of
//                     # the last epoch.
//                     # If more than one epoch is crossed - the gauge gets less,
//                     # but that'd meen it wasn't called for more than 1 year
//                     _integrate_inv_supply += rate * w * (prev_future_epoch - prev_week_time) / _working_supply
//                     rate = new_rate
//                     _integrate_inv_supply += rate * w * (week_time - prev_future_epoch) / _working_supply
//                 else:
//                     _integrate_inv_supply += rate * w * dt / _working_supply
//                 # On precisions of the calculation
//                 # rate ~= 10e18
//                 # last_weight > 0.01 * 1e18 = 1e16 (if pool weight is 1%)
//                 # _working_supply ~= TVL * 1e18 ~= 1e26 ($100M for example)
//                 # The largest loss is at dt = 1
//                 # Loss is 1e-9 - acceptable

//             if week_time == block.timestamp:
//                 break
//             prev_week_time = week_time
//             week_time = min(week_time + WEEK, block.timestamp)

//     _period += 1
//     self.period = _period
//     self.period_timestamp[_period] = block.timestamp
//     self.integrate_inv_supply[_period] = _integrate_inv_supply

//     # Update user-specific integrals
//     self.integrate_fraction[addr] += _working_balance * (_integrate_inv_supply - self.integrate_inv_supply_of[addr]) / 10 ** 18
//     self.integrate_inv_supply_of[addr] = _integrate_inv_supply
//     self.integrate_checkpoint_of[addr] = block.timestamp


// @external
// @nonreentrant('lock')
// def withdraw(_value: uint256):
//     """
//     @notice Withdraw `_value` LP tokens
//     @param _value Number of tokens to withdraw
//     """
//     self._checkpoint(msg.sender)

//     _balance: uint256 = self.balanceOf[msg.sender] - _value
//     _supply: uint256 = self.totalSupply - _value
//     self.balanceOf[msg.sender] = _balance
//     self.totalSupply = _supply

//     self._update_liquidity_limit(msg.sender, _balance, _supply)

//     assert ERC20(self.lp_token).transfer(msg.sender, _value)

//     log Withdraw(msg.sender, _value)


// @external
// @view
// def integrate_checkpoint() -> uint256:
//     return self.period_timestamp[self.period]


// @external
// def kill_me():
//     assert msg.sender == self.admin
//     self.is_killed = not self.is_killed


// @external
// def commit_transfer_ownership(addr: address):
//     """
//     @notice Transfer ownership of GaugeController to `addr`
//     @param addr Address to have ownership transferred to
//     """
//     assert msg.sender == self.admin  # dev: admin only
//     self.future_admin = addr
//     log CommitOwnership(addr)


// @external
// def apply_transfer_ownership():
//     """
//     @notice Apply pending ownership transfer
//     """
//     assert msg.sender == self.admin  # dev: admin only
//     _admin: address = self.future_admin
//     assert _admin != ZERO_ADDRESS  # dev: admin not set
//     self.admin = _admin
//     log ApplyOwnership(_admin)