// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {IWETH} from "./interfaces/IWETH.sol";
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
    uint256 realisedPnl; // realised P&L at the start of a new position. used to calculate the performance fee 

    address public owner;
    address public trader;
    address public collateralToken;
    address public indexToken;

    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // the address representing ETH
    address internal constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    bool public isLong;
    bool public isPositionOpen;
    bool public isWaitingForCallback;

    bytes private traderRepaymentData;

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

    function createPositionRequest(bytes memory _traderPositionData, bytes memory _traderSwapData, bool _isIncrease) public payable nonReentrant returns (bytes32 _requestKey) {
        if (isWaitingForCallback) revert WaitingForCallback();
        if (msg.sender != trader) revert NotTrader();

        isWaitingForCallback = true;

        uint256 _traderAmountIn;
        uint256 _puppetsAmountIn;
        address _positionValidator = orchestrator.getPositionValidator();
        if (_isIncrease) {
            _traderAmountIn = _getTraderAssetsAndAllocateShares(_traderSwapData);
            _puppetsAmountIn = _getPuppetsAssetsAndAllocateShares(_traderAmountIn);
            _requestKey = _createIncreasePositionRequest(_traderPositionData, _traderAmountIn, _puppetsAmountIn);
        } else {
            IPositionValidator(_positionValidator).validateSwapPath(_traderSwapData, collateralToken);
            traderRepaymentData = _traderSwapData;
            _requestKey = _createDecreasePositionRequest(_traderPositionData);
        }

        IPositionValidator(_positionValidator).validatePositionParameters(_traderPositionData, _traderAmountIn, _puppetsAmountIn, _isIncrease);
    }

    function createIncreasePositionRequestETH(bytes memory _traderPositionData, uint256 _minOut) external payable returns (bytes32 _requestKey) {
        (,,, uint256 _executionFee) = abi.decode(_traderPositionData, (uint256, uint256, uint256, uint256));
        uint256 _amount = msg.value;
        address _weth = WETH;
        
        IWETH(_weth).deposit{ value: _amount - _executionFee }();

        address[] memory _path = new address[](2);
        _path[0] = _weth;
        _path[1] = collateralToken;
        bytes memory _traderSwapData = abi.encodePacked(_path, _amount, _minOut);

        return createPositionRequest(_traderPositionData, _traderSwapData, true);
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

        // used to limit the number of position that can be opened in a given time period
        _updateLastPositionOpenedTimestamp();

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
        if (IERC20(_token).balanceOf(address(this)) > 0) IERC20(_token).safeTransfer(_to, IERC20(_token).balanceOf(address(this)));

        emit StuckTokensRescued(_token, _to);
    }

    // ============================================================================================
    // Internal Functions
    // ============================================================================================

    function _getTraderAssetsAndAllocateShares(bytes memory _traderSwapData) internal returns (uint256 _traderAmountIn) {
        (address[] memory _path, uint256 _amount, uint256 _minOut) = abi.decode(_traderSwapData, (address[], uint256, uint256));

        if (_amount > 0) {
            address _trader = trader;
            address _fromToken = _path[0];
            IERC20(_fromToken).safeTransferFrom(_trader, address(this), _amount);

            if (_fromToken == collateralToken) {
                _traderAmountIn = _amount;
            } else {
                address _toToken = _path[_path.length - 1];
                if (_toToken != collateralToken) revert InvalidPath();

                address _router = orchestrator.getGMXRouter();
                _approve(_router, _fromToken, _amount);

                uint256 _before = IERC20(_toToken).balanceOf(address(this));
                IGMXRouter(_router).swap(_path, _amount, _minOut, address(this));
                _traderAmountIn = IERC20(_toToken).balanceOf(address(this)) - _before;
            }

            uint256 _traderShares = _convertToShares(totalAssets, totalSupply, _traderAmountIn);

            EnumerableMap.set(participantShares, _trader, _traderShares);

            totalSupply += _traderShares;
            totalAssets += _traderAmountIn;

            emit TraderAssetsAndSharesAllocated(_traderAmountIn, _traderShares);
        }
    }

    function _getPuppetsAssetsAndAllocateShares(uint256 _traderAmountIn) internal returns (uint256 _puppetsAmountIn) {
        if (_traderAmountIn > 0) {
            uint256 _totalManagementFee;
            uint256 _managementFeePercentage = orchestrator.getManagementFeePercentage();
            uint256 _totalSupply = totalSupply;
            uint256 _totalAssets = totalAssets;
            address _collateralToken = collateralToken;
            bool _isOI = _isOpenInterest();
            bytes32 _routeKey = orchestrator.getRouteKey(trader, _collateralToken, indexToken, isLong);
            address[] memory _puppets = orchestrator.getPuppetsForRoute(_routeKey);
            for (uint256 i = 0; i < _puppets.length; i++) {
                address _puppet = _puppets[i];
                if (!_isOI && !orchestrator.canOpenNewPosition(address(this), _puppet)) {
                    orchestrator.liquidatePuppet(_puppet, _routeKey);
                }

                uint256 _allowancePercentage = orchestrator.getPuppetAllowancePercentage(_puppet, address(this));
                uint256 _puppetAmountIn = (orchestrator.getPuppetAccountBalance(_collateralToken, _puppet) * _allowancePercentage) / 100;

                if (_puppetAmountIn > _traderAmountIn) _puppetAmountIn = _traderAmountIn;

                if (orchestrator.isPuppetSolvent(_collateralToken, _puppet)) {
                    orchestrator.debitPuppetAccount(_puppetAmountIn, _collateralToken, _puppet);
                } else {
                    orchestrator.liquidatePuppet(_puppet, _routeKey);
                    continue;
                }

                _puppetsAmountIn += _puppetAmountIn;

                if (_managementFeePercentage > 0) {
                    uint256 _managementFee = (_puppetAmountIn * _managementFeePercentage) / 10000;

                    _totalManagementFee += _managementFee;
                    _puppetAmountIn -= _managementFee;
                }

                uint256 _puppetShares = _convertToShares(_totalAssets, _totalSupply, _puppetAmountIn);

                EnumerableMap.set(participantShares, _puppet, _puppetShares);

                _totalSupply += _puppetShares;
                _totalAssets += _puppetAmountIn;
            }

            totalSupply = _totalSupply;
            totalAssets = _totalAssets;

            // pull funds from Orchestrator
            orchestrator.sendFunds(_puppetsAmountIn, _collateralToken, address(this));

            // send management fee to owner
            if (_totalManagementFee > 0) IERC20(_collateralToken).safeTransfer(owner, _totalManagementFee);

            emit PuppetsAssetsAndSharesAllocated(_puppetsAmountIn, _totalManagementFee);
        }
    }

    function _createIncreasePositionRequest(bytes memory _traderPositionData, uint256 _traderAmountIn, uint256 _puppetsAmountIn) internal returns (bytes32 _requestKey) {
        (uint256 _minOut, uint256 _sizeDelta, uint256 _acceptablePrice, uint256 _executionFee) = abi.decode(_traderPositionData, (uint256, uint256, uint256, uint256));

        if (msg.value != _executionFee) revert InvalidExecutionFee();

        address[] memory _path = new address[](1);
        _path[0] = collateralToken;

        uint256 _amountIn = _traderAmountIn + _puppetsAmountIn;

        _requestKey = IGMXPositionRouter(orchestrator.getGMXPositionRouter()).createIncreasePosition{ value: _executionFee } (
            _path,
            indexToken,
            _amountIn,
            _minOut,
            _sizeDelta,
            isLong,
            _acceptablePrice,
            _executionFee,
            orchestrator.getReferralCode(),
            orchestrator.getCallbackTarget()
        );

        orchestrator.updateRequestKeyToRoute(_requestKey);

        if (!_isOpenInterest()) realisedPnl = _getRealisedPnl();

        emit CreateIncreasePosition(_requestKey, _amountIn, _minOut, _sizeDelta, _acceptablePrice, _executionFee);
    }

    function _createDecreasePositionRequest(bytes memory _traderPositionData) internal returns (bytes32 _requestKey) {
        (uint256 _collateralDelta, uint256 _sizeDelta, uint256 _acceptablePrice, uint256 _minOut, uint256 _executionFee)
            = abi.decode(_traderPositionData, (uint256, uint256, uint256, uint256, uint256));

        if (msg.value != _executionFee) revert InvalidExecutionFee();

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
            false, // _withdrawETH
            orchestrator.getCallbackTarget()
        );

        if (orchestrator.getRouteForRequestKey(_requestKey) != address(this)) revert KeyError();

        emit CreateDecreasePosition(_requestKey, _minOut, _collateralDelta, _sizeDelta, _acceptablePrice, _executionFee);
    }

    function _repayBalance() internal {
        address _collateralToken = collateralToken;
        uint256 _totalAssets = IERC20(_collateralToken).balanceOf(address(this));
        if (_totalAssets > 0) {
            uint256 _puppetsAssets;
            uint256 _totalSupply = totalSupply;
            uint256 _balance = _totalAssets;
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

            IERC20(_collateralToken).safeTransfer(address(orchestrator), _puppetsAssets);
            _repayTrader(_traderAssets);
        }

        if (!_isOpenInterest()) {
            _resetPosition();
        }

        emit RepayBalance(_totalAssets);
    }

    function _repayTrader(uint256 _traderAssets) internal {
        (address[] memory _path, uint256 _minOut, address _receiver) = abi.decode(traderRepaymentData, (address[], uint256, address));
        address _fromToken = collateralToken;
        address _toToken = _path[_path.length - 1];
        address _router = orchestrator.getGMXRouter();
        if (_fromToken != _toToken && _toToken != ETH) {
            _approve(_router, _fromToken, _traderAssets);

            uint256 _before = IERC20(_toToken).balanceOf(address(this));
            IGMXRouter(_router).swap(_path, _traderAssets, _minOut, address(this));
            _traderAssets = IERC20(_toToken).balanceOf(address(this)) - _before;
        }

        if (_toToken == ETH) {
            IGMXRouter(_router).swapTokensToETH(_path, _traderAssets, _minOut, payable(_receiver));
        } else {
            IERC20(_toToken).safeTransfer(_receiver, _traderAssets);
        }
        
        uint256 _ethBalance = address(this).balance;
        if (_ethBalance > 0) {
            payable(_receiver).sendValue(_ethBalance);
        }
    }

    function _isOpenInterest() internal view returns (bool) {
        (uint256 _size, uint256 _collateral,,,,,,) = IGMXVault(orchestrator.getGMXVault()).getPosition(address(this), collateralToken, indexToken, isLong);

        return _size > 0 && _collateral > 0;
    }

    function _resetPosition() internal {
        _chargePerformanceFee();

        isPositionOpen = false;
        totalAssets = 0;
        totalSupply = 0;
        for (uint256 i = 0; i < EnumerableMap.length(participantShares); i++) {
            (address _key, ) = EnumerableMap.at(participantShares, i);
            EnumerableMap.remove(participantShares, _key);
        }

        emit ResetPosition();
    }

    function _chargePerformanceFee() internal {
        uint256 _currentRealisedPnl = _getRealisedPnl();
        uint256 _realisedPnlBefore = realisedPnl;
        if (_currentRealisedPnl > _realisedPnlBefore && (_currentRealisedPnl - _realisedPnlBefore) > 0) {
            uint256 _performanceFeeAmount = _currentRealisedPnl - _realisedPnlBefore;
            uint256 _totalAssets = _performanceFeeAmount;
            uint256 _totalSupply = totalSupply;
            address _collateralToken = collateralToken;
            bytes32 _key = orchestrator.getRouteKey(trader, collateralToken, indexToken, isLong);
            address[] memory _puppets = orchestrator.getPuppetsForRoute(_key);
            for (uint256 i = 0; i < _puppets.length; i++) {
                address _puppet = _puppets[i];
                uint256 _shares = EnumerableMap.get(participantShares, _puppet);
                uint256 _assets = _convertToAssets(_totalAssets, _totalSupply, _shares);

                orchestrator.debitPuppetAccount(_assets, _collateralToken, _puppet);

                _totalSupply -= _shares;
                _totalAssets -= _assets;
            }
            orchestrator.sendFunds(_performanceFeeAmount, _collateralToken, orchestrator.getPrizePoolDistributor());
        }
    }

    function _getRealisedPnl() internal returns (uint256 _realisedPnl) {
        (,,,,,_realisedPnl,,) = IGMXVault(orchestrator.getGMXVault()).getPosition(address(this), collateralToken, indexToken, isLong);
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

    function _approve(address _spender, address _token, uint256 _amount) internal {
        IERC20(_token).safeApprove(_spender, 0);
        IERC20(_token).safeApprove(_spender, _amount);
    }

    // ============================================================================================
    // Receive Function
    // ============================================================================================

    receive() external payable {
        if (orchestrator.getReferralRebatesSender() == msg.sender) payable(orchestrator.getPrizePoolDistributor()).sendValue(msg.value);
    }
}