// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ======================== IOrchestrator =======================
// ==============================================================
// Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

import {IRoute} from "./IRoute.sol";

interface IOrchestrator {

    struct RouteType {
        address collateralToken;
        address indexToken;
        bool isLong;
        bool isRegistered;
    }

    struct GMXInfo {
        address vaultPriceFeed;
        address router;
        address vault;
        address positionRouter;
        bool priceFeedMaximise;
        bool priceFeedIncludeAmmPrice;
    }

    // ============================================================================================
    // View Functions
    // ============================================================================================

    // global

    /// @notice The ```performanceFee``` function returns the performance fee
    /// @return _performanceFee The performance fee
    function performanceFee() external view returns (uint256 _performanceFee);

    /// @notice The ```keeper``` function returns the address of the Keeper
    /// @return _keeper The address of the Keeper
    function keeper() external view returns (address _keeper);

    /// @notice The ```scoreGauge``` function returns the address of the ScoreGauge
    /// @return _scoreGauge The address of the ScoreGauge
    function scoreGauge() external view returns (address);

    /// @notice The ```referralCode``` function returns the referral code
    /// @return _referralCode The referral code
    function referralCode() external view returns (bytes32 _referralCode);

    /// @notice The ```routes``` function returns all the routes
    /// @return _routes The address array of all the routes
    function routes() external view returns (address[] memory _routes);

    /// @notice The ```paused``` function returns the paused state
    /// @return _paused The paused state
    function paused() external view returns (bool _paused);

    // route

    /// @notice The ```getRouteTypeKey``` function returns RouteType key for a given Route attributes
    /// @param _collateralToken The address of the Collateral Token
    /// @param _indexToken The address of the Index Token
    /// @param _isLong The boolean value of the position
    /// @return _routeTypeKey The RouteType key
    function getRouteTypeKey(address _collateralToken, address _indexToken, bool _isLong) external pure returns (bytes32 _routeTypeKey);

    /// @notice The ```getRouteKey``` function returns the Route key for a given RouteType key and Trader address
    /// @param _trader The address of the Trader
    /// @param _routeTypeKey The RouteType key
    /// @return _routeKey The Route key
    function getRouteKey(address _trader, bytes32 _routeTypeKey) external view returns (bytes32 _routeKey);

    /// @notice The ```getPositionKey``` function returns the Position key for a given Route, similar to what is stored in GMX
    /// @param _route The Route address
    /// @return _positionKey The Position key
    function getPositionKey(IRoute _route) external view returns (bytes32 _positionKey);

    /// @notice The ```subscribedPuppets``` function returns all the subscribed puppets for a given Route key
    /// @notice Those puppets may not be subscribed to the current Route's position
    /// @param _routeKey The Route key
    /// @return _puppets The address array of all the subscribed puppets
    function subscribedPuppets(bytes32 _routeKey) external view returns (address[] memory _puppets);

    /// @notice The ```getRoute``` function returns the Route address for a given Route key
    /// @param _routeKey The Route key
    /// @return _route The Route address
    function getRoute(bytes32 _routeKey) external view returns (address _route);

    /// @notice The ```getRoute``` function returns the Route address for a given Route attributes and Trader address
    /// @param _trader The address of the Trader
    /// @param _collateralToken The address of the Collateral Token
    /// @param _indexToken The address of the Index Token
    /// @param _isLong The boolean value of the position
    /// @return _route The Route address
    function getRoute(address _trader, address _collateralToken, address _indexToken, bool _isLong) external view returns (address _route);

    /// @notice The ```isRoute``` function returns the boolean value of whether a given address is a Route
    /// @param _route The address of the Route
    /// @return _isRoute The boolean value of whether the address is a Route
    function isRoute(address _route) external view returns (bool _isRoute);

    // puppet

    /// @notice The ```puppetSubscriptions``` function returns all the subscriptions for a given Puppet
    /// @param _puppet The address of the Puppet
    /// @return _subscriptions The address array of all the routes that the Puppet is subscribed to
    function puppetSubscriptions(address _puppet) external view returns (address[] memory _subscriptions);

