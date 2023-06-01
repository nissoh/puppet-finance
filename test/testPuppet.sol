// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.17;

// import "forge-std/Test.sol";
// import "forge-std/console.sol";

// import {AggregatorV3Interface} from "@chainlink/src/v0.8/interfaces/AggregatorV3Interface.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import {Auth, Authority} from "@solmate/auth/Auth.sol";

// import {Orchestrator} from "../src/Orchestrator.sol";
// import {Route} from "../src/Route.sol";
// import {RevenueDistributor} from "../src/RevenueDistributor.sol";
// import {RouteFactory} from "../src/RouteFactory.sol";

// import {IBase} from "../src/interfaces/IBase.sol";

// import {IGMXVault} from "../src/interfaces/IGMXVault.sol";
// import {IGMXReader} from "../src/interfaces/IGMXReader.sol";
// import {IGMXPositionRouter} from "../src/interfaces/IGMXPositionRouter.sol";

// contract testPuppet is IBase, Test {

//     using SafeERC20 for IERC20;

//     address owner = makeAddr("owner");
//     address trader = makeAddr("trader");
//     address keeper = makeAddr("keeper");
//     address alice = makeAddr("alice");
//     address bob = makeAddr("bob");
//     address yossi = makeAddr("yossi");

//     address collateralToken = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1); // WETH
//     address indexToken = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1); // WETH

//     address gmxVault = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
//     address gmxPositionRouter = 0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868;
//     address GMXPositionRouterKeeper = address(0x11D62807dAE812a0F1571243460Bf94325F43BB7);
//     address revenueDistributor;

//     bool isLong = true;
    
//     uint256 arbitrumFork;

//     Route route;
//     Orchestrator orchestrator;

//     AggregatorV3Interface priceFeed;

//     address constant WETH = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
//     address constant FRAX = address(0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F);
//     address constant USDC = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);

//     function setUp() public {

//         string memory ARBITRUM_RPC_URL = vm.envString("ARBITRUM_RPC_URL");
//         arbitrumFork = vm.createFork(ARBITRUM_RPC_URL);
//         vm.selectFork(arbitrumFork);

//         vm.deal(owner, 100 ether);
//         vm.deal(trader, 100 ether);
//         vm.deal(keeper, 100 ether);
//         vm.deal(alice, 100 ether);
//         vm.deal(bob, 100 ether);
//         vm.deal(yossi, 100 ether);

//         // deploy RevenueDistributor
//         Authority _authority = Authority(0x575F40E8422EfA696108dAFD12cD8d6366982416);
//         revenueDistributor = address(new RevenueDistributor(_authority));

//         // deploy RouteFactory
//         address _routeFactory = address(new RouteFactory());

//         // deploy orchestrator
//         address _gmxRouter = 0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064;
//         address _gmxReader = 0x22199a49A999c351eF7927602CFB187ec3cae489;
//         address _gmxReferralRebatesSender = address(0);
//         bytes32 _referralCode = bytes32(0);

//         GMXInfo memory _gmxInfo = GMXInfo({
//             gmxRouter: _gmxRouter,
//             gmxReader: _gmxReader,
//             gmxVault: gmxVault,
//             gmxPositionRouter: gmxPositionRouter,
//             gmxReferralRebatesSender: _gmxReferralRebatesSender
//         });

//         orchestrator = new Orchestrator(_authority, revenueDistributor, _routeFactory, keeper, _referralCode, _gmxInfo);


//         // set route type
//         vm.startPrank(owner);
//         orchestrator.setRouteType(WETH, WETH, true);

//         // set price feed info
//         address ETH_USD_PRICE_FEED_ADDRESS = address(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612);
//         uint256 ETH_USD_PRICE_FEED_DECIMALS = 8;

//         address[] memory _assets = new address[](1);
//         _assets[0] = WETH;
//         address[] memory _priceFeeds = new address[](1);
//         _priceFeeds[0] = ETH_USD_PRICE_FEED_ADDRESS;
//         uint256[] memory _decimals = new uint256[](1);
//         _decimals[0] = ETH_USD_PRICE_FEED_DECIMALS;

//         orchestrator.setPriceFeeds(_assets, _priceFeeds, _decimals);
//         vm.stopPrank();
//     }

//     function testCorrectFlow() public {
//         uint256 _assets = 1 ether;

//         // trader
//         bytes32 _routeKey = _testRegisterRouteWETH();

