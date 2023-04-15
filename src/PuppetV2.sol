// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract PuppetV2 {

    struct RouteInfo {
        // shares of route participents (puppets + manager)
        EnumerableMap.AddressToUintMap shares;
        // puppets
        EnumerableSet.AddressSet participents;
    }

    // route(=position/trade) => routeInfo
    mapping(bytes32 => RouteInfo) private routeInfo;

    // ====================== Trader Functions ======================

    // ====================== Puppet Functions ======================

    function deposit(uint256 _amount, address _puppet) public {
        puppetBalance[_puppet] += _amount;
        IERC20(WETH).transferFrom(msg.sender, address(this), _amount);
    }

    function chooseTraders(address[] memory _traders) public {
        for (uint256 i = 0; i < _traders.length; i++) {
            ITrader(_traders[i]).addPuppet(msg.sender);
            // map(enumerablemap)
        }
    }
}