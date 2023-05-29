// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import {IRoute} from "./interfaces/IRoute.sol";
import {IRouteFactory} from "./interfaces/IRouteFactory.sol";

import "./Base.sol";

contract Orchestrator is Base, IOrchestrator {

    using SafeERC20 for IERC20;
    using Address for address payable;

    struct RouteInfo {
        address route;
        bool isRegistered;
        EnumerableSet.AddressSet puppets;
        RouteType routeType;
    }

    address public routeFactory;

    // routes info
    address[] private routes;

    mapping(address => bool) public isRoute; // Route => isRoute
    mapping(address => mapping(address => uint256)) public lastPositionOpenedTimestamp; // Route => puppet => timestamp
    mapping(bytes32 => RouteType) public routeType; // routeTypeKey => RouteType
    mapping(bytes32 => RouteInfo) private routeInfo; // routeKey => RouteInfo

    // puppets info
    mapping(address => uint256) public throttleLimits; // puppet => throttle limit (in seconds)
    mapping(address => mapping(address => uint256)) public puppetDepositAccount; // puppet => collateralToken => balance
    mapping(address => EnumerableMap.AddressToUintMap) private puppetAllowances; // puppet => Route => allowance percentage

    // settings
    bool public paused; // used to pause all routes on update of gmx/global utils
    mapping(address => PriceFeedInfo) public priceFeeds; // collateralToken => PriceFeedInfo

    // ============================================================================================
    // Constructor
    // ============================================================================================

    constructor(Authority _authority, address _revenueDistributor, address _routeFactory, address _keeper, bytes32 _referralCode, GMXInfo memory _gmxInfo) Auth(address(0), _authority) {
        revenueDistributor = _revenueDistributor;
        routeFactory = _routeFactory;
        keeper = _keeper;

        gmxInfo = _gmxInfo;

        referralCode = _referralCode;
    }

    // ============================================================================================
    // Modifiers
    // ============================================================================================

    modifier onlyRoute() {
        if (msg.sender != owner && !isRoute[msg.sender]) revert NotRoute();
        _;
    }

    // ============================================================================================
    // View Functions
    // ============================================================================================

    // global

    function getGlobalInfo() external view returns (bytes32, address, address) {
        return (referralCode, keeper, revenueDistributor);
    }

    function getPriceFeed(address _asset) external view returns (address, uint256) {
        return (address(priceFeeds[_asset].priceFeed), priceFeeds[_asset].decimals);
    }

    function getRoutes() external view returns (address[] memory) {
        return routes;
    }

    function getIsPaused() external view returns (bool) {
        return paused;
    }

    // route

    function getRouteTypeKey(address _collateralToken, address _indexToken, bool _isLong) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_collateralToken, _indexToken, _isLong));
    }

    function getRouteKey(address _trader, bytes32 _routeTypeKey) public view returns (bytes32) {
        address _collateralToken = routeType[_routeTypeKey].collateralToken;
        address _indexToken = routeType[_routeTypeKey].indexToken;
        bool _isLong = routeType[_routeTypeKey].isLong;

        return keccak256(abi.encodePacked(_trader, _collateralToken, _indexToken, _isLong));
    }

    function getRoute(bytes32 _routeKey) external view returns (address) {
        return routeInfo[_routeKey].route;
    }

    function getPuppetsForRoute(bytes32 _routeKey) external view returns (address[] memory _puppets) {
        EnumerableSet.AddressSet storage _puppetsSet = routeInfo[_routeKey].puppets;
        _puppets = new address[](EnumerableSet.length(_puppetsSet));

        for (uint256 i = 0; i < EnumerableSet.length(_puppetsSet); i++) {
            _puppets[i] = EnumerableSet.at(_puppetsSet, i);
        }
    }

    // puppet

    function isBelowThrottleLimit(address _route, address _puppet) public view returns (bool) {
        return (block.timestamp - lastPositionOpenedTimestamp[_route][_puppet]) >= throttleLimits[_puppet];
    }

    function getPuppetAllowancePercentage(address _puppet, address _route) external view returns (uint256 _allowance) {
        return EnumerableMap.get(puppetAllowances[_puppet], _route);
    }

    function getPuppetAccountBalance(address _asset, address _puppet) external view returns (uint256) {
        return puppetDepositAccount[_asset][_puppet];
    }

    // gmx

    function getGMXInfo() external view returns (GMXInfo memory) {
        return gmxInfo;
    }

    // ============================================================================================
    // Trader Function
    // ============================================================================================

    /// @dev violates checks-effects-interactions pattern. we use reentrancy guard
    // slither-disable-next-line reentrancy-no-eth
    function registerRoute(address _collateralToken, address _indexToken, bool _isLong) external nonReentrant returns (bytes32 _routeKey) {
        if (_collateralToken == address(0) || _indexToken == address(0)) revert ZeroAddress();

        bytes32 _routeTypeKey = getRouteTypeKey(_collateralToken, _indexToken, _isLong);
        if (!routeType[_routeTypeKey].isRegistered) revert RouteTypeNotRegistered();

        address _trader = msg.sender;
        _routeKey = getRouteKey(_trader, _routeTypeKey);
        if (routeInfo[_routeKey].isRegistered) revert RouteAlreadyRegistered();

        address _route = IRouteFactory(routeFactory).createRoute(authority, address(this), _trader, _collateralToken, _indexToken, _isLong);

        RouteType memory _routeType;

        _routeType.collateralToken = _collateralToken;
        _routeType.indexToken = _indexToken;
        _routeType.isLong = _isLong;

        RouteInfo storage _routeInfo = routeInfo[_routeKey];
        
        _routeInfo.route = _route;
        _routeInfo.isRegistered = true;
        _routeInfo.routeType = _routeType;

        isRoute[_route] = true;
        routes.push(_route);

        emit RouteRegistered(_trader, _route, _routeTypeKey);
    }

    // ============================================================================================
    // Puppet Functions
    // ============================================================================================

    function deposit(uint256 _amount, address _asset, address _puppet) external payable nonReentrant {
        if (address(priceFeeds[_asset].priceFeed) == address(0)) revert NoPriceFeedForCollateralToken();
        if (_amount == 0) revert ZeroAmount();
        if (_puppet == address(0)) revert ZeroAddress();
        if (msg.value > 0) {
            if (_amount != msg.value) revert InvalidAmount();
            if (_asset != WETH) revert InvalidAsset();
        }

        puppetDepositAccount[_asset][_puppet] += _amount;

        if (msg.value > 0) {
            payable(_asset).functionCallWithValue(abi.encodeWithSignature("deposit()"), _amount);
        } else {
            IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);
        }

        emit Deposited(_amount, _asset, msg.sender, _puppet);
    }

    function withdraw(uint256 _amount, address _asset, address _receiver, bool _isETH) external nonReentrant {
        if (address(priceFeeds[_asset].priceFeed) == address(0)) revert NoPriceFeedForCollateralToken();
        if (_amount == 0) revert ZeroAmount();
        if (_receiver == address(0)) revert ZeroAddress();
        if (_isETH && _asset != WETH) revert InvalidAsset();
 
        puppetDepositAccount[_asset][msg.sender] -= _amount;

        if (_isETH) {
            IWETH(_asset).withdraw(_amount);
            payable(_receiver).sendValue(_amount);
        } else {
            IERC20(_asset).safeTransfer(_receiver, _amount);
        }

        emit Withdrawn(_amount, _asset, _receiver, msg.sender);
    }

    function updateRoutesSubscription(address[] memory _traders, uint256[] memory _allowances, bytes32 _routeTypeKey, bool _subscribe) external nonReentrant {
        if (_traders.length != _allowances.length) revert MismatchedInputArrays();

        address _puppet = msg.sender;
        for (uint256 i = 0; i < _traders.length; i++) {
            bytes32 _routeKey = getRouteKey(_traders[i], _routeTypeKey);
            RouteInfo storage _routeInfo = routeInfo[_routeKey];

            if (!_routeInfo.isRegistered) revert RouteNotRegistered();

            if (_subscribe) {
                if (_allowances[i] > 100 || _allowances[i] == 0) revert InvalidAllowancePercentage();

                EnumerableMap.set(puppetAllowances[_puppet], _routeInfo.route, _allowances[i]);

                if (!EnumerableSet.contains(_routeInfo.puppets, _puppet)) {
                    EnumerableSet.add(_routeInfo.puppets, _puppet);
                }
            } else {
                EnumerableMap.set(puppetAllowances[_puppet], _routeInfo.route, 0);

                if (EnumerableSet.contains(_routeInfo.puppets, _puppet)) {
                    EnumerableSet.remove(_routeInfo.puppets, _puppet);
                }
            }
        }

        emit RoutesSubscriptionUpdated(_traders, _allowances, _puppet, _routeTypeKey, _subscribe);
    }

    function setThrottleLimit(uint256 _throttleLimit) external {
        throttleLimits[msg.sender] = _throttleLimit;

        emit ThrottleLimitSet(msg.sender, _throttleLimit);
    }

    // ============================================================================================
    // Route Functions
    // ============================================================================================

    function debitPuppetAccount(uint256 _amount, address _asset, address _puppet) external onlyRoute {
        puppetDepositAccount[_asset][_puppet] -= _amount;

        emit PuppetAccountDebited(_amount, _asset, _puppet, msg.sender);
    }

    function creditPuppetAccount(uint256 _amount, address _asset, address _puppet) external onlyRoute {
        puppetDepositAccount[_asset][_puppet] += _amount;

        emit PuppetAccountCredited(_amount, _asset, _puppet, msg.sender);
    }

    function updateLastPositionOpenedTimestamp(address _route, address _puppet) external onlyRoute {
        lastPositionOpenedTimestamp[_route][_puppet] = block.timestamp;

        emit LastPositionOpenedTimestampUpdated(_route, _puppet, block.timestamp);
    }

    function sendFunds(uint256 _amount, address _asset, address _receiver) external onlyRoute {
        IERC20(_asset).safeTransfer(_receiver, _amount);

        emit FundsSent(_amount, _asset, _receiver, msg.sender);
    }

    // ============================================================================================
    // Authority Functions
    // ============================================================================================

    function setRouteType(address _collateral, address _index, bool _isLong) external requiresAuth {
        bytes32 _routeTypeKey = getRouteTypeKey(_collateral, _index, _isLong);
        routeType[_routeTypeKey] = RouteType(_collateral, _index, _isLong, true);

        emit RouteTypeSet(_routeTypeKey, _collateral, _index, _isLong);
    }

    function setGMXUtils(address _gmxRouter, address _gmxReader, address _gmxVault, address _gmxPositionRouter, address _gmxReferralRebatesSender) external requiresAuth {
        GMXInfo storage _gmxInfo = gmxInfo;

        _gmxInfo.gmxRouter = _gmxRouter;
        _gmxInfo.gmxReader = _gmxReader;
        _gmxInfo.gmxVault = _gmxVault;
        _gmxInfo.gmxPositionRouter = _gmxPositionRouter;
        _gmxInfo.gmxReferralRebatesSender = _gmxReferralRebatesSender;

        emit GMXUtilsSet(_gmxRouter, _gmxReader, _gmxVault, _gmxPositionRouter, _gmxReferralRebatesSender);
    }

    function setPuppetUtils(address _revenueDistributor, address _keeper, bytes32 _referralCode) external requiresAuth {
        revenueDistributor = _revenueDistributor;
        keeper = _keeper;
        referralCode = _referralCode;

        emit PuppetUtilsSet(_revenueDistributor, _keeper, _referralCode);
    }

    function setPriceFeeds(address[] memory _assets, address[] memory _priceFeeds, uint256[] memory _decimals) external requiresAuth {
        if (_assets.length != _priceFeeds.length || _assets.length != _decimals.length) revert MismatchedInputArrays();

        for (uint256 i = 0; i < _assets.length; i++) {
            priceFeeds[_assets[i]] = PriceFeedInfo({
                decimals: _decimals[i],
                priceFeed: AggregatorV3Interface(_priceFeeds[i])
            });
        }

        emit PriceFeedsSet(_assets, _priceFeeds, _decimals);
    }

    function pause(bool _pause) external requiresAuth {
        paused = _pause;

        emit Paused(_pause);
    }

    // ============================================================================================
    // Receive Function
    // ============================================================================================

    receive() external payable {}
}