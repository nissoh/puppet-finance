// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {TraderRoute} from "./TraderRoute.sol";

import {IGMXRouter} from "./interfaces/IGMXRouter.sol";
import {IGMXPositionRouter} from "./interfaces/IGMXPositionRouter.sol";
import {IPuppetOrchestrator} from "./interfaces/IPuppetOrchestrator.sol";
import {ITraderRoute} from "./interfaces/ITraderRoute.sol";

contract PuppetOrchestrator is ReentrancyGuard, IPuppetOrchestrator {

    using SafeERC20 for IERC20;

    // struct PendingDecrease {
    //     uint256 totalAmount;
    //     uint256 totalSupply;
    //     EnumerableMap.AddressToUintMap newParticipantShares;
    //     EnumerableMap.AddressToUintMap creditAmounts;
    // }

    // uint256 public marginFee = 0.01 ether; // TODO

    address public gmxRouter;
    address public gmxPositionRouter;
    address public callbackTarget;

    bytes32 public referralCode;

    // mapping(bytes32 => RouteInfo) private routeInfo;
    // mapping(bytes32 => PendingDecrease) public pendingDecreases;
    // mapping(bytes32 => bytes32) private gmxPositionKeyToRouteKey;

    // mapping(bytes32 => TraderRoute) public traderRoute; // TODO
    mapping(bytes32 => address) public traderRoute;

    // token => puppet => balance
    mapping(address => mapping(address => uint256)) public puppetDepositAccount;

    // ====================== Constructor ======================

    constructor(address _gmxRouter, address _gmxPositionRouter, address _callbackTarget, bytes32 _referralCode) {
        callbackTarget = _callbackTarget;
        referralCode = _referralCode;

        gmxRouter = _gmxRouter;
        gmxPositionRouter = _gmxPositionRouter;
    }

    // ====================== View Functions ======================

    function getGMXRouter() external view override returns (address) {
        return gmxRouter;
    }

    function getGMXPositionRouter() external view override returns (address) {
        return gmxPositionRouter;
    }

    function getCallbackTarget() external view override returns (address _callbackTarget) {
        return callbackTarget;
    }

    function getReferralCode() external view override returns (bytes32 _referralCode) {
        return referralCode;
    }

    function isPuppetSolvent(uint256 _amount, address _puppet) external view override returns (bool _isSolvent) {
        // TODO
    }

    // ====================== Accounting Helpers ======================

    function debitPuppetAccount(address _puppet, address _token, uint256 _amount) external override nonReentrant {
        // TODO
    }

    // ====================== Trader Functions ======================

    function registerRoute(address _collateralToken, address _indexToken, bool _isLong) external nonReentrant returns (bytes32 _routeKey) {
        address _trader = msg.sender;
        bytes32 _routeKey = getPositionKey(_trader, _collateralToken, _indexToken, _isLong);
        if (traderRoute[_routeKey] != address(0)) revert RouteAlreadyRegistered();

        address _routeAddress = address(new TraderRoute(_trader, _collateralToken, _indexToken, _isLong));

        traderRoute[_routeKey] = _routeAddress;

        emit RegisterRoute(_trader, _routeAddress, _collateralToken, _indexToken, _isLong);
    }

    // // TODO - add margin fee handling
    // function createDecreasePosition(bytes memory _positionData) external nonReentrant {
    //     (address[] memory _path, address _indexToken, uint256 _collateralDeltaUSD, uint256 _sizeDelta, bool _isLong, address _receiver, uint256 _acceptablePrice, uint256 _minOut, uint256 _executionFee, bool _withdrawETH)
    //         = abi.decode(_positionData, (address[], address, uint256, uint256, bool, address, uint256, uint256, uint256, bool));

    //     address _trader = msg.sender;
    //     bytes32 _routeKey = getPositionKey(_trader, _path[_path.length - 1], _indexToken, _isLong);
    //     RouteInfo storage _route = routeInfo[_routeKey];
    //     if (!_route.isRegistered) revert RouteNotRegistered();
    //     if (_route.trader != _trader) revert InvalidCaller();
    //     if (_route.isWaitingForCallback) revert RouteIsWaitingForCallback();

    //     uint256 _collateralDelta;
    //     if (_collateralDeltaUSD > 0) {
    //         // TODO: convert _collateralDeltaUSD to _collateralDelta using the exchange rate
    //         _collateralDelta = _collateralDeltaUSD; // TODO

    //         uint256 _totalSharesToBurn = convertToShares(_route.totalAmount, _route.totalSupply, _collateralDelta);

    //         PendingDecrease storage _pendingDecrease;

    //         uint256 _shares;
    //         uint256 _sharesToBurn;
    //         uint256 _amountToCredit;
    //         for (uint256 i = 0; i < puppetsSet.length(); i++) {
    //             address _puppet = puppetsSet.at(i);
    //             _shares = EnumerableMap.get(_route.participantShares, _puppet);
    //             _sharesToBurn = (_shares * _totalSharesToBurn) / _route.totalSupply;
    //             _amountToCredit = convertToAmount(_route.totalAmount, _route.totalSupply, _sharesToBurn);

    //             EnumerableMap.set(_pendingDecrease.newParticipantShares, _puppet, _shares - _sharesToBurn);
    //             EnumerableMap.set(_pendingDecrease.creditAmounts, _puppet, _amountToCredit);
    //         }

    //         _shares = EnumerableMap.get(_route.participantShares, _trader);
    //         _sharesToBurn = (_shares * _totalSharesToBurn) / _route.totalSupply;
    //         _amountToCredit = convertToAmount(_route.totalAmount, _route.totalSupply, _sharesToBurn);

    //         EnumerableMap.set(_pendingDecrease.newParticipantShares, _trader, _shares - _sharesToBurn);
    //         EnumerableMap.set(_pendingDecrease.creditAmounts, _trader, _amountToCredit);

    //         _pendingDecrease.totalAmount = _route.totalAmount - _collateralDelta;
    //         _pendingDecrease.totalSupply = _route.totalSupply - _totalSharesToBurn;

    //         pendingDecreases[_positionKey] = _pendingDecrease;
    //     }

    //     _createDecreasePosition(_positionData, _routeKey);
    //     // bytes32 _positionKey = IGMXPositionRouter(gmxPositionRouter).createDecreasePosition(_path, _indexToken, _collateralDelta, _sizeDelta, _isLong, _receiver, _acceptablePrice, _minOut, _executionFee, _withdrawETH, referralCode, callbackTarget);

    //     // gmxPositionKeyToRouteKey[_positionKey] = _routeKey;
    //     // _route.isWaitingForCallback = true;
    // }

    // function creditBalance(address _account, uint256 _amount) private {
    //     // TODO: Implement the logic to credit the balance of _account with _amount
    // }

    // ====================== Puppet Functions ======================

    function depositToAccount(uint256 _amount, address _token, address _puppet) external nonReentrant {
        puppetDepositAccount[_token][_puppet] += _amount;

        address _caller = msg.sender;
        IERC20(_token).safeTransferFrom(_caller, address(this), _amount);

        emit DepositToAccount(_amount, _token, _caller, _puppet);
    }

    function toggleRouteSubscription(address[] memory _traders, uint256[] memory _allowances, address _collateralToken, address _indexToken, bool _isLong, bool _sign) external nonReentrant {
        bytes32 _routeKey;
        address _puppet = msg.sender;
        for (uint256 i = 0; i < _traders.length; i++) {
            _routeKey = getPositionKey(_traders[i], _collateralToken, _indexToken, _isLong);
            address _route = traderRoute[_routeKey];
            if (_route == address(0)) revert RouteNotRegistered();

            bool _isPresent;
            if (_sign) {
                _isPresent = ITraderRoute(_route).signPuppet(_puppet, _allowances[i]);
                if (_isPresent) revert PuppetAlreadySigned();
            } else {
                _isPresent = ITraderRoute(_route).unsignPuppet(_puppet);
                if (!_isPresent) revert PuppetNotSigned();
            }
        }

        emit PuppetToggleSubscription(_traders, _allowances, _puppet, _collateralToken, _indexToken, _isLong, _sign);
    }

    function setTraderAllowance(bytes32[] memory _routeKeys, uint256[] memory _allowances) external nonReentrant {
        address _puppet = msg.sender;
        for (uint256 i = 0; i < _routeKeys.length; i++) {
            address _route = traderRoute[_routeKeys[i]];
            if (_route == address(0)) revert RouteNotRegistered();
            if (ITraderRoute(_route).isWaitingForCallback()) revert WaitingForCallback();
            if (ITraderRoute(_route).isPuppetSigned(_puppet)) revert PuppetNotSigned();
            if (ITraderRoute(_route).isPositionOpen()) revert PositionOpen();

            ITraderRoute(_route).setAllowance(_puppet, _allowances[i]);
        }

        emit PuppetSetAllowance(_routeKeys, _allowances, _puppet);
    }

    // TODO
    // function signToRouteAndSetAllowance(bytes32[] memory _routeKeys, uint256[] _allowance) external {}

    // TODO
    // function unsignFromRoute(bytes32[] memory _routeKeys) external nonReentrant {}

    // ====================== request callback ======================

    // function approveIncreasePosition(bytes32 _gmxPositionKey) external nonReentrant {
    //     if (msg.sender != callbackTarget) revert NotCallbackTarget();

    //     bytes32 _routeKey = gmxPositionKeyToRouteKey[_gmxPositionKey];
    //     RouteInfo storage _route = routeInfo[_routeKey];
    //     if (!_route.isRegistered) revert RouteNotRegistered();

    //     _deposit(_route, _route.trader, _route.traderRequestedCollateralAmount); // update shares and totalAmount for trader

    //     _route.isPositionOpen = true;
    //     _route.isWaitingForCallback = false;
    //     _route.traderRequestedCollateralAmount = 0;

    //     emit ApprovePosition(_routeKey);
    // }

    // function rejectIncreasePosition(bytes32 _gmxPositionKey) external nonReentrant {
    //     if (msg.sender != callbackTarget) revert NotCallbackTarget();

    //     bytes32 _routeKey = gmxPositionKeyToRouteKey[_gmxPositionKey];
    //     RouteInfo storage _route = routeInfo[_routeKey];
    //     if (!_route.isRegistered) revert RouteNotRegistered();

    //     uint256 _amount;
    //     bool _isPositionOpen = _route.isPositionOpen;
    //     for (uint256 i = 0; i < EnumerableSet.length(_route.puppetsSet); i++) {
    //         address _puppet = EnumerableSet.at(_route.puppetsSet, i);
    //         _amount = marginFee; // TODO marginFee

    //         if (!_isPositionOpen) _amount += EnumerableMap.get(_route.puppetAllowance, _puppet);

    //         puppetDepositAccount[_puppet] += _amount;
    //     }

    //     _amount = _route.traderRequestedCollateralAmount + marginFee; // TODO - marginFee // includes margin fee

    //     _route.isWaitingForCallback = false;
    //     _route.traderRequestedCollateralAmount = 0;

    //     if (!_isPositionOpen) {
    //         _route.isPositionOpen = false;
    //         _route.totalAmount = 0;
    //         _route.totalSupply = 0;
    //         for (uint256 i = 0; i < EnumerableMap.length(info.participantShares); i++) {
    //             (address key, ) = EnumerableMap.at(info.participantShares, i);
    //             EnumerableMap.remove(info.participantShares, key);
    //         }
    //     }
    //     // TODO - might need to transfer path[0] token instead of collateral token
    //     IERC20(_route.collateralToken).safeTransfer(_route.trader, _amount);

    //     emit RejectPosition(_routeKey, _amount);
    // }

    // function approveDecreasePosition(bytes32 _positionKey) external nonReentrant {
    //     if (msg.sender != callbackTarget) revert NotCallbackTarget();

    //     bytes32 _routeKey = gmxPositionKeyToRouteKey[_positionKey];
    //     PendingDecrease storage _pendingDecrease = pendingDecreases[_routeKey];
    //     RouteInfo storage _route = routeInfo[_routeKey];

    //     _route.totalAmount = _pendingDecrease.totalAmount;
    //     _route.totalSupply = _pendingDecrease.totalSupply;

    //     uint256 _newParticipantShares;
    //     uint256 _creditAmount;
    //     for (uint256 i = 0; i < puppetsSet.length(); i++) {
    //         address _puppet = puppetsSet.at(i);
    //         _newParticipantShares = EnumerableMap.get(_pendingDecrease.newParticipantShares, _puppet);
    //         _creditAmount = EnumerableMap.get(_pendingDecrease.creditAmounts, _puppet);

    //         EnumerableMap.set(_route.participantShares, _puppet, _newParticipantShares);
    //         puppetDepositAccount[_puppet] += _creditAmount;
    //     }

    //     _newParticipantShares = EnumerableMap.get(_pendingDecrease.newParticipantShares, _route.trader);
    //     _creditAmount = EnumerableMap.get(_pendingDecrease.creditAmounts, _route.trader);

    //     EnumerableMap.set(_route.participantShares, _route.trader, _newParticipantShares);

    //     delete pendingDecreases[_routeKey];

    //     _route.isWaitingForCallback = false;
    //     if (!_isPositionOpen(_route)) _route.isPositionOpen = false; // TODO

    //     creditBalance(msg.sender, _creditAmount); // TODO - send to trader

    //     emit ApproveDecreasePosition(_routeKey);
    // }

    // // TODO - credit margin fee
    // function rejectDecreasePosition(bytes32 _positionKey) external nonReentrant {
    //     if (msg.sender != callbackTarget) revert NotCallbackTarget();

    //     bytes32 _routeKey = gmxPositionKeyToRouteKey[_positionKey];
    //     PendingDecrease storage _pendingDecrease = pendingDecreases[_routeKey];
    //     RouteInfo storage _route = routeInfo[_routeKey];

    //     uint256 _creditAmount;
    //     for (uint256 i = 0; i < puppetsSet.length(); i++) {
    //         address _puppet = puppetsSet.at(i);
    //         _creditAmount = EnumerableMap.get(_pendingDecrease.creditAmounts, _puppet);
    //         puppetDepositAccount[_puppet] += _creditAmount;
    //     }

    //     _creditAmount = EnumerableMap.get(_pendingDecrease.creditAmounts, _route.trader);
    //     creditBalance(msg.sender, _creditAmount); // TODO - send to trader

    //     delete pendingDecreases[_positionKey];

    //     emit RejectDecreasePosition(_routeKey);
    // }

    // ====================== Owner Functions ======================

    // ====================== Internal Helper Functions ======================

    // function _createDecreasePosition(bytes memory _positionData, bytes32 _routeKey) internal {
    //     (address[] memory _path, address _indexToken, uint256 _collateralDeltaUSD, uint256 _sizeDelta, bool _isLong, address _receiver, uint256 _acceptablePrice, uint256 _minOut, uint256 _executionFee, bool _withdrawETH)
    //         = abi.decode(_positionData, (address[], address, uint256, uint256, bool, address, uint256, uint256, uint256, bool));

    //     RouteInfo storage _route = routeInfo[_routeKey];

    //     bytes32 _positionKey = IGMXPositionRouter(gmxPositionRouter).createDecreasePosition(_path, _indexToken, _amountIn, _minOut, _sizeDelta, _isLong, _acceptablePrice, _executionFee, referralCode, callbackTarget);
    //     if (gmxPositionKeyToRouteKey[_positionKey] != _routeKey) revert KeyError();

    //     _route.isWaitingForCallback = true;
    // }

    // ====================== Helper Functions ======================

    function getPositionKey(address _account, address _collateralToken, address _indexToken, bool _isLong) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, _collateralToken, _indexToken, _isLong));
    }

    // // ====================== Events ======================

    // event RegisterRoute(address indexed trader, address _routeAddress, address indexed collateralToken, address indexed indexToken, bool isLong);
    // event DepositToAccount(uint256 amount, address indexed caller, address indexed puppet);
    // event SignToRoute(address[] traders, address indexed puppet, address indexed collateralToken, address indexed indexToken, bool isLong, bool sign);
    // event Deposit(address indexed account, uint256 amount, uint256 shares);
    // event ApprovePosition(bytes32 indexed key);


    // // ====================== Errors ======================

    // error RouteAlreadyRegistered();
    // error CollateralTokenNotWhitelisted();
    // error IndexTokenNotWhitelisted();
    // error RouteNotRegistered();
    // error TraderNotMatch();
    // error PuppetAlreadySigned();
    // error PuppetNotSigned();
    // error Underflow();
    // error InvalidAmountIn();
    // error InvalidAmountOut();
    // error NotCallbackTarget();
    // error PositionNotOpen();
    // error RouteIsWaitingForCallback();
    // error ZeroAmount();
    // error WaitingForCallback();
    // error InvalidCaller();
}