// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IPositionRouterCallbackReceiver} from "./interfaces/IPositionRouterCallbackReceiver.sol";
import {IPuppet} from "./interfaces/IPuppet.sol";

contract PositionRouterCallbackReceiver is IPositionRouterCallbackReceiver {

    error Unauthorized();

    event GMXPositionCallback(bytes32 indexed _positionKey, bool indexed _isExecuted);

    address public puppetContract;
    address public owner;
    address public gmxPositionRouter;

    constructor(address _owner) {
        owner = _owner;
    }

    function setPuppetContract(address _puppetContract) external {
        if (msg.sender != owner) revert Unauthorized();

        puppetContract = _puppetContract;
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

        if (_isExecuted) {
            IPuppet(puppetContract).approvePosition(_positionKey);
        } else {
            if (_isPositionOpen(_positionKey)) {
                if (_isIncrease) {
                    IPuppet(puppetContract).rejectIncreasePosition(_positionKey, true);
                } else {
                    IPuppet(puppetContract).rejectDecreasePosition(_positionKey, true);
                }
            } else {
                if (_isIncrease) {
                    IPuppet(puppetContract).rejectIncreasePosition(_positionKey, false);
                } else {
                    IPuppet(puppetContract).rejectDecreasePosition(_positionKey, false);
                }
            }
        }
        emit GMXPositionCallback(_positionKey, _isExecuted);
    }

    function _isPositionOpen(bytes32 _positionKey) internal returns (bool _isOpen) {} // TODO 
}