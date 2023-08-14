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

    struct UserScore {
        uint256 cumulativeVolumeGenerated;
        uint256 profit;
    }

    struct Score {
        uint256 totalCumulativeVolumeGenerated;
        uint256 totalProfit;
        mapping(address => UserScore) tradersScore;
        mapping(address => UserScore) puppetsScore;
    }

    /// @notice The ```updateUserScore``` is called per user (Trader/Puppet) when Route settles a trade
    /// @param _volumeGenerated The uint256 value of the cumulative volume generated, USD denominated, with 30 decimals
    /// @param _profit The uint256 value of the profit, USD denominated, with 30 decimals
    /// @param _user The address of the user
    /// @param _isTrader The bool value of whether the address is a Trader or Puppet
    function updateUserScore(uint256 _volumeGenerated, uint256 _profit, address _user, bool _isTrader) external;

    function isKilled() external view returns (bool);

    error ZeroAddress();
}