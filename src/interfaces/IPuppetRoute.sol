// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IPuppetRoute {

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

    event PositionCreated(bool _isIncrease);
    event PositionClosed();
    event Liquidated();
    event PositionApproved(bool _isIncrease);
    event PositionRejected(bool _isIncrease);
    event CreateIncreasePosition(bytes32 indexed positionKey, uint256 amountIn, uint256 minOut, uint256 sizeDelta, uint256 acceptablePrice, uint256 executionFee);
    event CreateDecreasePosition(bytes32 indexed positionKey, uint256 minOut, uint256 collateralDeltaUSD, uint256 sizeDelta, uint256 acceptablePrice, uint256 executionFee);
    event FeesCollected(uint256 _requiredAssets);
    event FeesAndCollateralCollected(uint256 _requiredAssets);
    event RepayBalance(uint256 _totalAssets);
    event ResetPosition();

    // ====================== Errors ======================

    error WaitingForCallback();
    error PositionStillAlive();
    error NotKeeper();
    error NotTraderRoute();
    error NotCallbackTarget();
    error KeyError();
    error ZeroAmount();
    error NotOwner();
}