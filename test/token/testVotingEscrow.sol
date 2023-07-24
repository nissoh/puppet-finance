// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {DeployerUtilities} from "script/utilities/DeployerUtilities.sol";

import {Puppet} from "src/token/Puppet.sol";
import {VotingEscrow} from "src/token/VotingEscrow.sol";
import {VePuppet} from "src/token/vePuppetOLD.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract testVotingEscrow is Test, DeployerUtilities {

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public yossi = makeAddr("yossi");
    address public minter = makeAddr("minter");

    Puppet public puppetERC20;
    VotingEscrow public votingEscrow;
    VePuppet public vePuppet;

    function setUp() public {

        uint256 arbitrumFork = vm.createFork(vm.envString("ARBITRUM_RPC_URL"));
        vm.selectFork(arbitrumFork);

        vm.deal(owner, 100 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(yossi, 100 ether);
        vm.deal(minter, 100 ether);

        vm.startPrank(owner);
        puppetERC20 = new Puppet("Puppet Finance Token", "PUPPET", 18);
        puppetERC20.setMinter(minter);

        votingEscrow = new VotingEscrow(address(puppetERC20), "Vote-escrowed PUPPET", "vePUPPET", "1.0.0");
        vePuppet = new VePuppet(address(puppetERC20), 1);
        vm.stopPrank();

        // mint some PUPPET to alice and bob
        skip(86400); // skip INFLATION_DELAY (1 day)
        puppetERC20.updateMiningParameters(); // start 1st epoch
        skip(86400 * 365); // skip the entire epoch (year)
        vm.startPrank(minter);
        puppetERC20.mint(alice, 100000 * 1e18);
        puppetERC20.mint(bob, 100000 * 1e18);
        puppetERC20.mint(yossi, 100000 * 1e18);
        vm.stopPrank();

        // whitelist alice and bob as contracts, because of Foundry limitation (msg.sender != tx.origin)
        vm.startPrank(owner);
        votingEscrow.addToWhitelist(alice);
        votingEscrow.addToWhitelist(bob);
        votingEscrow.addToWhitelist(yossi);
        vm.stopPrank();
    }

    // =======================================================
    // Tests
    // =======================================================

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
        uint256 _aliceAmountLocked = puppetERC20.balanceOf(alice) / 3;
        uint256 _bobAmountLocked = puppetERC20.balanceOf(bob) / 3;
        uint256 _totalSupplyBefore;

        // --- CREATE LOCK ---

        // alice
        _checkCreateLockWrongFlows(alice);
        vm.startPrank(alice);
        _totalSupplyBefore = votingEscrow.totalSupply();
        IERC20(address(puppetERC20)).approve(address(votingEscrow), _aliceAmountLocked);
        votingEscrow.createLock(_aliceAmountLocked, block.timestamp + votingEscrow.MAXTIME());
        vm.stopPrank();
        _checkUserVotingDataAfterCreateLock(alice, _aliceAmountLocked, _totalSupplyBefore);

        // bob
        _checkCreateLockWrongFlows(bob);
        vm.startPrank(bob);
        _totalSupplyBefore = votingEscrow.totalSupply();
        IERC20(address(puppetERC20)).approve(address(votingEscrow), _bobAmountLocked);
        votingEscrow.createLock(_bobAmountLocked, block.timestamp + votingEscrow.MAXTIME());
        vm.stopPrank();
        _checkUserVotingDataAfterCreateLock(bob, _bobAmountLocked, _totalSupplyBefore);

        // --- DEPOSIT FOR ---

        // alice
        _checkDepositForWrongFlows(_aliceAmountLocked, alice, bob);
        vm.startPrank(bob);
        IERC20(address(puppetERC20)).approve(address(votingEscrow), _bobAmountLocked);
        vm.stopPrank();
        vm.startPrank(alice);
        _totalSupplyBefore = votingEscrow.totalSupply();
        uint256 _aliceBalanceBefore = votingEscrow.balanceOf(alice);
        uint256 _bobBalanceBefore = votingEscrow.balanceOf(bob);
        votingEscrow.depositFor(bob, _aliceAmountLocked);
        vm.stopPrank();
        _checkUserBalancesAfterDepositFor(alice, bob, _aliceBalanceBefore, _bobBalanceBefore, _aliceAmountLocked, _totalSupplyBefore);

        // bob
        _checkDepositForWrongFlows(_bobAmountLocked, bob, alice);
        vm.startPrank(alice);
        IERC20(address(puppetERC20)).approve(address(votingEscrow), _aliceAmountLocked);
        vm.stopPrank();
        vm.startPrank(bob);
        _totalSupplyBefore = votingEscrow.totalSupply();
        _aliceBalanceBefore = votingEscrow.balanceOf(alice);
        _bobBalanceBefore = votingEscrow.balanceOf(bob);
        votingEscrow.depositFor(alice, _bobAmountLocked);
        vm.stopPrank();
        _checkUserBalancesAfterDepositFor(bob, alice, _bobBalanceBefore, _aliceBalanceBefore, _bobAmountLocked, _totalSupplyBefore);

        // --- INCREASE UNLOCK TIME ---

        _checkLockTimesBeforeSkip();
        _aliceBalanceBefore = votingEscrow.balanceOf(alice);
        _bobBalanceBefore = votingEscrow.balanceOf(bob);
        console.log("alice max locked balance: ", votingEscrow.balanceOf(alice));
        uint256 _tsBefore = block.timestamp;
        skip(votingEscrow.MAXTIME() / 2); // skip half of the lock time
        console.log("alice half locked balance: ", votingEscrow.balanceOf(alice));
        _checkLockTimesAfterSkipHalf(_aliceBalanceBefore, _bobBalanceBefore);

        _checkIncreaseUnlockTimeWrongFlows(alice);
        vm.startPrank(alice);
        uint256 _aliceBalanceBeforeUnlock = votingEscrow.balanceOf(alice);
        uint256 _totalSupplyBeforeUnlock = votingEscrow.totalSupply();
        votingEscrow.increaseUnlockTime(block.timestamp + votingEscrow.MAXTIME());
        console.log("alice max locked balance:1 ", votingEscrow.balanceOf(alice));
        vm.stopPrank();
        _checkUserLockTimesAfterIncreaseUnlockTime(_tsBefore, _aliceBalanceBeforeUnlock, _aliceBalanceBefore, _totalSupplyBeforeUnlock, _totalSupplyBefore, alice);



        // skip(86400 * 20);
        // skip(86400 * 20);
        // skip(86400 * 20);
        // vm.roll(block.number + 100);

        // vm.startPrank(bob);
        // console.log("lockedEnd69: ", votingEscrow.lockedEnd(bob));
        // votingEscrow.increaseUnlockTime(block.timestamp + votingEscrow.MAXTIME());
        // console.log("lockedEnd6969: ", votingEscrow.lockedEnd(bob));
        // vm.stopPrank();

        // --- INCREASE AMOUNT ---

        // --- WITHDRAW ---
    }

    // =======================================================
    // Internal functions
    // =======================================================

    function _checkCreateLockWrongFlows(address _user) internal {
        uint256 _puppetBalance = puppetERC20.balanceOf(_user);
        uint256 _maxTime = votingEscrow.MAXTIME();
        require(_puppetBalance > 0, "no PUPPET balance");

        vm.startPrank(_user);
        
        vm.expectRevert(); // ```"Arithmetic over/underflow"``` (NO ALLOWANCE)
        votingEscrow.createLock(_puppetBalance, block.timestamp + _maxTime);

        IERC20(address(puppetERC20)).approve(address(votingEscrow), _puppetBalance);

        vm.expectRevert("need non-zero value");
        votingEscrow.createLock(0, block.timestamp + _maxTime);

        vm.expectRevert("Can only lock until time in the future");
        votingEscrow.createLock(_puppetBalance, block.timestamp - 1);

        vm.expectRevert("Voting lock can be 4 years max");
        votingEscrow.createLock(_puppetBalance, block.timestamp + _maxTime + _maxTime);

        IERC20(address(puppetERC20)).approve(address(votingEscrow), 0);

        vm.stopPrank();
    }

    function _checkUserVotingDataAfterCreateLock(address _user, uint256 _amountLocked, uint256 _totalSupplyBefore) internal {
        vm.startPrank(_user);

        uint256 _puppetBalance = puppetERC20.balanceOf(_user);
        uint256 _maxTime = votingEscrow.MAXTIME();
        IERC20(address(puppetERC20)).approve(address(votingEscrow), _puppetBalance);
        vm.expectRevert("Withdraw old tokens first");
        votingEscrow.createLock(_puppetBalance, block.timestamp + _maxTime);
        IERC20(address(puppetERC20)).approve(address(votingEscrow), 0);

        assertTrue(votingEscrow.getLastUserSlope(_user) != 0, "_checkUserVotingDataAfterCreateLock: E0");
        assertTrue(votingEscrow.userPointHistoryTs(_user, 1) != 0, "_checkUserVotingDataAfterCreateLock: E1");
        assertApproxEqAbs(votingEscrow.lockedEnd(_user), block.timestamp + votingEscrow.MAXTIME(), 1e10, "_checkUserVotingDataAfterCreateLock: E2");
        assertApproxEqAbs(votingEscrow.balanceOf(_user), _amountLocked, 1e23, "_checkUserVotingDataAfterCreateLock: E3");
        assertApproxEqAbs(votingEscrow.balanceOfAtT(_user, block.timestamp), _amountLocked, 1e23, "_checkUserVotingDataAfterCreateLock: E4");
        assertApproxEqAbs(votingEscrow.balanceOfAt(_user, block.number), _amountLocked, 1e23, "_checkUserVotingDataAfterCreateLock: E5");
        assertApproxEqAbs(votingEscrow.totalSupply(), _totalSupplyBefore + _amountLocked, 1e23, "_checkUserVotingDataAfterCreateLock: E6");
        assertApproxEqAbs(votingEscrow.totalSupplyAt(block.number), _totalSupplyBefore + _amountLocked, 1e23, "_checkUserVotingDataAfterCreateLock: E7");
    }

    function _checkDepositForWrongFlows(uint256 _amount, address _user, address _receiver) internal {
        vm.startPrank(_user);

        vm.expectRevert("need non-zero value");
        votingEscrow.depositFor(_receiver, 0);

        vm.expectRevert("No existing lock found");
        votingEscrow.depositFor(yossi, _amount);

        vm.expectRevert(); // ```"Arithmetic over/underflow"``` (NO ALLOWANCE)
        votingEscrow.depositFor(_receiver, _amount);

        vm.stopPrank();
    }

    function _checkUserBalancesAfterDepositFor(address _user, address _receiver, uint256 _userBalanceBefore, uint256 _receiverBalanceBefore, uint256 _amount, uint256 _totalSupplyBefore) internal {
        assertEq(votingEscrow.balanceOf(_user), _userBalanceBefore, "_checkUserBalancesAfterDepositFor: E0");
        assertApproxEqAbs(votingEscrow.balanceOf(_receiver), _receiverBalanceBefore + _amount, 1e23, "_checkUserBalancesAfterDepositFor: E1");
        assertEq(votingEscrow.balanceOfAtT(_user, block.timestamp), _userBalanceBefore, "_checkUserBalancesAfterDepositFor: E2");
        assertApproxEqAbs(votingEscrow.balanceOfAtT(_receiver, block.timestamp), _receiverBalanceBefore + _amount, 1e23, "_checkUserBalancesAfterDepositFor: E3");
        assertEq(votingEscrow.balanceOfAt(_user, block.number), _userBalanceBefore, "_checkUserBalancesAfterDepositFor: E4");
        assertApproxEqAbs(votingEscrow.balanceOfAt(_receiver, block.number), _receiverBalanceBefore + _amount, 1e23, "_checkUserBalancesAfterDepositFor: E5");
        assertApproxEqAbs(votingEscrow.totalSupply(), _totalSupplyBefore + _amount, 1e23, "_checkUserBalancesAfterDepositFor: E6");
        assertApproxEqAbs(votingEscrow.totalSupplyAt(block.number), _totalSupplyBefore + _amount, 1e23, "_checkUserBalancesAfterDepositFor: E7");
    }

    function _checkLockTimesBeforeSkip() internal {
        assertApproxEqAbs(votingEscrow.lockedEnd(alice), block.timestamp + votingEscrow.MAXTIME(), 1e6, "_checkLockTimesBeforeSkip: E0");
        assertApproxEqAbs(votingEscrow.lockedEnd(bob), block.timestamp + votingEscrow.MAXTIME(), 1e6, "_checkLockTimesBeforeSkip: E1");
    }

    function _checkLockTimesAfterSkipHalf(uint256 _aliceBalanceBefore, uint256 _bobBalanceBefore) internal {
        assertApproxEqAbs(votingEscrow.balanceOf(alice), _aliceBalanceBefore / 2, 1e20, "_checkLockTimesAfterSkipHalf: E0");
        assertApproxEqAbs(votingEscrow.balanceOf(bob), _bobBalanceBefore / 2, 1e20, "_checkLockTimesAfterSkipHalf: E1");
        assertEq(votingEscrow.balanceOfAtT(alice, block.timestamp - votingEscrow.MAXTIME() / 2), _aliceBalanceBefore, "_checkLockTimesAfterSkipHalf: E2");
        assertEq(votingEscrow.balanceOfAtT(bob, block.timestamp - votingEscrow.MAXTIME() / 2), _bobBalanceBefore, "_checkLockTimesAfterSkipHalf: E3");
    }

    function _checkIncreaseUnlockTimeWrongFlows(address _user) internal {
        uint256 _maxTime = votingEscrow.MAXTIME();
        uint256 _userLockEnd = votingEscrow.lockedEnd(_user);

        vm.startPrank(yossi);
        vm.expectRevert("No existing lock found");
        votingEscrow.increaseUnlockTime(block.timestamp + _maxTime);
        vm.stopPrank();

        vm.startPrank(_user);
        vm.expectRevert("Can only increase lock duration");
        votingEscrow.increaseUnlockTime(_userLockEnd);
        vm.stopPrank();

        vm.startPrank(_user);
        vm.expectRevert("Voting lock can be 4 years max");
        votingEscrow.increaseUnlockTime(block.timestamp + _maxTime + _maxTime);
        vm.stopPrank();
    }

    function _checkUserLockTimesAfterIncreaseUnlockTime(uint256 _tsBefore, uint256 _userBalanceBeforeUnlock, uint256 _userBalanceBefore, uint256 _totalSupplyBeforeUnlock, uint256 _totalSupplyBefore, address _user) internal {
        assertApproxEqAbs(votingEscrow.lockedEnd(_user), block.timestamp + votingEscrow.MAXTIME(), 1e6, "_checkUserLockTimesAfterIncreaseUnlockTime: E0");
        assertApproxEqAbs(votingEscrow.balanceOf(_user), _userBalanceBeforeUnlock * 2, 1e20, "_checkUserLockTimesAfterIncreaseUnlockTime: E1");
        assertApproxEqAbs(votingEscrow.balanceOfAtT(_user, block.timestamp), _userBalanceBeforeUnlock * 2, 1e20, "_checkUserLockTimesAfterIncreaseUnlockTime: E2");
        assertEq(votingEscrow.balanceOfAtT(_user, _tsBefore), votingEscrow.balanceOf(_user), "_checkUserLockTimesAfterIncreaseUnlockTime: E3");
        assertTrue(votingEscrow.totalSupply() > _totalSupplyBeforeUnlock, "_checkUserLockTimesAfterIncreaseUnlockTime: E4");
        assertApproxEqAbs(votingEscrow.totalSupply(), _totalSupplyBefore, 1e21, "_checkUserLockTimesAfterIncreaseUnlockTime: E5");
        assertEq(_userBalanceBefore, votingEscrow.balanceOf(_user), "_checkUserLockTimesAfterIncreaseUnlockTime: E6");
    }
}