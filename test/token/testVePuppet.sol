// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {DeployerUtilities} from "script/utilities/DeployerUtilities.sol";

import {Puppet} from "src/token/Puppet.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract testVePuppet is Test, DeployerUtilities {}