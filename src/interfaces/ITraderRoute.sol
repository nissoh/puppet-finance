// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ITraderRoute {

    // ============================================================================================
    // Mutated Functions
    // ============================================================================================

    function createPosition(bytes memory _traderData, bytes memory _puppetsData, bool _isIncrease, bool _isPuppetIncrease) external payable returns (bytes32 _positionKey) ;

    function notifyCallback() external;

    function createPuppetPosition() external;

    function onLiquidation(bytes memory _puppetPositionData) external;

    function setPuppetRoute(address payable _puppetRoute) external;

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
    event CreatePuppetPosition();

    // ============================================================================================
    // Errors
    // ============================================================================================

    error NotPuppetRoute();
    error NotTrader();
    error PositionStillAlive();
    error PositionNotApproved();
}