    /// @notice The ```puppetAllowancePercentage``` function returns the allowance percentage for a given Puppet and Route
    /// @param _puppet The address of the Puppet
    /// @param _route The address of the Route
    /// @return _allowance The allowance percentage
    function puppetAllowancePercentage(address _puppet, address _route) external view returns (uint256 _allowance);

    /// @notice The ```puppetSubscriptionExpiry``` function returns the subscription expiry for a given Puppet and Route
    /// @param _puppet The address of the Puppet
    /// @param _route The address of the Route
    /// @return _expiry The subscription expiry
    function puppetSubscriptionExpiry(address _puppet, address _route) external view returns (uint256);

    /// @notice The ```puppetAccountBalance``` function returns the account balance for a given Puppet and Asset
    /// @param _puppet The address of the Puppet
    /// @param _asset The address of the Asset
    /// @param _balance The address of the Puppet
    function puppetAccountBalance(address _puppet, address _asset) external view returns (uint256 _balance);

    /// @notice The ```puppetAccountBalanceAfterFee``` function returns the account balance for a given Puppet and Asset
    /// @param _puppet The address of the Puppet
    /// @param _asset The address of the Asset
    /// @param _isWithdraw The boolean value of the withdrawal
    /// @return _balance The account balance
    function puppetAccountBalanceAfterFee(address _puppet, address _asset, bool _isWithdraw) external view returns (uint256 _balance);

    /// @notice The ```puppetThrottleLimit``` function returns the throttle limit for a given Puppet and RouteType
    /// @param _puppet The address of the Puppet
    /// @param _routeType The RouteType key
    /// @return _balance The throttle limit
    function puppetThrottleLimit(address _puppet, bytes32 _routeType) external view returns (uint256 _balance);

    /// @notice The ```lastPositionOpenedTimestamp``` function returns the last position opened timestamp for a given Puppet and RouteType
    /// @param _puppet The address of the Puppet
    /// @param _routeType The RouteType key
    /// @return _lastPositionOpenedTimestamp The last position opened timestamp
    function lastPositionOpenedTimestamp(address _puppet, bytes32 _routeType) external view returns (uint256 _lastPositionOpenedTimestamp);

    /// @notice The ```isBelowThrottleLimit``` function returns whether a given Puppet is below the throttle limit for a given RouteType
    /// @param _puppet The address of the Puppet
    /// @param _routeType The RouteType key
    /// @return _isBelowThrottleLimit Whether the Puppet is below the throttle limit
    function isBelowThrottleLimit(address _puppet, bytes32 _routeType) external view returns (bool _isBelowThrottleLimit);

    // gmx

    /// @notice The ```getPrice``` function returns the price for a given Token from the GMX vaultPriceFeed
    /// @notice prices are USD denominated with 30 decimals
    /// @param _token The address of the Token
    /// @return _price The price
    function getPrice(address _token) external view returns (uint256 _price);

    /// @notice The ```gmxVaultPriceFeed``` function returns the GMX vaultPriceFeed address
    /// @return _gmxVaultPriceFeed The GMX vaultPriceFeed address
    function gmxVaultPriceFeed() external view returns (address _gmxVaultPriceFeed);

    /// @notice The ```gmxInfo``` function returns the GMX Router address
    /// @return _router The GMX Router address
    function gmxRouter() external view returns (address _router);

    /// @notice The ```gmxPositionRouter``` function returns the GMX Position Router address
    /// @return _positionRouter The GMX Position Router address
    function gmxPositionRouter() external view returns (address _positionRouter);

    /// @notice The ```gmxVault``` function returns the GMX Vault address
    /// @return _vault The GMX Vault address
    function gmxVault() external view returns (address _vault);

    // ============================================================================================
    // Mutated Functions
    // ============================================================================================

    // Trader

    /// @notice The ```registerRouteAccount``` function is called by a Trader to register a new Route Account
    /// @param _collateralToken The address of the Collateral Token
    /// @param _indexToken The address of the Index Token
    /// @param _isLong The boolean value of the position
    /// @return bytes32 The Route key
    function registerRouteAccount(address _collateralToken, address _indexToken, bool _isLong) external returns (bytes32);

