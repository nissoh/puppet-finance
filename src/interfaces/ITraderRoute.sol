// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ITraderRoute {

    // ============================================================================================
    // Mutated Functions
    // ============================================================================================

    function createPosition(bytes memory _traderData, bytes memory _puppetsData, bool _isIncrease, bool _isPuppetIncrease) external payable;

    function notifyCallback() external;

    function onLiquidation(bytes memory _puppetPositionData) external;

    function setPuppetRoute(address _puppetRoute) external;

    // ============================================================================================
    // View Functions
    // ============================================================================================

    function getTraderAmountIn() external view returns (uint256);

    function getPuppetRoute() external view returns (address);

    function getIsWaitingForCallback() external view returns (bool);

    // ============================================================================================
    // Events
    // ============================================================================================

    event NotifyCallback();

    // ============================================================================================
    // Errors
    // ============================================================================================

    error NotPuppetRoute();
    error NotTrader();
    error PositionStillAlive();
}