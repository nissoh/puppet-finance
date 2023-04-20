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

    event CreateIncreasePosition(bytes32 indexed positionKey, uint256 amountIn, uint256 minOut, uint256 sizeDelta, uint256 acceptablePrice, uint256 executionFee);
    event CreateDecreasePosition(bytes32 indexed positionKey, uint256 minOut, uint256 collateralDeltaUSD, uint256 sizeDelta, uint256 acceptablePrice, uint256 executionFee);
    event Deposit(address indexed account, uint256 amount, uint256 shares);
    event ApproveIncreasePosition();
    event ApproveDecreasePosition();
    event RejectIncreasePosition(uint256 totalPuppetsCredit, uint256 TraderCredit);
    event RejectDecreasePosition(uint256 totalPuppetsCredit, uint256 TraderCredit);

    // ====================== Errors ======================

    error InvalidCaller();
    error WaitingForCallback();
    error ZeroAmount();
    error Unauthorized();
    error InvalidAmountIn();
    error PositionIsOpen();
    error NotCallbackTarget();
    error RouteNotRegistered();
    error KeyError();
    error PuppetAlreadySigned();
    error PuppetNotSigned();
    error InvalidCollateralToken();
    error InvalidValue();
}