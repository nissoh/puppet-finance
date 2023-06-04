// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IBase} from "./IBase.sol";

interface IOrchestrator is IBase {

    struct RouteType {
        address collateralToken;
        address indexToken;
        bool isLong;
        bool isRegistered;
    }

    // ============================================================================================
    // View Functions
    // ============================================================================================

    // global

    function getGlobalInfo() external view returns (bytes32, address, address);

    function getRoutes() external view returns (address[] memory);

    function getIsPaused() external view returns (bool);

    // route

    function getRoute(address _trader, address _collateralToken, address _indexToken, bool _isLong) external view returns (address);

    function getRouteTypeKey(address _collateralToken, address _indexToken, bool _isLong) external pure returns (bytes32);

    function getRouteKey(address _trader, bytes32 _routeTypeKey) external view returns (bytes32);

    function getRoute(bytes32 _routeKey) external view returns (address);

    function getPuppetsForRoute(bytes32 _routeKey) external view returns (address[] memory);

    // puppet

    function isBelowThrottleLimit(address _puppet, address _route) external view returns (bool);

    function getPuppetAllowancePercentage(address _puppet, address _route) external view returns (uint256);

    function getPuppetAccountBalance(address _puppet, address _asset) external view returns (uint256);

    // gmx

    function getGMXInfo() external view returns (GMXInfo memory);

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

    function setThrottleLimit(uint256 _throttleLimit, address _route) external;

    // Route

    function debitPuppetAccount(uint256 _amount, address _asset, address _puppet) external;

    function creditPuppetAccount(uint256 _amount, address _asset, address _puppet) external;

    function updateLastPositionOpenedTimestamp(address _puppet, address _route) external;

    function sendFunds(uint256 _amount, address _asset, address _receiver) external;

    // Owner

    function setRouteType(address _collateral, address _index, bool _isLong) external;

    function setGMXUtils(address _gmxRouter, address _gmxReader, address _gmxVault, address _gmxPositionRouter, address _referralRebatesSender) external;

    function setPuppetUtils(address _revenueDistributor, address _keeper, bytes32 _referralCode) external;

    function pause(bool _pause) external;

    // ============================================================================================
    // Events
    // ============================================================================================

    event RouteRegistered(address indexed _trader, address indexed _route, bytes32 indexed _routeTypeKey);
    event Deposited(uint256 indexed _amount, address indexed _asset, address _caller, address indexed _puppet);
    event Withdrawn(uint256 _amount, address indexed _asset, address indexed _receiver, address indexed _puppet);
    event RoutesSubscriptionUpdated(address[] _traders, uint256[] _allowances, address indexed _puppet, bytes32 indexed _routeTypeKey, bool indexed _subscribe);
    event ThrottleLimitSet(address indexed _puppet, address indexed _route, uint256 _throttleLimit);
    event PuppetAccountDebited(uint256 _amount, address indexed _asset, address indexed _puppet, address indexed _caller);
    event PuppetAccountCredited(uint256 _amount, address indexed _asset, address indexed _puppet, address indexed _caller);
    event LastPositionOpenedTimestampUpdated(address indexed _puppet, address indexed _route, uint256 _timestamp);
    event FundsSent(uint256 _amount, address indexed _asset, address indexed _receiver, address indexed _caller);
    event RouteTypeSet(bytes32 _routeTypeKey, address _collateral, address _index, bool _isLong);
    event GMXUtilsSet(address _gmxRouter, address _gmxReader, address _gmxVault, address _gmxPositionRouter, address _referralRebatesSender);
    event PuppetUtilsSet(address _revenueDistributor, address _keeper, bytes32 _referralCode);
    event Paused(bool _paused);

    // ============================================================================================
    // Errors
    // ============================================================================================

    error NotRoute();
    error RouteTypeNotRegistered();
    error RouteAlreadyRegistered();
    error MismatchedInputArrays();
    error RouteNotRegistered();
    error PositionIsOpen();
    error InvalidAllowancePercentage();
    error InvalidPercentage();
    error ZeroAddress();
    error InvalidAmount();
    error InvalidAsset();
}