//         route = Route(payable(orchestrator.getRoute(_routeKey)));

//         // puppet
//         _testPuppetDeposit(_assets, WETH);
//         _testUpdateRoutesSubscription(_routeKey);
//         _testSetThrottleLimit();
//         _testPuppetWithdraw(_assets, WETH);

//         // route
//         _testIncreasePosition(false);
//         _testIncreasePosition(true);

//         // _testClosePosition();
//     }

//     // ============================================================================================
//     // Internal Test Functions
//     // ============================================================================================

//     //
//     // orchestrator
//     //

//     // Trader

//     function _testRegisterRouteWETH() internal returns (bytes32 _routeKey) {
//         vm.startPrank(trader);

//         vm.expectRevert(); // reverts with ZeroAddress()
//         orchestrator.registerRoute(address(0), address(0), true);

//         vm.expectRevert(); // reverts with NoPriceFeedForAsset()
//         orchestrator.registerRoute(FRAX, WETH, true);

//         _routeKey = orchestrator.registerRoute(WETH, WETH, true);

//         vm.expectRevert(); // reverts with RouteAlreadyRegistered()
//         orchestrator.registerRoute(WETH, WETH, true);

//         address[] memory _pupptsForRoute = orchestrator.getPuppetsForRoute(_routeKey);

//         address payable _route = payable(orchestrator.getRoute(_routeKey));

//         bytes32 _routeTypeKey = orchestrator.getRouteTypeKey(WETH, WETH, true);
//         assertEq(_routeKey, orchestrator.getRouteKey(trader, _routeTypeKey), "_testRegisterRoute: E0");
//         assertEq(_pupptsForRoute.length, 0, "_testRegisterRoute: E1");
//         assertEq(orchestrator.isRoute(_route), true, "_testRegisterRoute: E2");
//         address[] memory _routes = orchestrator.getRoutes();
//         assertEq(_routes[0], _route, "_testRegisterRoute: E3");
//         assertEq(address(Route(_route).orchestrator()), address(orchestrator), "_testRegisterRoute: E4");
//         vm.stopPrank();
//     }

//     // Puppet

//     function _testPuppetDeposit(uint256 _assets, address _token) internal {
//         _dealERC20(_token, alice, _assets);
//         _dealERC20(_token, bob, _assets);
//         _dealERC20(_token, yossi, _assets);

//         uint256 _balanceBefore = IERC20(_token).balanceOf(address(orchestrator));

//         // alice
//         uint256 _aliceBalanceBefore = address(alice).balance;
//         vm.startPrank(alice);

//         vm.expectRevert(); // reverts with NoPriceFeedForCollateralToken()
//         orchestrator.deposit{ value: _assets }(_assets, FRAX, alice);
        
//         uint256 _puppetAssetsBefore = orchestrator.puppetDepositAccount(bob, _token);
//         orchestrator.deposit{ value: _assets }(_assets, _token, alice);
        
//         assertEq(orchestrator.puppetDepositAccount(alice, _token), _puppetAssetsBefore + _assets, "_testPuppetDeposit: E0");
//         assertEq(_aliceBalanceBefore - _assets, address(alice).balance, "_testPuppetDeposit: E1");
//         vm.stopPrank();

//         // bob
//         uint256 _bobBalanceBefore = IERC20(_token).balanceOf(bob);
//         vm.startPrank(bob);
//         _approve(address(orchestrator), _token, _assets);
//         _puppetAssetsBefore = orchestrator.puppetDepositAccount(bob, _token);
//         orchestrator.deposit(_assets, _token, bob);
//         assertEq(orchestrator.puppetDepositAccount(bob, _token), _puppetAssetsBefore + _assets, "_testPuppetDeposit: E2");
//         assertEq(_bobBalanceBefore - _assets, IERC20(_token).balanceOf(bob), "_testPuppetDeposit: E3");
//         vm.stopPrank();

//         // yossi
//         uint256 _yossiBalanceBefore = IERC20(_token).balanceOf(yossi);
//         vm.startPrank(yossi);
//         _approve(address(orchestrator), _token, _assets);
//         _puppetAssetsBefore = orchestrator.puppetDepositAccount(yossi, _token);
//         orchestrator.deposit(_assets, _token, yossi);
//         assertEq(orchestrator.puppetDepositAccount(yossi, _token), _puppetAssetsBefore + _assets, "_testPuppetDeposit: E4");
//         assertEq(_yossiBalanceBefore - _assets, IERC20(_token).balanceOf(yossi), "_testPuppetDeposit: E5");
//         vm.stopPrank();

