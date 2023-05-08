// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

contract PrizePoolDistributor {
    
    // TODO 
 
    // ============================================================================================
    // Receive Function
    // ============================================================================================

    receive() external payable {
        if (orchestrator.getReferralRebatesSender() == msg.sender) payable(orchestrator.getPrizePoolDistributor()).sendValue(msg.value);
    }
}