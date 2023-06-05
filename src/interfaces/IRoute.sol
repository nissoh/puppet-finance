// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IPositionRouterCallbackReceiver} from "./IPositionRouterCallbackReceiver.sol";

interface IRoute is IPositionRouterCallbackReceiver {

    struct Route {
        bool isLong;
        address trader;
        address collateralToken;
        address indexToken;
    }

    struct Position {
        uint256 addCollateralRequestsIndex;
        uint256 totalSupply;
        uint256 totalAssets;
        bytes32[] requestKeys;
        address[] puppets;
        mapping(address => uint256) participantShares; // participant => shares
        mapping(address => bool) adjustedPuppets; // puppet => isAdjusted
        mapping(address => uint256) latestAmountIn; // puppet => latestAmountIn
    }

    struct AddCollateralRequest{
        uint256 puppetsAmountIn;
        uint256 traderAmountIn;
        uint256 traderShares;
        uint256 totalSupply;
        uint256 totalAssets;
        uint256[] puppetsShares;
        uint256[] puppetsAmounts;
    }

    // ============================================================================================
    // View Functions
    // ============================================================================================

    // Position Info

    function puppets() external view returns (address[] memory _puppets);

    function participantShares(address _participant) external view returns (uint256 _shares);

    function latestAmountIn(address _participant) external view returns (uint256 _amountIn);

    function isPuppetAdjusted(address _puppet) external view returns (bool _isAdjusted);

    // Request Info

    function puppetsRequestAmounts(bytes32 _requestKey) external view returns (uint256[] memory _puppetsShares, uint256[] memory _puppetsAmounts);

    function isWaitingForCallback() external view returns (bool);

    // ============================================================================================
    // Mutated Functions
    // ============================================================================================

    // Trader

    function createPositionRequest(bytes memory _traderPositionData, bytes memory _traderSwapData, uint256 _executionFee, bool _isIncrease) external payable returns (bytes32 _requestKey);

    function approvePlugin() external;

    // Keeper

    function decreaseSize(bytes memory _traderPositionData, uint256 _executionFee) external returns (bytes32 _requestKey);

    function liquidate() external;

    // Orchestrator

    function rescueTokens(uint256 _amount, address _token, address _receiver) external;

    function freeze(bool _freeze) external;

    // ============================================================================================
    // Events
    // ============================================================================================

    event Liquidated();
    event CallbackReceived(bytes32 indexed requestKey, bool indexed isExecuted, bool indexed isIncrease);
    event PluginApproved();
    event CreatedIncreasePositionRequest(bytes32 indexed requestKey, uint256 amountIn, uint256 minOut, uint256 sizeDelta, uint256 acceptablePrice, uint256 executionFee);
    event CreatedDecreasePositionRequest(bytes32 indexed requestKey, uint256 minOut, uint256 collateralDelta, uint256 sizeDelta, uint256 acceptablePrice, uint256 executionFee);
    event BalanceRepaid(uint256 totalAssets);
    event RouteReset();
    event TokensRescued(uint256 _amount, address _token, address _receiver);
    event Frozen(bool indexed _freeze);

    // ============================================================================================
    // Errors
    // ============================================================================================

    error NotKeeper();
    error NotTrader();
    error InvalidExecutionFee();
    error InvalidPath();
    error PositionStillAlive();
    error Paused();
    error NotOrchestrator();
    error RouteFrozen();
    error NotCallbackCaller();
}