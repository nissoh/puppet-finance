// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {DeployerUtilities} from "script/utilities/DeployerUtilities.sol";

import {Puppet} from "src/token/Puppet.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract testPuppetERC20 is Test, DeployerUtilities {

    using SafeERC20 for IERC20;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public yossi = makeAddr("yossi");

    Puppet public puppetERC20;

    function setUp() public {

        uint256 arbitrumFork = vm.createFork(vm.envString("ARBITRUM_RPC_URL"));
        vm.selectFork(arbitrumFork);

        vm.deal(owner, 100 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(yossi, 100 ether);

        vm.startPrank(owner);
        puppetERC20 = new Puppet("Puppet Finance Token", "PUPPET", 18);
        vm.stopPrank();
    }

    function testSanity() public {
        assertTrue(true);
    }

    function testParamsOnDeployment() public {
        assertEq(puppetERC20.name(), "Puppet Finance Token", "testParamsOnDeployment: E0");
        assertEq(puppetERC20.symbol(), "PUPPET", "testParamsOnDeployment: E1");
        assertEq(puppetERC20.decimals(), 18, "testParamsOnDeployment: E2");
        assertEq(puppetERC20.totalSupply(), 3000000 * 1e18, "testParamsOnDeployment: E3");
        assertEq(puppetERC20.start_epoch_supply(), 3000000 * 1e18, "testParamsOnDeployment: E4");
        assertEq(puppetERC20.balanceOf(owner), 3000000 * 1e18, "testParamsOnDeployment: E5");
        assertEq(puppetERC20.available_supply(), 3000000 * 1e18, "testParamsOnDeployment: E6");
    }

    function testParamsOnFinishedEpochs() public {

        skip(86400); // skip INFLATION_DELAY

        _testParamsOnEpochs1To10();
    }

    function _testParamsOnEpochs1To10() internal {
        // First Epoch
        puppetERC20.update_mining_parameters(); // start 1st epoch

        uint256 _mintableForFirstEpoch = puppetERC20.mintable_in_timeframe(puppetERC20.start_epoch_time(), puppetERC20.start_epoch_time() + (86400 * 365));

        assertApproxEqAbs(_mintableForFirstEpoch, 1330000 * 1e18, 1e20, "testParamsOnDeployment: E7"); // make sure ~1.3m tokens will be emitted in 1st year

        skip(86400 * 365 / 2); // skip half of 1st epoch (year)
        assertEq(puppetERC20.available_supply(), puppetERC20.totalSupply() + (_mintableForFirstEpoch / 2), "testParamsOnDeployment: E8");

        vm.expectRevert(); // reverts with ```too soon!```
        puppetERC20.update_mining_parameters();

        skip(86400 * 365 / 2); // skip 2nd half of 1st epoch (year)
        assertEq(puppetERC20.available_supply(), puppetERC20.totalSupply() + (_mintableForFirstEpoch), "testParamsOnDeployment: E8");

        // _testMint(); // todo

        uint256 _mintedLastEpoch = _mintableForFirstEpoch;
        for (uint256 i = 0; i < 49; i++) {
            puppetERC20.update_mining_parameters(); // start Epoch

            uint256 _mintableForEpoch = puppetERC20.mintable_in_timeframe(puppetERC20.start_epoch_time(), puppetERC20.start_epoch_time() + (86400 * 365));

             // make sure inflation is decreasing by 14% each year
            assertEq(_mintableForEpoch, _mintedLastEpoch - (_mintedLastEpoch * 14 / 100), "testParamsOnDeployment: E8");

            skip(86400 * 365); // skip the entire epoch (year)
            _mintedLastEpoch = _mintableForEpoch;
        }
        console.log("puppetERC20.available_supply(): ", puppetERC20.available_supply());
        10,069,644 528221868348528000
        
    }
}