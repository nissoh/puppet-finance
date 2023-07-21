// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// @title Puppet Finance Token
// @author Curve Finance
// @license MIT
// @notice ERC20 with piecewise-linear mining supply.
// @dev Based on the ERC-20 token standard as defined @ https://eips.ethereum.org/EIPS/eip-20

contract Puppet {

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event UpdateMiningParameters(uint256 time, uint256 rate, uint256 supply);
    event SetMinter(address minter);
    event SetAdmin(address admin);

    string public name;
    string public symbol;

    address public minter;
    address public admin;

    uint256 public decimals;
    uint256 private _totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowances;

    // Supply variables
    int128 public miningEpoch;

    uint256 public rate;
    uint256 public startEpochTime;
    uint256 public startEpochSupply;

    // General constants
    uint256 private constant _YEAR = 86400 * 365;

    // Supply parameters
    // NOTE: the supply of tokens will start at 3 million, and approximately 1,125,000 new tokens will be minted in the first year.
    // Each subsequent year, the number of new tokens minted will decrease by about 18%,
    // leading to a total supply of approximately 10 million tokens after 50 years.
    // Supply is capped at 10 million tokens either way.

    // Allocation:
    // =========
    // DAO controlled reserve - 14%
    // Core - 10%
    // Private sale - 5%
    // GBC airdrop - 1%
    // == 30% ==
    // left for inflation: 70%

    uint256 public constant MAX_SUPPLY = 10000000 * 1e18;

    uint256 private constant _INITIAL_SUPPLY = 3000000;
    uint256 private constant _INITIAL_RATE = 1125000 * 1e18 / _YEAR;
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
    // External functions
    // ============================================================================================

    // view functions

    /// @notice Current number of tokens in existence (claimed or unclaimed)
    function availableSupply() external view returns (uint256) {
        return _availableSupply();
    }

    /// @notice How much supply is mintable from start timestamp till end timestamp
    /// @param start Start of the time interval (timestamp)
    /// @param end End of the time interval (timestamp)
    /// @return Tokens mintable from `start` till `end`
    function mintableInTimeframe(uint256 start, uint256 end) external view returns (uint256) {
        require(start <= end, "start > end");
        uint256 _toMint = 0;
        uint256 _currentEpochTime = startEpochTime;
        uint256 _currentRate = rate;

        // Special case if end is in future (not yet minted) epoch
        if (end > _currentEpochTime + _RATE_REDUCTION_TIME) {
            _currentEpochTime += _RATE_REDUCTION_TIME;
            _currentRate = _currentRate * _RATE_DENOMINATOR / _RATE_REDUCTION_COEFFICIENT;
        }

        require(end <= _currentEpochTime + _RATE_REDUCTION_TIME, "too far in future");

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
            require(_currentRate <= _INITIAL_RATE, "This should never happen");
        }

        return _toMint;
    }

    /// @notice Total number of tokens in existence.
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /// @notice Check the amount of tokens that an owner allowed to a spender
    /// @param _owner The address which owns the funds
    /// @param _spender The address which will spend the funds
    /// @return uint256 specifying the amount of tokens still available for the spender
    function allowance(address _owner, address _spender) external view returns (uint256) {
        return allowances[_owner][_spender];
    }

    // mutated functions

    /// @notice Update mining rate and supply at the start of the epoch
    /// @dev Callable by any address, but only once per epoch. Total supply becomes slightly larger if this function is called late
    function updateMiningParameters() external {
        require(block.timestamp >= startEpochTime + _RATE_REDUCTION_TIME, "too soon!");
        _updateMiningParameters();
    }

    /// @notice Get timestamp of the current mining epoch start while simultaneously updating mining parameters
    /// @return Timestamp of the epoch
    function startEpochTimeWrite() external returns (uint256) {
        uint256 _startEpochTime = startEpochTime;
        if (block.timestamp >= _startEpochTime + _RATE_REDUCTION_TIME) {
            _updateMiningParameters();
            return startEpochTime;
        } else {
            return _startEpochTime;
        }
    }

    /// @notice Get timestamp of the next mining epoch start while simultaneously updating mining parameters
    /// @return Timestamp of the next epoch
    function futureEpochTimeWrite() external returns (uint256) {
        uint256 _startEpochTime = startEpochTime;
        if (block.timestamp >= _startEpochTime + _RATE_REDUCTION_TIME) {
            _updateMiningParameters();
            return startEpochTime + _RATE_REDUCTION_TIME;
        } else {
            return _startEpochTime + _RATE_REDUCTION_TIME;
        }
    }

    /// @notice Set the minter address
    /// @dev Only callable once, when minter has not yet been set
    /// @param _minter Address of the minter
    function setMinter(address _minter) external {
        require(msg.sender == admin, "admin only");
        require(minter == address(0), "can set the minter only once, at creation");
        minter = _minter;
        emit SetMinter(_minter);
    }

    /// @notice Set the new admin.
    /// @dev After all is set up, admin only can change the token name
    /// @param _admin New admin address
    function setAdmin(address _admin) external {
        require(msg.sender == admin, "admin only");
        admin = _admin;
        emit SetAdmin(_admin);
    }

    /// @notice Transfer `_value` tokens from `msg.sender` to `_to`
    /// @dev Vyper/Solidity does not allow underflows, so the subtraction in this function will revert on an insufficient balance
    /// @param _to The address to transfer to
    /// @param _value The amount to be transferred
    /// @return bool success
    function transfer(address _to, uint256 _value) external returns (bool) {
        require(_to != address(0), "transfers to 0x0 are not allowed");
        balanceOf[msg.sender] = balanceOf[msg.sender] - _value;
        balanceOf[_to] = balanceOf[_to] + _value;
        emit Transfer(msg.sender, _to, _value);
        return true;
    }

    /// @notice Transfer `_value` tokens from `_from` to `_to`
    /// @param _from address The address which you want to send tokens from
    /// @param _to address The address which you want to transfer to
    /// @param _value uint256 the amount of tokens to be transferred
    /// @return bool success
    function transferFrom(address _from, address _to, uint256 _value) external returns (bool) {
        require(_to != address(0), "transfers to 0x0 are not allowed");
        // NOTE: Vyper/Solidity does not allow underflows so the following subtraction would revert on insufficient balance
        balanceOf[_from] -= _value;
        balanceOf[_to] += _value;
        allowances[_from][msg.sender] -= _value;
        emit Transfer(_from, _to, _value);
        return true;
    }

    /// @notice Approve `_spender` to transfer `_value` tokens on behalf of `msg.sender`
    /// @dev Approval may only be from zero -> nonzero or from nonzero -> zero in order 
    /// to mitigate the potential race condition described here:
    /// https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
    /// @param _spender The address which will spend the funds
    /// @param _value The amount of tokens to be spent
    /// @return bool success
    function approve(address _spender, uint256 _value) external returns (bool) {
        require(_value == 0 || allowances[msg.sender][_spender] == 0, "approval may only be from zero -> nonzero or from nonzero -> zero");
        allowances[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    /// @notice Mint `_value` tokens and assign them to `_to`
    /// @dev Emits a Transfer event originating from 0x00
    /// @param _to The account that will receive the created tokens
    /// @param _value The amount that will be created
    /// @return bool success
    function mint(address _to, uint256 _value) external returns (bool) {
        require(msg.sender == minter, "minter only");
        require(_to != address(0), "zero address");
        if (block.timestamp >= startEpochTime + _RATE_REDUCTION_TIME) {
            _updateMiningParameters();
        }
        uint256 _newTotalSupply = _totalSupply + _value;
        require(_newTotalSupply <= _availableSupply(), "exceeds allowable mint amount");
        require(_newTotalSupply <= MAX_SUPPLY, "exceeds max supply");
        _totalSupply = _newTotalSupply;
        balanceOf[_to] += _value;
        emit Transfer(address(0), _to, _value);
        return true;
    }

    /// @notice Burn `_value` tokens belonging to `msg.sender`
    /// @dev Emits a Transfer event with a destination of 0x00
    /// @param _value The amount that will be burned
    /// @return bool success
    function burn(uint256 _value) external returns (bool) {
        balanceOf[msg.sender] -= _value;
        _totalSupply -= _value;
        emit Transfer(msg.sender, address(0), _value);
        return true;
    }

    /// @notice Change the token name and symbol to `_name` and `_symbol`
    /// @dev Only callable by the admin account
    /// @param _name New token name
    /// @param _symbol New token symbol
    function setName(string memory _name, string memory _symbol) external {
        require(msg.sender == admin, "only admin is allowed to change name");
        name = _name;
        symbol = _symbol;
    }

    // ============================================================================================
    // Internal functions
    // ============================================================================================

    // view functions

    function _availableSupply() internal view returns (uint256) {
        return startEpochSupply + (block.timestamp - startEpochTime) * rate;
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