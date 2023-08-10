// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

contract ScoreGaugeMock {

    mapping(address => uint256) public userVolume;
    mapping(address => uint256) public userProfit;

    /// @notice The ```updateUserScore``` is called per user (Trader/Puppet) when Route settles a trade
    /// @param _cumulativeVolumeGenerated The uint256 value of the cumulative volume generated, USD denominated, with 30 decimals
    /// @param _profit The uint256 value of the profit, USD denominated, with 30 decimals
    /// @param _user The address of the user
    /// @param _isTrader The bool value of whether the address is a Trader or Puppet
    function updateUserScore(uint256 _cumulativeVolumeGenerated, uint256 _profit, address _user, bool _isTrader) external {
        userVolume[_user] += _cumulativeVolumeGenerated;
        userProfit[_user] += _profit;
    }
}