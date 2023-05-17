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
import {IInputValidator} from "./interfaces/IInputValidator.sol";
import {IRoute} from "./interfaces/IRoute.sol";

contract Route is ReentrancyGuard, IRoute {

    using SafeERC20 for IERC20;
    using Address for address payable;

    struct IncreasePositionRequest {
        uint256 puppetsAmountIn;
        uint256 traderAmountIn;
        uint256 traderShares;
        uint256 totalSupply;
        uint256 totalAssets;
        uint256[] puppetsShares;
        uint256[] puppetsAmounts;
        address[] puppets;
    }

    uint256 public increasePositionRequestsIndex;
    uint256 public realisedPnl; // realised P&L at the start of a new position. used to calculate the performance fee

    uint256 private totalSupply;
    uint256 private totalAssets;

    address public owner;
    address public trader;
    address public collateralToken;
    address public indexToken;

    address private constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // the address representing ETH
    address private constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    bool public isLong;
    bool public isPositionOpen;
    bool public isWaitingForCallback;

    bool private isETH;

    bytes private traderRepaymentData;

    mapping(bytes32 => uint256) public requestKeyToIndex; // requestKey => increasePositionRequestsIndex
    mapping(uint256 => IncreasePositionRequest) public increasePositionRequests; // increasePositionRequestsIndex => IncreasePositionRequest

    EnumerableMap.AddressToUintMap participantShares; // participant => shares

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

        isPositionOpen = true;

        uint256 _traderAmountIn;
        uint256 _puppetsAmountIn;
        address _inputValidator = orchestrator.getInputValidator();
        if (_isIncrease) {
            (_traderAmountIn, _puppetsAmountIn) = _getAssetsAndAllocateShares(_traderSwapData);
            _requestKey = _createIncreasePositionRequest(_traderPositionData, _traderAmountIn, _puppetsAmountIn);
        } else {
            IInputValidator(_inputValidator).validateSwapPath(_traderSwapData, collateralToken);
            traderRepaymentData = _traderSwapData;
            _requestKey = _createDecreasePositionRequest(_traderPositionData);
        }

        IInputValidator(_inputValidator).validatePositionParameters(_traderPositionData, _traderAmountIn, _puppetsAmountIn, _isIncrease);
    }

    function createIncreasePositionRequestETH(bytes memory _traderPositionData, uint256 _minOut) external payable returns (bytes32 _requestKey) {
        (,,, uint256 _executionFee) = abi.decode(_traderPositionData, (uint256, uint256, uint256, uint256));
        uint256 _amount = msg.value;
        address _weth = WETH;
        address[] memory _path = new address[](2);
        _path[0] = _weth;
        _path[1] = collateralToken;
        bytes memory _traderSwapData = abi.encodePacked(_path, _amount, _minOut);

        isETH = true;

        IWETH(_weth).deposit{ value: _amount - _executionFee }();

        return createPositionRequest(_traderPositionData, _traderSwapData, true);
    }

    // ============================================================================================
    // Keeper Functions
    // ============================================================================================

    function onLiquidation() external nonReentrant {
        if (msg.sender != owner && msg.sender != orchestrator.getKeeper()) revert NotKeeper();
        if (!_isLiquidated()) revert PositionStillAlive();

        _repayBalance(bytes32(0), false);

        emit Liquidated();
    }

    // ============================================================================================
    // Callback Functions
    // ============================================================================================

    function callback(bytes32 _requestKey, bool _isExecuted, bool _isIncrease) external nonReentrant onlyCallbackTarget {
        if (_isExecuted) {
            if (_isIncrease) _executeRequest(_requestKey);

            _repayBalance(bytes32(0), false);

            emit ApprovePositionRequest();
        } else {
            _repayBalance(_requestKey, true);
            
            emit RejectPositionRequest();
        }
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

    function _getAssetsAndAllocateShares(bytes memory _traderSwapData) internal returns (uint256 _traderAmountIn, uint256 _puppetsAmountIn) {
        (,uint256 _amount,) = abi.decode(_traderSwapData, (address[], uint256, uint256));
        if (_amount > 0) {
            // 1. get trader assets and allocate shares
            _traderAmountIn = _getTraderAssets(_traderSwapData);

            uint256 _totalSupply;
            uint256 _totalAssets;

            uint256 _traderShares = _convertToShares(_totalAssets, _totalSupply, _traderAmountIn);
        
            _totalSupply = _traderShares;
            _totalAssets = _traderAmountIn;

            // 2. get puppets assets and allocate shares
            address _collateralToken = collateralToken;
            bool _isOI = _isOpenInterest();
            bytes32 _routeKey = orchestrator.getRouteKey(trader, _collateralToken, indexToken, isLong);
            uint256[] memory _puppetsShares;
            uint256[] memory _puppetsAmounts;
            address[] memory _puppets = orchestrator.getPuppetsForRoute(_routeKey);
            for (uint256 i = 0; i < _puppets.length; i++) {
                address _puppet = _puppets[i];
                if (!_isOI && !orchestrator.canOpenNewPosition(address(this), _puppet)) {
                    delete _puppets[i];
                    orchestrator.liquidatePuppet(_puppet, _routeKey);
                    continue;
                }

                uint256 _allowancePercentage = orchestrator.getPuppetAllowancePercentage(_puppet, address(this));
                uint256 _puppetAmountIn = (orchestrator.getPuppetAccountBalance(_collateralToken, _puppet) * _allowancePercentage) / 100;

                if (_puppetAmountIn > _traderAmountIn) _puppetAmountIn = _traderAmountIn;

                if (orchestrator.isPuppetSolvent(_collateralToken, _puppet)) {
                    orchestrator.debitPuppetAccount(_puppetAmountIn, _collateralToken, _puppet);
                } else {
                    delete _puppets[i];
                    orchestrator.liquidatePuppet(_puppet, _routeKey);
                    continue;
                }

                uint256 _puppetShares = _convertToShares(_totalAssets, _totalSupply, _puppetAmountIn);

                _puppetsShares[_puppetsShares.length] = _puppetShares;
                _puppetsAmounts[_puppetsAmounts.length] = _puppetAmountIn;

                _puppetsAmountIn += _puppetAmountIn;

                _totalSupply += _puppetShares;
                _totalAssets += _puppetAmountIn;
            }

            orchestrator.sendFunds(_puppetsAmountIn, _collateralToken, address(this)); // pull funds from Orchestrator

            // 3. store request data
            IncreasePositionRequest memory _request = IncreasePositionRequest({
                puppetsAmountIn: _puppetsAmountIn,
                traderAmountIn: _traderAmountIn,
                traderShares: _traderShares,
                totalSupply: _totalSupply,
                totalAssets: _totalAssets,
                puppetsShares: _puppetsShares,
                puppetsAmounts: _puppetsAmounts,
                puppets: _puppets
            });

            increasePositionRequests[increasePositionRequestsIndex] = _request;
        }

        increasePositionRequestsIndex += 1;
    }

    function _getTraderAssets(bytes memory _traderSwapData) internal returns (uint256 _traderAmountIn) {
        (address[] memory _path, uint256 _amount, uint256 _minOut) = abi.decode(_traderSwapData, (address[], uint256, uint256));

        address _trader = trader;
        address _fromToken = _path[0];
        if (!isETH) IERC20(_fromToken).safeTransferFrom(_trader, address(this), _amount);
        isETH = false;

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
    }

    function _executeRequest(bytes32 _requestKey) internal {
        IncreasePositionRequest memory _request = increasePositionRequests[requestKeyToIndex[_requestKey]];
        uint256 _traderAmountIn = _request.traderAmountIn;
        if (_traderAmountIn > 0) {
            uint256 _totalSupply = totalSupply;
            uint256 _totalAssets = totalAssets;
            for (uint256 i = 0; i < _request.puppets.length; i++) {
                address _puppet = _request.puppets[i];
                uint256 _puppetAmountIn = _request.puppetsAmounts[i];
                uint256 _puppetShares = _convertToShares(_totalAssets, _totalSupply, _puppetAmountIn);

                EnumerableMap.set(participantShares, _puppet, _puppetShares);

                _totalSupply += _puppetShares;
                _totalAssets += _puppetAmountIn;
            }

            uint256 _traderShares = _convertToShares(_totalAssets, _totalSupply, _traderAmountIn);

            EnumerableMap.set(participantShares, trader, _traderShares);

            _totalSupply += _traderShares;
            _totalAssets += _traderAmountIn;

            totalSupply = _totalSupply;
            totalAssets = _totalAssets;
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

        requestKeyToIndex[_requestKey] = increasePositionRequestsIndex - 1;

        orchestrator.updateRequestKeyToRoute(_requestKey);

        if (!_isOpenInterest()) {
            realisedPnl = _getRealisedPnl(); // used for performance fee calculation
            _updateLastPositionOpenedTimestamp(); // used to limit the number of position that can be opened in a given time period
        }

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

    function _repayBalance(bytes32 _requestKey, bool _isFailedRequest) internal {
        address _collateralToken = collateralToken;
        uint256 _totalAssets = IERC20(_collateralToken).balanceOf(address(this));
        if (_totalAssets > 0) {
            uint256 _totalSupply;
            uint256 _balance = _totalAssets;
            uint256 _puppetsAssets;
            bytes32 _key = orchestrator.getRouteKey(trader, _collateralToken, indexToken, isLong);
            address[] memory _puppets = orchestrator.getPuppetsForRoute(_key);
            IncreasePositionRequest memory _request = increasePositionRequests[requestKeyToIndex[_requestKey]];
            for (uint256 i = 0; i < _puppets.length; i++) {
                uint256 _shares;
                uint256 _assets;
                address _puppet = _puppets[i];
                if (_isFailedRequest) {
                    if (i == 0) _totalSupply = _request.totalSupply;
                    _shares = _request.puppetsShares[i];
                } else {
                    if (i == 0) _totalSupply = totalSupply;
                    _shares = EnumerableMap.get(participantShares, _puppet);
                }

                _assets = _convertToAssets(_balance, _totalSupply, _shares);

                orchestrator.creditPuppetAccount(_assets, _collateralToken, _puppet);

                _totalSupply -= _shares;
                _balance -= _assets;

                _puppetsAssets += _assets;
            }

            uint256 _traderShares = _isFailedRequest ? _request.traderShares : EnumerableMap.get(participantShares, trader);
            uint256 _traderAssets = _convertToAssets(_balance, _totalSupply, _traderShares);

            IERC20(_collateralToken).safeTransfer(address(orchestrator), _puppetsAssets);
            _repayTrader(_traderAssets, _isFailedRequest);
        }

        if (!_isOpenInterest()) {
            _resetRoute();
        }

        uint256 _ethBalance = address(this).balance;
        if (_ethBalance > 0) {
            payable(trader).sendValue(_ethBalance);
        }

        emit RepayBalance(_totalAssets);
    }

    function _repayTrader(uint256 _traderAssets, bool _isFailedRequest) internal {
        if (_isFailedRequest) {
            IERC20(collateralToken).safeTransfer(trader, _traderAssets);
        } else {
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
        }
    }

    function _isOpenInterest() internal view returns (bool) {
        (uint256 _size, uint256 _collateral,,,,,,) = IGMXVault(orchestrator.getGMXVault()).getPosition(address(this), collateralToken, indexToken, isLong);

        return _size > 0 && _collateral > 0;
    }

    function _resetRoute() internal {
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
            uint256 _performanceFeeAmount = (_currentRealisedPnl - _realisedPnlBefore) * orchestrator.getPerformanceFeePercentage() / 10000;
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

            orchestrator.sendFunds(_performanceFeeAmount, _collateralToken, orchestrator.getRevenueDistributor());
        }
    }

    function _getRealisedPnl() internal view returns (uint256 _realisedPnl) {
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
        if (orchestrator.getReferralRebatesSender() == msg.sender) payable(orchestrator.getRevenueDistributor()).sendValue(msg.value);
    }
}