// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {RouteFactory} from "../src/RouteFactory.sol";
import {Orchestrator} from "../src/Orchestrator.sol";

import "./utilities/DeployerUtilities.sol";

contract DeployPuppet is DeployerUtilities {

    bytes private _gmxInfo = abi.encode(_gmxRouter, _gmxVault, _gmxPositionRouter);

    function run() public {
        vm.startBroadcast(_deployerPrivateKey);

        Dictator _dictator = new Dictator(_deployer);
        RouteFactory _routeFactory = new RouteFactory();

        Orchestrator orchestrator = new Orchestrator(_dictator, address(_routeFactory), _keeper, _referralCode, _gmxInfo);

        bytes4 functionSig = orchestrator.setRouteType.selector;

        _setRoleCapability(_dictator, 0, address(orchestrator), functionSig, true);
        _setUserRole(_dictator, _deployer, 0, true);

        // set route type
        orchestrator.setRouteType(_weth, _weth, true);

        console.log("Deployed Addresses");
        console.log("==============================================");
        console.log("==============================================");
        console.log("dictator: %s", address(_dictator));
        console.log("routeFactory: %s", address(_routeFactory));
        console.log("orchestrator: %s", address(orchestrator));
        console.log("==============================================");
        console.log("==============================================");

        vm.stopBroadcast();
    }
}