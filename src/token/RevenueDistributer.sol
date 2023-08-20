// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ===================== RevenueDistributer =====================
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

    uint256 public startTime;
    uint256 public timeCursor;
    mapping(address => uint256) public timeCursorOf;
    mapping(address => uint256) public userEpochOf;

    uint256 public lastTokenTime;
    uint256[1000000000000000] public tokensPerWeek;

    address public votingEscrow;
    address public token;
    uint256 public totalReceived;
    uint256 public tokenLastBalance;

    uint256[1000000000000000] public veSupply; // VE total supply at week bounds

    address public admin;
    address public futureAdmin;
    bool public canCheckpointToken;
    address public emergencyReturn;
    bool public isKilled;

    uint256 private constant _WEEK = 1 weeks;
    uint256 private constant _TOKEN_CHECKPOINT_DEADLINE = 1 days;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    /// @notice Contract constructor
    /// @param _votingEscrow VotingEscrow contract address
    /// @param _startTime Epoch time for fee distribution to start
    /// @param _token Fee token address (3CRV)
    /// @param _admin Admin address
    /// @param _emergencyReturn Address to transfer `_token` balance to
    ///                         if this contract is killed
    constructor(address _votingEscrow, uint256 _startTime, address _token, address _admin, address _emergencyReturn) {
        uint256 t = _startTime / _WEEK * _WEEK;
        startTime = t;
        lastTokenTime = t;
        timeCursor = t;
        token = _token;
        votingEscrow = _votingEscrow;
        admin = _admin;
        emergencyReturn = _emergencyReturn;
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
        address _ve = votingEscrow;
        uint256 _maxUserEpoch = VotingEscrow(_ve).userPointEpoch(_user);
        uint256 _epoch = _findTimestampUserEpoch(_ve, _user, _timestamp, _maxUserEpoch);
        Point memory pt = Point(0, 0, 0, 0);
        (pt.bias, pt.slope, pt.ts,) = VotingEscrow(_ve).userPointHistory(_user, _epoch);

        return int256(pt.bias - pt.slope).toUint256() * _timestamp - pt.ts;
    }

    // Mutated functions

    /// @inheritdoc IRevenueDistributer
    function checkpointToken() external nonReentrant {
        if (msg.sender != admin && !(canCheckpointToken && block.timestamp > lastTokenTime + _TOKEN_CHECKPOINT_DEADLINE)) revert NotAuthorized();
        _checkpointToken();
    }

    /// @inheritdoc IRevenueDistributer
    function checkpointTotalSupply() external nonReentrant {
        _checkpointTotalSupply();
    }

    /// @inheritdoc IRevenueDistributer
    function claim(address _addr) external nonReentrant returns (uint256) {
        if (isKilled) revert Dead();

        if (block.timestamp >= timeCursor) _checkpointTotalSupply();

        uint256 _lastTokenTime = lastTokenTime;

        if (canCheckpointToken && block.timestamp > _lastTokenTime + _TOKEN_CHECKPOINT_DEADLINE) {
            _checkpointToken();
            _lastTokenTime = block.timestamp;
        }

        _lastTokenTime = _lastTokenTime / _WEEK * _WEEK;

        uint256 _amount = _claim(_addr, votingEscrow, _lastTokenTime);
        if (_amount != 0) {
            address _token = token;
            IERC20(_token).safeTransfer(_addr, _amount);
            tokenLastBalance -= _amount;
        }

        return _amount;
    }

    /// @inheritdoc IRevenueDistributer
    function claimMany(address[20] calldata _receivers) external nonReentrant returns (bool) {
        if (isKilled) revert Dead();

        if (block.timestamp >= timeCursor) _checkpointTotalSupply();

        uint256 _lastTokenTime = lastTokenTime;

        if (canCheckpointToken && block.timestamp > _lastTokenTime + _TOKEN_CHECKPOINT_DEADLINE) {
            _checkpointToken();
            _lastTokenTime = block.timestamp;
        }

        _lastTokenTime = _lastTokenTime / _WEEK * _WEEK;
        address _ve = votingEscrow;
        address _token = token;
        uint256 _total = 0;

        for (uint256 i = 0; i < 20; i++) {
            address _addr = _receivers[i];
            if (_addr == address(0)) {
                break;
            }

            uint256 _amount = _claim(_addr, _ve, _lastTokenTime);
            if (_amount != 0) {
                IERC20(_token).safeTransfer(_addr, _amount);
                _total += _amount;
            }
        }

        if (_total != 0) {
            tokenLastBalance -= _total;
        }

        return true;
    }

    /// @inheritdoc IRevenueDistributer
    function burn() external returns (bool) {
        if (isKilled) revert Dead();

        address _token = token;
        uint256 _amount = IERC20(_token).balanceOf(msg.sender);
        if (_amount != 0) {
            totalReceived += _amount;

            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
            if (canCheckpointToken && block.timestamp > lastTokenTime + _TOKEN_CHECKPOINT_DEADLINE) {
                _checkpointToken();
            }

            emit Burn(_amount);
        }

        return true;
    }


    /// @inheritdoc IRevenueDistributer
    function commitAdmin(address _addr) external onlyAdmin {
        futureAdmin = _addr;

        emit CommitAdmin(_addr);
    }

    /// @inheritdoc IRevenueDistributer
    function applyAdmin() external onlyAdmin {
        if (futureAdmin == address(0)) revert ZeroAddress();

        admin = futureAdmin;

        emit ApplyAdmin(futureAdmin);
    }

    /// @inheritdoc IRevenueDistributer
    function toggleAllowCheckpointToken() external onlyAdmin {
        bool _flag = !canCheckpointToken;
        canCheckpointToken = _flag;

        emit ToggleAllowCheckpointToken(_flag);
    }

    /// @inheritdoc IRevenueDistributer
    function killMe() external onlyAdmin {
        isKilled = true;

        address _token = token;
        IERC20(_token).safeTransfer(emergencyReturn, IERC20(_token).balanceOf(address(this)));

        emit Killed();
    }

    /// @inheritdoc IRevenueDistributer
    function recoverBalance() external onlyAdmin returns (bool) {
        address _token = token;
        uint256 _amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(emergencyReturn, _amount);

        emit RecoverBalance(_token, _amount);

        return true;
    }

    // ============================================================================================
    // Internal Functions
    // ============================================================================================

    // View functions

    function _findTimestampUserEpoch(
        address _ve,
        address _user,
        uint256 _timestamp,
        uint256 _maxUserEpoch
    ) internal view returns (uint256) {
        uint256 _min = 0;
        uint256 _max = _maxUserEpoch;
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

    function _checkpointToken() internal {
        uint256 _tokenBalance = IERC20(token).balanceOf(address(this));
        uint256 _toDistribute = _tokenBalance - tokenLastBalance;
        tokenLastBalance = _tokenBalance;

        uint256 _t = lastTokenTime;
        uint256 _sinceLast = block.timestamp - _t;
        lastTokenTime = block.timestamp;
        uint256 _thisWeek = _t / _WEEK * _WEEK;
        uint256 _nextWeek = 0;

        for (uint256 i = 0; i < 20; i++) {
            _nextWeek = _thisWeek + _WEEK;
            if (block.timestamp < _nextWeek) {
                if (_sinceLast == 0 && block.timestamp == _t) {
                    tokensPerWeek[_thisWeek] += _toDistribute;
                } else {
                    tokensPerWeek[_thisWeek] += _toDistribute * (block.timestamp - _t) / _sinceLast;
                }
                break;
            } else {
                if (_sinceLast == 0 && _nextWeek == _t) {
                    tokensPerWeek[_thisWeek] += _toDistribute;
                } else {
                    tokensPerWeek[_thisWeek] += _toDistribute * (_nextWeek - _t) / _sinceLast;
                }
            }
            _t = _nextWeek;
            _thisWeek = _nextWeek;
        }
        emit CheckpointToken(block.timestamp, _toDistribute);
    }

    function _findTimestampEpoch(address _ve, uint256 _timestamp) internal view returns (uint256) {
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

    function _checkpointTotalSupply() internal {
        address _ve = votingEscrow;
        uint256 _t = timeCursor;
        uint256 _roundedTimestamp = block.timestamp / _WEEK * _WEEK;
        VotingEscrow(_ve).checkpoint();

        for (uint256 i = 0; i < 20; i++) {
            if (_t > _roundedTimestamp) {
                break;
            } else {
                uint256 epoch = _findTimestampEpoch(_ve, _t);
                Point memory _pt = Point(0, 0, 0, 0);
                (_pt.bias, _pt.slope, _pt.ts, _pt.blk) = VotingEscrow(_ve).pointHistory(epoch);
                int128 _dt = 0;
                if (_t > _pt.ts) {
                    // If the point is at 0 epoch, it can actually be earlier than the first deposit
                    // Then make dt 0
                    _dt = int256(_t - _pt.ts).toInt128();
                }
                veSupply[_t] = int256(_pt.bias - _pt.slope * _dt).toUint256();
            }
            _t += _WEEK;
        }

        timeCursor = _t;
    }

    function _claim(address _addr, address _ve, uint256 _lastTokenTime) internal returns (uint256) {
        // Minimal user_epoch is 0 (if user had no point)
        uint256 _userEpoch = 0;
        uint256 _toDistribute = 0;

        uint256 _maxUserEpoch = VotingEscrow(_ve).userPointEpoch(_addr);
        uint256 _startTime = startTime;

        if (_maxUserEpoch == 0) {
            // No lock = no fees
            return 0;
        }

        uint256 _weekCursor = timeCursorOf[_addr];
        if (_weekCursor == 0) {
            // Need to do the initial binary search
            _userEpoch = _findTimestampUserEpoch(_ve, _addr, _startTime, _maxUserEpoch);
        } else {
            _userEpoch = userEpochOf[_addr];
        }

        if (_userEpoch == 0) {
            _userEpoch = 1;
        }

        Point memory _userPoint = Point(0, 0, 0, 0);

        (
            _userPoint.bias,
            _userPoint.slope,
            _userPoint.ts,
            _userPoint.blk
        ) = VotingEscrow(_ve).userPointHistory(_addr, _userEpoch);

        if (_weekCursor == 0) {
            _weekCursor = (_userPoint.ts + _WEEK - 1) / _WEEK * _WEEK;
        }

        if (_weekCursor >= _lastTokenTime) {
            return 0;
        }

        if (_weekCursor < _startTime) {
            _weekCursor = _startTime;
        }

        Point memory _oldUserPoint = Point(0, 0, 0, 0);

        // Iterate over weeks
        for (uint256 i = 0; i < 50; i++) {
            if (_weekCursor >= _lastTokenTime) {
                break;
            }

            if (_weekCursor >= _userPoint.ts && _userEpoch <= _maxUserEpoch) {
                _userEpoch += 1;
                _oldUserPoint = _userPoint;
                if (_userEpoch > _maxUserEpoch) {
                    _userPoint = Point(0, 0, 0, 0);
                } else {
                    (
                        _userPoint.bias,
                        _userPoint.slope,
                        _userPoint.ts,
                        _userPoint.blk
                     ) = VotingEscrow(_ve).userPointHistory(_addr, _userEpoch);
                }
            } else {
                // Calc
                // + i * 2 is for rounding errors
                int128 _dt = int256(_weekCursor - _oldUserPoint.ts).toInt128();
                uint256 _balanceOf = (_oldUserPoint.bias - _dt * _oldUserPoint.slope) > 0 ? int256(_oldUserPoint.bias - _dt * _oldUserPoint.slope).toUint256() : 0;
                if (_balanceOf == 0 && _userEpoch > _maxUserEpoch) {
                    break;
                }
                if (_balanceOf > 0) {
                    _toDistribute += _balanceOf * tokensPerWeek[_weekCursor] / veSupply[_weekCursor];
                }

                _weekCursor += _WEEK;
            }
        }

        _userEpoch = _maxUserEpoch < (_userEpoch - 1) ? _maxUserEpoch : (_userEpoch - 1);
        userEpochOf[_addr] = _userEpoch;
        timeCursorOf[_addr] = _weekCursor;

        emit Claimed(_addr, _toDistribute, _userEpoch, _maxUserEpoch);

        return _toDistribute;
    }
}