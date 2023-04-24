// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IGMXRouter} from "./interfaces/IGMXRouter.sol";
import {IGMXReader} from "./interfaces/IGMXReader.sol";
import {IGMXPositionRouter} from "./interfaces/IGMXPositionRouter.sol";
import {IWETH} from "./interfaces/IWETH.sol";

import {PuppetRoute} from "./PuppetRoute.sol";
import {IPuppetOrchestrator} from "./interfaces/IPuppetOrchestrator.sol";
import {ITraderRoute} from "./interfaces/ITraderRoute.sol";

contract TraderRoute is ReentrancyGuard, ITraderRoute {

    using SafeERC20 for IERC20;
    using Address for address payable;

    address public trader;
    address public collateralToken;
    address public indexToken;

    bool public isLong;
    bool public isWaitingForCallback;

    bytes public puppetPositionData;

    IPuppetOrchestrator public puppetOrchestrator;
    PuppetRoute public puppetRoute;

    // ====================== Constructor ======================

    constructor(address _trader, address _collateralToken, address _indexToken, bool _isLong) {
        puppetRoute = new PuppetRoute(_collateralToken, _indexToken, _isLong);

        puppetOrchestrator = IPuppetOrchestrator(msg.sender);

        trader = _trader;
        collateralToken = _collateralToken;
        indexToken = _indexToken;
        isLong = _isLong;

        IGMXRouter(puppetOrchestrator.getGMXRouter()).approvePlugin(puppetOrchestrator.getGMXPositionRouter());
    }

    // ====================== Modifiers ======================

    modifier onlyCallbackTarget() {
        if (msg.sender != owner && msg.sender != puppetOrchestrator.getCallbackTarget()) revert NotCallbackTarget();
        _;
    }

    modifier onlyPuppetRoute() {
        if (msg.sender != owner && msg.sender != address(puppetRoute)) revert NotPuppetRoute();
        _;
    }

    modifier onlyKeeper() {
        if (msg.sender != owner && !puppetOrchestrator.isKeeper(msg.sender)) revert NotKeeper();
        _;
    }

    // ====================== Trader functions ======================

    function createPosition(bytes memory _traderData, bytes memory _puppetsData, bool _isIncrease, bool _isPuppetIncrease) external payable nonReentrant {
        if (isWaitingForCallback) revert WaitingForCallback();
        if (msg.sender != trader) revert NotTrader();

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

    function onLiquidation(bytes memory _puppetPositionData) external nonReentrant onlyKeeper {
        if (!_isLiquidated()) revert PositionStillAlive();

        _repayBalance();

        puppetRoute.liquidatePosition(_puppetPositionData);

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

    function _createIncreasePosition(bytes memory _traderPositionData) internal {
        (address _indexToken, uint256 _amountIn, uint256 _minOut, uint256 _sizeDelta, uint256 _acceptablePrice, uint256 _executionFee)
            = abi.decode(_traderPositionData, (address, uint256, uint256, uint256, uint256, uint256));

        address[] memory _path = new address[](1);
        _path[0] = collateralToken;

        bytes32 _referralCode = puppetOrchestrator.getReferralCode();
        address _callbackTarget = puppetOrchestrator.getCallbackTarget();
        bytes32 _positionKey = IGMXPositionRouter(puppetOrchestrator.getGMXPositionRouter()).createIncreasePosition(_path, _indexToken, _amountIn, _minOut, _sizeDelta, routeInfo.isLong, _acceptablePrice, _executionFee, _referralCode, _callbackTarget);

        puppetOrchestrator.updatePositionKeyToRouteAddress(_positionKey);

        emit CreateIncreasePosition(_positionKey, _amountIn, _minOut, _sizeDelta, _acceptablePrice, _executionFee);
    }

    function _createDecreasePosition(bytes memory _traderPositionData) internal {
        (address _indexToken, uint256 _collateralDeltaUSD, uint256 _sizeDelta, uint256 _acceptablePrice, uint256 _minOut, uint256 _executionFee)
            = abi.decode(_traderPositionData, (address, uint256, uint256, uint256, uint256, uint256));

        address[] memory _path = new address[](1);
        _path[0] = collateralToken;

        address _callbackTarget = puppetOrchestrator.getCallbackTarget();
        bytes32 _positionKey = IGMXPositionRouter(puppetOrchestrator.getGMXPositionRouter()).createDecreasePosition(_path, _indexToken, _collateralDeltaUSD, _sizeDelta, _route.isLong, address(this), _acceptablePrice, _minOut, _executionFee, false, _callbackTarget);

        if (puppetOrchestrator.getRouteForPositionKey(_positionKey) != address(this)) revert KeyError();

        emit CreateDecreasePosition(_positionKey, _minOut, _collateralDeltaUSD, _sizeDelta, _acceptablePrice, _executionFee);
    }

    function _repayBalance() internal {
        uint256 _totalAssets = address(this).balance;
        if (_totalAssets > 0) payable(trader).sendValue(_totalAssets);
    }
}