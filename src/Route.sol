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
            _requestKey = _createIncreasePosition(_traderPositionData, _traderAmountIn, _puppetsAmountIn, _executionFee);
        } else {
            if (msg.value != _executionFee) revert InvalidExecutionFee();
            _requestKey = _createDecreasePosition(_traderPositionData, _executionFee);
        }

        IPositionValidator(puppetOrchestrator.getPositionValidator()).validatePositionParameters(_traderPositionData, _traderAmountIn, _puppetsAmountIn, _isIncrease);
    }

    // ============================================================================================
    // Keeper Functions
    // ============================================================================================

    function onLiquidation(bytes memory _puppetPositionData) external nonReentrant onlyKeeper {
        if (!_isLiquidated()) revert PositionStillAlive();

        _repayBalance();

        emit Liquidated();
    }

    // ============================================================================================
    // Callback Functions
    // ============================================================================================

    function approvePositionRequest() external override nonReentrant onlyCallbackTarget {
        isWaitingForCallback = false;

        _repayBalance();

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

    function _getPuppetsAmountIn(uint256 _traderAmountIn) internal returns (uint256 _puppetsAmountIn) {
        if (_traderAmountIn > 0) {
            uint256 _totalSupply = totalSupply;
            uint256 _totalAssets = totalAssets;
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

                uint256 _shares = _convertToShares(_totalAssets, _totalSupply, _assets);

                _puppetsAmountIn += _assets;

                EnumerableMap.set(participantShares, _puppet, _shares);

                _totalSupply += _shares;
                _totalAssets += _assets;
            }

            uint256 _traderShares = _convertToShares(_totalAssets, _totalSupply, _traderAmountIn);

            EnumerableMap.set(participantShares, _trader, _traderShares);

            totalSupply = _totalSupply;
            totalAssets = _totalAssets;

            puppetOrchestrator.sendFunds(_puppetsAmountIn);
        }
    }

    function _createIncreasePosition(bytes memory _positionData, uint256 _traderAmountIn, uint256 _puppetsAmountIn, uint256 _executionFee) internal override returns (bytes32 _requestKey) {
        (uint256 _minOut, uint256 _sizeDelta, uint256 _acceptablePrice) = abi.decode(_positionData, (uint256, uint256, uint256));

        address[] memory _path = new address[](1);
        _path[0] = collateralToken;

        uint256 _amountIn = _traderAmountIn + _puppetsAmountIn + _executionFee;

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

    function _createDecreasePosition(bytes memory _positionData, uint256 _executionFee) internal override returns (bytes32 _requestKey) {
        (uint256 _collateralDelta, uint256 _sizeDelta, uint256 _acceptablePrice, uint256 _minOut)
            = abi.decode(_positionData, (uint256, uint256, uint256, uint256));

        address[] memory _path = new address[](1);
        _path[0] = collateralToken;

        _requestKey = IGMXPositionRouter(puppetOrchestrator.getGMXPositionRouter()).createDecreasePosition{ value: _executionFee }(
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
        if (_totalAssets > 0) {
            uint256 _totalSupply = totalSupply;
            uint256 _balance = _totalAssets;
            bytes32 _key = puppetOrchestrator.getRouteKey(trader, collateralToken, indexToken, isLong);
            address[] memory _puppets = puppetOrchestrator.getPuppetsForRoute(_key);
            for (uint256 i = 0; i < _puppets.length; i++) {
                address _puppet = _puppets[i];
                uint256 _shares = EnumerableMap.get(participantShares, _puppet);
                uint256 _assets = _convertToAssets(_balance, _totalSupply, _shares);

                puppetOrchestrator.creditPuppetAccount(_assets, _puppet);

                _totalSupply -= _shares;
                _balance -= _assets;
            }

            uint256 _traderShares = EnumerableMap.get(participantShares, trader);
            uint256 _traderAssets = _convertToAssets(_balance, _totalSupply, _traderShares);

            payable(address(puppetOrchestrator)).sendValue(_totalAssets - _traderAssets);
            payable(trader).sendValue(_traderAssets);
        }

        if (!_isOpenInterest()) {
            _resetPosition();
        }

        emit RepayBalance(_totalAssets);
    }

    function _isOpenInterest() internal view returns (bool) {
        (uint256 _size, uint256 _collateral,,,,,,) = IGMXVault(puppetOrchestrator.getGMXVault()).getPosition(address(this), collateralToken, indexToken, isLong);

        return _size > 0 && _collateral > 0;
    }

    function _resetPosition() internal {
        totalAssets = 0;
        totalSupply = 0;
        for (uint256 i = 0; i < EnumerableMap.length(participantShares); i++) {
            (address _key, ) = EnumerableMap.at(participantShares, i);
            EnumerableMap.remove(participantShares, _key);
        }

        emit ResetPosition();
    }

    function _convertToShares(uint256 _totalAssets, uint256 _totalSupply, uint256 _assets) internal pure returns (uint256 _shares) {
        if (_assets == 0) revert ZeroAmount();

        if (_totalAssets == 0) {
            _shares = _assets;
        } else {
            _shares = (_assets * _totalSupply) / _totalAssets;
        }

        if (_shares == 0) revert ZeroAmount();
    }

    function _convertToAssets(uint256 _totalAssets, uint256 _totalSupply, uint256 _shares) internal pure returns (uint256 _assets) {
        if (_shares == 0) revert ZeroAmount();

        if (_totalSupply == 0) {
            _assets = _shares;
        } else {
            _assets = (_shares * _totalAssets) / _totalSupply;
        }

        if (_assets == 0) revert ZeroAmount();
    }
}