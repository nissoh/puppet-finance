// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {DeployerUtilities} from "script/utilities/DeployerUtilities.sol";

import {Puppet} from "src/token/Puppet.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract testPuppetERC20 is Test, DeployerUtilities {

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public minter = makeAddr("minter");

    Puppet public puppetERC20;

    function setUp() public {

        uint256 arbitrumFork = vm.createFork(vm.envString("ARBITRUM_RPC_URL"));
        vm.selectFork(arbitrumFork);

        vm.deal(owner, 100 ether);
        vm.deal(minter, 100 ether);

        vm.startPrank(owner);
        puppetERC20 = new Puppet("Puppet Finance Token", "PUPPET", 18);
        
        puppetERC20.setMinter(minter);
        vm.stopPrank();
    }

    function testParamsOnDeployment() public {
        assertEq(puppetERC20.name(), "Puppet Finance Token", "testParamsOnDeployment: E0");
        assertEq(puppetERC20.symbol(), "PUPPET", "testParamsOnDeployment: E1");
        assertEq(puppetERC20.decimals(), 18, "testParamsOnDeployment: E2");
        assertEq(puppetERC20.totalSupply(), 3000000 * 1e18, "testParamsOnDeployment: E3");
        assertEq(puppetERC20.startEpochSupply(), 3000000 * 1e18, "testParamsOnDeployment: E4");
        assertEq(puppetERC20.balanceOf(owner), 3000000 * 1e18, "testParamsOnDeployment: E5");
        assertEq(puppetERC20.availableSupply(), 3000000 * 1e18, "testParamsOnDeployment: E6");
    }

    function testParamsOnFinishedEpochs() public {

        skip(86400); // skip INFLATION_DELAY (1 day)

        // First Epoch
        puppetERC20.updateMiningParameters(); // start 1st epoch

        uint256 _mintableForFirstEpoch = puppetERC20.mintableInTimeframe(puppetERC20.startEpochTime(), puppetERC20.startEpochTime() + (86400 * 365));

        assertApproxEqAbs(_mintableForFirstEpoch, 1115000 * 1e18, 1e20, "testParamsOnFinishedEpochs: E7"); // make sure ~1,125,000 tokens will be emitted in 1st year

        skip(86400 * 365 / 2); // skip half of 1st epoch (year)
        assertEq(puppetERC20.availableSupply(), puppetERC20.totalSupply() + (_mintableForFirstEpoch / 2), "testParamsOnFinishedEpochs: E8");

        vm.expectRevert(); // reverts with ```too soon!```
        puppetERC20.updateMiningParameters();

        skip(86400 * 365 / 2); // skip 2nd half of 1st epoch (year)
        assertEq(puppetERC20.availableSupply(), puppetERC20.totalSupply() + (_mintableForFirstEpoch), "testParamsOnFinishedEpochs: E8");

        _testMint(_mintableForFirstEpoch); // this also starts the next epoch

        uint256 _mintedLastEpoch = _mintableForFirstEpoch;
        for (uint256 i = 0; i < 39; i++) {
            uint256 _mintableForEpoch = puppetERC20.mintableInTimeframe(puppetERC20.startEpochTime(), puppetERC20.startEpochTime() + (86400 * 365));

            assertTrue(_mintableForEpoch > 0, "testParamsOnFinishedEpochs: E9:");

             // make sure inflation is decreasing by ~18% each year
            assertApproxEqAbs(_mintableForEpoch, _mintedLastEpoch - (_mintedLastEpoch * 18 / 100), 1e23, "testParamsOnFinishedEpochs: E10:");

            skip(86400 * 365); // skip the entire epoch (year)

            _testMint(_mintableForEpoch); // this also starts the next epoch

            _mintedLastEpoch = _mintableForEpoch;
        }

        assertEq(puppetERC20.availableSupply(), 10000000 * 1e18, "testParamsOnFinishedEpochs: E11:");
        assertEq(puppetERC20.totalSupply(), 10000000 * 1e18, "testParamsOnFinishedEpochs: E12:");

        vm.startPrank(minter);
        vm.expectRevert(); // reverts with ```exceeds allowable mint amount```        
        puppetERC20.mint(owner, 1);
        vm.stopPrank();
    }

    function _testMint(uint256 _mintableForEpoch) internal {
        uint256 _aliceBalanceBefore = puppetERC20.balanceOf(alice);
        uint256 _totalSupplyBefore = puppetERC20.totalSupply();

        assertEq(puppetERC20.totalSupply(), _totalSupplyBefore, "_testMint: E1");

        vm.expectRevert(); // reverts with ```minter only```        
        puppetERC20.mint(owner, _mintableForEpoch);

        vm.startPrank(minter);
        puppetERC20.mint(alice, _mintableForEpoch);
        vm.stopPrank();

        assertEq(puppetERC20.availableSupply(), _totalSupplyBefore + _mintableForEpoch, "_testMint: E2");
        assertEq(puppetERC20.totalSupply(), _totalSupplyBefore + _mintableForEpoch, "_testMint: E3");
        assertEq(puppetERC20.balanceOf(alice), _aliceBalanceBefore + _mintableForEpoch, "_testMint: E4");
    }
}