//         assertEq(IERC20(_token).balanceOf(address(orchestrator)) - _balanceBefore, _assets * 3, "_testPuppetDeposit: E3");
//         assertTrue(IERC20(_token).balanceOf(address(orchestrator)) - _balanceBefore > 0, "_testPuppetDeposit: E4");
//     }

//     function _testUpdateRoutesSubscription(bytes32 _routeKey) internal {
//         uint256[] memory _allowances = new uint256[](1);
//         address[] memory _traders = new address[](1);
//         _traders[0] = trader;
//         _allowances[0] = 10; // 10% of the puppet's deposit account

//         bytes32 _routeTypeKey = orchestrator.getRouteTypeKey(WETH, WETH, true);
//         address _route = orchestrator.getRoute(_routeKey);

//         uint256[] memory _faultyAllowance = new uint256[](1);
//         _faultyAllowance[0] = 101;
//         address[] memory _faultyTraders = new address[](2);
//         _faultyTraders[0] = alice;
//         _faultyTraders[1] = bob;
//         bytes32 _faultyRouteTypeKey = orchestrator.getRouteTypeKey(FRAX, WETH, true);

//         vm.startPrank(alice);

//         vm.expectRevert(); // reverts with MismatchedInputArrays()
//         orchestrator.updateRoutesSubscription(_faultyTraders, _allowances, _routeTypeKey, true);

//         vm.expectRevert(); // reverts with InvalidAllowancePercentage()
//         orchestrator.updateRoutesSubscription(_traders, _faultyAllowance, _routeTypeKey, true);

//         vm.expectRevert(); // reverts with RouteNotRegistered()
//         orchestrator.updateRoutesSubscription(_traders, _allowances, _faultyRouteTypeKey, true);

//         orchestrator.updateRoutesSubscription(_traders, _allowances, _routeTypeKey, true);
//         assertEq(orchestrator.getPuppetAllowancePercentage(alice, _route), _allowances[0], "_testUpdateRoutesSubscription: E0");
//         assertEq(orchestrator.getPuppetsForRoute(_routeKey)[0], alice, "_testUpdateRoutesSubscription: E1");
//         assertEq(orchestrator.getPuppetsForRoute(_routeKey).length, 1, "_testUpdateRoutesSubscription: E2");
//         vm.stopPrank();

//         vm.startPrank(bob);
//         orchestrator.updateRoutesSubscription(_traders, _allowances, _routeTypeKey, true);
//         assertEq(orchestrator.getPuppetAllowancePercentage(bob, _route), _allowances[0], "_testUpdateRoutesSubscription: E3");
//         assertEq(orchestrator.getPuppetsForRoute(_routeKey)[1], bob, "_testUpdateRoutesSubscription: E4");
//         assertEq(orchestrator.getPuppetsForRoute(_routeKey).length, 2, "_testUpdateRoutesSubscription: E5");
//         // again
//         orchestrator.updateRoutesSubscription(_traders, _allowances, _routeTypeKey, true);
//         assertEq(orchestrator.getPuppetAllowancePercentage(bob, _route), _allowances[0], "_testUpdateRoutesSubscription: E03");
//         assertEq(orchestrator.getPuppetsForRoute(_routeKey)[1], bob, "_testUpdateRoutesSubscription: E04");
//         assertEq(orchestrator.getPuppetsForRoute(_routeKey).length, 2, "_testUpdateRoutesSubscription: E05");
//         vm.stopPrank();

//         vm.startPrank(yossi);
//         orchestrator.updateRoutesSubscription(_traders, _allowances, _routeTypeKey, true);
//         assertEq(orchestrator.getPuppetAllowancePercentage(yossi, _route), _allowances[0], "_testUpdateRoutesSubscription: E6");
//         assertEq(orchestrator.getPuppetsForRoute(_routeKey)[2], yossi, "_testUpdateRoutesSubscription: E7");
//         assertEq(orchestrator.getPuppetsForRoute(_routeKey).length, 3, "_testUpdateRoutesSubscription: E8");
//         vm.stopPrank();

