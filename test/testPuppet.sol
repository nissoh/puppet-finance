// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// import "forge-std/Test.sol";
// import "forge-std/console.sol";

// import {AggregatorV3Interface} from "@chainlink/src/v0.8/interfaces/AggregatorV3Interface.sol";

// import {Orchestrator} from "../src/Orchestrator.sol";
// import {Route} from "../src/Route.sol";

// import {IGMXVault} from "../src/interfaces/IGMXVault.sol";
// import {IGMXReader} from "../src/interfaces/IGMXReader.sol";
// import {IGMXPositionRouter} from "../src/interfaces/IGMXPositionRouter.sol";

// contract testPuppet is Test {

//     address owner = makeAddr("owner");
//     address trader = makeAddr("trader");
//     address keeper = makeAddr("keeper");
//     address alice = makeAddr("alice");
//     address bob = makeAddr("bob");
//     address yossi = makeAddr("yossi");

//     address route;

//     address collateralToken = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1); // WETH
//     address indexToken = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1); // WETH

//     address GMXPositionRouterKeeper = address(0x11D62807dAE812a0F1571243460Bf94325F43BB7);

//     bool isLong = true;
    
//     uint256 arbitrumFork;

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

//         // deploy orchestrator
//         address _gmxRouter = 0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064;
//         address _gmxReader = 0x22199a49A999c351eF7927602CFB187ec3cae489;
//         address _gmxVault = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
//         address _gmxPositionRouter = 0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868;
//         address _gmxCallbackCaller = 0x11D62807dAE812a0F1571243460Bf94325F43BB7;
//         address _gmxReferralRebatesSender = address(0);
//         bytes32 _referralCode = bytes32(0);
//         orchestrator = new Orchestrator(owner, address(0), keeper, _gmxRouter, _gmxReader, _gmxVault, _gmxPositionRouter, _gmxCallbackCaller, _gmxReferralRebatesSender, _referralCode);

//         // set price feed info
//         address ETH_USD_PRICE_FEED_ADDRESS = address(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612);
//         uint256 ETH_USD_PRICE_FEED_DECIMALS = 8;

//         address[] memory _assets = new address[](1);
//         _assets[0] = WETH;
//         address[] memory _priceFeeds = new address[](1);
//         _priceFeeds[0] = ETH_USD_PRICE_FEED_ADDRESS;
//         uint256[] memory _decimals = new uint256[](1);
//         _decimals[0] = ETH_USD_PRICE_FEED_DECIMALS;

//         vm.startPrank(owner);
//         orchestrator.setPriceFeedsInfo(_assets, _priceFeeds, _decimals);
//         vm.stopPrank();
//     }

//     function testCorrectFlow() public {
//         uint256 _assets = 1 ether;

//         bytes32 _routeKey = _testRegisterRouteWETH();

//         // _testPuppetDeposit(_assets);
//         // _testUpdateRoutesSubscription(_routeKey);

//         // _testCreateInitialPosition();
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

//         address _route = orchestrator.getRoute(_routeKey);

//         assertEq(_routeKey, orchestrator.getRouteKey(trader, WETH, WETH, true), "_testRegisterRoute: E0");
//         assertEq(_pupptsForRoute.length, 0, "_testRegisterRoute: E1");
//         assertEq(orchestrator.isRoute(_route), true, "_testRegisterRoute: E2");
//         vm.stopPrank();
//     }

//     // // Puppet

//     // function _testPuppetDeposit(uint256 _assets) internal {
//     //     // alice
//     //     vm.startPrank(alice);
//     //     vm.expectRevert(); // reverts with InvalidAmount()
//     //     orchestrator.depositToAccount(_assets, alice);
//     //     orchestrator.depositToAccount{ value: _assets }(_assets, alice);
//     //     assertEq(orchestrator.puppetDepositAccount(alice), _assets, "_testPuppetDeposit: E0");
//     //     vm.stopPrank();

//     //     // bob
//     //     vm.prank(bob);
//     //     orchestrator.depositToAccount{ value: _assets }(_assets, bob);
//     //     assertEq(orchestrator.puppetDepositAccount(bob), _assets, "_testPuppetDeposit: E1");

//     //     // yossi
//     //     vm.prank(yossi);
//     //     orchestrator.depositToAccount{ value: _assets }(_assets, yossi);
//     //     assertEq(orchestrator.puppetDepositAccount(yossi), _assets, "_testPuppetDeposit: E2");

//     //     assertEq(address(orchestrator).balance, _assets * 3, "_testPuppetDeposit: E3");
//     //     assertTrue(address(orchestrator).balance > 0, "_testPuppetDeposit: E4");
//     // }

