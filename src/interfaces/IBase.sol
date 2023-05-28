// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {AggregatorV3Interface} from "@chainlink/src/v0.8/interfaces/AggregatorV3Interface.sol";

interface IBase {

    struct PriceFeedInfo {
        uint256 decimals;
        AggregatorV3Interface priceFeed;
    }

    struct GMXInfo {
        address gmxRouter;
        address gmxReader;
        address gmxVault;
        address gmxPositionRouter;
        address gmxCallbackCaller;
        address gmxReferralRebatesSender;
    }

    // ============================================================================================
    // Events
    // ============================================================================================

    event SetOwner(address _owner);
    event StuckTokensRescued(address token, address to);

    // ============================================================================================
    // Errors
    // ============================================================================================

    error NotOwner();
    error ZeroAmount();
}