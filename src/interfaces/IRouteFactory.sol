// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ======================== IRouteFactory =======================
// ==============================================================
// Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

import {Authority} from "@solmate/auth/Auth.sol";

interface IRouteFactory {

    // ============================================================================================
    // External Functions
    // ============================================================================================

    /// @notice The ```registerRouteAccount``` is called on Orchestrator.registerRouteAccount
    /// @param _orchestrator The address of the Orchestrator
    /// @param _weth The address of the WETH Token
    /// @param _trader The address of the Trader
    /// @param _collateralToken The address of the Collateral Token
    /// @param _indexToken The address of the Index Token
    /// @param _isLong The boolean value of the position
    /// @return _route The address of the new Route
    function registerRouteAccount(address _orchestrator, address _weth, address _trader, address _collateralToken, address _indexToken, bool _isLong) external returns (address _route);

    // ============================================================================================
    // Events
    // ============================================================================================

    event RegisterRouteAccount(address indexed caller, address route, address orchestrator, address trader, address collateralToken, address indexToken, bool isLong);
}