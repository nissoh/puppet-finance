// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {IGMXRouter} from "./interfaces/IGMXRouter.sol";
import {IGMXReader} from "./interfaces/IGMXReader.sol";
import {IGMXPositionRouter} from "./interfaces/IGMXPositionRouter.sol";
import {IWETH} from "./interfaces/IWETH.sol";

import {IPuppetOrchestrator} from "./interfaces/IPuppetOrchestrator.sol";
import {IRoute} from "./interfaces/IRoute.sol";

contract BaseRoute is ReentrancyGuard, IRoute {

    using SafeERC20 for IERC20;
    using Address for address payable;

    struct RouteInfo {
        uint256 totalAmount;
        uint256 totalSupply;
        uint256 traderRequestedCollateralAmount;
        address trader;
        address collateralToken;
        address indexToken;
        bool isLong;
        bool isPositionOpen;
        bool isWaitingForCallback;
        EnumerableMap.AddressToUintMap participantShares;
        EnumerableMap.AddressToUintMap puppetAllowance;
        EnumerableSet.AddressSet puppetsSet;
    }

    struct PendingDecrease {
        uint256 totalAmount;
        uint256 totalSupply;
        bool isCollateralDeltaPositive;
        bool isETH;
        EnumerableMap.AddressToUintMap newParticipantShares;
        EnumerableMap.AddressToUintMap creditAmounts;
    }

    RouteInfo private routeInfo;
    PendingDecrease private pendingDecrease;

    IPuppetOrchestrator public puppetOrchestrator;

    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    // ====================== Constructor ======================

    constructor(address _trader, address _collateralToken, address _indexToken, bool _isLong) {
        puppetOrchestrator = IPuppetOrchestrator(msg.sender);

        routeInfo.trader = _trader;
        routeInfo.collateralToken = _collateralToken;
        routeInfo.indexToken = _indexToken;
        routeInfo.isLong = _isLong;

        IGMXRouter(puppetOrchestrator.getGMXRouter()).approvePlugin(puppetOrchestrator.getGMXPositionRouter());
    }

    // ====================== Helper functions ======================

    function isWaitingForCallback() external view returns (bool) {
        return routeInfo.isWaitingForCallback;
    }

    function isPositionOpen() public view returns (bool) {
        return routeInfo.isPositionOpen;
    }

    function isPuppetSigned(address _puppet) external view returns (bool) {
        return EnumerableSet.contains(routeInfo.puppetsSet, _puppet);
    }

    function convertToShares(uint256 _totalAmount, uint256 _totalSupply, uint256 _amount) public pure returns (uint256 _shares) {
        if (_totalAmount == 0) {
            _shares = _amount;
        } else {
            _shares = (_amount * _totalSupply) / _totalAmount;
        }
    }

    function convertToAmount(uint256 _totalAmount, uint256 _totalSupply, uint256 _shares) public pure returns (uint256 _amount) {
        if (_totalSupply == 0) {
            _amount = _shares;
        } else {
            _amount = (_shares * _totalAmount) / _totalSupply;
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

        // TODO - make sure that's correct
        // console.log("position size in USD", _response[0]);
        // console.log("position collateral in USD", _response[1]);

        return _response[0] > 0 && _response[1] > 0;
    }

    // ====================== Puppet orchestrator functions ======================

    function signPuppet(address _puppet, uint256 _allowance) external nonReentrant {
        if (msg.sender != address(puppetOrchestrator)) revert Unauthorized();
        if (routeInfo.isWaitingForCallback) revert WaitingForCallback();
        if (isPositionOpen()) revert PositionIsOpen();

        bool _isPresent = EnumerableSet.add(routeInfo.puppetsSet, _puppet);
        if (_isPresent) revert PuppetAlreadySigned();

        EnumerableMap.set(routeInfo.puppetAllowance, _puppet, _allowance);
    }

    function unsignPuppet(address _puppet) external nonReentrant {
        if (msg.sender != address(puppetOrchestrator)) revert Unauthorized();
        if (routeInfo.isWaitingForCallback) revert WaitingForCallback();
        if (isPositionOpen()) revert PositionIsOpen();

        bool _isPresent = EnumerableSet.remove(routeInfo.puppetsSet, _puppet);
        if (!_isPresent) revert PuppetNotSigned();
    }

    function setAllowance(address _puppet, uint256 _allowance) external nonReentrant {
        if (msg.sender != address(puppetOrchestrator)) revert Unauthorized();
        if (routeInfo.isWaitingForCallback) revert WaitingForCallback();
        if (isPositionOpen()) revert PositionIsOpen();

        EnumerableMap.set(routeInfo.puppetAllowance, _puppet, _allowance);
    }

    // ====================== Trader functions ======================

    // NOTE: on adjusting position:
    // when setting `_sizeDelta`, make sure to account for the fact that puppets do not add collateral to an adjusment in an open position
    function createIncreasePosition(bytes memory _positionData, uint256 _traderAmount, bool _isETH) external payable nonReentrant {
        (address _collateralToken,, uint256 _amountIn,,,,)
            = abi.decode(_positionData, (address, address, uint256, uint256, uint256, uint256, uint256));

        if (_isETH) {
            address _weth = WETH;
            if (!(msg.value > 0)) revert InvalidValue();
            if (msg.value != _amountIn) revert InvalidValue();
            if (_collateralToken != _weth) revert InvalidCollateralToken();

            IWETH(_weth).deposit{value: _amountIn}();
        } else {
            if (msg.value != 0) revert InvalidValue();
        }

        address _trader = msg.sender;

        RouteInfo storage _route = routeInfo;

        if (_route.trader != _trader) revert InvalidCaller();
        if (_route.isWaitingForCallback) revert WaitingForCallback();

        uint256 _puppetsTotalAmount;
        bool _isPositionOpen = _route.isPositionOpen;
        if (!_isPositionOpen) {
            for (uint256 i = 0; i < EnumerableSet.length(_route.puppetsSet); i++) {
                address _puppet = EnumerableSet.at(_route.puppetsSet, i);
                uint256 _allowance = EnumerableMap.get(_route.puppetAllowance, _puppet);

                // if (_allowance > _traderAmount) _allowance = _traderAmount; // TODO - limit allowance to trader amount

                if (puppetOrchestrator.isPuppetSolvent(_allowance, _collateralToken, _puppet)) {
                    puppetOrchestrator.debitPuppetAccount(_allowance, _puppet, _collateralToken);
                } else {
                    _liquidate(_puppet);
                    // i = i - 1;
                    continue;
                }

                _deposit(_route, _puppet, _allowance);

                _puppetsTotalAmount += _allowance;
            }
        }

        if ((_puppetsTotalAmount + _traderAmount) != _amountIn) revert InvalidAmountIn();

        _route.traderRequestedCollateralAmount = _traderAmount;

        if (_puppetsTotalAmount > 0) IERC20(_collateralToken).safeTransferFrom(address(puppetOrchestrator), address(this), _puppetsTotalAmount);
        if (_traderAmount > 0) IERC20(_collateralToken).safeTransferFrom(_trader, address(this), _traderAmount);

        _createIncreasePosition(_positionData);
    }

    function createDecreasePosition(bytes memory _positionData, bool _isETH) external nonReentrant {
        (address _collateralToken,, uint256 _collateralDeltaUSD,,,,)
            = abi.decode(_positionData, (address, address, uint256, uint256, uint256, uint256, uint256));

        if (_isETH && _collateralToken != WETH) revert InvalidCollateralToken();

        address _trader = msg.sender; 
        RouteInfo storage _route = routeInfo;

        if (_route.trader != _trader) revert InvalidCaller();
        if (_route.isWaitingForCallback) revert WaitingForCallback();

        uint256 _collateralDelta;
        if (_collateralDeltaUSD > 0) {
            // TODO: convert _collateralDeltaUSD to _collateralDelta using the exchange rate
            _collateralDelta = _collateralDeltaUSD;

            uint256 _totalSharesToBurn = convertToShares(_route.totalAmount, _route.totalSupply, _collateralDelta);

            PendingDecrease storage _pendingDecrease = pendingDecrease;

            uint256 _shares;
            uint256 _sharesToBurn;
            uint256 _amountToCredit;
            for (uint256 i = 0; i < EnumerableSet.length(_route.puppetsSet); i++) {
                address _puppet = EnumerableSet.at(_route.puppetsSet, i);
                _shares = EnumerableMap.get(_route.participantShares, _puppet);
                _sharesToBurn = (_shares * _totalSharesToBurn) / _route.totalSupply;
                _amountToCredit = convertToAmount(_route.totalAmount, _route.totalSupply, _sharesToBurn);

                EnumerableMap.set(_pendingDecrease.newParticipantShares, _puppet, _shares - _sharesToBurn);
                EnumerableMap.set(_pendingDecrease.creditAmounts, _puppet, _amountToCredit);
            }

            _shares = EnumerableMap.get(_route.participantShares, _trader);
            _sharesToBurn = (_shares * _totalSharesToBurn) / _route.totalSupply;
            _amountToCredit = convertToAmount(_route.totalAmount, _route.totalSupply, _sharesToBurn);

            EnumerableMap.set(_pendingDecrease.newParticipantShares, _trader, _shares - _sharesToBurn);
            EnumerableMap.set(_pendingDecrease.creditAmounts, _trader, _amountToCredit);

            _pendingDecrease.totalAmount = _route.totalAmount - _collateralDelta;
            _pendingDecrease.totalSupply = _route.totalSupply - _totalSharesToBurn;

            _pendingDecrease.isCollateralDeltaPositive = true;
            _pendingDecrease.isETH = _isETH;
        }

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

        RouteInfo storage _route = routeInfo;

        uint256 _traderRequestedCollateralAmount = _route.traderRequestedCollateralAmount;
        if (_traderRequestedCollateralAmount > 0) _deposit(_route, _route.trader, _traderRequestedCollateralAmount);

        _route.isPositionOpen = true;
        _route.isWaitingForCallback = false;
        _route.traderRequestedCollateralAmount = 0;

        emit ApproveIncreasePosition();
    }

    function rejectIncreasePosition() external nonReentrant {
        if (msg.sender != puppetOrchestrator.getCallbackTarget()) revert NotCallbackTarget();

        RouteInfo storage _route = routeInfo;

        uint256 _puppetsTotalAmount;
        bool _isPositionOpen = _route.isPositionOpen;
        if (!_isPositionOpen) {
            for (uint256 i = 0; i < EnumerableSet.length(_route.puppetsSet); i++) {
                address _puppet = EnumerableSet.at(_route.puppetsSet, i);
                uint256 _allowance = EnumerableMap.get(_route.puppetAllowance, _puppet);

                _puppetsTotalAmount += _allowance;
                puppetOrchestrator.creditPuppetAccount(_allowance, _puppet, _route.collateralToken);
            }

            _route.totalAmount = 0;
            _route.totalSupply = 0;
            for (uint256 i = 0; i < EnumerableMap.length(_route.participantShares); i++) {
                (address _key, ) = EnumerableMap.at(_route.participantShares, i);
                EnumerableMap.remove(_route.participantShares, _key);
            }
        }

        uint256 _traderRequestedCollateralAmount = _route.traderRequestedCollateralAmount;

        _route.isWaitingForCallback = false;
        _route.traderRequestedCollateralAmount = 0;

        if (_puppetsTotalAmount > 0) IERC20(_route.collateralToken).safeTransfer(address(puppetOrchestrator), _puppetsTotalAmount);
        if (_traderRequestedCollateralAmount > 0) IERC20(_route.collateralToken).safeTransfer(_route.trader, _traderRequestedCollateralAmount);

        emit RejectIncreasePosition(_puppetsTotalAmount, _traderRequestedCollateralAmount);
    }

    function approveDecreasePosition() external nonReentrant {
        if (msg.sender != puppetOrchestrator.getCallbackTarget()) revert NotCallbackTarget();

        RouteInfo storage _route = routeInfo;
        PendingDecrease storage _pendingDecrease = pendingDecrease;

        _route.isWaitingForCallback = false;

        if(_pendingDecrease.isCollateralDeltaPositive) {
            _route.totalAmount = _pendingDecrease.totalAmount;
            _route.totalSupply = _pendingDecrease.totalSupply;

            uint256 _newParticipantShares;
            uint256 _creditAmount;
            uint256 _totalPuppetsCreditAmount;
            for (uint256 i = 0; i < EnumerableSet.length(_route.puppetsSet); i++) {
                address _puppet = EnumerableSet.at(_route.puppetsSet, i);
                _newParticipantShares = EnumerableMap.get(_pendingDecrease.newParticipantShares, _puppet);
                _creditAmount = EnumerableMap.get(_pendingDecrease.creditAmounts, _puppet);

                EnumerableMap.set(_route.participantShares, _puppet, _newParticipantShares);
                puppetOrchestrator.creditPuppetAccount(_creditAmount, _puppet, _route.collateralToken);

                _totalPuppetsCreditAmount += _creditAmount;
            }

            _newParticipantShares = EnumerableMap.get(_pendingDecrease.newParticipantShares, _route.trader);
            _creditAmount = EnumerableMap.get(_pendingDecrease.creditAmounts, _route.trader);

            EnumerableMap.set(_route.participantShares, _route.trader, _newParticipantShares);

            if (!_isOpenInterest()) _route.isPositionOpen = false;
            _pendingDecrease.isCollateralDeltaPositive = false;

            IERC20(_route.collateralToken).safeTransfer(address(puppetOrchestrator), _totalPuppetsCreditAmount);
            if (_pendingDecrease.isETH) {
                IWETH(WETH).withdraw(_creditAmount);
                payable(_route.trader).sendValue(_creditAmount);
            } else {
                IERC20(_route.collateralToken).safeTransfer(_route.trader, _creditAmount);
            }
        }

        emit ApproveDecreasePosition();
    }

    function rejectDecreasePosition() external nonReentrant {
        if (msg.sender != puppetOrchestrator.getCallbackTarget()) revert NotCallbackTarget();

        routeInfo.isWaitingForCallback = false;

        emit RejectDecreasePosition();
    }

    // ====================== Internal functions ======================

    function _createIncreasePosition(bytes memory _positionData) internal {
        (address _collateralToken, address _indexToken, uint256 _amountIn, uint256 _minOut, uint256 _sizeDelta, uint256 _acceptablePrice, uint256 _executionFee)
            = abi.decode(_positionData, (address, address, uint256, uint256, uint256, uint256, uint256));

        address[] memory _path = new address[](1);
        _path[0] = _collateralToken;

        routeInfo.isWaitingForCallback = true;

        bytes32 _referralCode = puppetOrchestrator.getReferralCode();
        address _callbackTarget = puppetOrchestrator.getCallbackTarget();
        bytes32 _positionKey = IGMXPositionRouter(puppetOrchestrator.getGMXPositionRouter()).createIncreasePosition(_path, _indexToken, _amountIn, _minOut, _sizeDelta, routeInfo.isLong, _acceptablePrice, _executionFee, _referralCode, _callbackTarget);

        puppetOrchestrator.updateGMXPositionKeyToTraderRouteAddress(_positionKey);

        // TODO - if (_amountIn > 0 && isPositionOpen) (collateral is added to an exsisting position) --> 
        // call _decidePositionSizeDelta(), only if it's (_sizeDelta > 0), and make sure (_collateralDeltaUSD == 0)
        // if (_amountIn > 0 && routeInfo.isPositionOpen) {

        // }

        emit CreateIncreasePosition(_positionKey, _amountIn, _minOut, _sizeDelta, _acceptablePrice, _executionFee);
    }

    function _createDecreasePosition(bytes memory _positionData) internal {
        (address _collateralToken, address _indexToken, uint256 _collateralDeltaUSD, uint256 _sizeDelta, uint256 _acceptablePrice, uint256 _minOut, uint256 _executionFee)
            = abi.decode(_positionData, (address, address, uint256, uint256, uint256, uint256, uint256));

        address[] memory _path = new address[](1);
        _path[0] = _collateralToken;
    
        RouteInfo storage _route = routeInfo;

        _route.isWaitingForCallback = true;

        address _callbackTarget = puppetOrchestrator.getCallbackTarget();
        bytes32 _positionKey = IGMXPositionRouter(puppetOrchestrator.getGMXPositionRouter()).createDecreasePosition(_path, _indexToken, _collateralDeltaUSD, _sizeDelta, _route.isLong, address(this), _acceptablePrice, _minOut, _executionFee, false, _callbackTarget);

        if (puppetOrchestrator.getTraderRouteForPosition(_positionKey) != address(this)) revert KeyError();

        emit CreateDecreasePosition(_positionKey, _minOut, _collateralDeltaUSD, _sizeDelta, _acceptablePrice, _executionFee);
    }

    function _liquidate(address _puppet) internal {
        EnumerableSet.remove(routeInfo.puppetsSet, _puppet);
        EnumerableMap.set(routeInfo.puppetAllowance, _puppet, 0);
        
        emit Liquidate(_puppet);
    } 

    function _deposit(RouteInfo storage _route, address _account, uint256 _amount) internal {
        uint256 _shares = convertToShares(_route.totalAmount, _route.totalSupply, _amount);

        if (!(_amount > 0)) revert ZeroAmount();
        if (!(_shares > 0)) revert ZeroAmount();

        EnumerableMap.set(_route.participantShares, _account, EnumerableMap.get(_route.participantShares, _account) + _shares);

        _route.totalAmount += _amount;
        _route.totalSupply += _shares;

        emit Deposit(_account, _amount, _shares);
    }
}