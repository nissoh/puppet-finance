// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IPositionRouterCallbackReceiver} from "./IPositionRouterCallbackReceiver.sol";

interface IRoute is IPositionRouterCallbackReceiver {

    struct RouteInfo {
        bool isLong;
        address trader;
        address collateralToken;
        address indexToken;
    }

    struct PositionInfo {
        uint256 addCollateralRequestsIndex;
        uint256 totalSupply;
        uint256 totalAssets;
        address[] puppets;
        mapping(address => uint256) participantShares; // participant => shares
        mapping(address => bool) adjustedPuppets; // puppet => isAdjusted
    }

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
    // View Functions
    // ============================================================================================

    function getPuppets() external view returns (address[] memory _puppets);

    function getPuppetsRequestInfo(bytes32 _requestKey) external view returns (address[] memory _puppetsToAdjust, uint256[] memory _puppetsShares, uint256[] memory _puppetsAmounts);

    // ============================================================================================
    // Mutated Functions
    // ============================================================================================

    // trader

    function createPositionRequest(bytes memory _traderPositionData, bytes memory _traderSwapData, uint256 _executionFee, bool _isIncrease) external payable returns (bytes32 _requestKey);

    // keeper

    function decreaseSize(address[] memory _puppets, bytes memory _traderPositionData, uint256 _executionFee) external returns (bytes32 _requestKey);

    function liquidate() external;

    // owner

    function updateUtils(address _orchestrator) external;

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
    event RouteReset();
    event InsolventPuppets(address[] _insolventPuppets);
    event RatioAdjustmentWaitOver();
    event PuppetsToAdjust(bytes32 indexed requestKey);
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
    error Paused();
    error InvalidPrice();
}