// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TraderRoute} from "./TraderRoute.sol";

import {IGMXRouter} from "./interfaces/IGMXRouter.sol";
import {IGMXPositionRouter} from "./interfaces/IGMXPositionRouter.sol";
import {IPuppetOrchestrator} from "./interfaces/IPuppetOrchestrator.sol";
import {ITraderRoute} from "./interfaces/ITraderRoute.sol";
import {IWETH} from "./interfaces/IWETH.sol";

contract PuppetOrchestrator is ReentrancyGuard, IPuppetOrchestrator {

    using SafeERC20 for IERC20;
    using Address for address payable;

    address public owner;
    address private gmxRouter;
    address private gmxReader;
    address private gmxVault;
    address private gmxPositionRouter;
    address private callbackTarget;
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    bytes32 private referralCode;

    mapping(bytes32 => address) private gmxPositionKeyToTraderRouteAddress;

    // mapping(bytes32 => address) public traderRoute;
    mapping(bytes32 => ITraderRoute) public traderRoute;
    mapping(address => bool) public isTraderRoute;

    // token => puppet => balance
    mapping(address => mapping(address => uint256)) public puppetDepositAccount;

    // ====================== Constructor ======================

    constructor(address _gmxRouter, address _gmxReader, address _gmxVault, address _gmxPositionRouter, address _callbackTarget, bytes32 _referralCode) {
        callbackTarget = _callbackTarget;
        referralCode = _referralCode;

        gmxRouter = _gmxRouter;
        gmxReader = _gmxReader;
        gmxVault = _gmxVault;
        gmxPositionRouter = _gmxPositionRouter;
    }

    // ====================== Modifiers ======================

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyTrderRoute() {
        if (!isTraderRoute[msg.sender]) revert Unauthorized();
        _;
    }

    // ====================== View Functions ======================

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

    function getCallbackTarget() external view override returns (address _callbackTarget) {
        return callbackTarget;
    }

    function getReferralCode() external view override returns (bytes32 _referralCode) {
        return referralCode;
    }

    function isPuppetSolvent(uint256 _amount, address _token, address _puppet) external view override returns (bool _isSolvent) {
        return puppetDepositAccount[_token][_puppet] >= _amount;
    }

    function getTraderRouteForPosition(bytes32 _gmxPositionKey) external view returns (address _traderRoute) {
        return gmxPositionKeyToTraderRouteAddress[_gmxPositionKey];
    }

    // ====================== Trader Functions ======================

    function registerRoute(address _collateralToken, address _indexToken, bool _isLong) external nonReentrant returns (bytes32 _routeKey) {
        address _trader = msg.sender;
        _routeKey = getPositionKey(_trader, _collateralToken, _indexToken, _isLong);
        if (address(traderRoute[_routeKey]) != address(0)) revert RouteAlreadyRegistered();

        ITraderRoute _routeAddress = new TraderRoute(_trader, _collateralToken, _indexToken, _isLong);

        traderRoute[_routeKey] = _routeAddress;
        isTraderRoute[address(_routeAddress)] = true;

        emit RegisterRoute(_trader, address(_routeAddress), _collateralToken, _indexToken, _isLong);
    }

    // ====================== Puppet Functions ======================

    function depositETHToAccount(uint256 _amount, address _puppet) external payable nonReentrant { 
        if (msg.value != _amount) revert InvalidAmount();

        address _weth = WETH;
        IWETH(_weth).deposit{value: _amount}();
        puppetDepositAccount[_weth][_puppet] += _amount;

        emit DepositToAccount(_amount, _weth, msg.sender, _puppet);
    }

    function depositToAccount(uint256 _amount, address _token, address _puppet) external nonReentrant {
        puppetDepositAccount[_token][_puppet] += _amount;

        address _caller = msg.sender;
        IERC20(_token).safeTransferFrom(_caller, address(this), _amount);

        emit DepositToAccount(_amount, _token, _caller, _puppet);
    }

    function withdrawETHFromAccount(uint256 _amount) external nonReentrant {
        address _puppet = msg.sender;
        address _weth = WETH;
        puppetDepositAccount[_weth][_puppet] -= _amount;

        IWETH(_weth).withdraw(_amount);
        payable(_puppet).sendValue(_amount);

        emit WithdrawFromAccount(_amount, _weth, _puppet);
    }

    function withdrawFromAccount(uint256 _amount, address _token) external nonReentrant {
        address _puppet = msg.sender;
        puppetDepositAccount[_token][_puppet] -= _amount;

        IERC20(_token).safeTransfer(_puppet, _amount);

        emit WithdrawFromAccount(_amount, _token, _puppet);
    }

    function toggleRouteSubscription(address[] memory _traders, uint256[] memory _allowances, address _collateralToken, address _indexToken, bool _isLong, bool _sign) external nonReentrant {
        bytes32 _routeKey;
        address _puppet = msg.sender;
        for (uint256 i = 0; i < _traders.length; i++) {
            _routeKey = getPositionKey(_traders[i], _collateralToken, _indexToken, _isLong);
            ITraderRoute _route = traderRoute[_routeKey];
            if (address(_route) == address(0)) revert RouteNotRegistered();

            if (_sign) {
                _route.signPuppet(_puppet, _allowances[i]);
            } else {
                _route.unsignPuppet(_puppet);
            }
        }

        emit PuppetToggleSubscription(_traders, _allowances, _puppet, _collateralToken, _indexToken, _isLong, _sign);
    }

    function setTraderAllowance(bytes32[] memory _routeKeys, uint256[] memory _allowances) external nonReentrant {
        address _puppet = msg.sender;
        for (uint256 i = 0; i < _routeKeys.length; i++) {
            ITraderRoute _route = traderRoute[_routeKeys[i]];
            if (address(_route) == address(0)) revert RouteNotRegistered();
            if (_route.isWaitingForCallback()) revert WaitingForCallback();
            if (_route.isPuppetSigned(_puppet)) revert PuppetNotSigned();
            if (_route.isPositionOpen()) revert PositionOpen();

            _route.setAllowance(_puppet, _allowances[i]);
        }

        emit PuppetSetAllowance(_routeKeys, _allowances, _puppet);
    }

    // ====================== TraderRoute functions ======================

    function debitPuppetAccount(uint256 _amount, address _puppet, address _token) external override onlyTrderRoute {
        puppetDepositAccount[_token][_puppet] -= _amount;
    }

    function creditPuppetAccount(uint256 _amount, address _puppet, address _token) external override onlyTrderRoute {
        puppetDepositAccount[_token][_puppet] += _amount;
    }

    function updateGMXPositionKeyToTraderRouteAddress(bytes32 _gmxPositionKey) external onlyTrderRoute {
        gmxPositionKeyToTraderRouteAddress[_gmxPositionKey] = msg.sender;
    }

    // ====================== Owner Functions ======================

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

    function setOwner(address _owner) external onlyOwner {
        owner = _owner;
    }

    // ====================== Helper Functions ======================

    function getPositionKey(address _account, address _collateralToken, address _indexToken, bool _isLong) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, _collateralToken, _indexToken, _isLong));
    }
}