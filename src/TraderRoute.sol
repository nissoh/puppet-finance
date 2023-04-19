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
contract TraderRoute is ReentrancyGuard, ITraderRoute {

    using SafeERC20 for IERC20;

    struct RouteInfo {
        uint256 totalAmount;
        uint256 totalSupply;
        uint256 traderRequestedCollateralAmount;
        address trader;
        address collateralToken;
        address indexToken;
        bytes32 positionKey;
        bool isLong;
        bool isPositionOpen;
        bool isWaitingForCallback;
        EnumerableMap.AddressToUintMap participantShares;
        EnumerableMap.AddressToUintMap puppetAllowance;
        EnumerableSet.AddressSet puppetsSet;
    }

    RouteInfo private routeInfo;

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

    function isWaitingForCallback() external view returns (bool) {
        return routeInfo.isWaitingForCallback;
    }

    function isPositionOpen() public view returns (bool) {
        // TODO
    }

    function isPuppetSigned(address _puppet) external view returns (bool) {
        return EnumerableSet.contains(routeInfo.puppetsSet, _puppet);
    }

    function signPuppet(address _puppet, uint256 _allowance) external nonReentrant returns (bool _isPresent) {
        if (msg.sender != address(puppetOrchestrator)) revert Unauthorized();
        if (routeInfo.isWaitingForCallback) revert WaitingForCallback();
        if (isPositionOpen()) revert PositionIsOpen();

        _isPresent = EnumerableSet.add(routeInfo.puppetsSet, _puppet);
        EnumerableMap.set(routeInfo.puppetAllowance, _puppet, _allowance);
    }

    function unsignPuppet(address _puppet) external nonReentrant returns (bool _isPresent) {
        if (msg.sender != address(puppetOrchestrator)) revert Unauthorized();
        if (routeInfo.isWaitingForCallback) revert WaitingForCallback();
        if (isPositionOpen()) revert PositionIsOpen();

        _isPresent = EnumerableSet.remove(routeInfo.puppetsSet, _puppet);
    }

    function setAllowance(address _puppet, uint256 _allowance) external nonReentrant {
        if (msg.sender != address(puppetOrchestrator)) revert Unauthorized();
        if (routeInfo.isWaitingForCallback) revert WaitingForCallback();
        if (isPositionOpen()) revert PositionIsOpen();

        EnumerableMap.set(routeInfo.puppetAllowance, _puppet, _allowance);
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
        (address _collateralToken, address _indexToken, uint256 _amountIn,,, bool _isLong,,)
            = abi.decode(_positionData, (address, address, uint256, uint256, uint256, bool, uint256, uint256));

        address _trader = msg.sender;
        RouteInfo storage _route = routeInfo;
        if (_route.trader != _trader) revert InvalidCaller();
        if (_route.isWaitingForCallback) revert WaitingForCallback();

        uint256 _totalFunds; // total collateral + fees of all participants
        bool _isPositionOpen = _route.isPositionOpen; // take collateral from puppets only if position is not open. Fees are always taken when needed
        for (uint256 i = 0; i < EnumerableSet.length(_route.puppetsSet); i++) {
            address _puppet = EnumerableSet.at(_route.puppetsSet, i);
            uint256 _allowance;
            if (!_isPositionOpen) _allowance = EnumerableMap.get(_route.puppetAllowance, _puppet);

            uint256 _amount = _allowance + marginFee; // TODO - marginFee
            if (puppetOrchestrator.isPuppetSolvent(_amount, _puppet)) {
                puppetOrchestrator.debitPuppetAccount(_puppet, _collateralToken, _amount);
            } else {
                // _liquidate(_puppet); // TODO
                continue;
            }

            if (!_isPositionOpen) _deposit(_route, _puppet, _allowance); // update shares and totalAmount for puppet

            _totalFunds += _amount;
        }

        _totalFunds += _traderAmount;
        if (_totalFunds != _amountIn) revert InvalidAmountIn();

        _route.traderRequestedCollateralAmount = _traderAmount - marginFee; // TODO - marginFee // includes margin fee

        IERC20(_collateralToken).safeTransferFrom(_trader, address(this), _traderAmount);
        IERC20(_collateralToken).safeTransferFrom(address(puppetOrchestrator), address(this), _totalFunds - _traderAmount);

        _createIncreasePosition(_positionData);
    }

    function _createIncreasePosition(bytes memory _positionData) internal {
        (address _collateralToken, address _indexToken, uint256 _amountIn, uint256 _minOut, uint256 _sizeDelta, bool _isLong, uint256 _acceptablePrice, uint256 _executionFee)
            = abi.decode(_positionData, (address, address, uint256, uint256, uint256, bool, uint256, uint256));

        address[] memory _path = new address[](1);
        _path[0] = _collateralToken;

        bytes32 _referralCode = puppetOrchestrator.getReferralCode();
        address _callbackTarget = puppetOrchestrator.getCallbackTarget();
        bytes32 _positionKey = IGMXPositionRouter(puppetOrchestrator.getGMXPositionRouter()).createIncreasePosition(_path, _indexToken, _amountIn, _minOut, _sizeDelta, _isLong, _acceptablePrice, _executionFee, _referralCode, _callbackTarget);

        routeInfo.positionKey = _positionKey;
        routeInfo.isWaitingForCallback = true;

        emit CreateIncreasePosition(_positionKey, _amountIn, _minOut, _sizeDelta, _acceptablePrice, _executionFee);
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
}