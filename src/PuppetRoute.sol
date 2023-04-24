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

contract PuppetRoute is ReentrancyGuard, IPuppetRoute {

    using SafeERC20 for IERC20;
    using Address for address payable;

    uint256 private totalAmount;
    uint256 private totalSupply;

    address public collateralToken;
    address public indexToken;
    
    bool public isLong;
    bool public isPositionOpen;
    bool public isWaitingForCallback;
    bool public isIncrease;

    EnumerableSet.AddressSet private puppetsSet;

    EnumerableMap.AddressToUintMap private puppetShare;
    EnumerableMap.AddressToUintMap private puppetAllowance;

    IPuppetOrchestrator public puppetOrchestrator;
    ITraderRoute public traderRoute;

    // ====================== Constructor ======================

    constructor(address _puppetOrchestrator, address _collateralToken, address _indexToken, bool _isLong) {
        puppetOrchestrator = IPuppetOrchestrator(_puppetOrchestrator);
        traderRoute = ITraderRoute(msg.sender);

        collateralToken = _collateralToken;
        indexToken = _indexToken;
        isLong = _isLong;

        IGMXRouter(puppetOrchestrator.getGMXRouter()).approvePlugin(puppetOrchestrator.getGMXPositionRouter());
    }

    // ====================== Modifiers ======================

    modifier onlyKeeperOrTraderRoute() {
        if (msg.sender != owner) {
            if (isRejected) {
                if (msg.sender != puppetOrchestrator.getKeeper()) revert Unauthorized();
            } else {
                if (msg.sender != address(traderRoute)) revert Unauthorized();
            }
        }
        _;
    }

    modifier onlyCallbackTarget() {
        if (msg.sender != owner && msg.sender != puppetOrchestrator.getCallbackTarget()) {
            revert NotCallbackTarget();
        }
        _;
    }

    // ====================== TraderRoute functions ======================

    function createPosition(bytes memory _positionData, bool _isIncrease) public nonReentrant onlyKeeperOrTraderRoute {
        if (isWaitingForCallback) revert WaitingForCallback();

        isWaitingForCallback = true;
        isIncrease = _isIncrease;

        uint256 _requiredAssets = _getRequiredAssets(_positionData, _isIncrease);

        if (_isIncrease) {
            if (isPositionOpen) {
                _getFees(_requiredAssets);
            } else {
                _getFeesAndCollateral(_requiredAssets);
            }
            _createIncreasePosition(_positionData);
        } else {
            _getFees(_requiredAssets);
            _createDecreasePosition(_positionData);
        }

        emit PositionCreated(_isIncrease);
    }

    function closePosition(bytes memory _positionData) external {
        createPosition(_positionData, false);

        if (_isOpenInterest()) revert PositionStillAlive();

        emit PositionClosed();
    }

    // ====================== liquidation ======================

    function onLiquidation() external nonReentrant onlyKeeper {
        if (!_isLiquidated()) revert PositionStillAlive();

        isWaitingForCallback = false;

        _repayBalance();
        
        _resetPosition();

        emit Liquidated();
    }

    // ====================== request callback ======================

    function approvePositionRequest() external nonReentrant onlyCallbackTarget {
        isRejected = false;
        isPositionOpen = true;

        traderRoute.notifyCallback();

        _repayBalance();

        bool _isIncrease = isIncrease;
        if (!_isIncrease && !_isOpenInterest()) {
            _resetPosition();
        }

        emit PositionApproved(_isIncrease);
    }

    function rejectPositionRequest() external nonReentrant onlyCallbackTarget {
        isRejected = true;

        bool _isIncrease = isIncrease;
        if (_isIncrease) {
            _repayBalance();

            if (!isPositionOpen) {
                _resetPosition();
            }
        }

        emit PositionRejected(_isIncrease);
    }

    // ====================== Internal functions ======================

    function _createIncreasePosition(bytes memory _positionData) internal {
        (address _collateralToken, address _indexToken, uint256 _amountIn, uint256 _minOut, uint256 _sizeDelta, uint256 _acceptablePrice, uint256 _executionFee)
            = abi.decode(_positionData, (address, address, uint256, uint256, uint256, uint256, uint256));

        address[] memory _path = new address[](1);
        _path[0] = _collateralToken;

        bytes32 _referralCode = puppetOrchestrator.getReferralCode();
        address _callbackTarget = puppetOrchestrator.getCallbackTarget();
        IGMXPositionRouter(puppetOrchestrator.getGMXPositionRouter()).createIncreasePosition(_path, _indexToken, _amountIn, _minOut, _sizeDelta, routeInfo.isLong, _acceptablePrice, _executionFee, _referralCode, _callbackTarget);

        puppetOrchestrator.updatePositionKeyToRouteAddress(_positionKey);

        emit CreateIncreasePosition(_positionKey, _amountIn, _minOut, _sizeDelta, _acceptablePrice, _executionFee);
    }

    function _createDecreasePosition(bytes memory _positionData) internal {
        (address _collateralToken, address _indexToken, uint256 _collateralDeltaUSD, uint256 _sizeDelta, uint256 _acceptablePrice, uint256 _minOut, uint256 _executionFee)
            = abi.decode(_positionData, (address, address, uint256, uint256, uint256, uint256, uint256));

        address[] memory _path = new address[](1);
        _path[0] = _collateralToken;

        address _callbackTarget = puppetOrchestrator.getCallbackTarget();
        IGMXPositionRouter(puppetOrchestrator.getGMXPositionRouter()).createDecreasePosition(_path, _indexToken, _collateralDeltaUSD, _sizeDelta, _route.isLong, address(this), _acceptablePrice, _minOut, _executionFee, false, _callbackTarget);

        if (puppetOrchestrator.getRouteForPositionKey(_positionKey) != address(this)) revert KeyError();

        emit CreateDecreasePosition(_positionKey, _minOut, _collateralDeltaUSD, _sizeDelta, _acceptablePrice, _executionFee);
    }

    // TODO - fix
    function _getFees(uint256 _requiredAssets) internal {
        uint256 _requiredShares = convertToShares(totalAssets, totalSupply, _requiredAssets);
        uint256 _requiredAssetsPerShare = _requiredAssets / _requiredShares;
        for (uint256 i = 0; i < EnumerableSet.length(puppetsSet); i++) {
            address _puppet = EnumerableSet.at(puppetsSet, i);
            uint256 _shares = EnumerableMap.get(puppetShares, _puppet);
            uint256 _puppetRequiredAmount = _requiredAssetsPerShare * _shares;

            puppetOrchestrator.debitPuppetAccount(_puppetRequiredAmount, _puppet);
        }
        puppetOrchestrator.sendFunds(_requiredAssets);
    }

    function _getFeesAndCollateral(uint256 _requiredAssets) internal {
        uint256 _totalSupply;
        uint256 _totalAssets;
        uint256 _traderAmountIn = traderRoute.getTraderAmountIn();
        address _traderRoute = address(traderRoute);
        EnumerableSet.AddressSet storage _puppetsSet = puppetOrchestrator.getPuppetsSet(positionKey);
        for (uint256 i = 0; i < EnumerableSet.length(_puppetsSet); i++) {
            address _puppet = EnumerableSet.at(_puppetsSet, i);
            uint256 _assets = puppetOrchestrator.getPuppetAllowance(_puppet, _traderRoute);

            if (_assets > _traderAmountIn) _assets = _traderAmountIn;

            if (puppetOrchestrator.isPuppetSolvent(_puppet)) {
                puppetOrchestrator.debitPuppetAccount(_assets, _puppet);
            } else {
                bytes32 _positionKey = puppetOrchestrator.getPositionKey(address(this), collateralToken, indexToken, isLong);
                puppetOrchestrator.liquidatePuppet(_puppet, _positionKey);
                continue;
            }

            uint256 _shares = convertToShares(_totalAssets, _totalSupply, _assets);
            if (_shares == 0 || _assets == 0) revert ZeroAmount();
            EnumerableMap.set(puppetShares, _puppet, _shares);

            _totalSupply += _shares;
            _totalAssets += _assets;
        }

        if (_totalAssets != _requiredAssets) revert AssetsAmonutMismatch();

        totalSupply = _totalSupply;
        totalAssets = _totalAssets;

        puppetOrchestrator.sendFunds(_requiredAssets);
    }

    function _repayBalance() internal {
        uint256 _totalAssets = address(this).balance;
        if (_totalAssets > 0) {
            uint256 _totalSupply = totalSupply;
            uint256 _balance = _totalAssets;
            for (uint256 i = 0; i < EnumerableSet.length(puppetsSet); i++) {
                address _puppet = EnumerableSet.at(puppetsSet, i);
                uint256 _shares = EnumerableMap.get(participantShares, _puppet);
                uint256 _assets = convertToAssets(_balance, _totalSupply, _shares);
                if (_shares == 0 || _assets == 0) revert ZeroAmount();

                puppetOrchestrator.creditPuppetAccount(_assets, _puppet);

                _totalSupply -= _shares;
                _balance -= _assets;
            }

            payable(address(puppetOrchestrator)).sendValue(_totalAssets);
        }
    }

    function _resetPosition() internal {
        isPositionOpen = false;
        totalAssets = 0;
        totalSupply = 0;
        for (uint256 i = 0; i < EnumerableMap.length(participantShares); i++) {
            (address _key, ) = EnumerableMap.at(participantShares, i);
            EnumerableMap.remove(participantShares, _key);
        }
    }

    function _isLiquidated() internal view returns (bool) {
        (uint256 state, ) = IVault(puppetOrchestrator.getGMXVault()).validateLiquidation(address(this), collateralToken, indexToken, isLong, false);

        return state > 0;
    }

    function _getRequiredAssets(bytes memory _positionData, bool _isIncrease) internal view returns (uint256) {
        uint256 _amountIn;
        uint256 _executionFee;

        if (_isIncrease) {
            (_amountIn, _executionFee,,,,) = abi.decode(_positionData, (uint256, uint256, uint256, uint256, uint256, address));
        } else {
            (_executionFee,) = abi.decode(_positionData, (uint256,));
        }

        return _amountIn + _executionFee;
    }

    function _isOpenInterest() internal view returns (bool) {
        address[] memory _collateralTokens = new address[](1);
        address[] memory _indexTokens = new address[](1);
        bool[] memory _isLong = new bool[](1);

        _collateralTokens[0] = collateralToken;
        _indexTokens[0] = indexToken;
        _isLong[0] = isLong;

        uint256[] memory _response = IGMXReader(puppetOrchestrator.getGMXReader()).getPositions(puppetOrchestrator.getGMXVault(), address(this), _collateralTokens, _indexTokens, _isLong);

        return _response[0] > 0 && _response[1] > 0;
    }

    function _convertToShares(uint256 _totalAssets, uint256 _totalSupply, uint256 _assets) internal pure returns (uint256 _shares) {
        if (_assets == 0) revert ZeroAmount();

        if (_totalAssets == 0) {
            _shares = _assets;
        } else {
            _shares = (_assets * _totalSupply) / _totalAssets;
        }

        if (_shares == 0) revert ZeroShares();
    }

    function _convertToAssets(uint256 _totalAssets, uint256 _totalSupply, uint256 _shares) internal pure returns (uint256 _assets) {
        if (_totalSupply == 0) {
            _assets = _shares;
        } else {
            _assets = (_shares * _totalAssets) / _totalSupply;
        }
    }
}