// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Dictator} from "../../src/Dictator.sol";
import {RouteFactory} from "../../src/RouteFactory.sol";
import {Orchestrator} from "../../src/Orchestrator.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract DeployerUtilities is Script {

    // ============================================================================================
    // Variables
    // ============================================================================================

    // deployer info

    uint256 internal _deployerPrivateKey = vm.envUint("GBC_DEPLOYER2_PRIVATE_KEY");

    address internal _deployer = vm.envAddress("GBC_DEPLOYER2_ADDRESS");

    // GMX info

    address internal _gmxRouter = 0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064;
    address internal _gmxVault = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
    address internal _gmxPositionRouter = 0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868;

    // tokens

    address internal _weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address internal _frax = address(0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F);
    address internal _usdc = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);

    // Puppet info

    address internal _keeper = address(0);
    address internal _dictator = 0xc514680Bc42E57BfCdA5E9c7eaf9eD4234c66977;
    address internal _routeFactory = 0x5e5B5C1f69cFb1F0a84AD03d242B07C3A8e53B71;
    address internal orchestrator = 0xA12a6281c1773F267C274c3BE1B71DB2BACE06Cb;

    bytes32 internal _referralCode = bytes32(0);

    // ============================================================================================
    // Authority Functions
    // ============================================================================================

    function _setRoleCapability(Dictator _dictator, uint8 role, address target, bytes4 functionSig, bool enabled) internal {
        _dictator.setRoleCapability(role, target, functionSig, enabled);
    }

    function _setUserRole(Dictator _dictator, address user, uint8 role, bool enabled) internal {
        _dictator.setUserRole(user, role, enabled);
    }
}