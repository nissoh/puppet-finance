// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IOrchestrator {

    // ============================================================================================
    // View Functions
    // ============================================================================================

    function getRouteKey(address _trader, address _collateralToken, address _indexToken, bool _isLong) external pure returns (bytes32);

    function getPuppetsForRoute(bytes32 _routeKey) external view returns (address[] memory);

    function isPuppetSolvent(address _puppet) external view returns (bool);

    function getRouteForRequestKey(bytes32 _requestKey) external view returns (address);

    function getPuppetAllowance(address _puppet, address _route) external view returns (uint256);

    function getGMXRouter() external view returns (address);

    function getGMXReader() external view returns (address);

    function getGMXVault() external view returns (address);

    function getGMXPositionRouter() external view returns (address);

    function getCallbackTarget() external view returns (address);

    function getReferralCode() external view returns (bytes32);

    function getPositionValidator() external view returns (address);

    function getKeeper() external view returns (address);

    function getPrizePoolDistributor() external view returns (address);

    // ============================================================================================
    // Mutated Functions
    // ============================================================================================

    // Trader

    function registerRoute(address _collateralToken, address _indexToken, bool _isLong) external returns (bytes32);

    // Puppet

    function depositToAccount(uint256 _assets, address _puppet) external payable;

    function withdrawFromAccount(uint256 _assets, address _receiver) external;

    function updateRoutesSubscription(address[] memory _traders, uint256[] memory _allowances, address _collateralToken, address _indexToken, bool _isLong, bool _sign) external;

    // Route

    function debitPuppetAccount(uint256 _amount, address _puppet) external;

    function creditPuppetAccount(uint256 _amount, address _puppet) external;

    function liquidatePuppet(address _puppet, bytes32 _routeKey) external;

    function updateRequestKeyToRoute(bytes32 _requestKey) external;

    function sendFunds(uint256 _amount) external;

    // Owner

    function setGMXUtils(address _gmxRouter, address _gmxReader, address _gmxVault, address _gmxPositionRouter) external;

    function setCallbackTarget(address _callbackTarget) external;

    function setReferralCode(bytes32 _referralCode) external;

    function setSolvencyMargin(uint256 _solvencyMargin) external;

    function setPositionValidator(address _positionValidator) external;

    function setOwner(address _owner) external;

    // ============================================================================================
    // Events
    // ============================================================================================

    event RegisterRoute(address indexed trader, address _route, address indexed collateralToken, address indexed indexToken, bool isLong);
    event DepositToAccount(uint256 assets, address indexed caller, address indexed puppet);
    event WithdrawFromAccount(uint256 assets, address indexed receiver, address indexed puppet);
    event UpdateRoutesSubscription(address[] traders, uint256[] allowances, address indexed puppet, address indexed collateralToken, address indexed indexToken, bool isLong, bool sign);    
    event DebitPuppetAccount(uint256 _amount, address indexed _puppet, address indexed _token);
    event CreditPuppetAccount(uint256 _amount, address indexed _puppet, address indexed _token);
    event LiquidatePuppet(address indexed _puppet, bytes32 indexed _positionKey, address indexed _liquidator);
    event UpdateRequestKeyToRoute(bytes32 indexed _requestKey, address indexed _routeAddress);
    event SendFunds(uint256 _amount, address indexed _sender);

    // ============================================================================================
    // Errors
    // ============================================================================================

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