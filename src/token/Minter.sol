// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {IPuppet} from "src/interfaces/IPuppet.sol";
import {IGaugeController} from "src/interfaces/IGaugeController.sol";

// @title Token Minter
// @author Curve Finance
// @license MIT

contract Minter is ReentrancyGuard {

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

    /// @notice Mint everything which belongs to `_gauge` and send to it
    /// @param _gauge `ScoreGauge` address to mint for
    function mint(address _gauge) external nonReentrant {
        _mint(_gauge);
    }

    /// @notice Mint for multiple gauges
    /// @param _gauges List of `ScoreGauge` addresses
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
        IGaugeController _controller = controller;
        require(_controller.gauge_types(_gauge) >= 0, "gauge is not added");

        uint256 _epoch = _controller.epoch() - 1; // underflows if epoch() is 0
        require(_controller.hasEpochEnded(_epoch), "epoch has not ended yet");
        require(!minted[_epoch][_gauge], "already minted for this epoch");

        (uint256 _epochStartTime, uint256 _epochEndTime) = _controller.epochTimeframe(_epoch);
        require(block.timestamp >= _epochEndTime, "epoch has not ended yet1");

        uint256 _totalMint = token.mintableInTimeframe(_epochStartTime, _epochEndTime);
        uint256 _mintForGauge = _totalMint * _controller.gaugeWeightForEpoch(_epoch, _gauge) / 1e18;

        if (_mintForGauge > 0) {
            minted[_epoch][_gauge] = true;
            token.mint(_gauge, _mintForGauge);

            emit Minted(_gauge, _mintForGauge);
        }
    }

    // ============================================================================================
    // Events
    // ============================================================================================

    event Minted(address indexed gauge, uint256 minted);
}