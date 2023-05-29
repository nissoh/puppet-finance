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
import {RevenueDistributor} from "../src/RevenueDistributor.sol";
import {RouteFactory} from "../src/RouteFactory.sol";

import {IBase} from "../src/interfaces/IBase.sol";

import {IGMXVault} from "../src/interfaces/IGMXVault.sol";
import {IGMXReader} from "../src/interfaces/IGMXReader.sol";
import {IGMXPositionRouter} from "../src/interfaces/IGMXPositionRouter.sol";

contract testPuppet is IBase, Test {

    using SafeERC20 for IERC20;

    address owner = makeAddr("owner");
    address trader = makeAddr("trader");
    address keeper = makeAddr("keeper");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address yossi = makeAddr("yossi");

    address route;

    address collateralToken = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1); // WETH
    address indexToken = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1); // WETH

    address GMXPositionRouterKeeper = address(0x11D62807dAE812a0F1571243460Bf94325F43BB7);

    bool isLong = true;
    
    uint256 arbitrumFork;

    Orchestrator orchestrator;

    AggregatorV3Interface priceFeed;

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

        // deploy RevenueDistributor
        Authority _authority = Authority(0x575F40E8422EfA696108dAFD12cD8d6366982416);
        address _revenueDistributor = address(new RevenueDistributor(_authority));

        // deploy RouteFactory
        address _routeFactory = address(new RouteFactory());

        // deploy orchestrator
        address _gmxRouter = 0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064;
        address _gmxReader = 0x22199a49A999c351eF7927602CFB187ec3cae489;
        address _gmxVault = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
        address _gmxPositionRouter = 0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868;
        address _gmxCallbackCaller = 0x11D62807dAE812a0F1571243460Bf94325F43BB7;
        address _gmxReferralRebatesSender = address(0);
        bytes32 _referralCode = bytes32(0);

        GMXInfo memory _gmxInfo = GMXInfo({
            gmxRouter: _gmxRouter,
            gmxReader: _gmxReader,
            gmxVault: _gmxVault,
            gmxPositionRouter: _gmxPositionRouter,
            gmxCallbackCaller: _gmxCallbackCaller,
            gmxReferralRebatesSender: _gmxReferralRebatesSender
        });

        orchestrator = new Orchestrator(_authority, _revenueDistributor, _routeFactory, keeper, _referralCode, _gmxInfo);


        // set route type
        vm.startPrank(owner);
        orchestrator.setRouteType(WETH, WETH, true);

        // set price feed info
        address ETH_USD_PRICE_FEED_ADDRESS = address(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612);
        uint256 ETH_USD_PRICE_FEED_DECIMALS = 8;

        address[] memory _assets = new address[](1);
        _assets[0] = WETH;
        address[] memory _priceFeeds = new address[](1);
        _priceFeeds[0] = ETH_USD_PRICE_FEED_ADDRESS;
        uint256[] memory _decimals = new uint256[](1);
        _decimals[0] = ETH_USD_PRICE_FEED_DECIMALS;

        orchestrator.setPriceFeeds(_assets, _priceFeeds, _decimals);
        vm.stopPrank();
    }

    function testCorrectFlow() public {
        uint256 _assets = 1 ether;

        // trader
        bytes32 _routeKey = _testRegisterRouteWETH();

        // puppet
        _testPuppetDeposit(_assets, WETH);
        _testUpdateRoutesSubscription(_routeKey);
        _testSetThrottleLimit();
        _testPuppetWithdraw(_assets, WETH);

        // route
        // _testCreateInitialPosition();
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

        address[] memory _pupptsForRoute = orchestrator.getPuppetsForRoute(_routeKey);

        address payable _route = payable(orchestrator.getRoute(_routeKey));

        bytes32 _routeTypeKey = orchestrator.getRouteTypeKey(WETH, WETH, true);
        assertEq(_routeKey, orchestrator.getRouteKey(trader, _routeTypeKey), "_testRegisterRoute: E0");
        assertEq(_pupptsForRoute.length, 0, "_testRegisterRoute: E1");
        assertEq(orchestrator.isRoute(_route), true, "_testRegisterRoute: E2");
        address[] memory _routes = orchestrator.getRoutes();
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
        
        uint256 _puppetAssetsBefore = orchestrator.puppetDepositAccount(_token, alice);
        orchestrator.deposit{ value: _assets }(_assets, _token, alice);
        
        assertEq(orchestrator.puppetDepositAccount(_token, alice), _puppetAssetsBefore + _assets, "_testPuppetDeposit: E0");
        assertEq(_aliceBalanceBefore - _assets, address(alice).balance, "_testPuppetDeposit: E1");
        vm.stopPrank();

        // bob
        uint256 _bobBalanceBefore = IERC20(_token).balanceOf(bob);
        vm.startPrank(bob);
        _approve(address(orchestrator), _token, _assets);
        _puppetAssetsBefore = orchestrator.puppetDepositAccount(_token, bob);
        orchestrator.deposit(_assets, _token, bob);
        assertEq(orchestrator.puppetDepositAccount(_token, bob), _puppetAssetsBefore + _assets, "_testPuppetDeposit: E2");
        assertEq(_bobBalanceBefore - _assets, IERC20(_token).balanceOf(bob), "_testPuppetDeposit: E3");
        vm.stopPrank();

        // yossi
        uint256 _yossiBalanceBefore = IERC20(_token).balanceOf(yossi);
        vm.startPrank(yossi);
        _approve(address(orchestrator), _token, _assets);
        _puppetAssetsBefore = orchestrator.puppetDepositAccount(_token, yossi);
        orchestrator.deposit(_assets, _token, yossi);
        assertEq(orchestrator.puppetDepositAccount(_token, yossi), _puppetAssetsBefore + _assets, "_testPuppetDeposit: E4");
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
        assertEq(orchestrator.getPuppetAllowancePercentage(alice, _route), _allowances[0], "_testUpdateRoutesSubscription: E0");
        assertEq(orchestrator.getPuppetsForRoute(_routeKey)[0], alice, "_testUpdateRoutesSubscription: E1");
        assertEq(orchestrator.getPuppetsForRoute(_routeKey).length, 1, "_testUpdateRoutesSubscription: E2");
        vm.stopPrank();

        vm.startPrank(bob);
        orchestrator.updateRoutesSubscription(_traders, _allowances, _routeTypeKey, true);
        assertEq(orchestrator.getPuppetAllowancePercentage(bob, _route), _allowances[0], "_testUpdateRoutesSubscription: E3");
        assertEq(orchestrator.getPuppetsForRoute(_routeKey)[1], bob, "_testUpdateRoutesSubscription: E4");
        assertEq(orchestrator.getPuppetsForRoute(_routeKey).length, 2, "_testUpdateRoutesSubscription: E5");
        // again
        orchestrator.updateRoutesSubscription(_traders, _allowances, _routeTypeKey, true);
        assertEq(orchestrator.getPuppetAllowancePercentage(bob, _route), _allowances[0], "_testUpdateRoutesSubscription: E03");
        assertEq(orchestrator.getPuppetsForRoute(_routeKey)[1], bob, "_testUpdateRoutesSubscription: E04");
        assertEq(orchestrator.getPuppetsForRoute(_routeKey).length, 2, "_testUpdateRoutesSubscription: E05");
        vm.stopPrank();

        vm.startPrank(yossi);
        orchestrator.updateRoutesSubscription(_traders, _allowances, _routeTypeKey, true);
        assertEq(orchestrator.getPuppetAllowancePercentage(yossi, _route), _allowances[0], "_testUpdateRoutesSubscription: E6");
        assertEq(orchestrator.getPuppetsForRoute(_routeKey)[2], yossi, "_testUpdateRoutesSubscription: E7");
        assertEq(orchestrator.getPuppetsForRoute(_routeKey).length, 3, "_testUpdateRoutesSubscription: E8");
        vm.stopPrank();

        assertTrue(orchestrator.getPuppetAllowancePercentage(alice, _route) > 0, "_testUpdateRoutesSubscription: E9");
        assertTrue(orchestrator.getPuppetAllowancePercentage(bob, _route) > 0, "_testUpdateRoutesSubscription: E10");
        assertTrue(orchestrator.getPuppetAllowancePercentage(yossi, _route) > 0, "_testUpdateRoutesSubscription: E11");
    }

    function _testSetThrottleLimit() internal {

        vm.startPrank(alice);
        orchestrator.setThrottleLimit(1 days);
        assertEq(orchestrator.throttleLimits(alice), 1 days, "_testSetThrottleLimit: E0");
        vm.stopPrank();

        vm.startPrank(bob);
        orchestrator.setThrottleLimit(2 days);
        assertEq(orchestrator.throttleLimits(bob), 2 days, "_testSetThrottleLimit: E1");
        vm.stopPrank();

        vm.startPrank(yossi);
        orchestrator.setThrottleLimit(3 days);
        assertEq(orchestrator.throttleLimits(yossi), 3 days, "_testSetThrottleLimit: E2");
        vm.stopPrank();
    }

    function _testPuppetWithdraw(uint256 _assets, address _token) internal {
        uint256 _aliceDepositAccountBalanceBefore = orchestrator.puppetDepositAccount(alice, _token);
        uint256 _bobDepositAccountBalanceBefore = orchestrator.puppetDepositAccount(bob, _token);
        uint256 _yossiDepositAccountBalanceBefore = orchestrator.puppetDepositAccount(yossi, _token);

        _testPuppetDeposit(_assets, _token);

        vm.startPrank(alice);
        uint256 _orchestratorBalanceBefore = IERC20(_token).balanceOf(address(orchestrator));
        uint256 _puppetBalanceBefore = IERC20(_token).balanceOf(alice);
        orchestrator.withdraw(_assets, _token, alice, false);
        uint256 _puppetBalanceAfter = IERC20(_token).balanceOf(alice);
        uint256 _orchestratorBalanceAfter = IERC20(_token).balanceOf(address(orchestrator));
        vm.stopPrank();

        assertEq(_orchestratorBalanceBefore - _orchestratorBalanceAfter, _assets, "_testPuppetWithdraw: E0");
        assertEq(orchestrator.puppetDepositAccount(alice, _token), _aliceDepositAccountBalanceBefore, "_testPuppetWithdraw: E1");
        assertEq(_puppetBalanceBefore + _assets, _puppetBalanceAfter, "_testPuppetWithdraw: E2");

        vm.startPrank(bob);
        _orchestratorBalanceBefore = IERC20(_token).balanceOf(address(orchestrator));
        _puppetBalanceBefore = IERC20(_token).balanceOf(bob);
        orchestrator.withdraw(_assets, _token, bob, false);
        _puppetBalanceAfter = IERC20(_token).balanceOf(bob);
        _orchestratorBalanceAfter = IERC20(_token).balanceOf(address(orchestrator));
        vm.stopPrank();

        assertEq(_orchestratorBalanceBefore - _orchestratorBalanceAfter, _assets, "_testPuppetWithdraw: E3");
        assertEq(orchestrator.puppetDepositAccount(bob, _token), _bobDepositAccountBalanceBefore, "_testPuppetWithdraw: E4");
        assertEq(_puppetBalanceBefore + _assets, _puppetBalanceAfter, "_testPuppetWithdraw: E5");

        vm.startPrank(yossi);
        _orchestratorBalanceBefore = IERC20(_token).balanceOf(address(orchestrator));
        _puppetBalanceBefore = address(yossi).balance;
        orchestrator.withdraw(_assets, _token, yossi, true);
        _puppetBalanceAfter = address(yossi).balance;
        _orchestratorBalanceAfter = IERC20(_token).balanceOf(address(orchestrator));
        vm.stopPrank();

        assertEq(_orchestratorBalanceBefore - _orchestratorBalanceAfter, _assets, "_testPuppetWithdraw: E6");
        assertEq(orchestrator.puppetDepositAccount(yossi, _token), _yossiDepositAccountBalanceBefore, "_testPuppetWithdraw: E7");
        assertEq(_puppetBalanceBefore + _assets, _puppetBalanceAfter, "_testPuppetWithdraw: E8");
    }

    //
    // Route
    //

    // // open position
    // // add collateral + increase size
    // function _testCreateInitialPosition() internal {
    //     // (, int256 _price,,,) = priceFeed.latestRoundData();

    //     uint256 _minOut = 0; // _minOut can be zero if no swap is required
    //     uint256 _acceptablePrice = type(uint256).max; // the USD value of the max (for longs) or min (for shorts) index price acceptable when executing the request
    //     uint256 _executionFee = 180000000000000; // can be set to PositionRouter.minExecutionFee() https://arbiscan.io/address/0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868#readContract#F26

    //     // TODO - // Available amount in USD: PositionRouter.maxGlobalLongSizes(indexToken) - Vault.guaranteedUsd(indexToken)
    //     // uint256 _size = IGMXPositionRouter(orchestrator.getGMXPositionRouter()).maxGlobalLongSizes(indexToken) - IGMXVault(orchestrator.getGMXVault()).guaranteedUsd(indexToken);
    //     uint256 _size = 82698453891127247668603775976796325121 - 72755589402161323824061129657679280046;
    //     // the USD value of the change in position size
    //     uint256 _sizeDeltaTrader = _size / 50;
    //     uint256 _sizeDeltaPuppet = _size / 50;

    //     // the amount of tokenIn to deposit as collateral
    //     uint256 _amountInTrader = 10 ether;
    //     uint256 _amountInPuppet = _getAllowanceForRoute(_amountInTrader - _executionFee) - _executionFee;

    //     bytes memory _traderData = abi.encode(_minOut, _sizeDeltaTrader, _acceptablePrice, _executionFee);
    //     bytes memory _puppetsData = abi.encode(_amountInPuppet, _minOut, _sizeDeltaPuppet, _acceptablePrice, _executionFee);

    //     assertEq(ITraderRoute(traderRoute).getIsWaitingForCallback(), false, "_testCreateInitialPosition: E0");

    //     vm.expectRevert(); // reverts with NotTrader()
    //     ITraderRoute(traderRoute).createPosition(_traderData, _puppetsData, true, true);

    //     uint256 _traderBalanceBefore = address(trader).balance;

    //     vm.startPrank(trader);

    //     vm.expectRevert(); // reverts with `Arithmetic over/underflow` (on subtracting _executionFee from _amountInTrader) 
    //     ITraderRoute(traderRoute).createPosition(_traderData, _puppetsData, true, true);

    //     // 1. createPosition
    //     bytes32 _requestKey = ITraderRoute(traderRoute).createPosition{ value: _amountInTrader }(_traderData, _puppetsData, true, true);
    //     vm.stopPrank();

    //     assertEq(ITraderRoute(traderRoute).getIsWaitingForCallback(), true, "_testCreateInitialPosition: E1");
    //     assertEq(ITraderRoute(traderRoute).getTraderAmountIn(), _amountInTrader - _executionFee, "_testCreateInitialPosition: E02");
    //     assertEq(orchestrator.getRouteForRequestKey(_requestKey), address(traderRoute), "_testCreateInitialPosition: E2");

    //     vm.expectRevert(); // reverts with `NotKeeper()` 
    //     ITraderRoute(traderRoute).createPuppetPosition();

    //     vm.startPrank(orchestrator.getKeeper());
    //     vm.expectRevert(); // reverts with `PositionNotApproved()` 
    //     ITraderRoute(traderRoute).createPuppetPosition();
    //     vm.stopPrank();
        
    //     // 2. executePosition
    //     vm.startPrank(GMXPositionRouterKeeper); // keeper
    //     IGMXPositionRouter(orchestrator.getGMXPositionRouter()).executeIncreasePositions(type(uint256).max, payable(traderRoute));
    //     vm.stopPrank();

    //     if (_isOpenInterest(traderRoute)) {
    //         assertEq(ITraderRoute(traderRoute).getIsWaitingForCallback(), true, "_testCreateInitialPosition: E3");
    //         assertTrue(address(trader).balance < _traderBalanceBefore, "_testCreateInitialPosition: E4");
    //         assertTrue(TraderRoute(payable(traderRoute)).isRequestApproved(), "_testCreateInitialPosition: E5");

    //         uint256 _aliceDepositBalanceBefore = orchestrator.puppetDepositAccount(alice);
    //         uint256 _bobDepositBalanceBefore = orchestrator.puppetDepositAccount(bob);
    //         uint256 _yossiDepositBalanceBefore = orchestrator.puppetDepositAccount(yossi);
    //         uint256 _orchestratorBalanceBefore = address(orchestrator).balance;

    //         // 3. createPuppetPosition
    //         vm.startPrank(orchestrator.getKeeper());
    //         _requestKey = ITraderRoute(traderRoute).createPuppetPosition();
    //         vm.stopPrank();

    //         if (TraderRoute(payable(traderRoute)).isPuppetIncrease()) {
    //             _testPuppetRouteOnIncreaseBeforeCallback(_aliceDepositBalanceBefore, _bobDepositBalanceBefore, _yossiDepositBalanceBefore, _orchestratorBalanceBefore, _requestKey);
    //         } else {
    //             revert("not tested: 1");
    //         }

    //         uint256 _puppetRouteBalanceBefore = address(puppetRoute).balance;

    //         _aliceDepositBalanceBefore = orchestrator.puppetDepositAccount(alice);
    //         _bobDepositBalanceBefore = orchestrator.puppetDepositAccount(bob);
    //         _yossiDepositBalanceBefore = orchestrator.puppetDepositAccount(yossi);
    //         _orchestratorBalanceBefore = address(orchestrator).balance;

    //         // 4. executePuppetPosition
    //         vm.startPrank(GMXPositionRouterKeeper); // keeper
    //         IGMXPositionRouter(orchestrator.getGMXPositionRouter()).executeIncreasePositions(type(uint256).max, payable(puppetRoute));
    //         vm.stopPrank();

    //         if (_isOpenInterest(traderRoute)) {
    //             _testPuppetRouteOnIncreaseAfterPositionApproved(_executionFee, _orchestratorBalanceBefore, _aliceDepositBalanceBefore, _bobDepositBalanceBefore, _yossiDepositBalanceBefore, _puppetRouteBalanceBefore);
    //         } else {
    //             revert("not tested: 2");
    //         }

    //     } else {
    //         assertEq(address(traderRoute).balance, 0, "_testCreateInitialPosition: E5");
    //         assertEq(ITraderRoute(traderRoute).getIsWaitingForCallback(), false, "_testCreateInitialPosition: E6");
    //         assertEq(address(trader).balance, _traderBalanceBefore, "_testCreateInitialPosition: E7");
    //         revert("!OpenInterest"); // current config should open a position. i want to know if it fails
    //     }
    // }

    // function _testPuppetRouteOnIncreaseBeforeCallback(uint256 _aliceDepositBalanceBefore, uint256 _bobDepositBalanceBefore, uint256 _yossiDepositBalanceBefore, uint256 _orchestratorBalanceBefore, bytes32 _requestKey) internal {
    //     assertEq(PuppetRoute(payable(puppetRoute)).getIsPositionOpen(), false, "_testPuppetRouteOnIncreaseBeforeCallback: E0");
    //     assertEq(PuppetRoute(payable(puppetRoute)).isWaitingForCallback(), true, "_testPuppetRouteOnIncreaseBeforeCallback: E1");
    //     assertEq(PuppetRoute(payable(puppetRoute)).isIncrease(), true, "_testPuppetRouteOnIncreaseBeforeCallback: E2");

    //     // check that all puppets were debited and contract balance lower
    //     uint256 _traderAmountIn = ITraderRoute(traderRoute).getTraderAmountIn();
    //     uint256 _aliceAllowance = orchestrator.getPuppetAllowance(alice, traderRoute) >= _traderAmountIn ? _traderAmountIn : orchestrator.getPuppetAllowance(alice, traderRoute);
    //     uint256 _bobAllowance = orchestrator.getPuppetAllowance(bob, traderRoute) >= _traderAmountIn ? _traderAmountIn : orchestrator.getPuppetAllowance(bob, traderRoute);
    //     uint256 _yossiAllowance = orchestrator.getPuppetAllowance(yossi, traderRoute) >= _traderAmountIn ? _traderAmountIn : orchestrator.getPuppetAllowance(yossi, traderRoute);

    //     assertEq(orchestrator.puppetDepositAccount(alice), _aliceDepositBalanceBefore - _aliceAllowance, "_testPuppetRouteOnIncreaseBeforeCallback: E3");
    //     assertEq(orchestrator.puppetDepositAccount(bob), _bobDepositBalanceBefore - _bobAllowance, "_testPuppetRouteOnIncreaseBeforeCallback: E4");
    //     assertEq(orchestrator.puppetDepositAccount(yossi), _yossiDepositBalanceBefore - _yossiAllowance, "_testPuppetRouteOnIncreaseBeforeCallback: E5");
    //     assertEq(address(orchestrator).balance, _orchestratorBalanceBefore - (_aliceAllowance + _bobAllowance + _yossiAllowance), "_testPuppetRouteOnIncreaseBeforeCallback: E6");
        
    //     // check puppetRoute shares + totalAmount
    //     assertEq(PuppetRoute(payable(puppetRoute)).totalAssets(), _aliceAllowance + _bobAllowance + _yossiAllowance, "_testPuppetRouteOnIncreaseBeforeCallback: E7");

    //     // shares are 1:1 with assets in this case
    //     assertEq(PuppetRoute(payable(puppetRoute)).getPuppetShares(alice), _aliceAllowance, "_testPuppetRouteOnIncreaseBeforeCallback: E8");
    //     assertEq(PuppetRoute(payable(puppetRoute)).getPuppetShares(bob), _bobAllowance, "_testPuppetRouteOnIncreaseBeforeCallback: E9");
    //     assertEq(PuppetRoute(payable(puppetRoute)).getPuppetShares(yossi), _yossiAllowance, "_testPuppetRouteOnIncreaseBeforeCallback: E10");
    //     assertEq(PuppetRoute(payable(puppetRoute)).getPuppetShares(alice), PuppetRoute(payable(puppetRoute)).getPuppetShares(bob), "_testPuppetRouteOnIncreaseBeforeCallback: E11");
    //     assertEq(PuppetRoute(payable(puppetRoute)).getPuppetShares(alice), PuppetRoute(payable(puppetRoute)).getPuppetShares(yossi), "_testPuppetRouteOnIncreaseBeforeCallback: E12");

    //     assertEq(orchestrator.getRouteForRequestKey(_requestKey), puppetRoute, "_testPuppetRouteOnIncreaseBeforeCallback: E13");
    // }

    // function _testPuppetRouteOnIncreaseAfterPositionApproved(uint256 _executionFee, uint256 _orchestratorBalanceBefore, uint256 _aliceDepositBalanceBefore, uint256 _bobDepositBalanceBefore, uint256 _yossiDepositBalanceBefore, uint256 _puppetRouteBalanceBefore) internal {
    //     assertEq(PuppetRoute(payable(puppetRoute)).getIsPositionOpen(), true, "_testPuppetRouteOnIncreaseAfterPositionApproved: E0");
    //     assertEq(PuppetRoute(payable(puppetRoute)).isWaitingForCallback(), false, "_testPuppetRouteOnIncreaseAfterPositionApproved: E1");
    //     assertEq(PuppetRoute(payable(puppetRoute)).isWaitingForCallback(), false, "_testPuppetRouteOnIncreaseAfterPositionApproved: E2");

    //     assertEq(ITraderRoute(traderRoute).getIsWaitingForCallback(), false, "_testPuppetRouteOnIncreaseAfterPositionApproved: E3");
    //     assertEq(address(puppetRoute).balance, _puppetRouteBalanceBefore, "_testPuppetRouteOnIncreaseAfterPositionApproved: E4");
    //     assertEq(address(puppetRoute).balance, 0, "_testPuppetRouteOnIncreaseAfterPositionApproved: E5");

    //     assertEq(_isOpenInterest(puppetRoute), true, "_testPuppetRouteOnIncreaseAfterPositionApproved: E6");

    //     // _executionFee was returned to orchestrator (since we're on fork) - good chance to test _repayBalance in action
    //     uint256 _creditPerPuppet = _executionFee / 3;
    //     assertEq(orchestrator.puppetDepositAccount(alice), _aliceDepositBalanceBefore + _creditPerPuppet, "_testPuppetRouteOnIncreaseAfterPositionApproved: E7");
    //     assertEq(orchestrator.puppetDepositAccount(bob), _bobDepositBalanceBefore + _creditPerPuppet, "_testPuppetRouteOnIncreaseAfterPositionApproved: E8");
    //     assertEq(orchestrator.puppetDepositAccount(yossi), _yossiDepositBalanceBefore + _creditPerPuppet, "_testPuppetRouteOnIncreaseAfterPositionApproved: E9");
    //     assertEq(address(orchestrator).balance, _orchestratorBalanceBefore + _executionFee, "_testPuppetRouteOnIncreaseAfterPositionApproved: E10");
    // }

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

    // function _isOpenInterest(address _account) internal view returns (bool) {
    //     (uint256 _size, uint256 _collateral,,,,,,) = IGMXVault(orchestrator.getGMXVault()).getPosition(_account, collateralToken, indexToken, isLong);

    //     return _size > 0 && _collateral > 0;
    // }

    // function _getAllowanceForRoute(uint256 _traderAmountIn) internal returns (uint256 _totalAllowance) {
    //     bytes32 _routeKey = orchestrator.getTraderRouteKey(trader, collateralToken, indexToken, isLong);
    //     address[] memory _puppets = orchestrator.getPuppetsForRoute(_routeKey);

    //     for (uint256 i = 0; i < _puppets.length; i++) {
    //         address _puppet = _puppets[i];
    //         uint256 _allowance = orchestrator.getPuppetAllowance(_puppet, traderRoute);
    //         if (_allowance > _traderAmountIn) _allowance = _traderAmountIn;
    //         _totalAllowance += _allowance;

    //         assertTrue(_allowance > 0, "_getAllowanceForRoute: E1");
    //     }
    // }

    // function _convertToShares(uint256 _totalAssets, uint256 _totalSupply, uint256 _assets) internal pure returns (uint256 _shares) {
    //     if (_assets == 0) revert("ZeroAmount");

    //     if (_totalAssets == 0) {
    //         _shares = _assets;
    //     } else {
    //         _shares = (_assets * _totalSupply) / _totalAssets;
    //     }

    //     if (_shares == 0) revert("ZeroAmount");
    // }
}