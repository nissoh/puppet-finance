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

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract testGaugeControllerAndMinter is Test, DeployerUtilities {

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public yossi = makeAddr("yossi");
    address public minter = makeAddr("minter");
    address public gauge1 = makeAddr("gauge1");
    address public gauge2 = makeAddr("gauge2");
    address public gauge3 = makeAddr("gauge3");

    Puppet public puppetERC20;
    Minter public minterContract;
    VotingEscrow public votingEscrow;
    GaugeController public gaugeController;

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

        gaugeController = new GaugeController(address(puppetERC20), address(votingEscrow));

        minterContract = new Minter(address(puppetERC20), address(gaugeController));
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
        gaugeController.add_type("Arbitrum", 0);
        vm.stopPrank();
        _postGaugeTypeAddAsserts();

        // ADD GAUGE1
        _preGauge1AddAsserts();
        vm.startPrank(owner);
        gaugeController.add_gauge(gauge1, 0, 0);
        vm.stopPrank();
        _postGauge1AddAsserts();

        // ADD GAUGE2
        _preGauge2AddAsserts();
        vm.startPrank(owner);
        gaugeController.add_gauge(gauge2, 0, 0);
        vm.stopPrank();
        _postGauge2AddAsserts();

        // ADD GAUGE TYPE2
        _preGauge2TypeAddAsserts();
        vm.startPrank(owner);
        gaugeController.add_type("Optimism", 0);
        vm.stopPrank();
        _postGauge2TypeAddAsserts();

        // ADD GAUGE3
        _preGauge3AddAsserts();
        vm.startPrank(owner);
        gaugeController.add_gauge(gauge3, 1, 0);
        vm.stopPrank();
        _postGauge3AddAsserts();

        // INIT EPOCH
        _preInitEpochAsserts();
        // todo
    }

    function _preInitEpochAsserts() internal {
        vm.expectRevert(); // revert with ```Arithmetic over/underflow```
        minterContract.mint(gauge1);
        vm.expectRevert(); // revert with ```Arithmetic over/underflow```
        minterContract.mint(gauge2);
        vm.expectRevert(); // revert with ```Arithmetic over/underflow```
        minterContract.mint(gauge3);

        vm.startPrank(alice);
        vm.expectRevert("Epoch is not set yet");
        gaugeController.vote_for_gauge_weights(gauge1, 10000);
        vm.stopPrank();

        vm.expectRevert("Epoch is not set yet");
        gaugeController.advanceEpoch();

        assertEq(gaugeController.epoch(), 0, "_preInitEpochAsserts: E0");
    }

    // =======================================================
    // Internal Helper Functions
    // =======================================================

    function _preGaugeTypeAddAsserts() internal {
        assertEq(gaugeController.gauge_type_names(0), "", "_preGaugeTypeAddAsserts: E0");
        assertEq(gaugeController.n_gauge_types(), 0, "_preGaugeTypeAddAsserts: E1");
        assertEq(gaugeController.get_type_weight(0), 0, "_preGaugeTypeAddAsserts: E2");
        assertEq(gaugeController.get_total_weight(), 0, "_preGaugeTypeAddAsserts: E3");
        assertEq(gaugeController.get_weights_sum_per_type(0), 0, "_preGaugeTypeAddAsserts: E4");

        vm.expectRevert("only admin");
        gaugeController.add_type("Arbitrum", 0);
    }

    function _postGaugeTypeAddAsserts() internal {
        assertEq(gaugeController.gauge_type_names(0), "Arbitrum", "_postGaugeTypeAddAsserts: E0");
        assertEq(gaugeController.n_gauge_types(), 1, "_postGaugeTypeAddAsserts: E1");
        assertEq(gaugeController.get_type_weight(0), 0, "_postGaugeTypeAddAsserts: E2");
        assertEq(gaugeController.get_total_weight(), 0, "_postGaugeTypeAddAsserts: E3");
        assertEq(gaugeController.get_weights_sum_per_type(0), 0, "_postGaugeTypeAddAsserts: E4");
    }

    function _preGauge1AddAsserts() internal {
        assertEq(gaugeController.n_gauges(), 0, "_preGaugeAddAsserts: E0");
        assertEq(gaugeController.get_gauge_weight(gauge1), 0, "_preGaugeAddAsserts: E1");
        assertEq(gaugeController.get_total_weight(), 0, "_preGaugeAddAsserts: E2");
        assertEq(gaugeController.get_weights_sum_per_type(0), 0, "_preGaugeAddAsserts: E3");
        assertEq(gaugeController.gauges(0), address(0), "_preGaugeAddAsserts: E4");

        int128 _n_gauge_types = gaugeController.n_gauge_types();

        vm.expectRevert("dev: admin only");
        gaugeController.add_gauge(gauge1, _n_gauge_types, 0);

        vm.startPrank(owner);
        vm.expectRevert("dev: invalid gauge type");
        gaugeController.add_gauge(gauge1, _n_gauge_types, 0);
        vm.stopPrank();
    }

    function _postGauge1AddAsserts() internal {
        assertEq(gaugeController.n_gauges(), 1, "_postGauge1AddAsserts: E0");
        assertEq(gaugeController.get_gauge_weight(gauge1), 0, "_postGauge1AddAsserts: E1");
        assertEq(gaugeController.get_total_weight(), 0, "_postGauge1AddAsserts: E2");
        assertEq(gaugeController.get_weights_sum_per_type(0), 0, "_postGauge1AddAsserts: E3");
        assertEq(gaugeController.gauges(0), gauge1, "_postGauge1AddAsserts: E4");
        assertEq(gaugeController.gauge_relative_weight_write(gauge1, block.timestamp), 0, "_postGauge1AddAsserts: E5");

        vm.startPrank(owner);
        vm.expectRevert("dev: cannot add the same gauge twice");
        gaugeController.add_gauge(gauge1, 0, 0);
        vm.stopPrank();
    }

    function _preGauge2AddAsserts() internal {
        assertEq(gaugeController.n_gauges(), 1, "_preGauge2AddAsserts: E0");
        assertEq(gaugeController.get_gauge_weight(gauge2), 0, "_preGauge2AddAsserts: E1");
        assertEq(gaugeController.get_total_weight(), 0, "_preGauge2AddAsserts: E2");
        assertEq(gaugeController.get_weights_sum_per_type(0), 0, "_preGauge2AddAsserts: E3");
        assertEq(gaugeController.gauges(1), address(0), "_preGauge2AddAsserts: E4");

        int128 _n_gauge_types = gaugeController.n_gauge_types();

        vm.expectRevert("dev: admin only");
        gaugeController.add_gauge(gauge2, _n_gauge_types, 0);

        vm.startPrank(owner);
        vm.expectRevert("dev: invalid gauge type");
        gaugeController.add_gauge(gauge1, _n_gauge_types, 0);
        vm.stopPrank();
    }

    function _postGauge2AddAsserts() internal {
        assertEq(gaugeController.n_gauges(), 2, "_postGauge2AddAsserts: E0");
        assertEq(gaugeController.get_gauge_weight(gauge2), 0, "_postGauge2AddAsserts: E1");
        assertEq(gaugeController.get_total_weight(), 0, "_postGauge2AddAsserts: E2");
        assertEq(gaugeController.get_weights_sum_per_type(0), 0, "_postGauge2AddAsserts: E3");
        assertEq(gaugeController.gauges(1), gauge2, "_postGauge2AddAsserts: E4");
        assertEq(gaugeController.gauge_relative_weight_write(gauge2, block.timestamp), 0, "_postGauge2AddAsserts: E5");

        vm.startPrank(owner);
        vm.expectRevert("dev: cannot add the same gauge twice");
        gaugeController.add_gauge(gauge2, 0, 0);
        vm.stopPrank();
    }

    function _preGauge2TypeAddAsserts() internal {
        assertEq(gaugeController.gauge_type_names(1), "", "_preGauge2TypeAddAsserts: E0");
        assertEq(gaugeController.n_gauge_types(), 1, "_preGauge2TypeAddAsserts: E1");
        assertEq(gaugeController.get_type_weight(1), 0, "_preGauge2TypeAddAsserts: E2");
        assertEq(gaugeController.get_total_weight(), 0, "_preGauge2TypeAddAsserts: E3");
        assertEq(gaugeController.get_weights_sum_per_type(1), 0, "_preGauge2TypeAddAsserts: E4");

        vm.expectRevert("only admin");
        gaugeController.add_type("Optimism", 0);
    }

    function _postGauge2TypeAddAsserts() internal {
        assertEq(gaugeController.gauge_type_names(1), "Optimism", "_postGauge2TypeAddAsserts: E0");
        assertEq(gaugeController.n_gauge_types(), 2, "_postGauge2TypeAddAsserts: E1");
        assertEq(gaugeController.get_type_weight(0), 0, "_postGauge2TypeAddAsserts: E2");
        assertEq(gaugeController.get_total_weight(), 0, "_postGauge2TypeAddAsserts: E3");
        assertEq(gaugeController.get_weights_sum_per_type(0), 0, "_postGauge2TypeAddAsserts: E4");
    }

    function _preGauge3AddAsserts() internal {
        assertEq(gaugeController.n_gauges(), 2, "_preGaugeAddAsserts: E0");
        assertEq(gaugeController.get_gauge_weight(gauge3), 0, "_preGaugeAddAsserts: E1");
        assertEq(gaugeController.get_total_weight(), 0, "_preGaugeAddAsserts: E2");
        assertEq(gaugeController.get_weights_sum_per_type(1), 0, "_preGaugeAddAsserts: E3");
        assertEq(gaugeController.gauges(2), address(0), "_preGaugeAddAsserts: E4");

        int128 _n_gauge_types = gaugeController.n_gauge_types();

        vm.expectRevert("dev: admin only");
        gaugeController.add_gauge(gauge3, _n_gauge_types, 0);

        vm.startPrank(owner);
        vm.expectRevert("dev: invalid gauge type");
        gaugeController.add_gauge(gauge3, _n_gauge_types, 0);
        vm.stopPrank();
    }

    function _postGauge3AddAsserts() internal {
        assertEq(gaugeController.n_gauges(), 3, "_postGaugeAddAsserts: E0");
        assertEq(gaugeController.get_gauge_weight(gauge3), 0, "_postGaugeAddAsserts: E1");
        assertEq(gaugeController.get_total_weight(), 0, "_postGaugeAddAsserts: E2");
        assertEq(gaugeController.get_weights_sum_per_type(1), 0, "_postGaugeAddAsserts: E3");
        assertEq(gaugeController.gauges(2), gauge3, "_postGaugeAddAsserts: E4");
        assertEq(gaugeController.gauge_relative_weight_write(gauge3, block.timestamp), 0, "_postGaugeAddAsserts: E5");

        vm.startPrank(owner);
        vm.expectRevert("dev: cannot add the same gauge twice");
        gaugeController.add_gauge(gauge3, 0, 0);
        vm.stopPrank();
    }
}