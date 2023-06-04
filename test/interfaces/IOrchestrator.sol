// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IOrchestrator {

    struct GMXInfo {
        address gmxRouter;
        address gmxReader;
        address gmxVault;
        address gmxPositionRouter;
        address gmxReferralRebatesSender;
    }
}