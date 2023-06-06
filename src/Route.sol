// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ========================= Route ==============================
// ==============================================================
// Puppet Finance: https://github.com/GMX-Blueberry-Club/Puppet

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

import {IGMXRouter} from "./interfaces/IGMXRouter.sol";
import {IGMXPositionRouter} from "./interfaces/IGMXPositionRouter.sol";
import {IGMXVault} from "./interfaces/IGMXVault.sol";

import {IRoute} from "./interfaces/IRoute.sol";

import "./Base.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";
/// @title Route
/// @author johnnyonline (Puppet Finance) https://github.com/johnnyonline
/// @notice This contract acts as a container account which a trader can use to manage their position, and puppets can subscribe to
contract Route is Base, IRoute, Test {

    using SafeERC20 for IERC20;
    using Address for address payable;

    bool public frozen;

    uint256 public positionIndex;

    bytes32 private immutable _routeTypeKey;

    mapping(bytes32 => bool) public keeperRequests; // requestKey => isKeeperRequest

    mapping(bytes32 => uint256) public requestKeyToAddCollateralRequestsIndex; // requestKey => addCollateralRequestsIndex
    mapping(uint256 => AddCollateralRequest) public addCollateralRequests; // addCollateralIndex => AddCollateralRequest
    mapping(uint256 => Position) public positions; // positionIndex => Position

    IOrchestrator public orchestrator;

    Route public route;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    /// @notice The ```constructor``` function is called on deployment
    /// @param _orchestrator The address of the ```Orchestrator``` contract
    /// @param _trader The address of the trader
    /// @param _collateralToken The address of the collateral token
    /// @param _indexToken The address of the index token
    /// @param _isLong Whether the route is long or short
    constructor(address _orchestrator, address _trader, address _collateralToken, address _indexToken, bool _isLong) {
        orchestrator = IOrchestrator(_orchestrator);

        route.trader = _trader;
        route.collateralToken = _collateralToken;
        route.indexToken = _indexToken;
        route.isLong = _isLong;

        _routeTypeKey = orchestrator.getRouteTypeKey(_collateralToken, _indexToken, _isLong);

        IGMXRouter(orchestrator.gmxRouter()).approvePlugin(orchestrator.gmxPositionRouter());
    }

    // ============================================================================================
    // Modifiers
    // ============================================================================================

    /// @notice Modifier that ensures the caller is the trader or the orchestrator, and that the route is not frozen or paused
    modifier onlyTrader() {
        if (msg.sender != route.trader && msg.sender != address(orchestrator)) revert NotTrader();
        if (orchestrator.paused()) revert Paused();
        if (frozen) revert RouteFrozen();
        _;
    }

    /// @notice Modifier that ensures the caller is the orchestrator
    modifier onlyOrchestrator() {
        if (msg.sender != address(orchestrator)) revert NotOrchestrator();
        _;
    }

    /// @notice Modifier that ensures the caller is the keeper
    modifier onlyKeeper() {
        if (msg.sender != orchestrator.keeper()) revert NotKeeper();
        _;
    }

    /// @notice Modifier that ensures the caller is the callback caller
    modifier onlyCallbackCaller() {
        if (msg.sender != orchestrator.gmxPositionRouter()) revert NotCallbackCaller();
        _;
    }

    // ============================================================================================
    // View Functions
    // ============================================================================================

    // Position Info

    /// @inheritdoc IRoute
    function puppets() external view returns (address[] memory _puppets) {
        _puppets = positions[positionIndex].puppets;
    }

    /// @inheritdoc IRoute
    function participantShares(address _participant) external view returns (uint256 _shares) {
        _shares = positions[positionIndex].participantShares[_participant];
    }

    /// @inheritdoc IRoute
    function latestAmountIn(address _participant) external view returns (uint256 _amountIn) {
        _amountIn = positions[positionIndex].latestAmountIn[_participant];
    }

    /// @inheritdoc IRoute
    function isPuppetAdjusted(address _puppet) external view returns (bool _isAdjusted) {
        _isAdjusted = positions[positionIndex].adjustedPuppets[_puppet];
    }

    // Request Info

    /// @inheritdoc IRoute
    function puppetsRequestAmounts(bytes32 _requestKey) external view returns (uint256[] memory _puppetsShares, uint256[] memory _puppetsAmounts) {
        uint256 _index = requestKeyToAddCollateralRequestsIndex[_requestKey];
        _puppetsShares = addCollateralRequests[_index].puppetsShares;
        _puppetsAmounts = addCollateralRequests[_index].puppetsAmounts;
    }

    /// @inheritdoc IRoute
    function isWaitingForCallback() external view returns (bool) {
        bytes32[] memory _requests = positions[positionIndex].requestKeys;
        IGMXPositionRouter _positionRouter = IGMXPositionRouter(orchestrator.gmxPositionRouter());
        for (uint256 _i = 0; _i < _requests.length; _i++) {
            address[] memory _increasePath = _positionRouter.getIncreasePositionRequestPath(_requests[_i]);
            address[] memory _decreasePath = _positionRouter.getDecreasePositionRequestPath(_requests[_i]);
            if (_increasePath.length > 0 || _decreasePath.length > 0) {
                return true;
            }
        }

        return false;
    }

    // ============================================================================================
    // Trader Functions
    // ============================================================================================

    /// @inheritdoc IRoute
    // slither-disable-next-line reentrancy-eth
    function requestPosition(
        AdjustPositionParams memory _adjustPositionParams,
        SwapParams memory _swapParams,
        uint256 _executionFee,
        bool _isIncrease
    ) external payable onlyTrader nonReentrant returns (bytes32 _requestKey) {

        _repayBalance(bytes32(0), msg.value, false);

        if (_isIncrease) {
            uint256 _amountIn = _getAssets(_swapParams, _executionFee);
            _requestKey = _requestIncreasePosition(_adjustPositionParams, _amountIn, _executionFee);
        } else {
            _requestKey = _requestDecreasePosition(_adjustPositionParams, _executionFee);
        }
    }

    /// @inheritdoc IRoute
    function approvePlugin() external onlyTrader nonReentrant {
        IGMXRouter(orchestrator.gmxRouter()).approvePlugin(orchestrator.gmxPositionRouter());

        emit PluginApproved();
    }

    // ============================================================================================
    // Keeper Functions
    // ============================================================================================

    /// @inheritdoc IRoute
    function decreaseSize(AdjustPositionParams memory _adjustPositionParams, uint256 _executionFee) external onlyKeeper nonReentrant returns (bytes32 _requestKey) {
        keeperRequests[_requestKey] = true;
        _requestKey = _requestDecreasePosition(_adjustPositionParams, _executionFee);
    }

    /// @inheritdoc IRoute
    function liquidate() external onlyKeeper nonReentrant {
        if (_isOpenInterest()) revert PositionStillAlive();

        _repayBalance(bytes32(0), 0, false);

        emit Liquidated();
    }

    // ============================================================================================
    // Callback Function
    // ============================================================================================

    // @inheritdoc IPositionRouterCallbackReceiver
    function gmxPositionCallback(bytes32 _requestKey, bool _isExecuted, bool _isIncrease) external onlyCallbackCaller nonReentrant {
        if (_isExecuted) {
            if (_isIncrease) _allocateShares(_requestKey);
            _requestKey = bytes32(0);
        }

        _repayBalance(_requestKey, 0, keeperRequests[_requestKey]);

        emit CallbackReceived(_requestKey, _isExecuted, _isIncrease);
    }

    // ============================================================================================
    // Orchestrator Function
    // ============================================================================================

    /// @inheritdoc IRoute
    function rescueTokens(uint256 _amount, address _token, address _receiver) external {
        if (_token == address(0)) {
            payable(_receiver).sendValue(_amount);
        } else {
            IERC20(_token).safeTransfer(_receiver, _amount);
        }

        emit TokensRescued(_amount, _token, _receiver);
    }

    /// @inheritdoc IRoute
    function freeze(bool _freeze) external {
        frozen = _freeze;

        emit Frozen(_freeze);
    }

    // ============================================================================================
    // Internal Mutated Functions
    // ============================================================================================

    function _getAssets(SwapParams memory _swapParams, uint256 _executionFee) internal returns (uint256 _amountIn) {
        if (_swapParams.amount > 0) {
            // 1. get trader assets and allocate request shares. pull funds too, if needed
            uint256 _traderAmountIn = _getTraderAssets(_swapParams, _executionFee);

            uint256 _traderShares = _convertToShares(0, 0, _traderAmountIn);
        
            uint256 _totalSupply = _traderShares;
            uint256 _totalAssets = _traderAmountIn;

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
            orchestrator.sendFunds(_puppetsAmountIn, route.collateralToken, address(this));

            return (_puppetsAmountIn + _traderAmountIn);
        }
    }

    function _getTraderAssets(SwapParams memory _swapParams, uint256 _executionFee) internal returns (uint256 _traderAmountIn) {
        console.log("------------------");
        console.log("getTraderAssets");
        console.log(_swapParams.amount);
        console.log(_executionFee);
        console.log(_swapParams.path[0]);
        console.log(_swapParams.path[_swapParams.path.length - 1]);
        console.log(route.trader);
        console.log("------------------");
        if (msg.value - _executionFee > 0) {
            if (msg.value - _executionFee != _swapParams.amount) revert InvalidExecutionFee();
            if (_swapParams.path[0] != _WETH) revert InvalidPath();

            payable(_WETH).functionCallWithValue(abi.encodeWithSignature("deposit()"), _swapParams.amount);
        } else {
            if (msg.value != _executionFee) revert InvalidExecutionFee();

            IERC20(_swapParams.path[0]).safeTransferFrom(route.trader, address(this), _swapParams.amount);
        }

        if (_swapParams.path[0] == route.collateralToken) {
            _traderAmountIn = _swapParams.amount;
        } else {
            address _toToken = _swapParams.path[_swapParams.path.length - 1];
            if (_toToken != route.collateralToken) revert InvalidPath();

            address _router = orchestrator.gmxRouter();
            _approve(_router, _swapParams.path[0], _swapParams.amount);

            uint256 _before = IERC20(_toToken).balanceOf(address(this));
            IGMXRouter(_router).swap(_swapParams.path, _swapParams.amount, _swapParams.minOut, address(this));
            _traderAmountIn = IERC20(_toToken).balanceOf(address(this)) - _before;
        }
    }

    /// @notice The ```_getPuppetsAssetsAndAllocateRequestShares``` function is used to get the assets of the Puppets and allocate request shares
    /// @dev This function is called by ```_getAssets```
    /// @param _totalSupply The current total supply of shares in the request
    /// @param _totalAssets The current total assets in the request
    /// @return _puppetsRequestData The request data of the Puppets, encoded as bytes
    function _getPuppetsAssetsAndAllocateRequestShares(uint256 _totalSupply, uint256 _totalAssets) internal returns (bytes memory _puppetsRequestData) {
        Position storage _position = positions[positionIndex];
        bool _isOI = _isOpenInterest();
        uint256 _increaseRatio = 0;
        uint256 _traderAmountIn = _totalAssets;
        address[] memory _puppets;
        if (_isOI) {
            _increaseRatio = _traderAmountIn * 1e18 / _position.latestAmountIn[route.trader];
            _puppets = _position.puppets;
        } else {
            _puppets = orchestrator.subscribedPuppets(orchestrator.getRouteKey(route.trader, _routeTypeKey));
            _position.puppets = _puppets;
        }

        uint256 _puppetsAmountIn = 0;
        uint256[] memory _puppetsShares = new uint256[](_puppets.length);
        uint256[] memory _puppetsAmounts = new uint256[](_puppets.length);
        for (uint256 i = 0; i < _puppets.length; i++) {
            address _puppet = _puppets[i];
            uint256 _puppetShares = 0;
            uint256 _allowancePercentage = orchestrator.puppetAllowancePercentage(_puppet, address(this));
            uint256 _allowanceAmount = (orchestrator.puppetAccountBalance(_puppet, route.collateralToken) * _allowancePercentage) / 100;
            if (_isOI) {
                if (_position.adjustedPuppets[_puppet]) {
                    _allowanceAmount = 0;
                } else {
                    uint256 _requiredAdditionalCollateral = _position.latestAmountIn[_puppet] * _increaseRatio / 1e18;
                    if (_requiredAdditionalCollateral > _allowanceAmount || _requiredAdditionalCollateral == 0) {
                        _position.adjustedPuppets[_puppet] = true;
                        _allowanceAmount = 0;
                    } else {
                        _allowanceAmount = _requiredAdditionalCollateral;
                        _puppetShares = _convertToShares(_totalAssets, _totalSupply, _allowanceAmount);
                    }
                }
            } else {
                if (_allowanceAmount > 0 && orchestrator.isBelowThrottleLimit(_puppet, _routeTypeKey)) {
                    if (_allowanceAmount > _traderAmountIn) _allowanceAmount = _traderAmountIn;
                    _puppetShares = _convertToShares(_totalAssets, _totalSupply, _allowanceAmount);
                    orchestrator.updateLastPositionOpenedTimestamp(_puppet, _routeTypeKey);
                } else {
                    _allowanceAmount = 0;
                }
            }

            if (_allowanceAmount > 0) {
                orchestrator.debitPuppetAccount(_allowanceAmount, route.collateralToken, _puppet);

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

    // function _getPuppetsAssetsAndAllocateRequestShares(uint256 _totalSupply, uint256 _totalAssets) internal returns (bytes memory _puppetsRequestData) {
    //     bool _isOI = _isOpenInterest();
    //     uint256 _increaseRatio = _isOI ? _totalAssets * 1e18 / positions[positionIndex].latestAmountIn[route.trader] : 0;

    //     uint256 _puppetsAmountIn = 0;
    //     uint256 _traderAmountIn = _totalAssets;
    //     address[] memory _puppets = _getRelevantPuppets(_isOI);
    //     uint256[] memory _puppetsShares = new uint256[](_puppets.length);
    //     uint256[] memory _puppetsAmounts = new uint256[](_puppets.length);

    //     GetPuppetAdditionalAmountContext memory _context = GetPuppetAdditionalAmountContext({
    //         isOI: _isOI,
    //         increaseRatio: _increaseRatio,
    //         traderAmountIn: _traderAmountIn
    //     });

    //     for (uint256 i = 0; i < _puppets.length; i++) {
    //         (uint256 _allowanceAmount, uint256 _additionalShares) = _getPuppetAdditionalAmounts(_context, _totalSupply, _totalAssets, _puppets[i]);

    //         _totalSupply += _additionalShares;
    //         _totalAssets += _allowanceAmount;

    //         _puppetsAmountIn += _allowanceAmount;
    //         _puppetsShares[i] = _additionalShares;
    //         _puppetsAmounts[i] = _allowanceAmount;
    //     }

    //     _puppetsRequestData = abi.encode(_puppetsAmountIn, _totalSupply, _totalAssets, _puppetsShares, _puppetsAmounts);
    // }

    // function _getRelevantPuppets(bool _isOI) internal view returns (address[] memory _puppets) {
    //     return _isOI ? positions[positionIndex].puppets : orchestrator.subscribedPuppets(orchestrator.getRouteKey(route.trader, _routeTypeKey));
    // }

    // // function _getPuppetAdditionalAmounts(
    // //     bool _isOI,
    // //     uint256 _increaseRatio,
    // //     uint256 _totalSupply,
    // //     uint256 _totalAssets,
    // //     address _puppet
    // // ) internal returns (uint256 _allowanceAmount, uint256 _additionalShares) {
    
    // //     Position storage _position = positions[positionIndex];
    // //     uint256 _allowancePercentage = orchestrator.puppetAllowancePercentage(_puppet, address(this));

    // //     _allowanceAmount = (orchestrator.puppetAccountBalance(_puppet, route.collateralToken) * _allowancePercentage) / 100;

    // //     if (_isOI && !_shouldPuppetAdjust(_position.adjustedPuppets[_puppet], _increaseRatio, _allowanceAmount, _position.latestAmountIn[_puppet])) {
    // //         _position.adjustedPuppets[_puppet] = true;
    // //         _allowanceAmount = 0;
    // //     } else if (!_isOI && !_shouldAllowEligiblePuppet(orchestrator.isBelowThrottleLimit(_puppet, _routeTypeKey), _allowanceAmount, _totalAssets)) {
    // //         _allowanceAmount = 0;
    // //     }

    // //     if (_allowanceAmount > 0) {
    // //         orchestrator.debitPuppetAccount(_allowanceAmount, route.collateralToken, _puppet);
    // //         _additionalShares = _convertToShares(_totalAssets, _totalSupply, _allowanceAmount);
    // //     }
        
    // //     return (_allowanceAmount, _additionalShares);
    // // }

    // function _getPuppetAdditionalAmounts(
    //     GetPuppetAdditionalAmountContext memory _context,
    //     uint256 _totalSupply,
    //     uint256 _totalAssets,
    //     address _puppet
    // ) internal returns (uint256 _allowanceAmount, uint256 _additionalShares) {
    //     if (_context.isOI) {
    //         Position storage _position = positions[positionIndex];
    //         if (_position.adjustedPuppets[_puppet]) {
    //             _allowanceAmount = 0;
    //         } else {
    //             uint256 _requiredAdditionalCollateral = _position.latestAmountIn[_puppet] * _context.increaseRatio / 1e18;
    //             if (_requiredAdditionalCollateral > _allowanceAmount || _requiredAdditionalCollateral == 0) {
    //                 _position.adjustedPuppets[_puppet] = true;
    //                 _allowanceAmount = 0;
    //             } else {
    //                 _allowanceAmount = _requiredAdditionalCollateral;
    //                 _additionalShares = _convertToShares(_totalAssets, _totalSupply, _allowanceAmount);
    //             }
    //         }
    //     } else {
    //         if (_allowanceAmount > 0 && orchestrator.isBelowThrottleLimit(_puppet, _routeTypeKey)) {
    //             if (_allowanceAmount > _context.traderAmountIn) _allowanceAmount = _context.traderAmountIn;
    //             _additionalShares = _convertToShares(_totalAssets, _totalSupply, _allowanceAmount);
    //             orchestrator.updateLastPositionOpenedTimestamp(_puppet, _routeTypeKey);
    //         } else {
    //             _allowanceAmount = 0;
    //         }
    //     }
    // }

    // // function _shouldPuppetAdjust(bool _alreadyAdjusted, uint256 _increaseRatio, uint256 _allowanceAmount, uint256 _latestAmountIn) internal pure returns (bool) {
    // //     if (_alreadyAdjusted) return false;

    // //     uint256 _requiredAdditionalCollateral = _latestAmountIn * _increaseRatio / 1e18;
    // //     bool notRequired =  (_requiredAdditionalCollateral == 0 || (_requiredAdditionalCollateral > _allowanceAmount));
    // //     return !notRequired;
    // // }

    // // function _shouldAllowEligiblePuppet(bool _isEligible, uint256 _allowanceAmount, uint256 _totalAssets) internal pure returns (bool) {
    // //     if(!_isEligible) return false;
    // //     return _allowanceAmount > _min(_allowanceAmount, _totalAssets);
    // // }

    // // function _min(uint256 a, uint256 b) internal pure returns (uint256) {
    // //     return a < b ? a : b;
    // // }

    function _requestIncreasePosition(AdjustPositionParams memory _adjustPositionParams, uint256 _amountIn, uint256 _executionFee) internal returns (bytes32 _requestKey) {
        address[] memory _path = new address[](1);
        _path[0] = route.collateralToken;

        _approve(orchestrator.gmxRouter(), _path[0], _amountIn);

        // slither-disable-next-line arbitrary-send-eth
        _requestKey = IGMXPositionRouter(orchestrator.gmxPositionRouter()).createIncreasePosition{ value: _executionFee } (
            _path,
            route.indexToken,
            _amountIn,
            _adjustPositionParams.minOut,
            _adjustPositionParams.sizeDelta,
            route.isLong,
            _adjustPositionParams.acceptablePrice,
            _executionFee,
            orchestrator.referralCode(),
            address(this)
        );

        positions[positionIndex].requestKeys.push(_requestKey);

        if (_amountIn > 0) requestKeyToAddCollateralRequestsIndex[_requestKey] = positions[positionIndex].addCollateralRequestsIndex - 1;

        emit CreatedIncreasePositionRequest(
            _requestKey,
            _adjustPositionParams.amountIn,
            _adjustPositionParams.minOut,
            _adjustPositionParams.sizeDelta,
            _adjustPositionParams.acceptablePrice
        );
    }

    function _requestDecreasePosition(AdjustPositionParams memory _adjustPositionParams, uint256 _executionFee) internal returns (bytes32 _requestKey) {
        if (msg.value != _executionFee) revert InvalidExecutionFee();

        address[] memory _path = new address[](1);
        _path[0] = route.collateralToken;

        // slither-disable-next-line arbitrary-send-eth
        _requestKey = IGMXPositionRouter(orchestrator.gmxPositionRouter()).createDecreasePosition{ value: _executionFee } (
            _path,
            route.indexToken,
            _adjustPositionParams.collateralDelta,
            _adjustPositionParams.sizeDelta,
            route.isLong,
            address(this), // _receiver
            _adjustPositionParams.acceptablePrice,
            _adjustPositionParams.minOut,
            _executionFee,
            false, // _withdrawETH
            address(this)
        );

        positions[positionIndex].requestKeys.push(_requestKey);

        emit CreatedDecreasePositionRequest(
            _requestKey,
            _adjustPositionParams.minOut,
            _adjustPositionParams.collateralDelta,
            _adjustPositionParams.sizeDelta,
            _adjustPositionParams.acceptablePrice
        );
    }

    function _allocateShares(bytes32 _requestKey) internal {
        AddCollateralRequest memory _request = addCollateralRequests[requestKeyToAddCollateralRequestsIndex[_requestKey]];
        uint256 _traderAmountIn = _request.traderAmountIn;
        if (_traderAmountIn > 0) {
            Route memory _route = route;
            Position storage _position = positions[positionIndex];
            uint256 _totalSupply = _position.totalSupply;
            uint256 _totalAssets = _position.totalAssets;
            address[] memory _puppets = _position.puppets;
            for (uint256 i = 0; i < _puppets.length; i++) {
                address _puppet = _puppets[i];
                uint256 _puppetAmountIn = _request.puppetsAmounts[i];
                if (_puppetAmountIn > 0) {
                    uint256 _newPuppetShares = _convertToShares(_totalAssets, _totalSupply, _puppetAmountIn);

                    _position.participantShares[_puppet] += _newPuppetShares;

                    _position.latestAmountIn[_puppet] = _puppetAmountIn;

                    _totalSupply = _totalSupply + _newPuppetShares;
                    _totalAssets = _totalAssets + _puppetAmountIn;
                }
            }

            uint256 _newTraderShares = _convertToShares(_totalAssets, _totalSupply, _traderAmountIn);

            _position.participantShares[_route.trader] += _newTraderShares;

            _position.latestAmountIn[_route.trader] = _traderAmountIn;

            _totalSupply = _totalSupply + _newTraderShares;
            _totalAssets = _totalAssets + _traderAmountIn;

            _position.totalSupply = _totalSupply;
            _position.totalAssets = _totalAssets;
        }
    }

    function _repayBalance(bytes32 _requestKey, uint256 _traderAmountIn, bool _repayKeeper) internal {
        Position storage _position = positions[positionIndex];
        Route memory _route = route;

        if (!_isOpenInterest()) {
            _resetRoute();
        }

        uint256 _totalAssets = IERC20(_route.collateralToken).balanceOf(address(this));
        if (_totalAssets > 0) {
            uint256 _puppetsAssets = 0;
            uint256 _totalSupply = 0;
            uint256 _balance = _totalAssets;
            bool _isFailedRequest = _requestKey != bytes32(0);
            address[] memory _puppets = _position.puppets;
            AddCollateralRequest memory _request = addCollateralRequests[requestKeyToAddCollateralRequestsIndex[_requestKey]];
            for (uint256 i = 0; i < _puppets.length; i++) {
                uint256 _shares;
                address _puppet = _puppets[i];
                if (_isFailedRequest) {
                    if (i == 0) _totalSupply = _request.totalSupply;
                    _shares = _request.puppetsShares[i];
                } else {
                    if (i == 0) _totalSupply = _position.totalSupply;
                    _shares = _position.participantShares[_puppet];
                }

                if (_shares > 0) {
                    uint256 _assets = _convertToAssets(_balance, _totalSupply, _shares);

                    orchestrator.creditPuppetAccount(_assets, _route.collateralToken, _puppet);

                    _totalSupply -= _shares;
                    _balance -= _assets;

                    _puppetsAssets += _assets;
                }
            }

            uint256 _traderShares = _isFailedRequest ? _request.traderShares : _position.participantShares[_route.trader];
            uint256 _traderAssets = _convertToAssets(_balance, _totalSupply, _traderShares);

            IERC20(_route.collateralToken).safeTransfer(address(orchestrator), _puppetsAssets);
            IERC20(_route.collateralToken).safeTransfer(_route.trader, _traderAssets);
        }

        uint256 _ethBalance = address(this).balance;
        if ((_ethBalance - _traderAmountIn) > 0) {
            address _executionFeeReceiver = _repayKeeper ? orchestrator.keeper() : _route.trader;
            payable(_executionFeeReceiver).sendValue(_ethBalance - _traderAmountIn);
        }

        emit BalanceRepaid(_totalAssets);
    }

    function _resetRoute() internal {
        positionIndex += 1;

        emit RouteReset();
    }

    function _approve(address _spender, address _token, uint256 _amount) internal {
        IERC20(_token).safeApprove(_spender, 0);
        IERC20(_token).safeApprove(_spender, _amount);
    }

    // ============================================================================================
    // Internal View Functions
    // ============================================================================================

    function _isOpenInterest() internal view returns (bool) {
        Route memory _route = route;

        (uint256 _size, uint256 _collateral,,,,,,) = IGMXVault(orchestrator.gmxVault()).getPosition(address(this), _route.collateralToken, _route.indexToken, _route.isLong);

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