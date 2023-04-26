// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IRoute {

    // ============================================================================================
    // Mutated Functions
    // ============================================================================================

    function approvePositionRequest() external;

    function rejectPositionRequest() external;

    function setPuppetOrchestrator(address _puppetOrchestrator) external;

    function approvePlugin() external;

    // ============================================================================================
    // Events
    // ============================================================================================

    event Liquidated();
    event ApprovePositionRequest();
    event RejectPositionRequest();
    event RepayBalance(uint256 _totalAssets);
    event CreateIncreasePosition(bytes32 indexed positionKey, uint256 amountIn, uint256 minOut, uint256 sizeDelta, uint256 acceptablePrice, uint256 executionFee);
    event CreateDecreasePosition(bytes32 indexed positionKey, uint256 minOut, uint256 collateralDeltaUSD, uint256 sizeDelta, uint256 acceptablePrice, uint256 executionFee);

    // ============================================================================================
    // Errors
    // ============================================================================================

    error WaitingForCallback();
    error NotCallbackTarget();
    error NotOwner();
    error KeyError();
    error NotKeeper();
}