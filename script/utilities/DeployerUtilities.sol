// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Dictator} from "../../src/Dictator.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract DeployerUtilities is Script {

    // ============================================================================================
    // Variables
    // ============================================================================================

    // deployer info

    uint256 internal _deployerPrivateKey = vm.envUint("GBC_DEPLOYER_PRIVATE_KEY");

    address internal _deployer = vm.envAddress("GBC_DEPLOYER_ADDRESS");

    // GMX info

    address internal _gmxRouter = 0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064;
    address internal _gmxVault = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
    address internal _gmxPositionRouter = 0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868;

    // tokens

    address internal _weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address internal _frax = address(0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F);
    address internal _usdc = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);

    // Puppet info

    address internal _keeperAddr = address(0);
    address internal _dictatorAddr = 0xA12a6281c1773F267C274c3BE1B71DB2BACE06Cb;
    address internal _routeFactoryAddr = 0x3fC294C613C920393698d12bD26061fb8300e415;
    address payable internal _orchestratorAddr = payable(0x82403099D24b2bF9Ee036F05E34da85E30982234);

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