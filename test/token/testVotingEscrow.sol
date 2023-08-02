// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ICRVVotingEscrow} from "../interfaces/ICRVVotingEscrow.sol";
import {ISmartWalletWhitelist} from "../interfaces/ISmartWalletWhitelist.sol";

import {DeployerUtilities} from "script/utilities/DeployerUtilities.sol";

import {Puppet} from "src/token/Puppet.sol";
import {VotingEscrow} from "src/token/VotingEscrow.sol";

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

    ICRVVotingEscrow public crvVotingEscrow = ICRVVotingEscrow(0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2);

    function setUp() public {

        uint256 arbitrumFork = vm.createFork(vm.envString("ARBITRUM_RPC_URL"));
        vm.selectFork(arbitrumFork);

        // uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        // vm.selectFork(mainnetFork);

        vm.deal(owner, 100 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(yossi, 100 ether);
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
        _totalSupplyBefore = votingEscrow.totalSupply();
        skip(votingEscrow.MAXTIME() / 2); // skip half of the lock time
        _checkLockTimesAfterSkipHalf(_aliceBalanceBefore, _bobBalanceBefore, _totalSupplyBefore);

        _checkIncreaseUnlockTimeWrongFlows(alice);
        vm.startPrank(alice);
        uint256 _aliceBalanceBeforeUnlock = votingEscrow.balanceOf(alice);
        uint256 _totalSupplyBeforeUnlock = votingEscrow.totalSupply();
        votingEscrow.increaseUnlockTime(block.timestamp + votingEscrow.MAXTIME());
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 _bobBalanceBeforeUnlock = votingEscrow.balanceOf(bob);
        votingEscrow.increaseUnlockTime(block.timestamp + votingEscrow.MAXTIME());
        vm.stopPrank();

        _checkUserLockTimesAfterIncreaseUnlockTime(_aliceBalanceBeforeUnlock, _aliceBalanceBefore, _totalSupplyBeforeUnlock, _totalSupplyBefore, alice);
        _checkUserLockTimesAfterIncreaseUnlockTime(_bobBalanceBeforeUnlock, _bobBalanceBefore, _totalSupplyBeforeUnlock, _totalSupplyBefore, bob);

        // --- INCREASE AMOUNT ---

        _checkIncreaseAmountWrongFlows(alice);
        vm.startPrank(alice);
        _aliceBalanceBefore = votingEscrow.balanceOf(alice);
        _totalSupplyBefore = votingEscrow.totalSupply();
        IERC20(address(puppetERC20)).approve(address(votingEscrow), _aliceAmountLocked);
        votingEscrow.increaseAmount(_aliceAmountLocked);
        vm.stopPrank();
        _checkUserBalancesAfterIncreaseAmount(alice, _aliceBalanceBefore, _totalSupplyBefore, _aliceAmountLocked);

        _checkIncreaseAmountWrongFlows(bob);
        vm.startPrank(bob);
        _bobBalanceBefore = votingEscrow.balanceOf(bob);
        _totalSupplyBefore = votingEscrow.totalSupply();
        IERC20(address(puppetERC20)).approve(address(votingEscrow), _bobAmountLocked);
        votingEscrow.increaseAmount(_bobAmountLocked);
        vm.stopPrank();
        _checkUserBalancesAfterIncreaseAmount(bob, _bobBalanceBefore, _totalSupplyBefore, _bobAmountLocked);

        // --- WITHDRAW ---

        _checkWithdrawWrongFlows(alice);

        _totalSupplyBefore = votingEscrow.totalSupply();

        skip(votingEscrow.MAXTIME()); // entire lock time

        vm.startPrank(alice);
        _aliceBalanceBefore = puppetERC20.balanceOf(alice);
        votingEscrow.withdraw();
        vm.stopPrank();
        _checkUserBalancesAfterWithdraw(alice, _totalSupplyBefore, _aliceBalanceBefore);

        vm.startPrank(bob);
        _bobBalanceBefore = puppetERC20.balanceOf(bob);
        votingEscrow.withdraw();
        vm.stopPrank();
        _checkUserBalancesAfterWithdraw(bob, _totalSupplyBefore, _bobBalanceBefore);
    }

    function _testMutatedOnCRV() internal {
        address _crv = 0xD533a949740bb3306d119CC777fa900bA034cd52;
        _dealERC20(_crv, alice , 100000 * 1e18);
        _dealERC20(_crv, bob , 100000 * 1e18);

        // approve alice
        vm.startPrank(address(0x40907540d8a6C65c637785e8f8B742ae6b0b9968)); // dao address
        ISmartWalletWhitelist(address(0xca719728Ef172d0961768581fdF35CB116e0B7a4)).approveWallet(alice);
        ISmartWalletWhitelist(address(0xca719728Ef172d0961768581fdF35CB116e0B7a4)).approveWallet(bob);
        vm.stopPrank();

        // ======= CREATE LOCK =======

        vm.startPrank(alice);
        uint256 _aliceAmountLocked = IERC20(_crv).balanceOf(alice) / 3;
        IERC20(_crv).approve(address(crvVotingEscrow), _aliceAmountLocked);
        crvVotingEscrow.create_lock(_aliceAmountLocked, block.timestamp + (4 * 365 * 86400));
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 _bobAmountLocked = IERC20(_crv).balanceOf(bob) / 3;
        IERC20(_crv).approve(address(crvVotingEscrow), _bobAmountLocked);
        crvVotingEscrow.create_lock(_bobAmountLocked, block.timestamp + (4 * 365 * 86400));
        vm.stopPrank();

        // ======= DEPOSIT FOR =======

        vm.startPrank(bob);
        IERC20(_crv).approve(address(crvVotingEscrow), _bobAmountLocked);
        vm.stopPrank();
        vm.startPrank(alice);
        crvVotingEscrow.deposit_for(bob, _aliceAmountLocked);
        vm.stopPrank();

        vm.startPrank(alice);
        IERC20(_crv).approve(address(crvVotingEscrow), _bobAmountLocked);
        vm.stopPrank();
        vm.startPrank(bob);
        crvVotingEscrow.deposit_for(alice, _bobAmountLocked);
        vm.stopPrank();

        // --- INCREASE UNLOCK TIME ---

        skip((4 * 365 * 86400) / 2); // skip half of the lock time

        vm.startPrank(alice);
        crvVotingEscrow.increase_unlock_time(block.timestamp + (4 * 365 * 86400));
        vm.stopPrank();
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

    function _checkLockTimesAfterSkipHalf(uint256 _aliceBalanceBefore, uint256 _bobBalanceBefore, uint256 _totalSupplyBefore) internal {
        assertApproxEqAbs(votingEscrow.balanceOf(alice), _aliceBalanceBefore / 2, 1e21, "_checkLockTimesAfterSkipHalf: E0");
        assertApproxEqAbs(votingEscrow.balanceOf(bob), _bobBalanceBefore / 2, 1e21, "_checkLockTimesAfterSkipHalf: E1");
        assertEq(votingEscrow.balanceOfAtT(alice, block.timestamp - votingEscrow.MAXTIME() / 2), _aliceBalanceBefore, "_checkLockTimesAfterSkipHalf: E2");
        assertEq(votingEscrow.balanceOfAtT(bob, block.timestamp - votingEscrow.MAXTIME() / 2), _bobBalanceBefore, "_checkLockTimesAfterSkipHalf: E3");
        assertApproxEqAbs(votingEscrow.totalSupply(), _totalSupplyBefore / 2, 1e21, "_checkLockTimesAfterSkipHalf: E4");
        assertEq(votingEscrow.totalSupplyAtT(block.timestamp - votingEscrow.MAXTIME() / 2), _totalSupplyBefore, "_checkLockTimesAfterSkipHalf: E5");
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

    function _checkUserLockTimesAfterIncreaseUnlockTime(uint256 _userBalanceBeforeUnlock, uint256 _userBalanceBefore, uint256 _totalSupplyBeforeUnlock, uint256 _totalSupplyBefore, address _user) internal {
        assertApproxEqAbs(votingEscrow.lockedEnd(_user), block.timestamp + votingEscrow.MAXTIME(), 1e6, "_checkUserLockTimesAfterIncreaseUnlockTime: E0");
        assertApproxEqAbs(votingEscrow.balanceOf(_user), _userBalanceBeforeUnlock * 2, 1e21, "_checkUserLockTimesAfterIncreaseUnlockTime: E1");
        assertApproxEqAbs(votingEscrow.balanceOfAtT(_user, block.timestamp), _userBalanceBeforeUnlock * 2, 1e21, "_checkUserLockTimesAfterIncreaseUnlockTime: E2");
        // assertEq(votingEscrow.balanceOfAtT(_user, block.timestamp - votingEscrow.MAXTIME() / 2), votingEscrow.balanceOf(_user), "_checkUserLockTimesAfterIncreaseUnlockTime: E3");
        assertTrue(votingEscrow.totalSupply() > _totalSupplyBeforeUnlock, "_checkUserLockTimesAfterIncreaseUnlockTime: E4");
        assertApproxEqAbs(votingEscrow.totalSupply(), _totalSupplyBefore, 1e21, "_checkUserLockTimesAfterIncreaseUnlockTime: E5");
        assertApproxEqAbs(_userBalanceBefore, votingEscrow.balanceOf(_user), 1e21, "_checkUserLockTimesAfterIncreaseUnlockTime: E6");
    }

    function _checkIncreaseAmountWrongFlows(address _user) internal {
        vm.startPrank(_user);
        vm.expectRevert();
        votingEscrow.increaseAmount(0);
        vm.stopPrank();
    }

    function _checkUserBalancesAfterIncreaseAmount(address _user, uint256 _balanceBefore, uint256 _totalSupplyBefore, uint256 _amountLocked) internal {
        assertApproxEqAbs(votingEscrow.balanceOf(_user), _balanceBefore + _amountLocked, 1e21, "_checkUserBalancesAfterIncreaseAmount: E0");
        assertApproxEqAbs(votingEscrow.totalSupply(), _totalSupplyBefore + _amountLocked, 1e21, "_checkUserBalancesAfterIncreaseAmount: E1");   
    }

    function _checkWithdrawWrongFlows(address _user) internal {
        vm.startPrank(_user);
        vm.expectRevert(); // reverts with ```The lock didn't expire```
        votingEscrow.withdraw();
        vm.stopPrank();
    }

    function _checkUserBalancesAfterWithdraw(address _user, uint256 _totalSupplyBefore, uint256 _puppetBalanceBefore) internal {
        assertEq(votingEscrow.balanceOf(_user), 0, "_checkUserBalancesAfterWithdraw: E0");
        assertTrue(votingEscrow.totalSupply() < _totalSupplyBefore, "_checkUserBalancesAfterWithdraw: E1");
        assertTrue(puppetERC20.balanceOf(_user) > _puppetBalanceBefore, "_checkUserBalancesAfterWithdraw: E2");
    }

    function _dealERC20(address _token, address _recipient , uint256 _amount) internal {
        deal({ token: address(_token), to: _recipient, give: _amount});
    }
}