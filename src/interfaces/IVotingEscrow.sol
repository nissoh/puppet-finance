// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ======================= IVotingEscrow ========================
// ==============================================================

// Modified fork from Curve Finance: https://github.com/curvefi 
// @title Voting Escrow
// @author Curve Finance
// @license MIT
// @notice Votes have a weight depending on time, so that users are committed to the future of (whatever they are voting for)
// @dev Vote weight decays linearly over time. Lock time cannot be more than `MAXTIME` (4 years).

// Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

interface IVotingEscrow {

        struct Point {
                int128 bias;
                int128 slope; // - dweight / dt
                uint256 ts;
                uint256 blk; // block
        }
        // We cannot really do block numbers per se b/c slope is per time, not per block
        // and per block could be fairly bad b/c Ethereum changes blocktimes.
        // What we can do is to extrapolate ***At functions

        struct LockedBalance {
                int128 amount;
                uint256 end;
        }
    
        // ============================================================================================
        // External functions
        // ============================================================================================

        // view functions

        /// @notice Get the most recently recorded rate of voting power decrease for `addr`
        /// @param _addr Address of the user wallet
        /// @return _value Value of the slope
        function getLastUserSlope(address _addr) external view returns (int128 _value);

        /// @notice Get the timestamp for checkpoint `_idx` for `_addr`
        /// @param _addr User wallet address
        /// @param _idx User epoch number
        /// @return _time Epoch time of the checkpoint
        function userPointHistoryTs(address _addr, uint256 _idx) external view returns (uint256 _time);

        /// @notice Get timestamp when `_addr`'s lock finishes
        /// @param _addr User wallet
        /// @return _time Epoch time of the lock end
        function lockedEnd(address _addr) external view returns (uint256 _time);

        // NOTE: The following ERC20/minime-compatible methods are not real balanceOf and supply!
        // They measure the weights for the purpose of voting, so they don't represent real coins.

        /// @notice Get the Voting Escrow balance of `_addr` at timestamp `_t`
        /// @param _addr User wallet address
        /// @param _t Epoch time
        /// @return _balance Voting power
        function balanceOfAtT(address _addr, uint256 _t) external view returns (uint256 _balance);

        /// @notice Get the Voting Escrow balance of `_addr` at the current timestamp
        /// @param _addr User wallet address
        /// @return _balance Voting power
        function balanceOf(address _addr) external view returns (uint256 _balance);

        /// @notice Measure voting power of `addr` at block height `_block`
        /// @dev Adheres to MiniMe `balanceOfAt` interface: https://github.com/Giveth/minime
        /// @param addr User's wallet address
        /// @param _block Block to calculate the voting power at
        /// @return _balance Voting power
        function balanceOfAt(address addr, uint256 _block) external view returns (uint256 _balance);

        /// @notice Calculate total voting power
        /// @dev Adheres to the ERC20 `totalSupply` interface for Aragon compatibility
        /// @return _supply Total voting power
        function totalSupply() external view returns (uint256 _supply);

        /// @notice Calculate total voting power at timestamp `_t`
        /// @param _t Timestamp
        /// @return _supply Total voting power
        function totalSupplyAtT(uint256 _t) external view returns (uint256 _supply);

        /// @notice Calculate total voting power at block height `_block`
        /// @param _block Block height
        /// @return _supply Total voting power
        function totalSupplyAt(uint256 _block) external view returns (uint256 _supply);

        // mutated functions

        /// @notice Record global data to checkpoint
        function checkpoint() external;

        /// @notice Deposit `_value` tokens for `_addr` and add to the lock
        /// @dev Anyone (even a smart contract) can deposit for someone else, but 
        /// cannot extend their locktime and deposit for a brand new user
        /// @param _addr User's wallet address
        /// @param _value Amount to add to user's lock
        function depositFor(address _addr, uint256 _value) external;

        /// @notice Deposit `_value` tokens for `msg.sender` and lock until `_unlockTime`
        /// @param _value Amount to deposit
        /// @param _unlockTime Epoch time when tokens unlock, rounded down to whole weeks
        function createLock(uint256 _value, uint256 _unlockTime) external;

        /// @notice Deposit `_value` additional tokens for `msg.sender` without modifying the unlock time
        /// @param _value Amount of tokens to deposit and add to the lock
        function increaseAmount(uint256 _value) external;

        /// @notice Extend the unlock time for `msg.sender` to `_unlockTime`
        /// @param _unlockTime New epoch time for unlocking
        function increaseUnlockTime(uint256 _unlockTime) external;

        /// @notice Withdraw all tokens for `msg.sender`
        /// @dev Only possible if the lock has expired
        function withdraw() external;

        /// @notice Transfer ownership of VotingEscrow contract to `addr`
        /// @param _addr Address to have ownership transferred to
        function commitTransferOwnership(address _addr) external;

        /// @notice Apply ownership transfer
        function applyTransferOwnership() external;

        /// @notice Add address to whitelist smart contract depositors `addr`
        /// @param _addr Address to be whitelisted
        function addToWhitelist(address _addr) external;

        /// @notice Remove a smart contract address from whitelist
        /// @param _addr Address to be removed from whitelist
        function removeFromWhitelist(address _addr) external;

        /// @notice Unlock all locked balances
        function unlock() external;

        // ============================================================================================
        // Events
        // ============================================================================================

        event CommitOwnership(address admin);
        event ApplyOwnership(address admin);
        event Deposit(address provider, uint256 value, uint256 locktime, int128 type_, uint256 ts);
        event Withdraw(address provider, uint256 value, uint256 ts);
        event Supply(uint256 prevSupply, uint256 supply);

        // ============================================================================================
        // Errors
        // ============================================================================================

        error ZeroAddress();
        error LockNotExpired();
        error NoLockFound();
        error LockTimeTooLong();
        error LockTimeInThePast();
        error LockExpired();
        error ZeroValue();
        error WithdrawOldTokensFirst();
        error Unlocked();
        error NotAdmin();
        error NotWhitelisted();
}