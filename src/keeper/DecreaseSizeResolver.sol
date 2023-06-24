// SPDX-License-Identifier: AGPL
pragma solidity 0.8.17;

import {IOrchestrator} from "../interfaces/IOrchestrator.sol";
import {IRoute} from "../interfaces/IRoute.sol";
import {IGMXPositionRouter} from "../interfaces/IGMXPositionRouter.sol";

contract DecreaseSizeResolver {

    IOrchestrator public immutable orchestrator;

    constructor(IOrchestrator _orchestrator) {
        orchestrator = _orchestrator;
    }

    function checker(uint256 _executionFee) external view returns (bool _canExec, bytes memory _execPayload) {
        address[] memory _routes = orchestrator.routes();
        for (uint256 i = 0; i < _routes.length; i++) {
            IRoute _route = IRoute(_routes[i]);
            if (_route.isAdjustmentEnabled()) {
                bytes32 _routeKey = _route.routeKey();
                IRoute.AdjustPositionParams memory _adjustPositionParams = IRoute.AdjustPositionParams({
                    collateralDelta: 0, // we don't remove collateral
                    sizeDelta: _route.requiredAdjustmentSize(),
                    acceptablePrice: 0, // todo - get indexToken price from GMX's VaultPricefeed, add 50 bps slippage, make slippage configurable
                    minOut: 0 // minOut can be zero if no swap is required
                });

                _canExec = true;
                _execPayload = abi.encodeWithSelector(IRoute.decreaseSize.selector, _adjustPositionParams, _executionFee, _routeKey);
                break;
            }
        }
    }
}