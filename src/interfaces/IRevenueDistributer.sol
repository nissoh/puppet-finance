// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ===================== IRevenueDistributer ====================
// ==============================================================

// Modified fork from Curve Finance: https://github.com/curvefi 
// @title Curve Fee Distribution
// @author Curve Finance
// @license MIT

// Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

interface IRevenueDistributer {

    struct Point {
        int128 bias;
        int128 slope; // - dweight / dt
        uint256 ts;
        uint256 blk; // block
    }

    // ============================================================================================
    // External Functions
    // ============================================================================================

    // View functions

    /// @notice Get the vePUPPET balance for `_user` at `_timestamp`
    /// @param _user Address to query balance for
    /// @param _timestamp Epoch time
    /// @return _veBalance uint256 vePUPPET balance
    function veForAt(address _user, uint256 _timestamp) external view returns (uint256 _veBalance);

    // Mutated functions

    /// @notice Update the token checkpoint
    /// @dev Calculates the total number of tokens to be distributed in a given week.
    ///      During setup for the initial distribution this function is only callable
    ///      by the contract owner. Beyond initial distro, it can be enabled for anyone
    ///      to call.
    function checkpointToken() external;

    /// @notice Update the veCRV total supply checkpoint
    /// @dev The checkpoint is also updated by the first claimant each
    ///      new epoch week. This function may be called independently
    ///      of a claim, to reduce claiming gas costs.
    function checkpointTotalSupply() external;

    /// @notice Claim fees for `_addr`
    /// @dev Each call to claim look at a maximum of 50 user veCRV points.
    ///      For accounts with many veCRV related actions, this function
    ///      may need to be called more than once to claim all available
    ///      fees. In the `Claimed` event that fires, if `claim_epoch` is
    ///      less than `max_epoch`, the account may claim again.
    /// @param _addr Address to claim fees for
    /// @return _amount uint256 Amount of fees claimed in the call
    function claim(address _addr) external returns (uint256 _amount);

    /// @notice Make multiple fee claims in a single call
    /// @dev Used to claim for many accounts at once, or to make
    ///      multiple claims for the same address when that address
    ///      has significant veCRV history
    /// @param _receivers List of addresses to claim for. Claiming
    ///                   terminates at the first `ZERO_ADDRESS`.
    /// @return _success bool success
    function claimMany(address[20] calldata _receivers) external returns (bool _success);

    /// @notice Receive `token` into the contract and trigger a token checkpoint
    /// @return _success bool success
    function burn() external returns (bool _success);

    /// @notice Commit transfer of ownership
    /// @param _addr New admin address
    function commitAdmin(address _addr) external;

    /// @notice Apply transfer of ownership
    function applyAdmin() external;

    /// @notice Toggle permission for checkpointing by any account
    function toggleAllowCheckpointToken() external;

    /// @notice Kill the contract
    /// @dev Killing transfers the entire 3CRV balance to the emergency return address
    ///      and blocks the ability to claim or burn. The contract cannot be unkilled.
    function killMe() external;

    /// @notice Recover ERC20 tokens from this contract
    /// @dev Tokens are sent to the emergency return address.
    /// @return _success bool success
    function recoverBalance() external returns (bool _success);

    // ============================================================================================
    // Events
    // ============================================================================================

    event Burn(uint256 amount);
    event CommitAdmin(address admin);
    event ApplyAdmin(address admin);
    event ToggleAllowCheckpointToken(bool toggleFlag);
    event CheckpointToken(uint256 time, uint256 tokens);
    event Claimed(address indexed recipient, uint256 amount, uint256 userEpoch, uint256 maxUserEpoch);
    event RecoverBalance(address token, uint256 amount);
    event Killed();

    // ============================================================================================
    // Errors
    // ============================================================================================

    error NotAuthorized();
    error NotAdmin();
    error ZeroAddress();
    error Dead();
}