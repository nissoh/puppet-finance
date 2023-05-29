// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Authority} from "@solmate/auth/Auth.sol";

import {IRouteFactory} from "./interfaces/IRouteFactory.sol";

import {Route} from "./Route.sol";

contract RouteFactory is IRouteFactory {

    function createRoute(Authority _authority, address _orchestrator, address _trader, address _collateralToken, address _indexToken, bool _isLong) external returns (address _route) {
        _route = address(new Route(_authority, _orchestrator, _trader, _collateralToken, _indexToken, _isLong));

        emit RouteCreated(msg.sender, _route, _orchestrator, _trader, _collateralToken, _indexToken, _isLong);
    }
}