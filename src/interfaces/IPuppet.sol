// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// =========================== IPuppet ==========================
// ==============================================================

// Modified fork from Curve Finance: https://github.com/curvefi 
// @title Curve Finance Token
// @author Curve Finance
// @license MIT
// @notice ERC20 with piecewise-linear mining supply.
// @dev Based on the ERC-20 token standard as defined @ https://eips.ethereum.org/EIPS/eip-20

// Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

interface IPuppet {
    
        function mintableInTimeframe(uint256 start, uint256 end) external view returns (uint256);

        function mint(address _to, uint256 _value) external returns (bool);

        function updateMiningParameters() external;
        
        // ============================================================================================
        // Events
        // ============================================================================================

        event Transfer(address indexed from, address indexed to, uint256 value);
        event Approval(address indexed owner, address indexed spender, uint256 value);
        event UpdateMiningParameters(uint256 time, uint256 rate, uint256 supply);
        event SetMinter(address minter);
        event SetAdmin(address admin);

        // ============================================================================================
        // Errors
        // ============================================================================================

        error NotAdmin();
        error NotMinter();
        error ZeroAddress();
        error StartGreaterThanEnd();
        error TooFarInFuture();
        error RateHigherThanInitialRate();
        error TooSoon();
        error MinterAlreadySet();
        error NonZeroApproval();
        error MintExceedsAvailableSupply();

}