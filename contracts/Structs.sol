pragma solidity ^0.4.17;

library AragonStructs {
    struct Employee {
        address[] allowedTokens;
        address[] tokens;
        bool exists;
        uint256 yearlySalaryUsd;
        
        // Ficticiously initialized to the timestamp when the employee is added,
        // to prevent immediate payout.
        uint256 lastPayoutTimestamp;
        
        uint256 lastAllocationTimestamp;
    
        // Distribution is optional, will not exist until employee calls determineAllocation()
        uint256[] distribution;
    }
}
