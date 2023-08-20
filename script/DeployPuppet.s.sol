// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {ScoreGaugeV1} from "src/token/ScoreGaugeV1.sol";
import {Puppet} from "src/token/Puppet.sol";
import {VotingEscrow} from "src/token/VotingEscrow.sol";
import {GaugeController} from "src/token/GaugeController.sol";
import {Minter} from "src/token/Minter.sol";
import {RevenueDistributer} from "src/token/RevenueDistributer.sol";

import {RouteFactory} from "src/RouteFactory.sol";
import {Orchestrator} from "src/Orchestrator.sol";

import "./utilities/DeployerUtilities.sol";

// ---- Usage ----
// forge script script/DeployPuppet.s.sol:DeployPuppet --rpc-url $RPC_URL --broadcast
// forge verify-contract --constructor-args $ARGS --watch --chain-id 42161 --compiler-version v0.8.19+commit.7dd6d404 --verifier-url https://api.arbiscan.io/api $CONTRACT_ADDRESS src/Orchestrator.sol:Orchestrator
// --constructor-args $(cast abi-encode "constructor(address)" 0xBF73FEBB672CC5B8707C2D75cB49B0ee2e2C9DaA)
// $(cast abi-encode "constructor(address,address,address,address,bool)" 0x82403099D24b2bF9Ee036F05E34da85E30982234 0xF6F08BEe1b2B9059a5132d171943Fa7a078C77e1 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1 true)

// address _orchestrator, address _trader, address _collateralToken, address _indexToken, bool _isLong
// forge verify-contract --constructor-args $(cast abi-encode "constructor(address,address,address,address,bool)" 0x262Dc133C85148eDA91B0343dF85d4fD54847970 0x189b21eda0cff16461913D616a0A4F711Cd986cB 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1 true) --watch --chain-id 42161 --compiler-version v0.8.19+commit.7dd6d404 --verifier-url https://api.arbiscan.io/api $CONTRACT_ADDRESS src/Route.sol:Route

contract DeployPuppet is DeployerUtilities {

    bytes private _gmxInfo = abi.encode(_gmxVaultPriceFeed, _gmxRouter, _gmxVault, _gmxPositionRouter, false, false);

    function run() public {
        vm.startBroadcast(_deployerPrivateKey);

        address _platformFeeRecipient = _deployer;

        Puppet _puppetERC20 = new Puppet("Puppet Finance Token - TEST", "PUPPET-TEST", 18);

        VotingEscrow _votingEscrow = new VotingEscrow(address(_puppetERC20), "Vote-escrowed PUPPET - TEST", "vePUPPET-TEST", "1.0.0");

        GaugeController _gaugeController = new GaugeController(address(_puppetERC20), address(_votingEscrow));

        Minter _minterContract = new Minter(address(_puppetERC20), address(_gaugeController));
        _puppetERC20.setMinter(address(_minterContract));

        Dictator _dictator = Dictator(_dictatorAddr);

        RouteFactory _routeFactory = new RouteFactory();

        Orchestrator _orchestrator = new Orchestrator(_dictator, address(_routeFactory), _keeperAddr, _platformFeeRecipient, _weth, _referralCode, _gmxInfo);

        ScoreGaugeV1 _scoreGaugeV1 = new ScoreGaugeV1(_deployer, address(_minterContract), address(_orchestrator));

        // https://www.unixtimestamp.com/index.php?ref=theredish.com%2Fweb (1600300800) // todo - calc next Thursday at 00:00:00 UTC
        uint256 _startTime = 1692835200; // Thu Aug 24 2023 00:00:00 GMT+0000
        // todo - on deployment, call revenueDistributer.checkpointToken(), wait a week, then call revenueDistributer.toggleAllowCheckpointToken()
        RevenueDistributer _revenueDistributer = new RevenueDistributer(address(0x4c2892E20CDeb7495A5357Eb5C0a6d7E67172A14), _startTime, _weth, _deployer, _deployer);

        bytes4 setRouteTypeFunctionSig = _orchestrator.setRouteType.selector;
        bytes4 setScoreGaugeFunctionSig = _orchestrator.setScoreGauge.selector;

        _setRoleCapability(_dictator, 0, address(_orchestrator), setRouteTypeFunctionSig, true);
        _setRoleCapability(_dictator, 0, address(_orchestrator), setScoreGaugeFunctionSig, true);
        _setUserRole(_dictator, _deployer, 0, true);

        // set route type
        _orchestrator.setRouteType(_weth, _weth, true);
        _orchestrator.setScoreGauge(address(_scoreGaugeV1));

        console.log("Deployed Addresses");
        console.log("==============================================");
        console.log("==============================================");
        console.log("dictator: %s", address(_dictator));
        console.log("routeFactory: %s", address(_routeFactory));
        console.log("orchestrator: %s", address(_orchestrator));
        console.log("puppetERC20: %s", address(_puppetERC20));
        console.log("votingEscrow: %s", address(_votingEscrow));
        console.log("gaugeController: %s", address(_gaugeController));
        console.log("minterContract: %s", address(_minterContract));
        console.log("scoreGauge1V1: %s", address(_scoreGaugeV1));
        console.log("revenueDistributer: %s", address(_revenueDistributer));
        console.log("==============================================");
        console.log("==============================================");

        vm.stopBroadcast();
    }
}

// puppetERC20: 0x16e55B1a06eEdC9e08E47434D0dB2735eA589Db7
//   votingEscrow: 0x4c2892E20CDeb7495A5357Eb5C0a6d7E67172A14
//   gaugeController: 0xf5372c0c9E35353Bc14E3aB8067234A20AbB40D1
//   minterContract: 0x1a566519E821756DC5Bed52579F388e602007eE7
// dictator: 0xA12a6281c1773F267C274c3BE1B71DB2BACE06Cb
//   routeFactory: 0x24A8843c03b894ff449F1F69dd1D60327004c147
//   orchestrator: 0x446fb2e318632135a34CF395840FfE6a483274C7
//   scoreGauge1V1: 0x920C10F42c3F5Dba70Cd2c7567918D3A400FA876
// revenueDistributer: 0x451971fE0EE93D80Ff1157CCe7f6D816b4559ee2