// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/console.sol";

import {IPositionValidator} from "./interfaces/IPositionValidator.sol";

import "./BaseRoute.sol";

contract Route is BaseRoute, IRoute {

    using SafeERC20 for IERC20;
    using Address for address payable;

    // collateral amount trader sent to create position. Used to limit a puppet's position size
    uint256 private traderAmountIn;

    address public trader;

    // indicates whether the puppet position should be increased or decreased
    bool public isPuppetIncrease;
    // indicates whether the puppet position should be created
    bool public isRequestApproved;

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

    function createPosition(bytes memory _traderPositionData, uint256 _executionFee, bool _isIncrease) external payable nonReentrant returns (bytes32 _requestKey) {
        if (isWaitingForCallback) revert WaitingForCallback();
        if (msg.sender != trader) revert NotTrader();
        if (msg.value < _executionFee) revert InvalidExecutionFee();

        isWaitingForCallback = true;

        uint256 _traderAmountIn;
        uint256 _puppetsAmountIn;
        if (_isIncrease) {
            _traderAmountIn = msg.value - _executionFee;
            _puppetsAmountIn = _getPuppetsAmountIn(_traderAmountIn); // get puppets amounts + distribute shares to participants (puppets and trader)    
        } else {
            if (msg.value != _executionFee) revert InvalidExecutionFee();
        }

        IPositionValidator(puppetOrchestrator.getPositionValidator()).validatePositionParameters(_traderPositionData, _traderAmountIn, _puppetsAmountIn, _isIncrease);

        _requestKey = _isIncrease ? _createIncreasePosition(_traderData) : _createDecreasePosition(_traderData);
    }

    function _getPuppetsAmountIn(uint256 _traderAmountIn) internal returns (uint256 _puppetsAmountIn) {
        if (_traderAmountIn > 0) {
            address _trader = trader;
            bytes32 _routeKey = puppetOrchestrator.getRouteKey(_trader, collateralToken, indexToken, isLong);
            address[] memory _puppets = puppetOrchestrator.getPuppetsForRoute(_routeKey);
            for (uint256 i = 0; i < _puppets.length; i++) {
                address _puppet = _puppets[i];
                uint256 _assets = puppetOrchestrator.getPuppetAllowance(_puppet, address(this));

                if (_assets > _traderAmountIn) _assets = _traderAmountIn;

                if (puppetOrchestrator.isPuppetSolvent(_puppet)) {
                    puppetOrchestrator.debitPuppetAccount(_assets, _puppet);
                } else {
                    puppetOrchestrator.liquidatePuppet(_puppet, _routeKey);
                    continue;
                }

                uint256 _shares = _convertToShares(_assets);
                if (_shares == 0 || _assets == 0) revert ZeroAmount();

                _puppetsAmountIn += _assets;

                EnumerableMap.set(participantShares, _puppet, _shares);

                totalSupply += _shares;
                totalAssets += _assets;
            }

            uint256 _traderShares = _convertToShares(_traderAmountIn);

            EnumerableMap.set(participantShares, _trader, _traderShares);

            totalSupply += _traderShares;
            totalAssets += _traderAmountIn;

            puppetOrchestrator.sendFunds(_puppetsAmountIn);
        }
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
    // Keeper Functions
    // ============================================================================================

    /// @notice using a keeper here to avoid GMX PositionRouter reverting on reentrancy
    function createPuppetPosition() external nonReentrant onlyKeeper returns (bytes32 _requestKey) {
        if (!isRequestApproved) revert PositionNotApproved();

        isRequestApproved = false;

        _requestKey = isPuppetIncrease ? puppetRoute.createPosition(puppetPositionData, true) : puppetRoute.createPosition(puppetPositionData, false);

        emit CreatePuppetPosition();
    }

    function onLiquidation(bytes memory _puppetPositionData) external nonReentrant onlyKeeper {
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

        isRequestApproved = true;

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

    function setPuppetRoute(address payable _puppetRoute) external onlyOwner {
        puppetRoute = PuppetRoute(_puppetRoute);
    }

    // ============================================================================================
    // Internal Functions
    // ============================================================================================

    function _createIncreasePosition(bytes memory _positionData) internal override returns (bytes32 _requestKey) {
        (uint256 _minOut, uint256 _sizeDelta, uint256 _acceptablePrice, uint256 _executionFee) = abi.decode(_positionData, (uint256, uint256, uint256, uint256));

        uint256 _amountIn = msg.value;
        traderAmountIn = _amountIn - _executionFee;

        address[] memory _path = new address[](1);
        _path[0] = collateralToken;

        _requestKey = IGMXPositionRouter(puppetOrchestrator.getGMXPositionRouter()).createIncreasePositionETH{ value: _amountIn }(
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

        puppetOrchestrator.updateRequestKeyToRoute(_requestKey);

        emit CreateIncreasePosition(_requestKey, _amountIn, _minOut, _sizeDelta, _acceptablePrice, _executionFee);
    }

    function _createDecreasePosition(bytes memory _positionData) internal override returns (bytes32 _requestKey) {
        (uint256 _collateralDelta, uint256 _sizeDelta, uint256 _acceptablePrice, uint256 _minOut, uint256 _executionFee)
            = abi.decode(_positionData, (uint256, uint256, uint256, uint256, uint256));

        address[] memory _path = new address[](1);
        _path[0] = collateralToken;

        _requestKey = IGMXPositionRouter(puppetOrchestrator.getGMXPositionRouter()).createDecreasePosition{ value: msg.value }(
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

        if (puppetOrchestrator.getRouteForRequestKey(_requestKey) != address(this)) revert KeyError();

        emit CreateDecreasePosition(_requestKey, _minOut, _collateralDelta, _sizeDelta, _acceptablePrice, _executionFee);
    }

    function _repayBalance() internal override {
        uint256 _totalAssets = address(this).balance;
        if (_totalAssets > 0) payable(trader).sendValue(_totalAssets);

        emit RepayBalance(_totalAssets);
    }
}