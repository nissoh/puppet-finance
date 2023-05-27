// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {AggregatorV3Interface} from "@chainlink/src/v0.8/interfaces/AggregatorV3Interface.sol";

import {IVault} from "./interfaces/IVault.sol";
import {IGMXRouter} from "./interfaces/IGMXRouter.sol";
import {IGMXPositionRouter} from "./interfaces/IGMXPositionRouter.sol";
import {IGMXVault} from "./interfaces/IGMXVault.sol";
import {IGMXReader} from "./interfaces/IGMXReader.sol";

import {IRoute} from "./interfaces/IRoute.sol";

import "./Base.sol";

contract Route is Base, IRoute {

    using SafeERC20 for IERC20;
    using Address for address payable;

    uint256 private totalSupply;
    uint256 private totalAssets;
    uint256 private priceFeedDecimals;
    uint256 private addCollateralRequestsIndex;

    address public trader;
    address public collateralToken;
    address public indexToken;

    bool public isLong;
    bool public isPositionOpen;
    bool public waitForRatioAdjustment;

    bool private isETHRequest;

    bytes32 public routeTypeKey;

    bytes private traderRepaymentData;

    mapping(bytes32 => uint256) public requestKeyToIndex; // requestKey => addCollateralRequestsIndex
    mapping(uint256 => AddCollateralRequest) public addCollateralRequests; // addCollateralIndex => AddCollateralRequest

    // TODO - instead of EnumerableMap, use [epoch(index)][info], like in PrizePoolDistrebutor
    EnumerableMap.AddressToUintMap private participantShares; // participant => shares

    IOrchestrator public orchestrator;

    AggregatorV3Interface public priceFeed;

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

        (address _priceFeed, uint256 _decimals) = orchestrator.getPriceFeed(_collateralToken);
        priceFeed = AggregatorV3Interface(_priceFeed);
        priceFeedDecimals = _decimals;

        (referralCode, performanceFeePercentage, keeper, revenueDistributor) = orchestrator.getGlobalInfo();

        gmxInfo = orchestrator.getGMXInfo();

        routeTypeKey = orchestrator.getRouteTypeKey(_collateralToken, _indexToken, _isLong);

        IGMXRouter(gmxInfo.gmxRouter).approvePlugin(gmxInfo.gmxPositionRouter);
    }

    // ============================================================================================
    // Modifiers
    // ============================================================================================

    modifier onlyCallbackCaller() {
        if (msg.sender != owner && msg.sender != gmxInfo.gmxCallbackCaller) revert NotCallbackCaller();
        _;
    }

    modifier onlyKeeper() {
        if (msg.sender != owner && msg.sender != keeper) revert NotKeeper();
        _;
    }

    // ============================================================================================
    // Trader Functions
    // ============================================================================================

    /// @dev violates checks-effects-interactions pattern. we use reentrancy guard
    // slither-disable-next-line reentrancy-eth
    function createPositionRequest(bytes memory _traderPositionData, bytes memory _traderSwapData, bool _isIncrease) public payable nonReentrant returns (bytes32 _requestKey) {
        if (msg.sender != trader) revert NotTrader();
        if (orchestrator.getIsPaused()) revert Paused();
        if (waitForRatioAdjustment) revert WaiingtForRatioAdjustment();

        isPositionOpen = true;

        if (!isETHRequest) _checkForReferralRebates();

        uint256 _traderAmountIn;
        uint256 _puppetsAmountIn;
        if (_isIncrease) {
            (_traderAmountIn, _puppetsAmountIn) = _getAssets(_traderSwapData);
            _requestKey = _createIncreasePositionRequest(_traderPositionData, _traderAmountIn, _puppetsAmountIn);
        } else {
            _validateRepaymentData(_traderSwapData);
            traderRepaymentData = _traderSwapData;
            _requestKey = _createDecreasePositionRequest(_traderPositionData);
        }
    }

    function createAddCollateralRequestETH(bytes memory _traderPositionData, uint256 _minOut) external payable returns (bytes32 _requestKey) {
        (,,, uint256 _executionFee) = abi.decode(_traderPositionData, (uint256, uint256, uint256, uint256));
        uint256 _amount = msg.value - _executionFee;
        address _weth = WETH;
        address[] memory _path = new address[](2);
        _path[0] = _weth;
        _path[1] = collateralToken;
        bytes memory _traderSwapData = abi.encodePacked(_path, _amount, _minOut);

        _checkForReferralRebates();

        isETHRequest = true;

        payable(_weth).functionCallWithValue(abi.encodeWithSignature("deposit()"), _amount);

        return createPositionRequest(_traderPositionData, _traderSwapData, true);
    }

    // ============================================================================================
    // Keeper Function
    // ============================================================================================

    function decreaseSize() external nonReentrant onlyKeeper {
        // TODO - function for keeper to DecreasePosition on a scenario where Trader adds collateral but puppets cannot pay
        // we'll need to decrease the size of puppets that were not able to pay
    }

    function liquidate() external nonReentrant onlyKeeper {
        if (!_isLiquidated()) revert PositionStillAlive();

        _repayBalance(bytes32(0), false);

        emit Liquidated();
    }

    function checkForReferralRebates() external nonReentrant onlyKeeper {
        _checkForReferralRebates();
    }

    // ============================================================================================
    // Callback Function
    // ============================================================================================

    function gmxPositionCallback(bytes32 _requestKey, bool _isExecuted, bool _isIncrease) external nonReentrant onlyCallbackCaller {
        emit CallbackReceived(_requestKey, _isExecuted, _isIncrease);

        bool _repayKeeper;
        if (_isExecuted) {
            if (waitForRatioAdjustment) {
                // call by keeper was executed
                waitForRatioAdjustment = false;
                _repayKeeper = true;

                emit RatioAdjustmentExecuted();
            } else {
                // call by trader was executed
                if (_isIncrease) _allocateShares(_requestKey);

                _repayKeeper = false;
            }

            _requestKey = bytes32(0);
        } else if (waitForRatioAdjustment) {
            // call by keeper was not executed
            _repayKeeper = true;
            _requestKey = bytes32(0);

            emit RatioAdjustmentFailed();
        } else {
            // call by trader was not executed
            _repayKeeper = false;
            _requestKey = _requestKey;
        }

        _repayBalance(_requestKey, _repayKeeper);
    }

    // ============================================================================================
    // Owner Functions
    // ============================================================================================

    function approvePlugin() external onlyOwner {
        IGMXRouter(gmxInfo.gmxRouter).approvePlugin(gmxInfo.gmxPositionRouter);

        emit PluginApproved();
    }

    function setOrchestrator(address _orchestrator) external onlyOwner {
        orchestrator = IOrchestrator(_orchestrator);

        emit OrchestratorSet(_orchestrator);
    }

    function updatePriceFeed() external onlyOwner {
        (address _priceFeed, uint256 _decimals) = orchestrator.getPriceFeed(collateralToken);
        priceFeed = AggregatorV3Interface(_priceFeed);
        priceFeedDecimals = _decimals;

        emit PriceFeedUpdated();
    }

    function updateGlobalInfo() external onlyOwner {
        (
            referralCode,
            performanceFeePercentage,
            keeper,
            revenueDistributor
        ) = orchestrator.getGlobalInfo();

        emit GlobalInfoUpdated();
    }

    function updateGMXInfo() external onlyOwner {
        gmxInfo = orchestrator.getGMXInfo();

        emit GMXInfoUpdated();
    }

    // ============================================================================================
    // Internal Mutated Functions
    // ============================================================================================

    function _getAssets(bytes memory _traderSwapData) internal returns (uint256 _traderAmountIn, uint256 _puppetsAmountIn) {
        (,uint256 _amount,) = abi.decode(_traderSwapData, (address[], uint256, uint256));
        if (_amount > 0) {
            // 1. get trader assets and allocate shares on request
            _traderAmountIn = _getTraderAssets(_traderSwapData);

            uint256 _totalSupply = 0;
            uint256 _totalAssets = 0;

            uint256 _traderShares = _convertToShares(_totalAssets, _totalSupply, _traderAmountIn);
        
            _totalSupply = _traderShares;
            _totalAssets = _traderAmountIn;

            // 2. get puppets assets and allocate shares on request
            bool _isOI = _isOpenInterest();
            uint256 _collateralIncreaseRatio = 0;
            uint256 _totalRouteSupply = totalSupply;
            uint256 _totalRouteCollateral = _getCollateralInPosition();
            if (_isOI) {
                // potentially increasing collateral (_traderAmountIn could be 0)
                uint256 _traderOwnedCollateral = EnumerableMap.get(participantShares, trader) * _totalRouteCollateral / _totalRouteSupply;
                _collateralIncreaseRatio = _traderAmountIn * 1e18 / _traderOwnedCollateral;
            }

            address _collateralToken = collateralToken;
            bytes32 _routeKey = orchestrator.getRouteKey(trader, routeTypeKey);
            address[] memory _puppetsToAdjust;
            address[] memory _puppets = orchestrator.getPuppetsForRoute(_routeKey);
            uint256[] memory _puppetsShares = new uint256[](_puppets.length);
            uint256[] memory _puppetsAmounts = new uint256[](_puppets.length);
            for (uint256 i = 0; i < _puppets.length; i++) {
                address _puppet = _puppets[i];
                uint256 _puppetShares = 0;
                uint256 _allowancePercentage = orchestrator.getPuppetAllowancePercentage(_puppet, address(this));
                uint256 _puppetAllowanceAmount = (orchestrator.getPuppetAccountBalance(_collateralToken, _puppet) * _allowancePercentage) / 100;
                if (_isOI) {
                    // potentially increasing collateral (_collateralIncreaseRatio/puppetShares could be 0)
                    uint256 _puppetOwnedCollateral = EnumerableMap.get(participantShares, _puppet) * _totalRouteCollateral / _totalRouteSupply;
                    uint256 _puppetRequiredAdditionalCollateral = _puppetOwnedCollateral * _collateralIncreaseRatio / 1e18;
                    if (_puppetRequiredAdditionalCollateral > _puppetAllowanceAmount || _puppetRequiredAdditionalCollateral == 0) {
                        _puppetsToAdjust[_puppetsToAdjust.length] = _puppet;
                        _puppetAllowanceAmount = 0;
                    } else {
                        _puppetAllowanceAmount = _puppetRequiredAdditionalCollateral;
                        _puppetShares = _convertToShares(_totalAssets, _totalSupply, _puppetAllowanceAmount);
                    }
                } else {
                    if (_puppetAllowanceAmount > 0 && orchestrator.isBelowThrottleLimit(address(this), _puppet)) {
                        if (_puppetAllowanceAmount > _traderAmountIn) _puppetAllowanceAmount = _traderAmountIn;
                        _puppetShares = _convertToShares(_totalAssets, _totalSupply, _puppetAllowanceAmount);
                    } else {
                        _puppetAllowanceAmount = 0;
                    }
                }

                if (_puppetAllowanceAmount > 0) {
                    orchestrator.debitPuppetAccount(_puppetAllowanceAmount, _collateralToken, _puppet);

                    _puppetsAmountIn += _puppetAllowanceAmount;

                    _totalSupply += _puppetShares;
                    _totalAssets += _puppetAllowanceAmount;
                }

                _puppetsShares[_puppetsShares.length] = _puppetShares;
                _puppetsAmounts[_puppetsAmounts.length] = _puppetAllowanceAmount;
            }

            if (_puppetsToAdjust.length > 0) {
                waitForRatioAdjustment = true;

                emit PuppetsToAdjust(_puppetsToAdjust);
            }

            // 3. store request data
            AddCollateralRequest memory _request = AddCollateralRequest({
                puppetsAmountIn: _puppetsAmountIn,
                traderAmountIn: _traderAmountIn,
                traderShares: _traderShares,
                totalSupply: _totalSupply,
                totalAssets: _totalAssets,
                puppetsToAdjust: _puppetsToAdjust,
                puppetsShares: _puppetsShares,
                puppetsAmounts: _puppetsAmounts
            });

            addCollateralRequests[addCollateralRequestsIndex] = _request;
            addCollateralRequestsIndex += 1;

            // 4. pull funds from Orchestrator
            orchestrator.sendFunds(_puppetsAmountIn, _collateralToken, address(this));
        }
    }

    function _getTraderAssets(bytes memory _traderSwapData) internal returns (uint256 _traderAmountIn) {
        (address[] memory _path, uint256 _amount, uint256 _minOut) = abi.decode(_traderSwapData, (address[], uint256, uint256));

        address _fromToken = _path[0];
        if (!isETHRequest) IERC20(_fromToken).safeTransferFrom(msg.sender, address(this), _amount);

        if (_fromToken == collateralToken) {
            _traderAmountIn = _amount;
        } else {
            address _toToken = _path[_path.length - 1];
            if (_toToken != collateralToken) revert InvalidPath();

            address _router = gmxInfo.gmxRouter;
            _approve(_router, _fromToken, _amount);

            uint256 _before = IERC20(_toToken).balanceOf(address(this));
            IGMXRouter(_router).swap(_path, _amount, _minOut, address(this));
            _traderAmountIn = IERC20(_toToken).balanceOf(address(this)) - _before;
        }
    }

    function _allocateShares(bytes32 _requestKey) internal {
        AddCollateralRequest memory _request = addCollateralRequests[requestKeyToIndex[_requestKey]];
        uint256 _traderAmountIn = _request.traderAmountIn;
        if (_traderAmountIn > 0) {
            uint256 _totalSupply = totalSupply;
            uint256 _totalAssets = totalAssets;
            address _trader = trader;
            bytes32 _routeKey = orchestrator.getRouteKey(_trader, routeTypeKey);
            address[] memory _puppets = orchestrator.getPuppetsForRoute(_routeKey);
            for (uint256 i = 0; i < _puppets.length; i++) {
                address _puppet = _puppets[i];
                uint256 _puppetAmountIn = _request.puppetsAmounts[i];
                if (_puppetAmountIn > 0) {
                    uint256 _puppetShares = EnumerableMap.get(participantShares, _puppet);
                    uint256 _newPuppetShares = _convertToShares(_totalAssets, _totalSupply, _puppetAmountIn);

                    EnumerableMap.set(participantShares, _puppet, _puppetShares + _newPuppetShares);

                    _totalSupply += _newPuppetShares;
                    _totalAssets += _puppetAmountIn;
                }
            }

            uint256 _traderShares = EnumerableMap.get(participantShares, _trader);
            uint256 _newTraderShares = _convertToShares(_totalAssets, _totalSupply, _traderAmountIn);

            EnumerableMap.set(participantShares, _trader, _traderShares + _newTraderShares);

            _totalSupply += _newTraderShares;
            _totalAssets += _traderAmountIn;

            totalSupply = _totalSupply;
            totalAssets = _totalAssets;
        }
    }

    function _createIncreasePositionRequest(bytes memory _traderPositionData, uint256 _traderAmountIn, uint256 _puppetsAmountIn) internal returns (bytes32 _requestKey) {
        (uint256 _minOut, uint256 _sizeDelta, uint256 _acceptablePrice, uint256 _executionFee) = abi.decode(_traderPositionData, (uint256, uint256, uint256, uint256));

        address[] memory _path = new address[](1);
        _path[0] = collateralToken;

        uint256 _amountIn = _traderAmountIn + _puppetsAmountIn;

        if (isETHRequest && msg.value != (_amountIn + _executionFee)) revert InvalidValue();
        if (!isETHRequest && msg.value != _executionFee) revert InvalidValue();
        isETHRequest = false;

        // slither-disable-next-line arbitrary-send-eth
        _requestKey = IGMXPositionRouter(gmxInfo.gmxPositionRouter).createIncreasePosition{ value: _executionFee } (
            _path,
            indexToken,
            _amountIn,
            _minOut,
            _sizeDelta,
            isLong,
            _acceptablePrice,
            _executionFee,
            referralCode,
            gmxInfo.gmxCallbackCaller
        );

        if (_amountIn > 0) requestKeyToIndex[_requestKey] = addCollateralRequestsIndex - 1;

        if (!_isOpenInterest()) {
            // new position opened
            _updateLastPositionOpenedTimestamp(); // used to limit the number of position that can be opened in a given time period
        }

        emit CreatedIncreasePositionRequest(_requestKey, _amountIn, _minOut, _sizeDelta, _acceptablePrice, _executionFee);
    }

    function _createDecreasePositionRequest(bytes memory _traderPositionData) internal returns (bytes32 _requestKey) {
        (uint256 _collateralDelta, uint256 _sizeDelta, uint256 _acceptablePrice, uint256 _minOut, uint256 _executionFee)
            = abi.decode(_traderPositionData, (uint256, uint256, uint256, uint256, uint256));

        if (msg.value != _executionFee) revert InvalidExecutionFee();

        address[] memory _path = new address[](1);
        _path[0] = collateralToken;

        // slither-disable-next-line arbitrary-send-eth
        _requestKey = IGMXPositionRouter(gmxInfo.gmxPositionRouter).createDecreasePosition{ value: _executionFee } (
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
            gmxInfo.gmxCallbackCaller
        );

        emit CreatedDecreasePositionRequest(_requestKey, _minOut, _collateralDelta, _sizeDelta, _acceptablePrice, _executionFee);
    }

    function _repayBalance(bytes32 _requestKey, bool _repayKeeper) internal {
        address _collateralToken = collateralToken;
        uint256 _totalAssets = IERC20(_collateralToken).balanceOf(address(this));
        if (_totalAssets > 0) {
            uint256 _puppetsAssets = 0;
            uint256 _totalSupply = 0;
            uint256 _balance = _totalAssets;
            bool _isFailedRequest = _requestKey != bytes32(0);
            bytes32 _key = orchestrator.getRouteKey(trader, routeTypeKey);
            address[] memory _puppets = orchestrator.getPuppetsForRoute(_key);
            AddCollateralRequest memory _request = addCollateralRequests[requestKeyToIndex[_requestKey]];
            for (uint256 i = 0; i < _puppets.length; i++) {
                uint256 _shares;
                address _puppet = _puppets[i];
                if (_isFailedRequest) {
                    if (i == 0) _totalSupply = _request.totalSupply;
                    _shares = _request.puppetsShares[i];
                } else {
                    if (i == 0) _totalSupply = totalSupply;
                    _shares = EnumerableMap.get(participantShares, _puppet);
                }

                if (_shares > 0) {
                    uint256 _assets = _convertToAssets(_balance, _totalSupply, _shares);

                    orchestrator.creditPuppetAccount(_assets, _collateralToken, _puppet);

                    _totalSupply -= _shares;
                    _balance -= _assets;

                    _puppetsAssets += _assets;
                }
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
            address _executionFeeReceiver = _repayKeeper ? keeper : trader;
            payable(_executionFeeReceiver).sendValue(_ethBalance);
        }

        emit RepaidBalance(_totalAssets);
    }

    function _repayTrader(uint256 _traderAssets, bool _isFailedRequest) internal {
        if (_isFailedRequest) {
            IERC20(collateralToken).safeTransfer(trader, _traderAssets);
        } else {
            (address[] memory _path, uint256 _minOut, address _receiver) = abi.decode(traderRepaymentData, (address[], uint256, address));
            address _fromToken = collateralToken;
            address _toToken = _path[_path.length - 1];
            IGMXRouter _router = IGMXRouter(gmxInfo.gmxRouter);
            if (_fromToken != _toToken && _toToken != ETH) {
                _approve(address(_router), _fromToken, _traderAssets);

                uint256 _before = IERC20(_toToken).balanceOf(address(this));
                _router.swap(_path, _traderAssets, _minOut, address(this));
                _traderAssets = IERC20(_toToken).balanceOf(address(this)) - _before;
            }

            if (_toToken == ETH) {
                _router.swapTokensToETH(_path, _traderAssets, _minOut, payable(_receiver));
            } else {
                IERC20(_toToken).safeTransfer(_receiver, _traderAssets);
            }
        }
    }

    function _resetRoute() internal {
        isPositionOpen = false;
        totalAssets = 0;
        totalSupply = 0;
        for (uint256 i = 0; i < EnumerableMap.length(participantShares); i++) {
            (address _key, ) = EnumerableMap.at(participantShares, i);
            EnumerableMap.remove(participantShares, _key);
        }

        emit RouteReseted();
    }    

    function _updateLastPositionOpenedTimestamp() internal {
        bytes32 _routeKey = orchestrator.getRouteKey(trader, routeTypeKey);
        address[] memory _puppets = orchestrator.getPuppetsForRoute(_routeKey);
        for (uint256 i = 0; i < _puppets.length; i++) {
            address _puppet = _puppets[i];
            orchestrator.updateLastPositionOpenedTimestamp(address(this), _puppet);
        }
    }

    function _checkForReferralRebates() internal {
        uint256 _balance = IERC20(WETH).balanceOf(address(this));
        if (_balance > 0) {
            address _revenueDistributor = revenueDistributor;
            _approve(_revenueDistributor, WETH, _balance);
            IERC20(WETH).safeTransfer(_revenueDistributor, _balance);

            emit ReferralRebatesSent(_revenueDistributor, _balance);
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
        (uint256 _size, uint256 _collateral,,,,,,) = IGMXVault(gmxInfo.gmxVault).getPosition(address(this), collateralToken, indexToken, isLong);

        return _size > 0 && _collateral > 0;
    }

    function _getCollateralInPosition() internal view returns (uint256 _collateralInPosition) {
        // todo, this is USD denominated, need to convert to collateral denominated
        // (, int256 _price,,,) = priceFeed.latestRoundData();
        (,_collateralInPosition,,,,,,) = IGMXVault(gmxInfo.gmxVault).getPosition(address(this), collateralToken, indexToken, isLong);
    }

    function _isLiquidated() internal view returns (bool) {
        (uint256 state, ) = IGMXVault(gmxInfo.gmxVault).validateLiquidation(address(this), collateralToken, indexToken, isLong, false);

        return state > 0;
    }

    function _validateRepaymentData(bytes memory _traderSwapData) internal view {
        (address[] memory _path,,) = abi.decode(_traderSwapData, (address[], uint256, address));
        address _collateralToken = collateralToken;

        if (_path[0] != _collateralToken) revert InvalidTokenIn();
        if (_path.length > 2) revert InvalidPathLength();

        uint256 _maxAmountTokenIn;
        IGMXReader _gmxReader = IGMXReader(gmxInfo.gmxReader);
        IVault _gmxVault = IVault(gmxInfo.gmxVault);

        _maxAmountTokenIn = _path[1] == ETH ? _gmxReader.getMaxAmountIn(_gmxVault, _collateralToken, WETH) : 
        _gmxReader.getMaxAmountIn(_gmxVault, _collateralToken, _path[1]);
        if (_maxAmountTokenIn == 0) revert InvalidMaxAmount();
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
        if (gmxInfo.gmxReferralRebatesSender == msg.sender) payable(revenueDistributor).sendValue(msg.value);
    }
}