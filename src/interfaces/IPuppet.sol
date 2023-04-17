// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IPuppet {
    function cancelPosition(bytes32 _gmxPositionKey) external;
}