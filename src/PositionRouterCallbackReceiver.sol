// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IPositionRouterCallbackReceiver} from "./interfaces/IPositionRouterCallbackReceiver.sol";
import {IOrchestrator} from "./interfaces/IOrchestrator.sol";
import {IRoute} from "./interfaces/IRoute.sol";

contract PositionRouterCallbackReceiver is IPositionRouterCallbackReceiver {

    address public owner;
    address public gmxPositionRouter;

    IOrchestrator orchestrator;

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

    function gmxPositionCallback(bytes32 _requestKey, bool _isExecuted, bool _isIncrease) external override onlyGMXPositionRouter {
        IRoute _route = IRoute(orchestrator.getRouteForRequestKey(_requestKey));

        _route.callback(_requestKey, _isExecuted, _isIncrease);

        emit GMXPositionCallback(_requestKey, address(_route), _isExecuted);
    }

    // ============================================================================================
    // Owner Functions
    // ============================================================================================

    function setOrchestrator(address _orchestrator) external onlyOwner {
        orchestrator = IOrchestrator(_orchestrator);
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