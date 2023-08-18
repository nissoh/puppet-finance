// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// =========================== Puppet ===========================
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
    // event CommitAdmin:
//     admin: address

// event ApplyAdmin:
//     admin: address

// event ToggleAllowCheckpointToken:
//     toggle_flag: bool

// event CheckpointToken:
//     time: uint256
//     tokens: uint256

// event Claimed:
//     recipient: indexed(address)
//     amount: uint256
//     claim_epoch: uint256
//     max_epoch: uint256


// struct Point:
//     bias: int128
//     slope: int128  # - dweight / dt
//     ts: uint256
//     blk: uint256  # block

error NotAuthorized
}