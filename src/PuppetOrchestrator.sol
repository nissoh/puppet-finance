// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
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

    struct RouteInfo {
        address traderRoute;
        address collateralToken;
        address indexToken;
        bool isLong;
        bool isRegistered;
        EnumerableSet.AddressSet puppets;
    }

    uint256 solvencyMargin;

    address public owner;
    address private gmxRouter;
    address private gmxReader;
    address private gmxVault;
    address private gmxPositionRouter;
    address private callbackTarget;

    bytes32 private referralCode;

    mapping(address => uint256) public puppetDepositAccount;
    mapping(address => bool) public isTraderRoute;
    mapping(bytes32 => ITraderRoute) public traderRoute;

    mapping(bytes32 => address) private gmxPositionKeyToTraderRouteAddress;

    // puppet => traderRoute => allowance
    mapping(address => EnumerableMap.AddressToUintMap) private puppetAllowances;
    mapping(bytes32 => RouteInfo) private routeInfo;

    // ====================== Constructor ======================

    constructor(address _gmxRouter, address _gmxReader, address _gmxVault, address _gmxPositionRouter, address _callbackTarget, bytes32 _referralCode) {
        callbackTarget = _callbackTarget;
        referralCode = _referralCode;

        gmxRouter = _gmxRouter;
        gmxReader = _gmxReader;
        gmxVault = _gmxVault;
        gmxPositionRouter = _gmxPositionRouter;

        solvencyMargin = 2;
    }

    // ====================== Modifiers ======================

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyTraderRoute() {
        if (!isTraderRoute[msg.sender]) revert Unauthorized();
        _;
    }

    // ====================== Trader Functions ======================

    function registerRoute(address _collateralToken, address _indexToken, bool _isLong) external nonReentrant returns (bytes32 _routeKey) {
        address _trader = msg.sender;
        _routeKey = getPositionKey(_trader, _collateralToken, _indexToken, _isLong);
        if (routeInfo[_routeKey].isRegistered) revert RouteAlreadyRegistered();

        ITraderRoute _routeAddress = new TraderRoute(_trader, _collateralToken, _indexToken, _isLong);

        routeInfo[_routeKey] = RouteInfo({
            traderRoute: address(_routeAddress),
            collateralToken: _collateralToken,
            indexToken: _indexToken,
            isLong: _isLong,
            isRegistered: true,
            puppets: EnumerableSet.AddressSet(0)
        });

        isTraderRoute[address(_routeAddress)] = true;

        emit RegisterRoute(_trader, address(_routeAddress), _collateralToken, _indexToken, _isLong);
    }

    // ====================== Puppet Functions ======================

    function depositToAccount(uint256 _assets, address _puppet) external payable nonReentrant {
        if (_assets == 0) revert ZeroAmount();
        if (msg.value != _assets) revert InvalidAmount();

        puppetDepositAccount[_puppet] += _assets;

        emit DepositToAccount(_assets, msg.sender, _puppet);
    }

    function withdrawFromAccount(uint256 _assets, address _receiver) external nonReentrant {
        if (_assets == 0) revert ZeroAmount();

        address _puppet = msg.sender;
        puppetDepositAccount[_puppet] -= _assets;

        payable(_receiver).sendValue(_assets);

        emit WithdrawFromAccount(_assets, _puppet, _receiver);
    }

    function toggleRouteSubscription(address[] memory _traders, uint256[] memory _allowances, address _collateralToken, address _indexToken, bool _isLong, bool _sign) external nonReentrant {
        if (_traders.length != _allowances.length) revert MismatchedInputArrays();

        address _puppet = msg.sender;
        for (uint256 i = 0; i < _traders.length; i++) {
            RouteInfo storage _routeInfo = routeInfo[getPositionKey(_traders[i], _collateralToken, _indexToken, _isLong)];

            if (!_routeInfo.isRegistered) revert RouteNotRegistered();
            if (ITraderRoute(_routeInfo.traderRoute).isWaitingForCallback()) revert WaitingForCallback();
            if (ITraderRoute(_routeInfo.traderRoute).isPositionOpen()) revert PositionIsOpen();

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

            emit ToggleRouteSubscription(_traders, _allowances, _puppet, _collateralToken, _indexToken, _isLong, _sign);
        }
    }

    // ====================== TraderRoute functions ======================

    function debitPuppetAccount(uint256 _amount, address _puppet) external override onlyTraderRoute {
        puppetDepositAccount[_puppet] -= _amount;
    }

    function creditPuppetAccount(uint256 _amount, address _puppet) external override onlyTraderRoute {
        puppetDepositAccount[_puppet] += _amount;
    }

    function updateGMXPositionKeyToTraderRouteAddress(bytes32 _gmxPositionKey) external onlyTraderRoute {
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

    function setSolvencyMargin(uint256 _solvencyMargin) external onlyOwner {
        solvencyMargin = _solvencyMargin;
    }

    function setOwner(address _owner) external onlyOwner {
        owner = _owner;
    }

    // ====================== Helper Functions ======================

    function getPositionKey(address _account, address _collateralToken, address _indexToken, bool _isLong) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, _collateralToken, _indexToken, _isLong));
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

    function getTraderRouteForPosition(bytes32 _gmxPositionKey) external view returns (address _traderRoute) {
        return gmxPositionKeyToTraderRouteAddress[_gmxPositionKey];
    }

    function isPuppetSolvent(address _puppet) public view returns (bool) {
        uint256 totalAllowance;
        EnumerableMap.AddressToUintMap storage allowances = puppetAllowances[_puppet];

        for (uint256 i = 0; i < EnumerableMap.length(allowances); i++) {
            (, uint256 _allowance) = EnumerableMap.at(allowances, i);
            totalAllowance += _allowance;
        }

        return puppetDepositAccount[_puppet] >= (totalAllowance * solvencyMargin);
    }
}