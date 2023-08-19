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

    IPuppet private immutable _token;
    IGaugeController private immutable _controller;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    constructor(address _tokenAddr, address _controllerAddr) {
        _token = IPuppet(_tokenAddr);
        _controller = IGaugeController(_controllerAddr);
    }

    // ============================================================================================
    // External functions
    // ============================================================================================

    /// @inheritdoc IMinter
    function token() external view returns (address) {
        return address(_token);
    }

    /// @inheritdoc IMinter
    function controller() external view returns (address) {
        return address(_controller);
    }

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

        IGaugeController __controller = _controller;
        if (__controller.gaugeTypes(_gauge) < 0) revert GaugeNotAdded();

        uint256 _epoch = __controller.epoch() - 1; // underflows if epoch() is 0
        if (!__controller.hasEpochEnded(_epoch)) revert EpochNotEnded();
        if (minted[_epoch][_gauge]) revert AlreadyMinted();

        (uint256 _epochStartTime, uint256 _epochEndTime) = __controller.epochTimeframe(_epoch);
        if (block.timestamp < _epochEndTime) revert EpochNotEnded();

        uint256 _totalMint = _token.mintableInTimeframe(_epochStartTime, _epochEndTime);
        uint256 _mintForGauge = _totalMint * __controller.gaugeWeightForEpoch(_epoch, _gauge) / 1e18;

        if (_mintForGauge > 0) {
            minted[_epoch][_gauge] = true;
            _token.mint(_gauge, _mintForGauge);
            IScoreGauge(_gauge).depositRewards(_epoch, _mintForGauge);

            emit Minted(_gauge, _mintForGauge, _epoch);
        }
    }
}