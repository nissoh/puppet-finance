// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IPositionRouterCallbackReceiver} from "./IPositionRouterCallbackReceiver.sol";

interface IRoute is IPositionRouterCallbackReceiver {

    struct AddCollateralRequest{
        uint256 puppetsAmountIn;
        uint256 traderAmountIn;
        uint256 traderShares;
        uint256 totalSupply;
        uint256 totalAssets;
        address[] puppetsToAdjust;
        uint256[] puppetsShares;
        uint256[] puppetsAmounts;
    }

    // ============================================================================================
    // Mutated Functions
    // ============================================================================================

    // trader

    function createPositionRequest(bytes memory _traderPositionData, bytes memory _traderSwapData, bool _isIncrease) external payable returns (bytes32 _requestKey);

    function createAddCollateralRequestETH(bytes memory _traderPositionData, uint256 _minOut) external payable returns (bytes32 _requestKey);

    // keeper

    function decreaseSize() external;

    function liquidate() external;

    function checkForReferralRebates() external;

    // owner

    function approvePlugin() external;

    function setOrchestrator(address _orchestrator) external;

    function updatePriceFeed() external;

    function updateGlobalInfo() external;

    function updateGMXInfo() external;

    // ============================================================================================
    // Events
    // ============================================================================================


    event Liquidated();
    event CallbackReceived(bytes32 indexed requestKey, bool indexed isExecuted, bool indexed isIncrease);
    event PluginApproved();
    event OrchestratorSet(address orchestrator);
    event PriceFeedUpdated();
    event GlobalInfoUpdated();
    event GMXInfoUpdated();
    event CreatedIncreasePositionRequest(bytes32 indexed requestKey, uint256 amountIn, uint256 minOut, uint256 sizeDelta, uint256 acceptablePrice, uint256 executionFee);
    event CreatedDecreasePositionRequest(bytes32 indexed requestKey, uint256 minOut, uint256 collateralDelta, uint256 sizeDelta, uint256 acceptablePrice, uint256 executionFee);
    event RepaidBalance(uint256 totalAssets);
    event RouteReseted();
    event ReferralRebatesSent(address indexed revenueDistributor, uint256 balance);
    event InsolventPuppets(address[] _insolventPuppets);
    event RatioAdjustmentWaitOver();
    event PuppetsToAdjust(address[] _puppetsToAdjust);
    event RatioAdjustmentFailed();
    event RatioAdjustmentExecuted();

    // ============================================================================================
    // Errors
    // ============================================================================================

    error NotCallbackCaller();
    error NotKeeper();
    error NotTrader();
    error InvalidExecutionFee();
    error InvalidPath();
    error InvalidValue();
    error InvalidMaxAmount();
    error InvalidPathLength();
    error InvalidTokenIn();
    error PositionStillAlive();
    error WaiingtForRatioAdjustment();
    error Paused();
}