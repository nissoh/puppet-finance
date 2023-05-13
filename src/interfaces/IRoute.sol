// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IRoute {

    // ============================================================================================
    // Mutated Functions
    // ============================================================================================

    function createPositionRequest(bytes memory _traderPositionData, bytes memory _traderSwapData, bool _isIncrease) external payable returns (bytes32 _requestKey);

    function createIncreasePositionRequestETH(bytes memory _traderPositionData, uint256 _minOut) external payable returns (bytes32 _requestKey);

    function onLiquidation() external;

    function approvePositionRequest() external;

    function rejectPositionRequest() external;

    function approvePlugin() external;

    function setOrchestrator(address _orchestrator) external;

    function rescueStuckTokens(address _token, address _to) external;

    // ============================================================================================
    // Events
    // ============================================================================================

    event Liquidated();
    event ApprovePositionRequest();
    event RejectPositionRequest();
    event RepayBalance(uint256 _totalAssets);
    event CreateIncreasePosition(bytes32 indexed positionKey, uint256 amountIn, uint256 minOut, uint256 sizeDelta, uint256 acceptablePrice, uint256 executionFee);
    event CreateDecreasePosition(bytes32 indexed positionKey, uint256 minOut, uint256 collateralDeltaUSD, uint256 sizeDelta, uint256 acceptablePrice, uint256 executionFee);
    event ResetPosition();
    event PluginApproved();
    event OrchestratorSet(address indexed _orchestrator);
    event StuckTokensRescued(address token, address to);
    event PuppetsAssetsAndSharesAllocated(uint256 puppetsAmountIn, uint256 totalManagementFee);
    event TraderAssetsAndSharesAllocated(uint256 traderAmountIn, uint256 traderShares);

    // ============================================================================================
    // Errors
    // ============================================================================================

    error WaitingForCallback();
    error NotCallbackTarget();
    error NotOwner();
    error KeyError();
    error NotKeeper();
    error ZeroAmount();
    error InvalidExecutionFee();
    error PositionStillAlive();
    error NotTrader();
    error InvalidPath();
}