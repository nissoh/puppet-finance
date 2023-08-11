// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ======================== Orchestrator ========================
// ==============================================================
// Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import {IGMXVaultPriceFeed} from "./interfaces/IGMXVaultPriceFeed.sol";

import {IRouteFactory} from "./interfaces/IRouteFactory.sol";

import "./Base.sol";

/// @title Orchestrator
/// @author johnnyonline (Puppet Finance) https://github.com/johnnyonline
/// @notice This contract contains the logic and storage for managing routes and puppets
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
        mapping(bytes32 => uint256) subscriptionExpiry; // routeKey => expiration
        mapping(bytes32 => uint256) throttleLimits; // routeType => throttle limit (in seconds)
        mapping(bytes32 => uint256) lastPositionOpenedTimestamp; // routeType => timestamp
        mapping(address => uint256) depositAccount; // collateralToken => balance
        EnumerableMap.AddressToUintMap allowances; // route => allowance percentage
    }

    // settings
    uint256 public managementFee = 0;
    uint256 public withdrawalFee = 0;

    uint256 internal _performanceFee = 0;

    uint256 public immutable ownerFunctionsDeadline;

    uint256 public constant MAX_FEE = 1000; // 10%

    address public routeFactory;
    address public platformFeeRecipient;
    address public multiSubscriber;

    address private _keeper;
    address private _scoreGauge;

    bool private _paused;

    bytes32 private _referralCode;

    mapping(address => bool) public traderWhitelist; // allows a Trader to be a contract

    GMXInfo private _gmxInfo;

    // routes info
    mapping(address => bool) public isRoute; // Route => isRoute
    mapping(address => uint256) public platformAccount; // asset => fees balance
    mapping(bytes32 => RouteType) public routeType; // routeTypeKey => RouteType

    mapping(bytes32 => RouteInfo) private _routeInfo; // routeKey => RouteInfo

    address[] private _routes;

    // puppets info
    mapping(address => PuppetInfo) private _puppetInfo;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    /// @notice The ```constructor``` function is called on deployment
    /// @param _authority The Authority contract instance
    /// @param _routeFactory The RouteFactory contract address
    /// @param _keeperAddr The address of the keeper
    /// @param _scoreGaugeAddr The address of the score gauge
    /// @param _platformFeeRecipient The address of the platform fee recipient
    /// @param _wethAddr The WETH contract address
    /// @param _refCode The GMX referral code
    /// @param _gmx The GMX contract addresses
    constructor(
        Authority _authority,
        address _routeFactory,
        address _keeperAddr,
        address _scoreGaugeAddr,
        address _platformFeeRecipient,
        address _wethAddr,
        bytes32 _refCode,
        bytes memory _gmx
    ) Auth(address(0), _authority) Base(_wethAddr) {
        if (_platformFeeRecipient == address(0)) revert ZeroAddress();
        if (_wethAddr == address(0)) revert ZeroAddress();

        routeFactory = _routeFactory;
        _keeper = _keeperAddr;
        _scoreGauge = _scoreGaugeAddr;
        platformFeeRecipient = _platformFeeRecipient;

        (
            _gmxInfo.vaultPriceFeed,
            _gmxInfo.router,
            _gmxInfo.vault,
            _gmxInfo.positionRouter
        ) = abi.decode(_gmx, (address, address, address, address));

        _referralCode = _refCode;

        ownerFunctionsDeadline = block.timestamp + 16 weeks;
    }

    // ============================================================================================
    // Modifiers
    // ============================================================================================

    /// @notice Modifier that ensures the caller is a route
    modifier onlyRoute() {
        if (!isRoute[msg.sender]) revert NotRoute();
        _;
    }

    /// @notice Modifier that ensures the contract is not paused
    modifier notPaused() {
        if (_paused) revert Paused();
        _;
    }

    /// @notice Modifier that ensures certain owner functions are called before the pre defined deadline
    modifier beforeDeadline() {
        if (block.timestamp >= ownerFunctionsDeadline) revert FunctionCallPastDeadline();
        _;
    }

    // ============================================================================================
    // View Functions
    // ============================================================================================

    // global

    /// @inheritdoc IOrchestrator
    function performanceFee() external view returns (uint256) {
        return _performanceFee;
    }

    /// @inheritdoc IOrchestrator
    function keeper() external view returns (address) {
        return _keeper;
    }

    /// @inheritdoc IOrchestrator
    function scoreGauge() external view returns (address) {
        return _scoreGauge;
    }

    /// @inheritdoc IOrchestrator
    function referralCode() external view returns (bytes32) {
        return _referralCode;
    }

    /// @inheritdoc IOrchestrator
    function routes() external view returns (address[] memory) {
        return _routes;
    }

    /// @inheritdoc IOrchestrator
    function paused() external view returns (bool) {
        return _paused;
    }

    // route

    /// @inheritdoc IOrchestrator
    function getRouteTypeKey(address _collateralToken, address _indexToken, bool _isLong) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_collateralToken, _indexToken, _isLong));
    }

    /// @inheritdoc IOrchestrator
    function getRouteKey(address _trader, bytes32 _routeTypeKey) public view returns (bytes32) {
        address _collateralToken = routeType[_routeTypeKey].collateralToken;
        address _indexToken = routeType[_routeTypeKey].indexToken;
        bool _isLong = routeType[_routeTypeKey].isLong;

        return keccak256(abi.encodePacked(_trader, _collateralToken, _indexToken, _isLong));
    }

    /// @inheritdoc IOrchestrator
    function getPositionKey(IRoute _route) public view returns (bytes32) {
        return keccak256(abi.encodePacked(address(_route), _route.collateralToken(), _route.indexToken(), _route.isLong()));
    }

    /// @inheritdoc IOrchestrator
    function subscribedPuppets(bytes32 _routeKey) public view returns (address[] memory _puppets) {
        EnumerableSet.AddressSet storage _puppetsSet = _routeInfo[_routeKey].puppets;

        uint256 _validCount = 0;
        uint256 _puppetsSetLength = EnumerableSet.length(_puppetsSet);
        for (uint256 i = 0; i < _puppetsSetLength; i++) {
            address _puppet = EnumerableSet.at(_puppetsSet, i);
            if (_puppetInfo[_puppet].subscriptionExpiry[_routeKey] > block.timestamp) _validCount++;
        }

        _puppets = new address[](_validCount);

        uint256 j = 0;
        for (uint256 i = 0; i < _puppetsSetLength; i++) {
            address _puppet = EnumerableSet.at(_puppetsSet, i);
            if (_puppetInfo[_puppet].subscriptionExpiry[_routeKey] > block.timestamp) {
                _puppets[j] = _puppet;
                j++;
            }
        }

        return _puppets;
    }


    /// @inheritdoc IOrchestrator
    function getRoute(bytes32 _routeKey) external view returns (address) {
        return _routeInfo[_routeKey].route;
    }

    /// @inheritdoc IOrchestrator
    function getRoute(address _trader, address _collateralToken, address _indexToken, bool _isLong) external view returns (address) {
        bytes32 _routeTypeKey = getRouteTypeKey(_collateralToken, _indexToken, _isLong);
        bytes32 _routeKey = getRouteKey(_trader, _routeTypeKey);

        return _routeInfo[_routeKey].route;
    }

    // puppet

    /// @inheritdoc IOrchestrator
    function puppetSubscriptions(address _puppet) external view returns (address[] memory) {
        PuppetInfo storage __puppetInfo = _puppetInfo[_puppet];
        EnumerableMap.AddressToUintMap storage _allowances = __puppetInfo.allowances;

        uint256 _validCount = 0;
        uint256 _subscriptionCount = EnumerableMap.length(_allowances);
        for (uint256 i = 0; i < _subscriptionCount; i++) {
            (address _route,) = EnumerableMap.at(_allowances, i);
            if (__puppetInfo.subscriptionExpiry[IRoute(_route).routeKey()] > block.timestamp) _validCount++;
        }

        address[] memory _subscriptions = new address[](_validCount);

        uint256 j = 0;
        for (uint256 i = 0; i < _subscriptionCount; i++) {
            (address _route,) = EnumerableMap.at(_allowances, i);
            if (__puppetInfo.subscriptionExpiry[IRoute(_route).routeKey()] > block.timestamp) {
                _subscriptions[j] = _route;
                j++;
            }
        }

        return _subscriptions;
    }


    /// @inheritdoc IOrchestrator
    function puppetAllowancePercentage(address _puppet, address _route) external view returns (uint256) {
        if (_puppetInfo[_puppet].subscriptionExpiry[IRoute(_route).routeKey()] > block.timestamp) {
            return EnumerableMap.get(_puppetInfo[_puppet].allowances, _route);
        } else {
            return 0;
        }
    }

    /// @inheritdoc IOrchestrator
    function puppetSubscriptionExpiry(address _puppet, address _route) external view returns (uint256) {
        uint256 _expiry = _puppetInfo[_puppet].subscriptionExpiry[IRoute(_route).routeKey()];
        if (_expiry > block.timestamp) {
            return _expiry;
        } else {
            return 0;
        }
    }

    /// @inheritdoc IOrchestrator
    function puppetAccountBalance(address _puppet, address _asset) external view returns (uint256) {
        return _puppetInfo[_puppet].depositAccount[_asset];
    }

    /// @inheritdoc IOrchestrator
    function puppetAccountBalanceAfterFee(address _puppet, address _asset, bool _isWithdraw) external view returns (uint256) {
        uint256 _amount = _puppetInfo[_puppet].depositAccount[_asset];
        return _amount -= (_isWithdraw ? (_amount * withdrawalFee) : (_amount * managementFee)) / _BASIS_POINTS_DIVISOR;
    }

    /// @inheritdoc IOrchestrator
    function puppetThrottleLimit(address _puppet, bytes32 _routeType) external view returns (uint256) {
        return _puppetInfo[_puppet].throttleLimits[_routeType];
    }

    /// @inheritdoc IOrchestrator
    function lastPositionOpenedTimestamp(address _puppet, bytes32 _routeType) external view returns (uint256) {
        return _puppetInfo[_puppet].lastPositionOpenedTimestamp[_routeType];
    }

    /// @inheritdoc IOrchestrator
    function isBelowThrottleLimit(address _puppet, bytes32 _routeType) external view returns (bool) {
        return (block.timestamp - _puppetInfo[_puppet].lastPositionOpenedTimestamp[_routeType]) >= _puppetInfo[_puppet].throttleLimits[_routeType];
    }

    // gmx

    /// @inheritdoc IOrchestrator
    function getPrice(address _token) external view returns (uint256) {
        return IGMXVaultPriceFeed(_gmxInfo.vaultPriceFeed).getPrice(
            _token,
            _gmxInfo.priceFeedMaximise,
            _gmxInfo.priceFeedIncludeAmmPrice,
            false
        );
    }

    /// @inheritdoc IOrchestrator
    function gmxVaultPriceFeed() external view returns (address) {
        return _gmxInfo.vaultPriceFeed;
    }

    /// @inheritdoc IOrchestrator
    function gmxRouter() external view returns (address) {
        return _gmxInfo.router;
    }

    /// @inheritdoc IOrchestrator
    function gmxPositionRouter() external view returns (address) {
        return _gmxInfo.positionRouter;
    }

    /// @inheritdoc IOrchestrator
    function gmxVault() external view returns (address) {
        return _gmxInfo.vault;
    }

    // ============================================================================================
    // Trader Function
    // ============================================================================================

    /// @inheritdoc IOrchestrator
    // slither-disable-next-line reentrancy-no-eth
    function registerRouteAccount(
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) public nonReentrant notPaused returns (bytes32 _routeKey) {
        if (_collateralToken == address(0) || _indexToken == address(0)) revert ZeroAddress();
        if (msg.sender != tx.origin && !traderWhitelist[msg.sender]) revert NotWhitelisted();

        bytes32 _routeTypeKey = getRouteTypeKey(_collateralToken, _indexToken, _isLong);
        if (!routeType[_routeTypeKey].isRegistered) revert RouteTypeNotRegistered();

        _routeKey = getRouteKey(msg.sender, _routeTypeKey);
        if (_routeInfo[_routeKey].isRegistered) revert RouteAlreadyRegistered();

        address _routeAddr = IRouteFactory(routeFactory).registerRouteAccount(
            address(this),
            _weth,
            msg.sender,
            _collateralToken,
            _indexToken,
            _isLong
        );

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

        emit RegisterRouteAccount(msg.sender, _routeAddr, _routeTypeKey);
    }

    /// @inheritdoc IOrchestrator
    function requestPosition(
        IRoute.AdjustPositionParams memory _adjustPositionParams,
        IRoute.SwapParams memory _swapParams,
        bytes32 _routeTypeKey,
        uint256 _executionFee,
        bool _isIncrease
    ) public payable nonReentrant notPaused returns (bytes32 _requestKey) {
        bytes32 _routeKey = getRouteKey(msg.sender, _routeTypeKey);
        IRoute _route = IRoute(_routeInfo[_routeKey].route);
        if (address(_route) == address(0)) revert RouteNotRegistered();

        _removeExpiredSubscriptions(_routeKey);

        if (_isIncrease && (msg.value == _executionFee)) {
            address _token = _swapParams.path[0];
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _swapParams.amount);
        }

        _requestKey = _route.requestPosition{ value: msg.value }(
            _adjustPositionParams,
            _swapParams,
            _executionFee,
            _isIncrease
        );

        if (_route.isPositionOpen()) {
            emit AdjustPosition(msg.sender, address(_route), _isIncrease, _requestKey, _routeTypeKey, getPositionKey(_route));
        } else {
            emit OpenPosition(subscribedPuppets(_routeKey), msg.sender, address(_route), _isIncrease, _requestKey, _routeTypeKey, getPositionKey(_route));
        }
    }

    /// @inheritdoc IOrchestrator
    function registerRouteAccountAndRequestPosition(
        IRoute.AdjustPositionParams memory _adjustPositionParams,
        IRoute.SwapParams memory _swapParams,
        uint256 _executionFee,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) external payable returns (bytes32 _routeKey, bytes32 _requestKey) {
        _routeKey = registerRouteAccount(_collateralToken, _indexToken, _isLong);

        _requestKey = requestPosition(
            _adjustPositionParams,
            _swapParams,
            getRouteTypeKey(_collateralToken, _indexToken, _isLong),
            _executionFee,
            true
        );
    }

    /// @inheritdoc IOrchestrator
    function approvePlugin(bytes32 _routeTypeKey) external {
        address _route = _routeInfo[getRouteKey(msg.sender, _routeTypeKey)].route;
        if (_route == address(0)) revert RouteNotRegistered();

        IRoute(_route).approvePlugin();

        emit ApprovePlugin(msg.sender, _routeTypeKey);
    }

    // ============================================================================================
    // Puppet Functions
    // ============================================================================================

    /// @inheritdoc IOrchestrator
    function subscribeRoute(
        uint256 _allowance,
        uint256 _subscriptionPeriod,
        address _owner,
        address _trader,
        bytes32 _routeTypeKey, 
        bool _subscribe
    ) public nonReentrant notPaused {
        bytes32 _routeKey = getRouteKey(_trader, _routeTypeKey);
        RouteInfo storage _route = _routeInfo[_routeKey];

        if (msg.sender != multiSubscriber) {
            _owner = msg.sender;
        }

        PuppetInfo storage _puppet = _puppetInfo[_owner];

        if (!_route.isRegistered) revert RouteNotRegistered();
        if (IRoute(_route.route).isWaitingForCallback()) revert RouteWaitingForCallback();

        if (_subscribe) {
            if (_allowance > _BASIS_POINTS_DIVISOR || _allowance == 0) revert InvalidAllowancePercentage();
            if (_subscriptionPeriod == 0) revert InvalidSubscriptionPeriod();

            _puppet.subscriptionExpiry[_routeKey] = block.timestamp + _subscriptionPeriod;

            EnumerableMap.set(_puppet.allowances, _route.route, _allowance);
            EnumerableSet.add(_route.puppets, _owner);
        } else {
            delete _puppet.subscriptionExpiry[_routeKey];

            EnumerableMap.remove(_puppet.allowances, _route.route);
            EnumerableSet.remove(_route.puppets, _owner);
        }

        emit SubscribeRoute(_allowance, _trader, _owner, _route.route, _routeTypeKey, _subscribe);
    }

    /// @inheritdoc IOrchestrator
    function batchSubscribeRoute(
        address _owner,
        uint256[] memory _allowances,
        uint256[] memory _subscriptionPeriods,
        address[] memory _traders,
        bytes32[] memory _routeTypeKeys,
        bool[] memory _subscribe
    ) external {
        if (_traders.length != _allowances.length) revert MismatchedInputArrays();
        if (_traders.length != _subscriptionPeriods.length) revert MismatchedInputArrays();
        if (_traders.length != _subscribe.length) revert MismatchedInputArrays();
        if (_traders.length != _routeTypeKeys.length) revert MismatchedInputArrays();

        for (uint256 i = 0; i < _traders.length; i++) {
            subscribeRoute(_allowances[i], _subscriptionPeriods[i], _owner, _traders[i], _routeTypeKeys[i], _subscribe[i]);
        }
    }

    /// @inheritdoc IOrchestrator
    function deposit(uint256 _amount, address _asset, address _puppet) external payable nonReentrant notPaused {
        if (_amount == 0) revert ZeroAmount();
        if (_puppet == address(0)) revert ZeroAddress();
        if (_asset == address(0)) revert ZeroAddress();
        if (msg.value > 0) {
            if (_amount != msg.value) revert InvalidAmount();
            if (_asset != _weth) revert InvalidAsset();
        }

        _creditPuppetAccount(_amount, _asset, msg.sender);

        if (msg.value > 0) {
            payable(_asset).functionCallWithValue(abi.encodeWithSignature("deposit()"), _amount);
        } else {
            IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);
        }

        emit Deposit(_amount, _asset, msg.sender, _puppet);
    }

    /// @inheritdoc IOrchestrator
    function withdraw(uint256 _amount, address _asset, address _receiver, bool _isETH) external nonReentrant {
        if (_amount == 0) revert ZeroAmount();
        if (_receiver == address(0)) revert ZeroAddress();
        if (_asset == address(0)) revert ZeroAddress();
        if (_isETH && _asset != _weth) revert InvalidAsset();
 
        _debitPuppetAccount(_amount, _asset, msg.sender, true);

        if (_isETH) {
            IWETH(_asset).withdraw(_amount);
            payable(_receiver).sendValue(_amount);
        } else {
            IERC20(_asset).safeTransfer(_receiver, _amount);
        }

        emit Withdraw(_amount, _asset, _receiver, msg.sender);
    }

    /// @inheritdoc IOrchestrator
    function setThrottleLimit(uint256 _throttleLimit, bytes32 _routeType) external nonReentrant notPaused {
        _puppetInfo[msg.sender].throttleLimits[_routeType] = _throttleLimit;

        emit SetThrottleLimit(msg.sender, _routeType, _throttleLimit);
    }

    // ============================================================================================
    // Route Functions
    // ============================================================================================

    /// @inheritdoc IOrchestrator
    function debitPuppetAccount(uint256 _amount, address _asset, address _puppet) external onlyRoute {
        _debitPuppetAccount(_amount, _asset, _puppet, false);
    } 

    /// @inheritdoc IOrchestrator
    function creditPuppetAccount(uint256 _amount, address _asset, address _puppet) external onlyRoute {
        _creditPuppetAccount(_amount, _asset, _puppet);
    }

    /// @inheritdoc IOrchestrator
    function updateLastPositionOpenedTimestamp(address _puppet, bytes32 _routeType) external onlyRoute {
        _puppetInfo[_puppet].lastPositionOpenedTimestamp[_routeType] = block.timestamp;

        emit UpdateOpenTimestamp(_puppet, _routeType, block.timestamp);
    }

    /// @inheritdoc IOrchestrator
    function transferRouteFunds(uint256 _amount, address _asset, address _receiver) external onlyRoute {
        IERC20(_asset).safeTransfer(_receiver, _amount);

        emit TransferRouteFunds(_amount, _asset, _receiver, msg.sender);
    }

    /// @inheritdoc IOrchestrator
    function emitExecutionCallback(uint256 _performanceFeePaid, bytes32 _requestKey, bool _isExecuted, bool _isIncrease) external onlyRoute {
        emit ExecutePosition(_performanceFeePaid, msg.sender, _requestKey, _isExecuted, _isIncrease);
    }

    /// @inheritdoc IOrchestrator
    function emitSharesIncrease(uint256[] memory _puppetsShares, uint256 _traderShares, uint256 _totalSupply) external onlyRoute {
        emit SharesIncrease(_puppetsShares, _traderShares, _totalSupply, getPositionKey(IRoute(msg.sender)));
    }

    // ============================================================================================
    // Authority Functions
    // ============================================================================================

    // called by anyone

    /// @inheritdoc IOrchestrator
    function withdrawPlatformFees(address _asset) external nonReentrant returns (uint256 _amount) {
        if (_asset == address(0)) revert ZeroAddress();

        _amount = platformAccount[_asset];
        if (_amount == 0) revert ZeroAmount();

        platformAccount[_asset] = 0;

        address _platformFeeRecipient = platformFeeRecipient;
        IERC20(_asset).safeTransfer(_platformFeeRecipient, _amount);

        emit WithdrawPlatformFees(_amount, _asset, msg.sender, _platformFeeRecipient);
    }

    // called by keeper

    /// @inheritdoc IOrchestrator
    function adjustTargetLeverage(
        IRoute.AdjustPositionParams memory _adjustPositionParams,
        uint256 _executionFee,
        bytes32 _routeKey
    ) external payable requiresAuth nonReentrant returns (bytes32 _requestKey) {
        IRoute _route = IRoute(_routeInfo[_routeKey].route);
        if (address(_route) == address(0)) revert RouteNotRegistered();

        _requestKey = _route.decreaseSize{ value: msg.value }(_adjustPositionParams, _executionFee);

        emit AdjustTargetLeverage(address(_route), _requestKey, _routeKey, getPositionKey(_route));
    }

    /// @inheritdoc IOrchestrator
    function liquidatePosition(bytes32 _routeKey) external requiresAuth nonReentrant {
        IRoute _route = IRoute(_routeInfo[_routeKey].route);
        if (address(_route) == address(0)) revert RouteNotRegistered();

        _route.liquidate();

        emit LiquidatePosition(address(_route), _routeKey, getPositionKey(_route));
    }

    // called by owner

    /// @inheritdoc IOrchestrator
    function rescueRouteFunds(uint256 _amount, address _token, address _receiver, address _route) external requiresAuth nonReentrant {
        IRoute(_route).rescueTokenFunds(_amount, _token, _receiver);

        emit RescueRouteFunds(_amount, _token, _receiver, _route);
    }

    /// @inheritdoc IOrchestrator
    function setTraderWhitelist(address _trader, bool _isWhitelisted) external requiresAuth nonReentrant {
        traderWhitelist[_trader] = _isWhitelisted;

        emit SetTraderWhitelist(_trader, _isWhitelisted);
    }

    /// @inheritdoc IOrchestrator
    function serMultiSubscriber(address _multiSubscriber) external requiresAuth nonReentrant {
        if (_multiSubscriber == address(0)) revert ZeroAddress();

        _multiSubscriber = _multiSubscriber;

        emit SetMultiSubscriber(_multiSubscriber);
    }

    /// @inheritdoc IOrchestrator
    function setRouteType(address _collateral, address _index, bool _isLong) external beforeDeadline requiresAuth nonReentrant {
        bytes32 _routeTypeKey = getRouteTypeKey(_collateral, _index, _isLong);
        routeType[_routeTypeKey] = RouteType(_collateral, _index, _isLong, true);

        emit SetRouteType(_routeTypeKey, _collateral, _index, _isLong);
    }

    /// @inheritdoc IOrchestrator
    function setKeeper(address _keeperAddr) external beforeDeadline requiresAuth nonReentrant {
        if (_keeperAddr == address(0)) revert ZeroAddress();

        _keeper = _keeperAddr;

        emit SetKeeper(_keeper);
    }

    /// @inheritdoc IOrchestrator
    function setScoreGauge(address _gauge) external beforeDeadline requiresAuth nonReentrant {
        if (_gauge == address(0)) revert ZeroAddress();

        _scoreGauge = _gauge;

        emit SetScoreGauge(_gauge);
    }

    /// @inheritdoc IOrchestrator
    function setReferralCode(bytes32 _refCode) external beforeDeadline requiresAuth nonReentrant {
        if (_refCode == bytes32(0)) revert ZeroBytes32();

        _referralCode = _refCode;

        emit SetReferralCode(_refCode);
    }

    /// @inheritdoc IOrchestrator
    function setFees(uint256 _managmentFee, uint256 _withdrawalFee, uint256 _perfFee) external beforeDeadline requiresAuth nonReentrant {
        if (_managmentFee > MAX_FEE || _withdrawalFee > MAX_FEE || _perfFee > MAX_FEE) revert FeeExceedsMax();

        managementFee = _managmentFee;
        withdrawalFee = _withdrawalFee;

        _performanceFee = _perfFee;

        emit SetFees(_managmentFee, _withdrawalFee, _perfFee);
    }

    /// @inheritdoc IOrchestrator
    function setPlatformFeesRecipient(address _recipient) external beforeDeadline requiresAuth nonReentrant {
        if (_recipient == address(0)) revert ZeroAddress();

        platformFeeRecipient = _recipient;

        emit SetFeesRecipient(_recipient);
    }

    /// @inheritdoc IOrchestrator
    function pause(bool _pause) external beforeDeadline requiresAuth nonReentrant {
        _paused = _pause;

        emit Pause(_pause);
    }

    // ============================================================================================
    // Internal Functions
    // ============================================================================================

    /// @notice Remove Puppets with expired subscriptions from the Route's Puppets Set
    /// @param _routeKey Route Key
    function _removeExpiredSubscriptions(bytes32 _routeKey) internal {
        EnumerableSet.AddressSet storage _puppetsSet = _routeInfo[_routeKey].puppets;
        for (uint256 i = 0; i < EnumerableSet.length(_puppetsSet); i++) {
            address _puppet = EnumerableSet.at(_puppetsSet, i);
            if (_puppetInfo[_puppet].subscriptionExpiry[_routeKey] <= block.timestamp) {
                EnumerableSet.remove(_puppetsSet, _puppet);
            }
        }
    }

    function _debitPuppetAccount(uint256 _amount, address _asset, address _puppet, bool _isWithdraw) internal {
        uint256 _feeAmount = (_isWithdraw ? (_amount * withdrawalFee) : (_amount * managementFee)) / _BASIS_POINTS_DIVISOR;

        _puppetInfo[_puppet].depositAccount[_asset] -= (_amount + _feeAmount);
        platformAccount[_asset] += _feeAmount;

        emit DebitPuppet(_amount, _asset, _puppet, msg.sender);
        emit CreditPlatform(_feeAmount, _asset, _puppet, msg.sender, _isWithdraw);
    }

    function _creditPuppetAccount(uint256 _amount, address _asset, address _puppet) internal {
        _puppetInfo[_puppet].depositAccount[_asset] += _amount;

        emit CreditPuppet(_amount, _asset, _puppet, msg.sender);
    }

    // ============================================================================================
    // Receive Function
    // ============================================================================================

    receive() external payable {}
}