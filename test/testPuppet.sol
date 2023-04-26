// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {PuppetOrchestrator} from "../src/PuppetOrchestrator.sol";
import {PositionValidator} from "../src/PositionValidator.sol";
import {PositionRouterCallbackReceiver} from "../src/PositionRouterCallbackReceiver.sol";

contract testPuppet is Test {

    address owner;
    address trader;
    address alice;
    address bob;
    address yossi;
    
    uint256 arbitrumFork;

    PuppetOrchestrator puppetOrchestrator;
    PositionRouterCallbackReceiver positionRouterCallbackReceiver;

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
    }

    function testCorrectFlow() public {
        _testRegisterRoute();
    }

    // ============================================================================================
    // Internal Functions
    // ============================================================================================

    function _testRegisterRoute() internal {
        assertTrue(true);
        vm.startPrank(trader);
        bytes32 _routeKey = puppetOrchestrator.registerRoute(WETH, WETH, true);
        address[] memory _pupptsForRoute = puppetOrchestrator.getPuppetsForRoute(_routeKey);
        (address _traderRoute, address _puppetRoute) = puppetOrchestrator.getRouteForRouteKey(_routeKey);
        console.log("routeKey: %s", _traderRoute);

        assertEq(_routeKey, puppetOrchestrator.getTraderRouteKey(trader, WETH, WETH, true));
        assertEq(_pupptsForRoute.length, 0);
        assertEq(puppetOrchestrator.isRoute(_traderRoute), true);
        assertEq(puppetOrchestrator.isRoute(_puppetRoute), true);
    }
}