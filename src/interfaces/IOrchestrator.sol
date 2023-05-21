// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IBase} from "./IBase.sol";

interface IOrchestrator is IBase {

    // ============================================================================================
    // View Functions
    // ============================================================================================

    // global

    function getGlobalInfo() external view returns (bytes32, uint256, address, address);

    function getPriceFeed(address _asset) external view returns (address, uint256);

    function getRoutes() external view returns (address[] memory);

    function getIsPaused() external view returns (bool);

    // route

    function getRouteTypeKey(address _collateralToken, address _indexToken, bool _isLong) external pure returns (bytes32);

    function getRouteKey(address _trader, bytes32 _routeTypeKey) external view returns (bytes32);

    function getRoute(bytes32 _routeKey) external view returns (address);

    function getPuppetsForRoute(bytes32 _routeKey) external view returns (address[] memory);

    // puppet

    function isBelowThrottleLimit(address _route, address _puppet) external view returns (bool);

    function getPuppetAllowancePercentage(address _puppet, address _route) external view returns (uint256);

    function getPuppetAccountBalance(address _asset, address _puppet) external view returns (uint256);

    // gmx

    function getGMXInfo() external view returns (GMXInfo memory);

    // ============================================================================================
    // Mutated Functions
    // ============================================================================================

    // Trader

    function registerRoute(address _collateralToken, address _indexToken, bool _isLong) external returns (bytes32);

    // Puppet

    function depositToAccount(uint256 _amount, address _asset, address _puppet) external payable;

    function withdrawFromAccount(uint256 _amount, address _asset, address _receiver, bool _isETH) external;

    function updateRoutesSubscription(address[] memory _traders, uint256[] memory _allowances, bytes32 _routeTypeKey, bool _sign) external;

    function setThrottleLimit(uint256 _throttleLimit) external;

    // Route

    function debitPuppetAccount(uint256 _amount, address _asset, address _puppet) external;

    function creditPuppetAccount(uint256 _amount, address _asset, address _puppet) external;

    function updateLastPositionOpenedTimestamp(address _route, address _puppet) external;

    function sendFunds(uint256 _amount, address _asset, address _receiver) external;

    // Owner

    function setRouteType(address _collateral, address _index, bool _isLong) external;

    function setGMXUtils(address _gmxRouter, address _gmxReader, address _gmxVault, address _gmxPositionRouter, address _referralRebatesSender) external;

    function setPuppetUtils(address _revenueDistributor, address _keeper, bytes32 _referralCode) external;

    function setPriceFeedsInfo(address[] memory _assets, address[] memory _priceFeeds, uint256[] memory _decimals) external;

    function setPerformanceFeePercentage(uint256 _performanceFeePercentage) external;

    function pause(bool _pause) external;

    // ============================================================================================
    // Events
    // ============================================================================================

    // TODO - clean events & errors

    event RegisterRoute(address indexed trader, address indexed route, bytes32 indexed routeTypeKey);
    event DepositToAccount(uint256 amount, address indexed asset, address indexed caller, address indexed puppet);
    event WithdrawFromAccount(uint256 amount, address indexed asset, address indexed receiver, address indexed puppet);
    event UpdateLastPositionOpenedTimestamp(address indexed _route, address indexed _puppet, uint256 _timestamp);
    event UpdateRoutesSubscription(address[] traders, uint256[] allowances, address indexed puppet, bytes32 indexed routeTypeKey, bool indexed sign);
    event DebitPuppetAccount(uint256 _amount, address indexed _puppet, address indexed _token);
    event CreditPuppetAccount(uint256 _amount, address indexed _puppet, address indexed _token);
    event UpdateRequestKeyToRoute(bytes32 indexed _requestKey, address indexed _routeAddress);
    event SendFunds(uint256 _amount, address indexed _asset, address indexed _receiver);
    event SetThrottleLimit(address indexed puppet, uint256 throttleLimit);
    event SetGMXUtils(address _gmxRouter, address _gmxReader, address _gmxVault, address _gmxPositionRouter, address _referralRebatesSender);
    event SetPuppetUtils(address _revenueDistributor, address _keeper, bytes32 _referralCode);
    event SetPerformanceFeePercentage(uint256 _performanceFeePercentage);
    event Paused(bool indexed _paused);
    event SetPriceFeedsInfo(address[] _assets, address[] _priceFeeds, uint256[] _decimals);
    event RouteTypeSet(bytes32 indexed _routeTypeKey, address indexed _collateral, address indexed _index, bool _isLong);

    // ============================================================================================
    // Errors
    // ============================================================================================

    error RouteAlreadyRegistered();
    error NotRoute();
    error ZeroAmount();
    error InvalidAmount();
    error InsufficientPuppetFunds();
    error MismatchedInputArrays();
    error RouteNotRegistered();
    error WaitingForCallback();
    error PositionIsOpen();
    error InvalidAllowancePercentage();
    error InvalidTokenAddress();
    error InvalidPercentage();
    error InvalidAssetAddress();
    error InvalidAsset();
    error ZeroAmountWETH();
    error NoPriceFeedForCollateralToken();
    error ZeroAddress();
    error RouteTypeNotRegistered();
}