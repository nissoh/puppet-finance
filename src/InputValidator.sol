// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IGMXReader} from "./interfaces/IGMXReader.sol";
import {IVault} from "./interfaces/IVault.sol";

import {IOrchestrator} from "./interfaces/IOrchestrator.sol";

contract InputValidator {

    address public owner;

    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    IOrchestrator public orchestrator;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    constructor(address _orchestrator, address _owner) {
        orchestrator = IOrchestrator(_orchestrator);
        owner = _owner;
    }

    // ============================================================================================
    // Functions
    // ============================================================================================

    function validatePositionParameters(bytes memory _traderPositionData, uint256 _traderAmountIn, uint256 _puppetsAmountIn, bool _isIncrease) external {
        // TODO
    }

    function validateSwapPath(bytes memory _traderSwapData, address _collateralToken) external view {
        (address[] memory _path,,) = abi.decode(_traderSwapData, (address[], uint256, address));

        if (_path[0] != _collateralToken) revert InvalidTokenIn();
        if (_path.length > 2) revert InvalidPathLength();

        uint256 _maxAmountTokenIn;
        IGMXReader _gmxReader = IGMXReader(orchestrator.getGMXReader());
        IVault _gmxVault = IVault(orchestrator.getGMXVault());

        _maxAmountTokenIn = _path[1] == ETH ? _gmxReader.getMaxAmountIn(_gmxVault, _collateralToken, WETH) : 
        _gmxReader.getMaxAmountIn(_gmxVault, _collateralToken, _path[1]);
        if (_maxAmountTokenIn == 0) revert InvalidMaxAmount();
    }

    // ============================================================================================
    // Errors
    // ============================================================================================

    error InvalidTokenIn();
    error InvalidPathLength();
    error InvalidMaxAmount();
}