    /// @notice The ```requestPosition``` function creates a new position request
    /// @param _adjustPositionParams The adjusment params for the position
    /// @param _swapParams The swap data of the Trader, enables the Trader to add collateral with a non-collateral token
    /// @param _routeTypeKey The RouteType key
    /// @param _executionFee The total execution fee, paid by the Trader in ETH
    /// @param _isIncrease The boolean indicating if the request is an increase or decrease request
    /// @return _requestKey The request key
    function requestPosition(IRoute.AdjustPositionParams memory _adjustPositionParams, IRoute.SwapParams memory _swapParams, bytes32 _routeTypeKey, uint256 _executionFee, bool _isIncrease) external payable returns (bytes32 _requestKey);

    /// @notice The ```registerRouteAccountAndRequestPosition``` function is called by a Trader to register a new Route Account and create an Increase Position Request
    /// @param _adjustPositionParams The adjusment params for the position
    /// @param _swapParams The swap data of the Trader, enables the Trader to add collateral with a non-collateral token
    /// @param _executionFee The total execution fee, paid by the Trader in ETH
    /// @param _collateralToken The address of the Collateral Token
    /// @param _indexToken The address of the Index Token
    /// @param _isLong The boolean value of the position
    function registerRouteAccountAndRequestPosition(IRoute.AdjustPositionParams memory _adjustPositionParams, IRoute.SwapParams memory _swapParams, uint256 _executionFee, address _collateralToken, address _indexToken, bool _isLong) external payable returns (bytes32 _routeKey, bytes32 _requestKey);

    /// @notice The ```approvePlugin``` function is used to approve the GMX plugin in case we change the gmxPositionRouter address
    /// @param _routeTypeKey The RouteType key
    function approvePlugin(bytes32 _routeTypeKey) external;

    // Puppet

    /// @notice The ```subscribeRoute``` function is called by a Puppet to update his subscription to a Route
    /// @param _allowance The allowance percentage
    /// @param _subscriptionPeriod The subscription period
    /// @param _owner The subscribing Puppet
    /// @param _trader The address of the Trader
    /// @param _routeTypeKey The RouteType key
    /// @param _subscribe Whether to subscribe or unsubscribe
    function subscribeRoute(uint256 _allowance, uint256 _subscriptionPeriod, address _owner, address _trader, bytes32 _routeTypeKey, bool _subscribe) external;

    /// @notice The ```batchSubscribeRoute``` function is called by a Puppet to update his subscription to a list of Routes
    /// @param _owner The subscribing Puppet
    /// @param _allowances The allowance percentage array
    /// @param _subscriptionPeriods The subscription period array
    /// @param _traders The address array of Traders
    /// @param _routeTypeKeys The RouteType key array
    /// @param _subscribe Whether to subscribe or unsubscribe
    function batchSubscribeRoute(address _owner, uint256[] memory _allowances, uint256[] memory _subscriptionPeriods, address[] memory _traders, bytes32[] memory _routeTypeKeys, bool[] memory _subscribe) external;

    /// @notice The ```deposit``` function is called by a Puppet to deposit funds into his deposit account
    /// @param _amount The amount to deposit
    /// @param _asset The address of the Asset
    /// @param _puppet The address of the recepient
    function deposit(uint256 _amount, address _asset, address _puppet) external payable;

    /// @notice The ```withdraw``` function is called by a Puppet to withdraw funds from his deposit account
    /// @param _amount The amount to withdraw
    /// @param _asset The address of the Asset
    /// @param _receiver The address of the receiver of withdrawn funds
    /// @param _isETH Whether to withdraw ETH or not. Available only for WETH deposits
    function withdraw(uint256 _amount, address _asset, address _receiver, bool _isETH) external;

    /// @notice The ```setThrottleLimit``` function is called by a Puppet to set his throttle limit for a given RouteType
    /// @param _throttleLimit The throttle limit
    /// @param _routeType The RouteType key
    function setThrottleLimit(uint256 _throttleLimit, bytes32 _routeType) external;

    // Route

    /// @notice The ```debitPuppetAccount``` function is called by a Route to debit a Puppet's account
    /// @param _amount The amount to debit
    /// @param _asset The address of the Asset
    /// @param _puppet The address of the Puppet
    function debitPuppetAccount(uint256 _amount, address _asset, address _puppet) external;

