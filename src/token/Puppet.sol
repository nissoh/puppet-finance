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
    uint256 private total_supply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowances;

    // Supply variables
    int128 public mining_epoch;

    uint256 public start_epoch_time;
    uint256 public rate;
    uint256 public start_epoch_supply;

    // General constants
    uint256 private constant YEAR = 86400 * 365;

    // Allocation:
    // =========
    // DAO-controlled reserve - 12%
    // Core - 8%
    // Private sale - 5%
    // Public sale - 5%
    // == 30% ==
    // left for inflation: 70%

    // Supply parameters
    // NOTE: the supply of tokens will start at 3 million, and approximately 1.3 million new tokens will be minted in the first year.
    // Each subsequent year, the number of new tokens minted will decrease by about 14%,
    // leading to a total supply of approximately 10 million tokens after 50 years
    // uint256 public constant TOTAL_SUPPLY = 10_000_000;
    // uint256 private constant INITIAL_SUPPLY = 1_303_030_303;
    uint256 private constant INITIAL_SUPPLY = 3000000;

    // uint256 private constant INITIAL_RATE = 274_815_283 * 10 ** 18 / YEAR; // leading to 43% premine
    uint256 private constant INITIAL_RATE = 1125000 * 10 ** 18 / YEAR;

    uint256 private constant RATE_REDUCTION_TIME = YEAR;
    uint256 private constant RATE_REDUCTION_COEFFICIENT = 1189207115002721024; // 2 ** (1/4) * 1e18

    uint256 private constant RATE_DENOMINATOR = 10 ** 18;
    uint256 private constant INFLATION_DELAY = 86400;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    /// @notice Contract constructor
    /// @param _name Token full name
    /// @param _symbol Token symbol
    /// @param _decimals Number of decimals for token
    constructor(string memory _name, string memory _symbol, uint256 _decimals) {
        uint256 init_supply = INITIAL_SUPPLY * 10 ** _decimals;
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        balanceOf[msg.sender] = init_supply;
        total_supply = init_supply;
        admin = msg.sender;
        emit Transfer(address(0), msg.sender, init_supply);

        start_epoch_time = block.timestamp + INFLATION_DELAY - RATE_REDUCTION_TIME;
        mining_epoch = -1;
        rate = 0;
        start_epoch_supply = init_supply;
    }

    // ============================================================================================
    // External functions
    // ============================================================================================

    // view functions

    /// @notice Current number of tokens in existence (claimed or unclaimed)
    function available_supply() external view returns (uint256) {
        return _available_supply();
    }

    /// @notice How much supply is mintable from start timestamp till end timestamp
    /// @param start Start of the time interval (timestamp)
    /// @param end End of the time interval (timestamp)
    /// @return Tokens mintable from `start` till `end`
    function mintable_in_timeframe(uint256 start, uint256 end) external view returns (uint256) {
        require(start <= end, "start > end");
        uint256 to_mint = 0;
        uint256 current_epoch_time = start_epoch_time;
        uint256 current_rate = rate;

        // Special case if end is in future (not yet minted) epoch
        if (end > current_epoch_time + RATE_REDUCTION_TIME) {
            current_epoch_time += RATE_REDUCTION_TIME;
            current_rate = current_rate * RATE_DENOMINATOR / RATE_REDUCTION_COEFFICIENT;
        }

        require(end <= current_epoch_time + RATE_REDUCTION_TIME, "too far in future");

        for (uint256 i = 0; i < 999; i++) { // Curve will not work in 1000 years. Darn!
            if (end >= current_epoch_time) {
                uint256 current_end = end;
                if (current_end > current_epoch_time + RATE_REDUCTION_TIME) {
                    current_end = current_epoch_time + RATE_REDUCTION_TIME;
                }

                uint256 current_start = start;
                if (current_start >= current_epoch_time + RATE_REDUCTION_TIME) {
                    break; // We should never get here but what if...
                } else if (current_start < current_epoch_time) {
                    current_start = current_epoch_time;
                }

                to_mint += current_rate * (current_end - current_start);

                if (start >= current_epoch_time) {
                    break;
                }
            }

            current_epoch_time -= RATE_REDUCTION_TIME;
            current_rate = current_rate * RATE_REDUCTION_COEFFICIENT / RATE_DENOMINATOR; // double-division with rounding made rate a bit less => good
            require(current_rate <= INITIAL_RATE, "This should never happen");
        }

        return to_mint;
    }

    /// @notice Total number of tokens in existence.
    function totalSupply() external view returns (uint256) {
        return total_supply;
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
    function update_mining_parameters() external {
        require(block.timestamp >= start_epoch_time + RATE_REDUCTION_TIME, "too soon!");
        _update_mining_parameters();
    }

    /// @notice Get timestamp of the current mining epoch start while simultaneously updating mining parameters
    /// @return Timestamp of the epoch
    function start_epoch_time_write() external returns (uint256) {
        uint256 _start_epoch_time = start_epoch_time;
        if (block.timestamp >= _start_epoch_time + RATE_REDUCTION_TIME) {
            _update_mining_parameters();
            return start_epoch_time;
        } else {
            return _start_epoch_time;
        }
    }

    /// @notice Get timestamp of the next mining epoch start while simultaneously updating mining parameters
    /// @return Timestamp of the next epoch
    function future_epoch_time_write() external returns (uint256) {
        uint256 _start_epoch_time = start_epoch_time;
        if (block.timestamp >= _start_epoch_time + RATE_REDUCTION_TIME) {
            _update_mining_parameters();
            return start_epoch_time + RATE_REDUCTION_TIME;
        } else {
            return _start_epoch_time + RATE_REDUCTION_TIME;
        }
    }

    /// @notice Set the minter address
    /// @dev Only callable once, when minter has not yet been set
    /// @param _minter Address of the minter
    function set_minter(address _minter) external {
        require(msg.sender == admin, "admin only");
        require(minter == address(0), "can set the minter only once, at creation");
        minter = _minter;
        emit SetMinter(_minter);
    }

    /// @notice Set the new admin.
    /// @dev After all is set up, admin only can change the token name
    /// @param _admin New admin address
    function set_admin(address _admin) external {
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
        if (block.timestamp >= start_epoch_time + RATE_REDUCTION_TIME) {
            _update_mining_parameters();
        }
        uint256 _total_supply = total_supply + _value;
        require(_total_supply <= _available_supply(), "exceeds allowable mint amount");
        total_supply = _total_supply;
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
        total_supply -= _value;
        emit Transfer(msg.sender, address(0), _value);
        return true;
    }

    /// @notice Change the token name and symbol to `_name` and `_symbol`
    /// @dev Only callable by the admin account
    /// @param _name New token name
    /// @param _symbol New token symbol
    function set_name(string memory _name, string memory _symbol) external {
        require(msg.sender == admin, "only admin is allowed to change name");
        name = _name;
        symbol = _symbol;
    }

    // ============================================================================================
    // Internal functions
    // ============================================================================================

    // view functions

    function _available_supply() internal view returns (uint256) {
        return start_epoch_supply + (block.timestamp - start_epoch_time) * rate;
    }

    // mutated functions

    /// @dev Update mining rate and supply at the start of the epoch. Any modifying mining call must also call this
    function _update_mining_parameters() internal {
        uint256 _rate = rate;
        uint256 _start_epoch_supply = start_epoch_supply;

        start_epoch_time += RATE_REDUCTION_TIME;
        mining_epoch += 1;

        if (_rate == 0) {
            _rate = INITIAL_RATE;
        } else {
            _start_epoch_supply += _rate * RATE_REDUCTION_TIME;
            start_epoch_supply = _start_epoch_supply;
            _rate = _rate * RATE_DENOMINATOR / RATE_REDUCTION_COEFFICIENT;
        }

        rate = _rate;

        emit UpdateMiningParameters(block.timestamp, _rate, _start_epoch_supply);
    }
}