// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface IOrchestrator {

    function balanceOf(address addr) external view returns (uint256);

    function balanceOf(address addr, uint256 t) external view returns (uint256);

    function balanceOfAt(address addr, uint256 _block) external view returns (uint256);

    function create_lock(uint256 _value, uint256 _unlock_time) external;

    function increase_amount(uint256 _value) external;
}