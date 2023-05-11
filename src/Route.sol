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

    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // the address representing ETH

    bool public isLong;
    bool public isPositionOpen;
    bool public isWaitingForCallback;

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

        _updateLastPositionOpenedTimestamp(); // used to limit the number of position that can be opened in a given time period

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

    function approvePlugin() external onlyOwner {
        IGMXRouter(orchestrator.getGMXRouter()).approvePlugin(orchestrator.getGMXPositionRouter());

        emit PluginApproved();
    }

    function setOrchestrator(address _orchestrator) external onlyOwner {
        orchestrator = IOrchestrator(_orchestrator);

        emit OrchestratorSet(_orchestrator);
    }

    function rescueStuckTokens(address _token, address _to) external onlyOwner {
        if (address(this).balance > 0) payable(_to).sendValue(address(this).balance);
        if (_token != address(0) && IERC20(_token).balanceOf(address(this)) > 0) IERC20(_token).safeTransfer(_to, IERC20(_token).balanceOf(address(this)));

        emit StuckTokensRescued(_token, _to);
    }

    // ============================================================================================
    // Internal Functions
    // ============================================================================================

    function _getPuppetsAssetsAndAllocateShares(uint256 _traderAmountIn) internal returns (uint256 _puppetsAmountIn) {
        if (_traderAmountIn > 0) {
            uint256 _totalManagementFee;
            uint256 _managementFeePercentage = orchestrator.getManagementFeePercentage();
            uint256 _totalSupply = totalSupply;
            uint256 _totalAssets = totalAssets;
            address _trader = trader;
            address _collateralToken = collateralToken;
            bytes32 _routeKey = orchestrator.getRouteKey(_trader, _collateralToken, indexToken, isLong);
            address[] memory _puppets = orchestrator.getPuppetsForRoute(_routeKey);
            for (uint256 i = 0; i < _puppets.length; i++) {
                address _puppet = _puppets[i];
                if (!_isOpenInterest() && !orchestrator.canOpenNewPosition(address(this), _puppet)) {
                    orchestrator.liquidatePuppet(_puppet, _routeKey);
                }

                uint256 _allowancePercentage = orchestrator.getPuppetAllowancePercentage(_puppet, address(this));
                uint256 _assets = (orchestrator.getPuppetAccountBalance(_collateralToken, _puppet) * _allowancePercentage) / 100;

                if (_assets > _traderAmountIn) _assets = _traderAmountIn;

                if (orchestrator.isPuppetSolvent(_collateralToken, _puppet)) {
                    orchestrator.debitPuppetAccount(_assets, _collateralToken, _puppet);
                } else {
                    orchestrator.liquidatePuppet(_puppet, _routeKey);
                    continue;
                }

                _puppetsAmountIn += _assets;

                if (_managementFeePercentage > 0) {
                    uint256 _managementFee = (_assets * _managementFeePercentage) / 10000;

                    _totalManagementFee += _managementFee;
                    _assets -= _managementFee;
                }

                uint256 _shares = _convertToShares(_totalAssets, _totalSupply, _assets);

                EnumerableMap.set(participantShares, _puppet, _shares);

                _totalSupply += _shares;
                _totalAssets += _assets;
            }

            uint256 _traderShares = _convertToShares(_totalAssets, _totalSupply, _traderAmountIn);

            EnumerableMap.set(participantShares, _trader, _traderShares);

            totalSupply = _totalSupply;
            totalAssets = _totalAssets;

            // pull funds from Orchestrator
            orchestrator.sendFunds(_puppetsAmountIn, _collateralToken);

            // send management fee to owner
            if (_totalManagementFee > 0) {
                if (_collateralToken == ETH) payable(owner).sendValue(_totalManagementFee);
                else IERC20(_collateralToken).safeTransfer(owner, _totalManagementFee);
            }
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
            uint256 _puppetsAssets;
            uint256 _totalSupply = totalSupply;
            uint256 _balance = _totalAssets;
            address _collateralToken = collateralToken;
            bytes32 _key = orchestrator.getRouteKey(trader, _collateralToken, indexToken, isLong);
            address[] memory _puppets = orchestrator.getPuppetsForRoute(_key);
            for (uint256 i = 0; i < _puppets.length; i++) {
                address _puppet = _puppets[i];
                uint256 _shares = EnumerableMap.get(participantShares, _puppet);
                uint256 _assets = _convertToAssets(_balance, _totalSupply, _shares);

                orchestrator.creditPuppetAccount(_assets, _collateralToken, _puppet);

                _totalSupply -= _shares;
                _balance -= _assets;

                _puppetsAssets += _assets;
            }

            uint256 _traderShares = EnumerableMap.get(participantShares, trader);
            uint256 _traderAssets = _convertToAssets(_balance, _totalSupply, _traderShares);

            if (_collateralToken == ETH) {
                payable(address(orchestrator)).sendValue(_puppetsAssets);
                payable(trader).sendValue(_traderAssets);
            } else {
                IERC20(_collateralToken).safeTransfer(address(orchestrator), _puppetsAssets);
                IERC20(_collateralToken).safeTransfer(trader, _traderAssets);
            }
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

    function _updateLastPositionOpenedTimestamp() internal {
        bytes32 _routeKey = orchestrator.getRouteKey(trader, collateralToken, indexToken, isLong);
        address[] memory _puppets = orchestrator.getPuppetsForRoute(_routeKey);
        for (uint256 i = 0; i < _puppets.length; i++) {
            address _puppet = _puppets[i];
            orchestrator.updateLastPositionOpenedTimestamp(address(this), _puppet);
        }
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