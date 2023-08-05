// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// @title Token Minter
// @author Curve Finance
// @license MIT

// todo - should mint to ScoreGauges instead of directly to users, according to the ScoreGauges relative weights in the GaugeController
contract GaugeContoller {

}

// interface LiquidityGauge:
//     # Presumably, other gauges will provide the same interfaces
//     def integrate_fraction(addr: address) -> uint256: view
//     def user_checkpoint(addr: address) -> bool: nonpayable

// interface MERC20:
//     def mint(_to: address, _value: uint256) -> bool: nonpayable

// interface GaugeController:
//     def gauge_types(addr: address) -> int128: view


// event Minted:
//     recipient: indexed(address)
//     gauge: address
//     minted: uint256


// token: public(address)
// controller: public(address)

// # user -> gauge -> value
// minted: public(HashMap[address, HashMap[address, uint256]])

// # minter -> user -> can mint?
// allowed_to_mint_for: public(HashMap[address, HashMap[address, bool]])


// @external
// def __init__(_token: address, _controller: address):
//     self.token = _token
//     self.controller = _controller


// @internal
// def _mint_for(gauge_addr: address, _for: address):
//     assert GaugeController(self.controller).gauge_types(gauge_addr) >= 0  # dev: gauge is not added

//     LiquidityGauge(gauge_addr).user_checkpoint(_for)
//     total_mint: uint256 = LiquidityGauge(gauge_addr).integrate_fraction(_for)
//     to_mint: uint256 = total_mint - self.minted[_for][gauge_addr]

//     if to_mint != 0:
//         MERC20(self.token).mint(_for, to_mint)
//         self.minted[_for][gauge_addr] = total_mint

//         log Minted(_for, gauge_addr, total_mint)

// function _mint_for(address gauge_addr, address _for) internal { // todo
//     require(IGaugeController(controller).gauge_types(gauge_addr) >= 0, "gauge is not added");
//     uint256 _epoch = IGaugeController(controller).epoch() - 1;
//     require(!minted[_epoch][gauge_addr], "already minted for this epoch");
//     require(block.timestamp >= _epochEndTime, "epoch has not ended yet");

//     // mintableInTimeframe(uint256 start, uint256 end)
//     uint256 _totalMint = IPuppet(controller).mintableInTimeframe(_epochStartTime, _epochEndTime);
//     // when starting a new epoch on controller, make sure to update and record the relative weights of the gauges // todo
//     uint256 _mintForGauge = _totalMint * IGaugeController(gauge_addr).relativeWeightAtEpoch(_epoch, gauge_addr) / 1e18;

//     if (_mintForGauge > 0) {
//         minted[_epoch][gauge_addr] = true;
//         IPuppet(token).mint(gauge_addr, _mintForGauge);
//         emit Minted(_for, gauge_addr, _mintForGauge);
//     }
// }

// @external
// @nonreentrant('lock')
// def mint(gauge_addr: address):
//     """
//     @notice Mint everything which belongs to `msg.sender` and send to them
//     @param gauge_addr `LiquidityGauge` address to get mintable amount from
//     """
//     self._mint_for(gauge_addr, msg.sender)


// @external
// @nonreentrant('lock')
// def mint_many(gauge_addrs: address[8]):
//     """
//     @notice Mint everything which belongs to `msg.sender` across multiple gauges
//     @param gauge_addrs List of `LiquidityGauge` addresses
//     """
//     for i in range(8):
//         if gauge_addrs[i] == ZERO_ADDRESS:
//             break
//         self._mint_for(gauge_addrs[i], msg.sender)


// @external
// @nonreentrant('lock')
// def mint_for(gauge_addr: address, _for: address):
//     """
//     @notice Mint tokens for `_for`
//     @dev Only possible when `msg.sender` has been approved via `toggle_approve_mint`
//     @param gauge_addr `LiquidityGauge` address to get mintable amount from
//     @param _for Address to mint to
//     """
//     if self.allowed_to_mint_for[msg.sender][_for]:
//         self._mint_for(gauge_addr, _for)


// @external
// def toggle_approve_mint(minting_user: address):
//     """
//     @notice allow `minting_user` to mint for `msg.sender`
//     @param minting_user Address to toggle permission for
//     """
//     self.allowed_to_mint_for[minting_user][msg.sender] = not self.allowed_to_mint_for[minting_user][msg.sender]