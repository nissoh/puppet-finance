// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IWETH} from "./interfaces/IWETH.sol";
import {IOrchestrator} from "./interfaces/IOrchestrator.sol";
import {IBase, AggregatorV3Interface} from "./interfaces/IBase.sol";

contract Base is ReentrancyGuard, IBase {

    using SafeERC20 for IERC20;
    using Address for address payable;

    address public owner;
    address public revenueDistributor;
    address public keeper;

    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // the address representing ETH
    address internal constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    bytes32 public referralCode;

    GMXInfo public gmxInfo;

    // ============================================================================================
    // Modifiers
    // ============================================================================================

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    // ============================================================================================
    // Owner Functions
    // ============================================================================================

    function setOwner(address _owner) external onlyOwner {
        owner = _owner;

        emit SetOwner(_owner);
    }
}