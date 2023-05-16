// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IInputValidator {

    function validatePositionParameters(bytes memory _traderPositionData, uint256 _traderAmountIn, uint256 _puppetsAmountIn, bool _isIncrease) external;

    function validateSwapPath(bytes memory _traderSwapData, address _collateralToken) external;
}