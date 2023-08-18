// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface IVotingEscrow {
    
        function getLastUserSlope(address addr) external view returns (int128);

        function lockedEnd(address addr) external view returns (uint256);
}
// todo finish this