//     // function _testUpdateRoutesSubscription(bytes32 _routeKey) internal {
//     //     uint256[] memory _allowances = new uint256[](1);
//     //     address[] memory _traders = new address[](1);
//     //     _traders[0] = trader;

//     //     vm.startPrank(alice);
//     //     _allowances[0] = orchestrator.puppetDepositAccount(alice);
//     //     vm.expectRevert(); // reverts with InsufficientPuppetFunds()
//     //     orchestrator.updateRoutesSubscription(_traders, _allowances, collateralToken, indexToken, isLong, true);

//     //     _allowances[0] = orchestrator.puppetDepositAccount(alice) / orchestrator.solvencyMargin();
//     //     orchestrator.updateRoutesSubscription(_traders, _allowances, collateralToken, indexToken, isLong, true);

//     //     assertEq(orchestrator.getPuppetAllowance(alice, traderRoute), _allowances[0], "_testUpdateRoutesSubscription: E0");
//     //     assertEq(orchestrator.getPuppetsForRoute(_routeKey)[0], alice, "_testUpdateRoutesSubscription: E1");
//     //     assertEq(orchestrator.getPuppetsForRoute(_routeKey).length, 1, "_testUpdateRoutesSubscription: E2");
//     //     vm.stopPrank();

//     //     vm.startPrank(bob);
//     //     orchestrator.updateRoutesSubscription(_traders, _allowances, collateralToken, indexToken, isLong, true);
//     //     assertEq(orchestrator.getPuppetAllowance(bob, traderRoute), _allowances[0], "_testUpdateRoutesSubscription: E3");
//     //     assertEq(orchestrator.getPuppetsForRoute(_routeKey)[1], bob, "_testUpdateRoutesSubscription: E4");
//     //     assertEq(orchestrator.getPuppetsForRoute(_routeKey).length, 2, "_testUpdateRoutesSubscription: E5");
//     //     vm.stopPrank();

//     //     vm.startPrank(yossi);
//     //     orchestrator.updateRoutesSubscription(_traders, _allowances, collateralToken, indexToken, isLong, true);
//     //     assertEq(orchestrator.getPuppetAllowance(yossi, traderRoute), _allowances[0], "_testUpdateRoutesSubscription: E6");
//     //     assertEq(orchestrator.getPuppetsForRoute(_routeKey)[2], yossi, "_testUpdateRoutesSubscription: E7");
//     //     assertEq(orchestrator.getPuppetsForRoute(_routeKey).length, 3, "_testUpdateRoutesSubscription: E8");
//     //     vm.stopPrank();

//     //     assertTrue(orchestrator.getPuppetAllowance(alice, traderRoute) > 0, "_testUpdateRoutesSubscription: E9");
//     //     assertTrue(orchestrator.getPuppetAllowance(bob, traderRoute) > 0, "_testUpdateRoutesSubscription: E10");
//     //     assertTrue(orchestrator.getPuppetAllowance(yossi, traderRoute) > 0, "_testUpdateRoutesSubscription: E11");
//     // }

//     // //
//     // // TraderRoute
//     // //

//     // // open position
//     // // add collateral + increase size
//     // function _testCreateInitialPosition() internal {
//     //     // (, int256 _price,,,) = priceFeed.latestRoundData();

//     //     uint256 _minOut = 0; // _minOut can be zero if no swap is required
//     //     uint256 _acceptablePrice = type(uint256).max; // the USD value of the max (for longs) or min (for shorts) index price acceptable when executing the request
//     //     uint256 _executionFee = 180000000000000; // can be set to PositionRouter.minExecutionFee() https://arbiscan.io/address/0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868#readContract#F26

//     //     // TODO - // Available amount in USD: PositionRouter.maxGlobalLongSizes(indexToken) - Vault.guaranteedUsd(indexToken)
//     //     // uint256 _size = IGMXPositionRouter(orchestrator.getGMXPositionRouter()).maxGlobalLongSizes(indexToken) - IGMXVault(orchestrator.getGMXVault()).guaranteedUsd(indexToken);
//     //     uint256 _size = 82698453891127247668603775976796325121 - 72755589402161323824061129657679280046;
//     //     // the USD value of the change in position size
//     //     uint256 _sizeDeltaTrader = _size / 50;
//     //     uint256 _sizeDeltaPuppet = _size / 50;

//     //     // the amount of tokenIn to deposit as collateral
//     //     uint256 _amountInTrader = 10 ether;
//     //     uint256 _amountInPuppet = _getAllowanceForRoute(_amountInTrader - _executionFee) - _executionFee;