    /// @notice The ```creditPuppetAccount``` function is called by a Route to credit a Puppet's account
    /// @param _amount The amount to credit
    /// @param _asset The address of the Asset
    /// @param _puppet The address of the Puppet
    function creditPuppetAccount(uint256 _amount, address _asset, address _puppet) external;

    /// @notice The ```updateLastPositionOpenedTimestamp``` function is called by a Route to update the last position opened timestamp of a Puppet
    /// @param _puppet The address of the Puppet
    /// @param _routeType The RouteType key
    function updateLastPositionOpenedTimestamp(address _puppet, bytes32 _routeType) external;

    /// @notice The ```transferRouteFunds``` function is called by a Route to send funds to a _receiver
    /// @param _amount The amount to send
    /// @param _asset The address of the Asset
    /// @param _receiver The address of the receiver
    function transferRouteFunds(uint256 _amount, address _asset, address _receiver) external;

    /// @notice The ```emitExecutionCallback``` function is called by a Route to emit an event on a GMX position execution callback
    /// @param performanceFeePaid The performance fee paid to Trader
    /// @param _requestKey The request key
    /// @param _isExecuted The boolean indicating if the request is executed
    /// @param _isIncrease The boolean indicating if the request is an increase or decrease request
    function emitExecutionCallback(uint256 performanceFeePaid, bytes32 _requestKey, bool _isExecuted, bool _isIncrease) external;

    /// @notice The ```emitSharesIncrease``` function is called by a Route to emit an event on a successful add collateral request
    /// @param _puppetsShares The array of Puppets shares, corresponding to the Route's subscribed Puppets, as stored in the Route Position struct
    /// @param _traderShares The Trader's shares, as stored in the Route Position struct
    /// @param _totalSupply The total supply of the Route's shares
    function emitSharesIncrease(uint256[] memory _puppetsShares, uint256 _traderShares, uint256 _totalSupply) external;

    // Authority

    // called by anyone

    /// @notice The ```withdrawPlatformFees``` function is called by anyone to withdraw platform fees
    /// @param _asset The address of the Asset
    /// @return _amount The amount withdrawn
    function withdrawPlatformFees(address _asset) external returns (uint256 _amount);

    // called by keeper

    /// @notice The ```adjustTargetLeverage``` function is called by a keeper to adjust mirrored position to target leverage to match trader leverage
    /// @param _adjustPositionParams The adjusment params for the position
    /// @param _executionFee The total execution fee, paid by the Keeper in ETH
    /// @param _routeKey The Route key
    /// @return _requestKey The request key
    function adjustTargetLeverage(IRoute.AdjustPositionParams memory _adjustPositionParams, uint256 _executionFee, bytes32 _routeKey) external payable returns (bytes32 _requestKey);

    /// @notice The ```liquidatePosition``` function is called by Puppet keepers to reset the Route's accounting in case of a liquidation
    /// @param _routeKey The Route key
    function liquidatePosition(bytes32 _routeKey) external;

    // called by owner

    /// @notice The ```rescueRouteFunds``` function is called by the Authority to rescue tokens from a Route
    /// @dev Route should never hold any funds, but this function is here just in case
    /// @param _amount The amount to rescue
    /// @param _token The address of the Token
    /// @param _receiver The address of the receiver
    /// @param _route The address of the Route
    function rescueRouteFunds(uint256 _amount, address _token, address _receiver, address _route) external;

    /// @notice The ```setMultiSubscriber``` function is called by the Authority to set the MultiSubscriber address
    /// @param _multiSubscriber The address of the new MultiSubscriber
    function serMultiSubscriber(address _multiSubscriber) external; 

    /// @notice The ```setRouteType``` function is called by the Authority to set a new RouteType
    /// @dev system doesn't support tokens that apply a fee/burn/rebase on transfer 
    /// @param _collateral The address of the Collateral Token
    /// @param _index The address of the Index Token
    /// @param _isLong The boolean value of the position
    function setRouteType(address _collateral, address _index, bool _isLong) external;

    /// @notice The ```setKeeper``` function is called by the Authority to set the Keeper address
    /// @param _keeperAddr The address of the new Keeper
    function setKeeper(address _keeperAddr) external;

    /// @notice The ```setScoreGauge``` function is called by the Authority to set the Score Gauge address
    /// @param _gauge The address of the new Score Gauge
    function setScoreGauge(address _gauge) external;

