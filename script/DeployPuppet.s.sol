// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {RouteFactory} from "src/RouteFactory.sol";
import {Orchestrator} from "src/Orchestrator.sol";

import "./utilities/DeployerUtilities.sol";

// ---- Usage ----
// forge script script/DeployPuppet.s.sol:DeployPuppet --rpc-url $RPC_URL --broadcast
// forge verify-contract --constructor-args $ARGS --watch --chain-id 42161 --compiler-version v0.8.19+commit.7dd6d404 --verifier-url https://api.arbiscan.io/api $CONTRACT_ADDRESS src/Orchestrator.sol:Orchestrator
// --constructor-args $(cast abi-encode "constructor(address)" 0xBF73FEBB672CC5B8707C2D75cB49B0ee2e2C9DaA)
// $(cast abi-encode "constructor(address,address,address,address,bool)" 0x82403099D24b2bF9Ee036F05E34da85E30982234 0xF6F08BEe1b2B9059a5132d171943Fa7a078C77e1 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1 true)

// address _orchestrator, address _trader, address _collateralToken, address _indexToken, bool _isLong
// forge verify-contract --constructor-args $(cast abi-encode "constructor(address,address,address,address,bool)" 0x262Dc133C85148eDA91B0343dF85d4fD54847970 0x189b21eda0cff16461913D616a0A4F711Cd986cB 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1 true) --watch --chain-id 42161 --compiler-version v0.8.19+commit.7dd6d404 --verifier-url https://api.arbiscan.io/api $CONTRACT_ADDRESS src/Route.sol:Route

contract DeployPuppet is DeployerUtilities {

    bytes private _gmxInfo = abi.encode(_gmxVaultPriceFeed, _gmxRouter, _gmxVault, _gmxPositionRouter, false, false);

    function run() public {
        vm.startBroadcast(_deployerPrivateKey);

        address _platformFeeRecipient = _deployer;

        Dictator _dictator = Dictator(_dictatorAddr);

        RouteFactory _routeFactory = new RouteFactory();

        Orchestrator _orchestrator = new Orchestrator(_dictator, address(_routeFactory), _keeperAddr, _platformFeeRecipient, _weth, _referralCode, _gmxInfo);

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