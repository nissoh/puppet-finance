// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// =========================== IMinter ==========================
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

interface IMinter {

    struct EpochInfo {
        uint256 rewards;
        uint256 claimed;
        uint256 totalScore;
        uint256 totalProfit;
        uint256 totalVolumeGenerated;
        uint256 profitWeight;
        uint256 volumeWeight;
        mapping(address => UserPerformance) userPerformance;
    }

    struct UserPerformance {
        uint256 volumeGenerated;
        uint256 profit;
    }

    /// @notice Returns the address of the token
    /// @return _token The address of the token
    function token() external view returns (address _token);

    /// @notice Returns the address of the controller
    /// @return _controller The address of the controller
    function controller() external view returns (address _controller);

    /// @notice Mint everything which belongs to `_gauge` and send to it
    /// @param _gauge `ScoreGauge` address to mint for
    function mint(address _gauge) external;

    /// @notice Mint for multiple gauges
    /// @param _gauges List of `ScoreGauge` addresses
    function mintMany(address[] memory _gauges) external;

    // ============================================================================================
    // Events
    // ============================================================================================

    event Minted(address indexed gauge, uint256 minted, uint256 epoch);

    // ============================================================================================
    // Errors
    // ============================================================================================

    error GaugeIsKilled();
    error GaugeNotAdded();
    error EpochNotEnded();
    error AlreadyMinted();
}