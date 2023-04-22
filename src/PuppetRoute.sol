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
import {ITraderRoute} from "./interfaces/ITraderRoute.sol";
import {IPuppetRoute} from "./interfaces/IPuppetRoute.sol";

contract TraderRoute is ReentrancyGuard, IPuppetRoute {

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

    RouteInfo private routeInfo;
    PendingDecrease private pendingDecrease;

    IPuppetOrchestrator public puppetOrchestrator;

    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    // ====================== Constructor ======================

    constructor(address _trader, address _collateralToken, address _indexToken, bool _isLong) {
        puppetOrchestrator = IPuppetOrchestrator(msg.sender);

        trader = _trader;
        collateralToken = _collateralToken;
        indexToken = _indexToken;
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

    function convertToShares(uint256 _totalAssets, uint256 _totalSupply, uint256 _assets) public pure returns (uint256 _shares) {
        if (_assets == 0) revert ZeroAmount();

        if (_totalAssets == 0) {
            _shares = _assets;
        } else {
            _shares = (_assets * _totalSupply) / _totalAssets;
        }

        if (_shares == 0) revert ZeroShares();
    }

    function convertToAssets(uint256 _totalAssets, uint256 _totalSupply, uint256 _shares) public pure returns (uint256 _assets) {
        if (_totalSupply == 0) {
            _assets = _shares;
        } else {
            _assets = (_shares * _totalAssets) / _totalSupply;
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

        return _response[0] > 0 && _response[1] > 0;
    }

    // ====================== Puppet orchestrator functions ======================

    function signPuppet(address _puppet, uint256 _allowance) external nonReentrant {
        if (msg.sender != address(puppetOrchestrator)) revert Unauthorized();
        if (isWaitingForCallback) revert WaitingForCallback();
        if (traderRoute.isPositionOpen()) revert PositionIsOpen();

        bool _isPresent = EnumerableSet.add(puppetsSet, _puppet);
        if (_isPresent) revert PuppetAlreadySigned();

        EnumerableMap.set(puppetAllowance, _puppet, _allowance);
    }

    function unsignPuppet(address _puppet) external nonReentrant {
        if (msg.sender != address(puppetOrchestrator)) revert Unauthorized();
        if (isWaitingForCallback) revert WaitingForCallback();
        if (traderRoute.isPositionOpen()) revert PositionIsOpen();

        bool _isPresent = EnumerableSet.remove(puppetsSet, _puppet);
        if (!_isPresent) revert PuppetNotSigned();
    }

    function setAllowance(address _puppet, uint256 _allowance) external nonReentrant {
        if (msg.sender != address(puppetOrchestrator)) revert Unauthorized();
        if (isWaitingForCallback) revert WaitingForCallback();
        if (traderRoute.isPositionOpen()) revert PositionIsOpen();

        EnumerableMap.set(puppetAllowance, _puppet, _allowance);
    }

    // ====================== TraderRoute functions ======================

    function createIncreasePosition(bytes memory _positionData) external nonReentrant {
        if (isRejected) {
            if (msg.sender != address(keeper)) revert Unauthorized();
        } else {
            if (msg.sender != address(traderRoute)) revert Unauthorized();
        }

        (uint256 _amountIn, uint256 _executionFee,,,,) = abi.decode(_positionData, (uint256, uint256, uint256, uint256, uint256, address));

        uint256 _requiredAssets = _amountIn + _executionFee;

        if (isPositionOpen) {
            // trader is increasing position, get only the fees
            _getFees(_requiredAssets);
        } else {
            // trader is opening position, get the collateral and the fees
            _getAllowances(_requiredAssets);
        }
        
        _createIncreasePosition(_positionData);
    }

    function createDecreasePosition(bytes memory _positionData) external nonReentrant {
        if (isRejected) {
            if (msg.sender != address(keeper)) revert Unauthorized();
        } else {
            if (msg.sender != address(traderRoute)) revert Unauthorized();
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

    function approveIncreasePosition() external nonReentrant onlyCallbackTarget {
        isRejected = false;

        traderRoute.notifyCallback();

        emit ApproveIncreasePosition();
    }

    // if rejected, a keeper will need to call createIncreasePosition again until it is approved
    // TODO - add forceClose to allow the platform to close the position
    function rejectIncreasePosition() external nonReentrant onlyCallbackTarget {
        isRejected = true;

        _repayBalance();

        if (!isPositionOpen) {
            totalAssets = 0;
            totalSupply = 0;
            for (uint256 i = 0; i < EnumerableMap.length(participantShares); i++) {
                (address _key, ) = EnumerableMap.at(participantShares, i);
                EnumerableMap.remove(participantShares, _key);
            }
        }

        emit RejectIncreasePosition();
    }

    function approveDecreasePosition() external nonReentrant onlyCallbackTarget {
        isRejected = false;

        traderRoute.notifyCallback();

        _repayBalance();

        if (!_isOpenInterest()) {
            isPositionOpen = false;
            totalAssets = 0;
            totalSupply = 0;
            for (uint256 i = 0; i < EnumerableMap.length(participantShares); i++) {
                (address _key, ) = EnumerableMap.at(participantShares, i);
                EnumerableMap.remove(participantShares, _key);
            }
        }

        emit ApproveDecreasePosition();
    }

    function rejectDecreasePosition() external nonReentrant onlyCallbackTarget {
        isRejected = true;

        emit RejectDecreasePosition();
    }

    // ====================== Internal functions ======================

    function _createIncreasePosition(bytes memory _positionData) internal {
        (address _collateralToken, address _indexToken, uint256 _amountIn, uint256 _minOut, uint256 _sizeDelta, uint256 _acceptablePrice, uint256 _executionFee)
            = abi.decode(_positionData, (address, address, uint256, uint256, uint256, uint256, uint256));

        address[] memory _path = new address[](1);
        _path[0] = _collateralToken;

        bytes32 _referralCode = puppetOrchestrator.getReferralCode();
        address _callbackTarget = puppetOrchestrator.getCallbackTarget();
        bytes32 _positionKey = IGMXPositionRouter(puppetOrchestrator.getGMXPositionRouter()).createIncreasePosition(_path, _indexToken, _amountIn, _minOut, _sizeDelta, routeInfo.isLong, _acceptablePrice, _executionFee, _referralCode, _callbackTarget);

        // puppetOrchestrator.updateGMXPositionKeyToTraderRouteAddress(_positionKey);

        emit CreateIncreasePosition(_positionKey, _amountIn, _minOut, _sizeDelta, _acceptablePrice, _executionFee);
    }

    function _createDecreasePosition(bytes memory _positionData) internal {
        (address _collateralToken, address _indexToken, uint256 _collateralDeltaUSD, uint256 _sizeDelta, uint256 _acceptablePrice, uint256 _minOut, uint256 _executionFee)
            = abi.decode(_positionData, (address, address, uint256, uint256, uint256, uint256, uint256));

        address[] memory _path = new address[](1);
        _path[0] = _collateralToken;

        address _callbackTarget = puppetOrchestrator.getCallbackTarget();
        bytes32 _positionKey = IGMXPositionRouter(puppetOrchestrator.getGMXPositionRouter()).createDecreasePosition(_path, _indexToken, _collateralDeltaUSD, _sizeDelta, _route.isLong, address(this), _acceptablePrice, _minOut, _executionFee, false, _callbackTarget);

        // if (puppetOrchestrator.getTraderRouteForPosition(_positionKey) != address(this)) revert KeyError();

        emit CreateDecreasePosition(_positionKey, _minOut, _collateralDeltaUSD, _sizeDelta, _acceptablePrice, _executionFee);
    }

    function _liquidate(address _puppet) internal {
        EnumerableSet.remove(puppetsSet, _puppet);
        EnumerableMap.set(puppetAllowance, _puppet, 0);
        
        emit Liquidate(_puppet);
    }

    function _getFees(uint256 _requiredAssets) internal {
        uint256 _requiredShares = convertToShares(totalAssets, totalSupply, _requiredAssets);
        uint256 _requiredAssetsPerShare = _requiredAssets / _requiredShares;
        for (uint256 i = 0; i < EnumerableSet.length(puppetsSet); i++) {
            address _puppet = EnumerableSet.at(puppetsSet, i);
            uint256 _shares = EnumerableMap.get(puppetShares, _puppet);
            uint256 _puppetRequiredAmount = _requiredAssetsPerShare * _shares;

            if (puppetOrchestrator.isPuppetSolvent(_puppetRequiredAmount, _puppet)) {
                puppetOrchestrator.debitPuppetAccount(_puppetRequiredAmount, _puppet);
            } else {
                revert PuppetCannotCoverFees();
            }
        }
    }

    function _getAllowances(uint256 _requiredAssets) internal {
        uint256 _totalSupply;
        uint256 _totalAssets;
        uint256 _traderAmountIn = puppetOrchestrator.getTraderAmountIn();
        for (uint256 i = 0; i < EnumerableSet.length(puppetsSet); i++) {
            address _puppet = EnumerableSet.at(puppetsSet, i);
            uint256 _allowance = EnumerableMap.get(puppetAllowance, _puppet);

            if (_allowance > _traderAmountIn) _allowance = _traderAmountIn;

            if (puppetOrchestrator.isEnoughBuffer(_allowance, _puppet)) {
                puppetOrchestrator.debitPuppetAccount(_allowance, _puppet);
            } else {
                _liquidate(_puppet);
                continue;
            }

            uint256 _shares = convertToShares(_totalAssets, _totalSupply, _allowance);
            EnumerableMap.set(puppetShares, _puppet, _shares);

            _totalSupply += _shares;
            _totalAssets += _allowance;
        }

        if (_totalAssets != _requiredAssets) revert AssetsAmonutMismatch();

        totalSupply = _totalSupply;
        totalAssets = _totalAssets;

        IERC20(WETH).safeTransferFrom(address(puppetOrchestrator), address(this), _totalAssets);
        IWETH(WETH).withdraw(_totalAssets);

        if (address(this).balance < _totalAssets) revert AssetsAmonutMismatch();
        if (_totalAssets < minPositionSize) revert PositionTooSmall();
    }

    function _repayBalance() internal {
        uint256 _totalAssets = address(this).balance;
        if (_totalAssets > 0) {
            address _weth = WETH;
            IWETH(_weth).deposit{value: address(this).balance}();
            
            uint256 _totalSupply = totalSupply;
            _totalAssets = IERC20(_weth).balanceOf(address(this));
            for (uint256 i = 0; i < EnumerableSet.length(puppetsSet); i++) {
                address _puppet = EnumerableSet.at(puppetsSet, i);
                uint256 _shares = EnumerableMap.get(participantShares, _puppet);
                uint256 _assets = convertToAssets(_totalAssets, _totalSupply, _shares);

                puppetOrchestrator.creditPuppetAccount(_assets, _puppet);
            }
            IERC20(_weth).safeTransfer(address(puppetOrchestrator), _totalAssets);
        }
    }
}