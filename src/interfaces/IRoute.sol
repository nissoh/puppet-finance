// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IRoute {

    // ============================================================================================
    // Mutated Functions
    // ============================================================================================

    function createPositionRequest(bytes memory _traderPositionData, uint256 _executionFee, bool _isIncrease) external payable returns (bytes32 _requestKey);

    function onLiquidation() external;

    function approvePositionRequest() external;

    function rejectPositionRequest() external;

    function approvePlugin() external;

    function setOrchestrator(address _orchestrator) external;

    // ============================================================================================
    // Events
    // ============================================================================================

    event Liquidated();
    event ApprovePositionRequest();
    event RejectPositionRequest();
    event RepayBalance(uint256 _totalAssets);
    event CreateIncreasePosition(bytes32 indexed positionKey, uint256 amountIn, uint256 minOut, uint256 sizeDelta, uint256 acceptablePrice, uint256 executionFee);
    event CreateDecreasePosition(bytes32 indexed positionKey, uint256 minOut, uint256 collateralDeltaUSD, uint256 sizeDelta, uint256 acceptablePrice, uint256 executionFee);
    event ResetPosition();

    // ============================================================================================
    // Errors
    // ============================================================================================

    error WaitingForCallback();
    error NotCallbackTarget();
    error NotOwner();
    error KeyError();
    error NotKeeper();
    error ZeroAmount();
    error InvalidExecutionFee();
    error PositionStillAlive();
    error NotTrader();
}