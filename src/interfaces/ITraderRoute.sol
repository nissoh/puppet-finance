// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ITraderRoute {

    // ====================== Functions ======================

    function isWaitingForCallback() external view returns (bool);

    function isPositionOpen() external view returns (bool);

    function isPuppetSigned(address _puppet) external view returns (bool);

    function signPuppet(address _puppet, uint256 _allowance) external;

    function unsignPuppet(address _puppet) external;

    function setAllowance(address _puppet, uint256 _allowance) external;

    function approveIncreasePosition() external;

    function rejectIncreasePosition() external;

    function approveDecreasePosition() external;

    function rejectDecreasePosition() external;

    // ====================== Events ======================

    event NotifyCallback(bool isIncrease);
    event Liquidated();
    event ApprovePositionRequest();
    event RejectPositionRequest();
    event CreateIncreasePosition(bytes32 indexed positionKey, uint256 amountIn, uint256 minOut, uint256 sizeDelta, uint256 acceptablePrice, uint256 executionFee);
    event CreateDecreasePosition(bytes32 indexed positionKey, uint256 minOut, uint256 collateralDeltaUSD, uint256 sizeDelta, uint256 acceptablePrice, uint256 executionFee);

    // ====================== Errors ======================

    error NotCallbackTarget();
    error NotOwner();
    error WaitingForCallback();
    error NotTrader();
    error NotPuppetRoute();
    error NotKeeper();
    error PositionStillAlive();
    error KeyError();
}