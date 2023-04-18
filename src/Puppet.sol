// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IGMXRouter} from "./interfaces/IGMXRouter.sol";
import {IGMXPositionRouter} from "./interfaces/IGMXPositionRouter.sol";

contract Puppet is ReentrancyGuard {

    using SafeERC20 for IERC20;

    struct RouteInfo {
        uint256 totalAmount;
        uint256 totalSupply;
        uint256 traderRequestedCollateralAmount;
        address trader;
        address collateralToken;
        address indexToken;
        bool isLong;
        bool isRegistered;
        bool isPositionOpen;
        bool isWaitingForCallback;
        // bytes32 positionKey;
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

    uint256 public marginFee = 0.01 ether; // TODO

    address public gmxRouter;
    address public gmxPositionRouter;
    address public callbackTarget;

    bytes32 public referralCode;

    mapping(bytes32 => RouteInfo) private routeInfo;
    mapping(bytes32 => PendingDecrease) public pendingDecreases;
    mapping(bytes32 => bytes32) private gmxPositionKeyToRouteKey;

    // TODO - fix puppet token balance
    // // token => puppet => balance
    // mapping(address => mapping(address => uint256)) public puppetDepositAccount;
    mapping(address => uint256) public puppetDepositAccount;

    mapping(address => bool) public collateralTokenWhitelist;
    mapping(address => bool) public indexTokenWhitelist;

    // ====================== Constructor ======================

    constructor(address[] memory _collateralTokens, address[] memory _indexTokens, address _gmxRouter, address _gmxPositionRouter, address _callbackTarget, bytes32 _referralCode) {
        for (uint256 i = 0; i < _collateralTokens.length; i++) {
            collateralTokenWhitelist[_collateralTokens[i]] = true;
        }
        for (uint256 i = 0; i < _indexTokens.length; i++) {
            indexTokenWhitelist[_indexTokens[i]] = true;
        }

        callbackTarget = _callbackTarget;
        referralCode = _referralCode;

        gmxRouter = _gmxRouter;
        gmxPositionRouter = _gmxPositionRouter;

        IGMXRouter(_gmxRouter).approvePlugin(_gmxPositionRouter);
    }

    // ====================== Trader Functions ======================

    function registerRoute(address _collateralToken, address _indexToken, bool _isLong) external nonReentrant returns (bytes32 _routeKey) {
        address _trader = msg.sender;
        bytes32 _routeKey = getPositionKey(_trader, _collateralToken, _indexToken, _isLong);
        if (routeInfo[_routeKey].isRegistered) revert RouteAlreadyRegistered();

        routeInfo[_routeKey].isRegistered = true;
        routeInfo[_routeKey].trader = _trader;
        routeInfo[_routeKey].collateralToken = _collateralToken;
        routeInfo[_routeKey].indexToken = _indexToken;
        routeInfo[_routeKey].isLong = _isLong;

        emit RegisterRoute(_trader, _collateralToken, _indexToken, _isLong);
    }

    // TODO
    // function createIncreasePositionETH(bytes memory _positionData, uint256 _traderAmount) external payable {
    //     // wrap ETH and call createIncreasePosition
    //     // make sure _positionData's _collateralToken is WETH
    // }

    // NOTE: on adjusting position:
    // when setting `_sizeDelta`, make sure to account for the fact that puppets do not add collateral to an adjusment in an open position
    // if not, trader will pay for increasing position size of puppets
    function createIncreasePosition(bytes memory _positionData, uint256 _traderAmount) external nonReentrant {
        (address[] memory _path, address _indexToken, uint256 _amountIn,,, bool _isLong,,)
            = abi.decode(_positionData, (address[], address, uint256, uint256, uint256, bool, uint256, uint256));

        address _trader = msg.sender;
        bytes32 _routeKey = getPositionKey(_trader, _path[_path.length - 1], _indexToken, _isLong);
        RouteInfo storage _route = routeInfo[_routeKey];
        if (!_route.isRegistered) revert RouteNotRegistered();
        if (_route.trader != _trader) revert InvalidCaller();
        if (_route.isWaitingForCallback) revert RouteIsWaitingForCallback();

        uint256 _totalFunds; // total collateral + fees of all participants
        bool _isPositionOpen = _route.isPositionOpen; // take collateral from puppets only if position is not open. Fees are always taken when needed
        for (uint256 i = 0; i < EnumerableSet.length(_route.puppetsSet); i++) {
            uint256 _amount = marginFee; // TODO
            address _puppet = EnumerableSet.at(_route.puppetsSet, i);

            if (!_isPositionOpen) _amount += EnumerableMap.get(_route.puppetAllowance, _puppet);

            if (puppetDepositAccount[_puppet] >= _amount) {
                puppetDepositAccount[_puppet] -= _amount;
            } else {
                // _liquidate(_puppet); // TODO
                continue;
            }

            if (!_isPositionOpen) _deposit(_route, _puppet, _amount - marginFee); // TODO - marginFee // update shares and totalAmount for puppet

            _totalFunds += _amount;
        }

        _totalFunds += _traderAmount;
        if (_totalFunds != _amountIn) revert InvalidAmountIn();

        _route.traderRequestedCollateralAmount = _traderAmount - marginFee; // TODO - marginFee // includes margin fee

        IERC20(_path[0]).safeTransferFrom(_trader, address(this), _traderAmount);

        _createIncreasePosition(_positionData, _routeKey);
    }

    // TODO - add margin fee handling
    function createDecreasePosition(bytes memory _positionData) external nonReentrant {
        (address[] memory _path, address _indexToken, uint256 _collateralDeltaUSD, uint256 _sizeDelta, bool _isLong, address _receiver, uint256 _acceptablePrice, uint256 _minOut, uint256 _executionFee, bool _withdrawETH)
            = abi.decode(_positionData, (address[], address, uint256, uint256, bool, address, uint256, uint256, uint256, bool));

        address _trader = msg.sender;
        bytes32 _routeKey = getPositionKey(_trader, _path[_path.length - 1], _indexToken, _isLong);
        RouteInfo storage _route = routeInfo[_routeKey];
        if (!_route.isRegistered) revert RouteNotRegistered();
        if (_route.trader != _trader) revert InvalidCaller();
        if (_route.isWaitingForCallback) revert RouteIsWaitingForCallback();

        uint256 _collateralDelta;
        if (_collateralDeltaUSD > 0) {
            // TODO: convert _collateralDeltaUSD to _collateralDelta using the exchange rate
            _collateralDelta = _collateralDeltaUSD; // TODO

            uint256 _totalSharesToBurn = convertToShares(_route.totalAmount, _route.totalSupply, _collateralDelta);

            PendingDecrease storage _pendingDecrease;

            uint256 _shares;
            uint256 _sharesToBurn;
            uint256 _amountToCredit;
            for (uint256 i = 0; i < puppetsSet.length(); i++) {
                address _puppet = puppetsSet.at(i);
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

            pendingDecreases[_positionKey] = _pendingDecrease;
        }

        bytes32 _positionKey = IGMXPositionRouter(gmxPositionRouter).createDecreasePosition(_path, _indexToken, _collateralDelta, _sizeDelta, _isLong, _receiver, _acceptablePrice, _minOut, _executionFee, _withdrawETH, referralCode, callbackTarget);

        gmxPositionKeyToRouteKey[_positionKey] = _routeKey;
        _route.isWaitingForCallback = true;
    }

    function creditBalance(address _account, uint256 _amount) private {
        // TODO: Implement the logic to credit the balance of _account with _amount
    }

    // ====================== Puppet Functions ======================

    function depositToAccount(uint256 _amount, address _token, address _puppet) external nonReentrant {
        puppetDepositAccount[_puppet] += _amount;

        address _caller = msg.sender;
        IERC20(_token).safeTransferFrom(_caller, address(this), _amount);

        emit DepositToAccount(_amount, _caller, _puppet);
    }

    function toggleRouteSubscription(address[] memory _traders, address _collateralToken, address _indexToken, bool _isLong, bool _sign) external nonReentrant {
        if (!collateralTokenWhitelist[_collateralToken]) revert CollateralTokenNotWhitelisted();
        if (!indexTokenWhitelist[_indexToken]) revert IndexTokenNotWhitelisted();

        bytes32 _routeKey;
        address _puppet = msg.sender;
        for (uint256 i = 0; i < _traders.length; i++) {
            _routeKey = getPositionKey(_traders[i], _collateralToken, _indexToken, _isLong);
            if (!routeInfo[_routeKey].isRegistered) revert RouteNotRegistered();
            if (routeInfo[_routeKey].isWaitingForCallback) revert WaitingForCallback();

            bool _isPresent;
            EnumerableSet.AddressSet storage _puppetsSet = routeInfo[_routeKey].puppetsSet;
            if (_sign) {
                _isPresent = EnumerableSet.add(_puppetsSet, _puppet);
                if (_isPresent) revert PuppetAlreadySigned();
            } else {
                _isPresent = EnumerableSet.remove(_puppetsSet, _puppet);
                if (!_isPresent) revert PuppetNotSigned();
            }
        }

        emit SignToRoute(_traders, _puppet, _collateralToken, _indexToken, _isLong, _sign);
    }

    function setTraderAllowance(bytes32[] memory _routeKeys, uint256 _allowance) external nonReentrant {
        address _puppet = msg.sender;
        for (uint256 i = 0; i < _routeKeys.length; i++) {
            if (!EnumerableSet.contains(routeInfo[_routeKeys[i]].puppetsSet, _puppet)) revert PuppetNotSigned();
            if (routeInfo[_routeKeys[i]].isWaitingForCallback) revert WaitingForCallback();

            EnumerableMap.set(routeInfo[_routeKeys[i]].puppetAllowance, _puppet, _allowance);
        }
    }

    // TODO
    // function signToRouteAndSetAllowance(bytes32[] memory _routeKeys, uint256[] _allowance) external {}

    // TODO
    // function unsignFromRoute(bytes32[] memory _routeKeys) external nonReentrant {}

    // ====================== request callback ======================

    function approveIncreasePosition(bytes32 _gmxPositionKey) external nonReentrant {
        if (msg.sender != callbackTarget) revert NotCallbackTarget();

        bytes32 _routeKey = gmxPositionKeyToRouteKey[_gmxPositionKey];
        RouteInfo storage _route = routeInfo[_routeKey];
        if (!_route.isRegistered) revert RouteNotRegistered();

        _deposit(_route, _route.trader, _route.traderRequestedCollateralAmount); // update shares and totalAmount for trader

        _route.isPositionOpen = true;
        _route.isWaitingForCallback = false;
        _route.traderRequestedCollateralAmount = 0;

        emit ApprovePosition(_routeKey);
    }

    function rejectIncreasePosition(bytes32 _gmxPositionKey) external nonReentrant {
        if (msg.sender != callbackTarget) revert NotCallbackTarget();

        bytes32 _routeKey = gmxPositionKeyToRouteKey[_gmxPositionKey];
        RouteInfo storage _route = routeInfo[_routeKey];
        if (!_route.isRegistered) revert RouteNotRegistered();

        uint256 _amount;
        bool _isPositionOpen = _route.isPositionOpen;
        for (uint256 i = 0; i < EnumerableSet.length(_route.puppetsSet); i++) {
            address _puppet = EnumerableSet.at(_route.puppetsSet, i);
            _amount = marginFee; // TODO marginFee

            if (!_isPositionOpen) _amount += EnumerableMap.get(_route.puppetAllowance, _puppet);

            puppetDepositAccount[_puppet] += _amount;
        }

        _amount = _route.traderRequestedCollateralAmount + marginFee; // TODO - marginFee // includes margin fee

        _route.isWaitingForCallback = false;
        _route.traderRequestedCollateralAmount = 0;

        if (!_isPositionOpen) {
            _route.isPositionOpen = false;
            _route.totalAmount = 0;
            _route.totalSupply = 0;
            for (uint256 i = 0; i < EnumerableMap.length(info.participantShares); i++) {
                (address key, ) = EnumerableMap.at(info.participantShares, i);
                EnumerableMap.remove(info.participantShares, key);
            }
        }
        IERC20(_route.collateralToken).safeTransfer(_route.trader, _amount);

        emit RejectPosition(_routeKey, _amount);
    }

    function approveDecreasePosition(bytes32 _positionKey) external nonReentrant {
        if (msg.sender != callbackTarget) revert NotCallbackTarget();

        PendingDecrease storage _pendingDecrease = pendingDecreases[_positionKey];
        bytes32 _routeKey = gmxPositionKeyToRouteKey[_positionKey];
        RouteInfo storage _route = routeInfo[_routeKey];

        _route.totalAmount = _pendingDecrease.totalAmount;
        _route.totalSupply = _pendingDecrease.totalSupply;

        uint256 _newParticipantShares;
        uint256 _creditAmount;
        for (uint256 i = 0; i < puppetsSet.length(); i++) {
            address _puppet = puppetsSet.at(i);
            _newParticipantShares = EnumerableMap.get(_pendingDecrease.newParticipantShares, _puppet);
            _creditAmount = EnumerableMap.get(_pendingDecrease.creditAmounts, _puppet);

            EnumerableMap.set(_route.participantShares, _puppet, _newParticipantShares);
            puppetDepositAccount[_puppet] += _creditAmount;
        }

        _newParticipantShares = EnumerableMap.get(_pendingDecrease.newParticipantShares, _route.trader);
        _creditAmount = EnumerableMap.get(_pendingDecrease.creditAmounts, _route.trader);

        EnumerableMap.set(_route.participantShares, _route.trader, _newParticipantShares);
        creditBalance(msg.sender, _creditAmount);

        delete pendingDecreases[_positionKey];

        emit ApproveDecreasePosition(_routeKey);
    }

    // ====================== Owner Functions ======================

    // ====================== Internal Helper Functions ======================

    function _createIncreasePosition(bytes memory _positionData, bytes32 _routeKey) internal {
        (address[] memory _path, address _indexToken, uint256 _amountIn, uint256 _minOut, uint256 _sizeDelta, bool _isLong, uint256 _acceptablePrice, uint256 _executionFee)
            = abi.decode(_positionData, (address[], address, uint256, uint256, uint256, bool, uint256, uint256));

        RouteInfo storage _route = routeInfo[_routeKey];

        bytes32 _positionKey = IGMXPositionRouter(gmxPositionRouter).createIncreasePosition(_path, _indexToken, _amountIn, _minOut, _sizeDelta, _isLong, _acceptablePrice, _executionFee, referralCode, callbackTarget);

        gmxPositionKeyToRouteKey[_positionKey] = _routeKey;
        _route.isWaitingForCallback = true;
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

    // ====================== Helper Functions ======================

    function getPositionKey(address _account, address _collateralToken, address _indexToken, bool _isLong) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, _collateralToken, _indexToken, _isLong));
    }

    function convertToShares(uint256 _totalAmount, uint256 _totalSupply, uint256 _amount) public pure returns (uint256 _shares) {
        if (_totalAmount == 0) {
            _shares = _amount;
        } else {
            _shares = (_amount * _totalSupply) / _totalAmount;
        }
    }

    function convertToAssets(uint256 _totalAmount, uint256 _totalSupply, uint256 _shares) public pure returns (uint256 _amount) {
        if (_totalSupply == 0) {
            _amount = _shares;
        } else {
            _amount = (_shares * _totalAmount) / _totalSupply;
        }
    }

    // ====================== Events ======================

    event RegisterRoute(address indexed trader, address indexed collateralToken, address indexed indexToken, bool isLong);
    event DepositToAccount(uint256 amount, address indexed caller, address indexed puppet);
    event SignToRoute(address[] traders, address indexed puppet, address indexed collateralToken, address indexed indexToken, bool isLong, bool sign);
    event Deposit(address indexed account, uint256 amount, uint256 shares);
    event ApprovePosition(bytes32 indexed key);


    // ====================== Errors ======================

    error RouteAlreadyRegistered();
    error CollateralTokenNotWhitelisted();
    error IndexTokenNotWhitelisted();
    error RouteNotRegistered();
    error TraderNotMatch();
    error PuppetAlreadySigned();
    error PuppetNotSigned();
    error Underflow();
    error InvalidAmountIn();
    error InvalidAmountOut();
    error NotCallbackTarget();
    error PositionNotOpen();
    error RouteIsWaitingForCallback();
    error ZeroAmount();
    error WaitingForCallback();
    error InvalidCaller();
}