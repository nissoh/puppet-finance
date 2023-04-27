// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {AggregatorV3Interface} from "@chainlink/src/v0.8/interfaces/AggregatorV3Interface.sol";

import {PuppetOrchestrator} from "../src/PuppetOrchestrator.sol";
import {PositionValidator} from "../src/PositionValidator.sol";
import {PositionRouterCallbackReceiver} from "../src/PositionRouterCallbackReceiver.sol";

import {ITraderRoute} from "../src/interfaces/ITraderRoute.sol";

contract testPuppet is Test {

    address owner;
    address trader;
    address alice;
    address bob;
    address yossi;
    address traderRoute;
    address puppetRoute;

    address collateralToken = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address indexToken = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    
    uint256 arbitrumFork;

    PuppetOrchestrator puppetOrchestrator;
    PositionRouterCallbackReceiver positionRouterCallbackReceiver;

    AggregatorV3Interface priceFeed;

    address constant WETH = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1); 

    function setUp() public {

        string memory ARBITRUM_RPC_URL = vm.envString("ARBITRUM_RPC_URL");
        arbitrumFork = vm.createFork(ARBITRUM_RPC_URL);
        vm.selectFork(arbitrumFork);

        owner = address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        trader = address(0xa0Ee7A142d267C1f36714E4a8F75612F20a79720);
        alice = address(0xFa0C696bC56AE0d256D34a307c447E80bf92Dd41);
        bob = address(0x864e4b0c28dF7E2f317FF339CebDB5224F47220e);
        yossi = address(0x77Ee01E3d0E05b4afF42105Fe004520421248261);

        vm.deal(owner, 100 ether);
        vm.deal(trader, 100 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(yossi, 100 ether);

        PositionValidator _positionValidator = new PositionValidator();

        address _keeper = address(0);
        address _gmxRouter = 0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064;
        address _gmxReader = 0x22199a49A999c351eF7927602CFB187ec3cae489;
        address _gmxVault = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
        address _gmxPositionRouter = 0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868;
        bytes32 _referralCode = bytes32(0);
        positionRouterCallbackReceiver = new PositionRouterCallbackReceiver(owner, _gmxPositionRouter);
        puppetOrchestrator = new PuppetOrchestrator(owner, address(_positionValidator), _keeper, _gmxRouter, _gmxReader, _gmxVault, _gmxPositionRouter, address(positionRouterCallbackReceiver), _referralCode);

        address ETH_USD_PRICE_FEED_ADDRESS = address(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612);
        priceFeed = AggregatorV3Interface(ETH_USD_PRICE_FEED_ADDRESS);
    }

    function testCorrectFlow() public {
        uint256 _assets = 1 ether;
        bytes32 _routeKey = _testRegisterRoute();
        _testPuppetDeposit(_assets);
        _testUpdateRoutesSubscription(_routeKey);

        _testCreateInitialPosition();
    }

    // ============================================================================================
    // Internal Functions
    // ============================================================================================

    //
    // PuppetOrchestrator
    //

    // Trader

    function _testRegisterRoute() internal returns (bytes32 _routeKey) {
        vm.startPrank(trader);
        _routeKey = puppetOrchestrator.registerRoute(WETH, WETH, true);
        address[] memory _pupptsForRoute = puppetOrchestrator.getPuppetsForRoute(_routeKey);

        (traderRoute, puppetRoute) = puppetOrchestrator.getRouteForRouteKey(_routeKey);

        assertEq(_routeKey, puppetOrchestrator.getTraderRouteKey(trader, collateralToken, indexToken, true), "_testRegisterRoute: E0");
        assertEq(_pupptsForRoute.length, 0, "_testRegisterRoute: E1");
        assertEq(puppetOrchestrator.isRoute(traderRoute), true, "_testRegisterRoute: E2");
        assertEq(puppetOrchestrator.isRoute(puppetRoute), true, "_testRegisterRoute: E3");
        vm.stopPrank();
    }

    // Puppet

    function _testPuppetDeposit(uint256 _assets) internal {
        // alice
        vm.startPrank(alice);
        vm.expectRevert(); // reverts with InvalidAmount()
        puppetOrchestrator.depositToAccount(_assets, alice);
        puppetOrchestrator.depositToAccount{ value: _assets }(_assets, alice);
        assertEq(puppetOrchestrator.puppetDepositAccount(alice), _assets, "_testPuppetDeposit: E0");
        vm.stopPrank();

        // bob
        vm.prank(bob);
        puppetOrchestrator.depositToAccount{ value: _assets }(_assets, bob);
        assertEq(puppetOrchestrator.puppetDepositAccount(bob), _assets, "_testPuppetDeposit: E1");

        // yossi
        vm.prank(yossi);
        puppetOrchestrator.depositToAccount{ value: _assets }(_assets, yossi);
        assertEq(puppetOrchestrator.puppetDepositAccount(yossi), _assets, "_testPuppetDeposit: E2");

        assertEq(address(puppetOrchestrator).balance, _assets * 3, "_testPuppetDeposit: E3");
    }

    function _testUpdateRoutesSubscription(bytes32 _routeKey) internal {
        uint256[] memory _allowances = new uint256[](1);
        address[] memory _traders = new address[](1);
        _traders[0] = trader;

        vm.startPrank(alice);
        _allowances[0] = puppetOrchestrator.puppetDepositAccount(alice);
        vm.expectRevert(); // reverts with InsufficientPuppetFunds()
        puppetOrchestrator.updateRoutesSubscription(_traders, _allowances, collateralToken, indexToken, true, true);

        _allowances[0] = puppetOrchestrator.puppetDepositAccount(alice) / puppetOrchestrator.solvencyMargin();
        puppetOrchestrator.updateRoutesSubscription(_traders, _allowances, collateralToken, indexToken, true, true);

        assertEq(puppetOrchestrator.getPuppetAllowance(alice, traderRoute), _allowances[0], "_testUpdateRoutesSubscription: E0");
        assertEq(puppetOrchestrator.getPuppetsForRoute(_routeKey)[0], alice, "_testUpdateRoutesSubscription: E1");
        assertEq(puppetOrchestrator.getPuppetsForRoute(_routeKey).length, 1, "_testUpdateRoutesSubscription: E2");
        vm.stopPrank();

        vm.startPrank(bob);
        puppetOrchestrator.updateRoutesSubscription(_traders, _allowances, collateralToken, indexToken, true, true);
        assertEq(puppetOrchestrator.getPuppetAllowance(bob, traderRoute), _allowances[0], "_testUpdateRoutesSubscription: E3");
        assertEq(puppetOrchestrator.getPuppetsForRoute(_routeKey)[1], bob, "_testUpdateRoutesSubscription: E4");
        assertEq(puppetOrchestrator.getPuppetsForRoute(_routeKey).length, 2, "_testUpdateRoutesSubscription: E5");
        vm.stopPrank();

        vm.startPrank(yossi);
        puppetOrchestrator.updateRoutesSubscription(_traders, _allowances, collateralToken, indexToken, true, true);
        assertEq(puppetOrchestrator.getPuppetAllowance(yossi, traderRoute), _allowances[0], "_testUpdateRoutesSubscription: E6");
        assertEq(puppetOrchestrator.getPuppetsForRoute(_routeKey)[2], yossi, "_testUpdateRoutesSubscription: E7");
        assertEq(puppetOrchestrator.getPuppetsForRoute(_routeKey).length, 3, "_testUpdateRoutesSubscription: E8");
        vm.stopPrank();
    }

    //
    // TraderRoute
    //

    // open position
    // add collateral + increase size
    function _testCreateInitialPosition() internal {
        (, int256 _price,,,) = priceFeed.latestRoundData();

        uint256 _minOut = 0; // _minOut can be zero if no swap is required
        uint256 _acceptablePrice = uint256(_price); // the USD value of the max (for longs) or min (for shorts) index price acceptable when executing the request
        // _acceptablePrice = _acceptablePrice - (_acceptablePrice / 20); // decrease _acceptablePrice by 5%
        uint256 _executionFee = 180000000000000; // can be set to PositionRouter.minExecutionFee() https://arbiscan.io/address/0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868#readContract#F26

        // the USD value of the change in position size
        uint256 _sizeDeltaTrader = 1 ether; 
        uint256 _sizeDeltaPuppet = 1 ether;

        // the amount of tokenIn you want to deposit as collateral
        uint256 _amountInTrader = 1 ether;
        uint256 _amountInPuppet = 1 ether;

        bytes memory _traderData = abi.encode(_minOut, _sizeDeltaTrader, _acceptablePrice, _executionFee);
        bytes memory _puppetsData = abi.encode(_amountInPuppet, _minOut, _sizeDeltaPuppet, _acceptablePrice, _executionFee);

        assertEq(ITraderRoute(traderRoute).getIsWaitingForCallback(), false, "_testCreateInitialPosition: E0");

        vm.expectRevert(); // reverts with NotTrader()
        ITraderRoute(traderRoute).createPosition(_traderData, _puppetsData, true, true);

        vm.startPrank(trader);

        vm.expectRevert(); // reverts with `Arithmetic over/underflow` (on subtracting _executionFee from _amountInTrader) 
        ITraderRoute(traderRoute).createPosition(_traderData, _puppetsData, true, true);

        bytes32 _positionKey = ITraderRoute(traderRoute).createPosition{ value: _amountInTrader }(_traderData, _puppetsData, true, true);

        assertEq(ITraderRoute(traderRoute).getIsWaitingForCallback(), true, "_testCreateInitialPosition: E1");
        assertEq(puppetOrchestrator.getTraderRouteForPositionKey(_positionKey), address(traderRoute), "_testCreateInitialPosition: E2");

        // keeper - 0x11D62807dAE812a0F1571243460Bf94325F43BB7
    }
}