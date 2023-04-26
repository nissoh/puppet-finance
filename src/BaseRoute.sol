// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {IGMXRouter} from "./interfaces/IGMXRouter.sol";
import {IGMXPositionRouter} from "./interfaces/IGMXPositionRouter.sol";
import {IGMXVault} from "./interfaces/IGMXVault.sol";

import {IPuppetOrchestrator} from "./interfaces/IPuppetOrchestrator.sol";
import {ITraderRoute} from "./interfaces/ITraderRoute.sol";
import {IPuppetRoute} from "./interfaces/IPuppetRoute.sol";
import {IRoute} from "./interfaces/IRoute.sol";

contract BaseRoute is ReentrancyGuard, IRoute {

    address public owner;
    address public collateralToken;
    address public indexToken;
    
    bool public isLong;
    bool public isWaitingForCallback;

    IPuppetOrchestrator public puppetOrchestrator;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    constructor(address _puppetOrchestrator, address _owner, address _collateralToken, address _indexToken, bool _isLong) {
        puppetOrchestrator = IPuppetOrchestrator(_puppetOrchestrator);
        owner = _owner;
        collateralToken = _collateralToken;
        indexToken = _indexToken;
        isLong = _isLong;

        IGMXRouter(puppetOrchestrator.getGMXRouter()).approvePlugin(puppetOrchestrator.getGMXPositionRouter());
    }

    // ============================================================================================
    // Modifiers
    // ============================================================================================

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyCallbackTarget() {
        if (msg.sender != owner && msg.sender != puppetOrchestrator.getCallbackTarget()) revert NotCallbackTarget();
        _;
    }

    // ============================================================================================
    // Callback Functions
    // ============================================================================================

    function approvePositionRequest() external virtual nonReentrant onlyCallbackTarget {}
    function rejectPositionRequest() external virtual nonReentrant onlyCallbackTarget {}

    // ============================================================================================
    // Owner Functions
    // ============================================================================================

    function setPuppetOrchestrator(address _puppetOrchestrator) external virtual onlyOwner {
        puppetOrchestrator = IPuppetOrchestrator(_puppetOrchestrator);
    }

    function approvePlugin() external virtual onlyOwner {
        IGMXRouter(puppetOrchestrator.getGMXRouter()).approvePlugin(puppetOrchestrator.getGMXPositionRouter());
    }

    // ============================================================================================
    // Internal Functions
    // ============================================================================================

    function _createIncreasePosition(bytes memory _positionData) internal virtual returns (bytes32 _positionKey) {}
    function _createDecreasePosition(bytes memory _positionData) internal virtual returns (bytes32 _positionKey) {}
    function _repayBalance() internal virtual {}

    function _isLiquidated() internal view returns (bool) {
        (uint256 state, ) = IGMXVault(puppetOrchestrator.getGMXVault()).validateLiquidation(address(this), collateralToken, indexToken, isLong, false);

        return state > 0;
    }
}