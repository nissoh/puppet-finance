// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IGMXVault {

    function validateLiquidation(address _account, address _collateralToken, address _indexToken, bool _isLong, bool _raise) external view returns (uint256, uint256);
}