//         assertTrue(orchestrator.getPuppetAllowancePercentage(alice, _route) > 0, "_testUpdateRoutesSubscription: E9");
//         assertTrue(orchestrator.getPuppetAllowancePercentage(bob, _route) > 0, "_testUpdateRoutesSubscription: E10");
//         assertTrue(orchestrator.getPuppetAllowancePercentage(yossi, _route) > 0, "_testUpdateRoutesSubscription: E11");
//     }

//     function _testSetThrottleLimit() internal {

//         vm.startPrank(alice);
//         orchestrator.setThrottleLimit(1 days, address(route));
//         assertEq(orchestrator.throttleLimits(alice, address(route)), 1 days, "_testSetThrottleLimit: E0");
//         vm.stopPrank();

//         vm.startPrank(bob);
//         orchestrator.setThrottleLimit(2 days, address(route));
//         assertEq(orchestrator.throttleLimits(bob, address(route)), 2 days, "_testSetThrottleLimit: E1");
//         vm.stopPrank();

//         vm.startPrank(yossi);
//         orchestrator.setThrottleLimit(3 days, address(route));
//         assertEq(orchestrator.throttleLimits(yossi, address(route)), 3 days, "_testSetThrottleLimit: E2");
//         vm.stopPrank();
//     }

//     function _testPuppetWithdraw(uint256 _assets, address _token) internal {
//         uint256 _aliceDepositAccountBalanceBefore = orchestrator.puppetDepositAccount(alice, _token);
//         uint256 _bobDepositAccountBalanceBefore = orchestrator.puppetDepositAccount(bob, _token);
//         uint256 _yossiDepositAccountBalanceBefore = orchestrator.puppetDepositAccount(yossi, _token);

//         _testPuppetDeposit(_assets, _token);

//         vm.startPrank(alice);
//         uint256 _orchestratorBalanceBefore = IERC20(_token).balanceOf(address(orchestrator));
//         uint256 _puppetBalanceBefore = IERC20(_token).balanceOf(alice);
//         orchestrator.withdraw(_assets, _token, alice, false);
//         uint256 _puppetBalanceAfter = IERC20(_token).balanceOf(alice);
//         uint256 _orchestratorBalanceAfter = IERC20(_token).balanceOf(address(orchestrator));
//         vm.stopPrank();

//         assertEq(_orchestratorBalanceBefore - _orchestratorBalanceAfter, _assets, "_testPuppetWithdraw: E0");
//         assertEq(orchestrator.puppetDepositAccount(alice, _token), _aliceDepositAccountBalanceBefore, "_testPuppetWithdraw: E1");
//         assertEq(_puppetBalanceBefore + _assets, _puppetBalanceAfter, "_testPuppetWithdraw: E2");

//         vm.startPrank(bob);
//         _orchestratorBalanceBefore = IERC20(_token).balanceOf(address(orchestrator));
//         _puppetBalanceBefore = IERC20(_token).balanceOf(bob);
//         orchestrator.withdraw(_assets, _token, bob, false);
//         _puppetBalanceAfter = IERC20(_token).balanceOf(bob);
//         _orchestratorBalanceAfter = IERC20(_token).balanceOf(address(orchestrator));
//         vm.stopPrank();

//         assertEq(_orchestratorBalanceBefore - _orchestratorBalanceAfter, _assets, "_testPuppetWithdraw: E3");
//         assertEq(orchestrator.puppetDepositAccount(bob, _token), _bobDepositAccountBalanceBefore, "_testPuppetWithdraw: E4");
//         assertEq(_puppetBalanceBefore + _assets, _puppetBalanceAfter, "_testPuppetWithdraw: E5");

//         vm.startPrank(yossi);
//         _orchestratorBalanceBefore = IERC20(_token).balanceOf(address(orchestrator));
//         _puppetBalanceBefore = address(yossi).balance;
//         orchestrator.withdraw(_assets, _token, yossi, true);
//         _puppetBalanceAfter = address(yossi).balance;
//         _orchestratorBalanceAfter = IERC20(_token).balanceOf(address(orchestrator));
//         vm.stopPrank();

//         assertEq(_orchestratorBalanceBefore - _orchestratorBalanceAfter, _assets, "_testPuppetWithdraw: E6");
//         assertEq(orchestrator.puppetDepositAccount(yossi, _token), _yossiDepositAccountBalanceBefore, "_testPuppetWithdraw: E7");
//         assertEq(_puppetBalanceBefore + _assets, _puppetBalanceAfter, "_testPuppetWithdraw: E8");
//     }

//     //
//     // Route
//     //

