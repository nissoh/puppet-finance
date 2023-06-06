// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {AggregatorV3Interface} from "@chainlink/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Auth, Authority} from "@solmate/auth/Auth.sol";

import {Orchestrator} from "../src/Orchestrator.sol";
import {Route} from "../src/Route.sol";
import {RouteFactory} from "../src/RouteFactory.sol";
import {Dictator} from "../src/Dictator.sol";

import {IOrchestrator} from "../src/interfaces/IOrchestrator.sol";

import {IGMXVault} from "../src/interfaces/IGMXVault.sol";
import {IGMXReader} from "../src/interfaces/IGMXReader.sol";
import {IGMXPositionRouter} from "../src/interfaces/IGMXPositionRouter.sol";

contract testPuppet is Test {

    using SafeERC20 for IERC20;

    struct GMXInfo {
        address gmxRouter;
        address gmxReader;
        address gmxVault;
        address gmxPositionRouter;
        address gmxReferralRebatesSender;
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

        vm.startPrank(owner);
        _setRoleCapability(_dictator, 0, address(orchestrator), functionSig, true);
        _setUserRole(_dictator, owner, 0, true);

        orchestrator.setRouteType(WETH, WETH, true);
        vm.stopPrank();
    }

    function testCorrectFlow() public {
        uint256 _assets = 1 ether;

        // trader
        bytes32 _routeKey = _testRegisterRouteWETH();

        route = Route(payable(orchestrator.getRoute(_routeKey)));

        // puppet
        _testPuppetDeposit(_assets, WETH);
        _testUpdateRoutesSubscription(_routeKey);
        _testSetThrottleLimit();
        _testPuppetWithdraw(_assets, WETH);

        // route
        _testIncreasePosition(false, false);
        _testIncreasePosition(true, false);
        _testClosePosition();
        _testIncreasePosition(false, true);
    }

    // ============================================================================================
    // Internal Test Functions
    // ============================================================================================

    //
    // orchestrator
    //

    // Trader

    function _testRegisterRouteWETH() internal returns (bytes32 _routeKey) {
        vm.startPrank(trader);

        vm.expectRevert(); // reverts with ZeroAddress()
        orchestrator.registerRoute(address(0), address(0), true);

        vm.expectRevert(); // reverts with NoPriceFeedForAsset()
        orchestrator.registerRoute(FRAX, WETH, true);

        _routeKey = orchestrator.registerRoute(WETH, WETH, true);

        vm.expectRevert(); // reverts with RouteAlreadyRegistered()
        orchestrator.registerRoute(WETH, WETH, true);

        address[] memory _pupptsForRoute = orchestrator.subscribedPuppets(_routeKey);

        address payable _route = payable(orchestrator.getRoute(_routeKey));

        bytes32 _routeTypeKey = orchestrator.getRouteTypeKey(WETH, WETH, true);
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
        uint256 _aliceBalanceBefore = address(alice).balance;
        vm.startPrank(alice);

        vm.expectRevert(); // reverts with NoPriceFeedForCollateralToken()
        orchestrator.deposit{ value: _assets }(_assets, FRAX, alice);
        
        uint256 _puppetAssetsBefore = orchestrator.puppetAccountBalance(bob, _token);
        orchestrator.deposit{ value: _assets }(_assets, _token, alice);
        
        assertEq(orchestrator.puppetAccountBalance(alice, _token), _puppetAssetsBefore + _assets, "_testPuppetDeposit: E0");
        assertEq(_aliceBalanceBefore - _assets, address(alice).balance, "_testPuppetDeposit: E1");
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

    function _testUpdateRoutesSubscription(bytes32 _routeKey) internal {
        uint256[] memory _allowances = new uint256[](1);
        address[] memory _traders = new address[](1);
        _traders[0] = trader;
        _allowances[0] = 10; // 10% of the puppet's deposit account

        bytes32 _routeTypeKey = orchestrator.getRouteTypeKey(WETH, WETH, true);
        address _route = orchestrator.getRoute(_routeKey);

        uint256[] memory _faultyAllowance = new uint256[](1);
        _faultyAllowance[0] = 101;
        address[] memory _faultyTraders = new address[](2);
        _faultyTraders[0] = alice;
        _faultyTraders[1] = bob;
        bytes32 _faultyRouteTypeKey = orchestrator.getRouteTypeKey(FRAX, WETH, true);

        vm.startPrank(alice);

        vm.expectRevert(); // reverts with MismatchedInputArrays()
        orchestrator.updateRoutesSubscription(_faultyTraders, _allowances, _routeTypeKey, true);

        vm.expectRevert(); // reverts with InvalidAllowancePercentage()
        orchestrator.updateRoutesSubscription(_traders, _faultyAllowance, _routeTypeKey, true);

        vm.expectRevert(); // reverts with RouteNotRegistered()
        orchestrator.updateRoutesSubscription(_traders, _allowances, _faultyRouteTypeKey, true);

        orchestrator.updateRoutesSubscription(_traders, _allowances, _routeTypeKey, true);
        assertEq(orchestrator.puppetAllowancePercentage(alice, _route), _allowances[0], "_testUpdateRoutesSubscription: E0");
        assertEq(orchestrator.subscribedPuppets(_routeKey)[0], alice, "_testUpdateRoutesSubscription: E1");
        assertEq(orchestrator.subscribedPuppets(_routeKey).length, 1, "_testUpdateRoutesSubscription: E2");
        vm.stopPrank();

        vm.startPrank(bob);
        orchestrator.updateRoutesSubscription(_traders, _allowances, _routeTypeKey, true);
        assertEq(orchestrator.puppetAllowancePercentage(bob, _route), _allowances[0], "_testUpdateRoutesSubscription: E3");
        assertEq(orchestrator.subscribedPuppets(_routeKey)[1], bob, "_testUpdateRoutesSubscription: E4");
        assertEq(orchestrator.subscribedPuppets(_routeKey).length, 2, "_testUpdateRoutesSubscription: E5");
        // again
        orchestrator.updateRoutesSubscription(_traders, _allowances, _routeTypeKey, true);
        assertEq(orchestrator.puppetAllowancePercentage(bob, _route), _allowances[0], "_testUpdateRoutesSubscription: E03");
        assertEq(orchestrator.subscribedPuppets(_routeKey)[1], bob, "_testUpdateRoutesSubscription: E04");
        assertEq(orchestrator.subscribedPuppets(_routeKey).length, 2, "_testUpdateRoutesSubscription: E05");
        vm.stopPrank();

        vm.startPrank(yossi);
        orchestrator.updateRoutesSubscription(_traders, _allowances, _routeTypeKey, true);
        assertEq(orchestrator.puppetAllowancePercentage(yossi, _route), _allowances[0], "_testUpdateRoutesSubscription: E6");
        assertEq(orchestrator.subscribedPuppets(_routeKey)[2], yossi, "_testUpdateRoutesSubscription: E7");
        assertEq(orchestrator.subscribedPuppets(_routeKey).length, 3, "_testUpdateRoutesSubscription: E8");
        vm.stopPrank();

        assertTrue(orchestrator.puppetAllowancePercentage(alice, _route) > 0, "_testUpdateRoutesSubscription: E9");
        assertTrue(orchestrator.puppetAllowancePercentage(bob, _route) > 0, "_testUpdateRoutesSubscription: E10");
        assertTrue(orchestrator.puppetAllowancePercentage(yossi, _route) > 0, "_testUpdateRoutesSubscription: E11");
    }

    function _testSetThrottleLimit() internal {

        bytes32 _routeTypeKey = orchestrator.getRouteTypeKey(WETH, WETH, true);

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
        _puppetBalanceBefore = address(yossi).balance;
        orchestrator.withdraw(_assets, _token, yossi, true);
        _puppetBalanceAfter = address(yossi).balance;
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
    function _testIncreasePosition(bool _addCollateralToAnExistingPosition, bool _testNonCollateralTraderAmountIn) internal {
        // (, int256 _price,,,) = priceFeed.latestRoundData();

        uint256 _minOut = 0; // _minOut can be zero if no swap is required
        uint256 _acceptablePrice = type(uint256).max; // the USD value of the max (for longs) or min (for shorts) index price acceptable when executing the request
        uint256 _executionFee = 180000000000000; // can be set to PositionRouter.minExecutionFee() https://arbiscan.io/address/0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868#readContract#F26

        // TODO: get data dynamically
        // Available amount in USD: PositionRouter.maxGlobalLongSizes(indexToken) - Vault.guaranteedUsd(indexToken)
        // uint256 _size = IGMXPositionRouter(orchestrator.getGMXPositionRouter()).maxGlobalLongSizes(indexToken) - IGMXVault(orchestrator.getGMXVault()).guaranteedUsd(indexToken);
        uint256 _size = 92114231411087324391798166152938732778 - 86226694002961445455749333837394963689;
        
        // the USD value of the change in position size
        uint256 _sizeDelta = _size / 20;

        // the amount of tokenIn to deposit as collateral
        uint256 _amountInTrader = 10 ether;

        bytes memory _traderPositionData = abi.encode(_minOut, _sizeDelta, _acceptablePrice);

        address[] memory _path = new address[](1);
        _path[0] = FRAX;
        bytes memory _faultyTraderSwapData = abi.encode(_path, _amountInTrader, _minOut);
        _path[0] = WETH;
        bytes memory _traderSwapData = abi.encode(_path, _amountInTrader, _minOut);

        address[] memory _pathNonCollateral = new address[](2);
        _pathNonCollateral[0] = FRAX;
        _pathNonCollateral[1] = WETH;
        bytes memory _traderSwapDataNonCollateral = abi.encode(_pathNonCollateral, _amountInTrader, _minOut);

        assertEq(orchestrator.paused(), false, "_testCreateInitialPosition: E0");

        vm.expectRevert(); // reverts with NotTrader()
        route.createPositionRequest{ value: _amountInTrader + _executionFee }(_traderPositionData, _traderSwapData, _executionFee, true);

        vm.startPrank(trader);

        if (_testNonCollateralTraderAmountIn) {
            _dealERC20(FRAX, trader , _amountInTrader);
            uint256 _traderFraxBalanceBefore = IERC20(FRAX).balanceOf(trader);
            _approve(address(route), FRAX, type(uint256).max);
            route.createPositionRequest{ value: _executionFee }(_traderPositionData, _traderSwapDataNonCollateral, _executionFee, true);
            assertTrue(IERC20(FRAX).balanceOf(trader) < _traderFraxBalanceBefore, "_testCreateInitialPosition: E1");
            return; // just want to test the swap
        }

        vm.expectRevert(); // reverts with InvalidExecutionFee()
        route.createPositionRequest{ value: _amountInTrader + _executionFee + 10 }(_traderPositionData, _traderSwapData, _executionFee, true);

        vm.expectRevert(); // reverts with InvalidPath()
        route.createPositionRequest{ value: _amountInTrader + _executionFee }(_traderPositionData, _faultyTraderSwapData, _executionFee, true);

        bytes32 _routeTypeKey = orchestrator.getRouteTypeKey(WETH, WETH, true);
        if (!_addCollateralToAnExistingPosition) {
            assertEq(orchestrator.lastPositionOpenedTimestamp(alice, _routeTypeKey), 0, "_testCreateInitialPosition: E3");
            assertEq(orchestrator.lastPositionOpenedTimestamp(bob, _routeTypeKey), 0, "_testCreateInitialPosition: E4");
            assertEq(orchestrator.lastPositionOpenedTimestamp(yossi, _routeTypeKey), 0, "_testCreateInitialPosition: E5");
        }

        vm.stopPrank();

        uint256 _aliceDepositAccountBalanceBefore = orchestrator.puppetAccountBalance(alice, WETH);
        uint256 _bobDepositAccountBalanceBefore = orchestrator.puppetAccountBalance(bob, WETH);
        uint256 _yossiDepositAccountBalanceBefore = orchestrator.puppetAccountBalance(yossi, WETH);
        uint256 _orchestratorBalanceBefore = IERC20(WETH).balanceOf(address(orchestrator));
        uint256 _traderBalanceBeforeCollatToken = IERC20(WETH).balanceOf(trader);
        uint256 _traderBalanceBeforeEth = address(trader).balance;
        uint256 _alicePositionSharesBefore = route.participantShares(alice);
        uint256 _bobPositionSharesBefore = route.participantShares(bob);
        uint256 _yossiPositionSharesBefore = route.participantShares(yossi);
        uint256 _traderPositionSharesBefore = route.participantShares(trader);


        (uint256 _addCollateralRequestsIndexBefore,,) = route.positions(route.positionIndex());
        uint256 _positionIndexBefore = route.positionIndex();

        // 1. createPosition
        bytes32 _requestKey = _testCreatePosition(_traderPositionData, _traderSwapData, _amountInTrader, _executionFee, _positionIndexBefore, _addCollateralToAnExistingPosition);

        if (!_addCollateralToAnExistingPosition) {
            assertTrue(IERC20(WETH).balanceOf(address(orchestrator)) < _orchestratorBalanceBefore, "_testCreateInitialPosition: E05");
            assertTrue(orchestrator.puppetAccountBalance(alice, WETH) < _aliceDepositAccountBalanceBefore, "_testCreateInitialPosition: E06");
            assertTrue(orchestrator.puppetAccountBalance(bob, WETH) < _bobDepositAccountBalanceBefore, "_testCreateInitialPosition: E07");
            assertTrue(orchestrator.puppetAccountBalance(yossi, WETH) < _yossiDepositAccountBalanceBefore, "_testCreateInitialPosition: E08");
        }

        vm.expectRevert(); // reverts with NotCallbackCaller()
        route.gmxPositionCallback(_requestKey, true, true);

        (,uint256 _collateralInPositionGMXBefore,,,,,,) = IGMXVault(gmxVault).getPosition(address(route), collateralToken, indexToken, isLong);

        uint256[] memory _allowances = new uint256[](1);
        address[] memory _traders = new address[](1);
        _traders[0] = trader;
        _allowances[0] = 10; // 10% of the puppet's deposit account
        vm.startPrank(alice);
        vm.expectRevert(); // reverts with RouteWaitingForCallback()
        orchestrator.updateRoutesSubscription(_traders, _allowances, _routeTypeKey, false);
        vm.stopPrank();

        assertEq(route.isWaitingForCallback(), true, "_testCreateInitialPosition: E100");

        // 2. executePosition
        vm.startPrank(GMXPositionRouterKeeper); // keeper
        IGMXPositionRouter(gmxPositionRouter).executeIncreasePositions(type(uint256).max, payable(address(route)));
        vm.stopPrank();

        assertEq(route.isWaitingForCallback(), false, "_testCreateInitialPosition: E101");

        (uint256 _addCollateralRequestsIndexAfter,,) = route.positions(route.positionIndex());
        uint256 _positionIndexAfter = route.positionIndex();

        assertEq(_addCollateralRequestsIndexBefore + 1, _addCollateralRequestsIndexAfter, "_testCreateInitialPosition: E07");
        assertEq(address(route).balance, 0, "_testCreateInitialPosition: E007");
        assertEq(IERC20(WETH).balanceOf(address(route)), 0, "_testCreateInitialPosition: E008");

        (,uint256 _totalSupply, uint256 _totalAssets) = route.positions(route.positionIndex());
        if (!_addCollateralToAnExistingPosition) {
            if (_isOpenInterest(address(route))) {
                assertTrue(!route.keeperRequests(_requestKey), "_testCreateInitialPosition: E006");
                assertEq(_positionIndexBefore + 1, _positionIndexAfter, "_testCreateInitialPosition: E0007");
                assertApproxEqAbs(address(trader).balance, _traderBalanceBeforeEth - _amountInTrader - _executionFee, 1e18, "_testCreateInitialPosition: E009");
                assertEq(route.participantShares(alice), route.participantShares(bob), "_testCreateInitialPosition: E0010");
                assertEq(route.participantShares(alice), route.participantShares(yossi), "_testCreateInitialPosition: E0011");
                assertTrue(route.participantShares(trader) > route.participantShares(alice), "_testCreateInitialPosition: E0012");
                uint256 _totalParticipantShares = route.participantShares(alice) + route.participantShares(bob) + route.participantShares(yossi) + route.participantShares(trader);
                assertEq(_totalSupply, _totalParticipantShares, "_testCreateInitialPosition: E0013");
                assertEq(_totalAssets, _totalSupply, "_testCreateInitialPosition: E0014");
                assertTrue(_totalAssets > 0, "_testCreateInitialPosition: E0015");
                assertTrue(route.participantShares(alice) > _alicePositionSharesBefore, "_testCreateInitialPosition: E0016");
                assertTrue(route.participantShares(bob) > _bobPositionSharesBefore, "_testCreateInitialPosition: E0017");
                assertTrue(route.participantShares(yossi) > _yossiPositionSharesBefore, "_testCreateInitialPosition: E0018");
                assertTrue(route.participantShares(trader) > _traderPositionSharesBefore, "_testCreateInitialPosition: E0019");
                assertTrue(!route.isPuppetAdjusted(alice), "_testCreateInitialPosition: E0031");
                assertTrue(!route.isPuppetAdjusted(bob), "_testCreateInitialPosition: E0032");
                assertTrue(!route.isPuppetAdjusted(yossi), "_testCreateInitialPosition: E0033");
                // revert("asd");
            } else {
                assertEq(_positionIndexBefore + 1, _positionIndexAfter, "_testCreateInitialPosition: E06");
                assertEq(route.keeperRequests(_requestKey), false, "_testCreateInitialPosition: E9");
                assertEq(_totalSupply, 0, "_testCreateInitialPosition: E10");
                assertEq(_totalAssets, 0, "_testCreateInitialPosition: E11");
                assertEq(IERC20(WETH).balanceOf(address(route)), 0, "_testCreateInitialPosition: E12");
                assertEq(address(route).balance, 0, "_testCreateInitialPosition: E13");
                assertEq(orchestrator.puppetAccountBalance(alice, WETH), _aliceDepositAccountBalanceBefore, "_testCreateInitialPosition: E14");
                assertEq(orchestrator.puppetAccountBalance(bob, WETH), _bobDepositAccountBalanceBefore, "_testCreateInitialPosition: E15");
                assertEq(orchestrator.puppetAccountBalance(yossi, WETH), _yossiDepositAccountBalanceBefore, "_testCreateInitialPosition: E16");
                assertTrue(orchestrator.puppetAccountBalance(alice, WETH) > 0, "_testCreateInitialPosition: E014");
                assertTrue(orchestrator.puppetAccountBalance(bob, WETH) > 0, "_testCreateInitialPosition: E015");
                assertTrue(orchestrator.puppetAccountBalance(yossi, WETH) > 0, "_testCreateInitialPosition: E016");
                assertEq(IERC20(WETH).balanceOf(address(orchestrator)), _orchestratorBalanceBefore, "_testCreateInitialPosition: E17");
                assertEq(IERC20(WETH).balanceOf(trader) - _traderBalanceBeforeCollatToken, _amountInTrader, "_testCreateInitialPosition: E18");
                assertEq(route.participantShares(alice), _alicePositionSharesBefore, "_testCreateInitialPosition: E00016");
                assertEq(route.participantShares(bob), _bobPositionSharesBefore, "_testCreateInitialPosition: E00017");
                assertEq(route.participantShares(yossi), _yossiPositionSharesBefore, "_testCreateInitialPosition: E00018");
                assertEq(route.participantShares(trader), _traderPositionSharesBefore, "_testCreateInitialPosition: E00019");
                assertTrue(!route.isPuppetAdjusted(alice), "_testCreateInitialPosition: E00031");
                assertTrue(!route.isPuppetAdjusted(bob), "_testCreateInitialPosition: E00032");
                assertTrue(!route.isPuppetAdjusted(yossi), "_testCreateInitialPosition: E00033");
                revert("we want to test on successfull execution");
            }
        } else {
            // added collateral to an existing position request
            assertEq(_positionIndexBefore, _positionIndexAfter, "_testCreateInitialPosition: E20");

            (,uint256 _collateralInPositionGMXAfter,,,,,,) = IGMXVault(gmxVault).getPosition(address(route), collateralToken, indexToken, isLong); 
            if (_collateralInPositionGMXAfter > _collateralInPositionGMXBefore) {
                // adding collatral request was executed
                assertTrue(!route.keeperRequests(_requestKey), "_testCreateInitialPosition: E19");
                assertApproxEqAbs(address(trader).balance, _traderBalanceBeforeEth - _amountInTrader - _executionFee, 1e18, "_testCreateInitialPosition: E20");
                assertEq(route.participantShares(alice), route.participantShares(bob), "_testCreateInitialPosition: E21");
                assertTrue(route.participantShares(alice) < route.participantShares(yossi), "_testCreateInitialPosition: E22");
                assertTrue(route.participantShares(trader) > route.participantShares(yossi), "_testCreateInitialPosition: E23");
                uint256 _totalParticipantShares = route.participantShares(alice) + route.participantShares(bob) + route.participantShares(yossi) + route.participantShares(trader);
                assertEq(_totalSupply, _totalParticipantShares, "_testCreateInitialPosition: E24");
                assertEq(_totalAssets, _totalSupply, "_testCreateInitialPosition: E25");
                assertTrue(_totalAssets > 0, "_testCreateInitialPosition: E26");
                assertTrue(IERC20(WETH).balanceOf(address(orchestrator)) - _amountInTrader < _orchestratorBalanceBefore, "_testCreateInitialPosition: E27"); // using _amountInTrader because that's what we added for yossi
                assertEq(orchestrator.puppetAccountBalance(alice, WETH), _aliceDepositAccountBalanceBefore, "_testCreateInitialPosition: E28");
                assertEq(orchestrator.puppetAccountBalance(bob, WETH), _bobDepositAccountBalanceBefore, "_testCreateInitialPosition: E29");
                assertTrue(orchestrator.puppetAccountBalance(yossi, WETH) - _amountInTrader < _yossiDepositAccountBalanceBefore, "_testCreateInitialPosition: E30"); // using _amountInTrader because that's what we added for yossi
                assertEq(route.participantShares(alice), _alicePositionSharesBefore, "_testCreateInitialPosition: E0016");
                assertEq(route.participantShares(bob), _bobPositionSharesBefore, "_testCreateInitialPosition: E0017");
                assertTrue(route.participantShares(yossi) > _yossiPositionSharesBefore, "_testCreateInitialPosition: E0018");
                assertTrue(route.participantShares(trader) > _traderPositionSharesBefore, "_testCreateInitialPosition: E0019");
                assertTrue(route.isPuppetAdjusted(alice), "_testCreateInitialPosition: E31");
                assertTrue(route.isPuppetAdjusted(bob), "_testCreateInitialPosition: E32");
                assertTrue(!route.isPuppetAdjusted(yossi), "_testCreateInitialPosition: E33");
                // revert("asd");
            } else {
                // adding collatral request was cancelled
                revert("we want to test on successfull execution - 1");
            }
        } 
    }

    function _testCreatePosition(bytes memory _traderPositionData, bytes memory _traderSwapData, uint256 _amountInTrader, uint256 _executionFee, uint256 _positionIndexBefore, bool _addCollateralToAnExistingPosition) internal returns (bytes32 _requestKey) {
        // add weth to yossi's deposit account so he can join the increase
        if (_addCollateralToAnExistingPosition) {
            vm.startPrank(yossi);
            orchestrator.deposit{ value: _amountInTrader }(_amountInTrader, WETH, yossi);
            vm.stopPrank();
        }

        uint256 _orchesratorBalanceBefore = IERC20(WETH).balanceOf(address(orchestrator));
        uint256 _aliceDepositAccountBalanceBefore = orchestrator.puppetAccountBalance(alice, WETH);
        uint256 _bobDepositAccountBalanceBefore = orchestrator.puppetAccountBalance(bob, WETH);
        uint256 _yossiDepositAccountBalanceBefore = orchestrator.puppetAccountBalance(yossi, WETH);
        (uint256 _addCollateralRequestsIndexBefore,,) = route.positions(route.positionIndex());

        vm.startPrank(trader);
        _requestKey = route.createPositionRequest{ value: _amountInTrader + _executionFee }(_traderPositionData, _traderSwapData, _executionFee, true);
        vm.stopPrank();

        (uint256 _puppetsAmountIn, uint256 _traderAmountInReq, uint256 _traderRequestShares, uint256 _requestTotalSupply, uint256 _requestTotalAssets) = route.addCollateralRequests(route.requestKeyToAddCollateralRequestsIndex(_requestKey));
        (uint256 _addCollateralRequestsIndexAfter, uint256 _totalSupply, uint256 _totalAssets) = route.positions(route.positionIndex());
        uint256 _positionIndex = route.positionIndex();

        assertEq(_traderAmountInReq, _amountInTrader, "_testCreatePosition: E6");
        assertEq(_traderAmountInReq, _traderRequestShares, "_testCreatePosition: E7");
        assertTrue(_requestTotalSupply > 0, "_testCreatePosition: E8");
        assertTrue(_requestTotalAssets >= _amountInTrader, "_testCreatePosition: E9");

        address[] memory _puppets = route.puppets();
        (uint256[] memory _puppetsShares, uint256[] memory _puppetsAmounts) = route.puppetsRequestAmounts(_requestKey);

        if (_addCollateralToAnExistingPosition) {
            assertEq(_positionIndex, _positionIndexBefore, "_testCreatePosition: E10");
            assertTrue(_totalSupply > 0, "_testCreatePosition: E011");
            assertTrue(_totalAssets > 0, "_testCreatePosition: E012");
            assertEq(_puppetsShares[0], 0, "_testCreatePosition: E032");
            assertEq(_puppetsShares[1], 0, "_testCreatePosition: E033");
            assertTrue(_puppetsShares[2] > 0, "_testCreatePosition: E034"); // we increased Yossi's balance so he can join on the increase
        } else {
            assertEq(_positionIndex, _positionIndexBefore + 1, "_testCreatePosition: E10");
            assertEq(_totalSupply, 0, "_testCreatePosition: E11");
            assertEq(_totalAssets, 0, "_testCreatePosition: E12");
            assertTrue(_puppetsShares[0] > 0, "_testCreatePosition: E32");
            assertTrue(_puppetsShares[1] > 0, "_testCreatePosition: E33");
            assertTrue(_puppetsShares[2] > 0, "_testCreatePosition: E34");
            assertEq(_puppetsShares[0], _puppetsShares[2], "_testCreatePosition: E29");
            assertEq(_puppetsAmounts[0], _puppetsAmounts[2], "_testCreatePosition: E31");
        }

        bytes32 _routeTypeKey = orchestrator.getRouteTypeKey(WETH, WETH, true);
        assertEq(IERC20(WETH).balanceOf(address(route)), 0, "_testCreatePosition: E14");
        assertEq(route.requestKeyToAddCollateralRequestsIndex(_requestKey), _addCollateralRequestsIndexBefore, "_testCreatePosition: E15");
        assertEq(orchestrator.lastPositionOpenedTimestamp(alice, _routeTypeKey), block.timestamp, "_testCreatePosition: E16");
        assertEq(orchestrator.lastPositionOpenedTimestamp(bob, _routeTypeKey), block.timestamp, "_testCreatePosition: E17");
        assertEq(orchestrator.lastPositionOpenedTimestamp(yossi, _routeTypeKey), block.timestamp, "_testCreatePosition: E18");
        assertEq(_addCollateralRequestsIndexAfter, _addCollateralRequestsIndexBefore + 1, "_testCreatePosition: E19");
        assertEq(IERC20(WETH).balanceOf(address(orchestrator)) + _puppetsAmountIn, _orchesratorBalanceBefore, "_testCreatePosition: E20");
        assertEq(_puppetsShares.length, 3, "_testCreatePosition: E22");
        assertEq(_puppetsAmounts.length, 3, "_testCreatePosition: E23");
        assertEq(_puppets.length, 3, "_testCreatePosition: E24");
        assertEq(_aliceDepositAccountBalanceBefore - _puppetsAmounts[0], orchestrator.puppetAccountBalance(alice, WETH), "_testCreatePosition: E25");
        assertEq(_bobDepositAccountBalanceBefore - _puppetsAmounts[1], orchestrator.puppetAccountBalance(bob, WETH), "_testCreatePosition: E26");
        assertEq(_yossiDepositAccountBalanceBefore - _puppetsAmounts[2], orchestrator.puppetAccountBalance(yossi, WETH), "_testCreatePosition: E27");
        assertEq(_puppetsShares[0], _puppetsShares[1], "_testCreatePosition: E28");
        assertEq(_puppetsAmounts[0], _puppetsAmounts[1], "_testCreatePosition: E30");
    }

    function _testClosePosition() internal {
        assertTrue(_isOpenInterest(address(route)), "_testClosePosition: E1");

        bytes memory _traderSwapData;

        uint256 _minOut = 0;
        (uint256 _sizeDelta, uint256 _collateralDelta,,,,,,) = IGMXVault(gmxVault).getPosition(address(route), collateralToken, indexToken, isLong);
        // uint256 _acceptablePrice = type(uint256).max; // the USD value of the max (for longs) or min (for shorts) index price acceptable when executing the request
        uint256 _acceptablePrice = 0;
        uint256 _executionFee = 180000000000000; // can be set to PositionRouter.minExecutionFee() https://arbiscan.io/address/0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868#readContract#F26

        bytes memory _traderPositionData = abi.encode(_collateralDelta, _sizeDelta, _acceptablePrice, _minOut);

        assertEq(IERC20(WETH).balanceOf(address(route)), 0, "_testClosePosition: E2");
        assertEq(address(route).balance, 0, "_testClosePosition: E3");

        uint256 _traderBalanceBefore = IERC20(WETH).balanceOf(address(trader));
        uint256 _aliceDepositAccountBalanceBefore = orchestrator.puppetAccountBalance(alice, WETH);
        uint256 _bobDepositAccountBalanceBefore = orchestrator.puppetAccountBalance(bob, WETH);
        uint256 _yossiDepositAccountBalanceBefore = orchestrator.puppetAccountBalance(yossi, WETH);
        uint256 _orchesratorBalanceBefore = IERC20(WETH).balanceOf(address(orchestrator));
        uint256 _positionIndexBefore = route.positionIndex();

        vm.startPrank(trader);

        vm.expectRevert(); // revert with `InvalidExecutionFee`
        route.createPositionRequest{ value: _executionFee - 1 }(_traderPositionData, _traderSwapData, _executionFee, false);

        route.createPositionRequest{ value: _executionFee }(_traderPositionData, _traderSwapData, _executionFee, false);
        vm.stopPrank();

        vm.startPrank(GMXPositionRouterKeeper); // keeper
        IGMXPositionRouter(gmxPositionRouter).executeDecreasePositions(type(uint256).max, payable(address(route)));
        vm.stopPrank();

        assertEq(IERC20(WETH).balanceOf(address(route)), 0, "_testClosePosition: E02");
        assertEq(address(route).balance, 0, "_testClosePosition: E03");

        if (_isOpenInterest(address(route))) {
            // call was not executed
            revert("decrease call was not executed");
        } else {
            // call was executed
            assertTrue(_traderBalanceBefore < IERC20(WETH).balanceOf(address(trader)), "_testClosePosition: E4");
            assertTrue(_aliceDepositAccountBalanceBefore < orchestrator.puppetAccountBalance(alice, WETH), "_testClosePosition: E5");
            assertTrue(_bobDepositAccountBalanceBefore < orchestrator.puppetAccountBalance(bob, WETH), "_testClosePosition: E6");
            assertTrue(_yossiDepositAccountBalanceBefore < orchestrator.puppetAccountBalance(yossi, WETH), "_testClosePosition: E7");
            assertTrue(_orchesratorBalanceBefore < IERC20(WETH).balanceOf(address(orchestrator)), "_testClosePosition: E8");
            assertEq(_aliceDepositAccountBalanceBefore, _bobDepositAccountBalanceBefore, "_testClosePosition: E9");
            assertEq(orchestrator.puppetAccountBalance(alice, WETH), orchestrator.puppetAccountBalance(bob, WETH), "_testClosePosition: E10");
            assertEq(_positionIndexBefore + 1, route.positionIndex(), "_testClosePosition: E11");
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
            assertEq(route.isPuppetAdjusted(alice), false, "_testClosePosition: E21");
            assertEq(route.isPuppetAdjusted(bob), false, "_testClosePosition: E22");
            assertEq(route.isPuppetAdjusted(yossi), false, "_testClosePosition: E23");
        }
    }

    function _testCreatePositionWithNonCollateralToken() internal {

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