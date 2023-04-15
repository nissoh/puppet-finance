// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IGMXRouter} from "./interfaces/IGMXRouter.sol";
import {IGMXPositionRouter} from "./interfaces/IGMXPositionRouter.sol";

contract Puppet {

    using SafeERC20 for IERC20;

    struct RouteInfo {
        uint256 totalAmount;
        uint256 totalSupply;
        address trader;
        bool isRegistered;
        bool isPositionOpen;
        EnumerableMap.AddressToUintMap participantShares;
        EnumerableMap.AddressToUintMap puppetAllowance;
        EnumerableSet.AddressSet puppetsSet;
    }

    address public gmxRouter;
    address public gmxPositionRouter;

    uint256 public marginFee = 0.01 ether; // TODO

    // route => routeInfo
    mapping(bytes32 => RouteInfo) private routeInfo;
    // puppet => deposit account balance
    mapping(address => uint256) public puppetDepositAccount;

    // collateral token => is whitelisted
    mapping(address => bool) public collateralTokenWhitelist;
    // index token => is whitelisted
    mapping(address => bool) public indexTokenWhitelist;

    // ====================== Constructor ======================

    constructor(address[] memory _collateralTokens, address[] memory _indexTokens, address _gmxRouter, address _gmxPositionRouter) {
        for (uint256 i = 0; i < _collateralTokens.length; i++) {
            collateralTokenWhitelist[_collateralTokens[i]] = true;
        }
        for (uint256 i = 0; i < _indexTokens.length; i++) {
            indexTokenWhitelist[_indexTokens[i]] = true;
        }

        gmxRouter = _gmxRouter;
        gmxPositionRouter = _gmxPositionRouter;

        IGMXRouter(_gmxRouter).approvePlugin(_gmxPositionRouter);
    }

    // ====================== Trader Functions ======================

    function registerRoute(address _collateralToken, address _indexToken, bool _isLong) public {
        address _trader = msg.sender;
        bytes32 _routeKey = getPositionKey(_trader, _collateralToken, _indexToken, _isLong);
        if (routeInfo[_routeKey].isRegistered) revert RouteAlreadyRegistered();

        routeInfo[_routeKey].trader = _trader;
        routeInfo[_routeKey].isRegistered = true;

        emit RegisterRoute(_trader, _collateralToken, _indexToken, _isLong);
    }

    // TODO
    // function createIncreasePositionETH(bytes memory _positionData, uint256 _traderAmount) external payable {
    //     // wrap ETH and call createIncreasePosition
    //     // make sure _positionData's _indexToken is WETH
    // }

    function createIncreasePosition(bytes memory _positionData, uint256 _traderAmount) public {
        (address[] memory _path, address _indexToken, uint256 _amountIn,,, bool _isLong,,)
            = abi.decode(_positionData, (address[], address, uint256, uint256, uint256, bool, uint256, uint256));

        address _trader = msg.sender;
        bytes32 _routeKey = getPositionKey(_trader, _path[_path.length - 1], _indexToken, _isLong);
        RouteInfo storage _route = routeInfo[_routeKey];
        if (!_route.isRegistered) revert RouteNotRegistered();

        uint256 _totalFunds;
        bool _isPositionOpen = _route.isPositionOpen;
        for (uint256 i = 0; i < EnumerableSet.length(_route.puppetsSet); i++) {
            uint256 _amount;
            address _puppet = EnumerableSet.at(_route.puppetsSet, i);

            if (!_isPositionOpen) _amount = EnumerableMap.get(_route.puppetAllowance, _puppet);
            _amount += marginFee; // TODO

            if (puppetDepositAccount[_puppet] >= _amount) {
                puppetDepositAccount[_puppet] -= _amount;
            } else {
                // _liquidate(_puppet); // TODO
                continue;
            }

            if (!_isPositionOpen) _deposit(_route, _puppet, _amount);

            _totalFunds += _amount;
        }

        _route.isPositionOpen = true;

        _deposit(_route, _trader, _traderAmount - marginFee); // TODO - marginFee

        _totalFunds += _traderAmount;
        if (_totalFunds != _amountIn) revert InvalidAmountIn();

        IERC20(_path[0]).safeTransferFrom(_trader, address(this), _traderAmount);

        _createIncreasePosition(_positionData);
    }

    function _createIncreasePosition(bytes memory _positionData) internal {
        (address[] memory _path, address _indexToken, uint256 _amountIn, uint256 _minOut, uint256 _sizeDelta, bool _isLong, uint256 _acceptablePrice, uint256 _executionFee)
            = abi.decode(_positionData, (address[], address, uint256, uint256, uint256, bool, uint256, uint256));

        address _callbackTarget = address(this); // TODO
        bytes32 _referralCode; // TODO
        IGMXPositionRouter(gmxPositionRouter).createIncreasePosition(_path, _indexToken, _amountIn, _minOut, _sizeDelta, _isLong, _acceptablePrice, _executionFee, _referralCode, _callbackTarget);
    }

    function _deposit(RouteInfo storage _route, address _account, uint256 _amount) internal {
        uint256 _shares = convertToShares(_route.totalAmount, _route.totalSupply, _amount);

        EnumerableMap.set(_route.participantShares, _account, EnumerableMap.get(_route.participantShares, _account) + _shares);

        _route.totalAmount += _amount;
        _route.totalSupply += _shares;

        emit Deposit(_account, _amount, _shares);
    }

    // function createDecreasePosition
    // 4. *removing collateral* createDecreasePosition (txn hash https://arbiscan.io/tx/0xddeac229f6190861f93185acb69111fe963ad9de282a52ad6da23300a1ac1539)
    // 5. *closing position* createDecreasePosition (txn hash https://arbiscan.io/tx/0x0aa093c2709d3f2a42b7c41345cfa4588e736bb5d98b2d0eca47f029f74a930e)

    // ====================== Puppet Functions ======================

    function depositToAccount(uint256 _amount, address _token, address _puppet) public {
        puppetDepositAccount[_puppet] += _amount;

        address _caller = msg.sender;
        IERC20(_token).safeTransferFrom(_caller, address(this), _amount);

        emit DepositToAccount(_amount, _caller, _puppet);
    }

    function toggleRouteSubscription(address[] memory _traders, address _collateralToken, address _indexToken, bool _isLong, bool _sign) public {
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

    function setTraderAllowance(bytes32[] memory _routeKeys, uint256 _allowance) external {
        address _puppet = msg.sender;
        for (uint256 i = 0; i < _routeKeys.length; i++) {
            if (!EnumerableSet.contains(routeInfo[_routeKeys[i]].puppetsSet, _puppet)) revert PuppetNotSigned();
            EnumerableMap.set(routeInfo[_routeKeys[i]].puppetAllowance, _puppet, _allowance);
        }
    }

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
}