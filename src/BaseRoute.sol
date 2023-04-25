// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {IGMXRouter} from "./interfaces/IGMXRouter.sol";

import {IPuppetOrchestrator} from "./interfaces/IPuppetOrchestrator.sol";
import {ITraderRoute} from "./interfaces/ITraderRoute.sol";
import {IPuppetRoute} from "./interfaces/IPuppetRoute.sol";

contract BaseRoute is ReentrancyGuard {

    using SafeERC20 for IERC20;
    using Address for address payable;

    address public collateralToken;
    address public indexToken;
    
    bool public isLong;
    bool public isWaitingForCallback;

    IPuppetOrchestrator public puppetOrchestrator;

    // ====================== Constructor ======================

    constructor(address _puppetOrchestrator, address _collateralToken, address _indexToken, bool _isLong) {
        puppetOrchestrator = IPuppetOrchestrator(_puppetOrchestrator);

        collateralToken = _collateralToken;
        indexToken = _indexToken;
        isLong = _isLong;

        IGMXRouter(puppetOrchestrator.getGMXRouter()).approvePlugin(puppetOrchestrator.getGMXPositionRouter());
    }

    // ====================== Modifiers ======================

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyCallbackTarget() {
        if (msg.sender != owner && msg.sender != puppetOrchestrator.getCallbackTarget()) revert NotCallbackTarget();
        _;
    }

    // ====================== request callback ======================

    function approvePositionRequest() external virtual nonReentrant onlyCallbackTarget {}
    function rejectPositionRequest() external virtual nonReentrant onlyCallbackTarget {
    
    // ====================== Owner functions ======================

    function setPuppetOrchestrator(address _puppetOrchestrator) external onlyOwner {
        puppetOrchestrator = IPuppetOrchestrator(_puppetOrchestrator);
    }

    function approvePlugin() external onlyOwner {
        IGMXRouter(puppetOrchestrator.getGMXRouter()).approvePlugin(puppetOrchestrator.getGMXPositionRouter());
    }

    // ====================== Internal functions ======================

    function _createIncreasePosition(bytes memory _positionData) internal virtual {}
    function _createDecreasePosition(bytes memory _positionData) internal virtual {}
    function _repayBalance() internal virtual {}
}