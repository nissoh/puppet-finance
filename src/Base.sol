// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IWETH} from "./interfaces/IWETH.sol";
import {IOrchestrator} from "./interfaces/IOrchestrator.sol";

abstract contract Base is ReentrancyGuard {

    address internal _keeper;

    address internal constant _ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // the address representing ETH
    address internal constant _WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    bytes32 internal _referralCode;

    // ============================================================================================
    // Events
    // ============================================================================================

    event SetOwner(address _owner);
    event StuckTokensRescued(address token, address to);

    // ============================================================================================
    // Errors
    // ============================================================================================

    error NotOwner();
    error ZeroAmount();
}