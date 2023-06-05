// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IOrchestrator {

    struct RouteType {
        address collateralToken;
        address indexToken;
        bool isLong;
        bool isRegistered;
    }

    struct GMXInfo {
        address gmxRouter;
        address gmxVault;
        address gmxPositionRouter;
        address gmxReferralRebatesSender;
    }

    // ============================================================================================
    // View Functions
    // ============================================================================================

    // global

    function keeper() external view returns (address);

    function referralCode() external view returns (bytes32);

    function routes() external view returns (address[] memory);

    function paused() external view returns (bool);

    // route

    function getRoute(bytes32 _routeKey) external view returns (address);

    function getRoute(address _trader, address _collateralToken, address _indexToken, bool _isLong) external view returns (address);

    function getRouteTypeKey(address _collateralToken, address _indexToken, bool _isLong) external pure returns (bytes32);

    function getRouteKey(address _trader, bytes32 _routeTypeKey) external view returns (bytes32);

    function subscribedPuppets(bytes32 _routeKey) external view returns (address[] memory _puppets);

    // puppet

    function puppetAllowancePercentage(address _puppet, address _route) external view returns (uint256 _allowance);

    function puppetAccountBalance(address _puppet, address _asset) external view returns (uint256);

    function puppetThrottleLimit(address _puppet, bytes32 _routeType) external view returns (uint256);

    function lastPositionOpenedTimestamp(address _puppet, bytes32 _routeType) external view returns (uint256);

    function isBelowThrottleLimit(address _puppet, bytes32 _routeType) external view returns (bool);

    // gmx

    function gmxRouter() external view returns (address);

    function gmxPositionRouter() external view returns (address);

    function gmxVault() external view returns (address);

    // ============================================================================================
    // Mutated Functions
    // ============================================================================================

    // Trader

    function registerRoute(address _collateralToken, address _indexToken, bool _isLong) external returns (bytes32);

    function registerRouteAndCreateIncreasePositionRequest(bytes memory _traderPositionData, bytes memory _traderSwapData, uint256 _executionFee, address _collateralToken, address _indexToken, bool _isLong) external payable returns (bytes32 _routeKey, bytes32 _requestKey);

    // Puppet

    function deposit(uint256 _amount, address _asset, address _puppet) external payable;

    function withdraw(uint256 _amount, address _asset, address _receiver, bool _isETH) external;

    function updateRoutesSubscription(address[] memory _traders, uint256[] memory _allowances, bytes32 _routeTypeKey, bool _subscribe) external;

    function setThrottleLimit(uint256 _throttleLimit, bytes32 _routeType) external;

    // Route

    function debitPuppetAccount(uint256 _amount, address _asset, address _puppet) external;

    function creditPuppetAccount(uint256 _amount, address _asset, address _puppet) external;

    function updateLastPositionOpenedTimestamp(address _puppet, bytes32 _routeType) external;

    function sendFunds(uint256 _amount, address _asset, address _receiver) external;

    // Authority

    function rescueTokens(uint256 _amount, address _token, address _receiver) external;

    function rescueRouteTokens(uint256 _amount, address _token, address _receiver, address _route) external;

    function routeCreatePositionRequest(bytes memory _traderPositionData, bytes memory _traderSwapData, uint256 _executionFee, address _route, bool _isIncrease) external payable returns (bytes32 _requestKey);

    function freezeRoute(address _route, bool _freeze) external;
    
    function setRouteType(address _collateral, address _index, bool _isLong) external;

    function setGMXInfo(address _gmxRouter, address _gmxVault, address _gmxPositionRouter) external;

    function setKeeper(address _keeperAddr) external;

    function setReferralCode(bytes32 _refCode) external;

    function pause(bool _pause) external;

    // ============================================================================================
    // Events
    // ============================================================================================

    event RouteRegistered(address indexed _trader, address indexed _route, bytes32 indexed _routeTypeKey);
    event Deposited(uint256 indexed _amount, address indexed _asset, address _caller, address indexed _puppet);
    event Withdrawn(uint256 _amount, address indexed _asset, address indexed _receiver, address indexed _puppet);
    event RoutesSubscriptionUpdated(address[] _traders, uint256[] _allowances, address indexed _puppet, bytes32 indexed _routeTypeKey, bool indexed _subscribe);
    event ThrottleLimitSet(address indexed _puppet, bytes32 indexed _routeType, uint256 _throttleLimit);
    event PuppetAccountDebited(uint256 _amount, address indexed _asset, address indexed _puppet, address indexed _caller);
    event PuppetAccountCredited(uint256 _amount, address indexed _asset, address indexed _puppet, address indexed _caller);
    event LastPositionOpenedTimestampUpdated(address indexed _puppet, bytes32 indexed _routeType, uint256 _timestamp);
    event FundsSent(uint256 _amount, address indexed _asset, address indexed _receiver, address indexed _caller);
    event RouteTypeSet(bytes32 _routeTypeKey, address _collateral, address _index, bool _isLong);
    event GMXUtilsSet(address _gmxRouter, address _gmxVault, address _gmxPositionRouter);
    event Paused(bool _paused);
    event ReferralCodeSet(bytes32 indexed _referralCode);
    event KeeperSet(address indexed _keeper);
    event PositionRequestCreated(bytes32 indexed _requestKey, address indexed _route, bool indexed _isIncrease);
    event RouteTokensRescued(uint256 _amount, address indexed _token, address indexed _receiver, address indexed _route);
    event TokensRescued(uint256 _amount, address indexed _token, address indexed _receiver);
    event RouteFrozen(address indexed _route, bool indexed _freeze);

    // ============================================================================================
    // Errors
    // ============================================================================================

    error NotRoute();
    error RouteTypeNotRegistered();
    error RouteAlreadyRegistered();
    error MismatchedInputArrays();
    error RouteNotRegistered();
    error InvalidAllowancePercentage();
    error ZeroAddress();
    error InvalidAmount();
    error InvalidAsset();
    error ZeroBytes32();
    error RouteWaitingForCallback();
}