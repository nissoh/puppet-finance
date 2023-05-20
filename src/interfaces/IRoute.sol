// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IPositionRouterCallbackReceiver} from "./IPositionRouterCallbackReceiver.sol";

interface IRoute is IPositionRouterCallbackReceiver {

    struct AddCollateralRequest{
        uint256 puppetsAmountIn;
        uint256 traderAmountIn;
        uint256 traderShares;
        uint256 totalSupply;
        uint256 totalAssets;
        uint256[] puppetsShares;
        uint256[] puppetsAmounts;
    }

    // ============================================================================================
    // Mutated Functions
    // ============================================================================================

    // trader

    function createPositionRequest(bytes memory _traderPositionData, bytes memory _traderSwapData, bool _isIncrease) external payable returns (bytes32 _requestKey);

    function createAddCollateralRequestETH(bytes memory _traderPositionData, uint256 _minOut) external payable returns (bytes32 _requestKey);

    // keeper

    function liquidate() external;

    // owner

    function approvePlugin() external;

    function setOrchestrator(address _orchestrator) external;

    function updateGMXInfo() external;

    // ============================================================================================
    // Events
    // ============================================================================================

    // TODO - clean events & errors

    event Liquidated();
    event ApprovePositionRequest();
    event RejectPositionRequest();
    event RepayBalance(uint256 _totalAssets);
    event CreateIncreasePosition(bytes32 indexed positionKey, uint256 amountIn, uint256 minOut, uint256 sizeDelta, uint256 acceptablePrice, uint256 executionFee);
    event CreateDecreasePosition(bytes32 indexed positionKey, uint256 minOut, uint256 collateralDeltaUSD, uint256 sizeDelta, uint256 acceptablePrice, uint256 executionFee);
    event ResetPosition();
    event PluginApproved();
    event OrchestratorSet(address indexed _orchestrator);
    event PuppetsAssetsAndSharesAllocated(uint256 puppetsAmountIn, uint256 totalManagementFee);
    event TraderAssetsAndSharesAllocated(uint256 traderAmountIn, uint256 traderShares);
    event CallbackReceived(bytes32 indexed _requestKey, bool indexed _isExecuted, bool indexed _isIncrease);
    event GMXInfoUpdated();
    event GlobalInfoUpdated();
    event ReferralRebatesSent(address indexed _revenueDistributor, uint256 _balance);
    event RouteReseted();
    event RepaidBalance(uint256 _totalAssets);
    event CreatedDecreasePositionRequest(bytes32 indexed _requestKey, uint256 _minOut, uint256 _collateralDelta, uint256 _sizeDelta, uint256 _acceptablePrice, uint256 _executionFee);
    event CreatedIncreasePositionRequest(bytes32 indexed _requestKey, uint256 _amountIn, uint256 _minOut, uint256 _sizeDelta, uint256 _acceptablePrice, uint256 _executionFee);

    // ============================================================================================
    // Errors
    // ============================================================================================

    error WaitingForCallback();
    error NotCallbackCaller();
    error KeyError();
    error NotKeeper();
    error ZeroAmount();
    error InvalidExecutionFee();
    error PositionStillAlive();
    error NotTrader();
    error InvalidPath();
    error InvalidValue();
    error InvalidMaxAmount();
    error InvalidPathLength();
    error InvalidTokenIn();
    error Paused();
}