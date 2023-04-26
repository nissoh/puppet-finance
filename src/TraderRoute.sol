// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {PuppetRoute} from "./PuppetRoute.sol";
import {IPositionValidator} from "./interfaces/IPositionValidator.sol";

import "./BaseRoute.sol";

contract TraderRoute is BaseRoute, ITraderRoute {

    using SafeERC20 for IERC20;
    using Address for address payable;

    // collateral amount trader sent to create position. Used to limit a puppet's position size
    uint256 private traderAmountIn;

    address public trader;

    // indicates if the puppet position should be increased or decreased
    bool public isPuppetIncrease;

    // the data to pass to the puppet createPosition function
    bytes private puppetPositionData;

    IPuppetRoute public puppetRoute;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    constructor(
        address _puppetOrchestrator,
        address _owner,
        address _trader,
        address _collateralToken,
        address _indexToken,
        bool _isLong
        ) BaseRoute(_puppetOrchestrator, _owner, _collateralToken, _indexToken, _isLong) {

        puppetRoute = new PuppetRoute(_puppetOrchestrator, _trader, _owner, _collateralToken, _indexToken, _isLong);

        trader = _trader;
    }

    // ============================================================================================
    // View Functions
    // ============================================================================================

    function getTraderAmountIn() external view returns (uint256) {
        return traderAmountIn;
    }

    function getPuppetRoute() external view returns (address) {
        return address(puppetRoute);
    }

    function getIsWaitingForCallback() external view returns (bool) {
        return isWaitingForCallback;
    }

    // ============================================================================================
    // Trader Functions
    // ============================================================================================

    function createPosition(bytes memory _traderData, bytes memory _puppetsData, bool _isIncrease, bool _isPuppetIncrease) external payable nonReentrant {
        if (isWaitingForCallback) revert WaitingForCallback();
        if (msg.sender != trader) revert NotTrader();

        puppetPositionData = _puppetsData;
        isWaitingForCallback = true;
        isPuppetIncrease = _isPuppetIncrease;

        IPositionValidator(puppetOrchestrator.getPositionValidator()).validatePositionParameters(_traderData, _puppetsData, _isIncrease, _isPuppetIncrease);

        _isIncrease ? _createIncreasePosition(_traderData) : _createDecreasePosition(_traderData);
    }

    // ============================================================================================
    // PuppetRoute Functions
    // ============================================================================================

    function notifyCallback() external nonReentrant {
        if (msg.sender != owner && msg.sender != address(puppetRoute)) revert NotPuppetRoute();

        isWaitingForCallback = false;

        emit NotifyCallback();
    }

    // ============================================================================================
    // On Liquidation
    // ============================================================================================

    function onLiquidation(bytes memory _puppetPositionData) external nonReentrant {
        if (msg.sender != owner && msg.sender != puppetOrchestrator.getKeeper()) revert NotKeeper();
        if (!_isLiquidated()) revert PositionStillAlive();

        _repayBalance();

        puppetRoute.closePosition(_puppetPositionData);

        emit Liquidated();
    }

    // ============================================================================================
    // Callback Functions
    // ============================================================================================

    function approvePositionRequest() external override nonReentrant onlyCallbackTarget {
        _repayBalance();

        isPuppetIncrease ? puppetRoute.createPosition(puppetPositionData, true) : puppetRoute.createPosition(puppetPositionData, false);

        emit ApprovePositionRequest();
    }

    function rejectPositionRequest() external override nonReentrant onlyCallbackTarget {
        isWaitingForCallback = false;

        _repayBalance();

        emit RejectPositionRequest();
    }

    // ============================================================================================
    // Owner Functions
    // ============================================================================================

    function setPuppetRoute(address _puppetRoute) external onlyOwner {
        puppetRoute = PuppetRoute(_puppetRoute);
    }

    // ============================================================================================
    // Internal Functions
    // ============================================================================================

    function _createIncreasePosition(bytes memory _positionData) internal override {
        (uint256 _minOut, uint256 _sizeDelta, uint256 _acceptablePrice, uint256 _executionFee) = abi.decode(_positionData, (uint256, uint256, uint256, uint256));

        uint256 _amountIn = msg.value;
        traderAmountIn = _amountIn - _executionFee;

        address[] memory _path = new address[](1);
        _path[0] = collateralToken;

        bytes32 _positionKey = IGMXPositionRouter(puppetOrchestrator.getGMXPositionRouter()).createIncreasePositionETH{ value: _amountIn }(
            _path,
            indexToken,
            _minOut,
            _sizeDelta,
            isLong,
            _acceptablePrice,
            _executionFee,
            puppetOrchestrator.getReferralCode(),
            puppetOrchestrator.getCallbackTarget()
        );

        puppetOrchestrator.updatePositionKeyToTraderRoute(_positionKey);

        emit CreateIncreasePosition(_positionKey, _amountIn, _minOut, _sizeDelta, _acceptablePrice, _executionFee);
    }

    function _createDecreasePosition(bytes memory _positionData) internal override {
        (uint256 _collateralDelta, uint256 _sizeDelta, uint256 _acceptablePrice, uint256 _minOut, uint256 _executionFee)
            = abi.decode(_positionData, (uint256, uint256, uint256, uint256, uint256));

        address[] memory _path = new address[](1);
        _path[0] = collateralToken;

        bytes32 _positionKey = IGMXPositionRouter(puppetOrchestrator.getGMXPositionRouter()).createDecreasePosition{ value: msg.value }(
            _path,
            indexToken,
            _collateralDelta,
            _sizeDelta,
            isLong,
            address(this), // _receiver
            _acceptablePrice,
            _minOut,
            _executionFee,
            true, // _withdrawETH
            puppetOrchestrator.getCallbackTarget()
        );

        if (puppetOrchestrator.getRouteForPositionKey(_positionKey) != address(this)) revert KeyError();

        emit CreateDecreasePosition(_positionKey, _minOut, _collateralDelta, _sizeDelta, _acceptablePrice, _executionFee);
    }

    function _repayBalance() internal override {
        uint256 _totalAssets = address(this).balance;
        if (_totalAssets > 0) payable(trader).sendValue(_totalAssets);

        emit RepayBalance(_totalAssets);
    }
}