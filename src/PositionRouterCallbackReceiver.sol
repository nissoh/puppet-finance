// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IPositionRouterCallbackReceiver} from "./interfaces/IPositionRouterCallbackReceiver.sol";
import {IPuppetOrchestrator} from "./interfaces/IPuppetOrchestrator.sol";
import {ITraderRoute} from "./interfaces/ITraderRoute.sol";

contract PositionRouterCallbackReceiver is IPositionRouterCallbackReceiver {

    IPuppetOrchestrator puppetOrchestrator;

    address public owner;
    address public gmxPositionRouter;

    // ====================== Constructor ======================

    constructor(address _owner) {
        owner = _owner;
    }

    // ====================== Modifiers ======================

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyGMXPositionRouter() {
        if (msg.sender != gmxPositionRouter) revert Unauthorized();
        _;
    }

    // ====================== GMXPositionRouter functions ======================
    
    function gmxPositionCallback(bytes32 _positionKey, bool _isExecuted, bool _isIncrease) external override onlyGMXPositionRouter {
        ITraderRoute _traderRoute = ITraderRoute(puppetOrchestrator.getTraderRouteForPosition(_positionKey));

        if (_isIncrease) {
            if (_isExecuted) {
                _traderRoute.approveIncreasePosition();
            } else {
                _traderRoute.rejectIncreasePosition();
            }
        } else {
            if (_isExecuted) {
                _traderRoute.approveDecreasePosition();
            } else {
                _traderRoute.rejectDecreasePosition();
            }
        }

        emit GMXPositionCallback(_positionKey, address(_traderRoute), _isExecuted);
    }

    // ====================== Owner functions ======================

    function setPuppetOrchestrator(address _puppetOrchestrator) external onlyOwner {
        puppetOrchestrator = IPuppetOrchestrator(_puppetOrchestrator);
    }

    function setGMXPositionRouter(address _gmxPositionRouter) external onlyOwner {
        gmxPositionRouter = _gmxPositionRouter;
    }

    function setOwner(address _owner) external onlyOwner {
        owner = _owner;
    }

    // ====================== Events ======================

    event GMXPositionCallback(bytes32 indexed _positionKey, address indexed _traderRoute, bool indexed _isExecuted);

    // ====================== Errors ======================

    error Unauthorized();
}