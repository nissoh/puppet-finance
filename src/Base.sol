// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IWETH} from "./interfaces/IWETH.sol";
import {IOrchestrator} from "./interfaces/IOrchestrator.sol";
import {IBase, AggregatorV3Interface} from "./interfaces/IBase.sol";

abstract contract Base is ReentrancyGuard, Auth, IBase {

    address public revenueDistributor;
    address public keeper;

    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // the address representing ETH
    address internal constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    bytes32 public referralCode;

    GMXInfo public gmxInfo;
}