//     //     bytes memory _traderData = abi.encode(_minOut, _sizeDeltaTrader, _acceptablePrice, _executionFee);
//     //     bytes memory _puppetsData = abi.encode(_amountInPuppet, _minOut, _sizeDeltaPuppet, _acceptablePrice, _executionFee);

//     //     assertEq(ITraderRoute(traderRoute).getIsWaitingForCallback(), false, "_testCreateInitialPosition: E0");

//     //     vm.expectRevert(); // reverts with NotTrader()
//     //     ITraderRoute(traderRoute).createPosition(_traderData, _puppetsData, true, true);

//     //     uint256 _traderBalanceBefore = address(trader).balance;

//     //     vm.startPrank(trader);

//     //     vm.expectRevert(); // reverts with `Arithmetic over/underflow` (on subtracting _executionFee from _amountInTrader) 
//     //     ITraderRoute(traderRoute).createPosition(_traderData, _puppetsData, true, true);

//     //     // 1. createPosition
//     //     bytes32 _requestKey = ITraderRoute(traderRoute).createPosition{ value: _amountInTrader }(_traderData, _puppetsData, true, true);
//     //     vm.stopPrank();

//     //     assertEq(ITraderRoute(traderRoute).getIsWaitingForCallback(), true, "_testCreateInitialPosition: E1");
//     //     assertEq(ITraderRoute(traderRoute).getTraderAmountIn(), _amountInTrader - _executionFee, "_testCreateInitialPosition: E02");
//     //     assertEq(orchestrator.getRouteForRequestKey(_requestKey), address(traderRoute), "_testCreateInitialPosition: E2");

//     //     vm.expectRevert(); // reverts with `NotKeeper()` 
//     //     ITraderRoute(traderRoute).createPuppetPosition();

//     //     vm.startPrank(orchestrator.getKeeper());
//     //     vm.expectRevert(); // reverts with `PositionNotApproved()` 
//     //     ITraderRoute(traderRoute).createPuppetPosition();
//     //     vm.stopPrank();
        
//     //     // 2. executePosition
//     //     vm.startPrank(GMXPositionRouterKeeper); // keeper
//     //     IGMXPositionRouter(orchestrator.getGMXPositionRouter()).executeIncreasePositions(type(uint256).max, payable(traderRoute));
//     //     vm.stopPrank();

//     //     if (_isOpenInterest(traderRoute)) {
//     //         assertEq(ITraderRoute(traderRoute).getIsWaitingForCallback(), true, "_testCreateInitialPosition: E3");
//     //         assertTrue(address(trader).balance < _traderBalanceBefore, "_testCreateInitialPosition: E4");
//     //         assertTrue(TraderRoute(payable(traderRoute)).isRequestApproved(), "_testCreateInitialPosition: E5");

//     //         uint256 _aliceDepositBalanceBefore = orchestrator.puppetDepositAccount(alice);
//     //         uint256 _bobDepositBalanceBefore = orchestrator.puppetDepositAccount(bob);
//     //         uint256 _yossiDepositBalanceBefore = orchestrator.puppetDepositAccount(yossi);
//     //         uint256 _orchestratorBalanceBefore = address(orchestrator).balance;

//     //         // 3. createPuppetPosition
//     //         vm.startPrank(orchestrator.getKeeper());
//     //         _requestKey = ITraderRoute(traderRoute).createPuppetPosition();
//     //         vm.stopPrank();

//     //         if (TraderRoute(payable(traderRoute)).isPuppetIncrease()) {
//     //             _testPuppetRouteOnIncreaseBeforeCallback(_aliceDepositBalanceBefore, _bobDepositBalanceBefore, _yossiDepositBalanceBefore, _orchestratorBalanceBefore, _requestKey);
//     //         } else {
//     //             revert("not tested: 1");
//     //         }

//     //         uint256 _puppetRouteBalanceBefore = address(puppetRoute).balance;

//     //         _aliceDepositBalanceBefore = orchestrator.puppetDepositAccount(alice);
//     //         _bobDepositBalanceBefore = orchestrator.puppetDepositAccount(bob);
//     //         _yossiDepositBalanceBefore = orchestrator.puppetDepositAccount(yossi);
//     //         _orchestratorBalanceBefore = address(orchestrator).balance;

//     //         // 4. executePuppetPosition
//     //         vm.startPrank(GMXPositionRouterKeeper); // keeper
//     //         IGMXPositionRouter(orchestrator.getGMXPositionRouter()).executeIncreasePositions(type(uint256).max, payable(puppetRoute));
//     //         vm.stopPrank();

