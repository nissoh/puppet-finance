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
// @title Curve Fee Distribution
// @author Curve Finance
// @license MIT

// Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {IRevenueDistributer} from "src/interfaces/IRevenueDistributer.sol";

import {VotingEscrow} from "src/token/VotingEscrow.sol";

contract RevenueDistributer is ReentrancyGuard, IRevenueDistributer {

    using SafeERC20 for IERC20;

    using SafeCast for uint256;
    using SafeCast for int256;

    uint256 constant WEEK = 7 * 86400;
    uint256 constant TOKEN_CHECKPOINT_DEADLINE = 86400;

    uint256 public start_time;
    uint256 public time_cursor;
    mapping(address => uint256) public time_cursor_of;
    mapping(address => uint256) public user_epoch_of;

    uint256 public last_token_time;
    uint256[1000000000000000] public tokens_per_week;

    address public voting_escrow;
    address public token;
    uint256 public total_received;
    uint256 public token_last_balance;

    uint256[1000000000000000] public ve_supply; // VE total supply at week bounds

    address public admin;
    address public future_admin;
    bool public can_checkpoint_token;
    address public emergency_return;
    bool public is_killed;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    /// @notice Contract constructor
    /// @param _voting_escrow VotingEscrow contract address
    /// @param _start_time Epoch time for fee distribution to start
    /// @param _token Fee token address (3CRV)
    /// @param _admin Admin address
    /// @param _emergency_return Address to transfer `_token` balance to
    ///                          if this contract is killed
    constructor(address _voting_escrow, uint256 _start_time, address _token, address _admin, address _emergency_return) {
        uint256 t = _start_time / WEEK * WEEK;
        start_time = t;
        last_token_time = t;
        time_cursor = t;
        token = _token;
        voting_escrow = _voting_escrow;
        admin = _admin;
        emergency_return = _emergency_return;
    }

    // ============================================================================================
    // Modifiers
    // ============================================================================================

    /// @notice Modifier that ensures the caller is the contract's Admin
    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    // ============================================================================================
    // External Functions
    // ============================================================================================

    // View functions

    /// @inheritdoc IRevenueDistributer
    function veForAt(address _user, uint256 _timestamp) external view returns (uint256) {
        address _ve = voting_escrow;
        uint256 _max_user_epoch = VotingEscrow(_ve).userPointEpoch(_user);
        uint256 _epoch = _find_timestamp_user_epoch(_ve, _user, _timestamp, _max_user_epoch);
        Point memory pt = Point(0, 0, 0, 0);
        (pt.bias, pt.slope, pt.ts,) = VotingEscrow(_ve).userPointHistory(_user, _epoch);

        return int256(pt.bias - pt.slope).toUint256() * _timestamp - pt.ts;
    }

    // Mutated functions

    /// @inheritdoc IRevenueDistributer
    function checkpointToken() external {
        if (msg.sender != admin && !(can_checkpoint_token && block.timestamp > last_token_time + TOKEN_CHECKPOINT_DEADLINE)) revert NotAuthorized();
        _checkpoint_token();
    }

    /// @inheritdoc IRevenueDistributer
    function checkpointTotalSupply() external {
        _checkpoint_total_supply();
    }

    /// @inheritdoc IRevenueDistributer
    function claim(address _addr) external nonReentrant returns (uint256) {
        if (is_killed) revert Dead();

        if (block.timestamp >= time_cursor) _checkpoint_total_supply();

        uint256 _last_token_time = last_token_time;

        if (can_checkpoint_token && block.timestamp > _last_token_time + TOKEN_CHECKPOINT_DEADLINE) {
            _checkpoint_token();
            _last_token_time = block.timestamp;
        }

        _last_token_time = _last_token_time / WEEK * WEEK;

        uint256 _amount = _claim(_addr, voting_escrow, _last_token_time);
        if (_amount != 0) {
            address _token = token;
            IERC20(_token).safeTransfer(_addr, _amount);
            token_last_balance -= _amount;
        }

        return _amount;
    }

    /// @inheritdoc IRevenueDistributer
    function claimMany(address[20] calldata _receivers) external nonReentrant returns (bool) {
        if (is_killed) revert Dead();

        if (block.timestamp >= time_cursor) _checkpoint_total_supply();

        uint256 _last_token_time = last_token_time;

        if (can_checkpoint_token && block.timestamp > _last_token_time + TOKEN_CHECKPOINT_DEADLINE) {
            _checkpoint_token();
            _last_token_time = block.timestamp;
        }

        _last_token_time = _last_token_time / WEEK * WEEK;
        address _ve = voting_escrow;
        address _token = token;
        uint256 _total = 0;

        for (uint256 i = 0; i < 20; i++) {
            address _addr = _receivers[i];
            if (_addr == address(0)) {
                break;
            }

            uint256 _amount = _claim(_addr, _ve, _last_token_time);
            if (_amount != 0) {
                IERC20(_token).safeTransfer(_addr, _amount);
                _total += _amount;
            }
        }

        if (_total != 0) {
            token_last_balance -= _total;
        }

        return true;
    }

    /// @inheritdoc IRevenueDistributer
    function commitAdmin(address _addr) external onlyAdmin {
        future_admin = _addr;

        emit CommitAdmin(_addr);
    }

    /// @inheritdoc IRevenueDistributer
    function applyAdmin() external onlyAdmin {
        if (future_admin == address(0)) revert ZeroAddress();

        admin = future_admin;

        emit ApplyAdmin(future_admin);
    }

    /// @inheritdoc IRevenueDistributer
    function toggleAllowCheckpointToken() external onlyAdmin {
        bool _flag = !can_checkpoint_token;
        can_checkpoint_token = _flag;

        emit ToggleAllowCheckpointToken(_flag);
    }

    /// @inheritdoc IRevenueDistributer
    function killMe() external onlyAdmin {
        is_killed = true;

        address _token = token;
        IERC20(_token).safeTransfer(emergency_return, IERC20(_token).balanceOf(address(this)));

        emit Killed();
    }

    /// @inheritdoc IRevenueDistributer
    function recoverBalance() external onlyAdmin returns (bool) {
        address _token = token;
        uint256 _amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(emergency_return, _amount);

        emit RecoverBalance(_token, _amount);

        return true;
    }

    // ============================================================================================
    // Internal Functions
    // ============================================================================================

    // View functions

    function _find_timestamp_user_epoch(
        address _ve,
        address _user,
        uint256 _timestamp,
        uint256 _max_user_epoch
    ) internal view returns (uint256) {
        uint256 _min = 0;
        uint256 _max = _max_user_epoch;
        for (uint256 i = 0; i < 128; i++) {
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 2) / 2;
            Point memory pt = Point(0, 0, 0, 0);
            (pt.bias, pt.slope, pt.ts, pt.blk) = VotingEscrow(_ve).userPointHistory(_user, _mid);
            if (pt.ts <= _timestamp) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }

        return _min;
    }

    // Mutated functions

    function _checkpoint_token() internal {
        uint256 token_balance = IERC20(token).balanceOf(address(this));
        uint256 to_distribute = token_balance - token_last_balance;
        token_last_balance = token_balance;

        uint256 t = last_token_time;
        uint256 since_last = block.timestamp - t;
        last_token_time = block.timestamp;
        uint256 this_week = t / WEEK * WEEK;
        uint256 next_week = 0;

        for (uint256 i = 0; i < 20; i++) {
            next_week = this_week + WEEK;
            if (block.timestamp < next_week) {
                if (since_last == 0 && block.timestamp == t) {
                    tokens_per_week[this_week] += to_distribute;
                } else {
                    tokens_per_week[this_week] += to_distribute * (block.timestamp - t) / since_last;
                }
                break;
            } else {
                if (since_last == 0 && next_week == t) {
                    tokens_per_week[this_week] += to_distribute;
                } else {
                    tokens_per_week[this_week] += to_distribute * (next_week - t) / since_last;
                }
            }
            t = next_week;
            this_week = next_week;
        }
        emit CheckpointToken(block.timestamp, to_distribute);
    }

    function _find_timestamp_epoch(address _ve, uint256 _timestamp) internal view returns (uint256) {
        uint256 _min = 0;
        uint256 _max = VotingEscrow(_ve).epoch();
        for (uint256 i = 0; i < 128; i++) {
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 2) / 2;
            Point memory pt = Point(0, 0, 0, 0);
            (pt.bias, pt.slope, pt.ts, pt.blk) = VotingEscrow(_ve).pointHistory(_mid);
            if (pt.ts <= _timestamp) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }

        return _min;
    }

    function _checkpoint_total_supply() internal {
        address _ve = voting_escrow;
        uint256 _t = time_cursor;
        uint256 _rounded_timestamp = block.timestamp / WEEK * WEEK;
        VotingEscrow(_ve).checkpoint();

        for (uint256 i = 0; i < 20; i++) {
            if (_t > _rounded_timestamp) {
                break;
            } else {
                uint256 epoch = _find_timestamp_epoch(_ve, _t);
                Point memory _pt = Point(0, 0, 0, 0);
                (_pt.bias, _pt.slope, _pt.ts, _pt.blk) = VotingEscrow(_ve).pointHistory(epoch);
                int128 _dt = 0;
                if (_t > _pt.ts) {
                    // If the point is at 0 epoch, it can actually be earlier than the first deposit
                    // Then make dt 0
                    _dt = int256(_t - _pt.ts).toInt128();
                }
                ve_supply[_t] = int256(_pt.bias - _pt.slope * _dt).toUint256();
            }
            _t += WEEK;
        }

        time_cursor = _t;
    }

    function _claim(address _addr, address _ve, uint256 _last_token_time) internal returns (uint256) {
        // Minimal user_epoch is 0 (if user had no point)
        uint256 _user_epoch = 0;
        uint256 _to_distribute = 0;

        uint256 _max_user_epoch = VotingEscrow(_ve).userPointEpoch(_addr);
        uint256 _start_time = start_time;

        if (_max_user_epoch == 0) {
            // No lock = no fees
            return 0;
        }

        uint256 _week_cursor = time_cursor_of[_addr];
        if (_week_cursor == 0) {
            // Need to do the initial binary search
            _user_epoch = _find_timestamp_user_epoch(_ve, _addr, _start_time, _max_user_epoch);
        } else {
            _user_epoch = user_epoch_of[_addr];
        }

        if (_user_epoch == 0) {
            _user_epoch = 1;
        }

        Point memory _user_point = Point(0, 0, 0, 0);
        (
            _user_point.bias,
            _user_point.slope,
            _user_point.ts,
            _user_point.blk
        ) = VotingEscrow(_ve).userPointHistory(_addr, _user_epoch);

        if (_week_cursor == 0) {
            _week_cursor = (_user_point.ts + WEEK - 1) / WEEK * WEEK;
        }

        if (_week_cursor >= _last_token_time) {
            return 0;
        }

        if (_week_cursor < _start_time) {
            _week_cursor = _start_time;
        }
        Point memory _old_user_point = Point(0, 0, 0, 0);

        // Iterate over weeks
        for (uint256 i = 0; i < 50; i++) {
            if (_week_cursor >= _last_token_time) {
                break;
            }

            if (_week_cursor >= _user_point.ts && _user_epoch <= _max_user_epoch) {
                _user_epoch += 1;
                _old_user_point = _user_point;
                if (_user_epoch > _max_user_epoch) {
                    _user_point = Point(0, 0, 0, 0);
                } else {
                    (
                        _user_point.bias,
                        _user_point.slope,
                        _user_point.ts,
                        _user_point.blk
                     ) = VotingEscrow(_ve).userPointHistory(_addr, _user_epoch);
                }
            } else {
                // Calc
                // + i * 2 is for rounding errors
                int128 dt = int256(_week_cursor - _old_user_point.ts).toInt128();
                uint256 balance_of = max(int256(_old_user_point.bias - dt * _old_user_point.slope).toUint256(), 0);
                if (balance_of == 0 && _user_epoch > _max_user_epoch) {
                    break;
                }
                if (balance_of > 0) {
                    _to_distribute += balance_of * tokens_per_week[_week_cursor] / ve_supply[_week_cursor];
                }

                _week_cursor += WEEK;
            }
        }

        _user_epoch = min(_max_user_epoch, _user_epoch - 1);
        user_epoch_of[_addr] = _user_epoch;
        time_cursor_of[_addr] = _week_cursor;

        emit Claimed(_addr, _to_distribute, _user_epoch, _max_user_epoch);

        return _to_distribute;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
}