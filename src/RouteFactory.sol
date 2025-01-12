// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ====================== RouteFactory ==========================
// ==============================================================
// Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

import {IRouteFactory} from "./interfaces/IRouteFactory.sol";

import {Route} from "./Route.sol";

/// @title RouteFactory
/// @author johnnyonline (Puppet Finance) https://github.com/johnnyonline
/// @notice This contract is used by the Orchestrator to create new Routes
contract RouteFactory is IRouteFactory {

    /// @inheritdoc IRouteFactory
    function registerRouteAccount(
        address _orchestrator,
        address _weth,
        address _trader,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) external returns (address _route) {
        _route = address(new Route(_orchestrator, _weth, _trader, _collateralToken, _indexToken, _isLong));

        emit RegisterRouteAccount(msg.sender, _route, _orchestrator, _trader, _collateralToken, _indexToken, _isLong);
    }
}