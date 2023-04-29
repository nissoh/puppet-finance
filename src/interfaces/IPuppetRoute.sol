// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IPuppetRoute {

    // ============================================================================================
    // Mutated Functions
    // ============================================================================================

    function createPosition(bytes memory _positionData, bool _isIncrease) external returns (bytes32 _requestKey);

    function closePosition(bytes memory _positionData) external;

    function onLiquidation() external;

    function setTraderRoute(address _puppetRoute) external;

    // ============================================================================================
    // View Functions
    // ============================================================================================

    function getIsPositionOpen() external view returns (bool);

    function getPuppetShares(address _puppet) external view returns (uint256);

    // ============================================================================================
    // Events
    // ============================================================================================

    event FeesCollected(uint256 _requiredAssets);
    event FeesAndCollateralCollected(uint256 _requiredAssets);
    event ResetPosition();

    // ============================================================================================
    // Errors
    // ============================================================================================

    error NotTraderRoute();
    error PositionStillAlive();
    error ZeroAmount();
    error AssetsAmonutMismatch();
}