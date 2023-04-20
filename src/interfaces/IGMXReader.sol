// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IGMXReader {

    function getPositions(address _vault, address _account, address[] memory _collateralTokens, address[] memory _indexTokens, bool[] memory _isLong) external view returns(uint256[] memory);
}