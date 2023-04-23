// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {IGMXRouter} from "./interfaces/IGMXRouter.sol";
import {IGMXReader} from "./interfaces/IGMXReader.sol";
import {IGMXPositionRouter} from "./interfaces/IGMXPositionRouter.sol";
import {IWETH} from "./interfaces/IWETH.sol";

import {IPuppetOrchestrator} from "./interfaces/IPuppetOrchestrator.sol";
import {ITraderRoute} from "./interfaces/ITraderRoute.sol";

contract TraderRoute is ReentrancyGuard, ITraderRoute {

    using SafeERC20 for IERC20;
    using Address for address payable;

    address public trader;
    address public collateralToken;
    address public indexToken;

    bool public isLong;
    bool public isPositionOpen;
    bool public isWaitingForCallback;

    bytes public puppetPositionData;

    IPuppetOrchestrator public puppetOrchestrator;

    // ====================== Constructor ======================

    constructor(address _trader, address _collateralToken, address _indexToken, bool _isLong) {
        puppetOrchestrator = IPuppetOrchestrator(msg.sender);

        trader = _trader;
        collateralToken = _collateralToken;
        indexToken = _indexToken;
        isLong = _isLong;

        IGMXRouter(puppetOrchestrator.getGMXRouter()).approvePlugin(puppetOrchestrator.getGMXPositionRouter());
    }

    // ====================== Modifiers ======================

    modifier onlyCallbackTarget() {
        if (msg.sender != puppetOrchestrator.getCallbackTarget()) revert NotCallbackTarget();
        _;
    }

    modifier onlyPuppetRoute() {
        if (msg.sender != address(puppetRoute)) revert Unauthorized();
        _;
    }

    // ====================== Trader functions ======================

    function createPosition(bytes memory _traderData, bytes memory _puppetsData, bool _isIncrease, bool _isPuppetIncrease) external payable nonReentrant {
        if (isWaitingForCallback) revert WaitingForCallback();
        if (trader != msg.sender) revert Unauthorized();

        puppetPositionData = _puppetsData;
        isWaitingForCallback = true;
        isPuppetIncrease = _isPuppetIncrease;

        _isIncrease ? _createIncreasePosition(_traderData) : _createDecreasePosition(_traderData);
    }

    // ====================== PuppetRoute ======================

    function notifyCallback(bool _isIncrease) external nonReentrant onlyPuppetRoute {
        isWaitingForCallback = false;
    }

    // ====================== liquidation ======================

    function onLiquidation() external nonReentrant {
        // if (msg.sender != puppetOrchestrator.getCallbackTarget()) revert NotCallbackTarget(); // TODO - who is msg.sender?

        _repayBalance();

        emit Liquidated();
    }

    // ====================== request callback ======================

    function approvePositionRequest() external nonReentrant onlyCallbackTarget {
        _repayBalance();

        isPuppetIncrease ? puppetRoute.createIncreasePosition(puppetPositionData) : puppetRoute.createDecreasePosition(puppetPositionData);

        emit ApprovePositionRequest();
    }

    function rejectPositionRequest() external nonReentrant onlyCallbackTarget {
        isWaitingForCallback = false;

        _repayBalance();

        emit RejectPositionRequest();
    }

    // ====================== Internal functions ======================

    function _createIncreasePosition(bytes memory _traderData) internal {
        (address _collateralToken, address _indexToken, uint256 _amountIn, uint256 _minOut, uint256 _sizeDelta, uint256 _acceptablePrice, uint256 _executionFee)
            = abi.decode(_traderData, (address, address, uint256, uint256, uint256, uint256, uint256));

        address[] memory _path = new address[](1);
        _path[0] = _collateralToken;

        bytes32 _referralCode = puppetOrchestrator.getReferralCode();
        address _callbackTarget = puppetOrchestrator.getCallbackTarget();
        bytes32 _positionKey = IGMXPositionRouter(puppetOrchestrator.getGMXPositionRouter()).createIncreasePosition(_path, _indexToken, _amountIn, _minOut, _sizeDelta, routeInfo.isLong, _acceptablePrice, _executionFee, _referralCode, _callbackTarget);

        puppetOrchestrator.updateGMXPositionKeyToTraderRouteAddress(_positionKey);

        emit CreateIncreasePosition(_positionKey, _amountIn, _minOut, _sizeDelta, _acceptablePrice, _executionFee);
    }

    function _createDecreasePosition(bytes memory _traderData) internal {
        (address _collateralToken, address _indexToken, uint256 _collateralDeltaUSD, uint256 _sizeDelta, uint256 _acceptablePrice, uint256 _minOut, uint256 _executionFee)
            = abi.decode(_traderData, (address, address, uint256, uint256, uint256, uint256, uint256));

        address[] memory _path = new address[](1);
        _path[0] = _collateralToken;

        address _callbackTarget = puppetOrchestrator.getCallbackTarget();
        bytes32 _positionKey = IGMXPositionRouter(puppetOrchestrator.getGMXPositionRouter()).createDecreasePosition(_path, _indexToken, _collateralDeltaUSD, _sizeDelta, _route.isLong, address(this), _acceptablePrice, _minOut, _executionFee, false, _callbackTarget);

        if (puppetOrchestrator.getTraderRouteForPosition(_positionKey) != address(this)) revert KeyError();

        emit CreateDecreasePosition(_positionKey, _minOut, _collateralDeltaUSD, _sizeDelta, _acceptablePrice, _executionFee);
    }

    function _repayBalance() internal {
        uint256 _totalAssets = address(this).balance;
        if (_totalAssets > 0) payable(trader).sendValue(_totalAssets);
    }
}