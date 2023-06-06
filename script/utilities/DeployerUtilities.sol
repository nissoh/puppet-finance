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

    bytes32 internal _referralCode = bytes32(0);

    // todo - add Dictator and RouteFactory addresses 

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


// ---- Notes ----

// forge script script/arbitrum/InitFortressArbi.s.sol:InitFortress --rpc-url $RPC_URL --broadcast
// cast call COMPUNDER_ADDRESS "balanceOf(address)(uint256)" 0x24aDB12fE4b03b780989B5D7C5A5114b2fc45F01 --rpc-url RPC_URL
// cast call REG_ADDRESS "getTokenCompounder(address)(address)" 0x24aDB12fE4b03b780989B5D7C5A5114b2fc45F01 --rpc-url RPC_URL
// https://abi.hashex.org/ - for constructor
// forge flatten --output GlpCompounder.sol src/arbitrum/compounders/gmx/GlpCompounder.sol
// forge verify-contract --verifier-url https://arbiscan.io/ 0x03605C3A3dAf860774448df807742c0d0e49460C src/arbitrum/utils/FortressArbiRegistry.sol:FortressArbiRegistry