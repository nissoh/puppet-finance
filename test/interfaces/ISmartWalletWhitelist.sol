// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface ISmartWalletWhitelist {
    function approveWallet(address _wallet) external;
}