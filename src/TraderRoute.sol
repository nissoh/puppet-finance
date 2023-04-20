// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IGMXRouter} from "./interfaces/IGMXRouter.sol";
import {IGMXPositionRouter} from "./interfaces/IGMXPositionRouter.sol";

import {IPuppetOrchestrator} from "./interfaces/IPuppetOrchestrator.sol";
import {ITraderRoute} from "./interfaces/ITraderRoute.sol";

// TODO - on position liquidation, clear route

// questions:
    // 1. require the trader's collateral to be x% of the total funds deposited by investors? (e.g. in order to use 1000$ of investors funds, trader will need 10% so 100$)
    // 2. cut trader collateral on loss?
    // 3. limit performance fee to x% of TVL? (to disincentivize over risk taking)
    //
    // one of the first 2 is a must in order to allign incentives on all scenarios. ideally both. but probably only #1 makes sense here
    // #3 might not make sense here


contract TraderRoute is ReentrancyGuard, ITraderRoute {

    using SafeERC20 for IERC20;

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
        EnumerableMap.AddressToUintMap newParticipantShares;
        EnumerableMap.AddressToUintMap creditAmounts;
    }

    RouteInfo private routeInfo;
    PendingDecrease private pendingDecrease;

    IPuppetOrchestrator public puppetOrchestrator;

    uint256 public marginFee = 0.01 ether; // TODO

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

    function _isOpenInterest() internal view returns (bool) {
        // TODO
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

    // TODO
    // function createIncreasePositionETH(bytes memory _positionData, uint256 _traderAmount) external payable {
    //     // wrap ETH and call createIncreasePosition
    //     // make sure _positionData's _collateralToken is WETH
    // }

    // NOTE: on adjusting position:
    // when setting `_sizeDelta`, make sure to account for the fact that puppets do not add collateral to an adjusment in an open position
    // if not, trader will pay for increasing position size of puppets
    function createIncreasePosition(bytes memory _positionData, uint256 _traderAmount) external nonReentrant {
        (address _collateralToken,, uint256 _amountIn,,,,)
            = abi.decode(_positionData, (address, address, uint256, uint256, uint256, uint256, uint256));

        address _trader = msg.sender;

        RouteInfo storage _route = routeInfo;

        if (_route.trader != _trader) revert InvalidCaller();
        if (_route.isWaitingForCallback) revert WaitingForCallback();

        uint256 _totalFunds;
        bool _isPositionOpen = _route.isPositionOpen;
        for (uint256 i = 0; i < EnumerableSet.length(_route.puppetsSet); i++) {
            address _puppet = EnumerableSet.at(_route.puppetsSet, i);
            uint256 _allowance;
            if (!_isPositionOpen) _allowance = EnumerableMap.get(_route.puppetAllowance, _puppet);

            uint256 _amount = _allowance + marginFee; // TODO - marginFee
            if (puppetOrchestrator.isPuppetSolvent(_amount, _collateralToken, _puppet)) {
                puppetOrchestrator.debitPuppetAccount(_puppet, _collateralToken, _amount);
            } else {
                // _liquidate(_puppet); // TODO
                continue;
            }

            if (!_isPositionOpen) _deposit(_route, _puppet, _allowance);

            _totalFunds += _amount;
        }

        _totalFunds += _traderAmount;
        if (_totalFunds != _amountIn) revert InvalidAmountIn();

        _route.traderRequestedCollateralAmount = _traderAmount - marginFee; // TODO - marginFee

        IERC20(_collateralToken).safeTransferFrom(_trader, address(this), _traderAmount);
        IERC20(_collateralToken).safeTransferFrom(address(puppetOrchestrator), address(this), _totalFunds - _traderAmount);

        _createIncreasePosition(_positionData);
    }

    // // TODO - add margin fee handling
    function createDecreasePosition(bytes memory _positionData) external nonReentrant {
        (address _collateralToken,, uint256 _collateralDeltaUSD,,,,)
            = abi.decode(_positionData, (address, address, uint256, uint256, uint256, uint256, uint256));

        address _trader = msg.sender; 
        RouteInfo storage _route = routeInfo;

        if (_route.trader != _trader) revert InvalidCaller();
        if (_route.isWaitingForCallback) revert WaitingForCallback();

        uint256 _collateralDelta;
        if (_collateralDeltaUSD > 0) {
            // TODO: convert _collateralDeltaUSD to _collateralDelta using the exchange rate
            _collateralDelta = _collateralDeltaUSD; // TODO

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
        }

        _createDecreasePosition(_positionData);
    }

    // ====================== request callback ======================

    function approveIncreasePosition() external nonReentrant {
        if (msg.sender != puppetOrchestrator.getCallbackTarget()) revert NotCallbackTarget();

        RouteInfo storage _route = routeInfo;

        _deposit(_route, _route.trader, _route.traderRequestedCollateralAmount);

        _route.isPositionOpen = true;
        _route.isWaitingForCallback = false;
        _route.traderRequestedCollateralAmount = 0;

        emit ApproveIncreasePosition();
    }

    function rejectIncreasePosition() external nonReentrant {
        if (msg.sender != puppetOrchestrator.getCallbackTarget()) revert NotCallbackTarget();

        RouteInfo storage _route = routeInfo;

        uint256 _amount;
        uint256 _totalPuppetsCredit;
        bool _isPositionOpen = _route.isPositionOpen;
        for (uint256 i = 0; i < EnumerableSet.length(_route.puppetsSet); i++) {
            address _puppet = EnumerableSet.at(_route.puppetsSet, i);
            _amount = marginFee; // TODO - marginFee

            if (!_isPositionOpen) _amount += EnumerableMap.get(_route.puppetAllowance, _puppet);

            _totalPuppetsCredit += _amount;
            puppetOrchestrator.creditPuppetAccount(_puppet, _route.collateralToken, _amount);
        }

        _amount = _route.traderRequestedCollateralAmount + marginFee; // TODO - marginFee

        _route.isWaitingForCallback = false;
        _route.traderRequestedCollateralAmount = 0;

        if (!_isPositionOpen) {
            _route.totalAmount = 0;
            _route.totalSupply = 0;
            for (uint256 i = 0; i < EnumerableMap.length(_route.participantShares); i++) {
                (address _key, ) = EnumerableMap.at(_route.participantShares, i);
                EnumerableMap.remove(_route.participantShares, _key);
            }
        }

        IERC20(_route.collateralToken).safeTransfer(address(puppetOrchestrator), _totalPuppetsCredit);
        IERC20(_route.collateralToken).safeTransfer(_route.trader, _amount);

        emit RejectIncreasePosition(_totalPuppetsCredit, _amount);
    }

    function approveDecreasePosition() external nonReentrant {
        if (msg.sender != puppetOrchestrator.getCallbackTarget()) revert NotCallbackTarget();

        RouteInfo storage _route = routeInfo;
        PendingDecrease storage _pendingDecrease = pendingDecrease;

        _route.totalAmount = _pendingDecrease.totalAmount;
        _route.totalSupply = _pendingDecrease.totalSupply;

        uint256 _newParticipantShares;
        uint256 _creditAmount;
        for (uint256 i = 0; i < EnumerableSet.length(_route.puppetsSet); i++) {
            address _puppet = EnumerableSet.at(_route.puppetsSet, i);
            _newParticipantShares = EnumerableMap.get(_pendingDecrease.newParticipantShares, _puppet);
            _creditAmount = EnumerableMap.get(_pendingDecrease.creditAmounts, _puppet);

            EnumerableMap.set(_route.participantShares, _puppet, _newParticipantShares);
            puppetOrchestrator.creditPuppetAccount(_puppet, _route.collateralToken, _creditAmount);
        }

        _newParticipantShares = EnumerableMap.get(_pendingDecrease.newParticipantShares, _route.trader);
        _creditAmount = EnumerableMap.get(_pendingDecrease.creditAmounts, _route.trader);

        EnumerableMap.set(_route.participantShares, _route.trader, _newParticipantShares);

        _route.isWaitingForCallback = false;
        if (!_isOpenInterest()) _route.isPositionOpen = false;

        IERC20(_route.collateralToken).safeTransfer(_route.trader, _creditAmount);

        emit ApproveDecreasePosition();
    }

    // TODO - credit margin fee
    function rejectDecreasePosition() external nonReentrant {
        if (msg.sender != puppetOrchestrator.getCallbackTarget()) revert NotCallbackTarget();

        RouteInfo storage _route = routeInfo;

        uint256 _totalPuppetsCredit;
        uint256 _creditAmount = marginFee; // TODO - marginFee
        for (uint256 i = 0; i < EnumerableSet.length(_route.puppetsSet); i++) {
            address _puppet = EnumerableSet.at(_route.puppetsSet, i);

            puppetOrchestrator.creditPuppetAccount(_puppet, _route.collateralToken, _creditAmount);
            _totalPuppetsCredit += _creditAmount;
        }

        _route.isWaitingForCallback = false;

        IERC20(_route.collateralToken).safeTransfer(address(puppetOrchestrator), _totalPuppetsCredit);
        IERC20(_route.collateralToken).safeTransfer(_route.trader, _creditAmount);

        emit RejectDecreasePosition(_totalPuppetsCredit, _creditAmount);
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