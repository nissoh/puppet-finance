// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract PuppetV2 {

    // FLOW
    // 1. users chooses a bunch of registered traders + deposits funds
    // 2. trader opens a position using the funds deposited by him + investors that have selected him, according to the global rules (e.g. 1% puppet deposit balance)
    // 3. when trader modifies a position - take assets from puppets, pro rata to the manager's change (e.g. if manager doubles the amount of collateral, also double the amount of collateral of the puppet), no more than global role thuogh (trader modify position is like create a new position)
    // 
    // accounting is done via shares, only 1 position is opened per trader/route (so shares are on position)
    
    // address of puppet/trader (trade participents) to amount of shares
    // enumerablemap AddressToUintMap

    // using EnumerableMap for EnumerableMap.AddressToUintMap;

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