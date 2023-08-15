// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ========================= IScoreGauge ========================
// ==============================================================

// Modified fork from Curve Finance: https://github.com/curvefi 
// @title Liquidity Gauge
// @author Curve Finance
// @license MIT
// @notice Used for measuring liquidity and insurance

// Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

interface IScoreGauge {

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

    /// @notice The ```claimableRewards``` returns the amount of rewards claimable by a user for a given epoch
    /// @param _epoch The uint256 value of the epoch
    /// @param _user The address of the user
    /// @return _userReward The uint256 value of the claimable rewards, with 18 decimals
    function claimableRewards(uint256 _epoch, address _user) external view returns (uint256 _userReward);

    /// @notice The ```isKilled``` function returns whether the gauge is killed or not
    /// @return _isKilled The bool value of the gauge status
    function isKilled() external view returns (bool _isKilled);

    /// @notice The ```depositRewards``` function allows the minter to mint rewards for the current epoch
    /// @param _amount The uint256 value of the amount of minted rewards, with 18 decimals
    function depositRewards(uint256 _amount) external;

    /// @notice The ```claim``` function allows a user to claim rewards for a given epoch
    /// @param _epoch The uint256 value of the epoch
    /// @return _userReward The uint256 value of the claimable rewards, with 18 decimals
    function claim(uint256 _epoch) external returns (uint256 _userReward);

    /// @notice The ```updateUserScore``` is called by Routes when a trade is settled, for each user (Trader/Puppet)
    /// @param _volumeGenerated The uint256 value of the cumulative volume generated, USD denominated, with 30 decimals
    /// @param _profit The uint256 value of the profit, USD denominated, with 30 decimals
    /// @param _user The address of the user
    function updateUserScore(uint256 _volumeGenerated, uint256 _profit, address _user) external;

    /// @notice The ```killMe``` is called by the admin to kill the gauge
    function killMe() external;    

    // ============================================================================================
    // Events
    // ============================================================================================

    event DepositRewards(uint256 amount);
    event Claim(uint256 indexed epoch, uint256 userReward, address indexed user);
    event UserScoreUpdate(address indexed user, uint256 volumeGenerated, uint256 profit);

    // ============================================================================================
    // Errors
    // ============================================================================================

    error NotMinter();
    error InvalidEpoch();
    error AlreadyClaimed();
    error NotRoute();
}