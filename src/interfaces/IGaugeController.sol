// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface IGaugeController {
    
        function gauge_types(address _addr) external view returns (int128);

        function epoch() external view returns (uint256);

        function epochTimeframe(uint256 _epoch) external view returns (uint256, uint256);

        function gaugeWeightForEpoch(uint256 _epoch, address _gauge) external view returns (uint256);
}