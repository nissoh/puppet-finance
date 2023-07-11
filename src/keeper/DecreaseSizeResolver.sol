// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ==================== DecreaseSizeResolver ====================
// ==============================================================
// Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

import {Auth, Authority} from "@solmate/auth/Auth.sol";

import {IGMXPositionRouter} from "../interfaces/IGMXPositionRouter.sol";
import {IGMXVaultPriceFeed} from "../interfaces/IGMXVaultPriceFeed.sol";

import {IOrchestrator} from "../interfaces/IOrchestrator.sol";
import {IRoute} from "../interfaces/IRoute.sol";

contract DecreaseSizeResolver is Auth {

    uint256 public executionFee;
    uint256 public priceFeedSlippage;

    uint256 private constant _BASIS_POINTS_DIVISOR = 10000;

    IOrchestrator public orchestrator;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    constructor(Authority _authority, IOrchestrator _orchestrator) Auth(address(0), _authority) {
        orchestrator = _orchestrator;

        executionFee = 180000000000000;
        priceFeedSlippage = 2000000; // 0.5%
    }

    // ============================================================================================
    // View Functions
    // ============================================================================================

    function checker() external view returns (bool _canExec, bytes memory _execPayload) {
        address[] memory _routes = orchestrator.routes();
        for (uint256 i = 0; i < _routes.length; i++) {
            IRoute _route = IRoute(_routes[i]);
            if (_route.isAdjustmentEnabled()) {
                bytes32 _routeKey = _route.routeKey();
                IRoute.AdjustPositionParams memory _adjustPositionParams = IRoute.AdjustPositionParams({
                    collateralDelta: 0, // we don't remove collateral
                    sizeDelta: _route.requiredAdjustmentSize(),
                    acceptablePrice: _getAcceptablePrice(_route),
                    minOut: 0 // minOut can be zero if no swap is required
                });

                _canExec = true;
                _execPayload = abi.encodeWithSelector(
                    IOrchestrator.adjustTargetLeverage.selector,
                    _adjustPositionParams,
                    executionFee,
                    _routeKey
                );

                break;
            }
        }
    }

    function _getAcceptablePrice(IRoute _route) internal view returns (uint256) {
        if (_route.isLong()) {
            return orchestrator.getPrice(_route.indexToken()) * _BASIS_POINTS_DIVISOR / priceFeedSlippage;
        } else {
            return orchestrator.getPrice(_route.indexToken()) * priceFeedSlippage / _BASIS_POINTS_DIVISOR;
        }
    }

    // ============================================================================================
    // Authority Functions
    // ============================================================================================

    function setOrchestrator(IOrchestrator _orchestrator) external requiresAuth {
        orchestrator = _orchestrator;
    }

    function setExecutionFee(uint256 _executionFee) external requiresAuth {
        executionFee = _executionFee;
    }

    function setPriceFeedSlippage(uint256 _priceFeedSlippage) external requiresAuth {
        priceFeedSlippage = _priceFeedSlippage;
    }
}