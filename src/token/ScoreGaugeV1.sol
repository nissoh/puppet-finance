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
import "forge-std/Test.sol";
import "forge-std/console.sol";
/// @title ScoreGauge. Modified fork of Curve's LiquidityGauge
/// @author johnnyonline (Puppet Finance) https://github.com/johnnyonline
/// @notice Used to measure scores of Traders and Puppets, according to pre defined metrics with configurable weights, and distributes rewards to them
contract ScoreGaugeV1 is ReentrancyGuard, IScoreGauge, Test {

    using SafeERC20 for IERC20;

    bool private _isKilled;

    address public admin;
    address public futureAdmin; // can and will be a smart contract

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

    // view functions

    /// @inheritdoc IScoreGauge
    function claimableRewards(uint256 _epoch, address _user) external view returns (uint256) {
        return _claimableRewards(_epoch, _user);
    }

    /// @inheritdoc IScoreGauge
    function userPerformance(uint256 _epoch, address _user) external view returns (uint256 _volume, uint256 _profit) {
        EpochInfo storage _epochInfo = epochInfo[_epoch];
        _volume = _epochInfo.userPerformance[_user].volume;
        _profit = _epochInfo.userPerformance[_user].profit;
    }

    /// @inheritdoc IScoreGauge
    function hasClaimed(uint256 _epoch, address _user) external view returns (bool) {
        return epochInfo[_epoch].claimed[_user];
    }

    /// @inheritdoc IScoreGauge
    function isKilled() external view returns (bool) {
        return _isKilled;
    }

    // mutated functions

    /// @inheritdoc IScoreGauge
    function claim(uint256 _epoch, address _receiver) public nonReentrant returns (uint256 _rewards) {
        _rewards = _claim(_epoch, _receiver);

        IERC20(token).safeTransfer(_receiver, _rewards);
    }

    /// @inheritdoc IScoreGauge
    function claimMany(uint256[] calldata _epochs, address _receiver) external nonReentrant returns (uint256 _rewards) {
        for (uint256 i = 0; i < _epochs.length; i++) {
            _rewards += _claim(_epochs[i], _receiver);
        }
        console.log("claimMany: %s", _rewards);
        console.log("balanceOf: %s", IERC20(token).balanceOf(address(this)));
        IERC20(token).safeTransfer(_receiver, _rewards);
    }

    /// @inheritdoc IScoreGauge
    function depositRewards(uint256 _epoch, uint256 _amount) external nonReentrant {
        if (msg.sender != address(minter)) revert NotMinter();

        _updateWeights(_epoch);

        EpochInfo storage _epochInfo = epochInfo[_epoch];
        _epochInfo.profitRewards += _amount * _epochInfo.profitWeight / _BASIS_POINTS_DIVISOR;
        _epochInfo.volumeRewards += _amount * _epochInfo.volumeWeight / _BASIS_POINTS_DIVISOR;
        console.log("depositRewards: %s", _amount);
        console.log("balanceOf: %s", IERC20(token).balanceOf(address(this)));
        console.log("profitRewards: %s", _epochInfo.profitRewards); // todo -- test that
        console.log("volumeRewards: %s", _epochInfo.volumeRewards);


        emit DepositRewards(_amount);
    }

    /// @inheritdoc IScoreGauge
    function updateUserScore(uint256 _volume, uint256 _profit, address _user) external {
        if (!IOrchestrator(orchestrator).isRoute(msg.sender)) revert NotRoute();

        if (!_isKilled) {
            uint256 _epoch = controller.epoch();
            EpochInfo storage _epochInfo = epochInfo[_epoch];

            _epochInfo.userPerformance[_user].volume += _volume;
            _epochInfo.userPerformance[_user].profit += _profit;

            _epochInfo.totalVolume += _volume;
            _epochInfo.totalProfit += _profit;

            _updateWeights(_epoch);

            emit UserScoreUpdate(_user, _volume, _profit);
        }
    }

    /// @inheritdoc IScoreGauge
    function killMe() external onlyAdmin {
        _isKilled = true;
    }

    /// @inheritdoc IScoreGauge
    function commitTransferOwnership(address _futureAdmin) external onlyAdmin {
        futureAdmin = _futureAdmin;

        emit CommitOwnership(_futureAdmin);
    }

    /// @inheritdoc IScoreGauge
    function applyTransferOwnership() external onlyAdmin {
        address _admin = futureAdmin;
        if (_admin == address(0)) revert ZeroAddress();

        admin = _admin;

        emit ApplyOwnership(_admin);
    }

    // ============================================================================================
    // Internal Functions
    // ============================================================================================

    function _claimableRewards(uint256 _epoch, address _user) internal view returns (uint256) {
        EpochInfo storage _epochInfo = epochInfo[_epoch];
        if (_epochInfo.claimed[_user]) return 0;

        console.log("epochInfo[_epoch].totalProfit", _epochInfo.totalProfit);
        console.log("epochInfo[_epoch].totalVolume", _epochInfo.totalVolume);
        console.log("_epochInfo.userPerformance[_user].profit", _epochInfo.userPerformance[_user].profit);
        console.log("_epochInfo.userPerformance[_user].volume", _epochInfo.userPerformance[_user].volume);
        console.log("_userProfitRewards: ", _epochInfo.userPerformance[_user].profit * _PRECISION / _epochInfo.totalProfit);
        console.log("_userVolumeRewards: ", _epochInfo.userPerformance[_user].volume * _PRECISION / _epochInfo.totalVolume);

        uint256 _profitShare = _epochInfo.userPerformance[_user].profit * _PRECISION / _epochInfo.totalProfit;
        uint256 _volumeShare = _epochInfo.userPerformance[_user].volume * _PRECISION / _epochInfo.totalVolume;

        uint256 _userProfitRewards = _profitShare * _epochInfo.profitRewards / _PRECISION;
        uint256 _userVolumeRewards = _volumeShare * _epochInfo.volumeRewards / _PRECISION;
        console.log("totalRewards: ", _userProfitRewards + _userVolumeRewards);
        return _userProfitRewards + _userVolumeRewards;
    }

    function _claim(uint256 _epoch, address _receiver) internal returns (uint256 _rewards) {
        if (_epoch >= IGaugeController(controller).epoch()) revert InvalidEpoch();

        EpochInfo storage _epochInfo = epochInfo[_epoch];
        if (_epochInfo.claimed[msg.sender]) revert AlreadyClaimed();

        _rewards = _claimableRewards(_epoch, msg.sender);
        if (_rewards == 0) revert NoRewards();

        _epochInfo.claimed[msg.sender] = true;

        emit Claim(_epoch, _rewards, msg.sender, _receiver);
    }

    function _updateWeights(uint256 _epoch) internal {
        EpochInfo storage _epochInfo = epochInfo[_epoch];
        if (_epochInfo.profitWeight == 0 && _epochInfo.volumeWeight == 0) {
            IGaugeController _controller = controller;
            _epochInfo.profitWeight = _controller.profitWeight();
            _epochInfo.volumeWeight = _controller.volumeWeight();
            if (_epochInfo.profitWeight == 0 && _epochInfo.volumeWeight == 0) revert InvalidWeights();
        }
    }
}