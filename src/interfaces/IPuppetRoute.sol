// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IPuppetRoute {

    // ====================== Functions ======================

    function createPosition(bytes memory _positionData, bool _isIncrease) public;

    function closePosition(bytes memory _positionData) external;

    function onLiquidation() external;

    function setTraderRoute(address _puppetRoute) external;

    // ====================== Events ======================

    event FeesCollected(uint256 _requiredAssets);
    event FeesAndCollateralCollected(uint256 _requiredAssets);
    event ResetPosition();

    // ====================== Errors ======================

    error NotTraderRoute();
    error PositionStillAlive();
    error ZeroAmount();
    error AssetsAmonutMismatch();
}