// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IScoreGauge} from "src/interfaces/IScoreGauge.sol";

contract RouteMock {

    IScoreGauge public scoreGauge;

    constructor(address _gauge) {
        scoreGauge = IScoreGauge(_gauge);
    }

    function updateScoreGauge(uint256 _cumulativeVolumeGenerated, uint256 _profit, address _user) external {
        scoreGauge.updateUserScore(_cumulativeVolumeGenerated, _profit, _user);
    }
}