// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface IPuppet {
    
        function mintableInTimeframe(uint256 start, uint256 end) external view returns (uint256);

        function mint(address _to, uint256 _value) external returns (bool);

        function updateMiningParameters() external;
}