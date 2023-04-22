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

    address private constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

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

    // ====================== Trader functions ======================

    function createIncreasePosition(bytes memory _traderData, bytes memory _puppetsData) external payable nonReentrant {
        if (isWaitingForCallback) revert WaitingForCallback();

        address _trader = msg.sender;
        if (trader != _trader) revert InvalidCaller();

        (address _collateralToken,, uint256 _amountIn,,,,)
            = abi.decode(_traderData, (address, address, uint256, uint256, uint256, uint256, uint256));

        puppetPositionData = _puppetsData;

        _transferFunds(_amountIn, _collateralToken, _trader);

        _createIncreasePosition(_traderData, _puppetsData);
    }

    function createDecreasePosition(bytes memory _positionData, bool _isETH) external nonReentrant {
        if (isWaitingForCallback) revert WaitingForCallback();

        (address _collateralToken,, uint256 _collateralDeltaUSD,,,,)
            = abi.decode(_positionData, (address, address, uint256, uint256, uint256, uint256, uint256));

        if (_isETH && _collateralToken != WETH) revert InvalidCollateralToken();

        address _trader = msg.sender;
        if (trader != _trader) revert InvalidCaller();

        _createDecreasePosition(_positionData);
    }

    // ====================== liquidation ======================

    function onLiquidation() external nonReentrant {
        // if (msg.sender != puppetOrchestrator.getCallbackTarget()) revert NotCallbackTarget(); // TODO - who is msg.sender?
        if (_isOpenInterest()) revert PositionStillAlive();

        RouteInfo storage _route = routeInfo;

        _route.totalAmount = 0;
        _route.totalSupply = 0;
        _route.traderRequestedCollateralAmount = 0;
        _route.isPositionOpen = false;
        _route.isWaitingForCallback = false;
        for (uint256 i = 0; i < EnumerableMap.length(_route.participantShares); i++) {
            (address _key, ) = EnumerableMap.at(_route.participantShares, i);
            EnumerableMap.remove(_route.participantShares, _key);
        }

        emit OnLiquidation();
    }

    // ====================== request callback ======================

    function approveIncreasePosition() external nonReentrant {
        if (msg.sender != puppetOrchestrator.getCallbackTarget()) revert NotCallbackTarget();

        isPositionOpen = true;

        puppetRoute.createIncreasePosition(puppetPositionData);

        emit ApproveIncreasePosition();
    }

    function rejectIncreasePosition() external nonReentrant {
        if (msg.sender != puppetOrchestrator.getCallbackTarget()) revert NotCallbackTarget();

        address _token = collateralToken;
        uint256 _balance = IERC20(_token).balanceOf(address(this));
        if (_balance > 0) IERC20(_token).safeTransfer(trader, _balance);

        isWaitingForCallback = false;

        emit RejectIncreasePosition(_balance);
    }

    function approveDecreasePosition() external nonReentrant {
        if (msg.sender != puppetOrchestrator.getCallbackTarget()) revert NotCallbackTarget();

        address _token = collateralToken;
        uint256 _balance = IERC20(_token).balanceOf(address(this));
        if (_balance > 0) {
            if (isETH) {
                IWETH(_token).withdraw(_balance);
                payable(_trader).sendValue(_balance);
            } else {
                IERC20(_token).safeTransfer(_trader, _balance);
            }
        }

        isWaitingForCallback = false;

        emit ApproveDecreasePosition();
    }

    function rejectDecreasePosition() external nonReentrant {
        if (msg.sender != puppetOrchestrator.getCallbackTarget()) revert NotCallbackTarget();

        isWaitingForCallback = false;

        emit RejectDecreasePosition();
    }

    // ====================== Internal functions ======================

    function _createIncreasePosition(bytes memory _traderData, bytes memory _puppetData) internal {
        (address _collateralToken, address _indexToken, uint256 _amountIn, uint256 _minOut, uint256 _sizeDelta, uint256 _acceptablePrice, uint256 _executionFee)
            = abi.decode(_traderData, (address, address, uint256, uint256, uint256, uint256, uint256));

        address[] memory _path = new address[](1);
        _path[0] = _collateralToken;

        isWaitingForCallback = true;

        bytes32 _referralCode = puppetOrchestrator.getReferralCode();
        address _callbackTarget = puppetOrchestrator.getCallbackTarget();
        bytes32 _positionKey = IGMXPositionRouter(puppetOrchestrator.getGMXPositionRouter()).createIncreasePosition(_path, _indexToken, _amountIn, _minOut, _sizeDelta, routeInfo.isLong, _acceptablePrice, _executionFee, _referralCode, _callbackTarget);

        puppetOrchestrator.updateGMXPositionKeyToTraderRouteAddress(_positionKey);

        emit CreateIncreasePosition(_positionKey, _amountIn, _minOut, _sizeDelta, _acceptablePrice, _executionFee);
    }

    function _createDecreasePosition(bytes memory _traderData, bytes memory _puppetData) internal {
        (address _collateralToken, address _indexToken, uint256 _collateralDeltaUSD, uint256 _sizeDelta, uint256 _acceptablePrice, uint256 _minOut, uint256 _executionFee)
            = abi.decode(_traderData, (address, address, uint256, uint256, uint256, uint256, uint256));

        address[] memory _path = new address[](1);
        _path[0] = _collateralToken;
    
        RouteInfo storage _route = routeInfo;

        isWaitingForCallback = true;
        isWaitingForPuppetRouteCallback = true;

        address _callbackTarget = puppetOrchestrator.getCallbackTarget();
        bytes32 _positionKey = IGMXPositionRouter(puppetOrchestrator.getGMXPositionRouter()).createDecreasePosition(_path, _indexToken, _collateralDeltaUSD, _sizeDelta, _route.isLong, address(this), _acceptablePrice, _minOut, _executionFee, false, _callbackTarget);

        if (puppetOrchestrator.getTraderRouteForPosition(_positionKey) != address(this)) revert KeyError();

        puppetRoute.createDecreasePosition(_puppetData);

        emit CreateDecreasePosition(_positionKey, _minOut, _collateralDeltaUSD, _sizeDelta, _acceptablePrice, _executionFee);
    }

    function _transferFunds(uint256 _amountIn, address _collateralToken, address _trader) internal {
        if (msg.value > 0) {
            address _weth = WETH;
            if (msg.value != _amountIn) revert InvalidValue();
            if (_collateralToken != _weth) revert InvalidCollateralToken();
            IWETH(_weth).deposit{value: _amountIn}();
        } else {
            IERC20(_collateralToken).safeTransferFrom(_trader, address(this), _amountIn);
        }
    }

    function _isOpenInterest() internal view returns (bool) {
        address[] memory _collateralTokens = new address[](1);
        address[] memory _indexTokens = new address[](1);
        bool[] memory _isLong = new bool[](1);

        _collateralTokens[0] = routeInfo.collateralToken;
        _indexTokens[0] = routeInfo.indexToken;
        _isLong[0] = routeInfo.isLong;

        uint256[] memory _response = IGMXReader(puppetOrchestrator.getGMXReader()).getPositions(puppetOrchestrator.getGMXVault(), address(this), _collateralTokens, _indexTokens, _isLong);

        return _response[0] > 0 && _response[1] > 0;
    }
}