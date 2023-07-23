// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {DeployerUtilities} from "script/utilities/DeployerUtilities.sol";

import {Puppet} from "src/token/Puppet.sol";
import {VotingEscrow} from "src/token/VotingEscrow.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract testVotingEscrow is Test, DeployerUtilities {

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public minter = makeAddr("minter");

    Puppet public puppetERC20;
    VotingEscrow public votingEscrow;

    function setUp() public {

        uint256 arbitrumFork = vm.createFork(vm.envString("ARBITRUM_RPC_URL"));
        vm.selectFork(arbitrumFork);

        vm.deal(owner, 100 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(minter, 100 ether);

        vm.startPrank(owner);
        puppetERC20 = new Puppet("Puppet Finance Token", "PUPPET", 18);
        puppetERC20.setMinter(minter);

        votingEscrow = new VotingEscrow(address(puppetERC20), "Vote-escrowed PUPPET", "vePUPPET", "1.0.0");
        vm.stopPrank();

        // mint some PUPPET to alice and bob
        skip(86400); // skip INFLATION_DELAY (1 day)
        puppetERC20.updateMiningParameters(); // start 1st epoch
        skip(86400 * 365); // skip the entire epoch (year)
        vm.startPrank(minter);
        puppetERC20.mint(alice, 100000 * 1e18);
        puppetERC20.mint(bob, 100000 * 1e18);
        vm.stopPrank();

        // whitelist alice and bob as contracts, because of Foundry limitation (msg.sender != tx.origin)
        vm.startPrank(owner);
        votingEscrow.addToWhitelist(alice);
        votingEscrow.addToWhitelist(bob);
        vm.stopPrank();
    }

    function testParamsOnDeployment() public {
        // sanity deploy params tests
        assertEq(votingEscrow.decimals(), 18, "testParamsOnDeployment: E0");
        assertEq(votingEscrow.name(), "Vote-escrowed PUPPET", "testParamsOnDeployment: E1");
        assertEq(votingEscrow.symbol(), "vePUPPET", "testParamsOnDeployment: E2");
        assertEq(votingEscrow.version(), "1.0.0", "testParamsOnDeployment: E3");
        assertEq(votingEscrow.token(), address(puppetERC20), "testParamsOnDeployment: E4");

        // sanity view functions tests
        assertEq(votingEscrow.getLastUserSlope(alice), 0, "testParamsOnDeployment: E5");
        assertEq(votingEscrow.userPointHistoryTs(alice, 0), 0, "testParamsOnDeployment: E6");
        assertEq(votingEscrow.lockedEnd(alice), 0, "testParamsOnDeployment: E7");
        assertEq(votingEscrow.balanceOf(alice), 0, "testParamsOnDeployment: E8");
        assertEq(votingEscrow.balanceOfAtT(alice, block.timestamp), 0, "testParamsOnDeployment: E9");
        assertEq(votingEscrow.balanceOfAt(alice, block.number), 0, "testParamsOnDeployment: E10");
        assertEq(votingEscrow.totalSupply(), 0, "testParamsOnDeployment: E11");
        assertEq(votingEscrow.totalSupplyAt(block.number), 0, "testParamsOnDeployment: E12");

        votingEscrow.checkpoint();

        assertEq(votingEscrow.getLastUserSlope(alice), 0, "testParamsOnDeployment: E13");
        assertEq(votingEscrow.userPointHistoryTs(alice, 0), 0, "testParamsOnDeployment: E14");
        assertEq(votingEscrow.lockedEnd(alice), 0, "testParamsOnDeployment: E15");
        assertEq(votingEscrow.balanceOf(alice), 0, "testParamsOnDeployment: E16");
        assertEq(votingEscrow.balanceOfAtT(alice, block.timestamp), 0, "testParamsOnDeployment: E17");
        assertEq(votingEscrow.balanceOfAt(alice, block.number), 0, "testParamsOnDeployment: E18");
        assertEq(votingEscrow.totalSupply(), 0, "testParamsOnDeployment: E19");
        assertEq(votingEscrow.totalSupplyAt(block.number), 0, "testParamsOnDeployment: E20");
    }

    function testMutated() public {
        vm.startPrank(alice);
        IERC20(address(puppetERC20)).approve(address(votingEscrow), puppetERC20.balanceOf(alice));
        votingEscrow.createLock(puppetERC20.balanceOf(alice), block.timestamp + votingEscrow.MAXTIME());
        vm.stopPrank();

        _checkUserVotingDataAfterCreateLock(alice);
    }

    function _checkUserVotingDataAfterCreateLock(address _user) internal {
        votingEscrow.checkpoint();
        // assertEq(votingEscrow.getLastUserSlope(_user), 0, "_checkUserVotingDataAfterCreateLock: E0");
        console.log("getLastUserSlope");
        console.log("getLastUserSlope: ", uint256(int256(votingEscrow.getLastUserSlope(_user))));
        // assertEq(votingEscrow.userPointHistoryTs(_user, 0), block.timestamp, "_checkUserVotingDataAfterCreateLock: E1");
        console.log("userPointHistoryTs0: ", votingEscrow.userPointHistoryTs(_user, 0));
        console.log("userPointHistoryTs1: ", votingEscrow.userPointHistoryTs(_user, 1));
        console.log("userPointHistoryTs2: ", votingEscrow.userPointHistoryTs(_user, 2));
        // assertEq(votingEscrow.lockedEnd(_user), block.timestamp + votingEscrow.MAXTIME(), "_checkUserVotingDataAfterCreateLock: E2");
        console.log("lockedEnd: ", votingEscrow.lockedEnd(_user));
        // assertEq(votingEscrow.balanceOf(_user), puppetERC20.balanceOf(_user), "_checkUserVotingDataAfterCreateLock: E3");
        console.log("balanceOf: ", votingEscrow.balanceOf(_user));
        console.log("puppetERC20.balanceOf(_user): ", puppetERC20.balanceOf(_user));
        // assertEq(votingEscrow.balanceOfAtT(_user, block.timestamp), puppetERC20.balanceOf(_user), "_checkUserVotingDataAfterCreateLock: E4");
        console.log("balanceOfAtT: ", votingEscrow.balanceOfAtT(_user, block.timestamp));
        // assertEq(votingEscrow.balanceOfAt(_user, block.number), puppetERC20.balanceOf(_user), "_checkUserVotingDataAfterCreateLock: E5");
        console.log("balanceOfAt: ", votingEscrow.balanceOfAt(_user, block.number));
        // assertEq(votingEscrow.totalSupply(), puppetERC20.balanceOf(_user), "_checkUserVotingDataAfterCreateLock: E6");
        console.log("totalSupply: ", votingEscrow.totalSupply());
        // assertEq(votingEscrow.totalSupplyAt(block.number), puppetERC20.balanceOf(_user), "_checkUserVotingDataAfterCreateLock: E7");
        console.log("totalSupplyAt: ", votingEscrow.totalSupplyAt(block.number));

        skip(86400);
        console.log("totalSupply1: ", votingEscrow.totalSupply());
        console.log("totalSupplyAt1: ", votingEscrow.totalSupplyAt(block.number)); // TODO - should be this 0?
        revert("ad");
    }
}