// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ======================== IScoreGauge =======================
// ==============================================================
// Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

interface IScoreGauge {

    /// @notice The ```updateTraderScore``` is called when Route settles a trade
    /// @param _cumulativeVolumeGenerated The uint256 value of the cumulative volume generated, USD denominated, with 30 decimals
    /// @param _profit The uint256 value of the profit, USD denominated, with 30 decimals
    function updateTraderScore(uint256 _cumulativeVolumeGenerated, uint256 _profit) external;
}