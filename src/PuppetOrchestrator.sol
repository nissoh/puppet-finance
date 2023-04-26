// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TraderRoute} from "./TraderRoute.sol";

import {IPuppetRoute} from "./interfaces/IPuppetRoute.sol";
import {ITraderRoute} from "./interfaces/ITraderRoute.sol";
import {IPuppetOrchestrator} from "./interfaces/IPuppetOrchestrator.sol";

contract PuppetOrchestrator is ReentrancyGuard, IPuppetOrchestrator {

    using SafeERC20 for IERC20;
    using Address for address payable;

    struct RouteInfo {
        address traderRoute;
        address puppetRoute;
        address collateralToken;
        address indexToken;
        bool isLong;
        bool isRegistered;
        EnumerableSet.AddressSet puppets;
    }

    uint256 public solvencyMargin; // require puppet's balance to be `solvencyMargin` times more than the amount of his total allowances

    address public owner;
    address private gmxRouter;
    address private gmxReader;
    address private gmxVault;
    address private gmxPositionRouter;
    address private callbackTarget;
    address private positionValidator;
    address private keeper;

    bytes32 private referralCode;

    mapping(bytes32 => RouteInfo) private routeInfo; // routeKey => RouteInfo
    mapping(address => bool) public isRoute; // traderRoute => isRoute

    mapping(address => EnumerableMap.AddressToUintMap) private puppetAllowances; // puppet => traderRoute => allowance
    mapping(address => uint256) public puppetDepositAccount; // puppet => deposit account balance

    mapping(bytes32 => address) private positionKeyToTraderRoute; // GMX position key => traderRoute address

    // ============================================================================================
    // Constructor
    // ============================================================================================

    constructor(
        address _owner,
        address _positionValidator,
        address _keeper,
        address _gmxRouter,
        address _gmxReader,
        address _gmxVault,
        address _gmxPositionRouter,
        address _callbackTarget,
        bytes32 _referralCode
    ) {
        owner = _owner;
        positionValidator = _positionValidator;
        keeper = _keeper;

        gmxRouter = _gmxRouter;
        gmxReader = _gmxReader;
        gmxVault = _gmxVault;
        gmxPositionRouter = _gmxPositionRouter;

        callbackTarget = _callbackTarget;
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

    function getTraderRouteKey(address _account, address _collateralToken, address _indexToken, bool _isLong) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, _collateralToken, _indexToken, _isLong));
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

    function getTraderRouteForPositionKey(bytes32 _positionKey) external view override returns (address) {
        return positionKeyToTraderRoute[_positionKey];
    }

    function getRouteForRouteKey(bytes32 _routeKey) external view override returns (address _traderRoute, address _puppetRoute) {
        _traderRoute = routeInfo[_routeKey].traderRoute;
        _puppetRoute = routeInfo[_routeKey].puppetRoute;
    }

    function getPuppetAllowance(address _puppet, address _traderRoute) external view override returns (uint256 _allowance) {
        return EnumerableMap.get(puppetAllowances[_puppet], _traderRoute);
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

    // ============================================================================================
    // Trader Functions
    // ============================================================================================

    // slither-disable-next-line reentrancy-no-eth
    function registerRoute(address _collateralToken, address _indexToken, bool _isLong) external override nonReentrant returns (bytes32 _routeKey) {
        address _trader = msg.sender;
        _routeKey = getTraderRouteKey(_trader, _collateralToken, _indexToken, _isLong);
        if (routeInfo[_routeKey].isRegistered) revert RouteAlreadyRegistered();

        address _traderRoute = address(new TraderRoute(address(this), owner, _trader, _collateralToken, _indexToken, _isLong));
        address _puppetRoute = ITraderRoute(_traderRoute).getPuppetRoute();

        RouteInfo storage _routeInfo = routeInfo[_routeKey];
        
        _routeInfo.traderRoute = _traderRoute;
        _routeInfo.puppetRoute = _puppetRoute;
        _routeInfo.collateralToken = _collateralToken;
        _routeInfo.indexToken = _indexToken;
        _routeInfo.isLong = _isLong;
        _routeInfo.isRegistered = true;

        isRoute[_traderRoute] = true;
        isRoute[_puppetRoute] = true;

        emit RegisterRoute(_trader, _traderRoute, _puppetRoute, _collateralToken, _indexToken, _isLong);
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
            bytes32 _routeKey = getTraderRouteKey(_traders[i], _collateralToken, _indexToken, _isLong);
            RouteInfo storage _routeInfo = routeInfo[_routeKey];

            if (!_routeInfo.isRegistered) revert RouteNotRegistered();
            if (ITraderRoute(_routeInfo.traderRoute).getIsWaitingForCallback()) revert WaitingForCallback();
            if (IPuppetRoute(_routeInfo.puppetRoute).getIsPositionOpen()) revert PositionIsOpen();

            if (_sign) {
                EnumerableMap.set(puppetAllowances[_puppet], _routeInfo.traderRoute, _allowances[i]);

                if (!EnumerableSet.contains(_routeInfo.puppets, _puppet)) {
                    EnumerableSet.add(_routeInfo.puppets, _puppet);
                }
            } else {
                EnumerableMap.set(puppetAllowances[_puppet], _routeInfo.traderRoute, 0);

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

    function liquidatePuppet(address _puppet, bytes32 _positionKey) external onlyRoute {
        RouteInfo storage _routeInfo = routeInfo[_positionKey];
        
        EnumerableSet.remove(_routeInfo.puppets, _puppet);
        EnumerableMap.set(puppetAllowances[_puppet], _routeInfo.traderRoute, 0);

        emit LiquidatePuppet(_puppet, _positionKey, msg.sender);
    }

    function updatePositionKeyToTraderRoute(bytes32 _positionKey) external onlyRoute {
        positionKeyToTraderRoute[_positionKey] = msg.sender;

        emit UpdatePositionKeyToTraderRoute(_positionKey, msg.sender);
    }

    function sendFunds(uint256 _amount) external onlyRoute {
        payable(msg.sender).sendValue(_amount);

        emit SendFunds(_amount, msg.sender);
    }

    // ============================================================================================
    // Owner Functions
    // ============================================================================================

    function setGMXUtils(address _gmxRouter, address _gmxReader, address _gmxVault, address _gmxPositionRouter) external onlyOwner {
        gmxRouter = _gmxRouter;
        gmxReader = _gmxReader;
        gmxVault = _gmxVault;
        gmxPositionRouter = _gmxPositionRouter;
    }

    function setCallbackTarget(address _callbackTarget) external onlyOwner {
        callbackTarget = _callbackTarget;
    }

    function setReferralCode(bytes32 _referralCode) external onlyOwner {
        referralCode = _referralCode;
    }

    function setSolvencyMargin(uint256 _solvencyMargin) external onlyOwner {
        solvencyMargin = _solvencyMargin;
    }

    function setPositionValidator(address _positionValidator) external onlyOwner {
        positionValidator = _positionValidator;
    }

    function setOwner(address _owner) external onlyOwner {
        owner = _owner;
    }
}