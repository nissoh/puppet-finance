// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IPuppetOrchestrator {

    // ====================== Functions ======================

    function getGMXRouter() external view returns (address);

    function getGMXPositionRouter() external view returns (address);

    function isPuppetSolvent(uint256 _amount, address _puppet) external view returns (bool);

    function getReferralCode() external view returns (bytes32);

    function getCallbackTarget() external view returns (address);

    function debitPuppetAccount(address _puppet, address _token, uint256 _amount) external;

    // ====================== Events ======================

    event RegisterRoute(address indexed trader, address _routeAddress, address indexed collateralToken, address indexed indexToken, bool isLong);
    event DepositToAccount(uint256 amount, address indexed token, address indexed caller, address indexed puppet);
    event PuppetToggleSubscription(address[] traders, uint256[] allowances, address indexed puppet, address indexed collateralToken, address indexed indexToken, bool isLong, bool sign);
    event PuppetSetAllowance(bytes32[] _routeKeys, uint256[] _allowances, address indexed _puppet);

    // ====================== Errors ======================

    error RouteAlreadyRegistered();
    error PuppetAlreadySigned();
    error PuppetNotSigned();
    error WaitingForCallback();
    error PositionOpen();
    error RouteNotRegistered();
}