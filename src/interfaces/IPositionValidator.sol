// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IPositionValidator {

    function validatePositionParameters(bytes memory _traderData, bytes memory _puppetsData, bool _isTraderIncrease, bool _isPuppetIncrease) external;
}