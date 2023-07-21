// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// @title Voting Escrow
// @author Curve Finance
// @license MIT
// @notice Votes have a weight depending on time, so that users are committed to the future of (whatever they are voting for)
// @dev Vote weight decays linearly over time. Lock time cannot be more than `MAXTIME` (4 years).

// Voting escrow to have time-weighted votes
// Votes have a weight depending on time, so that users are committed
// to the future of (whatever they are voting for).
// The weight in this implementation is linear, and lock cannot be more than maxtime:
// w ^
// 1 +        /
//   |      /
//   |    /
//   |  /
//   |/
// 0 +--------+------> time
//       maxtime (4 years?)
// todo - add (1) auto-max-relock, (2) global emergency unlock (unlocked)
contract vePuppet is ReentrancyGuard {

    using SafeERC20 for IERC20;

    struct Point {
        int128 bias;
        int128 slope; // - dweight / dt
        uint256 ts;
        uint256 blk; // block
    }
    // We cannot really do block numbers per se b/c slope is per time, not per block
    // and per block could be fairly bad b/c Ethereum changes blocktimes.
    // What we can do is to extrapolate ***At functions

    struct LockedBalance {
        int128 amount;
        uint256 end;
    }

    // Interface for checking whether address belongs to a whitelisted type of a smart wallet.
    // When new types are added - the whole contract is changed
    // The check() method is modifying to be able to use caching for individual wallet addresses
    // interface SmartWalletChecker:
    //     def check(addr: address) -> bool: nonpayable
    // todo

    // event CommitOwnership:
    //     admin: address
    event CommitOwnership(address admin);

    // event ApplyOwnership:
    //     admin: address
    event ApplyOwnership(address admin);

    // event Deposit:
    //     provider: indexed(address)
    //     value: uint256
    //     locktime: indexed(uint256)
    //     type: int128
    //     ts: uint256
    event Deposit(address provider, uint256 value, uint256 locktime, int128 type_, uint256 ts);

    // event Withdraw:
    //     provider: indexed(address)
    //     value: uint256
    //     ts: uint256
    event Withdraw(address provider, uint256 value, uint256 ts);

    // event Supply:
    //     prevSupply: uint256
    //     supply: uint256
    event Supply(uint256 prevSupply, uint256 supply);

    // DEPOSIT_FOR_TYPE: constant(int128) = 0
    int128 constant DEPOSIT_FOR_TYPE = 0;
    // CREATE_LOCK_TYPE: constant(int128) = 1
    int128 constant CREATE_LOCK_TYPE = 1;
    // INCREASE_LOCK_AMOUNT: constant(int128) = 2
    int128 constant INCREASE_LOCK_AMOUNT = 2;
    // INCREASE_UNLOCK_TIME: constant(int128) = 3
    int128 constant INCREASE_UNLOCK_TIME = 3;

    // WEEK: constant(uint256) = 7 * 86400  # all future times are rounded by week
    uint256 constant WEEK = 7 * 86400; // all future times are rounded by week
    // MAXTIME: constant(uint256) = 4 * 365 * 86400  # 4 years
    uint256 constant MAXTIME = 4 * 365 * 86400; // 4 years
    // MULTIPLIER: constant(uint256) = 10 ** 18
    uint256 constant MULTIPLIER = 10 ** 18;

    // token: public(address)
    address public token;
    // supply: public(uint256)
    uint256 public supply;

    // locked: public(HashMap[address, LockedBalance])
    mapping(address => LockedBalance) public locked;

    // epoch: public(uint256)
    uint256 public epoch;
    // point_history: public(Point[100000000000000000000000000000])  # epoch -> unsigned point
    mapping(uint256 => Point) public point_history; // epoch -> unsigned point
    // user_point_history: public(HashMap[address, Point[1000000000]])  # user -> Point[user_epoch]
    mapping(address => Point[1000000000]) public user_point_history; // user -> Point[user_epoch]
    // user_point_epoch: public(HashMap[address, uint256])
    mapping(address => uint256) public user_point_epoch;
    // slope_changes: public(HashMap[uint256, int128])  # time -> signed slope change
    mapping(uint256 => int128) public slope_changes; // time -> signed slope change

    // Whitelisted (smart contract) wallets which are allowed to deposit
    // The goal is to prevent tokenizing the escrow
    mapping(address => bool) public contracts_whitelist;

    // Aragon's view methods for compatibility
    // controller: public(address)
    address public controller;
    // transfersEnabled: public(bool)
    bool public transfersEnabled;

    // name: public(String[64])
    string public name;
    // symbol: public(String[32])
    string public symbol;
    // version: public(String[32])
    string public version;
    // decimals: public(uint256)
    uint256 public decimals;

    // Checker for whitelisted (smart contract) wallets which are allowed to deposit
    // The goal is to prevent tokenizing the escrow
    // future_smart_wallet_checker: public(address)
    address public future_smart_wallet_checker;
    // smart_wallet_checker: public(address)
    address public smart_wallet_checker;
    // todo

    // admin: public(address)  # Can and will be a smart contract
    address public admin; // Can and will be a smart contract
    // future_admin: public(address)
    address public future_admin;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    /// @notice Contract constructor
    /// @param _token `ERC20CRV` token address
    /// @param _name Token name
    /// @param _symbol Token symbol
    /// @param _version Contract version - required for Aragon compatibility
    constructor(address _token, string memory _name, string memory _symbol, string memory _version) {
        admin = msg.sender;
        token = _token;
        point_history[0].blk = block.number;
        point_history[0].ts = block.timestamp;
        controller = msg.sender;
        transfersEnabled = true;

        uint256 _decimals = IERC20(_token).decimals();
        require(_decimals <= 255, "decimals <= 255");
        decimals = _decimals;

        name = _name;
        symbol = _symbol;
        version = _version;
    }

    // ============================================================================================
    // Modifier
    // ============================================================================================

    modifier onlyUserOrWhitelist() {
        if (msg.sender != tx.origin) {
        require(contracts_whitelist[msg.sender], "Smart contract not allowed");
        }
        _;
    }

    // ============================================================================================
    // External functions
    // ============================================================================================

    // view functions

    /// @notice Get the most recently recorded rate of voting power decrease for `addr`
    /// @param _addr Address of the user wallet
    /// @return Value of the slope
    function get_last_user_slope(address _addr) external view returns (int128) {
        uint256 _uepoch = user_point_epoch[_addr];
        return user_point_history[_addr][_uepoch].slope;
    }

    /// @notice Get the timestamp for checkpoint `_idx` for `_addr`
    /// @param _addr User wallet address
    /// @param _idx User epoch number
    /// @return Epoch time of the checkpoint
    function user_point_history__ts(address _addr, uint256 _idx) external view returns (uint256) {
        return user_point_history[_addr][_idx].ts;
    }

    /// @notice Get timestamp when `_addr`'s lock finishes
    /// @param _addr User wallet
    /// @return Epoch time of the lock end
    function locked__end(address _addr) external view returns (uint256) {
        return locked[_addr].end;
    }

    // NOTE: The following ERC20/minime-compatible methods are not real balanceOf and supply!
    // They measure the weights for the purpose of voting, so they don't represent real coins.

    /// @notice Get the current voting power for `msg.sender`
    /// @dev Adheres to the ERC20 `balanceOf` interface for Aragon compatibility
    /// @param addr User wallet address
    /// @param _t Epoch time to return voting power at
    /// @return User voting power
    function balanceOf(address _addr) external view returns (uint256) {
        uint256 _epoch = user_point_epoch[_addr];
        if (_epoch == 0) {
            return 0;
        } else {
            Point memory last_point = user_point_history[_addr][_epoch];
            last_point.bias -= last_point.slope * int128(block.timestamp - last_point.ts); // todo use safeCast
            if (last_point.bias < 0) {
                last_point.bias = 0;
            }
            return uint256(last_point.bias); // todo use safeCast
        }
    }

    // @external
    // @view
    // def balanceOfAt(addr: address, _block: uint256) -> uint256:
    //     """
    //     @notice Measure voting power of `addr` at block height `_block`
    //     @dev Adheres to MiniMe `balanceOfAt` interface: https://github.com/Giveth/minime
    //     @param addr User's wallet address
    //     @param _block Block to calculate the voting power at
    //     @return Voting power
    //     """
    //     # Copying and pasting totalSupply code because Vyper cannot pass by
    //     # reference yet
    //     assert _block <= block.number

    //     # Binary search
    //     _min: uint256 = 0
    //     _max: uint256 = self.user_point_epoch[addr]
    //     for i in range(128):  # Will be always enough for 128-bit numbers
    //         if _min >= _max:
    //             break
    //         _mid: uint256 = (_min + _max + 1) / 2
    //         if self.user_point_history[addr][_mid].blk <= _block:
    //             _min = _mid
    //         else:
    //             _max = _mid - 1

    //     upoint: Point = self.user_point_history[addr][_min]

    //     max_epoch: uint256 = self.epoch
    //     _epoch: uint256 = self.find_block_epoch(_block, max_epoch)
    //     point_0: Point = self.point_history[_epoch]
    //     d_block: uint256 = 0
    //     d_t: uint256 = 0
    //     if _epoch < max_epoch:
    //         point_1: Point = self.point_history[_epoch + 1]
    //         d_block = point_1.blk - point_0.blk
    //         d_t = point_1.ts - point_0.ts
    //     else:
    //         d_block = block.number - point_0.blk
    //         d_t = block.timestamp - point_0.ts
    //     block_time: uint256 = point_0.ts
    //     if d_block != 0:
    //         block_time += d_t * (_block - point_0.blk) / d_block

    //     upoint.bias -= upoint.slope * convert(block_time - upoint.ts, int128)
    //     if upoint.bias >= 0:
    //         return convert(upoint.bias, uint256)
    //     else:
    //         return 0
    /// @notice Measure voting power of `addr` at block height `_block`
    /// @dev Adheres to MiniMe `balanceOfAt` interface: https://github.com/Giveth/minime
    /// @param addr User's wallet address
    /// @param _block Block to calculate the voting power at
    /// @return Voting power
    function balanceOfAt(address addr, uint256 _block) external view returns (uint256) {
        // Copying and pasting totalSupply code because Vyper cannot pass by
        // reference yet
        require(_block <= block.number);

        // Binary search
        uint256 _min = 0;
        uint256 _max = user_point_epoch[addr];
        for (uint256 i = 0; i < 128; ++i) { // Will be always enough for 128-bit numbers
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 1) / 2;
            if (user_point_history[addr][_mid].blk <= _block) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }

        Point memory upoint = user_point_history[addr][_min];

        uint256 max_epoch = epoch;
        uint256 _epoch = find_block_epoch(_block, max_epoch);
        Point memory point_0 = point_history[_epoch];
        uint256 d_block = 0;
        uint256 d_t = 0;
        if (_epoch < max_epoch) {
            Point memory point_1 = point_history[_epoch + 1];
            d_block = point_1.blk - point_0.blk;
            d_t = point_1.ts - point_0.ts;
        } else {
            d_block = block.number - point_0.blk;
            d_t = block.timestamp - point_0.ts;
        }
        uint256 block_time = point_0.ts;
        if (d_block != 0) {
            block_time += (d_t * (_block - point_0.blk)) / d_block;
        }

        upoint.bias -= upoint.slope * int128(int256(block_time - upoint.ts)); // todo use safeCast
        if (upoint.bias >= 0) {
            return uint256(uint128(upoint.bias)); // todo use safeCast
        } else {
            return 0;
        }
    }

    /// @notice Calculate total voting power at some point in the past
    /// @param point The point (bias/slope) to start search from
    /// @param t Time to calculate the total voting power at
    /// @return Total voting power at that time
    function supply_at(Point memory point, uint256 t) internal view returns (uint256) {
        Point memory last_point = point;
        uint256 t_i = (last_point.ts / WEEK) * WEEK;
        for (uint256 i = 0; i < 255; ++i) {
            t_i += WEEK;
            int128 d_slope = 0;
            if (t_i > t) {
                t_i = t;
            } else {
                d_slope = slope_changes[t_i];
            }
            last_point.bias -= last_point.slope * int128(t_i - last_point.ts); // todo use safeCast
            if (t_i == t) {
                break;
            }
            last_point.slope += d_slope;
            last_point.ts = t_i;
        }

        if (last_point.bias >= 0) {
            return uint256(last_point.bias); // todo use safeCast
        } else {
            return 0;
        }
    }

    /// @notice Calculate total voting power
    /// @dev Adheres to the ERC20 `totalSupply` interface for Aragon compatibility
    /// @return Total voting power
    function totalSupply() external view returns (uint256) {
        uint256 _epoch = epoch;
        Point memory last_point = point_history[_epoch];
        return supply_at(last_point, block.timestamp);
    }

    function totalSupplyAt(uint256 _block) external view returns (uint256) {
        require(_block <= block.number);

        uint256 _epoch = epoch;
        uint256 target_epoch = find_block_epoch(_block, _epoch);

        Point memory point = point_history[target_epoch];
        uint256 dt = 0;
        if (target_epoch < _epoch) {
            Point memory point_next = point_history[target_epoch + 1];
            if (point.blk != point_next.blk) {
                dt = (_block - point.blk) * (point_next.ts - point.ts) / (point_next.blk - point.blk);
            }
        } else {
            if (point.blk != block.number) {
                dt = (_block - point.blk) * (block.timestamp - point.ts) / (block.number - point.blk);
            }
        }
        // Now dt contains info on how far are we beyond point

        return supply_at(point, point.ts + dt);
    }

    // mutated functions

    /// @notice Record global data to checkpoint
    function checkpoint() external {
        _checkpoint(address(0), LockedBalance(0, 0), LockedBalance(0, 0));
    }

    /// @notice Deposit `_value` tokens for `_addr` and add to the lock
    /// @dev Anyone (even a smart contract) can deposit for someone else, but 
    /// cannot extend their locktime and deposit for a brand new user
    /// @param _addr User's wallet address
    /// @param _value Amount to add to user's lock
    function deposit_for(address _addr, uint256 _value) external nonReentrant {
        LockedBalance memory _locked = locked[_addr];

        require(_value > 0, "need non-zero value");
        require(_locked.amount > 0, "No existing lock found");
        require(_locked.end > block.timestamp, "Cannot add to expired lock. Withdraw");

        _deposit_for(_addr, _value, 0, locked[_addr], DEPOSIT_FOR_TYPE);
    }

    /// @notice Deposit `_value` tokens for `msg.sender` and lock until `_unlock_time`
    /// @param _value Amount to deposit
    /// @param _unlock_time Epoch time when tokens unlock, rounded down to whole weeks
    function create_lock(uint256 _value, uint256 _unlock_time) external onlyUserOrWhitelist nonReentrant {
        require(_value > 0, "need non-zero value");
        require(locked[msg.sender].amount == 0, "Withdraw old tokens first");

        uint256 unlock_time = (_unlock_time / WEEK) * WEEK; // Locktime is rounded down to weeks
        require(unlock_time > block.timestamp, "Can only lock until time in the future");
        require(unlock_time <= block.timestamp + MAXTIME, "Voting lock can be 4 years max");

        _deposit_for(msg.sender, _value, unlock_time, locked[msg.sender], CREATE_LOCK_TYPE);
    }

    /// @notice Deposit `_value` additional tokens for `msg.sender` without modifying the unlock time
    /// @param _value Amount of tokens to deposit and add to the lock
    function increase_amount(uint256 _value) external onlyUserOrWhitelist nonReentrant {
        LockedBalance memory _locked = locked[msg.sender];

        require(_value > 0, "need non-zero value");
        require(_locked.amount > 0, "No existing lock found");
        require(_locked.end > block.timestamp, "Cannot add to expired lock. Withdraw");

        _deposit_for(msg.sender, _value, 0, locked[msg.sender], INCREASE_LOCK_AMOUNT);
    }

    /// @notice Extend the unlock time for `msg.sender` to `_unlock_time`
    /// @param _unlock_time New epoch time for unlocking
    function increase_unlock_time(uint256 _unlock_time) external onlyUserOrWhitelist nonReentrant {
        LockedBalance memory _locked = locked[msg.sender];

        require(_locked.amount > 0, "No existing lock found");
        require(_locked.end > block.timestamp, "Cannot add to expired lock. Withdraw");

        uint256 unlock_time = (_unlock_time / WEEK) * WEEK; // Locktime is rounded down to weeks
        require(unlock_time > _locked.end, "Can only increase lock duration");
        require(unlock_time <= block.timestamp + MAXTIME, "Voting lock can be 4 years max");

        _deposit_for(msg.sender, 0, unlock_time, locked[msg.sender], INCREASE_UNLOCK_TIME);
    }

    /// @notice Withdraw all tokens for `msg.sender`
    /// @dev Only possible if the lock has expired
    function withdraw() external nonReentrant {
        LockedBalance memory _locked = locked[msg.sender];

        require(_locked.amount > 0, "No existing lock found");
        require(_locked.end <= block.timestamp, "The lock didn't expire");

        uint256 value = uint256(_locked.amount); // todo use safeCast

        LockedBalance memory old_locked = _locked;
        _locked.end = 0;
        _locked.amount = 0;
        locked[msg.sender] = _locked;
        uint256 supply_before = supply;
        supply = supply_before - value;

        _checkpoint(msg.sender, old_locked, _locked);

        IERC20(token).safeTransfer(msg.sender, value);

        emit Withdraw(msg.sender, value, block.timestamp);
        emit Supply(supply_before, supply_before - value);
    }

    /// @notice Transfer ownership of VotingEscrow contract to `addr`
    /// @param addr Address to have ownership transferred to
    function commit_transfer_ownership(address addr) external {
        require(msg.sender == admin, "dev: admin only");
        future_admin = addr;
        emit CommitOwnership(addr);
    }

    /// @notice Apply ownership transfer
    function apply_transfer_ownership() external {
        require(msg.sender == admin, "dev: admin only");
        address _admin = future_admin;
        require(_admin != address(0), "dev: admin not set");
        admin = _admin;
        emit ApplyOwnership(_admin);
    }

    /// @notice Add address to whitelist smart contract depositors `addr`
    /// @param addr Address to be whitelisted
    function add_to_whitelist(address addr) external {
        require(msg.sender == admin, "dev: admin only");
        contracts_whitelist[addr] = true;
    }

    /// @notice Remove a smart contract address from whitelist
    /// @param addr Address to be removed from whitelist
    function remove_from_whitelist(address addr) external {
        require(msg.sender == admin, "dev: admin only");
        contracts_whitelist[addr] = false;
    }

    // # Dummy methods for compatibility with Aragon

    // @external
    // def changeController(_newController: address):
    //     """
    //     @dev Dummy method required for Aragon compatibility
    //     """
    //     assert msg.sender == self.controller
    //     self.controller = _newController

    // ============================================================================================
    // Internal functions
    // ============================================================================================

    // view functions

    /// @notice Binary search to estimate timestamp for block number
    /// @param _block Block to find
    /// @param max_epoch Don't go beyond this epoch
    /// @return Approximate timestamp for block
    function find_block_epoch(uint256 _block, uint256 max_epoch) internal view returns (uint256) {
        // Binary search
        uint256 _min = 0;
        uint256 _max = max_epoch;
        for (uint256 i = 0; i < 128; i++) { // Will always be enough for 128-bit numbers
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 1) / 2;
            if (point_history[_mid].blk <= _block) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }
        return _min;
    }

    // mutated functions

    /// @notice Record global and per-user data to checkpoint
    /// @param _addr User's wallet address. No user checkpoint if 0x0
    /// @param old_locked Pevious locked amount / end lock time for the user
    /// @param new_locked New locked amount / end lock time for the user
    function _checkpoint(address _addr, LockedBalance memory old_locked, LockedBalance memory new_locked) internal {
        Point memory u_old;
        Point memory u_new;
        int128 old_dslope = 0;
        int128 new_dslope = 0;
        uint256 _epoch = epoch;

        if (_addr != address(0x0)) {
            // Calculate slopes and biases
            // Kept at zero when they have to
            if (old_locked.end > block.timestamp && old_locked.amount > 0) {
                u_old.slope = old_locked.amount / MAXTIME;
                u_old.bias = u_old.slope * int128(int256(old_locked.end - block.timestamp)); // todo use safeCast
            }
            if (new_locked.end > block.timestamp && new_locked.amount > 0) {
                u_new.slope = new_locked.amount / MAXTIME;
                u_new.bias = u_new.slope * int128(int256(new_locked.end - block.timestamp)); // todo use safeCast
            }

            // Read values of scheduled changes in the slope
            // old_locked.end can be in the past and in the future
            // new_locked.end can ONLY by in the FUTURE unless everything expired: than zeros
            old_dslope = slope_changes[old_locked.end];
            if (new_locked.end != 0) {
                if (new_locked.end == old_locked.end) {
                    new_dslope = old_dslope;
                } else {
                    new_dslope = slope_changes[new_locked.end];
                }
            }
        }

        Point memory last_point = Point({bias: 0, slope: 0, ts: block.timestamp, blk: block.number});
        if (_epoch > 0) {
            last_point = point_history[_epoch];
        }
        uint256 last_checkpoint = last_point.ts;
        // initial_last_point is used for extrapolation to calculate block number
        // (approximately, for *At methods) and save them
        // as we cannot figure that out exactly from inside the contract

        uint256 initial_last_point_ts = last_point.ts;
        uint256 initial_last_point_blk = last_point.blk;

        uint256 block_slope = 0; // dblock/dt
        if (block.timestamp > last_point.ts) {
            block_slope = (MULTIPLIER * (block.number - last_point.blk)) / (block.timestamp - last_point.ts);
        }
        // If last point is already recorded in this block, slope=0
        // But that's ok b/c we know the block in such case

        // Go over weeks to fill history and calculate what the current point is
        uint256 t_i = (last_checkpoint / WEEK) * WEEK;
        for (uint256 i = 0; i < 255; ++i) {
            // Hopefully it won't happen that this won't get used in 5 years!
            // If it does, users will be able to withdraw but vote weight will be broken
            t_i += WEEK;
            int128 d_slope = 0;
            if (t_i > block.timestamp) {
                t_i = block.timestamp;
            } else {
                d_slope = slope_changes[t_i];
            }
            last_point.bias -= last_point.slope * int128(int256(t_i - last_checkpoint)); // todo use safeCast
            last_point.slope += d_slope;
            if (last_point.bias < 0) {
                // This can happen
                last_point.bias = 0;
            }
            if (last_point.slope < 0) {
                // This cannot happen - just in case
                last_point.slope = 0;
            }
            last_checkpoint = t_i;
            last_point.ts = t_i;
            last_point.blk = initial_last_point_blk + (block_slope * (t_i - initial_last_point_ts)) / MULTIPLIER;
            _epoch += 1;
            if (t_i == block.timestamp) {
                last_point.blk = block.number;
                break;
            } else {
                point_history[_epoch] = last_point;
            }
        }

        epoch = _epoch;
        // Now point_history is filled until t=now

        if (_addr != address(0x0)) {
            // If last point was in this block, the slope change has been applied already
            // But in such case we have 0 slope(s)
            last_point.slope += (u_new.slope - u_old.slope);
            last_point.bias += (u_new.bias - u_old.bias);
            if (last_point.slope < 0) {
                last_point.slope = 0;
            }
            if (last_point.bias < 0) {
                last_point.bias = 0;
            }
        }

        // Record the changed point into history
        point_history[_epoch] = last_point;

        if (_addr != address(0x0)) {
            // Schedule the slope changes (slope is going down)
            // We subtract new_user_slope from [new_locked.end]
            // and add old_user_slope to [old_locked.end]
            if (old_locked.end > block.timestamp) {
                // old_dslope was <something> - u_old.slope, so we cancel that
                old_dslope += u_old.slope;
                if (new_locked.end == old_locked.end) {
                old_dslope -= u_new.slope; // It was a new deposit, not extension
                }
                slope_changes[old_locked.end] = old_dslope;
            }

            if (new_locked.end > block.timestamp) {
                if (new_locked.end > old_locked.end) {
                new_dslope -= u_new.slope; // old slope disappeared at this point
                slope_changes[new_locked.end] = new_dslope;
                }
                // else: we recorded it already in old_dslope
            }
            // Now handle user history
            address addr = _addr;
            uint256 user_epoch = user_point_epoch[addr] + 1;

            user_point_epoch[addr] = user_epoch;
            u_new.ts = block.timestamp;
            u_new.blk = block.number;
            user_point_history[addr][user_epoch] = u_new;
        }
    }

    /// @notice Deposit and lock tokens for a user
    /// @param _addr User's wallet address
    /// @param _value Amount to deposit
    /// @param unlock_time New time when to unlock the tokens, or 0 if unchanged
    /// @param locked_balance Previous locked amount / timestamp
    function _deposit_for(address _addr, uint256 _value, uint256 unlock_time, LockedBalance memory locked_balance, int128 type_) internal {
        LockedBalance memory _locked = locked_balance;
        uint256 supply_before = supply;

        supply = supply_before + _value;
        LockedBalance memory old_locked = _locked;
        // Adding to existing lock, or if a lock is expired - creating a new one
        _locked.amount += int128(_value); // todo use safeCast
        if (unlock_time != 0) _locked.end = unlock_time;
        locked[_addr] = _locked;

        // Possibilities:
        // Both old_locked.end could be current or expired (>/< block.timestamp)
        // value == 0 (extend lock) or value > 0 (add to lock or extend lock)
        // _locked.end > block.timestamp (always)
        _checkpoint(_addr, old_locked, _locked);

        if (_value != 0) IERC20(token).safeTransferFrom(_addr, address(this), _value);

        emit Deposit(_addr, _value, _locked.end, type_, block.timestamp);
        emit Supply(supply_before, supply_before + _value);
    }
}