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
        uint256 createdTraderCollateralAmount;
        uint256 traderCollateralAmount;
        address trader;
        address collateralToken;
        address indexToken;
        bool isLong;
        bool isRegistered;
        bool isPositionOpen;
        bool isPositionInitiated;
        bool isWaitingForCallback;
        bytes32 positionKey;
        EnumerableMap.AddressToUintMap participantShares;
        EnumerableMap.AddressToUintMap puppetAllowance;
        EnumerableSet.AddressSet puppetsSet;
    }

    uint256 public marginFee = 0.01 ether; // TODO

    address public gmxRouter;
    address public gmxPositionRouter;
    address public callbackTarget;

    bytes32 public referralCode;

    mapping(bytes32 => RouteInfo) private routeInfo;
    mapping(bytes32 => bytes32) private gmxPositionKeyToRouteKey;
    
    // puppet => deposit account balance
    mapping(address => uint256) public puppetDepositAccount;

    // collateral token => is whitelisted
    mapping(address => bool) public collateralTokenWhitelist;
    // index token => is whitelisted
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

    function registerRoute(address _collateralToken, address _indexToken, bool _isLong) external nonReentrant {
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

    function createIncreasePosition(bytes memory _positionData, uint256 _traderAmount) external nonReentrant {
        (address[] memory _path, address _indexToken, uint256 _amountIn,,, bool _isLong,,)
            = abi.decode(_positionData, (address[], address, uint256, uint256, uint256, bool, uint256, uint256));

        address _trader = msg.sender;
        bytes32 _routeKey = getPositionKey(_trader, _path[_path.length - 1], _indexToken, _isLong);
        RouteInfo storage _route = routeInfo[_routeKey];
        if (!_route.isRegistered) revert RouteNotRegistered();
        if (_route.isWaitingForCallback) revert RouteIsWaitingForCallback();

        uint256 _totalFunds; // total collateral + fees of all participants
        bool _isPositionInitiated = _route.isPositionInitiated; // take collateral from puppets only if position is not open. Fees are always taken when needed
        for (uint256 i = 0; i < EnumerableSet.length(_route.puppetsSet); i++) {
            uint256 _amount = marginFee; // TODO
            address _puppet = EnumerableSet.at(_route.puppetsSet, i);

            if (!_isPositionInitiated) _amount += EnumerableMap.get(_route.puppetAllowance, _puppet);

            if (puppetDepositAccount[_puppet] >= _amount) {
                puppetDepositAccount[_puppet] -= _amount;
            } else {
                // _liquidate(_puppet); // TODO
                continue;
            }

            if (!_isPositionInitiated) _deposit(_route, _puppet, _amount - marginFee); // TODO - marginFee // update shares and totalAmount for puppet

            _totalFunds += _amount;
        }

        _route.isPositionInitiated = true;

        _deposit(_route, _trader, _traderAmount - marginFee); // TODO - marginFee // update shares and totalAmount for trader

        _totalFunds += _traderAmount;
        if (_totalFunds != _amountIn) revert InvalidAmountIn();

        _route.createdTraderCollateralAmount = _traderAmount;

        IERC20(_path[0]).safeTransferFrom(_trader, address(this), _traderAmount);

        _createIncreasePosition(_positionData, _routeKey);
    }

    function _createIncreasePosition(bytes memory _positionData, bytes32 _routeKey) internal {
        (address[] memory _path, address _indexToken, uint256 _amountIn, uint256 _minOut, uint256 _sizeDelta, bool _isLong, uint256 _acceptablePrice, uint256 _executionFee)
            = abi.decode(_positionData, (address[], address, uint256, uint256, uint256, bool, uint256, uint256));

        RouteInfo storage _route = routeInfo[_routeKey];
        if (_route.isPositionOpen) {
            // trader added collateral to existing position
            // TODO - decrease position size to account for puppets not adding collateral
            // make sure _sizeDelta (position size in USD)...
        }

        bytes32 _positionKey = IGMXPositionRouter(gmxPositionRouter).createIncreasePosition(_path, _indexToken, _amountIn, _minOut, _sizeDelta, _isLong, _acceptablePrice, _executionFee, referralCode, callbackTarget);

        gmxPositionKeyToRouteKey[_positionKey] = _routeKey;
        _route.isWaitingForCallback = true;
    }

    function _deposit(RouteInfo storage _route, address _account, uint256 _amount) internal {
        uint256 _shares = convertToShares(_route.totalAmount, _route.totalSupply, _amount);

        EnumerableMap.set(_route.participantShares, _account, EnumerableMap.get(_route.participantShares, _account) + _shares);

        _route.totalAmount += _amount;
        _route.totalSupply += _shares;

        emit Deposit(_account, _amount, _shares);
    }

    // update traderCollateralAmount with createdTraderCollateralAmount
    // function approvePosition // TODO

    function rejectIncreasePosition(bytes32 _gmxPositionKey, bool _isPositionOpen) external nonReentrant {
        if (msg.sender != callbackTarget) revert NotCallbackTarget();

        bytes32 _routeKey = gmxPositionKeyToRouteKey[_gmxPositionKey];
        RouteInfo storage _route = routeInfo[_routeKey];
        if (!_route.isRegistered) revert RouteNotRegistered();

        uint256 _amount;
        for (uint256 i = 0; i < EnumerableSet.length(_route.puppetsSet); i++) {
            address _puppet = EnumerableSet.at(_route.puppetsSet, i);
            _amount = marginFee; // TODO marginFee

            if (!_isPositionOpen) _amount += EnumerableMap.get(_route.puppetAllowance, _puppet);

            puppetDepositAccount[_puppet] += _amount;
        }

        _amount = _route.createdTraderCollateralAmount + marginFee; // TODO marginFee
        if (!_isPositionOpen) _amount += route.traderCollateralAmount;

        _route.isWaitingForCallback = false;
        _route.createdTraderCollateralAmount = 0;

        if (!_isPositionOpen) {
            _route.isPositionOpen = false;
            _route.isPositionInitiated = false;
            _route.traderCollateralAmount = 0;
            _route.totalAmount = 0;
            _route.totalSupply = 0;
            // clear participantShares
            for (uint256 i = 0; i < EnumerableMap.length(info.participantShares); i++) {
                (address key, ) = EnumerableMap.at(info.participantShares, i);
                EnumerableMap.remove(info.participantShares, key);
            }
        }

        IERC20(_route.collateralToken).safeTransfer(_route.trader, _amount);
    }

    // function createDecreasePosition
    // 4. *removing collateral* createDecreasePosition (txn hash https://arbiscan.io/tx/0xddeac229f6190861f93185acb69111fe963ad9de282a52ad6da23300a1ac1539)
    // 5. *closing position* createDecreasePosition (txn hash https://arbiscan.io/tx/0x0aa093c2709d3f2a42b7c41345cfa4588e736bb5d98b2d0eca47f029f74a930e)

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
            _routeKey = getPositionKey(_traders[0], _collateralToken, _indexToken, _isLong);
            if (!routeInfo[_routeKey].isRegistered) revert RouteNotRegistered();
            if (_traders[i] != routeInfo[_routeKey].trader) revert TraderNotMatch();

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
            EnumerableMap.set(routeInfo[_routeKeys[i]].puppetAllowance, _puppet, _allowance);
        }
    }

    // TODO
    // function signToRouteAndSetAllowance(bytes32[] memory _routeKeys, uint256[] _allowance) external {}

    // TODO
    // function unsignFromRoute(bytes32[] memory _routeKeys) external nonReentrant {}

    // ====================== GMX request callback ======================

    // function gmxPositionCallback(bytes32 _key, bool _wasExecuted, bool _isIncrease) {}

    // ====================== Owner Functions ======================

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
}