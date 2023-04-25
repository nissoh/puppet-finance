// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IPuppetOrchestrator {

    // ====================== Functions ======================

    function registerRoute(address _collateralToken, address _indexToken, bool _isLong) external returns (bytes32);

    function depositToAccount(uint256 _assets, address _puppet) external payable;

    function withdrawFromAccount(uint256 _assets, address _receiver) external;

    function toggleRouteSubscription(address[] memory _traders, uint256[] memory _allowances, address _collateralToken, address _indexToken, bool _isLong, bool _sign) external;

    function debitPuppetAccount(uint256 _amount, address _puppet) external;

    function creditPuppetAccount(uint256 _amount, address _puppet) external;

    function liquidatePuppet(address _puppet, bytes32 _positionKey) external;

    function updatePositionKeyToRouteAddress(bytes32 _positionKey) external;

    function sendFunds(uint256 _amount) external;

    function setGMXUtils(address _gmxRouter, address _gmxReader, address _gmxVault, address _gmxPositionRouter) external;

    function setCallbackTarget(address _callbackTarget) external;

    function setReferralCode(bytes32 _referralCode) external;

    function setSolvencyMargin(uint256 _solvencyMargin) external;

    function setPositionValidator(address _positionValidator) external;

    function setOwner(address _owner) external;

    function getTraderAccountKey(address _account, address _collateralToken, address _indexToken, bool _isLong) external pure returns (bytes32);

    function getGMXRouter() external view returns (address);

    function getGMXReader() external view returns (address);

    function getGMXVault() external view returns (address);

    function getGMXPositionRouter() external view returns (address);

    function getCallbackTarget() external view returns (address);

    function getReferralCode() external view returns (bytes32);

    function getPositionValidator() external view returns (address);

    function getKeeper() external view returns (address);

    function getRouteForPositionKey(bytes32 _positionKey) external view returns (address);

    function getPuppetAllowance(address _puppet, address _route) external view returns (uint256);

    function getPuppetsForRoute(bytes32 _key) external view returns (address[] memory);

    function isPuppetSolvent(address _puppet) external view returns (bool);

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