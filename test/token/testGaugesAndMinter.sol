// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// import {ICRVVotingEscrow} from "../interfaces/ICRVVotingEscrow.sol";
// import {ISmartWalletWhitelist} from "../interfaces/ISmartWalletWhitelist.sol";

import {DeployerUtilities} from "script/utilities/DeployerUtilities.sol";

import {Puppet} from "src/token/Puppet.sol";
import {VotingEscrow} from "src/token/VotingEscrow.sol";
import {GaugeController} from "src/token/GaugeController.sol";
import {Minter} from "src/token/Minter.sol";
import {ScoreGaugeV1} from "src/token/ScoreGaugeV1.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";
// todo - test score gauge
contract testGaugesAndMinter is Test, DeployerUtilities {

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public yossi = makeAddr("yossi");
    address public minter = makeAddr("minter");

    Puppet public puppetERC20;
    Minter public minterContract;
    VotingEscrow public votingEscrow;
    GaugeController public gaugeController;
    ScoreGaugeV1 public scoreGauge1V1;
    ScoreGaugeV1 public scoreGauge2V1;
    ScoreGaugeV1 public scoreGauge3V1;

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

        votingEscrow = new VotingEscrow(address(puppetERC20), "Vote-escrowed PUPPET", "vePUPPET", "1.0.0");

        gaugeController = new GaugeController(address(puppetERC20), address(votingEscrow));

        minterContract = new Minter(address(puppetERC20), address(gaugeController));
        puppetERC20.setMinter(address(minterContract));

        scoreGauge1V1 = new ScoreGaugeV1(owner, address(minterContract), address(gaugeController));
        scoreGauge2V1 = new ScoreGaugeV1(owner, address(minterContract), address(gaugeController));
        scoreGauge3V1 = new ScoreGaugeV1(owner, address(minterContract), address(gaugeController));

        vm.stopPrank();

        // mint some PUPPET to alice and bob
        // skip(86400); // skip INFLATION_DELAY (1 day)
        // puppetERC20.updateMiningParameters(); // start 1st epoch
        // skip(86400 * 365); // skip the entire epoch (year)
        vm.startPrank(owner);
        uint256 _balance = IERC20(address(puppetERC20)).balanceOf(owner) / 3;
        IERC20(address(puppetERC20)).transfer(alice, _balance);
        IERC20(address(puppetERC20)).transfer(bob, _balance);
        IERC20(address(puppetERC20)).transfer(yossi, _balance);
        vm.stopPrank();

        // whitelist alice and bob as contracts, because of Foundry limitation (msg.sender != tx.origin)
        vm.startPrank(owner);
        votingEscrow.addToWhitelist(alice);
        votingEscrow.addToWhitelist(bob);
        votingEscrow.addToWhitelist(yossi);
        vm.stopPrank();

        // vote lock for alice
        vm.startPrank(alice);
        _balance = IERC20(address(puppetERC20)).balanceOf(alice);
        IERC20(address(puppetERC20)).approve(address(votingEscrow), _balance);
        votingEscrow.createLock(_balance, block.timestamp + votingEscrow.MAXTIME());
        vm.stopPrank();

        // vote lock for bob
        vm.startPrank(bob);
        _balance = IERC20(address(puppetERC20)).balanceOf(bob);
        IERC20(address(puppetERC20)).approve(address(votingEscrow), _balance);
        votingEscrow.createLock(_balance, block.timestamp + votingEscrow.MAXTIME());
        vm.stopPrank();

        // vote lock for yossi
        vm.startPrank(yossi);
        _balance = IERC20(address(puppetERC20)).balanceOf(yossi);
        IERC20(address(puppetERC20)).approve(address(votingEscrow), _balance);
        votingEscrow.createLock(_balance, block.timestamp + votingEscrow.MAXTIME());
        vm.stopPrank();
    }

    // =======================================================
    // Tests
    // =======================================================

    function testCorrectFlow() public {
        
        // ADD GAUGE TYPE1
        _preGaugeTypeAddAsserts();
        vm.startPrank(owner);
        gaugeController.addType("Arbitrum", 1000000000000000000);
        vm.stopPrank();
        _postGaugeTypeAddAsserts();

        // ADD GAUGE1
        _preGauge1AddAsserts();
        vm.startPrank(owner);
        gaugeController.addGauge(address(scoreGauge1V1), 0, 1);
        vm.stopPrank();
        _postGauge1AddAsserts();

        // ADD GAUGE2
        _preGauge2AddAsserts();
        vm.startPrank(owner);
        gaugeController.addGauge(address(scoreGauge2V1), 0, 0);
        vm.stopPrank();
        _postGauge2AddAsserts();

        // ADD GAUGE TYPE2
        _preGauge2TypeAddAsserts();
        vm.startPrank(owner);
        gaugeController.addType("Optimism", 1000000000000000000);
        vm.stopPrank();
        _postGauge2TypeAddAsserts();

        // ADD GAUGE3
        _preGauge3AddAsserts();
        vm.startPrank(owner);
        gaugeController.addGauge(address(scoreGauge3V1), 1, 0);
        vm.stopPrank();
        _postGauge3AddAsserts();

        // INIT 1st EPOCH
        _preInitEpochAsserts();
        skip(86400); // wait _INFLATION_DELAY so we can initEpoch
        vm.startPrank(owner);
        gaugeController.initializeEpoch();
        vm.stopPrank();
        _postInitEpochAsserts(); // epoch has not ended yet

        skip(86400 * 7); // skip epoch duration (1 week)
        _preAdvanceEpochAsserts(); // epoch has ended
        gaugeController.advanceEpoch();
        _postAdvanceEpochAsserts();

        // MINT REWARDS FOR 1st EPOCH
        address[] memory _gauges = new address[](3);
        _gauges[0] = address(scoreGauge1V1);
        _gauges[1] = address(scoreGauge2V1);
        _gauges[2] = address(scoreGauge3V1);
        minterContract.mintMany(_gauges);
        _postMintRewardsAsserts();

        // VOTE FOR 2nd EPOCH (gauge2 gets all rewards) (we vote immediately after minting, if we wait a few days, votes will be valid for 3rd epoch)
        _preVote2ndEpochAsserts();
        _userVote2ndEpoch(alice);
        _userVote2ndEpoch(bob);
        _userVote2ndEpoch(yossi);

        // ON 2nd EPOCH END
        skip(86400 * 7); // skip 1 epoch (1 week)
        _pre2ndEpochEndAsserts(); // (before calling advanceEpoch())
        gaugeController.advanceEpoch();
        _post2ndEpochEndAsserts();

        // MINT REWARDS FOR 2nd EPOCH
        uint256 _gauge1BalanceBefore = puppetERC20.balanceOf(address(scoreGauge1V1));
        minterContract.mintMany(_gauges);
        _postMintFor2ndEpochRewardsAsserts(_gauge1BalanceBefore);

        // VOTE FOR 3rd EPOCH (gauge1 gets half of rewards, gauge2 gets half of rewards)
        // skip(86400 * 1); // skip 5 days, just to make it more realistic
        _userVote3rdEpoch(alice);
        _userVote3rdEpoch(bob);
        _userVote3rdEpoch(yossi);
        _postVote3rdEpochAsserts();

        // ON 3rd EPOCH END
        skip(86400 * 7); // skip the 2 days left in the epoch
        _pre3rdEpochEndAsserts(); // (before calling advanceEpoch())
        gaugeController.advanceEpoch();
        _post3rdEpochEndAsserts();

        // MINT REWARDS FOR 3rd EPOCH
        _gauge1BalanceBefore = puppetERC20.balanceOf(address(scoreGauge1V1));
        uint256 _gauge2BalanceBefore = puppetERC20.balanceOf(address(scoreGauge2V1));
        minterContract.mintMany(_gauges);
        _postMintFor3rdEpochRewardsAsserts(_gauge1BalanceBefore, _gauge2BalanceBefore);

        // VOTE FOR 4th EPOCH (gauge3 gets all rewards)
        skip(86400 * 2); // skip 2 days, just to make it more realistic
        _userVote4thEpoch(alice);
        _userVote4thEpoch(bob);
        _userVote4thEpoch(yossi);
        _postVote4thEpochAsserts();

        // ON 4th EPOCH END
        skip(86400 * 5); // skip the 5 days left in the epoch
        _pre4thEpochEndAsserts(); // (before calling advanceEpoch())
        gaugeController.advanceEpoch();
        _post4thEpochEndAsserts();
    }

    // =======================================================
    // Internal Helper Functions
    // =======================================================

    function _preGaugeTypeAddAsserts() internal {
        assertEq(gaugeController.gauge_type_names(0), "", "_preGaugeTypeAddAsserts: E0");
        assertEq(gaugeController.n_gauge_types(), 0, "_preGaugeTypeAddAsserts: E1");
        assertEq(gaugeController.getTypeWeight(0), 0, "_preGaugeTypeAddAsserts: E2");
        assertEq(gaugeController.getTotalWeight(), 0, "_preGaugeTypeAddAsserts: E3");
        assertEq(gaugeController.getWeightsSumPerType(0), 0, "_preGaugeTypeAddAsserts: E4");

        bytes4 selector = bytes4(keccak256("NotAdmin()"));
        vm.expectRevert(); // vm.expectRevert(); // "only admin"
        gaugeController.addType("Arbitrum", 0);
    }

    function _postGaugeTypeAddAsserts() internal {
        assertEq(gaugeController.gauge_type_names(0), "Arbitrum", "_postGaugeTypeAddAsserts: E0");
        assertEq(gaugeController.n_gauge_types(), 1, "_postGaugeTypeAddAsserts: E1");
        assertEq(gaugeController.getTypeWeight(0), 1000000000000000000, "_postGaugeTypeAddAsserts: E2");
        assertEq(gaugeController.getTotalWeight(), 0, "_postGaugeTypeAddAsserts: E3");
        assertEq(gaugeController.getWeightsSumPerType(0), 0, "_postGaugeTypeAddAsserts: E4");
    }

    function _preGauge1AddAsserts() internal {
        assertEq(gaugeController.n_gauges(), 0, "_preGaugeAddAsserts: E0");
        assertEq(gaugeController.getGaugeWeight(address(scoreGauge1V1)), 0, "_preGaugeAddAsserts: E1");
        assertEq(gaugeController.getTotalWeight(), 0, "_preGaugeAddAsserts: E2");
        assertEq(gaugeController.getWeightsSumPerType(0), 0, "_preGaugeAddAsserts: E3");
        assertEq(gaugeController.gauges(0), address(0), "_preGaugeAddAsserts: E4");
        assertEq(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge1V1), block.timestamp), 0, "_preGaugeAddAsserts: E5");

        int128 _n_gauge_types = gaugeController.n_gauge_types();
        
        bytes4 selector = bytes4(keccak256("NotAdmin()"));
        vm.expectRevert(selector); // "dev: admin only" // todo
        gaugeController.addGauge(address(scoreGauge1V1), _n_gauge_types, 0);

        vm.startPrank(owner);
        vm.expectRevert(); // vm.expectRevert("dev: invalid gauge type");
        gaugeController.addGauge(address(scoreGauge1V1), _n_gauge_types, 0);
        vm.stopPrank();
    }

    function _postGauge1AddAsserts() internal {
        assertEq(gaugeController.n_gauges(), 1, "_postGauge1AddAsserts: E0");
        assertEq(gaugeController.getGaugeWeight(address(scoreGauge1V1)), 1, "_postGauge1AddAsserts: E1");
        assertEq(gaugeController.getTotalWeight(), 1000000000000000000, "_postGauge1AddAsserts: E2");
        assertEq(gaugeController.getWeightsSumPerType(0), 1, "_postGauge1AddAsserts: E3");
        assertEq(gaugeController.gauges(0), address(scoreGauge1V1), "_postGauge1AddAsserts: E4");
        assertEq(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge1V1), block.timestamp), 0, "_postGauge1AddAsserts: E5"); // some time need to pass before this is updated
        assertEq(gaugeController.gaugeRelativeWeight(address(scoreGauge1V1), block.timestamp), 0, "_postGauge1AddAsserts: E6"); // same here

        vm.startPrank(owner);
        vm.expectRevert(); // vm.expectRevert("dev: cannot add the same gauge twice");
        gaugeController.addGauge(address(scoreGauge1V1), 0, 0);
        vm.stopPrank();
    }

    function _preGauge2AddAsserts() internal {
        assertEq(gaugeController.n_gauges(), 1, "_preGauge2AddAsserts: E0");
        assertEq(gaugeController.getGaugeWeight(address(scoreGauge2V1)), 0, "_preGauge2AddAsserts: E1");
        assertEq(gaugeController.getTotalWeight(), 1000000000000000000, "_preGauge2AddAsserts: E2");
        assertEq(gaugeController.getWeightsSumPerType(0), 1, "_preGauge2AddAsserts: E3");
        assertEq(gaugeController.gauges(1), address(0), "_preGauge2AddAsserts: E4");

        int128 _n_gauge_types = gaugeController.n_gauge_types();

        vm.expectRevert(); // vm.expectRevert("dev: admin only");
        gaugeController.addGauge(address(scoreGauge2V1), _n_gauge_types, 0);

        vm.startPrank(owner);
        vm.expectRevert(); // vm.expectRevert("dev: invalid gauge type");
        gaugeController.addGauge(address(scoreGauge1V1), _n_gauge_types, 0);
        vm.stopPrank();
    }

    function _postGauge2AddAsserts() internal {
        assertEq(gaugeController.n_gauges(), 2, "_postGauge2AddAsserts: E0");
        assertEq(gaugeController.getGaugeWeight(address(scoreGauge2V1)), 0, "_postGauge2AddAsserts: E1");
        assertEq(gaugeController.getTotalWeight(), 1000000000000000000, "_postGauge2AddAsserts: E2");
        assertEq(gaugeController.getWeightsSumPerType(0), 1, "_postGauge2AddAsserts: E3");
        assertEq(gaugeController.gauges(1), address(scoreGauge2V1), "_postGauge2AddAsserts: E4");
        assertEq(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge2V1), block.timestamp), 0, "_postGauge2AddAsserts: E5");

        vm.startPrank(owner);
        vm.expectRevert(); // vm.expectRevert("dev: cannot add the same gauge twice");
        gaugeController.addGauge(address(scoreGauge2V1), 0, 0);
        vm.stopPrank();
    }

    function _preGauge2TypeAddAsserts() internal {
        assertEq(gaugeController.gauge_type_names(1), "", "_preGauge2TypeAddAsserts: E0");
        assertEq(gaugeController.n_gauge_types(), 1, "_preGauge2TypeAddAsserts: E1");
        assertEq(gaugeController.getTypeWeight(1), 0, "_preGauge2TypeAddAsserts: E2");
        assertEq(gaugeController.getTotalWeight(), 1000000000000000000, "_preGauge2TypeAddAsserts: E3");
        assertEq(gaugeController.getWeightsSumPerType(1), 0, "_preGauge2TypeAddAsserts: E4");

        vm.expectRevert(); // vm.expectRevert("only admin");
        gaugeController.addType("Optimism", 0);
    }

    function _postGauge2TypeAddAsserts() internal {
        assertEq(gaugeController.gauge_type_names(1), "Optimism", "_postGauge2TypeAddAsserts: E0");
        assertEq(gaugeController.n_gauge_types(), 2, "_postGauge2TypeAddAsserts: E1");
        assertEq(gaugeController.getTypeWeight(1), 1000000000000000000, "_postGauge2TypeAddAsserts: E2");
        assertEq(gaugeController.getTotalWeight(), 1000000000000000000, "_postGauge2TypeAddAsserts: E3");
        assertEq(gaugeController.getWeightsSumPerType(0), 1, "_postGauge2TypeAddAsserts: E4");
    }

    function _preGauge3AddAsserts() internal {
        assertEq(gaugeController.n_gauges(), 2, "_preGaugeAddAsserts: E0");
        assertEq(gaugeController.getGaugeWeight(address(scoreGauge3V1)), 0, "_preGaugeAddAsserts: E1");
        assertEq(gaugeController.getTotalWeight(), 1000000000000000000, "_preGaugeAddAsserts: E2");
        assertEq(gaugeController.getWeightsSumPerType(1), 0, "_preGaugeAddAsserts: E3");
        assertEq(gaugeController.gauges(2), address(0), "_preGaugeAddAsserts: E4");

        int128 _n_gauge_types = gaugeController.n_gauge_types();

        vm.expectRevert(); // vm.expectRevert("dev: admin only");
        gaugeController.addGauge(address(scoreGauge3V1), _n_gauge_types, 0);

        vm.startPrank(owner);
        vm.expectRevert(); // vm.expectRevert("dev: invalid gauge type");
        gaugeController.addGauge(address(scoreGauge3V1), _n_gauge_types, 0);
        vm.stopPrank();
    }

    function _postGauge3AddAsserts() internal {
        assertEq(gaugeController.n_gauges(), 3, "_postGaugeAddAsserts: E0");
        assertEq(gaugeController.getGaugeWeight(address(scoreGauge3V1)), 0, "_postGaugeAddAsserts: E1");
        assertEq(gaugeController.getTotalWeight(), 1000000000000000000, "_postGaugeAddAsserts: E2");
        assertEq(gaugeController.getWeightsSumPerType(1), 0, "_postGaugeAddAsserts: E3");
        assertEq(gaugeController.gauges(2), address(scoreGauge3V1), "_postGaugeAddAsserts: E4");
        assertEq(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge3V1), block.timestamp), 0, "_postGaugeAddAsserts: E5");

        vm.startPrank(owner);
        vm.expectRevert(); // vm.expectRevert("dev: cannot add the same gauge twice");
        gaugeController.addGauge(address(scoreGauge3V1), 0, 0);
        vm.stopPrank();
    }

    function _preInitEpochAsserts() internal {
        vm.expectRevert(); // vm.expectRevert(); // revert with ```Arithmetic over/underflow```
        minterContract.mint(address(scoreGauge1V1));
        vm.expectRevert(); // vm.expectRevert(); // revert with ```Arithmetic over/underflow```
        minterContract.mint(address(scoreGauge2V1));
        vm.expectRevert(); // vm.expectRevert(); // revert with ```Arithmetic over/underflow```
        minterContract.mint(address(scoreGauge3V1));

        vm.startPrank(alice);
        vm.expectRevert(); // vm.expectRevert("Epoch is not set yet");
        gaugeController.voteForGaugeWeights(address(scoreGauge1V1), 10000);
        vm.stopPrank();

        vm.expectRevert(); // vm.expectRevert("Epoch is not set yet");
        gaugeController.advanceEpoch();

        assertEq(gaugeController.epoch(), 0, "_preInitEpochAsserts: E0");
        assertEq(puppetERC20.mintableInTimeframe(block.timestamp, block.timestamp + 1 weeks), 0, "_preInitEpochAsserts: E1"); // must wait _INFLATION_DELAY

        vm.expectRevert(); // vm.expectRevert("admin only");
        gaugeController.initializeEpoch();

        vm.startPrank(owner);
        vm.expectRevert(); // vm.expectRevert("too soon!");
        gaugeController.initializeEpoch(); // must wait _INFLATION_DELAY
        vm.stopPrank();

        (uint256 _startTime, uint256 _endTime) = gaugeController.epochTimeframe(0);
        assertEq(_startTime, 0, "_preInitEpochAsserts: E2");
        assertEq(_endTime, 0, "_preInitEpochAsserts: E3");
    }

    function _postInitEpochAsserts() internal {
        assertEq(gaugeController.epoch(), 1, "_postInitEpochAsserts: E0");
        assertTrue(puppetERC20.mintableInTimeframe(block.timestamp, block.timestamp + 1 weeks) > 0, "_postInitEpochAsserts: E1");
        assertEq(gaugeController.getTotalWeight(), 1000000000000000000, "_postInitEpochAsserts: E2");
        assertEq(gaugeController.getWeightsSumPerType(0), 1, "_postInitEpochAsserts: E3");
        assertEq(gaugeController.currentEpochEndTime(), block.timestamp + 1 weeks, "_postInitEpochAsserts: E4");
        (uint256 _startTime, uint256 _endTime) = gaugeController.epochTimeframe(1);
        assertEq(_startTime, 0, "_postInitEpochAsserts: E5");
        assertEq(_endTime, 0, "_postInitEpochAsserts: E6");

        vm.expectRevert(); // vm.expectRevert("epoch has not ended yet");
        minterContract.mint(address(scoreGauge1V1));

        vm.expectRevert(); // vm.expectRevert("Epoch has not ended yet");
        gaugeController.advanceEpoch();
    }

    function _preVote2ndEpochAsserts() internal {
        assertEq(gaugeController.gaugeRelativeWeightWrite(address(address(scoreGauge1V1)), block.timestamp), 1e18, "_preVote2ndEpochAsserts: E0");
        assertEq(gaugeController.gaugeRelativeWeightWrite(address(address(scoreGauge2V1)), block.timestamp), 0, "_preVote2ndEpochAsserts: E1");
        assertEq(gaugeController.gaugeRelativeWeightWrite(address(address(scoreGauge3V1)), block.timestamp), 0, "_preVote2ndEpochAsserts: E2");
        assertEq(gaugeController.gaugeWeightForEpoch(1, address(address(scoreGauge1V1))), 1e18, "_preVote2ndEpochAsserts: E3");
        assertEq(gaugeController.gaugeWeightForEpoch(1, address(address(scoreGauge2V1))), 0, "_preVote2ndEpochAsserts: E4");
        assertEq(gaugeController.gaugeWeightForEpoch(1, address(address(scoreGauge3V1))), 0, "_preVote2ndEpochAsserts: E5");
        assertEq(gaugeController.gaugeWeightForEpoch(2, address(address(scoreGauge1V1))), 0, "_preVote2ndEpochAsserts: E6");
        assertEq(gaugeController.gaugeWeightForEpoch(2, address(address(scoreGauge2V1))), 0, "_preVote2ndEpochAsserts: E7");
        assertEq(gaugeController.gaugeWeightForEpoch(2, address(address(scoreGauge3V1))), 0, "_preVote2ndEpochAsserts: E8");
        assertEq(gaugeController.gaugeWeightForEpoch(3, address(address(scoreGauge1V1))), 0, "_preVote2ndEpochAsserts: E9");
        assertEq(gaugeController.gaugeWeightForEpoch(3, address(address(scoreGauge2V1))), 0, "_preVote2ndEpochAsserts: E10");
        assertEq(gaugeController.gaugeWeightForEpoch(3, address(address(scoreGauge3V1))), 0, "_preVote2ndEpochAsserts: E11");
        assertTrue(gaugeController.getTotalWeight() > 0, "_preVote2ndEpochAsserts: E12");
    }

    function _preAdvanceEpochAsserts() internal {
        assertEq(gaugeController.gaugeRelativeWeight(address(scoreGauge1V1), block.timestamp), 0, "_preAdvanceEpochAsserts: E0");
        assertEq(gaugeController.gaugeRelativeWeight(address(scoreGauge2V1), block.timestamp), 0, "_preAdvanceEpochAsserts: E1");
        assertEq(gaugeController.gaugeRelativeWeight(address(scoreGauge3V1), block.timestamp), 0, "_preAdvanceEpochAsserts: E2");
        assertEq(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge1V1), block.timestamp), 1e18, "_preAdvanceEpochAsserts: E3");
        assertEq(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge2V1), block.timestamp), 0, "_preAdvanceEpochAsserts: E4");
        assertEq(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge3V1), block.timestamp), 0, "_preAdvanceEpochAsserts: E5");
    }

    function _postAdvanceEpochAsserts() internal {
        assertEq(gaugeController.epoch(), 2, "_postAdvanceEpochAsserts: E0");
        (uint256 _start, uint256 _end) = gaugeController.epochTimeframe(1);
        assertEq(_end, block.timestamp, "_postAdvanceEpochAsserts: E1");
        assertEq(_start, block.timestamp - 1 weeks, "_postAdvanceEpochAsserts: E2");
        assertEq(gaugeController.gaugeWeightForEpoch(1, address(scoreGauge1V1)), 1e18, "_postAdvanceEpochAsserts: E3");
        assertEq(gaugeController.gaugeWeightForEpoch(1, address(scoreGauge2V1)), 0, "_postAdvanceEpochAsserts: E4");
        assertEq(gaugeController.gaugeWeightForEpoch(1, address(scoreGauge3V1)), 0, "_postAdvanceEpochAsserts: E5");
        assertTrue(gaugeController.hasEpochEnded(1), "_postAdvanceEpochAsserts: E6");
        assertTrue(!gaugeController.hasEpochEnded(2), "_postAdvanceEpochAsserts: E7");

        assertTrue(puppetERC20.mintableInTimeframe(_start, _end) > 20000 * 1e18, "_postAdvanceEpochAsserts: E9");

        assertEq(gaugeController.gaugeRelativeWeight(address(scoreGauge1V1), block.timestamp), 1e18, "_postAdvanceEpochAsserts: E10");
        assertEq(gaugeController.gaugeRelativeWeight(address(scoreGauge2V1), block.timestamp), 0, "_postAdvanceEpochAsserts: E11");
        assertEq(gaugeController.gaugeRelativeWeight(address(scoreGauge3V1), block.timestamp), 0, "_postAdvanceEpochAsserts: E12");
    }

    function _postMintRewardsAsserts() internal {
        (uint256 _start, uint256 _end) = gaugeController.epochTimeframe(1);
        uint256 _totalMintable = puppetERC20.mintableInTimeframe(_start, _end);
        assertEq(IERC20(address(puppetERC20)).balanceOf(address(scoreGauge1V1)), _totalMintable, "_postMintRewardsAsserts: E0");
        assertEq(IERC20(address(puppetERC20)).balanceOf(address(scoreGauge2V1)), 0, "_postMintRewardsAsserts: E1");
        assertEq(IERC20(address(puppetERC20)).balanceOf(address(scoreGauge3V1)), 0, "_postMintRewardsAsserts: E2");

        vm.expectRevert(); // vm.expectRevert("already minted for this epoch");
        minterContract.mint(address(scoreGauge1V1));
    }

    function _userVote2ndEpoch(address _user) internal {
        vm.startPrank(_user);
        gaugeController.voteForGaugeWeights(address(scoreGauge2V1), 10000);

        vm.expectRevert(); // vm.expectRevert("Already voted for this epoch");
        gaugeController.voteForGaugeWeights(address(scoreGauge2V1), 10000);

        vm.expectRevert(); // vm.expectRevert("Used too much power");
        gaugeController.voteForGaugeWeights(address(scoreGauge1V1), 1);

        vm.stopPrank();

        assertEq(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge1V1), block.timestamp), 1e18, "_userVote2ndEpoch: E0");
        assertEq(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge2V1), block.timestamp), 0, "_userVote2ndEpoch: E1");
        assertEq(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge3V1), block.timestamp), 0, "_userVote2ndEpoch: E2");
        assertEq(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge1V1), block.timestamp + 1 weeks), 0, "_userVote2ndEpoch: E3");
        assertApproxEqAbs(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge2V1), block.timestamp + 1 weeks), 1e18, 1e5, "_userVote2ndEpoch: E4");
        assertEq(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge3V1), block.timestamp + 1 weeks), 0, "_userVote2ndEpoch: E5");
    }

    function _pre2ndEpochEndAsserts() internal {
        assertEq(gaugeController.gaugeRelativeWeight(address(scoreGauge1V1), block.timestamp), 0, "_pre2ndEpochEndAsserts: E0");
        assertApproxEqAbs(gaugeController.gaugeRelativeWeight(address(scoreGauge2V1), block.timestamp), 1e18, 1e5, "_pre2ndEpochEndAsserts: E1");
        assertEq(gaugeController.gaugeRelativeWeight(address(scoreGauge3V1), block.timestamp), 0, "_pre2ndEpochEndAsserts: E2");

        assertEq(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge1V1), block.timestamp), 0, "_pre2ndEpochEndAsserts: E3");
        assertApproxEqAbs(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge2V1), block.timestamp), 1e18, 1e5, "_pre2ndEpochEndAsserts: E4");
        assertEq(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge3V1), block.timestamp), 0, "_pre2ndEpochEndAsserts: E5");
    }

    function _post2ndEpochEndAsserts() internal {
        assertEq(gaugeController.epoch(), 3, "_post2ndEpochEndAsserts: E0");
        (uint256 _start, uint256 _end) = gaugeController.epochTimeframe(2);
        assertEq(_end, block.timestamp, "_post2ndEpochEndAsserts: E1");
        assertEq(_start, block.timestamp - 1 weeks, "_post2ndEpochEndAsserts: E2");
        assertEq(gaugeController.gaugeWeightForEpoch(2, address(scoreGauge1V1)), 0, "_post2ndEpochEndAsserts: E3");
        assertApproxEqAbs(gaugeController.gaugeWeightForEpoch(2, address(scoreGauge2V1)), 1e18, 1e5, "_post2ndEpochEndAsserts: E4");
        assertEq(gaugeController.gaugeWeightForEpoch(2, address(scoreGauge3V1)), 0, "_post2ndEpochEndAsserts: E5");
        assertTrue(gaugeController.hasEpochEnded(1), "_post2ndEpochEndAsserts: E6");
        assertTrue(gaugeController.hasEpochEnded(2), "_post2ndEpochEndAsserts: E7");
        assertTrue(!gaugeController.hasEpochEnded(3), "_post2ndEpochEndAsserts: E71");

        assertTrue(puppetERC20.mintableInTimeframe(_start, _end) > 20000 * 1e18, "_post2ndEpochEndAsserts: E9");

        assertEq(gaugeController.gaugeRelativeWeight(address(scoreGauge1V1), block.timestamp), 0, "_post2ndEpochEndAsserts: E10");
        assertApproxEqAbs(gaugeController.gaugeRelativeWeight(address(scoreGauge2V1), block.timestamp), 1e18, 1e5, "_post2ndEpochEndAsserts: E11");
        assertEq(gaugeController.gaugeRelativeWeight(address(scoreGauge3V1), block.timestamp), 0, "_post2ndEpochEndAsserts: E12");
    }

    function _postMintFor2ndEpochRewardsAsserts(uint256 _gauge1BalanceBefore) internal {
        (uint256 _start, uint256 _end) = gaugeController.epochTimeframe(2);
        uint256 _totalMintable = puppetERC20.mintableInTimeframe(_start, _end);
        assertEq(IERC20(address(puppetERC20)).balanceOf(address(scoreGauge1V1)), _gauge1BalanceBefore, "_postMintFor2ndEpochRewardsAsserts: E0");
        assertApproxEqAbs(IERC20(address(puppetERC20)).balanceOf(address(scoreGauge2V1)), _totalMintable, 1e5, "_postMintFor2ndEpochRewardsAsserts: E1");
        assertEq(IERC20(address(puppetERC20)).balanceOf(address(scoreGauge3V1)), 0, "_postMintFor2ndEpochRewardsAsserts: E2");

        vm.expectRevert(); // vm.expectRevert("already minted for this epoch");
        minterContract.mint(address(scoreGauge2V1));
    }

    function _userVote3rdEpoch(address _user) internal {
        vm.startPrank(_user);
        gaugeController.voteForGaugeWeights(address(scoreGauge2V1), 5000);
        gaugeController.voteForGaugeWeights(address(scoreGauge1V1), 5000);

        vm.expectRevert(); // vm.expectRevert("Already voted for this epoch");
        gaugeController.voteForGaugeWeights(address(scoreGauge1V1), 10000);

        vm.expectRevert(); // vm.expectRevert("Already voted for this epoch");
        gaugeController.voteForGaugeWeights(address(scoreGauge2V1), 10000);

        vm.expectRevert(); // vm.expectRevert("Used too much power");
        gaugeController.voteForGaugeWeights(address(scoreGauge3V1), 1);

        vm.stopPrank();

        assertEq(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge1V1), block.timestamp), 0, "_userVote3rdEpoch: E0");
        assertApproxEqAbs(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge2V1), block.timestamp), 1e18, 1e5, "_userVote3rdEpoch: E1");
        assertEq(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge3V1), block.timestamp), 0, "_userVote3rdEpoch: E2");
    }

    function _postVote3rdEpochAsserts() internal {
        assertApproxEqAbs(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge1V1), block.timestamp + 1 weeks), 1e18 / 2, 1e5, "_postVote3rdEpochAsserts: E0");
        assertApproxEqAbs(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge2V1), block.timestamp + 1 weeks), 1e18 / 2, 1e5, "_postVote3rdEpochAsserts: E1");
        assertEq(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge3V1), block.timestamp + 1 weeks), 0, "_postVote3rdEpochAsserts: E2");
    }

    function _pre3rdEpochEndAsserts() internal {
        assertApproxEqAbs(gaugeController.gaugeRelativeWeight(address(scoreGauge1V1), block.timestamp), 1e18 / 2, 1e5, "_pre3rdEpochEndAsserts: E0");
        assertApproxEqAbs(gaugeController.gaugeRelativeWeight(address(scoreGauge2V1), block.timestamp), 1e18 / 2, 1e5, "_pre3rdEpochEndAsserts: E1");
        assertEq(gaugeController.gaugeRelativeWeight(address(scoreGauge3V1), block.timestamp), 0, "_pre3rdEpochEndAsserts: E2");

        assertApproxEqAbs(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge1V1), block.timestamp), 1e18 / 2, 1e5, "_pre3rdEpochEndAsserts: E3");
        assertApproxEqAbs(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge2V1), block.timestamp), 1e18 / 2, 1e5, "_pre3rdEpochEndAsserts: E4");
        assertEq(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge3V1), block.timestamp), 0, "_pre3rdEpochEndAsserts: E5");
        assertTrue(gaugeController.getTypeWeight(0) > 0, "_pre3rdEpochEndAsserts: E6");
        assertEq(gaugeController.getTypeWeight(1), 1000000000000000000, "_pre3rdEpochEndAsserts: E7");
    }

    function _post3rdEpochEndAsserts() internal {
        assertEq(gaugeController.epoch(), 4, "_post3rdEpochEndAsserts: E0");
        (uint256 _start, uint256 _end) = gaugeController.epochTimeframe(3);
        assertEq(_end, block.timestamp, "_post3rdEpochEndAsserts: E1");
        assertEq(_start, block.timestamp - 1 weeks, "_post3rdEpochEndAsserts: E2");
        assertApproxEqAbs(gaugeController.gaugeWeightForEpoch(3, address(scoreGauge1V1)), 1e18 / 2, 1e5, "_post3rdEpochEndAsserts: E3");
        assertApproxEqAbs(gaugeController.gaugeWeightForEpoch(3, address(scoreGauge2V1)), 1e18 / 2, 1e5, "_post3rdEpochEndAsserts: E4");
        assertEq(gaugeController.gaugeWeightForEpoch(3, address(scoreGauge3V1)), 0, "_post3rdEpochEndAsserts: E5");
        assertTrue(gaugeController.hasEpochEnded(1), "_post3rdEpochEndAsserts: E6");
        assertTrue(gaugeController.hasEpochEnded(2), "_post3rdEpochEndAsserts: E7");
        assertTrue(gaugeController.hasEpochEnded(3), "_post3rdEpochEndAsserts: E8");
        assertTrue(!gaugeController.hasEpochEnded(4), "_post3rdEpochEndAsserts: E9");

        assertTrue(puppetERC20.mintableInTimeframe(_start, _end) > 20000 * 1e18, "_post3rdEpochEndAsserts: E10");

        assertApproxEqAbs(gaugeController.gaugeRelativeWeight(address(scoreGauge1V1), block.timestamp), 1e18 / 2, 1e5, "_post3rdEpochEndAsserts: E11");
        assertApproxEqAbs(gaugeController.gaugeRelativeWeight(address(scoreGauge2V1), block.timestamp), 1e18 / 2, 1e5, "_post3rdEpochEndAsserts: E12");
        assertEq(gaugeController.gaugeRelativeWeight(address(scoreGauge3V1), block.timestamp), 0, "_post3rdEpochEndAsserts: E13");
        assertTrue(gaugeController.getTypeWeight(0) > 0, "_post3rdEpochEndAsserts: E14");
        assertEq(gaugeController.getTypeWeight(1), 1e18, "_post3rdEpochEndAsserts: E15");
    }

    function _postMintFor3rdEpochRewardsAsserts(uint256 _gauge1BalanceBefore, uint256 _gauge2BalanceBefore) internal {
        (uint256 _start, uint256 _end) = gaugeController.epochTimeframe(3);
        uint256 _totalMintable = puppetERC20.mintableInTimeframe(_start, _end);
        assertApproxEqAbs(IERC20(address(puppetERC20)).balanceOf(address(scoreGauge1V1)), _gauge1BalanceBefore + (_totalMintable / 2), 1e5, "_postMintFor3rdEpochRewardsAsserts: E0");
        assertApproxEqAbs(IERC20(address(puppetERC20)).balanceOf(address(scoreGauge2V1)), _gauge2BalanceBefore + (_totalMintable / 2), 1e5, "_postMintFor3rdEpochRewardsAsserts: E1");
        assertEq(IERC20(address(puppetERC20)).balanceOf(address(scoreGauge3V1)), 0, "_postMintFor3rdEpochRewardsAsserts: E2");

        vm.expectRevert(); // vm.expectRevert("already minted for this epoch");
        minterContract.mint(address(scoreGauge1V1));

        vm.expectRevert(); // vm.expectRevert("already minted for this epoch");
        minterContract.mint(address(scoreGauge2V1));
    }

    function _userVote4thEpoch(address _user) internal {
        vm.startPrank(_user);
        gaugeController.voteForGaugeWeights(address(scoreGauge2V1), 0);
        gaugeController.voteForGaugeWeights(address(scoreGauge1V1), 0);
        gaugeController.voteForGaugeWeights(address(scoreGauge3V1), 10000);

        vm.expectRevert(); // vm.expectRevert("Already voted for this epoch");
        gaugeController.voteForGaugeWeights(address(scoreGauge1V1), 10000);

        vm.expectRevert(); // vm.expectRevert("Already voted for this epoch");
        gaugeController.voteForGaugeWeights(address(scoreGauge2V1), 10000);

        vm.expectRevert(); // vm.expectRevert("Already voted for this epoch");
        gaugeController.voteForGaugeWeights(address(scoreGauge3V1), 10000);

        vm.stopPrank();

        assertApproxEqAbs(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge1V1), block.timestamp), 1e18 / 2, 1e5, "_userVote4thEpoch: E0");
        assertApproxEqAbs(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge2V1), block.timestamp), 1e18 / 2, 1e5, "_userVote4thEpoch: E1");
        assertEq(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge3V1), block.timestamp), 0, "_userVote4thEpoch: E2");
    }

    function _postVote4thEpochAsserts() internal {
        assertEq(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge1V1), block.timestamp + 1 weeks), 0, "_postVote4thEpochAsserts: E0");
        assertEq(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge2V1), block.timestamp + 1 weeks), 0, "_postVote4thEpochAsserts: E1");
        assertApproxEqAbs(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge3V1), block.timestamp + 1 weeks), 1e18, 1e5, "_postVote4thEpochAsserts: E2");
        assertEq(gaugeController.getTypeWeight(0), 1e18, "_postVote4thEpochAsserts: E3");
        assertEq(gaugeController.getTypeWeight(1), 1e18, "_postVote4thEpochAsserts: E4");
    }

    function _pre4thEpochEndAsserts() internal {
        assertEq(gaugeController.gaugeRelativeWeight(address(scoreGauge1V1), block.timestamp), 0, "_pre4thEpochEndAsserts: E0");
        assertEq(gaugeController.gaugeRelativeWeight(address(scoreGauge2V1), block.timestamp), 0, "_pre4thEpochEndAsserts: E1");
        assertApproxEqAbs(gaugeController.gaugeRelativeWeight(address(scoreGauge3V1), block.timestamp), 1e18, 1e5, "_pre4thEpochEndAsserts: E2");

        assertEq(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge1V1), block.timestamp), 0, "_pre4thEpochEndAsserts: E3");
        assertEq(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge2V1), block.timestamp), 0, "_pre4thEpochEndAsserts: E4");
        assertApproxEqAbs(gaugeController.gaugeRelativeWeightWrite(address(scoreGauge3V1), block.timestamp), 1e18, 1e5, "_pre4thEpochEndAsserts: E5");
        assertEq(gaugeController.getTypeWeight(0), 1e18, "_pre4thEpochEndAsserts: E6");
        assertEq(gaugeController.getTypeWeight(1), 1e18, "_pre4thEpochEndAsserts: E7");
    }

    function _post4thEpochEndAsserts() internal {
        assertEq(gaugeController.epoch(), 5, "_post4thEpochEndAsserts: E0");
        (uint256 _start, uint256 _end) = gaugeController.epochTimeframe(4);
        assertEq(_end, block.timestamp, "_post4thEpochEndAsserts: E1");
        assertEq(_start, block.timestamp - 1 weeks, "_post4thEpochEndAsserts: E2");
        assertEq(gaugeController.gaugeWeightForEpoch(4, address(scoreGauge1V1)), 0, "_post4thEpochEndAsserts: E3");
        assertEq(gaugeController.gaugeWeightForEpoch(4, address(scoreGauge2V1)), 0, "_post4thEpochEndAsserts: E4");
        assertApproxEqAbs(gaugeController.gaugeWeightForEpoch(4, address(scoreGauge3V1)), 1e18, 1e5, "_post4thEpochEndAsserts: E5");
        assertTrue(gaugeController.hasEpochEnded(1), "_post4thEpochEndAsserts: E6");
        assertTrue(gaugeController.hasEpochEnded(2), "_post4thEpochEndAsserts: E7");
        assertTrue(gaugeController.hasEpochEnded(3), "_post4thEpochEndAsserts: E8");
        assertTrue(gaugeController.hasEpochEnded(4), "_post4thEpochEndAsserts: E9");
        assertTrue(!gaugeController.hasEpochEnded(5), "_post4thEpochEndAsserts: E9");

        assertTrue(puppetERC20.mintableInTimeframe(_start, _end) > 20000 * 1e18, "_post4thEpochEndAsserts: E10");

        assertEq(gaugeController.gaugeRelativeWeight(address(scoreGauge1V1), block.timestamp), 0, "_post4thEpochEndAsserts: E11");
        assertEq(gaugeController.gaugeRelativeWeight(address(scoreGauge2V1), block.timestamp), 0, "_post4thEpochEndAsserts: E12");
        assertApproxEqAbs(gaugeController.gaugeRelativeWeight(address(scoreGauge3V1), block.timestamp), 1e18, 1e5, "_post4thEpochEndAsserts: E13");
        assertEq(gaugeController.getTypeWeight(0), 1e18, "_post4thEpochEndAsserts: E14");
        assertEq(gaugeController.getTypeWeight(1), 1e18, "_post4thEpochEndAsserts: E15");
    }
}