//     // open position
//     // add collateral + increase size
//     // trader adds ETH collateral
//     function _testIncreasePosition(bool _addCollateralToAnExistingPosition) internal {
//         // (, int256 _price,,,) = priceFeed.latestRoundData();

//         uint256 _minOut = 0; // _minOut can be zero if no swap is required
//         uint256 _acceptablePrice = type(uint256).max; // the USD value of the max (for longs) or min (for shorts) index price acceptable when executing the request
//         uint256 _executionFee = 180000000000000; // can be set to PositionRouter.minExecutionFee() https://arbiscan.io/address/0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868#readContract#F26

//         // TODO: get data dynamically
//         // Available amount in USD: PositionRouter.maxGlobalLongSizes(indexToken) - Vault.guaranteedUsd(indexToken)
//         // uint256 _size = IGMXPositionRouter(orchestrator.getGMXPositionRouter()).maxGlobalLongSizes(indexToken) - IGMXVault(orchestrator.getGMXVault()).guaranteedUsd(indexToken);
//         uint256 _size = 92114231411087324391798166152938732778 - 86226694002961445455749333837394963689;
        
//         // the USD value of the change in position size
//         uint256 _sizeDelta = _size / 20;

//         // the amount of tokenIn to deposit as collateral
//         uint256 _amountInTrader = 10 ether;

//         bytes memory _traderPositionData = abi.encode(_minOut, _sizeDelta, _acceptablePrice);

//         address[] memory _path = new address[](1);
//         _path[0] = FRAX;
//         bytes memory _faultyTraderSwapData = abi.encode(_path, _amountInTrader, _minOut);
//         _path[0] = WETH;
//         bytes memory _traderSwapData = abi.encode(_path, _amountInTrader, _minOut);

//         assertEq(orchestrator.getIsPaused(), false, "_testCreateInitialPosition: E0");

//         vm.expectRevert(); // reverts with NotTrader()
//         route.createPositionRequest{ value: _amountInTrader + _executionFee }(_traderPositionData, _traderSwapData, _executionFee, true);

//         vm.startPrank(trader);

//         vm.expectRevert(); // reverts with InvalidExecutionFee()
//         route.createPositionRequest{ value: _amountInTrader + _executionFee + 10 }(_traderPositionData, _traderSwapData, _executionFee, true);

//         vm.expectRevert(); // reverts with InvalidPath()
//         route.createPositionRequest{ value: _amountInTrader + _executionFee }(_traderPositionData, _faultyTraderSwapData, _executionFee, true);

//         if (!_addCollateralToAnExistingPosition) {
//             assertEq(orchestrator.lastPositionOpenedTimestamp(alice, address(route)), 0, "_testCreateInitialPosition: E3");
//             assertEq(orchestrator.lastPositionOpenedTimestamp(bob, address(route)), 0, "_testCreateInitialPosition: E4");
//             assertEq(orchestrator.lastPositionOpenedTimestamp(yossi, address(route)), 0, "_testCreateInitialPosition: E5");
//         }

//         vm.stopPrank();

//         uint256 _aliceDepositAccountBalanceBefore = orchestrator.puppetDepositAccount(alice, WETH);
//         uint256 _bobDepositAccountBalanceBefore = orchestrator.puppetDepositAccount(bob, WETH);
//         uint256 _yossiDepositAccountBalanceBefore = orchestrator.puppetDepositAccount(yossi, WETH);
//         uint256 _orchestratorBalanceBefore = IERC20(WETH).balanceOf(address(orchestrator));
//         uint256 _traderBalanceBeforeCollatToken = IERC20(WETH).balanceOf(trader);
//         uint256 _traderBalanceBeforeEth = address(trader).balance;

//         (uint256 _positionIndexBefore, uint256 _addCollateralRequestsIndexBefore,,) = route.positionInfo();

//         // 1. createPosition
//         bytes32 _requestKey = _testCreatePosition(_traderPositionData, _traderSwapData, _amountInTrader, _executionFee, _addCollateralToAnExistingPosition);

//         // if (_addCollateralToAnExistingPosition) _testRequestToAddCollateralToPosition(_requestKey);

