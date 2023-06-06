// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./utilities/DeployerUtilities.sol";

// ---- Usage ----
// forge script script/DeployPuppet.s.sol:DeployPuppet --rpc-url $RPC_URL --broadcast
// forge verify-contract --verifier-url https://arbiscan.io/ $CONTRACT_ADDRESS src/Orchestrator.sol:Orchestrator

// forge verify-contract --constructor-args 0x000000000000000000000000189b21eda0cff16461913d616a0a4f711cd986cb --watch --chain-id 42161 --compiler-version v0.8.17+commit.8df45f5f --verifier-url https://api.arbiscan.io/api 0xc514680Bc42E57BfCdA5E9c7eaf9eD4234c66977 src/Dictator.sol:Dictator
// --constructor-args $(cast abi-encode "constructor(address)" 0xBF73FEBB672CC5B8707C2D75cB49B0ee2e2C9DaA)

//   dictator: 0xc514680Bc42E57BfCdA5E9c7eaf9eD4234c66977
//   routeFactory: 0x5e5B5C1f69cFb1F0a84AD03d242B07C3A8e53B71
//   orchestrator: 0xA12a6281c1773F267C274c3BE1B71DB2BACE06Cb

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