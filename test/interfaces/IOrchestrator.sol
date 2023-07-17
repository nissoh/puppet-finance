// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface IOrchestrator {

    struct GMXInfo {
        address gmxRouter;
        address gmxReader;
        address gmxVault;
        address gmxPositionRouter;
        address gmxReferralRebatesSender;
    }
}