// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {RouteMock} from "test/mocks/RouteMock.sol";
import {IScoreGauge} from "src/interfaces/IScoreGauge.sol";

contract OrchestratorMock {

    IScoreGauge public scoreGauge;

    constructor(address _gauge) {
        scoreGauge = IScoreGauge(_gauge);
    }

    function isRoute(address) external pure returns (bool) {
        return true;
    }

    function deployRouteMock() external returns (address) {
        return address(new RouteMock(address(scoreGauge)));
    }
}