//         if (!_addCollateralToAnExistingPosition) {
//             assertTrue(IERC20(WETH).balanceOf(address(orchestrator)) < _orchestratorBalanceBefore, "_testCreateInitialPosition: E05");
//             assertTrue(orchestrator.puppetDepositAccount(alice, WETH) < _aliceDepositAccountBalanceBefore, "_testCreateInitialPosition: E06");
//             assertTrue(orchestrator.puppetDepositAccount(bob, WETH) < _bobDepositAccountBalanceBefore, "_testCreateInitialPosition: E07");
//             assertTrue(orchestrator.puppetDepositAccount(yossi, WETH) < _yossiDepositAccountBalanceBefore, "_testCreateInitialPosition: E08");
//         }

//         vm.expectRevert(); // reverts with NotCallbackCaller()
//         route.gmxPositionCallback(_requestKey, true, true);

//         (,uint256 _collateralInPositionGMXBefore,,,,,,) = IGMXVault(gmxVault).getPosition(address(route), collateralToken, indexToken, isLong); 

//         // 2. executePosition
//         vm.startPrank(GMXPositionRouterKeeper); // keeper
//         IGMXPositionRouter(gmxPositionRouter).executeIncreasePositions(type(uint256).max, payable(address(route)));
//         vm.stopPrank();

//         (uint256 _positionIndexAfter, uint256 _addCollateralRequestsIndexAfter,,) = route.positionInfo();
        
//         assertEq(_addCollateralRequestsIndexBefore + 1, _addCollateralRequestsIndexAfter, "_testCreateInitialPosition: E07");
//         assertEq(address(route).balance, 0, "_testCreateInitialPosition: E007");
//         assertEq(IERC20(WETH).balanceOf(address(route)), 0, "_testCreateInitialPosition: E008");

//         if (!_addCollateralToAnExistingPosition) {
//             if (_isOpenInterest(address(route))) {
//                 (,, uint256 _totalSupply, uint256 _totalAssets) = route.positionInfo();

//                 assertTrue(!route.keeperRequests(_requestKey), "_testCreateInitialPosition: E006");
//                 assertEq(_positionIndexBefore, _positionIndexAfter, "_testCreateInitialPosition: E0007");
//                 assertApproxEqAbs(address(trader).balance, _traderBalanceBeforeEth - _amountInTrader - _executionFee, 1e18, "_testCreateInitialPosition: E009");
//                 assertEq(route.participantShares(_positionIndexAfter, alice), route.participantShares(_positionIndexAfter, bob), "_testCreateInitialPosition: E0010");
//                 assertEq(route.participantShares(_positionIndexAfter, alice), route.participantShares(_positionIndexAfter, yossi), "_testCreateInitialPosition: E0011");
//                 assertTrue(route.participantShares(_positionIndexAfter, trader) >= route.participantShares(_positionIndexAfter, alice), "_testCreateInitialPosition: E0012");
//                 uint256 _totalParticipantShares = route.participantShares(_positionIndexAfter, alice) + route.participantShares(_positionIndexAfter, bob) + route.participantShares(_positionIndexAfter, yossi) + route.participantShares(_positionIndexAfter, trader);
//                 assertEq(_totalSupply, _totalParticipantShares, "_testCreateInitialPosition: E0013");
//                 assertEq(_totalAssets, _totalSupply, "_testCreateInitialPosition: E0014");
//                 assertTrue(_totalAssets > 0, "_testCreateInitialPosition: E0015");
//                 // revert("asd");
//             } else {
//                 (,, uint256 _totalSupply, uint256 _totalAssets) = route.positionInfo();