//     //         if (_isOpenInterest(traderRoute)) {
//     //             _testPuppetRouteOnIncreaseAfterPositionApproved(_executionFee, _orchestratorBalanceBefore, _aliceDepositBalanceBefore, _bobDepositBalanceBefore, _yossiDepositBalanceBefore, _puppetRouteBalanceBefore);
//     //         } else {
//     //             revert("not tested: 2");
//     //         }

//     //     } else {
//     //         assertEq(address(traderRoute).balance, 0, "_testCreateInitialPosition: E5");
//     //         assertEq(ITraderRoute(traderRoute).getIsWaitingForCallback(), false, "_testCreateInitialPosition: E6");
//     //         assertEq(address(trader).balance, _traderBalanceBefore, "_testCreateInitialPosition: E7");
//     //         revert("!OpenInterest"); // current config should open a position. i want to know if it fails
//     //     }
//     // }

//     // function _testPuppetRouteOnIncreaseBeforeCallback(uint256 _aliceDepositBalanceBefore, uint256 _bobDepositBalanceBefore, uint256 _yossiDepositBalanceBefore, uint256 _orchestratorBalanceBefore, bytes32 _requestKey) internal {
//     //     assertEq(PuppetRoute(payable(puppetRoute)).getIsPositionOpen(), false, "_testPuppetRouteOnIncreaseBeforeCallback: E0");
//     //     assertEq(PuppetRoute(payable(puppetRoute)).isWaitingForCallback(), true, "_testPuppetRouteOnIncreaseBeforeCallback: E1");
//     //     assertEq(PuppetRoute(payable(puppetRoute)).isIncrease(), true, "_testPuppetRouteOnIncreaseBeforeCallback: E2");

//     //     // check that all puppets were debited and contract balance lower
//     //     uint256 _traderAmountIn = ITraderRoute(traderRoute).getTraderAmountIn();
//     //     uint256 _aliceAllowance = orchestrator.getPuppetAllowance(alice, traderRoute) >= _traderAmountIn ? _traderAmountIn : orchestrator.getPuppetAllowance(alice, traderRoute);
//     //     uint256 _bobAllowance = orchestrator.getPuppetAllowance(bob, traderRoute) >= _traderAmountIn ? _traderAmountIn : orchestrator.getPuppetAllowance(bob, traderRoute);
//     //     uint256 _yossiAllowance = orchestrator.getPuppetAllowance(yossi, traderRoute) >= _traderAmountIn ? _traderAmountIn : orchestrator.getPuppetAllowance(yossi, traderRoute);

//     //     assertEq(orchestrator.puppetDepositAccount(alice), _aliceDepositBalanceBefore - _aliceAllowance, "_testPuppetRouteOnIncreaseBeforeCallback: E3");
//     //     assertEq(orchestrator.puppetDepositAccount(bob), _bobDepositBalanceBefore - _bobAllowance, "_testPuppetRouteOnIncreaseBeforeCallback: E4");
//     //     assertEq(orchestrator.puppetDepositAccount(yossi), _yossiDepositBalanceBefore - _yossiAllowance, "_testPuppetRouteOnIncreaseBeforeCallback: E5");
//     //     assertEq(address(orchestrator).balance, _orchestratorBalanceBefore - (_aliceAllowance + _bobAllowance + _yossiAllowance), "_testPuppetRouteOnIncreaseBeforeCallback: E6");
        
//     //     // check puppetRoute shares + totalAmount
//     //     assertEq(PuppetRoute(payable(puppetRoute)).totalAssets(), _aliceAllowance + _bobAllowance + _yossiAllowance, "_testPuppetRouteOnIncreaseBeforeCallback: E7");

//     //     // shares are 1:1 with assets in this case
//     //     assertEq(PuppetRoute(payable(puppetRoute)).getPuppetShares(alice), _aliceAllowance, "_testPuppetRouteOnIncreaseBeforeCallback: E8");
//     //     assertEq(PuppetRoute(payable(puppetRoute)).getPuppetShares(bob), _bobAllowance, "_testPuppetRouteOnIncreaseBeforeCallback: E9");
//     //     assertEq(PuppetRoute(payable(puppetRoute)).getPuppetShares(yossi), _yossiAllowance, "_testPuppetRouteOnIncreaseBeforeCallback: E10");
//     //     assertEq(PuppetRoute(payable(puppetRoute)).getPuppetShares(alice), PuppetRoute(payable(puppetRoute)).getPuppetShares(bob), "_testPuppetRouteOnIncreaseBeforeCallback: E11");
//     //     assertEq(PuppetRoute(payable(puppetRoute)).getPuppetShares(alice), PuppetRoute(payable(puppetRoute)).getPuppetShares(yossi), "_testPuppetRouteOnIncreaseBeforeCallback: E12");

