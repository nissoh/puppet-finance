// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ITraderRoute {

    // ====================== Functions ======================

    function isWaitingForCallback() external view returns (bool);

    function isPositionOpen() external view returns (bool);

    function isPuppetSigned(address _puppet) external view returns (bool);

    function signPuppet(address _puppet, uint256 _allowance) external returns (bool);

    function unsignPuppet(address _puppet) external returns (bool);

    function setAllowance(address _puppet, uint256 _allowance) external;

    // ====================== Events ======================

    event CreateIncreasePosition(bytes32 indexed positionKey, uint256 amountIn, uint256 minOut, uint256 sizeDelta, uint256 acceptablePrice, uint256 executionFee);
    event Deposit(address indexed account, uint256 amount, uint256 shares);

    // ====================== Errors ======================

    error InvalidCaller();
    error WaitingForCallback();
    error ZeroAmount();
    error Unauthorized();
    error InvalidAmountIn();
    error PositionIsOpen();
}