// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ========================= ScoreGaugeV1 ==============================
// ==============================================================
// Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

import {IScoreGauge} from "src/interfaces/IScoreGauge.sol";
import {IGaugeController} from "src/interfaces/IGaugeController.sol";

/// @title ScoreGauge. Modified fork of Curve's LiquidityGauge
/// @author johnnyonline (Puppet Finance) https://github.com/johnnyonline
/// @notice Used to measure scores of Traders and Puppets, according to pre defined metrics with configurable weights, and distributes rewards to them
contract ScoreGaugeV1 is IScoreGauge {

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

    uint256 public contractCreationTimestamp;

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

        address _token = IMinter(_minter).token();
        address _controller = IMinter(_minter).controller();

        token = _token;
        controller = _controller;
        voting_escrow = IGaugeController(_controller).voting_escrow();
        contractCreationTimestamp = block.timestamp;
    }

    // ============================================================================================
    // View Functions
    // ============================================================================================

    // function integrate_checkpoint() external view returns (uint256) {
    //     return period_timestamp[period];
    // }

    // ============================================================================================
    // Mutative Functions
    // ============================================================================================

    // external

    // todo
    function claim(uint256 _epoch, bool _isTrader) external {
        if (_epoch >= IGaugeController(controller).epoch()) revert("Cannot claim for ongoing or future epoch");

        EpochInfo storage _epochInfo = epochInfo[_epoch];
        if (_epochInfo.claimed[_isTrader][msg.sender]) revert("Already claimed for this epoch");

        uint256 _userProfit;
        uint256 _userCvg;
        if (_isTrader) {
            _userProfit = _epochInfo.puppetScore[msg.sender].profit;
            _userCvg = _epochInfo.puppetScore[msg.sender].cumulativeVolumeGenerated;
        } else {
            _userProfit = _epochInfo.traderScore[msg.sender].profit;
            _userCvg = _epochInfo.traderScore[msg.sender].cumulativeVolumeGenerated;
        }

        uint256 _userScore = ((_userProfit * _epochInfo.profitWeight + _userCvg * _epochInfo.volumeWeight) / 10000) * 1e18 / _epochInfo.totalScore;
        uint256 _userReward = _userScore * _epochInfo.rewards / 1e18;

        _epochInfo.rewards -= _userReward;

        _epochInfo.claimed[_isTrader][msg.sender] = true;

        IERC20(token).safeTransfer(msg.sender, _userReward);

        emit Claim(_epoch, _isTrader, msg.sender, _userReward);
    }

    /// @inheritdoc IScoreGauge
    function updateUserScore(uint256 _volumeGenerated, uint256 _profit, address _user, bool _isTrader) external {
        if (!orchestrator.isRoute(msg.sender)) revert NotRoute();

        EpochInfo storage _epochInfo = epochInfo[controller.epoch()];
        if (_isTrader) {
            _epochInfo.tradersScore[_user].cumulativeVolumeGenerated += _volumeGenerated;
            _epochInfo.tradersScore[_user].profit += _profit;
        } else {
            _epochInfo.puppetsScore[_user].cumulativeVolumeGenerated += _volumeGenerated;
            _epochInfo.puppetsScore[_user].profit += _profit;
        }

        uint256 _totalCvg = _epochInfo.totalCumulativeVolumeGenerated + _volumeGenerated;
        uint256 _totalProfit = _epochInfo.totalProfit + _profit;

        _epochInfo.totalCumulativeVolumeGenerated = _totalCvg;
        _epochInfo.totalProfit = _totalProfit;

        _epochInfo.totalScore = (_totalProfit * _epochInfo.profitWeight + _totalCvg * _epochInfo.cvgWeight) / 10000;

        emit UserScoreUpdate(_user, _volumeGenerated, _profit, _isTrader);
    }

    function kill_me() external {
        if (msg.sender != admin) revert("unauthorized");
        is_killed = !is_killed;
    }

    /// @notice Transfer ownership of GaugeController to `_addr`
    /// @param _addr Address to have ownership transferred to
    function commit_transfer_ownership(address _addr) external {
        if (msg.sender != admin) revert("unauthorized");
        future_admin = _addr;
        emit CommitOwnership(_addr);
    }

    /// @notice Apply pending ownership transfer
    function apply_transfer_ownership() external {
        if (msg.sender != admin) revert("unauthorized");
        address _admin = future_admin;
        if (_admin == address(0)) revert("admin not set");
        admin = _admin;
        emit ApplyOwnership(_admin);
    }
}