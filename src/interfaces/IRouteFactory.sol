// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Authority} from "@solmate/auth/Auth.sol";

interface IRouteFactory {

    // ============================================================================================
    // External Functions
    // ============================================================================================

    function createRoute(Authority _authority, address _orchestrator, address _trader, address _collateralToken, address _indexToken, bool _isLong) external returns (address _route);

    // ============================================================================================
    // Events
    // ============================================================================================

    event RouteCreated(address indexed caller, address indexed route, address indexed orchestrator, address trader, address collateralToken, address indexToken, bool isLong);
}