//     //     assertEq(orchestrator.getRouteForRequestKey(_requestKey), puppetRoute, "_testPuppetRouteOnIncreaseBeforeCallback: E13");
//     // }

//     // function _testPuppetRouteOnIncreaseAfterPositionApproved(uint256 _executionFee, uint256 _orchestratorBalanceBefore, uint256 _aliceDepositBalanceBefore, uint256 _bobDepositBalanceBefore, uint256 _yossiDepositBalanceBefore, uint256 _puppetRouteBalanceBefore) internal {
//     //     assertEq(PuppetRoute(payable(puppetRoute)).getIsPositionOpen(), true, "_testPuppetRouteOnIncreaseAfterPositionApproved: E0");
//     //     assertEq(PuppetRoute(payable(puppetRoute)).isWaitingForCallback(), false, "_testPuppetRouteOnIncreaseAfterPositionApproved: E1");
//     //     assertEq(PuppetRoute(payable(puppetRoute)).isWaitingForCallback(), false, "_testPuppetRouteOnIncreaseAfterPositionApproved: E2");

//     //     assertEq(ITraderRoute(traderRoute).getIsWaitingForCallback(), false, "_testPuppetRouteOnIncreaseAfterPositionApproved: E3");
//     //     assertEq(address(puppetRoute).balance, _puppetRouteBalanceBefore, "_testPuppetRouteOnIncreaseAfterPositionApproved: E4");
//     //     assertEq(address(puppetRoute).balance, 0, "_testPuppetRouteOnIncreaseAfterPositionApproved: E5");

//     //     assertEq(_isOpenInterest(puppetRoute), true, "_testPuppetRouteOnIncreaseAfterPositionApproved: E6");

//     //     // _executionFee was returned to orchestrator (since we're on fork) - good chance to test _repayBalance in action
//     //     uint256 _creditPerPuppet = _executionFee / 3;
//     //     assertEq(orchestrator.puppetDepositAccount(alice), _aliceDepositBalanceBefore + _creditPerPuppet, "_testPuppetRouteOnIncreaseAfterPositionApproved: E7");
//     //     assertEq(orchestrator.puppetDepositAccount(bob), _bobDepositBalanceBefore + _creditPerPuppet, "_testPuppetRouteOnIncreaseAfterPositionApproved: E8");
//     //     assertEq(orchestrator.puppetDepositAccount(yossi), _yossiDepositBalanceBefore + _creditPerPuppet, "_testPuppetRouteOnIncreaseAfterPositionApproved: E9");
//     //     assertEq(address(orchestrator).balance, _orchestratorBalanceBefore + _executionFee, "_testPuppetRouteOnIncreaseAfterPositionApproved: E10");
//     // }

//     // // ============================================================================================
//     // // Internal Helper Functions
//     // // ============================================================================================

//     // function _isOpenInterest(address _account) internal view returns (bool) {
//     //     (uint256 _size, uint256 _collateral,,,,,,) = IGMXVault(orchestrator.getGMXVault()).getPosition(_account, collateralToken, indexToken, isLong);

//     //     return _size > 0 && _collateral > 0;
//     // }

//     // function _getAllowanceForRoute(uint256 _traderAmountIn) internal returns (uint256 _totalAllowance) {
//     //     bytes32 _routeKey = orchestrator.getTraderRouteKey(trader, collateralToken, indexToken, isLong);
//     //     address[] memory _puppets = orchestrator.getPuppetsForRoute(_routeKey);

//     //     for (uint256 i = 0; i < _puppets.length; i++) {
//     //         address _puppet = _puppets[i];
//     //         uint256 _allowance = orchestrator.getPuppetAllowance(_puppet, traderRoute);
//     //         if (_allowance > _traderAmountIn) _allowance = _traderAmountIn;
//     //         _totalAllowance += _allowance;

//     //         assertTrue(_allowance > 0, "_getAllowanceForRoute: E1");
//     //     }
//     // }

//     // function _convertToShares(uint256 _totalAssets, uint256 _totalSupply, uint256 _assets) internal pure returns (uint256 _shares) {
//     //     if (_assets == 0) revert("ZeroAmount");

//     //     if (_totalAssets == 0) {
//     //         _shares = _assets;
//     //     } else {
//     //         _shares = (_assets * _totalSupply) / _totalAssets;
//     //     }

//     //     if (_shares == 0) revert("ZeroAmount");
//     // }
// }