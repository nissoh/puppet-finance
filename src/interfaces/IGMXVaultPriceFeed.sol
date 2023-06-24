// SPDX-License-Identifier: AGPL
pragma solidity 0.8.17;

interface IGMXVaultPriceFeed {

    function getPrice(address _token, bool _maximise, bool _includeAmmPrice, bool) external view returns (uint256);   
}