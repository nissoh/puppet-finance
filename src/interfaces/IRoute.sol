// SPDX-License-Identifier: AGPL
pragma solidity 0.8.17;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// =========================== IRoute ===========================
// ==============================================================
// Puppet Finance: https://github.com/GMX-Blueberry-Club/Puppet

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

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
        mapping(address => uint256) latestAmountIn; // puppet => latestAmountIn
    }

    struct AddCollateralRequest{
        bool isAdjustmentRequired;
        uint256 puppetsAmountIn;
        uint256 traderAmountIn;
        uint256 traderShares;
        uint256 totalSupply;
        uint256 totalAssets;
        uint256[] puppetsShares;
        uint256[] puppetsAmounts;
    }

    struct AdjustPositionParams {
        uint256 collateralDelta;
        uint256 sizeDelta;
        uint256 acceptablePrice;
        uint256 minOut;
    }

    struct SwapParams {
        address[] path;
        uint256 amount;
        uint256 minOut;
    }

    struct GetPuppetAdditionalAmountContext {
        bool isOI;
        uint256 increaseRatio;
        uint256 traderAmountIn;
    }

    struct PuppetRequestInfo {
        bool isAdjustmentRequired;
        uint256 additionalAmount;
        uint256 additionalShares;
    }

    // ============================================================================================
    // View Functions
    // ============================================================================================

    // Route Info

    /// @notice The ```trader``` function returns the trader address of the current route
    /// @return _trader The trader address
    function trader() external view returns (address _trader);

    /// @notice The ```collateralToken``` function returns the collateral token address of the current route
    /// @return _collateralToken The collateral token address
    function collateralToken() external view returns (address _collateralToken);

    /// @notice The ```indexToken``` function returns the index token address of the current route
    /// @return _indexToken The index token address
    function indexToken() external view returns (address _indexToken);

    /// @notice The ```isLong``` function returns the direction of the current route
    /// @return _isLong The direction of the current route
    function isLong() external view returns (bool _isLong);

    /// @notice The ```routeKey``` function returns the route key of the current route
    /// @return _routeKey The route key 
    function routeKey() external view returns (bytes32 _routeKey);

    // Position Info

    /// @notice The ```puppets``` function returns the puppets that are subscribed to the current position
    /// @return _puppets The address array of puppets
    function puppets() external view returns (address[] memory _puppets);

    /// @notice The ```puppetShares``` function returns the shares of a participant in the current position
    /// @param _participant The participant address
    /// @return _shares The shares of the participant
    function participantShares(address _participant) external view returns (uint256 _shares);

    /// @notice The ```totalSupply``` function returns the latest collateral amount added by a participant to the current position
    /// @param _participant The participant address
    /// @return _amountIn The latest collateral amount added by the participant
    function latestAmountIn(address _participant) external view returns (uint256 _amountIn);

    /// @notice The ```isAdjustmentEnabled``` function indicates if the route is enabled for keeper adjustment
    /// @return _isEnabled Indicating if the route is enabled for keeper adjustment
    function isAdjustmentEnabled() external view returns (bool _isEnabled);

    /// @notice The ```requiredAdjustmentSize``` function returns the required adjustment size for the route
    /// @notice If Puppets cannot pay the required amount when Trader adds collateral to an existing position, we need to decrease their size so the position's size/collateral ratio is as expected
    /// @return _requiredSize The required adjustment size for the route 
    function requiredAdjustmentSize() external view returns (uint256 _requiredSize);

    // Request Info

    /// @notice The ```puppetsRequestAmounts``` function returns the puppets amounts and shares for a given request
    /// @param _requestKey The request key
    /// @return _puppetsShares The total puppets shares
    /// @return _puppetsAmounts The total puppets amounts 
    function puppetsRequestAmounts(bytes32 _requestKey) external view returns (uint256[] memory _puppetsShares, uint256[] memory _puppetsAmounts);

    /// @notice The ```isWaitingForCallback``` function indicates if the route is waiting for a callback from GMX
    /// @return bool Indicating if the route is waiting for a callback from GMX
    function isWaitingForCallback() external view returns (bool);

    // ============================================================================================
    // Mutated Functions
    // ============================================================================================

    // Orchestrator

    // called by trader

    /// @notice The ```requestPosition``` function creates a new position request
    /// @param _adjustPositionParams The adjusment params for the position
    /// @param _swapParams The swap data of the Trader, enables the Trader to add collateral with a non-collateral token
    /// @param _executionFee The total execution fee, paid by the Trader in ETH
    /// @param _isIncrease The boolean indicating if the request is an increase or decrease request
    /// @return _requestKey The request key
    function requestPosition(AdjustPositionParams memory _adjustPositionParams, SwapParams memory _swapParams, uint256 _executionFee, bool _isIncrease) external payable returns (bytes32 _requestKey);

    /// @notice The ```approvePlugin``` function is used to approve the GMX plugin in case we change the gmxPositionRouter address
    function approvePlugin() external;

    // called by keeper

    /// @notice The ```decreaseSize``` function is called by Puppet keepers to decrease the position size in case there are Puppets to adjust
    /// @param _adjustPositionParams The adjusment params for the position
    /// @param _executionFee The total execution fee, paid by the Keeper in ETH
    /// @return _requestKey The request key
    function decreaseSize(AdjustPositionParams memory _adjustPositionParams, uint256 _executionFee) external payable returns (bytes32 _requestKey);

    /// @notice The ```liquidate``` function is called by Puppet keepers to reset the Route's accounting in case of a liquidation
    function liquidate() external;

    // called by owner

    /// @notice The ```rescueTokens``` is called by the Orchestrator and Authority to rescue tokens
    /// @param _amount The amount to rescue
    /// @param _token The token address
    /// @param _receiver The receiver address
    function rescueTokens(uint256 _amount, address _token, address _receiver) external;

    /// @notice The ```freeze``` function is called by the Orchestrator and Authority to freeze the Route
    /// @param _freeze The boolean indicating if the Route should be frozen or unfrozen 
    function freeze(bool _freeze) external;

    // ============================================================================================
    // Events
    // ============================================================================================

    event Liquidate();
    event Callback(bytes32 indexed requestKey, bool indexed isExecuted, bool indexed isIncrease);
    event PluginApproval();
    event IncreaseRequest(bytes32 indexed requestKey, uint256 amountIn, uint256 minOut, uint256 sizeDelta, uint256 acceptablePrice);
    event DecreaseRequest(bytes32 indexed requestKey, uint256 minOut, uint256 collateralDelta, uint256 sizeDelta, uint256 acceptablePrice);
    event Repay(uint256 totalAssets);
    event Reset();
    event Rescue(uint256 amount, address token, address receiver);
    event Freeze(bool indexed freeze);

    // ============================================================================================
    // Errors
    // ============================================================================================

    error WaitingForKeeperAdjustment();
    error NotKeeper();
    error NotTrader();
    error InvalidExecutionFee();
    error InvalidPath();
    error PositionStillAlive();
    error Paused();
    error NotOrchestrator();
    error RouteFrozen();
    error NotCallbackCaller();
    error NotWaitingForKeeperAdjustment();
    error ZeroAmount();
    error KeeperAdjustmentDisabled();
}