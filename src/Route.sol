// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IVault} from "./interfaces/IVault.sol";
import {IGMXRouter} from "./interfaces/IGMXRouter.sol";
import {IGMXPositionRouter} from "./interfaces/IGMXPositionRouter.sol";
import {IGMXVault} from "./interfaces/IGMXVault.sol";
import {IGMXReader} from "./interfaces/IGMXReader.sol";

import {IRoute} from "./interfaces/IRoute.sol";

import "./Base.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract Route is Base, IRoute, Test {

    using SafeERC20 for IERC20;
    using Address for address payable;

    uint256 public positionIndex;

    bytes32 public routeTypeKey;

    mapping(bytes32 => bool) public keeperRequests; // requestKey => isKeeperRequest

    mapping(bytes32 => uint256) public requestKeyToAddCollateralRequestsIndex; // requestKey => addCollateralRequestsIndex
    mapping(uint256 => AddCollateralRequest) public addCollateralRequests; // addCollateralIndex => AddCollateralRequest
    mapping(uint256 => PositionInfo) public positions; // positionIndex => PositionInfo

    IOrchestrator public orchestrator;

    RouteInfo public routeInfo;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    constructor(Authority _authority, address _orchestrator, address _trader, address _collateralToken, address _indexToken, bool _isLong) Auth(address(0), _authority) {
        orchestrator = IOrchestrator(_orchestrator);

        routeInfo.trader = _trader;
        routeInfo.collateralToken = _collateralToken;
        routeInfo.indexToken = _indexToken;
        routeInfo.isLong = _isLong;

        (referralCode, keeper, revenueDistributor) = orchestrator.getGlobalInfo();

        gmxInfo = orchestrator.getGMXInfo();

        routeTypeKey = orchestrator.getRouteTypeKey(_collateralToken, _indexToken, _isLong);

        IGMXRouter(gmxInfo.gmxRouter).approvePlugin(gmxInfo.gmxPositionRouter);
    }

    // ============================================================================================
    // Modifiers
    // ============================================================================================

    modifier onlyKeeper() {
        if (msg.sender != owner && msg.sender != keeper) revert NotKeeper();
        _;
    }

    // ============================================================================================
    // View Functions
    // ============================================================================================

    // Position Info

    function getPuppets() external view returns (address[] memory _puppets) {
        _puppets = positions[positionIndex].puppets;
    }

    function getParticipantShares(address _participant) external view returns (uint256 _shares) {
        _shares = positions[positionIndex].participantShares[_participant];
    }

    function getLatestAmountIn(address _participant) external view returns (uint256 _amountIn) {
        _amountIn = positions[positionIndex].latestAmountIn[_participant];
    }

    function isPuppetAdjusted(address _puppet) external view returns (bool _isAdjusted) {
        _isAdjusted = positions[positionIndex].adjustedPuppets[_puppet];
    }

    // Request Info

    function getPuppetsRequestInfo(bytes32 _requestKey) external view returns (uint256[] memory _puppetsShares, uint256[] memory _puppetsAmounts) {
        uint256 _index = requestKeyToAddCollateralRequestsIndex[_requestKey];
        _puppetsShares = addCollateralRequests[_index].puppetsShares;
        _puppetsAmounts = addCollateralRequests[_index].puppetsAmounts;
    }

    // ============================================================================================
    // Trader Functions
    // ============================================================================================

    /// @dev violates checks-effects-interactions pattern. we use reentrancy guard
    // slither-disable-next-line reentrancy-eth
    function createPositionRequest(bytes memory _traderPositionData, bytes memory _traderSwapData, uint256 _executionFee, bool _isIncrease) external payable nonReentrant returns (bytes32 _requestKey) {
        if (msg.sender != routeInfo.trader) revert NotTrader();
        if (orchestrator.getIsPaused()) revert Paused();

        _repayBalance(bytes32(0), msg.value, false); // this sends trader eth back to trader

        if (_isIncrease) {
            uint256 _amountIn = _getAssets(_traderSwapData, _executionFee);
            _requestKey = _createIncreasePositionRequest(_traderPositionData, _amountIn, _executionFee);
        } else {
            _requestKey = _createDecreasePositionRequest(_traderPositionData, _executionFee);
        }
    }

    // ============================================================================================
    // Keeper Function
    // ============================================================================================

    /// @notice used to decrease the size of puppets that were not able to add collateral
    function decreaseSize(bytes memory _traderPositionData, uint256 _executionFee) external nonReentrant onlyKeeper returns (bytes32 _requestKey) {
        keeperRequests[_requestKey] = true;
        _requestKey = _createDecreasePositionRequest(_traderPositionData, _executionFee);
    }

    function liquidate() external nonReentrant onlyKeeper {
        if (_isOpenInterest()) revert PositionStillAlive();

        _repayBalance(bytes32(0), 0, false);

        emit Liquidated();
    }

    // ============================================================================================
    // Callback Function
    // ============================================================================================

    function gmxPositionCallback(bytes32 _requestKey, bool _isExecuted, bool _isIncrease) external nonReentrant {
        if (msg.sender != owner && msg.sender != gmxInfo.gmxPositionRouter) revert NotCallbackCaller();

        emit CallbackReceived(_requestKey, _isExecuted, _isIncrease);

        bool _repayKeeper = keeperRequests[_requestKey];
        if (_isExecuted) {
            if (_isIncrease) _allocateShares(_requestKey);
            _requestKey = bytes32(0); // repay any collateral to the exsisting sharesholders
        }

        _repayBalance(_requestKey, 0, _repayKeeper);
    }

    // ============================================================================================
    // Authority Functions
    // ============================================================================================

    function updateUtils(address _orchestrator) external requiresAuth {
        orchestrator = IOrchestrator(_orchestrator);

        emit OrchestratorSet(_orchestrator);

        (
            referralCode,
            keeper,
            revenueDistributor
        ) = orchestrator.getGlobalInfo();

        emit GlobalInfoUpdated();

        gmxInfo = orchestrator.getGMXInfo();

        emit GMXInfoUpdated();

        IGMXRouter(gmxInfo.gmxRouter).approvePlugin(gmxInfo.gmxPositionRouter);

        emit PluginApproved();
    }

    // ============================================================================================
    // Internal Mutated Functions
    // ============================================================================================

    function _getAssets(bytes memory _traderSwapData, uint256 _executionFee) internal returns (uint256 _amountIn) {
        (,uint256 _amount,) = abi.decode(_traderSwapData, (address[], uint256, uint256));

        if (_amount > 0) {
            // 1. get trader assets and allocate request shares
            uint256 _traderAmountIn = _getTraderAssets(_traderSwapData, _executionFee);

            uint256 _totalSupply = 0;
            uint256 _totalAssets = 0;

            uint256 _traderShares = _convertToShares(_totalAssets, _totalSupply, _traderAmountIn);
        
            _totalSupply = _traderShares;
            _totalAssets = _traderAmountIn;

            // 2. get puppets assets and allocate request shares
            bytes memory _puppetsRequestData = _getPuppetsAssetsAndAllocateRequestShares(_totalSupply, _totalAssets);

            uint256 _puppetsAmountIn;
            uint256[] memory _puppetsShares;
            uint256[] memory _puppetsAmounts;
            (
                _puppetsAmountIn,
                _totalSupply,
                _totalAssets,
                _puppetsShares,
                _puppetsAmounts
            ) = abi.decode(_puppetsRequestData, (uint256, uint256, uint256, uint256[], uint256[]));

            // 3. store request data
            AddCollateralRequest memory _request = AddCollateralRequest({
                puppetsAmountIn: _puppetsAmountIn,
                traderAmountIn: _traderAmountIn,
                traderShares: _traderShares,
                totalSupply: _totalSupply,
                totalAssets: _totalAssets,
                puppetsShares: _puppetsShares,
                puppetsAmounts: _puppetsAmounts
            });

            uint256 _positionIndex = positionIndex;
            addCollateralRequests[positions[_positionIndex].addCollateralRequestsIndex] = _request;
            positions[_positionIndex].addCollateralRequestsIndex += 1;

            // 4. pull funds from Orchestrator
            orchestrator.sendFunds(_puppetsAmountIn, routeInfo.collateralToken, address(this));

            return (_puppetsAmountIn + _traderAmountIn);
        }
    }

    function _getTraderAssets(bytes memory _traderSwapData, uint256 _executionFee) internal returns (uint256 _traderAmountIn) {
        (address[] memory _path, uint256 _amount, uint256 _minOut) = abi.decode(_traderSwapData, (address[], uint256, uint256));

        if (msg.value - _executionFee > 0) {
            if (msg.value - _executionFee != _amount) revert InvalidExecutionFee();
            if (_path[0] != _WETH) revert InvalidPath();

            payable(_WETH).functionCallWithValue(abi.encodeWithSignature("deposit()"), _amount);
        } else {
            IERC20(_path[0]).safeTransferFrom(msg.sender, address(this), _amount);
        }

        if (_path[0] == routeInfo.collateralToken) {
            _traderAmountIn = _amount;
        } else {
            address _toToken = _path[_path.length - 1];
            if (_toToken != routeInfo.collateralToken) revert InvalidPath();

            address _router = gmxInfo.gmxRouter;
            _approve(_router, _path[0], _amount);

            uint256 _before = IERC20(_toToken).balanceOf(address(this));
            IGMXRouter(_router).swap(_path, _amount, _minOut, address(this));
            _traderAmountIn = IERC20(_toToken).balanceOf(address(this)) - _before;
        }
    }

    function _getPuppetsAssetsAndAllocateRequestShares(uint256 _totalSupply, uint256 _totalAssets) internal returns (bytes memory _puppetsRequestData) {
        RouteInfo memory _routeInfo = routeInfo;
        PositionInfo storage _positionInfo = positions[positionIndex];
        IOrchestrator _orchestrator = orchestrator;
        bool _isOI = _isOpenInterest();
        uint256 _puppetsAmountIn = 0;
        uint256 _increaseRatio = 0;
        uint256 _traderAmountIn = _totalAssets;
        address[] memory _puppets;
        if (_isOI) {
            _increaseRatio = _traderAmountIn * 1e18 / _positionInfo.latestAmountIn[_routeInfo.trader];
            _puppets = _positionInfo.puppets;
        } else {
            bytes32 _routeKey = _orchestrator.getRouteKey(_routeInfo.trader, routeTypeKey);
            _puppets = _orchestrator.getPuppetsForRoute(_routeKey);
            _positionInfo.puppets = _puppets;
        }

        address _collateralToken = _routeInfo.collateralToken;
        uint256[] memory _puppetsShares = new uint256[](_puppets.length);
        uint256[] memory _puppetsAmounts = new uint256[](_puppets.length);
        for (uint256 i = 0; i < _puppets.length; i++) {
            address _puppet = _puppets[i];
            uint256 _puppetShares = 0;
            uint256 _allowancePercentage = _orchestrator.getPuppetAllowancePercentage(_puppet, address(this));
            uint256 _allowanceAmount = (_orchestrator.getPuppetAccountBalance(_puppet, _collateralToken) * _allowancePercentage) / 100;
            if (_isOI) {
                if (_positionInfo.adjustedPuppets[_puppet]) {
                    _allowanceAmount = 0;
                } else {
                    uint256 _requiredAdditionalCollateral = _positionInfo.latestAmountIn[_puppet] * _increaseRatio / 1e18;
                    if (_requiredAdditionalCollateral > _allowanceAmount || _requiredAdditionalCollateral == 0) {
                        _positionInfo.adjustedPuppets[_puppet] = true;
                        _allowanceAmount = 0;
                    } else {
                        _allowanceAmount = _requiredAdditionalCollateral;
                        _puppetShares = _convertToShares(_totalAssets, _totalSupply, _allowanceAmount);
                    }
                }
            } else {
                if (_allowanceAmount > 0 && _orchestrator.isBelowThrottleLimit(_puppet, address(this))) {
                    if (_allowanceAmount > _traderAmountIn) _allowanceAmount = _traderAmountIn;
                    _puppetShares = _convertToShares(_totalAssets, _totalSupply, _allowanceAmount);
                } else {
                    _allowanceAmount = 0;
                }
            }

            if (_allowanceAmount > 0) {
                _orchestrator.debitPuppetAccount(_allowanceAmount, _collateralToken, _puppet);

                _puppetsAmountIn = _puppetsAmountIn + _allowanceAmount;

                _totalSupply = _totalSupply + _puppetShares;
                _totalAssets = _totalAssets + _allowanceAmount;
            }

            _puppetsShares[i] = _puppetShares;
            _puppetsAmounts[i] = _allowanceAmount;
        }

        _puppetsRequestData = abi.encode(
            _puppetsAmountIn,
            _totalSupply,
            _totalAssets,
            _puppetsShares,
            _puppetsAmounts
        );
    }

    function _createIncreasePositionRequest(bytes memory _traderPositionData, uint256 _amountIn, uint256 _executionFee) internal returns (bytes32 _requestKey) {
        (uint256 _minOut, uint256 _sizeDelta, uint256 _acceptablePrice) = abi.decode(_traderPositionData, (uint256, uint256, uint256));

        RouteInfo memory _routeInfo = routeInfo;

        address[] memory _path = new address[](1);
        _path[0] = _routeInfo.collateralToken;

        _approve(gmxInfo.gmxRouter, _path[0], _amountIn);

        // slither-disable-next-line arbitrary-send-eth
        _requestKey = IGMXPositionRouter(gmxInfo.gmxPositionRouter).createIncreasePosition{ value: _executionFee } (
            _path,
            _routeInfo.indexToken,
            _amountIn,
            _minOut,
            _sizeDelta,
            _routeInfo.isLong,
            _acceptablePrice,
            _executionFee,
            referralCode,
            address(this)
        );

        if (_amountIn > 0) requestKeyToAddCollateralRequestsIndex[_requestKey] = positions[positionIndex].addCollateralRequestsIndex - 1;

        if (!_isOpenInterest()) {
            _updateLastPositionOpenedTimestamp(); // used to limit the number of position that can be opened in a given time period
        }

        emit CreatedIncreasePositionRequest(_requestKey, _amountIn, _minOut, _sizeDelta, _acceptablePrice, _executionFee);
    }

    function _createDecreasePositionRequest(bytes memory _traderPositionData, uint256 _executionFee) internal returns (bytes32 _requestKey) {
        (uint256 _collateralDelta, uint256 _sizeDelta, uint256 _acceptablePrice, uint256 _minOut)
            = abi.decode(_traderPositionData, (uint256, uint256, uint256, uint256));

        if (msg.value != _executionFee) revert InvalidExecutionFee();

        RouteInfo memory _routeInfo = routeInfo;

        address[] memory _path = new address[](1);
        _path[0] = _routeInfo.collateralToken;

        // slither-disable-next-line arbitrary-send-eth
        _requestKey = IGMXPositionRouter(gmxInfo.gmxPositionRouter).createDecreasePosition{ value: _executionFee } (
            _path,
            _routeInfo.indexToken,
            _collateralDelta,
            _sizeDelta,
            _routeInfo.isLong,
            address(this), // _receiver
            _acceptablePrice,
            _minOut,
            _executionFee,
            false, // _withdrawETH
            address(this)
        );

        emit CreatedDecreasePositionRequest(_requestKey, _minOut, _collateralDelta, _sizeDelta, _acceptablePrice, _executionFee);
    }

    function _allocateShares(bytes32 _requestKey) internal {
        AddCollateralRequest memory _request = addCollateralRequests[requestKeyToAddCollateralRequestsIndex[_requestKey]];
        uint256 _traderAmountIn = _request.traderAmountIn;
        if (_traderAmountIn > 0) {
            RouteInfo memory _routeInfo = routeInfo;
            PositionInfo storage _positionInfo = positions[positionIndex];
            uint256 _totalSupply = _positionInfo.totalSupply;
            uint256 _totalAssets = _positionInfo.totalAssets;
            address[] memory _puppets = _positionInfo.puppets;
            for (uint256 i = 0; i < _puppets.length; i++) {
                address _puppet = _puppets[i];
                uint256 _puppetAmountIn = _request.puppetsAmounts[i];
                if (_puppetAmountIn > 0) {
                    uint256 _newPuppetShares = _convertToShares(_totalAssets, _totalSupply, _puppetAmountIn);

                    _positionInfo.participantShares[_puppet] += _newPuppetShares;

                    _positionInfo.latestAmountIn[_puppet] = _puppetAmountIn;

                    _totalSupply = _totalSupply + _newPuppetShares;
                    _totalAssets = _totalAssets + _puppetAmountIn;
                }
            }

            uint256 _newTraderShares = _convertToShares(_totalAssets, _totalSupply, _traderAmountIn);

            _positionInfo.participantShares[_routeInfo.trader] += _newTraderShares;

            _positionInfo.latestAmountIn[_routeInfo.trader] = _traderAmountIn;

            _totalSupply = _totalSupply + _newTraderShares;
            _totalAssets = _totalAssets + _traderAmountIn;

            _positionInfo.totalSupply = _totalSupply;
            _positionInfo.totalAssets = _totalAssets;
        }
    }

    function _repayBalance(bytes32 _requestKey, uint256 _traderAmountIn, bool _repayKeeper) internal {
        RouteInfo memory _routeInfo = routeInfo;
        PositionInfo storage _positionInfo = positions[positionIndex];
        address _collateralToken = _routeInfo.collateralToken;
        uint256 _totalAssets = IERC20(_collateralToken).balanceOf(address(this));
        if (_totalAssets > 0) {
            uint256 _puppetsAssets = 0;
            uint256 _totalSupply = 0;
            uint256 _balance = _totalAssets;
            bool _isFailedRequest = _requestKey != bytes32(0);
            IOrchestrator _orchestrator = orchestrator;
            address[] memory _puppets = _positionInfo.puppets;
            AddCollateralRequest memory _request = addCollateralRequests[requestKeyToAddCollateralRequestsIndex[_requestKey]];
            for (uint256 i = 0; i < _puppets.length; i++) {
                uint256 _shares;
                address _puppet = _puppets[i];
                if (_isFailedRequest) {
                    if (i == 0) _totalSupply = _request.totalSupply;
                    _shares = _request.puppetsShares[i];
                } else {
                    if (i == 0) _totalSupply = _positionInfo.totalSupply;
                    _shares = _positionInfo.participantShares[_puppet];
                }

                if (_shares > 0) {
                    uint256 _assets = _convertToAssets(_balance, _totalSupply, _shares);

                    _orchestrator.creditPuppetAccount(_assets, _collateralToken, _puppet);

                    _totalSupply -= _shares;
                    _balance -= _assets;

                    _puppetsAssets += _assets;
                }
            }

            uint256 _traderShares = _isFailedRequest ? _request.traderShares : _positionInfo.participantShares[_routeInfo.trader];
            uint256 _traderAssets = _convertToAssets(_balance, _totalSupply, _traderShares);

            IERC20(_collateralToken).safeTransfer(address(_orchestrator), _puppetsAssets);
            IERC20(_collateralToken).safeTransfer(routeInfo.trader, _traderAssets);
        }

        if (!_isOpenInterest()) {
            _resetRoute();
        }

        uint256 _ethBalance = address(this).balance;
        if ((_ethBalance - _traderAmountIn)> 0) {
            address _executionFeeReceiver = _repayKeeper ? keeper : _routeInfo.trader;
            payable(_executionFeeReceiver).sendValue(_ethBalance - _traderAmountIn);
        }

        emit RepaidBalance(_totalAssets);
    }

    function _resetRoute() internal {
        positionIndex += 1;

        emit RouteReset();
    }

    function _updateLastPositionOpenedTimestamp() internal {
        IOrchestrator _orchestrator = orchestrator;
        address[] storage _puppets = positions[positionIndex].puppets;
        for (uint256 i = 0; i < _puppets.length; i++) {
            address _puppet = _puppets[i];
            _orchestrator.updateLastPositionOpenedTimestamp(_puppet, address(this));
        }
    }

    function _approve(address _spender, address _token, uint256 _amount) internal {
        IERC20(_token).safeApprove(_spender, 0);
        IERC20(_token).safeApprove(_spender, _amount);
    }

    // ============================================================================================
    // Internal View Functions
    // ============================================================================================

    function _isOpenInterest() internal view returns (bool) {
        RouteInfo memory _routeInfo = routeInfo;

        (uint256 _size, uint256 _collateral,,,,,,) = IGMXVault(gmxInfo.gmxVault).getPosition(address(this), _routeInfo.collateralToken, _routeInfo.indexToken, _routeInfo.isLong);

        return _size > 0 && _collateral > 0;
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

    receive() external payable {}
}