// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// =========================== Puppet ===========================
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

import {IPuppet} from "src/interfaces/IPuppet.sol";

contract Puppet is IPuppet {

    // ERC20 variables

    string public name;
    string public symbol;

    address public minter;
    address public admin;

    uint256 public decimals;

    uint256 private _totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowances;

    // supply variables

    int128 public miningEpoch;

    uint256 public rate;
    uint256 public startEpochTime;
    uint256 public startEpochSupply;

    // supply constants

    // NOTE: the supply of tokens will start at 3 million, and approximately 1,115,000 new tokens will be minted in the first year.
    // Each subsequent year, the number of new tokens minted will decrease by about 16%,
    // leading to a total supply of approximately 10 million tokens after about 40 years.
    // Supply is hard-capped at 10 million tokens either way.

    // Allocation:
    // =========
    // DAO controlled reserve - 14%
    // Core - 10%
    // Private sale - 5%
    // GBC airdrop - 1%
    // == 30% ==
    // left for inflation: 70%

    uint256 public constant MAX_SUPPLY = 10_000_000 * 1e18;

    uint256 private constant _YEAR = 86400 * 365;
    uint256 private constant _INITIAL_SUPPLY = 3_000_000;
    uint256 private constant _INITIAL_RATE = 1_115_000 * 1e18 / _YEAR;
    uint256 private constant _RATE_REDUCTION_TIME = _YEAR;
    uint256 private constant _RATE_REDUCTION_COEFFICIENT = 1189207115002721024; // 2 ** (1/4) * 1e18
    uint256 private constant _RATE_DENOMINATOR = 1e18;
    uint256 private constant _INFLATION_DELAY = 86400;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    /// @notice Contract constructor
    /// @param _name Token full name
    /// @param _symbol Token symbol
    /// @param _decimals Number of decimals for token
    constructor(string memory _name, string memory _symbol, uint256 _decimals) {
        uint256 _initSupply = _INITIAL_SUPPLY * 10 ** _decimals;
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        balanceOf[msg.sender] = _initSupply;
        _totalSupply = _initSupply;
        admin = msg.sender;
        emit Transfer(address(0), msg.sender, _initSupply);

        startEpochTime = block.timestamp + _INFLATION_DELAY - _RATE_REDUCTION_TIME;
        miningEpoch = -1;
        rate = 0;
        startEpochSupply = _initSupply;
    }

    // ============================================================================================
    // Modifiers
    // ============================================================================================

    /// @notice Ensures the caller is the contract's Admin
    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    /// @notice Ensures the caller is the contract's Minter
    modifier onlyMinter() {
        if (msg.sender != minter) revert NotMinter();
        _;
    }

    // ============================================================================================
    // External functions
    // ============================================================================================

    // view functions

    /// @inheritdoc IPuppet
    function availableSupply() external view returns (uint256) {
        return _availableSupply();
    }

    /// @inheritdoc IPuppet
    function mintableInTimeframe(uint256 start, uint256 end) external view returns (uint256) {
        if (start > end) revert StartGreaterThanEnd();

        uint256 _toMint = 0;
        uint256 _currentEpochTime = startEpochTime;
        uint256 _currentRate = rate;

        // Special case if end is in future (not yet minted) epoch
        if (end > _currentEpochTime + _RATE_REDUCTION_TIME) {
            _currentEpochTime += _RATE_REDUCTION_TIME;
            _currentRate = _currentRate * _RATE_DENOMINATOR / _RATE_REDUCTION_COEFFICIENT;
        }

        if (end > _currentEpochTime + _RATE_REDUCTION_TIME) revert TooFarInFuture();

        for (uint256 i = 0; i < 999; i++) { // Curve will not work in 1000 years. Darn!
            if (end >= _currentEpochTime) {
                uint256 _currentEnd = end;
                if (_currentEnd > _currentEpochTime + _RATE_REDUCTION_TIME) {
                    _currentEnd = _currentEpochTime + _RATE_REDUCTION_TIME;
                }

                uint256 _currentStart = start;
                if (_currentStart >= _currentEpochTime + _RATE_REDUCTION_TIME) {
                    break; // We should never get here but what if...
                } else if (_currentStart < _currentEpochTime) {
                    _currentStart = _currentEpochTime;
                }

                _toMint += _currentRate * (_currentEnd - _currentStart);

                if (start >= _currentEpochTime) {
                    break;
                }
            }

            _currentEpochTime -= _RATE_REDUCTION_TIME;
            _currentRate = _currentRate * _RATE_REDUCTION_COEFFICIENT / _RATE_DENOMINATOR; // double-division with rounding made rate a bit less => good
            if (_currentRate > _INITIAL_RATE) revert RateHigherThanInitialRate();
        }

        if (_toMint > MAX_SUPPLY - _totalSupply) {
            _toMint = MAX_SUPPLY - _totalSupply;
        }

        return _toMint;
    }

    /// @inheritdoc IPuppet
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /// @inheritdoc IPuppet
    function allowance(address _owner, address _spender) external view returns (uint256) {
        return allowances[_owner][_spender];
    }

    // mutated functions

    /// @inheritdoc IPuppet
    function updateMiningParameters() external {
        if (block.timestamp < startEpochTime + _RATE_REDUCTION_TIME) revert TooSoon();

        _updateMiningParameters();
    }

    /// @inheritdoc IPuppet
    function startEpochTimeWrite() external returns (uint256) {
        uint256 _startEpochTime = startEpochTime;
        if (block.timestamp >= _startEpochTime + _RATE_REDUCTION_TIME) {
            _updateMiningParameters();
            return startEpochTime;
        } else {
            return _startEpochTime;
        }
    }

    /// @inheritdoc IPuppet
    function futureEpochTimeWrite() external returns (uint256) {
        uint256 _startEpochTime = startEpochTime;
        if (block.timestamp >= _startEpochTime + _RATE_REDUCTION_TIME) {
            _updateMiningParameters();
            return startEpochTime + _RATE_REDUCTION_TIME;
        } else {
            return _startEpochTime + _RATE_REDUCTION_TIME;
        }
    }

    /// @inheritdoc IPuppet
    function setMinter(address _minter) external onlyAdmin {
        if (minter != address(0)) revert MinterAlreadySet();

        minter = _minter;

        emit SetMinter(_minter);
    }

    /// @inheritdoc IPuppet
    function setAdmin(address _admin) external onlyAdmin {
        admin = _admin;

        emit SetAdmin(_admin);
    }

    /// @inheritdoc IPuppet
    function transfer(address _to, uint256 _value) external returns (bool) {
        if (_to == address(0)) revert ZeroAddress();

        balanceOf[msg.sender] = balanceOf[msg.sender] - _value;
        balanceOf[_to] = balanceOf[_to] + _value;

        emit Transfer(msg.sender, _to, _value);

        return true;
    }

    /// @inheritdoc IPuppet
    function transferFrom(address _from, address _to, uint256 _value) external returns (bool) {
        if (_to == address(0)) revert ZeroAddress();

        // NOTE: Vyper/Solidity does not allow underflows so the following subtraction would revert on insufficient balance
        balanceOf[_from] -= _value;
        balanceOf[_to] += _value;
        allowances[_from][msg.sender] -= _value;

        emit Transfer(_from, _to, _value);

        return true;
    }

    /// @inheritdoc IPuppet
    function approve(address _spender, uint256 _value) external returns (bool) {
        if (_value != 0 && allowances[msg.sender][_spender] != 0) revert NonZeroApproval();

        allowances[msg.sender][_spender] = _value;

        emit Approval(msg.sender, _spender, _value);

        return true;
    }

    /// @inheritdoc IPuppet
    function mint(address _to, uint256 _value) external onlyMinter returns (bool) {
        if (_to == address(0)) revert ZeroAddress();

        if (block.timestamp >= startEpochTime + _RATE_REDUCTION_TIME) {
            _updateMiningParameters();
        }

        uint256 _newTotalSupply = _totalSupply + _value;
        if (_newTotalSupply > _availableSupply()) revert MintExceedsAvailableSupply();

        _totalSupply = _newTotalSupply;
        balanceOf[_to] += _value;

        emit Transfer(address(0), _to, _value);

        return true;
    }

    /// @inheritdoc IPuppet
    function burn(uint256 _value) external returns (bool) {
        balanceOf[msg.sender] -= _value;
        _totalSupply -= _value;

        emit Transfer(msg.sender, address(0), _value);

        return true;
    }

    // ============================================================================================
    // Internal functions
    // ============================================================================================

    // view functions

    function _availableSupply() internal view returns (uint256) { 
        return _min(startEpochSupply + (block.timestamp - startEpochTime) * rate, MAX_SUPPLY);
    }

    function _min(uint256 _a, uint256 _b) internal pure returns (uint256) {
        return _a < _b ? _a : _b;
    }

    // mutated functions

    /// @dev Update mining rate and supply at the start of the epoch. Any modifying mining call must also call this
    function _updateMiningParameters() internal {
        uint256 _rate = rate;
        uint256 _startEpochSupply = startEpochSupply;

        startEpochTime += _RATE_REDUCTION_TIME;
        miningEpoch += 1;

        if (_rate == 0) {
            _rate = _INITIAL_RATE;
        } else {
            _startEpochSupply += _rate * _RATE_REDUCTION_TIME;
            startEpochSupply = _startEpochSupply;
            _rate = _rate * _RATE_DENOMINATOR / _RATE_REDUCTION_COEFFICIENT;
        }

        rate = _rate;

        emit UpdateMiningParameters(block.timestamp, _rate, _startEpochSupply);
    }
}