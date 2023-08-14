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

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IOrchestrator} from "src/interfaces/IOrchestrator.sol";
import {IMinter} from "src/interfaces/IMinter.sol";
import {IScoreGauge} from "src/interfaces/IScoreGauge.sol";
import {IGaugeController} from "src/interfaces/IGaugeController.sol";

/// @title ScoreGauge. Modified fork of Curve's LiquidityGauge
/// @author johnnyonline (Puppet Finance) https://github.com/johnnyonline
/// @notice Used to measure scores of Traders and Puppets, according to pre defined metrics with configurable weights, and distributes rewards to them
contract ScoreGaugeV1 is ReentrancyGuard, IScoreGauge {

    using SafeERC20 for IERC20;

    IERC20 public token;
    IMinter public minter;
    IOrchestrator public orchestrator;
    IGaugeController public controller;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    /// @notice Contract constructor
    /// @param _authority The Authority contract instance
    /// @param _minter The Minter contract instance
    /// @param _orchestrator The Orchestrator contract instance
    constructor(Authority _authority, IMinter _minter, IOrchestrator _orchestrator) Auth(address(0), _authority) {
        minter = _minter;
        orchestrator = _orchestrator;

        token = IERC20(IMinter(_minter).token());
        controller = IGaugeController(IMinter(_minter).controller());
    }

    // ============================================================================================
    // View Functions
    // ============================================================================================

    /// @inheritdoc IScoreGauge
    function claimableRewards(uint256 _epoch, address _user, bool _isTrader) external view returns (uint256) {
        EpochInfo storage _epochInfo = epochInfo[_epoch];
        if (_epochInfo.claimed[_isTrader][_user]) return 0;

        uint256 _userProfit;
        uint256 _userCvg;
        if (_isTrader) {
            _userProfit = _epochInfo.puppetScore[_user].profit;
            _userCvg = _epochInfo.puppetScore[_user].cumulativeVolumeGenerated;
        } else {
            _userProfit = _epochInfo.traderScore[_user].profit;
            _userCvg = _epochInfo.traderScore[_user].cumulativeVolumeGenerated;
        }

        uint256 _userScore = ((_userProfit * _epochInfo.profitWeight + _userCvg * _epochInfo.volumeWeight) / 10000) * 1e18 / _epochInfo.totalScore;
        uint256 _userReward = _userScore * _epochInfo.rewards / 1e18;

        return _userReward;
    }

    // ============================================================================================
    // Mutative Functions
    // ============================================================================================

    /// @inheritdoc IScoreGauge
    function claim(uint256 _epoch, bool _isTrader) external nonReentrant {
        if (_epoch >= IGaugeController(controller).epoch()) revert InvalidEpoch();

        EpochInfo storage _epochInfo = epochInfo[_epoch];
        if (_epochInfo.claimed[_isTrader][msg.sender]) revert AlreadyClaimed();

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

        _epochInfo.claimed[_isTrader][msg.sender] = true;

        IERC20(token).safeTransfer(msg.sender, _userReward);

        emit Claim(_epoch, _userReward, msg.sender, _isTrader);
    }

    /// @inheritdoc IScoreGauge
    function updateUserScore(uint256 _volumeGenerated, uint256 _profit, address _user, bool _isTrader) external {
        if (!IOrchestrator(orchestrator).isRoute(msg.sender)) revert NotRoute();

        if (!is_killed) {
            EpochInfo storage _epochInfo = epochInfo[controller.epoch()];
            if (_isTrader) {
                _epochInfo.tradersScore[_user].cumulativeVolumeGenerated += _volumeGenerated;
                _epochInfo.tradersScore[_user].profit += _profit;
            } else {
                _epochInfo.puppetsScore[_user].cumulativeVolumeGenerated += _volumeGenerated;
                _epochInfo.puppetsScore[_user].profit += _profit;
            }

            if (_epochInfo.profitWeight == 0 && _epochInfo.volumeWeight == 0) {
                _epochInfo.profitWeight = IGaugeController(controller).profitWeight();
                _epochInfo.volumeWeight = IGaugeController(controller).volumeWeight();
            }

            uint256 _totalCvg = _epochInfo.totalCumulativeVolumeGenerated + _volumeGenerated;
            uint256 _totalProfit = _epochInfo.totalProfit + _profit;

            _epochInfo.totalCumulativeVolumeGenerated = _totalCvg;
            _epochInfo.totalProfit = _totalProfit;

            _epochInfo.totalScore = (_totalProfit * _epochInfo.profitWeight + _totalCvg * _epochInfo.cvgWeight) / 10000;

            emit UserScoreUpdate(_user, _volumeGenerated, _profit, _isTrader);
        }
    }

    /// @inheritdoc IScoreGauge
    function killMe() external requiresAuth {
        is_killed = !is_killed;
    }
}