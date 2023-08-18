// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ====================== ScoreGaugeV1 ==========================
// ==============================================================

// Modified fork from Curve Finance: https://github.com/curvefi 
// @title Liquidity Gauge
// @author Curve Finance
// @license MIT
// @notice Used for measuring liquidity and insurance

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

    bool private _isKilled;

    address public admin;
    address public future_admin; // can and will be a smart contract

    mapping(uint256 => EpochInfo) public epochInfo; // epoch => EpochInfo

    uint256 internal constant _BASIS_POINTS_DIVISOR = 10_000;
    uint256 internal constant _PRECISION = 1e18;

    IERC20 public token;
    IMinter public minter;
    IOrchestrator public orchestrator;
    IGaugeController public controller;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    /// @notice Contract constructor
    /// @param _admin The admin address
    /// @param _minter The Minter address
    /// @param _orchestrator The Orchestrator address
    constructor(address _admin, address _minter, address _orchestrator) {
        admin = _admin;

        minter = IMinter(_minter);
        orchestrator = IOrchestrator(_orchestrator);

        token = IERC20(IMinter(_minter).token());
        controller = IGaugeController(IMinter(_minter).controller());
    }

    // ============================================================================================
    // Modifiers
    // ============================================================================================

    /// @notice Modifier that ensures the caller is the contract's Admin
    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    // ============================================================================================
    // External Functions
    // ============================================================================================

    /// @inheritdoc IScoreGauge
    function claimableRewards(uint256 _epoch, address _user) external view returns (uint256) {
        return _claimableRewards(_epoch, _user);
    }

    /// @inheritdoc IScoreGauge
    function userPerformance(uint256 _epoch, address _user) external view returns (uint256 _volumeGenerated, uint256 _profit) {
        _volumeGenerated = epochInfo[_epoch].userPerformance[_user].volumeGenerated;
        _profit = epochInfo[_epoch].userPerformance[_user].profit;
    }

    /// @inheritdoc IScoreGauge
    function hasClaimed(uint256 _epoch, address _user) external view returns (bool) {
        return epochInfo[_epoch].claimed[_user];
    }

    /// @inheritdoc IScoreGauge
    function isKilled() external view returns (bool) {
        return _isKilled;
    }

    /// @inheritdoc IScoreGauge
    function depositRewards(uint256 _epoch, uint256 _amount) external nonReentrant {
        if (msg.sender != address(minter)) revert NotMinter();

        epochInfo[_epoch].rewards += _amount;

        emit DepositRewards(_amount);
    }

    /// @inheritdoc IScoreGauge
    function claim(uint256 _epoch, address _receiver) external nonReentrant returns (uint256 _userReward) {
        if (_epoch >= IGaugeController(controller).epoch()) revert InvalidEpoch();

        EpochInfo storage _epochInfo = epochInfo[_epoch];
        if (_epochInfo.claimed[msg.sender]) revert AlreadyClaimed();

        _userReward = _claimableRewards(_epoch, msg.sender);
        if (_userReward == 0) revert NoRewards();

        _epochInfo.claimed[msg.sender] = true;

        IERC20(token).safeTransfer(_receiver, _userReward);

        emit Claim(_epoch, _userReward, msg.sender, _receiver);
    }

    /// @inheritdoc IScoreGauge
    function updateUserScore(uint256 _volumeGenerated, uint256 _profit, address _user) external {
        if (!IOrchestrator(orchestrator).isRoute(msg.sender)) revert NotRoute();

        if (!_isKilled) {
            EpochInfo storage _epochInfo = epochInfo[controller.epoch()];
            _epochInfo.userPerformance[_user].volumeGenerated += _volumeGenerated;
            _epochInfo.userPerformance[_user].profit += _profit;

            if (_epochInfo.profitWeight == 0 && _epochInfo.volumeWeight == 0) {
                IGaugeController _controller = controller;
                _epochInfo.profitWeight = _controller.profitWeight();
                _epochInfo.volumeWeight = _controller.volumeWeight();
                if (_epochInfo.profitWeight == 0 && _epochInfo.volumeWeight == 0) revert InvalidWeights();
            }

            uint256 _totalVolumeGenerated = _epochInfo.totalVolumeGenerated + _volumeGenerated;
            uint256 _totalProfit = _epochInfo.totalProfit + _profit;

            _epochInfo.totalVolumeGenerated = _totalVolumeGenerated;
            _epochInfo.totalProfit = _totalProfit;

            _epochInfo.totalScore = 
                (_totalProfit * _epochInfo.profitWeight + _totalVolumeGenerated * _epochInfo.volumeWeight) 
                / _BASIS_POINTS_DIVISOR;

            emit UserScoreUpdate(_user, _volumeGenerated, _profit);
        }
    }

    /// @inheritdoc IScoreGauge
    function killMe() external onlyAdmin {
        _isKilled = true;
    }

    /// @inheritdoc IScoreGauge
    function commitTransferOwnership(address _futureAdmin) external onlyAdmin {
        future_admin = _futureAdmin;

        emit CommitOwnership(_futureAdmin);
    }

    /// @inheritdoc IScoreGauge
    function applyTransferOwnership() external onlyAdmin {
        address _admin = future_admin;
        require(_admin != address(0), "admin not set");

        admin = _admin;

        emit ApplyOwnership(_admin);
    }

    // ============================================================================================
    // Internal Functions
    // ============================================================================================

    function _claimableRewards(uint256 _epoch, address _user) internal view returns (uint256) {
        EpochInfo storage _epochInfo = epochInfo[_epoch];
        if (_epochInfo.claimed[_user]) return 0;

        uint256 _userProfit = _epochInfo.userPerformance[_user].profit;
        uint256 _userVolumeGenerated = _epochInfo.userPerformance[_user].volumeGenerated;

        uint256 _userScore = ((_userProfit * _epochInfo.profitWeight + _userVolumeGenerated * _epochInfo.volumeWeight) / _BASIS_POINTS_DIVISOR);
        uint256 _userScoreShare = _userScore * _PRECISION / _epochInfo.totalScore;
        uint256 _userReward = _userScoreShare * _epochInfo.rewards / _PRECISION;

        return _userReward;
    }
}