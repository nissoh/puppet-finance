// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import {IRoute} from "./interfaces/IRoute.sol";
import {IRouteFactory} from "./interfaces/IRouteFactory.sol";

import "./Base.sol";

contract Orchestrator is Auth, Base, IOrchestrator {

    using SafeERC20 for IERC20;
    using Address for address payable;

    struct RouteInfo {
        address route;
        bool isRegistered;
        EnumerableSet.AddressSet puppets;
        RouteType routeType;
    }

    struct PuppetInfo {
        mapping(address => uint256) throttleLimits; // Route => throttle limit (in seconds)
        mapping(address => uint256) lastPositionOpenedTimestamp; // Route => timestamp
        mapping(address => uint256) depositAccount; // collateralToken => balance
        EnumerableMap.AddressToUintMap allowances; // Route => allowance percentage
    }

    struct GMXInfo {
        address gmxRouter;
        address gmxReader;
        address gmxVault;
        address gmxPositionRouter;
        address gmxReferralRebatesSender;
    }

    address public routeFactory;

    // routes info
    mapping(address => bool) public isRoute; // Route => isRoute
    mapping(bytes32 => RouteType) public routeType; // routeTypeKey => RouteType

    mapping(bytes32 => RouteInfo) private _routeInfo; // routeKey => RouteInfo

    address[] private _routes;

    // puppets info
    mapping(address => PuppetInfo) private _puppetInfo;

    // settings
    bool private _paused; // used to pause all routes on update of gmx/global utils

    GMXInfo private _gmxInfo;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    constructor(Authority _authority, address _routeFactory, address _keeperAddr, bytes32 _refCode, GMXInfo memory _gmx) Auth(address(0), _authority) {
        routeFactory = _routeFactory;
        _keeper = _keeperAddr;

        _gmxInfo = _gmx;

        _referralCode = _refCode;
    }

    // ============================================================================================
    // Modifiers
    // ============================================================================================

    modifier onlyRoute() {
        if (!isRoute[msg.sender]) revert NotRoute();
        _;
    }

    // ============================================================================================
    // View Functions
    // ============================================================================================

    // global

    function getKeeper() external view returns (address) {
        return _keeper;
    }

    function getRefCode() external view returns (bytes32) {
        return _referralCode;
    }

    function getRoutes() external view returns (address[] memory) {
        return _routes;
    }

    function getIsPaused() external view returns (bool) {
        return _paused;
    }

    // route

    function getRoute(bytes32 _routeKey) external view returns (address) {
        return _routeInfo[_routeKey].route;
    }

    function getRoute(address _trader, address _collateralToken, address _indexToken, bool _isLong) external view returns (address) {
        bytes32 _routeTypeKey = getRouteTypeKey(_collateralToken, _indexToken, _isLong);
        bytes32 _routeKey = getRouteKey(_trader, _routeTypeKey);

        return _routeInfo[_routeKey].route;
    }

    function getRouteTypeKey(address _collateralToken, address _indexToken, bool _isLong) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_collateralToken, _indexToken, _isLong));
    }

    function getRouteKey(address _trader, bytes32 _routeTypeKey) public view returns (bytes32) {
        address _collateralToken = routeType[_routeTypeKey].collateralToken;
        address _indexToken = routeType[_routeTypeKey].indexToken;
        bool _isLong = routeType[_routeTypeKey].isLong;

        return keccak256(abi.encodePacked(_trader, _collateralToken, _indexToken, _isLong));
    }

    function getPuppetsForRoute(bytes32 _routeKey) external view returns (address[] memory _puppets) {
        EnumerableSet.AddressSet storage _puppetsSet = _routeInfo[_routeKey].puppets;
        _puppets = new address[](EnumerableSet.length(_puppetsSet));

        for (uint256 i = 0; i < EnumerableSet.length(_puppetsSet); i++) {
            _puppets[i] = EnumerableSet.at(_puppetsSet, i);
        }
    }

    // puppet

    function isBelowThrottleLimit(address _puppet, address _route) external view returns (bool) {
        return (block.timestamp - _puppetInfo[_puppet].lastPositionOpenedTimestamp[_route]) >= _puppetInfo[_puppet].throttleLimits[_route];
    }

    function getPuppetThrottleLimit(address _puppet, address _route) external view returns (uint256) {
        return _puppetInfo[_puppet].throttleLimits[_route];
    }

    function getPuppetAllowancePercentage(address _puppet, address _route) external view returns (uint256 _allowance) {
        return EnumerableMap.get(_puppetInfo[_puppet].allowances, _route);
    }

    function getPuppetAccountBalance(address _puppet, address _asset) external view returns (uint256) {
        return _puppetInfo[_puppet].depositAccount[_asset];
    }

    function getLastPositionOpenedTimestamp(address _puppet, address _route) external view returns (uint256) {
        return _puppetInfo[_puppet].lastPositionOpenedTimestamp[_route];
    }

    // gmx

    function getGMXRouter() external view returns (address) {
        return _gmxInfo.gmxRouter;
    }

    function getGMXPositionRouter() external view returns (address) {
        return _gmxInfo.gmxPositionRouter;
    }

    function getGMXVault() external view returns (address) {
        return _gmxInfo.gmxVault;
    }

    // ============================================================================================
    // Trader Function
    // ============================================================================================

    /// @dev violates checks-effects-interactions pattern. we use reentrancy guard
    // slither-disable-next-line reentrancy-no-eth
    function registerRoute(address _collateralToken, address _indexToken, bool _isLong) public nonReentrant returns (bytes32 _routeKey) {
        if (_collateralToken == address(0) || _indexToken == address(0)) revert ZeroAddress();

        bytes32 _routeTypeKey = getRouteTypeKey(_collateralToken, _indexToken, _isLong);
        if (!routeType[_routeTypeKey].isRegistered) revert RouteTypeNotRegistered();

        _routeKey = getRouteKey(msg.sender, _routeTypeKey);
        if (_routeInfo[_routeKey].isRegistered) revert RouteAlreadyRegistered();

        address _routeAddr = IRouteFactory(routeFactory).createRoute(address(this), msg.sender, _collateralToken, _indexToken, _isLong);

        RouteType memory _routeType = RouteType({
            collateralToken: _collateralToken,
            indexToken: _indexToken,
            isLong: _isLong,
            isRegistered: true
        });

        RouteInfo storage _route = _routeInfo[_routeKey];

        _route.route = _routeAddr;
        _route.isRegistered = true;
        _route.routeType = _routeType;

        isRoute[_routeAddr] = true;
        _routes.push(_routeAddr);

        emit RouteRegistered(msg.sender, _routeAddr, _routeTypeKey);
    }

    function registerRouteAndCreateIncreasePositionRequest(
        bytes memory _traderPositionData,
        bytes memory _traderSwapData,
        uint256 _executionFee,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) external payable returns (bytes32 _routeKey, bytes32 _requestKey) {
        _routeKey = registerRoute(_collateralToken, _indexToken, _isLong);
        _requestKey = IRoute(_routeInfo[_routeKey].route).createPositionRequest{value: msg.value}(_traderPositionData, _traderSwapData, _executionFee, true);
    }

    // ============================================================================================
    // Puppet Functions
    // ============================================================================================

    function deposit(uint256 _amount, address _asset, address _puppet) external payable nonReentrant {
        if (_amount == 0) revert ZeroAmount();
        if (_puppet == address(0)) revert ZeroAddress();
        if (_asset == address(0)) revert ZeroAddress();
        if (msg.value > 0) {
            if (_amount != msg.value) revert InvalidAmount();
            if (_asset != _WETH) revert InvalidAsset();
        }

        _puppetInfo[_puppet].depositAccount[_asset] += _amount;

        emit Deposited(_amount, _asset, msg.sender, _puppet);

        if (msg.value > 0) {
            payable(_asset).functionCallWithValue(abi.encodeWithSignature("deposit()"), _amount);
        } else {
            IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);
        }
    }

    function withdraw(uint256 _amount, address _asset, address _receiver, bool _isETH) external nonReentrant {
        if (_amount == 0) revert ZeroAmount();
        if (_receiver == address(0)) revert ZeroAddress();
        if (_asset == address(0)) revert ZeroAddress();
        if (_isETH && _asset != _WETH) revert InvalidAsset();
 
        _puppetInfo[msg.sender].depositAccount[_asset] -= _amount;

        emit Withdrawn(_amount, _asset, _receiver, msg.sender);

        if (_isETH) {
            IWETH(_asset).withdraw(_amount);
            payable(_receiver).sendValue(_amount);
        } else {
            IERC20(_asset).safeTransfer(_receiver, _amount);
        }
    }

    function updateRoutesSubscription(address[] memory _traders, uint256[] memory _allowances, bytes32 _routeTypeKey, bool _subscribe) external nonReentrant {
        if (_traders.length != _allowances.length) revert MismatchedInputArrays();

        address _puppet = msg.sender;
        for (uint256 i = 0; i < _traders.length; i++) {
            bytes32 _routeKey = getRouteKey(_traders[i], _routeTypeKey);
            RouteInfo storage _route = _routeInfo[_routeKey];

            if (!_route.isRegistered) revert RouteNotRegistered();

            if (_subscribe) {
                if (_allowances[i] > 100 || _allowances[i] == 0) revert InvalidAllowancePercentage();

                EnumerableMap.set(_puppetInfo[_puppet].allowances, _route.route, _allowances[i]);

                if (!EnumerableSet.contains(_route.puppets, _puppet)) {
                    EnumerableSet.add(_route.puppets, _puppet);
                }
            } else {
                EnumerableMap.set(_puppetInfo[_puppet].allowances, _route.route, 0);

                if (EnumerableSet.contains(_route.puppets, _puppet)) {
                    EnumerableSet.remove(_route.puppets, _puppet);
                }
            }
        }

        emit RoutesSubscriptionUpdated(_traders, _allowances, _puppet, _routeTypeKey, _subscribe);
    }

    function setThrottleLimit(uint256 _throttleLimit, address _route) external {
        _puppetInfo[msg.sender].throttleLimits[_route] = _throttleLimit;

        emit ThrottleLimitSet(msg.sender, _route, _throttleLimit);
    }

    // ============================================================================================
    // Route Functions
    // ============================================================================================

    function debitPuppetAccount(uint256 _amount, address _asset, address _puppet) external onlyRoute {
        _puppetInfo[_puppet].depositAccount[_asset] -= _amount;

        emit PuppetAccountDebited(_amount, _asset, _puppet, msg.sender);
    }

    function creditPuppetAccount(uint256 _amount, address _asset, address _puppet) external onlyRoute {
        _puppetInfo[_puppet].depositAccount[_asset] += _amount;

        emit PuppetAccountCredited(_amount, _asset, _puppet, msg.sender);
    }

    function updateLastPositionOpenedTimestamp(address _puppet, address _route) external onlyRoute {
        _puppetInfo[_puppet].lastPositionOpenedTimestamp[_route] = block.timestamp;

        emit LastPositionOpenedTimestampUpdated(_puppet, _route, block.timestamp);
    }

    function sendFunds(uint256 _amount, address _asset, address _receiver) external onlyRoute {
        emit FundsSent(_amount, _asset, _receiver, msg.sender);

        IERC20(_asset).safeTransfer(_receiver, _amount);
    }

    // ============================================================================================
    // Authority Functions
    // ============================================================================================
    // TODO - add requiresAuth

    function rescueTokens(uint256 _amount, address _token, address _receiver) external nonReentrant {
        if (_token == address(0)) {
            payable(_receiver).sendValue(_amount);
        } else {
            IERC20(_token).safeTransfer(_receiver, _amount);
        }

        emit TokensRescued(_amount, _token, _receiver);
    }

    function rescueRouteTokens(uint256 _amount, address _token, address _receiver, address _route) external nonReentrant {
        IRoute(_route).rescueTokens(_amount, _token, _receiver);

        emit RouteTokensRescued(_amount, _token, _receiver, _route);
    }

    function routeCreatePositionRequest(bytes memory _traderPositionData, bytes memory _traderSwapData, uint256 _executionFee, address _route, bool _isIncrease) external payable nonReentrant returns (bytes32 _requestKey) {
        _requestKey = IRoute(_route).createPositionRequest{value: msg.value}(_traderPositionData, _traderSwapData, _executionFee, _isIncrease);

        emit PositionRequestCreated(_requestKey, _route, _isIncrease);
    }

    function setRouteType(address _collateral, address _index, bool _isLong) external nonReentrant {
        bytes32 _routeTypeKey = getRouteTypeKey(_collateral, _index, _isLong);
        routeType[_routeTypeKey] = RouteType(_collateral, _index, _isLong, true);

        emit RouteTypeSet(_routeTypeKey, _collateral, _index, _isLong);
    }

    function setGMXInfo(address _gmxRouter, address _gmxReader, address _gmxVault, address _gmxPositionRouter, address _gmxReferralRebatesSender) external nonReentrant {
        GMXInfo storage _gmx = _gmxInfo;

        _gmx.gmxRouter = _gmxRouter;
        _gmx.gmxReader = _gmxReader;
        _gmx.gmxVault = _gmxVault;
        _gmx.gmxPositionRouter = _gmxPositionRouter;
        _gmx.gmxReferralRebatesSender = _gmxReferralRebatesSender;

        emit GMXUtilsSet(_gmxRouter, _gmxReader, _gmxVault, _gmxPositionRouter, _gmxReferralRebatesSender); // todo - clean unused
    }

    function setKeeper(address _keeperAddr) external nonReentrant {
        if (_keeperAddr == address(0)) revert ZeroAddress();

        _keeper = _keeperAddr;

        emit KeeperSet(_keeper);
    }

    function setReferralCode(bytes32 _refCode) external nonReentrant {
        if (_refCode == bytes32(0)) revert ZeroBytes32();

        _referralCode = _refCode;

        emit ReferralCodeSet(_refCode);
    }

    function pause(bool _pause) external nonReentrant {
        _paused = _pause;

        emit Paused(_pause);
    }

    // ============================================================================================
    // Receive Function
    // ============================================================================================

    receive() external payable {}
}