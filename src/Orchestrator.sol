// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Route} from "./Route.sol";

import {IOrchestrator} from "./interfaces/IOrchestrator.sol";

contract Orchestrator is ReentrancyGuard, IOrchestrator {

    using SafeERC20 for IERC20;
    using Address for address payable;

    struct RouteInfo {
        address route;
        address collateralToken;
        address indexToken;
        bool isLong;
        bool isRegistered;
        EnumerableSet.AddressSet puppets;
    }

    uint256 public solvencyMargin; // require puppet's balance to be `solvencyMargin` times more than the amount of his total allowances

    address public owner;
    address private prizePoolDistributor;
    address private callbackTarget;
    address private positionValidator;
    address private keeper;
    address private referralRebatesSender;
    address private gmxRouter;
    address private gmxReader;
    address private gmxVault;
    address private gmxPositionRouter;

    bytes32 private referralCode;

    mapping(bytes32 => RouteInfo) private routeInfo; // routeKey => RouteInfo
    mapping(address => bool) public isRoute; // Route => isRoute

    mapping(address => EnumerableMap.AddressToUintMap) private puppetAllowances; // puppet => Route => allowance
    mapping(address => uint256) public puppetDepositAccount; // puppet => deposit account balance

    mapping(bytes32 => address) private requestKeyToRoute; // GMX position key => Route address

    // ============================================================================================
    // Constructor
    // ============================================================================================

    constructor(
        address _owner,
        address _prizePoolDistributor,
        address _callbackTarget,
        address _positionValidator,
        address _keeper,
        address _referralRebatesSender,
        address _gmxRouter,
        address _gmxReader,
        address _gmxVault,
        address _gmxPositionRouter,
        bytes32 _referralCode
    ) {
        owner = _owner;
        prizePoolDistributor = _prizePoolDistributor;
        callbackTarget = _callbackTarget;
        positionValidator = _positionValidator;
        keeper = _keeper;

        referralRebatesSender = _referralRebatesSender;
        gmxRouter = _gmxRouter;
        gmxReader = _gmxReader;
        gmxVault = _gmxVault;
        gmxPositionRouter = _gmxPositionRouter;

        referralCode = _referralCode;

        solvencyMargin = 2; // require puppet's balance to be 2x the amount of his total allowances
    }

    // ============================================================================================
    // Modifiers
    // ============================================================================================

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyRoute() {
        if (msg.sender != owner && !isRoute[msg.sender]) revert NotRoute();
        _;
    }

    // ============================================================================================
    // View Functions
    // ============================================================================================

    function getRouteKey(address _trader, address _collateralToken, address _indexToken, bool _isLong) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_trader, _collateralToken, _indexToken, _isLong));
    }

    function getPuppetsForRoute(bytes32 _routeKey) external view override returns (address[] memory _puppets) {
        EnumerableSet.AddressSet storage _puppetsSet = routeInfo[_routeKey].puppets;
        _puppets = new address[](EnumerableSet.length(_puppetsSet));

        for (uint256 i = 0; i < EnumerableSet.length(_puppetsSet); i++) {
            _puppets[i] = EnumerableSet.at(_puppetsSet, i);
        }
    }

    function isPuppetSolvent(address _puppet) public view override returns (bool) {
        uint256 totalAllowance;
        EnumerableMap.AddressToUintMap storage _allowances = puppetAllowances[_puppet];

        for (uint256 i = 0; i < EnumerableMap.length(_allowances); i++) {
            (, uint256 _allowance) = EnumerableMap.at(_allowances, i);
            totalAllowance += _allowance;
        }

        return puppetDepositAccount[_puppet] >= (totalAllowance * solvencyMargin);
    }

    function getRouteForRequestKey(bytes32 _requestKey) external view override returns (address) {
        return requestKeyToRoute[_requestKey];
    }

    function getPuppetAllowance(address _puppet, address _route) external view override returns (uint256 _allowance) {
        return EnumerableMap.get(puppetAllowances[_puppet], _route);
    }

    function getGMXRouter() external view override returns (address) {
        return gmxRouter;
    }

    function getGMXReader() external view override returns (address) {
        return gmxReader;
    }

    function getGMXVault() external view override returns (address) {
        return gmxVault;
    }

    function getGMXPositionRouter() external view override returns (address) {
        return gmxPositionRouter;
    }

    function getCallbackTarget() external view override returns (address) {
        return callbackTarget;
    }

    function getReferralCode() external view override returns (bytes32) {
        return referralCode;
    }

    function getPositionValidator() external view override returns (address) {
        return positionValidator;
    }

    function getKeeper() external view override returns (address) {
        return keeper;
    }

    function getPrizePoolDistributor() external view override returns (address) {
        return prizePoolDistributor;
    }

    function getReferralRebatesSender() external view override returns (address) {
        return referralRebatesSender;
    }

    // ============================================================================================
    // Trader Functions
    // ============================================================================================

    // slither-disable-next-line reentrancy-no-eth
    function registerRoute(address _collateralToken, address _indexToken, bool _isLong) external override nonReentrant returns (bytes32 _routeKey) {
        address _trader = msg.sender;
        _routeKey = getRouteKey(_trader, _collateralToken, _indexToken, _isLong);
        if (routeInfo[_routeKey].isRegistered) revert RouteAlreadyRegistered();

        address _route = address(new Route(address(this), owner, _trader, _collateralToken, _indexToken, _isLong));

        RouteInfo storage _routeInfo = routeInfo[_routeKey];
        
        _routeInfo.traderRoute = _route;
        _routeInfo.collateralToken = _collateralToken;
        _routeInfo.indexToken = _indexToken;
        _routeInfo.isLong = _isLong;
        _routeInfo.isRegistered = true;

        isRoute[_route] = true;

        emit RegisterRoute(_trader, _route, _collateralToken, _indexToken, _isLong);
    }

    // ============================================================================================
    // Puppet Functions
    // ============================================================================================

    function depositToAccount(uint256 _assets, address _puppet) external payable override nonReentrant {
        if (_assets == 0) revert ZeroAmount();
        if (msg.value != _assets) revert InvalidAmount();

        puppetDepositAccount[_puppet] += _assets;

        emit DepositToAccount(_assets, msg.sender, _puppet);
    }

    function withdrawFromAccount(uint256 _assets, address _receiver) external override nonReentrant {
        if (_assets == 0) revert ZeroAmount();

        address _puppet = msg.sender;
        puppetDepositAccount[_puppet] -= _assets;

        if (!isPuppetSolvent(_puppet)) revert InsufficientPuppetFunds();

        payable(_receiver).sendValue(_assets);

        emit WithdrawFromAccount(_assets, _receiver, _puppet);
    }

    function updateRoutesSubscription(address[] memory _traders, uint256[] memory _allowances, address _collateralToken, address _indexToken, bool _isLong, bool _sign) external override nonReentrant {
        if (_traders.length != _allowances.length) revert MismatchedInputArrays();

        address _puppet = msg.sender;
        for (uint256 i = 0; i < _traders.length; i++) {
            bytes32 _routeKey = getRouteKey(_traders[i], _collateralToken, _indexToken, _isLong);
            RouteInfo storage _routeInfo = routeInfo[_routeKey];

            if (!_routeInfo.isRegistered) revert RouteNotRegistered();
            if (ITraderRoute(_routeInfo.route).getIsWaitingForCallback()) revert WaitingForCallback();
            if (ITraderRoute(_routeInfo.route).getIsPositionOpen()) revert PositionIsOpen();

            if (_sign) {
                EnumerableMap.set(puppetAllowances[_puppet], _routeInfo.route, _allowances[i]);

                if (!EnumerableSet.contains(_routeInfo.puppets, _puppet)) {
                    EnumerableSet.add(_routeInfo.puppets, _puppet);
                }
            } else {
                EnumerableMap.set(puppetAllowances[_puppet], _routeInfo.route, 0);

                if (EnumerableSet.contains(_routeInfo.puppets, _puppet)) {
                    EnumerableSet.remove(_routeInfo.puppets, _puppet);
                }
            }
        }

        if (!isPuppetSolvent(_puppet)) revert InsufficientPuppetFunds();

        emit UpdateRoutesSubscription(_traders, _allowances, _puppet, _collateralToken, _indexToken, _isLong, _sign);
    }

    // ============================================================================================
    // Route Functions
    // ============================================================================================

    function debitPuppetAccount(uint256 _amount, address _puppet) external override onlyRoute {
        puppetDepositAccount[_puppet] -= _amount;

        emit DebitPuppetAccount(_amount, _puppet, msg.sender);
    }

    function creditPuppetAccount(uint256 _amount, address _puppet) external override onlyRoute {
        puppetDepositAccount[_puppet] += _amount;

        emit CreditPuppetAccount(_amount, _puppet, msg.sender);
    }

    function liquidatePuppet(address _puppet, bytes32 _routeKey) external onlyRoute {
        RouteInfo storage _routeInfo = routeInfo[_routeKey];
        
        EnumerableSet.remove(_routeInfo.puppets, _puppet);
        EnumerableMap.set(puppetAllowances[_puppet], _routeInfo.traderRoute, 0);

        emit LiquidatePuppet(_puppet, _routeKey, msg.sender);
    }

    function updateRequestKeyToRoute(bytes32 _requestKey) external onlyRoute {
        requestKeyToRoute[_requestKey] = msg.sender;

        emit UpdateRequestKeyToRoute(_requestKey, msg.sender);
    }

    function sendFunds(uint256 _amount) external onlyRoute {
        payable(msg.sender).sendValue(_amount);

        emit SendFunds(_amount, msg.sender);
    }

    // ============================================================================================
    // Owner Functions
    // ============================================================================================

    function setGMXUtils(address _gmxRouter, address _gmxReader, address _gmxVault, address _gmxPositionRouter, address _referralRebatesSender) external onlyOwner {
        gmxRouter = _gmxRouter;
        gmxReader = _gmxReader;
        gmxVault = _gmxVault;
        gmxPositionRouter = _gmxPositionRouter;
        referralRebatesSender = _referralRebatesSender;
    }

    function setPuppetUtils(address _prizePoolDistributor, address _callbackTarget, address _positionValidator, address _keeper) external onlyOwner {
        prizePoolDistributor = _prizePoolDistributor;
        callbackTarget = _callbackTarget;
        positionValidator = _positionValidator;
        keeper = _keeper;
    }

    function setReferralCode(bytes32 _referralCode) external onlyOwner {
        referralCode = _referralCode;
    }

    function setSolvencyMargin(uint256 _solvencyMargin) external onlyOwner {
        solvencyMargin = _solvencyMargin;
    }

    function setOwner(address _owner) external onlyOwner {
        owner = _owner;
    }

    // ============================================================================================
    // Receive Function
    // ============================================================================================

    receive() external payable {}
}