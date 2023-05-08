// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {IGMXRouter} from "./interfaces/IGMXRouter.sol";
import {IGMXPositionRouter} from "./interfaces/IGMXPositionRouter.sol";
import {IGMXVault} from "./interfaces/IGMXVault.sol";

import {IOrchestrator} from "./interfaces/IOrchestrator.sol";
import {IPositionValidator} from "./interfaces/IPositionValidator.sol";
import {IRoute} from "./interfaces/IRoute.sol";

contract Route is ReentrancyGuard, IRoute {

    using SafeERC20 for IERC20;
    using Address for address payable;

    uint256 totalSupply;
    uint256 totalAssets;

    address public owner;
    address public trader;
    address public collateralToken;
    address public indexToken;
    
    bool public isLong;
    bool public isWaitingForCallback;
    bool public isPositionOpen;

    EnumerableMap.AddressToUintMap participantShares;

    IOrchestrator public orchestrator;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    constructor(address _orchestrator, address _owner, address _trader, address _collateralToken, address _indexToken, bool _isLong) {
        orchestrator = IOrchestrator(_orchestrator);
        owner = _owner;
        trader = _trader;
        collateralToken = _collateralToken;
        indexToken = _indexToken;
        isLong = _isLong;

        IGMXRouter(orchestrator.getGMXRouter()).approvePlugin(orchestrator.getGMXPositionRouter());
    }

    // ============================================================================================
    // Modifiers
    // ============================================================================================

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyCallbackTarget() {
        if (msg.sender != owner && msg.sender != orchestrator.getCallbackTarget()) revert NotCallbackTarget();
        _;
    }

    // ============================================================================================
    // Trader Functions
    // ============================================================================================

    function createPositionRequest(bytes memory _traderPositionData, uint256 _executionFee, bool _isIncrease) external payable nonReentrant returns (bytes32 _requestKey) {
        if (isWaitingForCallback) revert WaitingForCallback();
        if (msg.sender != trader) revert NotTrader();
        if (msg.value < _executionFee) revert InvalidExecutionFee();

        isWaitingForCallback = true;

        uint256 _traderAmountIn;
        uint256 _puppetsAmountIn;
        if (_isIncrease) {
            _traderAmountIn = msg.value - _executionFee;
            _puppetsAmountIn = _getPuppetsAssetsAndAllocateShares(_traderAmountIn);
            _requestKey = _createIncreasePosition(_traderPositionData, _traderAmountIn, _puppetsAmountIn, _executionFee);
        } else {
            if (msg.value != _executionFee) revert InvalidExecutionFee();
            _requestKey = _createDecreasePosition(_traderPositionData, _executionFee);
        }

        IPositionValidator(orchestrator.getPositionValidator()).validatePositionParameters(_traderPositionData, _traderAmountIn, _puppetsAmountIn, _isIncrease);
    }

    // ============================================================================================
    // Keeper Functions
    // ============================================================================================

    function onLiquidation() external nonReentrant {
        if (msg.sender != owner && msg.sender != orchestrator.getKeeper()) revert NotKeeper();
        if (!_isLiquidated()) revert PositionStillAlive();

        _repayBalance();

        emit Liquidated();
    }

    // ============================================================================================
    // Callback Functions
    // ============================================================================================

    function approvePositionRequest() external override nonReentrant onlyCallbackTarget {
        isWaitingForCallback = false;
        isPositionOpen = true;

        // TODO: for allowing several position requests at a time - _writeShares() to storage only here
        // _writeShares();

        _repayBalance();

        emit ApprovePositionRequest();
    }

    function rejectPositionRequest() external override nonReentrant onlyCallbackTarget {
        isWaitingForCallback = false;

        _repayBalance();

        emit RejectPositionRequest();
    }

    // ============================================================================================
    // Owner Functions
    // ============================================================================================

    function approvePlugin() external virtual onlyOwner {
        IGMXRouter(orchestrator.getGMXRouter()).approvePlugin(orchestrator.getGMXPositionRouter());
    }

    function setOrchestrator(address _orchestrator) external virtual onlyOwner {
        orchestrator = IOrchestrator(_orchestrator);
    }

    // ============================================================================================
    // Internal Functions
    // ============================================================================================

    function _getPuppetsAssetsAndAllocateShares(uint256 _traderAmountIn) internal returns (uint256 _puppetsAmountIn) {
        if (_traderAmountIn > 0) {
            uint256 _totalSupply = totalSupply;
            uint256 _totalAssets = totalAssets;
            address _trader = trader;
            bytes32 _routeKey = orchestrator.getRouteKey(_trader, collateralToken, indexToken, isLong);
            address[] memory _puppets = orchestrator.getPuppetsForRoute(_routeKey);
            for (uint256 i = 0; i < _puppets.length; i++) {
                address _puppet = _puppets[i];
                uint256 _assets = orchestrator.getPuppetAllowance(_puppet, address(this));

                if (_assets > _traderAmountIn) _assets = _traderAmountIn;

                if (orchestrator.isPuppetSolvent(_puppet)) {
                    orchestrator.debitPuppetAccount(_assets, _puppet);
                } else {
                    orchestrator.liquidatePuppet(_puppet, _routeKey);
                    continue;
                }

                uint256 _shares = _convertToShares(_totalAssets, _totalSupply, _assets);

                _puppetsAmountIn += _assets;

                EnumerableMap.set(participantShares, _puppet, _shares);

                _totalSupply += _shares;
                _totalAssets += _assets;
            }

            uint256 _traderShares = _convertToShares(_totalAssets, _totalSupply, _traderAmountIn);

            EnumerableMap.set(participantShares, _trader, _traderShares);

            totalSupply = _totalSupply;
            totalAssets = _totalAssets;

            orchestrator.sendFunds(_puppetsAmountIn);
        }
    }

    function _createIncreasePosition(bytes memory _traderPositionData, uint256 _traderAmountIn, uint256 _puppetsAmountIn, uint256 _executionFee) internal returns (bytes32 _requestKey) {
        (uint256 _minOut, uint256 _sizeDelta, uint256 _acceptablePrice) = abi.decode(_traderPositionData, (uint256, uint256, uint256));

        address[] memory _path = new address[](1);
        _path[0] = collateralToken;

        uint256 _amountIn = _traderAmountIn + _puppetsAmountIn + _executionFee;

        _requestKey = IGMXPositionRouter(orchestrator.getGMXPositionRouter()).createIncreasePositionETH{ value: _amountIn } (
            _path,
            indexToken,
            _minOut,
            _sizeDelta,
            isLong,
            _acceptablePrice,
            _executionFee,
            orchestrator.getReferralCode(),
            orchestrator.getCallbackTarget()
        );

        orchestrator.updateRequestKeyToRoute(_requestKey);

        emit CreateIncreasePosition(_requestKey, _amountIn, _minOut, _sizeDelta, _acceptablePrice, _executionFee);
    }

    function _createDecreasePosition(bytes memory _traderPositionData, uint256 _executionFee) internal returns (bytes32 _requestKey) {
        (uint256 _collateralDelta, uint256 _sizeDelta, uint256 _acceptablePrice, uint256 _minOut)
            = abi.decode(_traderPositionData, (uint256, uint256, uint256, uint256));

        address[] memory _path = new address[](1);
        _path[0] = collateralToken;

        _requestKey = IGMXPositionRouter(orchestrator.getGMXPositionRouter()).createDecreasePosition{ value: _executionFee } (
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
            orchestrator.getCallbackTarget()
        );

        if (orchestrator.getRouteForRequestKey(_requestKey) != address(this)) revert KeyError();

        emit CreateDecreasePosition(_requestKey, _minOut, _collateralDelta, _sizeDelta, _acceptablePrice, _executionFee);
    }

    function _repayBalance() internal {
        uint256 _totalAssets = address(this).balance;
        if (_totalAssets > 0) {
            uint256 _totalSupply = totalSupply;
            uint256 _balance = _totalAssets;
            bytes32 _key = orchestrator.getRouteKey(trader, collateralToken, indexToken, isLong);
            address[] memory _puppets = orchestrator.getPuppetsForRoute(_key);
            for (uint256 i = 0; i < _puppets.length; i++) {
                address _puppet = _puppets[i];
                uint256 _shares = EnumerableMap.get(participantShares, _puppet);
                uint256 _assets = _convertToAssets(_balance, _totalSupply, _shares);

                orchestrator.creditPuppetAccount(_assets, _puppet);

                _totalSupply -= _shares;
                _balance -= _assets;
            }

            uint256 _traderShares = EnumerableMap.get(participantShares, trader);
            uint256 _traderAssets = _convertToAssets(_balance, _totalSupply, _traderShares);

            payable(address(orchestrator)).sendValue(_totalAssets - _traderAssets);
            payable(trader).sendValue(_traderAssets);
        }

        if (!_isOpenInterest()) {
            _resetPosition();
        }

        emit RepayBalance(_totalAssets);
    }

    function _isOpenInterest() internal view returns (bool) {
        (uint256 _size, uint256 _collateral,,,,,,) = IGMXVault(orchestrator.getGMXVault()).getPosition(address(this), collateralToken, indexToken, isLong);

        return _size > 0 && _collateral > 0;
    }

    function _resetPosition() internal {
        isPositionOpen = false;
        totalAssets = 0;
        totalSupply = 0;
        for (uint256 i = 0; i < EnumerableMap.length(participantShares); i++) {
            (address _key, ) = EnumerableMap.at(participantShares, i);
            EnumerableMap.remove(participantShares, _key);
        }

        emit ResetPosition();
    }

    function _isLiquidated() internal view returns (bool) {
        (uint256 state, ) = IGMXVault(orchestrator.getGMXVault()).validateLiquidation(address(this), collateralToken, indexToken, isLong, false);

        return state > 0;
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
        if (_shares == 0) revert ZeroAmount();

        if (_totalSupply == 0) {
            _assets = _shares;
        } else {
            _assets = (_shares * _totalAssets) / _totalSupply;
        }

        if (_assets == 0) revert ZeroAmount();
    }

    // ============================================================================================
    // Receive Function
    // ============================================================================================

    receive() external payable {
        if (orchestrator.getReferralRebatesSender() == msg.sender) payable(orchestrator.getPrizePoolDistributor()).sendValue(msg.value);
    }
}