//                 assertEq(_positionIndexBefore + 1, _positionIndexAfter, "_testCreateInitialPosition: E06");
//                 assertEq(route.keeperRequests(_requestKey), false, "_testCreateInitialPosition: E9");
//                 assertEq(_totalSupply, 0, "_testCreateInitialPosition: E10");
//                 assertEq(_totalAssets, 0, "_testCreateInitialPosition: E11");
//                 assertEq(IERC20(WETH).balanceOf(address(route)), 0, "_testCreateInitialPosition: E12");
//                 assertEq(address(route).balance, 0, "_testCreateInitialPosition: E13");
//                 assertEq(orchestrator.puppetDepositAccount(alice, WETH), _aliceDepositAccountBalanceBefore, "_testCreateInitialPosition: E14");
//                 assertEq(orchestrator.puppetDepositAccount(bob, WETH), _bobDepositAccountBalanceBefore, "_testCreateInitialPosition: E15");
//                 assertEq(orchestrator.puppetDepositAccount(yossi, WETH), _yossiDepositAccountBalanceBefore, "_testCreateInitialPosition: E16");
//                 assertTrue(orchestrator.puppetDepositAccount(alice, WETH) > 0, "_testCreateInitialPosition: E014");
//                 assertTrue(orchestrator.puppetDepositAccount(bob, WETH) > 0, "_testCreateInitialPosition: E015");
//                 assertTrue(orchestrator.puppetDepositAccount(yossi, WETH) > 0, "_testCreateInitialPosition: E016");
//                 assertEq(IERC20(WETH).balanceOf(address(orchestrator)), _orchestratorBalanceBefore, "_testCreateInitialPosition: E17");
//                 assertEq(IERC20(WETH).balanceOf(trader) - _traderBalanceBeforeCollatToken, _amountInTrader, "_testCreateInitialPosition: E18");
//                 revert("we want to test on successfull execution");
//             }
//         } else {
//             // added collateral to an existing position request
//             (,, uint256 _totalSupply, uint256 _totalAssets) = route.positionInfo();
//             (,uint256 _collateralInPositionGMXAfter,,,,,,) = IGMXVault(gmxVault).getPosition(address(route), collateralToken, indexToken, isLong); 
//             if (_collateralInPositionGMXAfter > _collateralInPositionGMXBefore) {
//                 // adding collatral request was executed
//                 // todo 1 - check that new shares were added to trader
//                 // todo

//                 revert("asd");

//             } else {
//                 // adding collatral request was cancelled
//                 revert("we want to test on successfull execution - 1");
//             }
//         } 
//     }

//     function _testRequestToAddCollateralToPosition(bytes32 _requestKey) internal {

//     }

//     function _testCreatePosition(bytes memory _traderPositionData, bytes memory _traderSwapData, uint256 _amountInTrader, uint256 _executionFee, bool _addCollateralToAnExistingPosition) internal returns (bytes32 _requestKey) {
//         // add weth to yossi's deposit account so he can join the increase
//         if (_addCollateralToAnExistingPosition) {
//             vm.startPrank(yossi);
//             orchestrator.deposit{ value: _amountInTrader }(_amountInTrader, WETH, yossi);
//             vm.stopPrank();
//         }

//         uint256 _orchesratorBalanceBefore = IERC20(WETH).balanceOf(address(orchestrator));
//         uint256 _aliceDepositAccountBalanceBefore = orchestrator.puppetDepositAccount(alice, WETH);
//         uint256 _bobDepositAccountBalanceBefore = orchestrator.puppetDepositAccount(bob, WETH);
//         uint256 _yossiDepositAccountBalanceBefore = orchestrator.puppetDepositAccount(yossi, WETH);
//         (,uint256 _addCollateralRequestsIndexBefore,,) = route.positionInfo();

//     //     price 186061955088
//     // adjusted price 1860619550880000000000
//     // decimals 8
//     // collateralInPosition0 18872759229593706053197558384222811
//     // collateralInPosition1 10143266107607
//     // collateralInPosition2 5451553007
        
//         // OI
//         // totalRouteSupply 10300000000000000000
//         // totalRouteCollateral 811959552988093991235880
//         // participantShares 10000000000000000000
//         // traderOwnedCollateral 788310245619508729355223
//         // collateralIncreaseRatio 12685360942050

//         vm.startPrank(trader);
//         _requestKey = route.createPositionRequest{ value: _amountInTrader + _executionFee }(_traderPositionData, _traderSwapData, _executionFee, true);
//         vm.stopPrank();

//         (uint256 _puppetsAmountIn, uint256 _traderAmountInReq, uint256 _traderRequestShares, uint256 _requestTotalSupply, uint256 _requestTotalAssets) = route.addCollateralRequests(route.requestKeyToAddCollateralRequestsIndex(_requestKey));
//         (uint256 _positionIndex, uint256 _addCollateralRequestsIndexAfter, uint256 _totalSupply, uint256 _totalAssets) = route.positionInfo();

//         assertEq(_traderAmountInReq, _amountInTrader, "_testCreatePosition: E6");
//         assertEq(_traderAmountInReq, _traderRequestShares, "_testCreatePosition: E7");
//         assertTrue(_requestTotalSupply > 0, "_testCreatePosition: E8");
//         assertTrue(_requestTotalAssets >= _amountInTrader, "_testCreatePosition: E9");

//         address[] memory _puppets = route.getPuppets();
//         (address[] memory _puppetsToAdjust, uint256[] memory _puppetsShares, uint256[] memory _puppetsAmounts) = route.getPuppetsRequestInfo(_requestKey);