    /// @notice The ```setReferralCode``` function is called by the Authority to set the referral code
    /// @param _refCode The new referral code
    function setReferralCode(bytes32 _refCode) external;

    /// @notice The ```setFees``` function is called by the Authority to set the management and withdrawal fees
    /// @param _managmentFee The new management fee
    /// @param _withdrawalFee The new withdrawal fee
    /// @param _perfFee The new performance fee
    function setFees(uint256 _managmentFee, uint256 _withdrawalFee, uint256 _perfFee) external;

    /// @notice The ```setPlatformFeesRecipient``` function is called by the Authority to set the platform fees recipient
    /// @param _recipient The new platform fees recipient
    function setPlatformFeesRecipient(address _recipient) external;

    /// @notice The ```pause``` function is called by the Authority to pause all Routes
    /// @param _pause The new pause state
    function pause(bool _pause) external;

    // ============================================================================================
    // Events
    // ============================================================================================

    event RegisterRouteAccount(address indexed trader, address indexed route, bytes32 routeTypeKey);
    event SetRouteType(bytes32 routeTypeKey, address collateral, address index, bool isLong);

    event ApprovePlugin(address indexed caller, bytes32 routeTypeKey);
    event SubscribeRoute(bool subscribe, uint256 allowance, uint256 subscriptionExpiry, address indexed trader, address indexed puppet, address indexed route, bytes32 routeTypeKey, bool subscribe);
    event SetThrottleLimit(address indexed puppet, bytes32 routeType, uint256 throttleLimit);

    event UpdateOpenTimestamp(address indexed puppet, bytes32 routeType, uint256 timestamp);
    
    event Deposit(uint256 amount, address asset, address caller, address indexed puppet);
    event Withdraw(uint256 amount, address asset, address indexed receiver, address indexed puppet);

    event AdjustPosition(address indexed trader, address indexed route, bool isIncrease, bytes32 requestKey, bytes32 routeTypeKey, bytes32 positionKey); 
    event OpenPosition(address[] puppets, address indexed trader, address indexed route, bool isIncrease, bytes32 requestKey, bytes32 routeTypeKey, bytes32 positionKey);
    event ExecutePosition(uint256 performanceFeePaid, address indexed route, bytes32 requestKey, bool isExecuted, bool isIncrease);
    event SharesIncrease(uint256[] puppetsShares, uint256 traderShares, uint256 totalSupply, bytes32 positionKey);
    event AdjustTargetLeverage(address indexed route, bytes32 requestKey, bytes32 routeKey, bytes32 positionKey);
    event LiquidatePosition(address indexed route, bytes32 routeKey, bytes32 positionKey);

    event DebitPuppet(uint256 amount, address asset, address indexed puppet, address indexed caller);
    event CreditPlatform(uint256 amount, address asset, address puppet, address caller, bool isWithdraw);
    event CreditPuppet(uint256 amount, address asset, address indexed puppet, address indexed caller);

    event TransferRouteFunds(uint256 amount, address asset, address indexed receiver, address indexed caller);
    event Pause(bool paused);
    event SetReferralCode(bytes32 referralCode);
    event WithdrawPlatformFees(uint256 amount, address asset, address caller, address platformFeeRecipient);
    event SetFees(uint256 managmentFee, uint256 withdrawalFee, uint256 performanceFee);
    event SetFeesRecipient(address recipient);
    event SetKeeper(address keeper);
    event SetScoreGauge(address scoreGauge);
    event RescueRouteFunds(uint256 amount, address token, address indexed receiver, address indexed route);
    event SetMultiSubscriber(address multiSubscriber);

    // ============================================================================================
    // Errors
    // ============================================================================================

    error NotRoute();
    error RouteTypeNotRegistered();
    error RouteAlreadyRegistered();
    error MismatchedInputArrays();
    error RouteNotRegistered();
    error InvalidAllowancePercentage();
    error InvalidSubscriptionPeriod();
    error InvalidAmount();
    error InvalidAsset();
    error ZeroAddress();
    error ZeroAmount();
    error Paused();
    error FeeExceedsMax();
    error ZeroBytes32();
    error RouteWaitingForCallback();
    error FunctionCallPastDeadline();
    error NotWhitelisted();
}