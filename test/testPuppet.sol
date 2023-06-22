// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {AggregatorV3Interface} from "@chainlink/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Auth, Authority} from "@solmate/auth/Auth.sol";

import {Orchestrator} from "src/Orchestrator.sol";
import {Route} from "src/Route.sol";
import {RouteFactory} from "src/RouteFactory.sol";
import {Dictator} from "src/Dictator.sol";
import {IRoute} from "src/interfaces/IRoute.sol";

import {IOrchestrator} from "src/interfaces/IOrchestrator.sol";

import {IGMXVault} from "src/interfaces/IGMXVault.sol";
import {IGMXReader} from "src/interfaces/IGMXReader.sol";
import {IGMXPositionRouter} from "src/interfaces/IGMXPositionRouter.sol";
import {IVault} from "src/interfaces/IVault.sol";

contract testPuppet is Test {

    using SafeERC20 for IERC20;

    struct GMXInfo {
        address gmxRouter;
        address gmxReader;
        address gmxVault;
        address gmxPositionRouter;
        address gmxReferralRebatesSender;
    }

     struct CreatePositionParams {
        IRoute.AdjustPositionParams adjustPositionParams;
        IRoute.SwapParams swapParams;
        uint256 amountInTrader;
        uint256 executionFee;
        uint256 positionIndexBefore;
        address tokenIn;
        bytes32 routeTypeKey;
    }

    struct IncreaseBalanceBefore {
        uint256 aliceDepositAccountBalanceBefore;
        uint256 bobDepositAccountBalanceBefore;
        uint256 yossiDepositAccountBalanceBefore;
        uint256 orchestratorBalanceBefore;
        uint256 traderBalanceBeforeCollatToken;
        uint256 traderBalanceBeforeEth;
        uint256 alicePositionSharesBefore;
        uint256 bobPositionSharesBefore;
        uint256 yossiPositionSharesBefore;
        uint256 traderPositionSharesBefore;
        uint256 positionIndexBefore;
    }

    struct CreatePositionFirst {
        uint256 orchesratorBalanceBefore;
        uint256 aliceDepositAccountBalanceBefore;
        uint256 bobDepositAccountBalanceBefore;
        uint256 yossiDepositAccountBalanceBefore;
        address tokenIn;
        bytes32 routeTypeKey;
    }

    struct RouteTypeInfo {
        address collateralToken;
        address indexToken;
        bool isLong;
        bytes32 routeTypeKey;
    }

    struct ClosePositionBefore {
        uint256 traderBalanceBefore;
        uint256 aliceDepositAccountBalanceBefore;
        uint256 bobDepositAccountBalanceBefore;
        uint256 yossiDepositAccountBalanceBefore;
        uint256 orchesratorBalanceBefore;
        uint256 positionIndexBefore;
    }

    address owner = makeAddr("owner");
    address trader = makeAddr("trader");
    address keeper = makeAddr("keeper");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address yossi = makeAddr("yossi");

    address collateralToken = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1); // WETH
    address indexToken = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1); // WETH

    address gmxVault = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
    address gmxPositionRouter = 0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868;
    address gmxRouter = 0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064;
    address GMXPositionRouterKeeper = address(0x11D62807dAE812a0F1571243460Bf94325F43BB7);
    address revenueDistributor;

    bool isLong = true;
    
    uint256 arbitrumFork;

    Route route;
    Orchestrator orchestrator;

    AggregatorV3Interface priceFeed;

    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant WETH = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address constant FRAX = address(0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F);
    address constant USDC = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);

    function setUp() public {

        string memory ARBITRUM_RPC_URL = vm.envString("ARBITRUM_RPC_URL");
        arbitrumFork = vm.createFork(ARBITRUM_RPC_URL);
        vm.selectFork(arbitrumFork);

        vm.deal(owner, 100 ether);
        vm.deal(trader, 100 ether);
        vm.deal(keeper, 100 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(yossi, 100 ether);

        Dictator _dictator = new Dictator(owner);
        RouteFactory _routeFactory = new RouteFactory();

        bytes memory _gmxInfo = abi.encode(gmxRouter, gmxVault, gmxPositionRouter);

        orchestrator = new Orchestrator(_dictator, address(_routeFactory), address(0), bytes32(0), _gmxInfo);

        bytes4 functionSig = orchestrator.setRouteType.selector;
        bytes4 functionSig2 = orchestrator.decreaseSize.selector;
        bytes4 functionSig3 = orchestrator.liquidate.selector;

        vm.startPrank(owner);
        _setRoleCapability(_dictator, 0, address(orchestrator), functionSig, true);
        _setRoleCapability(_dictator, 1, address(orchestrator), functionSig2, true);
        _setRoleCapability(_dictator, 1, address(orchestrator), functionSig3, true);

        _setUserRole(_dictator, owner, 0, true);
        _setUserRole(_dictator, keeper, 1, true);

        orchestrator.setRouteType(WETH, WETH, true);
        orchestrator.setRouteType(USDC, WETH, false);
        vm.stopPrank();
    }

    function testCorrectFlow() public {
        uint256 _assets = 1 ether;

        collateralToken = WETH;
        indexToken = WETH;
        isLong = true;

        // trader
        bytes32 _routeKey = _testRegisterRoute(WETH, WETH, true);
        bytes32 _routeTypeKey = orchestrator.getRouteTypeKey(WETH, WETH, true);

        route = Route(payable(orchestrator.getRoute(_routeKey)));

        // puppet
        _testPuppetDeposit(_assets, WETH);
        _testUpdateRoutesSubscription(WETH, WETH, _routeKey, true);
        _testSetThrottleLimit(_routeTypeKey);
        _testPuppetWithdraw(_assets, WETH);

        RouteTypeInfo memory _routeTypeInfo = RouteTypeInfo(WETH, WETH, true, _routeTypeKey);

        // route
        _testIncreasePosition(_routeTypeInfo, false, false);
        _testIncreasePosition(_routeTypeInfo, true, false);
        _testClosePosition(_routeTypeKey, false);

        // puppet
        _testRemoveRouteSubscription(WETH, WETH, true);
    }

    function testNonCollateralAmountIn() public {
        uint256 _assets = 1 ether;

        collateralToken = WETH;
        indexToken = WETH;
        isLong = true;

        // trader
        bytes32 _routeKey = _testRegisterRoute(WETH, WETH, true);
        bytes32 _routeTypeKey = orchestrator.getRouteTypeKey(WETH, WETH, true);

        route = Route(payable(orchestrator.getRoute(_routeKey)));

        // puppet
        _testPuppetDeposit(_assets, WETH);
        _testUpdateRoutesSubscription(WETH, WETH, _routeKey, true);
        _testSetThrottleLimit(_routeTypeKey);
        _testPuppetWithdraw(_assets, WETH);

        RouteTypeInfo memory _routeTypeInfo = RouteTypeInfo(WETH, WETH, true, _routeTypeKey);

        // route
        _testIncreasePosition(_routeTypeInfo, false, false);
        _testIncreasePosition(_routeTypeInfo, false, true);
        _testClosePosition(_routeTypeKey, false);
    }

    function testAuthFunctions() public {
        uint256 _assets = 1 ether;

        collateralToken = WETH;
        indexToken = WETH;
        isLong = true;

        // trader
        bytes32 _routeKey = _testRegisterRoute(WETH, WETH, true);
        bytes32 _routeTypeKey = orchestrator.getRouteTypeKey(WETH, WETH, true);

        route = Route(payable(orchestrator.getRoute(_routeKey)));

        // puppet
        _testPuppetDeposit(_assets, WETH);
        _testUpdateRoutesSubscription(WETH, WETH, _routeKey, true);

        RouteTypeInfo memory _routeTypeInfo = RouteTypeInfo(WETH, WETH, true, _routeTypeKey);

        // route
        _testIncreasePosition(_routeTypeInfo, false, false);
        _testIncreasePosition(_routeTypeInfo, true, false); // todo

        // auth
        _testClosePosition(_routeTypeKey, true);
        _testAuthLiquidate(_routeKey);
    }

    function testRegisterRouteAndIncreasePosition() public {
        _testRegisterRouteAndIncreasePosition();
    }

    function testUSDCCorrectFlow() public {
        uint256 _assets = 1 ether;
        collateralToken = USDC;
        indexToken = WETH;
        isLong = false;

        // trader
        bytes32 _routeKey = _testRegisterRoute(USDC, WETH, false);
        bytes32 _routeTypeKey = orchestrator.getRouteTypeKey(USDC, WETH, false);

        route = Route(payable(orchestrator.getRoute(_routeKey)));

        // puppet
        _testPuppetDeposit(_assets, USDC);
        _testUpdateRoutesSubscription(USDC, WETH, _routeKey, false);
        _testSetThrottleLimit(_routeTypeKey);
        _testPuppetWithdraw(_assets, USDC);

        RouteTypeInfo memory _routeTypeInfo = RouteTypeInfo(USDC, WETH, false, _routeTypeKey);

        // route
        _testIncreasePosition(_routeTypeInfo, false, false);
        _testIncreasePosition(_routeTypeInfo, true, false);
        _testClosePosition(_routeTypeKey, false);

        // puppet
        _testRemoveRouteSubscription(USDC, WETH, false);
    }

    // ============================================================================================
    // Internal Test Functions
    // ============================================================================================

    //
    // orchestrator
    //

    // Trader

    function _testRegisterRoute(address _collateralToken, address _indexToken, bool _isLong) internal returns (bytes32 _routeKey) {
        vm.startPrank(trader);

        vm.expectRevert(); // reverts with ZeroAddress()
        orchestrator.registerRoute(address(0), address(0), true);

        vm.expectRevert(); // reverts with NoPriceFeedForAsset()
        orchestrator.registerRoute(FRAX, WETH, true);

        _routeKey = orchestrator.registerRoute(_collateralToken, _indexToken, _isLong);

        vm.expectRevert(); // reverts with RouteAlreadyRegistered()
        orchestrator.registerRoute(_collateralToken, _indexToken, _isLong);

        address[] memory _pupptsForRoute = orchestrator.subscribedPuppets(_routeKey);

        address payable _route = payable(orchestrator.getRoute(_routeKey));

        bytes32 _routeTypeKey = orchestrator.getRouteTypeKey(_collateralToken, _indexToken, _isLong);
        assertEq(_routeKey, orchestrator.getRouteKey(trader, _routeTypeKey), "_testRegisterRoute: E0");
        assertEq(_pupptsForRoute.length, 0, "_testRegisterRoute: E1");
        assertEq(orchestrator.isRoute(_route), true, "_testRegisterRoute: E2");
        address[] memory _routes = orchestrator.routes();
        assertEq(_routes[0], _route, "_testRegisterRoute: E3");
        assertEq(address(Route(_route).orchestrator()), address(orchestrator), "_testRegisterRoute: E4");
        vm.stopPrank();
    }

    // Puppet

    function _testPuppetDeposit(uint256 _assets, address _token) internal {
        _dealERC20(_token, alice, _assets);
        _dealERC20(_token, bob, _assets);
        _dealERC20(_token, yossi, _assets);

        uint256 _balanceBefore = IERC20(_token).balanceOf(address(orchestrator));

        // alice
        uint256 _aliceBalanceBeforeETH = address(alice).balance;
        uint256 _aliceBalanceBefore = IERC20(_token).balanceOf(address(alice));
        vm.startPrank(alice);

        vm.expectRevert(); // reverts with NoPriceFeedForCollateralToken()
        orchestrator.deposit{ value: _assets }(_assets, FRAX, alice);
        
        uint256 _puppetAssetsBefore = orchestrator.puppetAccountBalance(bob, _token);
        if (_token == WETH) {
            orchestrator.deposit{ value: _assets }(_assets, _token, alice);
            assertEq(_aliceBalanceBeforeETH - _assets, address(alice).balance, "_testPuppetDeposit: E1");
        } else {
            _approve(address(orchestrator), _token, _assets);
            orchestrator.deposit(_assets, _token, alice);
            assertEq(_aliceBalanceBefore - _assets, IERC20(_token).balanceOf(alice), "_testPuppetDeposit: E01");
        }
        
        assertEq(orchestrator.puppetAccountBalance(alice, _token), _puppetAssetsBefore + _assets, "_testPuppetDeposit: E0");
        vm.stopPrank();

        // bob
        uint256 _bobBalanceBefore = IERC20(_token).balanceOf(bob);
        vm.startPrank(bob);
        _approve(address(orchestrator), _token, _assets);
        _puppetAssetsBefore = orchestrator.puppetAccountBalance(bob, _token);
        orchestrator.deposit(_assets, _token, bob);
        assertEq(orchestrator.puppetAccountBalance(bob, _token), _puppetAssetsBefore + _assets, "_testPuppetDeposit: E2");
        assertEq(_bobBalanceBefore - _assets, IERC20(_token).balanceOf(bob), "_testPuppetDeposit: E3");
        vm.stopPrank();

        // yossi
        uint256 _yossiBalanceBefore = IERC20(_token).balanceOf(yossi);
        vm.startPrank(yossi);
        _approve(address(orchestrator), _token, _assets);
        _puppetAssetsBefore = orchestrator.puppetAccountBalance(yossi, _token);
        orchestrator.deposit(_assets, _token, yossi);
        assertEq(orchestrator.puppetAccountBalance(yossi, _token), _puppetAssetsBefore + _assets, "_testPuppetDeposit: E4");
        assertEq(_yossiBalanceBefore - _assets, IERC20(_token).balanceOf(yossi), "_testPuppetDeposit: E5");
        vm.stopPrank();

        assertEq(IERC20(_token).balanceOf(address(orchestrator)) - _balanceBefore, _assets * 3, "_testPuppetDeposit: E3");
        assertTrue(IERC20(_token).balanceOf(address(orchestrator)) - _balanceBefore > 0, "_testPuppetDeposit: E4");
    }

    function _testUpdateRoutesSubscription(address _collateralToken, address _indexToken, bytes32 _routeKey, bool _isLong) internal {
        uint256[] memory _allowances = new uint256[](1);
        address[] memory _traders = new address[](1);
        bytes32[] memory _routeTypeKeys = new bytes32[](1);
        bool[] memory _subscribe = new bool[](1);

        bytes32 _routeTypeKey = orchestrator.getRouteTypeKey(_collateralToken, _indexToken, _isLong);
        address _route = orchestrator.getRoute(_routeKey);

        _traders[0] = trader;
        _allowances[0] = 1000; // 10% of the puppet's deposit account
        _routeTypeKeys[0] = _routeTypeKey;
        _subscribe[0] = true;

        uint256[] memory _faultyAllowance = new uint256[](1);
        _faultyAllowance[0] = 10001;
        address[] memory _faultyTraders = new address[](2);
        _faultyTraders[0] = alice;
        _faultyTraders[1] = bob;
        bytes32[] memory _faultyRouteTypeKeys = new bytes32[](2);
        _faultyRouteTypeKeys[0] = orchestrator.getRouteTypeKey(FRAX, WETH, true);

        vm.startPrank(alice);

        vm.expectRevert(); // reverts with MismatchedInputArrays()
        orchestrator.updateRoutesSubscriptions(_allowances, _faultyTraders, _routeTypeKeys, _subscribe);

        vm.expectRevert(); // reverts with InvalidAllowancePercentage()
        orchestrator.updateRoutesSubscriptions(_faultyAllowance, _traders, _routeTypeKeys, _subscribe);

        vm.expectRevert(); // reverts with RouteNotRegistered()
        orchestrator.updateRoutesSubscriptions(_allowances, _traders, _faultyRouteTypeKeys, _subscribe);

        {
            address[] memory _subscriptions = orchestrator.puppetSubscriptions(alice);
            assertEq(_subscriptions.length, 0, "_testUpdateRoutesSubscription: E00");
        }
        {
            address[] memory _subscriptions = orchestrator.puppetSubscriptions(bob);
            assertEq(_subscriptions.length, 0, "_testUpdateRoutesSubscription: E01");
        }
        {
            address[] memory _subscriptions = orchestrator.puppetSubscriptions(yossi);
            assertEq(_subscriptions.length, 0, "_testUpdateRoutesSubscription: E02");
        }

        orchestrator.updateRoutesSubscriptions(_allowances, _traders, _routeTypeKeys, _subscribe);
        assertEq(orchestrator.puppetAllowancePercentage(alice, _route), _allowances[0], "_testUpdateRoutesSubscription: E0");
        assertEq(orchestrator.subscribedPuppets(_routeKey)[0], alice, "_testUpdateRoutesSubscription: E1");
        assertEq(orchestrator.subscribedPuppets(_routeKey).length, 1, "_testUpdateRoutesSubscription: E2");
        vm.stopPrank();

        {
            address[] memory _subscriptions = orchestrator.puppetSubscriptions(alice);
            assertEq(_subscriptions.length, 1, "_testUpdateRoutesSubscription: E00");
            assertEq(_subscriptions[0], _route, "_testUpdateRoutesSubscription: E01");
        }

        vm.startPrank(bob);
        orchestrator.updateRoutesSubscriptions(_allowances, _traders, _routeTypeKeys, _subscribe);
        assertEq(orchestrator.puppetAllowancePercentage(bob, _route), _allowances[0], "_testUpdateRoutesSubscription: E3");
        assertEq(orchestrator.subscribedPuppets(_routeKey)[1], bob, "_testUpdateRoutesSubscription: E4");
        assertEq(orchestrator.subscribedPuppets(_routeKey).length, 2, "_testUpdateRoutesSubscription: E5");
        // again
        orchestrator.updateRoutesSubscriptions(_allowances, _traders, _routeTypeKeys, _subscribe);
        assertEq(orchestrator.puppetAllowancePercentage(bob, _route), _allowances[0], "_testUpdateRoutesSubscription: E03");
        assertEq(orchestrator.subscribedPuppets(_routeKey)[1], bob, "_testUpdateRoutesSubscription: E04");
        assertEq(orchestrator.subscribedPuppets(_routeKey).length, 2, "_testUpdateRoutesSubscription: E05");
        vm.stopPrank();

        {
            address[] memory _subscriptions = orchestrator.puppetSubscriptions(bob);
            assertEq(_subscriptions.length, 1, "_testUpdateRoutesSubscription: E005");
            assertEq(_subscriptions[0], _route, "_testUpdateRoutesSubscription: E006");
        }

        vm.startPrank(yossi);
        orchestrator.updateRoutesSubscriptions(_allowances, _traders, _routeTypeKeys, _subscribe);
        assertEq(orchestrator.puppetAllowancePercentage(yossi, _route), _allowances[0], "_testUpdateRoutesSubscription: E6");
        assertEq(orchestrator.subscribedPuppets(_routeKey)[2], yossi, "_testUpdateRoutesSubscription: E7");
        assertEq(orchestrator.subscribedPuppets(_routeKey).length, 3, "_testUpdateRoutesSubscription: E8");
        vm.stopPrank();

        {
            address[] memory _subscriptions = orchestrator.puppetSubscriptions(yossi);
            assertEq(_subscriptions.length, 1, "_testUpdateRoutesSubscription: E007");
            assertEq(_subscriptions[0], _route, "_testUpdateRoutesSubscription: E008");
        }

        assertTrue(orchestrator.puppetAllowancePercentage(alice, _route) > 0, "_testUpdateRoutesSubscription: E9");
        assertTrue(orchestrator.puppetAllowancePercentage(bob, _route) > 0, "_testUpdateRoutesSubscription: E10");
        assertTrue(orchestrator.puppetAllowancePercentage(yossi, _route) > 0, "_testUpdateRoutesSubscription: E11");
    }

    function _testRemoveRouteSubscription(address _collateralToken, address _indexToken, bool _isLong) internal {
        uint256[] memory _allowances = new uint256[](1);
        address[] memory _traders = new address[](1);
        bytes32[] memory _routeTypeKeys = new bytes32[](1);
        bool[] memory _subscribe = new bool[](1);

        bytes32 _routeTypeKey = orchestrator.getRouteTypeKey(_collateralToken, _indexToken, _isLong);

        _traders[0] = trader;
        _allowances[0] = 1000; // 10% of the puppet's deposit account
        _routeTypeKeys[0] = _routeTypeKey;
        _subscribe[0] = false;

        address[] memory _aliceSubscriptionsBefore = orchestrator.puppetSubscriptions(alice);
        address[] memory _bobSubscriptionsBefore = orchestrator.puppetSubscriptions(bob);
        address[] memory _yossiSubscriptionsBefore = orchestrator.puppetSubscriptions(yossi);

        assertTrue(_aliceSubscriptionsBefore.length > 0, "_testRemoveRouteSubscription: E0");
        assertTrue(_bobSubscriptionsBefore.length > 0, "_testRemoveRouteSubscription: E1");
        assertTrue(_yossiSubscriptionsBefore.length > 0, "_testRemoveRouteSubscription: E2");

        vm.startPrank(alice);
        orchestrator.updateRoutesSubscriptions(_allowances, _traders, _routeTypeKeys, _subscribe);
        vm.stopPrank();

        vm.startPrank(bob);
        orchestrator.updateRoutesSubscriptions(_allowances, _traders, _routeTypeKeys, _subscribe);
        vm.stopPrank();

        vm.startPrank(yossi);
        orchestrator.updateRoutesSubscriptions(_allowances, _traders, _routeTypeKeys, _subscribe);
        vm.stopPrank();

        {
            address[] memory _aliceSubscriptionsAfter = orchestrator.puppetSubscriptions(alice);
            address[] memory _bobSubscriptionsAfter = orchestrator.puppetSubscriptions(bob);
            address[] memory _yossiSubscriptionsAfter = orchestrator.puppetSubscriptions(yossi);

            assertEq(_aliceSubscriptionsAfter.length, _aliceSubscriptionsBefore.length - 1, "_testRemoveRouteSubscription: E3");
            assertEq(_bobSubscriptionsAfter.length, _bobSubscriptionsBefore.length - 1, "_testRemoveRouteSubscription: E4");
            assertEq(_yossiSubscriptionsAfter.length, _yossiSubscriptionsBefore.length - 1, "_testRemoveRouteSubscription: E5");
        }
    }

    function _testSetThrottleLimit(bytes32 _routeTypeKey) internal {

        vm.startPrank(alice);
        orchestrator.setThrottleLimit(1 days, _routeTypeKey);
        assertEq(orchestrator.puppetThrottleLimit(alice, _routeTypeKey), 1 days, "_testSetThrottleLimit: E0");
        vm.stopPrank();

        vm.startPrank(bob);
        orchestrator.setThrottleLimit(2 days, _routeTypeKey);
        assertEq(orchestrator.puppetThrottleLimit(bob, _routeTypeKey), 2 days, "_testSetThrottleLimit: E1");
        vm.stopPrank();

        vm.startPrank(yossi);
        orchestrator.setThrottleLimit(3 days, _routeTypeKey);
        assertEq(orchestrator.puppetThrottleLimit(yossi, _routeTypeKey), 3 days, "_testSetThrottleLimit: E2");
        vm.stopPrank();
    }

    function _testPuppetWithdraw(uint256 _assets, address _token) internal {
        uint256 _aliceDepositAccountBalanceBefore = orchestrator.puppetAccountBalance(alice, _token);
        uint256 _bobDepositAccountBalanceBefore = orchestrator.puppetAccountBalance(bob, _token);
        uint256 _yossiDepositAccountBalanceBefore = orchestrator.puppetAccountBalance(yossi, _token);

        _testPuppetDeposit(_assets, _token);

        vm.startPrank(alice);
        uint256 _orchestratorBalanceBefore = IERC20(_token).balanceOf(address(orchestrator));
        uint256 _puppetBalanceBefore = IERC20(_token).balanceOf(alice);
        orchestrator.withdraw(_assets, _token, alice, false);
        uint256 _puppetBalanceAfter = IERC20(_token).balanceOf(alice);
        uint256 _orchestratorBalanceAfter = IERC20(_token).balanceOf(address(orchestrator));
        vm.stopPrank();

        assertEq(_orchestratorBalanceBefore - _orchestratorBalanceAfter, _assets, "_testPuppetWithdraw: E0");
        assertEq(orchestrator.puppetAccountBalance(alice, _token), _aliceDepositAccountBalanceBefore, "_testPuppetWithdraw: E1");
        assertEq(_puppetBalanceBefore + _assets, _puppetBalanceAfter, "_testPuppetWithdraw: E2");

        vm.startPrank(bob);
        _orchestratorBalanceBefore = IERC20(_token).balanceOf(address(orchestrator));
        _puppetBalanceBefore = IERC20(_token).balanceOf(bob);
        orchestrator.withdraw(_assets, _token, bob, false);
        _puppetBalanceAfter = IERC20(_token).balanceOf(bob);
        _orchestratorBalanceAfter = IERC20(_token).balanceOf(address(orchestrator));
        vm.stopPrank();

        assertEq(_orchestratorBalanceBefore - _orchestratorBalanceAfter, _assets, "_testPuppetWithdraw: E3");
        assertEq(orchestrator.puppetAccountBalance(bob, _token), _bobDepositAccountBalanceBefore, "_testPuppetWithdraw: E4");
        assertEq(_puppetBalanceBefore + _assets, _puppetBalanceAfter, "_testPuppetWithdraw: E5");

        vm.startPrank(yossi);
        _orchestratorBalanceBefore = IERC20(_token).balanceOf(address(orchestrator));
        if (_token == WETH) {
            _puppetBalanceBefore = address(yossi).balance;
            orchestrator.withdraw(_assets, _token, yossi, true);
            _puppetBalanceAfter = address(yossi).balance;
        } else {
            _puppetBalanceBefore = IERC20(_token).balanceOf(yossi);
            orchestrator.withdraw(_assets, _token, yossi, false);
            _puppetBalanceAfter = IERC20(_token).balanceOf(yossi);
        }
        _orchestratorBalanceAfter = IERC20(_token).balanceOf(address(orchestrator));
        vm.stopPrank();

        assertEq(_orchestratorBalanceBefore - _orchestratorBalanceAfter, _assets, "_testPuppetWithdraw: E6");
        assertEq(orchestrator.puppetAccountBalance(yossi, _token), _yossiDepositAccountBalanceBefore, "_testPuppetWithdraw: E7");
        assertEq(_puppetBalanceBefore + _assets, _puppetBalanceAfter, "_testPuppetWithdraw: E8");
    }

    //
    // Route
    //

    // open position
    // add collateral + increase size
    // trader adds ETH collateral
    function _testIncreasePosition(RouteTypeInfo memory _routeTypeInfo, bool _addCollateralToAnExistingPosition, bool _testNonCollateralTraderAmountIn) internal {
        uint256 _minOut = 0; // _minOut can be zero if no swap is required
        uint256 _executionFee = 180000000000000; // can be set to PositionRouter.minExecutionFee() https://arbiscan.io/address/0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868#readContract#F26

        uint256 _sizeDelta;
        uint256 _amountInTrader;
        uint256 _acceptablePrice; // the USD value of the max (for longs) or min (for shorts) index price acceptable when executing the request
        if (_routeTypeInfo.isLong) {
            // TODO: long position
            // Available amount in USD: PositionRouter.maxGlobalLongSizes(indexToken) - Vault.guaranteedUsd(indexToken)
            _sizeDelta =  36751139216995468418460853833822170677 - IVault(orchestrator.gmxVault()).guaranteedUsd(indexToken);
            _sizeDelta = _sizeDelta / 20;
            _acceptablePrice = type(uint256).max;
            _amountInTrader = 1 ether;
            // _amountInTrader = _sizeDelta / 2000 
        } else {
            // TODO: short position
            // Available amount in USD: PositionRouter.maxGlobalShortSizes(indexToken) - Vault.globalShortSizes(indexToken)
            _sizeDelta = 34970255953895708427749126867602519944 - IVault(orchestrator.gmxVault()).globalShortSizes(indexToken);
            _sizeDelta = _sizeDelta / 50;
            _acceptablePrice = type(uint256).min;
            _amountInTrader = _sizeDelta / 5 / 1e24;
        }

        // the USD value of the change in position size
        // _sizeDelta = _sizeDelta / 50;

        address[] memory _path = new address[](1);

        IRoute.AdjustPositionParams memory _adjustPositionParams = IRoute.AdjustPositionParams({
            // amountIn: _amountInTrader,
            collateralDelta: 0,
            sizeDelta: _sizeDelta,
            acceptablePrice: _acceptablePrice,
            minOut: _minOut
        });

        _path[0] = _routeTypeInfo.collateralToken;
        IRoute.SwapParams memory _swapParams = IRoute.SwapParams({
            path: _path,
            amount: _amountInTrader,
            minOut: _minOut
        });

        assertEq(orchestrator.paused(), false, "_testCreateInitialPosition: E0");

        vm.expectRevert(); // reverts with NotOrchestrator()
        route.requestPosition{ value: _amountInTrader + _executionFee }(_adjustPositionParams, _swapParams, _executionFee, true);

        vm.startPrank(trader);

        vm.expectRevert(); // reverts with NotOrchestrator()
        route.requestPosition{ value: _amountInTrader + _executionFee }(_adjustPositionParams, _swapParams, _executionFee, true);

        if (_testNonCollateralTraderAmountIn) {
            _testNonCollatAmountIn(_amountInTrader, _executionFee, _adjustPositionParams, _routeTypeInfo.routeTypeKey);
            return; // just want to test the swap
        }

        vm.expectRevert(); // reverts with InvalidExecutionFee()
        orchestrator.requestPosition{ value: _amountInTrader + _executionFee + 10 }(_adjustPositionParams, _swapParams, _routeTypeInfo.routeTypeKey, _executionFee, true);

        if (!_addCollateralToAnExistingPosition) {
            assertEq(orchestrator.lastPositionOpenedTimestamp(alice, _routeTypeInfo.routeTypeKey), 0, "_testCreateInitialPosition: E3");
            assertEq(orchestrator.lastPositionOpenedTimestamp(bob, _routeTypeInfo.routeTypeKey), 0, "_testCreateInitialPosition: E4");
            assertEq(orchestrator.lastPositionOpenedTimestamp(yossi, _routeTypeInfo.routeTypeKey), 0, "_testCreateInitialPosition: E5");
        }

        vm.stopPrank();

        CreatePositionParams memory _params = CreatePositionParams({
            adjustPositionParams: _adjustPositionParams,
            swapParams: _swapParams,
            amountInTrader: _amountInTrader,
            executionFee: _executionFee,
            positionIndexBefore: route.positionIndex(),
            tokenIn: _routeTypeInfo.collateralToken,
            routeTypeKey: _routeTypeInfo.routeTypeKey
        });

        _testCreateIncreasePosition(_params, _addCollateralToAnExistingPosition);
    }

    function _testCreateIncreasePosition(CreatePositionParams memory _params, bool _addCollateralToAnExistingPosition) internal {

        _dealERC20(_params.tokenIn, trader, _params.amountInTrader);
        
        IncreaseBalanceBefore memory _increaseBalanceBefore = IncreaseBalanceBefore({
            aliceDepositAccountBalanceBefore: orchestrator.puppetAccountBalance(alice, _params.tokenIn),
            bobDepositAccountBalanceBefore: orchestrator.puppetAccountBalance(bob, _params.tokenIn),
            yossiDepositAccountBalanceBefore: orchestrator.puppetAccountBalance(yossi, _params.tokenIn),
            orchestratorBalanceBefore: IERC20(_params.tokenIn).balanceOf(address(orchestrator)),
            traderBalanceBeforeCollatToken: IERC20(_params.tokenIn).balanceOf(trader),
            traderBalanceBeforeEth: address(trader).balance,
            alicePositionSharesBefore: route.participantShares(alice),
            bobPositionSharesBefore: route.participantShares(bob),
            yossiPositionSharesBefore: route.participantShares(yossi),
            traderPositionSharesBefore: route.participantShares(trader),
            positionIndexBefore: route.positionIndex()
        });

        // (uint256 _addCollateralRequestsIndexBefore,,) = route.positions(route.positionIndex());
        // uint256 _positionIndexBefore = route.positionIndex();

        bytes32 _requestKey = _testCreatePosition(_params, _addCollateralToAnExistingPosition);
        if (!_addCollateralToAnExistingPosition) {
            assertTrue(IERC20(_params.tokenIn).balanceOf(address(orchestrator)) < _increaseBalanceBefore.orchestratorBalanceBefore, "_testCreateInitialPosition: E05");
            assertTrue(orchestrator.puppetAccountBalance(alice, _params.tokenIn) < _increaseBalanceBefore.aliceDepositAccountBalanceBefore, "_testCreateInitialPosition: E0000006");
            assertTrue(orchestrator.puppetAccountBalance(bob, _params.tokenIn) < _increaseBalanceBefore.bobDepositAccountBalanceBefore, "_testCreateInitialPosition: E07");
            assertTrue(orchestrator.puppetAccountBalance(yossi, _params.tokenIn) < _increaseBalanceBefore.yossiDepositAccountBalanceBefore, "_testCreateInitialPosition: E08");
        }

        vm.expectRevert(); // reverts with NotCallbackCaller()
        route.gmxPositionCallback(_requestKey, true, true);

        (,uint256 _collateralInPositionGMXBefore,,,,,,) = IGMXVault(gmxVault).getPosition(address(route), collateralToken, indexToken, isLong);

        uint256[] memory _allowances = new uint256[](1);
        address[] memory _traders = new address[](1);
        _traders[0] = trader;
        _allowances[0] = 10; // 10% of the puppet's deposit account

        {
            bytes32[] memory _routeTypeKeys = new bytes32[](1);
            _routeTypeKeys[0] = _params.routeTypeKey;

            bool[] memory _subscribe = new bool[](1);
            _subscribe[0] = true;

            vm.startPrank(alice);
            vm.expectRevert(); // reverts with RouteWaitingForCallback()
            orchestrator.updateRoutesSubscriptions(_allowances, _traders, _routeTypeKeys, _subscribe);
            vm.stopPrank();
        }

        assertEq(route.isWaitingForCallback(), true, "_testCreateInitialPosition: E100");

        // 2. executePosition
        vm.startPrank(GMXPositionRouterKeeper); // keeper
        IGMXPositionRouter(gmxPositionRouter).executeIncreasePositions(type(uint256).max, payable(address(route)));
        vm.stopPrank();

        assertEq(route.isWaitingForCallback(), false, "_testCreateInitialPosition: E101");

        // (uint256 _addCollateralRequestsIndexAfter,,) = route.positions(route.positionIndex());
        uint256 _positionIndexAfter = route.positionIndex();

        assertEq(address(route).balance, 0, "_testCreateInitialPosition: E007");
        assertEq(IERC20(WETH).balanceOf(address(route)), 0, "_testCreateInitialPosition: E008");

        (,uint256 _totalSupply, uint256 _totalAssets) = route.positions(route.positionIndex());
        if (!_addCollateralToAnExistingPosition) {
            if (_isOpenInterest(address(route))) {
                assertTrue(!route.keeperRequests(_requestKey), "_testCreateInitialPosition: E006");
                assertEq(_increaseBalanceBefore.positionIndexBefore + 1, _positionIndexAfter, "_testCreateInitialPosition: E0007");
                assertApproxEqAbs(address(trader).balance, _increaseBalanceBefore.traderBalanceBeforeEth - _params.executionFee, 1e18, "_testCreateInitialPosition: E009");
                assertApproxEqAbs(IERC20(_params.tokenIn).balanceOf(trader), _increaseBalanceBefore.traderBalanceBeforeCollatToken - _params.amountInTrader, 1e18, "_testCreateInitialPosition: E0091");
                assertEq(route.participantShares(alice), route.participantShares(bob), "_testCreateInitialPosition: E0010");
                assertEq(route.participantShares(alice), route.participantShares(yossi), "_testCreateInitialPosition: E0011");
                assertTrue(route.participantShares(trader) >= route.participantShares(alice), "_testCreateInitialPosition: E0012");
                uint256 _totalParticipantShares = route.participantShares(alice) + route.participantShares(bob) + route.participantShares(yossi) + route.participantShares(trader);
                assertEq(_totalSupply, _totalParticipantShares, "_testCreateInitialPosition: E0013");
                assertEq(_totalAssets, _totalSupply, "_testCreateInitialPosition: E0014");
                assertTrue(_totalAssets > 0, "_testCreateInitialPosition: E0015");
                assertTrue(route.participantShares(alice) > _increaseBalanceBefore.alicePositionSharesBefore, "_testCreateInitialPosition: E0016");
                assertTrue(route.participantShares(bob) > _increaseBalanceBefore.bobPositionSharesBefore, "_testCreateInitialPosition: E0017");
                assertTrue(route.participantShares(yossi) > _increaseBalanceBefore.yossiPositionSharesBefore, "_testCreateInitialPosition: E0018");
                assertTrue(route.participantShares(trader) > _increaseBalanceBefore.traderPositionSharesBefore, "_testCreateInitialPosition: E0019");
                // assertTrue(!route.isPuppetAdjusted(alice), "_testCreateInitialPosition: E0031");
                // assertTrue(!route.isPuppetAdjusted(bob), "_testCreateInitialPosition: E0032");
                // assertTrue(!route.isPuppetAdjusted(yossi), "_testCreateInitialPosition: E0033");
                // revert("asd");
            } else {
                address _token = _params.tokenIn;
                assertEq(_increaseBalanceBefore.positionIndexBefore + 2, _positionIndexAfter, "_testCreateInitialPosition: E06");
                assertEq(route.keeperRequests(_requestKey), false, "_testCreateInitialPosition: E9");
                assertEq(_totalSupply, 0, "_testCreateInitialPosition: E10");
                assertEq(_totalAssets, 0, "_testCreateInitialPosition: E11");
                assertEq(IERC20(WETH).balanceOf(address(route)), 0, "_testCreateInitialPosition: E12");
                assertEq(address(route).balance, 0, "_testCreateInitialPosition: E13");
                assertEq(orchestrator.puppetAccountBalance(alice, _token), _increaseBalanceBefore.aliceDepositAccountBalanceBefore, "_testCreateInitialPosition: E14");
                assertEq(orchestrator.puppetAccountBalance(bob, _token), _increaseBalanceBefore.bobDepositAccountBalanceBefore, "_testCreateInitialPosition: E15");
                assertEq(orchestrator.puppetAccountBalance(yossi, _token), _increaseBalanceBefore.yossiDepositAccountBalanceBefore, "_testCreateInitialPosition: E16");
                assertTrue(orchestrator.puppetAccountBalance(alice, _token) > 0, "_testCreateInitialPosition: E014");
                assertTrue(orchestrator.puppetAccountBalance(bob, _token) > 0, "_testCreateInitialPosition: E015");
                assertTrue(orchestrator.puppetAccountBalance(yossi, _token) > 0, "_testCreateInitialPosition: E016");
                assertEq(IERC20(_token).balanceOf(address(orchestrator)), _increaseBalanceBefore.orchestratorBalanceBefore, "_testCreateInitialPosition: E17");
                // assertEq(_increaseBalanceBefore.traderBalanceBeforeCollatToken - IERC20(_token).balanceOf(trader), _params.amountInTrader, "_testCreateInitialPosition: E18");
                assertEq(route.participantShares(alice), _increaseBalanceBefore.alicePositionSharesBefore, "_testCreateInitialPosition: E00016");
                assertEq(route.participantShares(bob), _increaseBalanceBefore.bobPositionSharesBefore, "_testCreateInitialPosition: E00017");
                assertEq(route.participantShares(yossi), _increaseBalanceBefore.yossiPositionSharesBefore, "_testCreateInitialPosition: E00018");
                assertEq(route.participantShares(trader), _increaseBalanceBefore.traderPositionSharesBefore, "_testCreateInitialPosition: E00019");
                // assertTrue(!route.isPuppetAdjusted(alice), "_testCreateInitialPosition: E00031");
                // assertTrue(!route.isPuppetAdjusted(bob), "_testCreateInitialPosition: E00032");
                // assertTrue(!route.isPuppetAdjusted(yossi), "_testCreateInitialPosition: E00033");
                revert("we want to test on successfull execution");
            }
        } else {
            // added collateral to an existing position request
            assertEq(_increaseBalanceBefore.positionIndexBefore, _positionIndexAfter, "_testCreateInitialPosition: E020");

            (,uint256 _collateralInPositionGMXAfter,,,,,,) = IGMXVault(gmxVault).getPosition(address(route), collateralToken, indexToken, isLong); 
            if (_collateralInPositionGMXAfter > _collateralInPositionGMXBefore) {
                // adding collatral request was executed
                address _token = _params.tokenIn;
                assertTrue(!route.keeperRequests(_requestKey), "_testCreateInitialPosition: E19");
                assertApproxEqAbs(address(trader).balance, _increaseBalanceBefore.traderBalanceBeforeEth - _params.executionFee, 1e18, "_testCreateInitialPosition: E20");
                assertEq(route.participantShares(alice), route.participantShares(bob), "_testCreateInitialPosition: E21");
                assertTrue(route.participantShares(alice) < route.participantShares(yossi), "_testCreateInitialPosition: E22");
                assertTrue(route.participantShares(trader) >= route.participantShares(yossi), "_testCreateInitialPosition: E23");
                uint256 _totalParticipantShares = route.participantShares(alice) + route.participantShares(bob) + route.participantShares(yossi) + route.participantShares(trader);
                assertEq(_totalSupply, _totalParticipantShares, "_testCreateInitialPosition: E24");
                assertEq(_totalAssets, _totalSupply, "_testCreateInitialPosition: E25");
                assertTrue(_totalAssets > 0, "_testCreateInitialPosition: E26");
                assertTrue(IERC20(WETH).balanceOf(address(orchestrator)) - _params.amountInTrader < _increaseBalanceBefore.orchestratorBalanceBefore, "_testCreateInitialPosition: E27"); // using _amountInTrader because that's what we added for yossi
                assertEq(orchestrator.puppetAccountBalance(alice, _token), 0, "_testCreateInitialPosition: E28");
                assertEq(orchestrator.puppetAccountBalance(bob, _token), 0, "_testCreateInitialPosition: E29");
                assertTrue(orchestrator.puppetAccountBalance(yossi, _token) - _params.amountInTrader < _increaseBalanceBefore.yossiDepositAccountBalanceBefore, "_testCreateInitialPosition: E30"); // using _amountInTrader because that's what we added for yossi
                assertEq(route.participantShares(alice), _increaseBalanceBefore.alicePositionSharesBefore, "_testCreateInitialPosition: E0016");
                assertEq(route.participantShares(bob), _increaseBalanceBefore.bobPositionSharesBefore, "_testCreateInitialPosition: E0017");
                assertTrue(route.participantShares(yossi) > _increaseBalanceBefore.yossiPositionSharesBefore, "_testCreateInitialPosition: E0018");
                assertTrue(route.participantShares(trader) > _increaseBalanceBefore.traderPositionSharesBefore, "_testCreateInitialPosition: E0019");
                // assertTrue(route.isPuppetAdjusted(alice), "_testCreateInitialPosition: E31");
                // assertTrue(route.isPuppetAdjusted(bob), "_testCreateInitialPosition: E32");
                // assertTrue(!route.isPuppetAdjusted(yossi), "_testCreateInitialPosition: E33");
                // revert("asd");
            } else {
                // adding collatral request was cancelled
                revert("we want to test on successfull execution - 1");
            }
        }
    }

    function _testCreatePosition(CreatePositionParams memory _params, bool _addCollateralToAnExistingPosition) internal returns (bytes32 _requestKey) {
        // add weth to yossi's deposit account so he can join the increase
        if (_addCollateralToAnExistingPosition) {
            _dealERC20(_params.tokenIn, yossi, _params.amountInTrader);
            vm.startPrank(yossi);
            orchestrator.deposit{ value: _params.amountInTrader }(_params.amountInTrader, WETH, yossi);
            vm.stopPrank();

            // withdraw all of alice's position
            vm.startPrank(alice);
            orchestrator.withdraw(orchestrator.puppetAccountBalance(alice, _params.tokenIn), _params.tokenIn, alice, false);
            vm.stopPrank();

            // withdraw all of bob's position
            vm.startPrank(bob);
            orchestrator.withdraw(orchestrator.puppetAccountBalance(bob, _params.tokenIn), _params.tokenIn, bob, false);
            vm.stopPrank();

            assertEq(orchestrator.puppetAccountBalance(alice, _params.tokenIn), 0, "_testCreatePosition: E0001");
            assertEq(orchestrator.puppetAccountBalance(bob, _params.tokenIn), 0, "_testCreatePosition: E0002");
        }

        (uint256 _addCollateralRequestsIndexBefore,,) = route.positions(route.positionIndex());
        CreatePositionFirst memory _createPositionFirst = CreatePositionFirst({
            orchesratorBalanceBefore: IERC20(_params.tokenIn).balanceOf(address(orchestrator)),
            aliceDepositAccountBalanceBefore: orchestrator.puppetAccountBalance(alice, _params.tokenIn),
            bobDepositAccountBalanceBefore: orchestrator.puppetAccountBalance(bob, _params.tokenIn),
            yossiDepositAccountBalanceBefore: orchestrator.puppetAccountBalance(yossi, _params.tokenIn),
            tokenIn: _params.tokenIn,
            routeTypeKey: _params.routeTypeKey
        });

        vm.startPrank(trader);
        _approve(address(route), _params.swapParams.path[0], type(uint256).max);
        _requestKey = orchestrator.requestPosition{ value: _params.executionFee }(_params.adjustPositionParams, _params.swapParams, _params.routeTypeKey, _params.executionFee, true);
        vm.stopPrank();

        _testCreatePositionExt(_params, _createPositionFirst, _requestKey, _addCollateralToAnExistingPosition, _addCollateralRequestsIndexBefore);
    }

    function _testCreatePositionExt(CreatePositionParams memory _params, CreatePositionFirst memory _createPositionFirst, bytes32 _requestKey, bool _addCollateralToAnExistingPosition, uint256 _addCollateralRequestsIndexBefore) internal {
        (, uint256 _puppetsAmountIn, uint256 _traderAmountInReq, uint256 _traderRequestShares, uint256 _requestTotalSupply, uint256 _requestTotalAssets) = route.addCollateralRequests(route.requestKeyToAddCollateralRequestsIndex(_requestKey));
        (uint256 _addCollateralRequestsIndexAfter, uint256 _totalSupply, uint256 _totalAssets) = route.positions(route.positionIndex());

        {
            assertEq(_traderAmountInReq, _params.amountInTrader, "_testCreatePosition: E6");
            assertEq(_traderAmountInReq, _traderRequestShares, "_testCreatePosition: E7");
            assertTrue(_requestTotalSupply > 0, "_testCreatePosition: E8");
            assertTrue(_requestTotalAssets >= _params.amountInTrader, "_testCreatePosition: E9");
        }

        (uint256[] memory _puppetsShares, uint256[] memory _puppetsAmounts) = route.puppetsRequestAmounts(_requestKey);

        _testCreatePositionExtAssertionsFirst(_params, _addCollateralToAnExistingPosition, _totalSupply, _totalAssets, _puppetsShares, _puppetsAmounts);
        _testCreatePositionExtAssertionsSecond(_createPositionFirst, _puppetsShares, _puppetsAmounts, _puppetsAmountIn, _addCollateralRequestsIndexBefore, _addCollateralRequestsIndexAfter);

        _testCreatePositionExtAssertionsThird(_requestKey, _addCollateralRequestsIndexBefore);
    }

    function _testCreatePositionExtAssertionsThird(bytes32 _requestKey, uint256 _addCollateralRequestsIndexBefore) internal {
        assertEq(route.requestKeyToAddCollateralRequestsIndex(_requestKey), _addCollateralRequestsIndexBefore, "_testCreatePosition: E15");
    }

    function _testCreatePositionExtAssertionsSecond(CreatePositionFirst memory _createPositionFirst, uint256[] memory _puppetsShares, uint256[] memory _puppetsAmounts, uint256 _puppetsAmountIn, uint256 _addCollateralRequestsIndexBefore, uint256 _addCollateralRequestsIndexAfter) internal {
            address[] memory _puppets = route.puppets();
            // bytes32 _routeTypeKey = orchestrator.getRouteTypeKey(WETH, WETH, true);
            assertEq(IERC20(WETH).balanceOf(address(route)), 0, "_testCreatePosition: E14");
            assertEq(orchestrator.lastPositionOpenedTimestamp(alice, _createPositionFirst.routeTypeKey), block.timestamp, "_testCreatePosition: E16");
            assertEq(orchestrator.lastPositionOpenedTimestamp(bob, _createPositionFirst.routeTypeKey), block.timestamp, "_testCreatePosition: E17");
            assertEq(orchestrator.lastPositionOpenedTimestamp(yossi, _createPositionFirst.routeTypeKey), block.timestamp, "_testCreatePosition: E18");
            assertEq(_addCollateralRequestsIndexAfter, _addCollateralRequestsIndexBefore + 1, "_testCreatePosition: E19");
            assertEq(IERC20(_createPositionFirst.tokenIn).balanceOf(address(orchestrator)) + _puppetsAmountIn, _createPositionFirst.orchesratorBalanceBefore, "_testCreatePosition: E20");
            assertEq(_puppetsShares.length, 3, "_testCreatePosition: E22");
            assertEq(_puppetsAmounts.length, 3, "_testCreatePosition: E23");
            assertEq(_puppets.length, 3, "_testCreatePosition: E24");
            assertEq(_createPositionFirst.aliceDepositAccountBalanceBefore - _puppetsAmounts[0], orchestrator.puppetAccountBalance(alice, _createPositionFirst.tokenIn), "_testCreatePosition: E25");
            assertEq(_createPositionFirst.bobDepositAccountBalanceBefore - _puppetsAmounts[1], orchestrator.puppetAccountBalance(bob, _createPositionFirst.tokenIn), "_testCreatePosition: E26");
            assertEq(_createPositionFirst.yossiDepositAccountBalanceBefore - _puppetsAmounts[2], orchestrator.puppetAccountBalance(yossi, _createPositionFirst.tokenIn), "_testCreatePosition: E27");
            assertEq(_puppetsShares[0], _puppetsShares[1], "_testCreatePosition: E28");
            assertEq(_puppetsAmounts[0], _puppetsAmounts[1], "_testCreatePosition: E30");
        }

    function _testCreatePositionExtAssertionsFirst(CreatePositionParams memory _params, bool _addCollateralToAnExistingPosition, uint256 _totalSupply, uint256 _totalAssets, uint256[] memory _puppetsShares, uint256[] memory _puppetsAmounts) internal {
            if (_addCollateralToAnExistingPosition) {
                assertEq(route.positionIndex(), _params.positionIndexBefore, "_testCreatePosition: E10");
                assertTrue(_totalSupply > 0, "_testCreatePosition: E011");
                assertTrue(_totalAssets > 0, "_testCreatePosition: E012");
                assertEq(_puppetsShares[0], 0, "_testCreatePosition: E032");
                assertEq(_puppetsShares[1], 0, "_testCreatePosition: E033");
                assertTrue(_puppetsShares[2] > 0, "_testCreatePosition: E034"); // we increased Yossi's balance so he can join on the increase
            } else {
                assertEq(route.positionIndex(), _params.positionIndexBefore + 1, "_testCreatePosition: E66910");
                assertEq(_totalSupply, 0, "_testCreatePosition: E11");
                assertEq(_totalAssets, 0, "_testCreatePosition: E12");
                assertTrue(_puppetsShares[0] > 0, "_testCreatePosition: E32");
                assertTrue(_puppetsShares[1] > 0, "_testCreatePosition: E33");
                assertTrue(_puppetsShares[2] > 0, "_testCreatePosition: E34");
                assertEq(_puppetsShares[0], _puppetsShares[2], "_testCreatePosition: E29");
                assertEq(_puppetsAmounts[0], _puppetsAmounts[2], "_testCreatePosition: E31");
            }
        }

    function _testClosePosition(bytes32 _routeTypeKey, bool _isAuth) internal {
        assertTrue(_isOpenInterest(address(route)), "_testClosePosition: E1");

        uint256 _minOut = 0;
        (uint256 _sizeDelta, uint256 _collateralDelta,,,,,,) = IGMXVault(gmxVault).getPosition(address(route), collateralToken, indexToken, isLong);
        uint256 _executionFee = 180000000000000; // can be set to PositionRouter.minExecutionFee() https://arbiscan.io/address/0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868#readContract#F26

        uint256 _acceptablePrice;  // the USD value of the min (for longs) or max (for shorts) index price acceptable when executing the request
        if (isLong) {
            _acceptablePrice = 0;
        } else {
            _acceptablePrice = type(uint256).max;
        }

        IRoute.AdjustPositionParams memory _adjustPositionParams = IRoute.AdjustPositionParams({
            // amountIn: 0,
            collateralDelta: _collateralDelta,
            sizeDelta: _sizeDelta,
            acceptablePrice: _acceptablePrice,
            minOut: _minOut
        });

        IRoute.SwapParams memory _swapParams = IRoute.SwapParams({
            path: new address[](0),
            amount: 0,
            minOut: 0
        });
        
        assertEq(IERC20(collateralToken).balanceOf(address(route)), 0, "_testClosePosition: E2");
        assertEq(address(route).balance, 0, "_testClosePosition: E3");

        ClosePositionBefore memory _closePositionBefore = ClosePositionBefore({
            traderBalanceBefore: IERC20(collateralToken).balanceOf(address(trader)), 
            aliceDepositAccountBalanceBefore: orchestrator.puppetAccountBalance(alice, collateralToken),
            bobDepositAccountBalanceBefore: orchestrator.puppetAccountBalance(bob, collateralToken),
            yossiDepositAccountBalanceBefore: orchestrator.puppetAccountBalance(yossi, collateralToken),
            orchesratorBalanceBefore: IERC20(collateralToken).balanceOf(address(orchestrator)),
            positionIndexBefore: route.positionIndex()
        });

        if (!_isAuth) {
            vm.startPrank(trader);

            {
                vm.expectRevert(); // revert with `InvalidExecutionFee`
                orchestrator.requestPosition{ value: _executionFee - 1 }(_adjustPositionParams, _swapParams, _routeTypeKey, _executionFee, false);
            }

            if (route.waitForKeeperAdjustment()) {
                vm.expectRevert(); // revert with `waitingForKeeperAdjustment`
                orchestrator.requestPosition{ value: _executionFee }(_adjustPositionParams, _swapParams, _routeTypeKey, _executionFee, false);
                return;
            }

            orchestrator.requestPosition{ value: _executionFee }(_adjustPositionParams, _swapParams, _routeTypeKey, _executionFee, false);
            vm.stopPrank();

            vm.startPrank(GMXPositionRouterKeeper); // keeper
            IGMXPositionRouter(gmxPositionRouter).executeDecreasePositions(type(uint256).max, payable(address(route)));
            vm.stopPrank();

            assertEq(IERC20(collateralToken).balanceOf(address(route)), 0, "_testClosePosition: E02");
            assertEq(address(route).balance, 0, "_testClosePosition: E03");

            if (_isOpenInterest(address(route))) {
                // call was not executed
                revert("decrease call was not executed");
            } else {
                // call was executed
                assertTrue(_closePositionBefore.traderBalanceBefore < IERC20(collateralToken).balanceOf(address(trader)), "_testClosePosition: E4");
                assertTrue(_closePositionBefore.aliceDepositAccountBalanceBefore < orchestrator.puppetAccountBalance(alice, collateralToken), "_testClosePosition: E5");
                assertTrue(_closePositionBefore.bobDepositAccountBalanceBefore < orchestrator.puppetAccountBalance(bob, collateralToken), "_testClosePosition: E6");
                assertTrue(_closePositionBefore.yossiDepositAccountBalanceBefore < orchestrator.puppetAccountBalance(yossi, collateralToken), "_testClosePosition: E7");
                assertTrue(_closePositionBefore.orchesratorBalanceBefore < IERC20(collateralToken).balanceOf(address(orchestrator)), "_testClosePosition: E8");
                assertEq(_closePositionBefore.aliceDepositAccountBalanceBefore, _closePositionBefore.bobDepositAccountBalanceBefore, "_testClosePosition: E9");
                assertApproxEqAbs(orchestrator.puppetAccountBalance(alice, collateralToken), orchestrator.puppetAccountBalance(bob, collateralToken), 1e15, "_testClosePosition: E10");
                assertEq(_closePositionBefore.positionIndexBefore + 1, route.positionIndex(), "_testClosePosition: E11");
                address[] memory _puppets = route.puppets();
                assertEq(_puppets.length, 0, "_testClosePosition: E12");
                assertEq(route.participantShares(alice), 0, "_testClosePosition: E13");
                assertEq(route.participantShares(bob), 0, "_testClosePosition: E14");
                assertEq(route.participantShares(yossi), 0, "_testClosePosition: E15");
                assertEq(route.participantShares(trader), 0, "_testClosePosition: E16");
                assertEq(route.latestAmountIn(alice), 0, "_testClosePosition: E17");
                assertEq(route.latestAmountIn(bob), 0, "_testClosePosition: E18");
                assertEq(route.latestAmountIn(yossi), 0, "_testClosePosition: E19");
                assertEq(route.latestAmountIn(trader), 0, "_testClosePosition: E20");
                // assertEq(route.isPuppetAdjusted(alice), false, "_testClosePosition: E21");
                // assertEq(route.isPuppetAdjusted(bob), false, "_testClosePosition: E22");
                // assertEq(route.isPuppetAdjusted(yossi), false, "_testClosePosition: E23");
            }
        } else {
            bytes32 _routeKey = orchestrator.getRouteKey(trader, _routeTypeKey);
            _testAuthDecreaseSize(_adjustPositionParams, _executionFee, _routeKey);
        }
    }

    function _testNonCollatAmountIn(uint256 _amountInTrader, uint256 _executionFee, IRoute.AdjustPositionParams memory _adjustPositionParams, bytes32 _routeTypeKey) internal {
        // TODO
        _amountInTrader = _amountInTrader / 50;
        address[] memory _pathNonCollateral = new address[](2);
        _pathNonCollateral[0] = FRAX;
        _pathNonCollateral[1] = WETH;
        IRoute.SwapParams memory _traderSwapDataNonCollateral = IRoute.SwapParams({
            path: _pathNonCollateral,
            amount: _amountInTrader,
            minOut: 0
        });
        
        vm.startPrank(address(trader));
        _dealERC20(FRAX, trader, _amountInTrader);
        uint256 _traderFraxBalanceBefore = IERC20(FRAX).balanceOf(trader);
        _approve(address(route), FRAX, type(uint256).max);
        
        {
            address[] memory _path = new address[](1);

            _path[0] = FRAX;
            IRoute.SwapParams memory _faultyTraderSwapData = IRoute.SwapParams({
                path: _path,
                amount: _amountInTrader,
                minOut: 0
            });

            vm.expectRevert(); // reverts with InvalidPath()
            orchestrator.requestPosition{ value: _amountInTrader + _executionFee }(_adjustPositionParams, _faultyTraderSwapData, _routeTypeKey, _executionFee, true);
        }
        
        orchestrator.requestPosition{ value: _executionFee }(_adjustPositionParams, _traderSwapDataNonCollateral, _routeTypeKey, _executionFee, true);
        assertTrue(IERC20(FRAX).balanceOf(trader) < _traderFraxBalanceBefore, "_testCreateInitialPosition: E1");
        vm.stopPrank();
    }

    function _testRegisterRouteAndIncreasePosition() internal {
        uint256 _minOut = 0; // _minOut can be zero if no swap is required
        uint256 _acceptablePrice = type(uint256).max; // the USD value of the max (for longs) or min (for shorts) index price acceptable when executing the request
        uint256 _executionFee = 180000000000000; // can be set to PositionRouter.minExecutionFee() https://arbiscan.io/address/0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868#readContract#F26

        // TODO: get data dynamically
        // Available amount in USD: PositionRouter.maxGlobalLongSizes(indexToken) - Vault.guaranteedUsd(indexToken)
        // uint256 _size = IGMXPositionRouter(orchestrator.getGMXPositionRouter()).maxGlobalLongSizes(indexToken) - IGMXVault(orchestrator.getGMXVault()).guaranteedUsd(indexToken);
        uint256 _size = 36751139216995468418460853833822170677 - IVault(orchestrator.gmxVault()).guaranteedUsd(indexToken);

        // the USD value of the change in position size
        uint256 _sizeDelta = _size / 20;

        // the amount of tokenIn to deposit as collateral
        uint256 _amountInTrader = 10 ether;

        address[] memory _path = new address[](1);

        IRoute.AdjustPositionParams memory _adjustPositionParams = IRoute.AdjustPositionParams({
            // amountIn: _amountInTrader,
            collateralDelta: 0,
            sizeDelta: _sizeDelta,
            acceptablePrice: _acceptablePrice,
            minOut: _minOut
        });
        
        _path[0] = WETH;
        IRoute.SwapParams memory _swapParams = IRoute.SwapParams({
            path: _path,
            amount: _amountInTrader,
            minOut: _minOut
        });

        vm.startPrank(trader);
        (bytes32 _routeKey, bytes32 _requestKey) = orchestrator.registerRouteAndRequestPosition{ value: _amountInTrader + _executionFee }(_adjustPositionParams, _swapParams, _executionFee, collateralToken, indexToken, isLong);
        vm.stopPrank();

        assertTrue(_routeKey != bytes32(0), "_testRegisterRouteAndIncreasePosition: E01");
        assertTrue(_requestKey != bytes32(0), "_testRegisterRouteAndIncreasePosition: E02");
    }

    function _testAuthDecreaseSize(IRoute.AdjustPositionParams memory _adjustPositionParams, uint256 _executionFee, bytes32 _routeKey) internal {
        vm.expectRevert(); // reverts with Unauthorized()
        orchestrator.decreaseSize(_adjustPositionParams, _executionFee, _routeKey);

        vm.startPrank(keeper);
        orchestrator.decreaseSize{ value: _executionFee }(_adjustPositionParams, _executionFee, _routeKey);
        vm.stopPrank();

        vm.startPrank(GMXPositionRouterKeeper); // keeper
        IGMXPositionRouter(gmxPositionRouter).executeDecreasePositions(type(uint256).max, payable(address(route)));
        vm.stopPrank();
    }

    function _testAuthLiquidate(bytes32 _routeKey) internal {
        vm.expectRevert(); // reverts with Unauthorized()
        orchestrator.liquidate(_routeKey);

        uint256 _positionIndexBefore = route.positionIndex();

        vm.startPrank(keeper);
        orchestrator.liquidate(_routeKey);
        vm.stopPrank();

        assertEq(_positionIndexBefore + 1, route.positionIndex(), "_testAuthLiquidate: E01");
    }

    // ============================================================================================
    // Internal Helper Functions
    // ============================================================================================

    function _dealERC20(address _token, address _recipient , uint256 _amount) internal {
        deal({ token: address(_token), to: _recipient, give: _amount});
    }

    function _approve(address _spender, address _token, uint256 _amount) internal {
        IERC20(_token).safeApprove(_spender, 0);
        IERC20(_token).safeApprove(_spender, _amount);
    }

    function _isOpenInterest(address _account) internal view returns (bool) {
        (uint256 _size, uint256 _collateral,,,,,,) = IGMXVault(gmxVault).getPosition(_account, collateralToken, indexToken, isLong);

        return _size > 0 && _collateral > 0;
    }

    function _setRoleCapability(Dictator _dictator, uint8 role, address target, bytes4 functionSig, bool enabled) internal {
        _dictator.setRoleCapability(role, target, functionSig, enabled);
    }

    function _setUserRole(Dictator _dictator, address user, uint8 role, bool enabled) internal {
        _dictator.setUserRole(user, role, enabled);
    }
}