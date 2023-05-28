// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IRouteFactory {

    // ============================================================================================
    // External Functions
    // ============================================================================================

    function createRoute(address _orchestrator, address _owner, address _trader, address _collateralToken, address _indexToken, bool _isLong) external returns (address _route);

    // ============================================================================================
    // Events
    // ============================================================================================

    event RouteCreated(address indexed route, address indexed orchestrator, address indexed owner, address trader, address collateralToken, address indexToken, bool isLong);
}