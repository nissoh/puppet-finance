// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {RouteFactory} from "../../src/RouteFactory.sol";
import {Orchestrator} from "../../src/Orchestrator.sol";

import "./utilities/DeployerUtilities.sol";

// ---- Usage ----
// forge script script/DeployPuppet.s.sol:DeployPuppet --rpc-url $RPC_URL --broadcast
// forge verify-contract --constructor-args $ARGS --watch --chain-id 42161 --compiler-version v0.8.17+commit.8df45f5f --verifier-url https://api.arbiscan.io/api $CONTRACT_ADDRESS src/Orchestrator.sol:Orchestrator
// --constructor-args $(cast abi-encode "constructor(address)" 0xBF73FEBB672CC5B8707C2D75cB49B0ee2e2C9DaA)

contract DeployPuppet is DeployerUtilities {

    bytes private _gmxInfo = abi.encode(_gmxRouter, _gmxVault, _gmxPositionRouter);

    function run() public {
        vm.startBroadcast(_deployerPrivateKey);

        Dictator _dictator = Dictator(_dictatorAddr);
        RouteFactory _routeFactory = RouteFactory(_routeFactoryAddr);

        Orchestrator _orchestrator = Orchestrator(_orchestratorAddr);

        bytes4 functionSig = _orchestrator.setRouteType.selector;

        _setRoleCapability(_dictator, 0, address(_orchestrator), functionSig, true);
        _setUserRole(_dictator, _deployer, 0, true);

        // set route type
        _orchestrator.setRouteType(_weth, _weth, true);

        console.log("Deployed Addresses");
        console.log("==============================================");
        console.log("==============================================");
        console.log("dictator: %s", address(_dictator));
        console.log("routeFactory: %s", address(_routeFactory));
        console.log("orchestrator: %s", address(_orchestrator));
        console.log("==============================================");
        console.log("==============================================");

        vm.stopBroadcast();
    }
}