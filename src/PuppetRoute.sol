// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {IGMXReader} from "./interfaces/IGMXReader.sol";

import "./BaseRoute.sol";

import "forge-std/console.sol";

contract PuppetRoute is BaseRoute, IPuppetRoute {

    using SafeERC20 for IERC20;
    using Address for address payable;

    uint256 private totalAssets;
    uint256 private totalSupply;

    address public trader;

    bool public isPositionOpen;
    bool public isIncrease;
    bool public isRejected;

    EnumerableMap.AddressToUintMap private puppetShares;

    ITraderRoute public traderRoute;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    constructor(
        address _puppetOrchestrator,
        address _trader,
        address _owner,
        address _collateralToken, 
        address _indexToken, 
        bool _isLong
        ) BaseRoute(_puppetOrchestrator, _owner, _collateralToken, _indexToken, _isLong) {

        trader = _trader;
        traderRoute = ITraderRoute(msg.sender);
    }

    // ============================================================================================
    // Modifiers
    // ============================================================================================

    modifier onlyKeeperOrTraderRoute() {
        if (msg.sender != owner) {
            if (isRejected) {
                if (msg.sender != puppetOrchestrator.getKeeper()) revert NotKeeper();
            } else {
                if (msg.sender != address(traderRoute)) revert NotTraderRoute();
            }
        }
        _;
    }

    // ============================================================================================
    // View Functions
    // ============================================================================================

    function getIsPositionOpen() external view returns (bool) {
        return isPositionOpen;
    }

    // ============================================================================================
    // TraderRoute Functions
    // ============================================================================================

    function createPosition(bytes memory _positionData, bool _isIncrease) public nonReentrant onlyKeeperOrTraderRoute returns (bytes32 _positionKey) {
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
            _positionKey = _createIncreasePosition(_positionData);
        } else {
            _getFees(_requiredAssets);
            _positionKey = _createDecreasePosition(_positionData);
        }
    }

    function closePosition(bytes memory _positionData) external {
        createPosition(_positionData, false);

        if (_isOpenInterest()) revert PositionStillAlive();
    }

    // ============================================================================================
    // On Liquidation
    // ============================================================================================

    // slither-disable-next-line reentrancy-eth
    function onLiquidation() external nonReentrant {
        if (msg.sender != owner && msg.sender != puppetOrchestrator.getKeeper()) revert NotKeeper();
        if (!_isLiquidated()) revert PositionStillAlive();

        isWaitingForCallback = false;

        _repayBalance();
        
        _resetPosition();

        emit Liquidated();
    }

    // ============================================================================================
    // Callback Functions
    // ============================================================================================

    // slither-disable-next-line reentrancy-eth
    function approvePositionRequest() external override nonReentrant onlyCallbackTarget {
        isRejected = false;
        isPositionOpen = true;
        isWaitingForCallback = false;

        traderRoute.notifyCallback();

        _repayBalance();

        bool _isIncrease = isIncrease;
        if (!_isIncrease && !_isOpenInterest()) {
            _resetPosition();
        }

        emit ApprovePositionRequest();
    }

    // slither-disable-next-line reentrancy-eth
    function rejectPositionRequest() external override nonReentrant onlyCallbackTarget {
        isRejected = true;
        isWaitingForCallback = false;

        bool _isIncrease = isIncrease;
        if (_isIncrease) {
            _repayBalance();

            if (!isPositionOpen) {
                _resetPosition();
            }
        }

        emit RejectPositionRequest();
    }

    // ============================================================================================
    // Owner Functions
    // ============================================================================================

    function setTraderRoute(address _puppetRoute) external onlyOwner {
        traderRoute = ITraderRoute(_puppetRoute);
    }

    // ============================================================================================
    // Internal Functions
    // ============================================================================================

    function _createIncreasePosition(bytes memory _positionData) internal override returns (bytes32 _positionKey) {
        (uint256 _amountIn, uint256 _minOut, uint256 _sizeDelta, uint256 _acceptablePrice, uint256 _executionFee)
            = abi.decode(_positionData, (uint256, uint256, uint256, uint256, uint256));

        address[] memory _path = new address[](1);
        _path[0] = collateralToken;

        // slither-disable-next-line arbitrary-send-eth
        _positionKey = IGMXPositionRouter(puppetOrchestrator.getGMXPositionRouter()).createIncreasePositionETH{ value: _amountIn + _executionFee }(
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

        puppetOrchestrator.updatePositionKeyToTraderRoute(_positionKey);

        emit CreateIncreasePosition(_positionKey, _amountIn, _minOut, _sizeDelta, _acceptablePrice, _executionFee);
    }

    function _createDecreasePosition(bytes memory _positionData) internal override returns (bytes32 _positionKey) {
        (uint256 _collateralDelta, uint256 _sizeDelta, uint256 _acceptablePrice, uint256 _minOut, uint256 _executionFee)
            = abi.decode(_positionData, (uint256, uint256, uint256, uint256, uint256));

        address[] memory _path = new address[](1);
        _path[0] = collateralToken;

        // slither-disable-next-line arbitrary-send-eth
        _positionKey = IGMXPositionRouter(puppetOrchestrator.getGMXPositionRouter()).createDecreasePosition{ value: _executionFee }(
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

        if (puppetOrchestrator.getTraderRouteForPositionKey(_positionKey) != address(this)) revert KeyError();

        emit CreateDecreasePosition(_positionKey, _minOut, _collateralDelta, _sizeDelta, _acceptablePrice, _executionFee);
    }

    function _getFees(uint256 _requiredAssets) internal {
        uint256 _totalAssets;
        uint256 _requiredShares = _convertToShares(totalAssets, totalSupply, _requiredAssets);
        bytes32 _key = puppetOrchestrator.getTraderRouteKey(trader, collateralToken, indexToken, isLong);
        address[] memory _puppets = puppetOrchestrator.getPuppetsForRoute(_key);
        for (uint256 i = 0; i < _puppets.length; i++) {
            address _puppet = _puppets[i];
            uint256 _shares = EnumerableMap.get(puppetShares, _puppet);
            uint256 _puppetRequiredAmount = (_requiredAssets * _shares) / _requiredShares;

            puppetOrchestrator.debitPuppetAccount(_puppetRequiredAmount, _puppet);

            _totalAssets += _puppetRequiredAmount;
        }

        if (_totalAssets != _requiredAssets) revert AssetsAmonutMismatch();

        puppetOrchestrator.sendFunds(_requiredAssets);

        emit FeesCollected(_requiredAssets);
    }

    function _getFeesAndCollateral(uint256 _requiredAssets) internal {
        uint256 _totalSupply;
        uint256 _totalAssets;
        uint256 _traderAmountIn = traderRoute.getTraderAmountIn();
        bytes32 _key = puppetOrchestrator.getTraderRouteKey(trader, collateralToken, indexToken, isLong);
        address[] memory _puppets = puppetOrchestrator.getPuppetsForRoute(_key);
        for (uint256 i = 0; i < _puppets.length; i++) {
            address _puppet = _puppets[i];
            uint256 _assets = puppetOrchestrator.getPuppetAllowance(_puppet, address(traderRoute));

            if (_assets > _traderAmountIn) _assets = _traderAmountIn;

            if (puppetOrchestrator.isPuppetSolvent(_puppet)) {
                puppetOrchestrator.debitPuppetAccount(_assets, _puppet);
            } else {
                puppetOrchestrator.liquidatePuppet(_puppet, _key);
                continue;
            }

            uint256 _shares = _convertToShares(_totalAssets, _totalSupply, _assets);
            if (_shares == 0 || _assets == 0) revert ZeroAmount();

            EnumerableMap.set(puppetShares, _puppet, _shares);

            _totalSupply += _shares;
            _totalAssets += _assets;
        }

        console.log("_totalAssets", _totalAssets);
        console.log("_requiredAssets", _requiredAssets);
        // 1 1500000000000000000
        // 1 10000180000000000000

        if (_totalAssets != _requiredAssets) revert AssetsAmonutMismatch();

        totalSupply = _totalSupply;
        totalAssets = _totalAssets;

        puppetOrchestrator.sendFunds(_requiredAssets);

        emit FeesAndCollateralCollected(_requiredAssets);
    }

    function _repayBalance() internal override {
        uint256 _totalAssets = address(this).balance;
        if (_totalAssets > 0) {
            uint256 _totalSupply = totalSupply;
            uint256 _balance = _totalAssets;
            bytes32 _key = puppetOrchestrator.getTraderRouteKey(trader, collateralToken, indexToken, isLong);
            address[] memory _puppets = puppetOrchestrator.getPuppetsForRoute(_key);
            for (uint256 i = 0; i < _puppets.length; i++) {
                address _puppet = _puppets[i];
                uint256 _shares = EnumerableMap.get(puppetShares, _puppet);
                uint256 _assets = _convertToAssets(_balance, _totalSupply, _shares);
                if (_shares == 0 || _assets == 0) revert ZeroAmount();

                puppetOrchestrator.creditPuppetAccount(_assets, _puppet);

                _totalSupply -= _shares;
                _balance -= _assets;
            }

            payable(address(puppetOrchestrator)).sendValue(_totalAssets);
        }

        emit RepayBalance(_totalAssets);
    }

    function _resetPosition() internal {
        isPositionOpen = false;
        totalAssets = 0;
        totalSupply = 0;
        for (uint256 i = 0; i < EnumerableMap.length(puppetShares); i++) {
            (address _key, ) = EnumerableMap.at(puppetShares, i);
            EnumerableMap.remove(puppetShares, _key);
        }

        emit ResetPosition();
    }

    function _getRequiredAssets(bytes memory _positionData, bool _isIncrease) internal pure returns (uint256) {
        uint256 _amountIn = 0;
        uint256 _executionFee = 0;
        if (_isIncrease) {
            (_amountIn,,,, _executionFee) = abi.decode(_positionData, (uint256, uint256, uint256, uint256, uint256));
        } else {
            (,,,, _executionFee) = abi.decode(_positionData, (uint256, uint256, uint256, uint256, uint256));
        }

        return _amountIn + _executionFee;
    }

    // TODO - fix so it's like in test
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

        if (_shares == 0) revert ZeroAmount();
    }

    function _convertToAssets(uint256 _totalAssets, uint256 _totalSupply, uint256 _shares) internal pure returns (uint256 _assets) {
        if (_totalSupply == 0) {
            _assets = _shares;
        } else {
            _assets = (_shares * _totalAssets) / _totalSupply;
        }
    }
}