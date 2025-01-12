// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ========================== Dictator ==========================
// ==============================================================
// Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";

/// @title Dictator
/// @author johnnyonline (Puppet Finance) https://github.com/johnnyonline
/// @notice This contract manages user and roles permisions in all contracts which have this contract as Autority
contract Dictator is RolesAuthority {
    constructor(address _owner) RolesAuthority(_owner, Authority(address(0))) {}
}