// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IPuppetOrchestrator {

    // ====================== Functions ======================

    function getGMXRouter() external view returns (address);

    function getGMXReader() external view returns (address);

    function getGMXVault() external view returns (address);

    function getGMXPositionRouter() external view returns (address);

    function isPuppetSolvent(uint256 _amount, address _token, address _puppet) external view returns (bool);

    function getReferralCode() external view returns (bytes32);

    function getCallbackTarget() external view returns (address);

    function getTraderRouteForPosition(bytes32 _gmxPositionKey) external view returns (address);

    function updateGMXPositionKeyToTraderRouteAddress(bytes32 _gmxPositionKey) external; 

    function debitPuppetAccount(uint256 _amount, address _puppet, address _token) external;

    function creditPuppetAccount(uint256 _amount, address _puppet, address _token) external;

    // ====================== Events ======================

    event RegisterRoute(address indexed trader, address _traderRoute, address _puppetRoute, address indexed collateralToken, address indexed indexToken, bool isLong);
    event DepositToAccount(uint256 assets, address indexed caller, address indexed puppet);
    event WithdrawFromAccount(uint256 assets, address indexed receiver, address indexed puppet);
    event ToggleRouteSubscription(address[] traders, uint256[] allowances, address indexed puppet, address indexed collateralToken, address indexed indexToken, bool isLong, bool sign);    
    event DebitPuppetAccount(uint256 _amount, address indexed _puppet, address indexed _token);
    event CreditPuppetAccount(uint256 _amount, address indexed _puppet, address indexed _token);
    event LiquidatePuppet(address indexed _puppet, bytes32 indexed _positionKey, address indexed _liquidator);
    event UpdatePositionKeyToRouteAddress(bytes32 indexed _positionKey, address indexed _routeAddress);
    event SendFunds(uint256 _amount, address indexed _sender);

    // ====================== Errors ======================

    error RouteAlreadyRegistered();
    error NotOwner();
    error NotRoute();
    error ZeroAmount();
    error InvalidAmount();
    error InsufficientPuppetFunds();
    error MismatchedInputArrays();
    error RouteNotRegistered();
    error WaitingForCallback();
    error PositionIsOpen();
}