//         assertEq(_positionIndex, 0, "_testCreatePosition: E10");

//         if (_addCollateralToAnExistingPosition) {
//             assertTrue(_totalSupply > 0, "_testCreatePosition: E011");
//             assertTrue(_totalAssets > 0, "_testCreatePosition: E012");
//             assertTrue(_puppetsToAdjust[0] != address(0), "_testCreatePosition: E021");
//             assertEq(_puppetsShares[0], 0, "_testCreatePosition: E032");
//             assertEq(_puppetsShares[1], 0, "_testCreatePosition: E033");
//             assertTrue(_puppetsShares[2] > 0, "_testCreatePosition: E034"); // we increased Yossi's balance so he can join on the increase
//         } else {
//             assertEq(_totalSupply, 0, "_testCreatePosition: E11");
//             assertEq(_totalAssets, 0, "_testCreatePosition: E12");
//             assertEq(_puppetsToAdjust[0], address(0), "_testCreatePosition: E21");
//             assertTrue(_puppetsShares[0] > 0, "_testCreatePosition: E32");
//             assertTrue(_puppetsShares[1] > 0, "_testCreatePosition: E33");
//             assertTrue(_puppetsShares[2] > 0, "_testCreatePosition: E34");
//             assertEq(_puppetsShares[0], _puppetsShares[2], "_testCreatePosition: E29");
//             assertEq(_puppetsAmounts[0], _puppetsAmounts[2], "_testCreatePosition: E31");
//         }

//         assertEq(IERC20(WETH).balanceOf(address(route)), 0, "_testCreatePosition: E14");
//         assertEq(route.requestKeyToAddCollateralRequestsIndex(_requestKey), _addCollateralRequestsIndexBefore, "_testCreatePosition: E15");
//         assertEq(orchestrator.lastPositionOpenedTimestamp(alice, address(route)), block.timestamp, "_testCreatePosition: E16");
//         assertEq(orchestrator.lastPositionOpenedTimestamp(bob, address(route)), block.timestamp, "_testCreatePosition: E17");
//         assertEq(orchestrator.lastPositionOpenedTimestamp(yossi, address(route)), block.timestamp, "_testCreatePosition: E18");
//         assertEq(_addCollateralRequestsIndexAfter, _addCollateralRequestsIndexBefore + 1, "_testCreatePosition: E19");
//         assertEq(IERC20(WETH).balanceOf(address(orchestrator)) + _puppetsAmountIn, _orchesratorBalanceBefore, "_testCreatePosition: E20");
//         assertEq(_puppetsShares.length, 3, "_testCreatePosition: E22");
//         assertEq(_puppetsAmounts.length, 3, "_testCreatePosition: E23");
//         assertEq(_puppets.length, 3, "_testCreatePosition: E24");
//         assertEq(_aliceDepositAccountBalanceBefore - _puppetsAmounts[0], orchestrator.getPuppetAccountBalance(alice, WETH), "_testCreatePosition: E25");
//         assertEq(_bobDepositAccountBalanceBefore - _puppetsAmounts[1], orchestrator.getPuppetAccountBalance(bob, WETH), "_testCreatePosition: E26");
//         assertEq(_yossiDepositAccountBalanceBefore - _puppetsAmounts[2], orchestrator.getPuppetAccountBalance(yossi, WETH), "_testCreatePosition: E27");
//         assertEq(_puppetsShares[0], _puppetsShares[1], "_testCreatePosition: E28");
//         assertEq(_puppetsAmounts[0], _puppetsAmounts[1], "_testCreatePosition: E30");
//     }

//     // ============================================================================================
//     // Internal Helper Functions
//     // ============================================================================================

//     function _dealERC20(address _token, address _recipient , uint256 _amount) internal {
//         deal({ token: address(_token), to: _recipient, give: _amount});
//     }

//     function _approve(address _spender, address _token, uint256 _amount) internal {
//         IERC20(_token).safeApprove(_spender, 0);
//         IERC20(_token).safeApprove(_spender, _amount);
//     }

//     function _isOpenInterest(address _account) internal view returns (bool) {
//         (uint256 _size, uint256 _collateral,,,,,,) = IGMXVault(gmxVault).getPosition(_account, collateralToken, indexToken, isLong);

//         return _size > 0 && _collateral > 0;
//     }
// }