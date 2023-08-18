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
    
        // ============================================================================================
        // External functions
        // ============================================================================================

        // view functions

        /// @notice Current number of tokens in existence (claimed or unclaimed)
        /// @return _availableSupply Total available supply of tokens
        function availableSupply() external view returns (uint256 _availableSupply);

        /// @notice How much supply is mintable from start timestamp till end timestamp
        /// @param start Start of the time interval (timestamp)
        /// @param end End of the time interval (timestamp)
        /// @return _mintable mintable from `start` till `end`
        function mintableInTimeframe(uint256 start, uint256 end) external view returns (uint256 _mintable);

        /// @notice Total number of tokens in existence.
        /// @return _totalSupply Total supply of tokens
        function totalSupply() external view returns (uint256 _totalSupply);

        /// @notice Check the amount of tokens that an owner allowed to a spender
        /// @param _owner The address which owns the funds
        /// @param _spender The address which will spend the funds
        /// @return _allowance uint256 specifying the amount of tokens still available for the spender
        function allowance(address _owner, address _spender) external view returns (uint256 _allowance);

        // mutated functions

        /// @notice Update mining rate and supply at the start of the epoch
        /// @dev Callable by any address, but only once per epoch. Total supply becomes slightly larger if this function is called late
        function updateMiningParameters() external;

        /// @notice Get timestamp of the current mining epoch start while simultaneously updating mining parameters
        /// @return _startEpochTime Timestamp of the epoch
        function startEpochTimeWrite() external returns (uint256 _startEpochTime);

        /// @notice Get timestamp of the next mining epoch start while simultaneously updating mining parameters
        /// @return _futureEpochTime Timestamp of the next epoch
        function futureEpochTimeWrite() external returns (uint256 _futureEpochTime);

        /// @notice Set the minter address
        /// @dev Only callable once, when minter has not yet been set
        /// @param _minter Address of the minter
        function setMinter(address _minter) external;

        /// @notice Set the new admin.
        /// @dev After all is set up, admin only can change the token name
        /// @param _admin New admin address
        function setAdmin(address _admin) external;

        /// @notice Transfer `_value` tokens from `msg.sender` to `_to`
        /// @dev Vyper/Solidity does not allow underflows, so the subtraction in this function will revert on an insufficient balance
        /// @param _to The address to transfer to
        /// @param _value The amount to be transferred
        /// @return _success bool success
        function transfer(address _to, uint256 _value) external returns (bool _success);

        /// @notice Transfer `_value` tokens from `_from` to `_to`
        /// @param _from address The address which you want to send tokens from
        /// @param _to address The address which you want to transfer to
        /// @param _value uint256 the amount of tokens to be transferred
        /// @return _success bool success
        function transferFrom(address _from, address _to, uint256 _value) external returns (bool _success);

        /// @notice Approve `_spender` to transfer `_value` tokens on behalf of `msg.sender`
        /// @dev Approval may only be from zero -> nonzero or from nonzero -> zero in order 
        /// to mitigate the potential race condition described here:
        /// https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
        /// @param _spender The address which will spend the funds
        /// @param _value The amount of tokens to be spent
        /// @return _success bool success
        function approve(address _spender, uint256 _value) external returns (bool _success);

        /// @notice Mint `_value` tokens and assign them to `_to`
        /// @dev Emits a Transfer event originating from 0x00
        /// @param _to The account that will receive the created tokens
        /// @param _value The amount that will be created
        /// @return _success bool success
        function mint(address _to, uint256 _value) external returns (bool _success);

        /// @notice Burn `_value` tokens belonging to `msg.sender`
        /// @dev Emits a Transfer event with a destination of 0x00
        /// @param _value The amount that will be burned
        /// @return _success bool success
        function burn(uint256 _value) external returns (bool _success);
        
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