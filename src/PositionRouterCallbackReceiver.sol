// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IPositionRouterCallbackReceiver} from "./interfaces/IPositionRouterCallbackReceiver.sol";
import {IPuppetOrchestrator} from "./interfaces/IPuppetOrchestrator.sol";
import {ITraderRoute} from "./interfaces/ITraderRoute.sol";

contract PositionRouterCallbackReceiver is IPositionRouterCallbackReceiver {

    error Unauthorized();

    event GMXPositionCallback(bytes32 indexed _positionKey, address indexed _traderRoute, bool indexed _isExecuted);

    address public puppetOrchestrator;
    address public owner;
    address public gmxPositionRouter;

    constructor(address _owner) {
        owner = _owner;
    }

    function setPuppetOrchestrator(address _puppetOrchestrator) external {
        if (msg.sender != owner) revert Unauthorized();

        puppetOrchestrator = _puppetOrchestrator;
    }

    function setGMXPositionRouter(address _gmxPositionRouter) external {
        if (msg.sender != owner) revert Unauthorized();

        gmxPositionRouter = _gmxPositionRouter;
    }

    function setOwner(address _owner) external {
        if (msg.sender != owner) revert Unauthorized();

        owner = _owner;
    }

    function gmxPositionCallback(bytes32 _positionKey, bool _isExecuted, bool _isIncrease) external override {
        if (msg.sender != gmxPositionRouter) revert Unauthorized();

        address _traderRoute = IPuppetOrchestrator(puppetOrchestrator).getTraderRouteForPosition(_positionKey);

        if (_isIncrease) {
            if (_isExecuted) {
                ITraderRoute(_traderRoute).approveIncreasePosition();
            } else {
                ITraderRoute(_traderRoute).rejectIncreasePosition();
            }
        } else {
            if (_isExecuted) {
                ITraderRoute(_traderRoute).approveDecreasePosition();
            } else {
                ITraderRoute(_traderRoute).rejectDecreasePosition();
            }
        }
        emit GMXPositionCallback(_positionKey, _traderRoute, _isExecuted);
    }

    // function _isPositionOpen(bytes32 _positionKey) internal returns (bool _isOpen) {} // TODO 
}