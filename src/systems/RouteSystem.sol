// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {AggregatorV3Interface} from "@chainlink/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {System} from "@latticexyz/world/src/System.sol";
import {Counter} from "../codegen/Tables.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// import {IVault} from "./interfaces/IVault.sol";
// import {IGMXRouter} from "./interfaces/IGMXRouter.sol";
// import {IGMXPositionRouter} from "./interfaces/IGMXPositionRouter.sol";
// import {IGMXVault} from "./interfaces/IGMXVault.sol";
// import {IGMXReader} from "./interfaces/IGMXReader.sol";

contract RouteSystem is System, ReentrancyGuard {
    // using SafeERC20 for IERC20;
    // using Address for address payable;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    // constructor(
    //     address _orchestrator,
    //     address _owner,
    //     address _trader,
    //     address _collateralToken,
    //     address _indexToken,
    //     bool _isLong
    // ) {

    //     // owner = _owner;
    //     // trader = _trader;
    //     // collateralToken = _collateralToken;
    //     // indexToken = _indexToken;
    //     // isLong = _isLong;

    //     // (address _priceFeed, uint256 _decimals) = orchestrator.getPriceFeed(_collateralToken);
    //     // priceFeed = AggregatorV3Interface(_priceFeed);
    //     // priceFeedDecimals = _decimals;

    //     // (referralCode, performanceFeePercentage, keeper, revenueDistributor) = orchestrator.getGlobalInfo();

    //     // gmxInfo = orchestrator.getGMXInfo();

    //     // IGMXRouter(gmxInfo.gmxRouter).approvePlugin(gmxInfo.gmxPositionRouter);
    // }

//     modifier onlyOwner() {
//         if (msg.sender != owner) revert NotOwner();
//         _;
//     }

//     modifier onlyCallbackCaller() {
//         if (msg.sender != owner && msg.sender != gmxInfo.gmxCallbackCaller) revert NotCallbackCaller();
//         _;
//     }

//     modifier onlyKeeper() {
//         if (msg.sender != owner && msg.sender != keeper) revert NotKeeper();
//         _;
//     }

//     function increment() public returns (uint32) {
//         uint32 counter = Counter.get();
//         uint32 newValue = counter + 1;
//         Counter.set(newValue);
//         return newValue;
//     }

//     function createPositionRequest(bytes memory _traderPositionData, bytes memory _traderSwapData, bool _isIncrease)
//         public
//         payable
//         nonReentrant
//         returns (bool)
//     {
//         if (msg.sender != trader) revert NotTrader();
//         if (orchestrator.getIsPaused()) revert Paused();

//         if (!isETHRequest) _checkForReferralRebates();

//         isPositionOpen = true;

//         return true;
//     }

//     // ============================================================================================
//     // Callback Function
//     // ============================================================================================

//     function gmxPositionCallback(bytes32 _requestKey, bool _isExecuted, bool _isIncrease) external nonReentrant 
//     // onlyCallbackCaller
//     {
//         if (_isExecuted) {
//             if (_isIncrease) _allocateShares(_requestKey);
//             _requestKey = bytes32(0);
//         }

//         _repayBalance(_requestKey);

//         emit CallbackReceived(_requestKey, _isExecuted, _isIncrease);
//     }

//     // ============================================================================================
//     // Owner Functions
//     // ============================================================================================

//     function approvePlugin() external onlyOwner {
//         IGMXRouter(gmxInfo.gmxRouter).approvePlugin(gmxInfo.gmxPositionRouter);

//         emit PluginApproved();
//     }

//     function setOrchestrator(address _orchestrator) external onlyOwner {
//         orchestrator = IOrchestrator(_orchestrator);

//         emit OrchestratorSet(_orchestrator);
//     }

//     function updateGlobalInfo() external onlyOwner {
//         (referralCode, performanceFeePercentage, keeper, revenueDistributor) = orchestrator.getGlobalInfo();

//         emit GlobalInfoUpdated();
//     }

//     function updateGMXInfo() external onlyOwner {
//         gmxInfo = orchestrator.getGMXInfo();

//         emit GMXInfoUpdated();
//     }

//     function _convertToShares(uint256 _totalAssets, uint256 _totalSupply, uint256 _assets)
//         internal
//         pure
//         returns (uint256 _shares)
//     {
//         if (_assets == 0) revert ZeroAmount();

//         if (_totalAssets == 0) {
//             _shares = _assets;
//         } else {
//             _shares = (_assets * _totalSupply) / _totalAssets;
//         }

//         if (_shares == 0) revert ZeroAmount();
//     }

//     function _convertToAssets(uint256 _totalAssets, uint256 _totalSupply, uint256 _shares)
//         internal
//         pure
//         returns (uint256 _assets)
//     {
//         if (_shares == 0) revert ZeroAmount();

//         if (_totalSupply == 0) {
//             _assets = _shares;
//         } else {
//             _assets = (_shares * _totalAssets) / _totalSupply;
//         }

//         if (_assets == 0) revert ZeroAmount();
//     }

//     // ============================================================================================
//     // Receive Function
//     // ============================================================================================

//     receive() external payable {
//         if (gmxInfo.gmxReferralRebatesSender == msg.sender) payable(revenueDistributor).sendValue(msg.value);
//     }
}