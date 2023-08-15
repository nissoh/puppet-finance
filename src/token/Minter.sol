// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ========================== Minter ============================
// ==============================================================

// Modified fork from Curve Finance: https://github.com/curvefi 
// @title Token Minter
// @author Curve Finance
// @license MIT

// Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {IMinter} from "src/interfaces/IMinter.sol";
import {IPuppet} from "src/interfaces/IPuppet.sol";
import {IScoreGauge} from "src/interfaces/IScoreGauge.sol";
import {IGaugeController} from "src/interfaces/IGaugeController.sol";

contract Minter is ReentrancyGuard, IMinter {

    mapping(uint256 => mapping(address => bool)) public minted; // epoch -> gauge -> hasMinted

    IPuppet public token;
    IGaugeController public controller;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    constructor(address _token, address _controller) {
        token = IPuppet(_token);
        controller = IGaugeController(_controller);
    }

    // ============================================================================================
    // External functions
    // ============================================================================================

    /// @inheritdoc IMinter
    function mint(address _gauge) external nonReentrant {
        _mint(_gauge);
    }

    /// @inheritdoc IMinter
    function mintMany(address[] memory _gauges) external nonReentrant {
        for (uint256 i = 0; i < _gauges.length; i++) {
            if (_gauges[i] == address(0)) {
                break;
            }
            _mint(_gauges[i]);
        }
    }

    // ============================================================================================
    // Internal functions
    // ============================================================================================

    function _mint(address _gauge) internal {
        if (IScoreGauge(_gauge).isKilled()) revert GaugeIsKilled();

        IGaugeController _controller = controller;
        if (_controller.gaugeTypes(_gauge) <= 0) revert GaugeNotAdded();

        uint256 _epoch = _controller.epoch() - 1; // underflows if epoch() is 0
        if (!_controller.hasEpochEnded(_epoch)) revert EpochHasNotEnded();
        if (minted[_epoch][_gauge]) revert AlreadyMinted();

        (uint256 _epochStartTime, uint256 _epochEndTime) = _controller.epochTimeframe(_epoch);
        if (block.timestamp < _epochEndTime) revert EpochHasNotEnded();

        uint256 _totalMint = token.mintableInTimeframe(_epochStartTime, _epochEndTime);
        uint256 _mintForGauge = _totalMint * _controller.gaugeWeightForEpoch(_epoch, _gauge) / 1e18;

        if (_mintForGauge > 0) {
            minted[_epoch][_gauge] = true;
            token.mint(_gauge, _mintForGauge);
            IScoreGauge(_gauge).depositRewards(_mintForGauge);

            emit Minted(_gauge, _mintForGauge);
        }
    }
}