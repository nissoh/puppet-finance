// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IPositionValidator {

    function validatePositionParameters(bytes memory _traderPositionData, uint256 _traderAmountIn, uint256 _puppetsAmountIn, bool _isIncrease) external;
}