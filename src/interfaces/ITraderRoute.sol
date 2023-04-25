// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ITraderRoute {

    // ====================== Functions ======================

    function getTraderAmountIn() external pure returns (uint256);

    function createPosition(bytes memory _traderData, bytes memory _puppetsData, bool _isIncrease, bool _isPuppetIncrease) external payable;

    function notifyCallback(bool _isIncrease) external;

    function onLiquidation(bytes memory _puppetPositionData) external;

    function setPuppetRoute(address _puppetRoute) external;

    // ====================== Events ======================

    event NotifyCallback(bool isIncrease);

    // ====================== Errors ======================

    error NotPuppetRoute();
    error NotTrader();
    error PositionStillAlive();
}