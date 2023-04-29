// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IPositionRouterCallbackReceiver} from "./interfaces/IPositionRouterCallbackReceiver.sol";
import {IPuppetOrchestrator} from "./interfaces/IPuppetOrchestrator.sol";
import {IRoute} from "./interfaces/IRoute.sol";

contract PositionRouterCallbackReceiver is IPositionRouterCallbackReceiver {

    address public owner;
    address public gmxPositionRouter;

    IPuppetOrchestrator puppetOrchestrator;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    constructor(address _owner, address _gmxPositionRouter) {
        owner = _owner;
        gmxPositionRouter = _gmxPositionRouter;
    }

    // ============================================================================================
    // Modifiers
    // ============================================================================================

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyGMXPositionRouter() {
        if (msg.sender != owner && msg.sender != gmxPositionRouter) revert NotGMXPositionRouter();
        _;
    }

    // ============================================================================================
    // GMXPositionRouter Functions
    // ============================================================================================

    function gmxPositionCallback(bytes32 _positionKey, bool _isExecuted, bool) external override onlyGMXPositionRouter {
        IRoute _route = IRoute(puppetOrchestrator.getTraderRouteForPositionKey(_positionKey));

        if (_isExecuted) {
            _route.approvePositionRequest();
        } else {
            _route.rejectPositionRequest();
        }

        emit GMXPositionCallback(_positionKey, address(_route), _isExecuted);
    }

    // ============================================================================================
    // Owner Functions
    // ============================================================================================

    function setPuppetOrchestrator(address _puppetOrchestrator) external onlyOwner {
        puppetOrchestrator = IPuppetOrchestrator(_puppetOrchestrator);
    }

    function setGMXPositionRouter(address _gmxPositionRouter) external onlyOwner {
        gmxPositionRouter = _gmxPositionRouter;
    }

    function setOwner(address _owner) external onlyOwner {
        owner = _owner;
    }

    // ============================================================================================
    // Events
    // ============================================================================================

    event GMXPositionCallback(bytes32 indexed _positionKey, address indexed _route, bool indexed _isExecuted);

    // ============================================================================================
    // Errors
    // ============================================================================================

    error NotOwner();
    error NotGMXPositionRouter();
}