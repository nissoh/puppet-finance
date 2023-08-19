// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ======================== VotingEscrow ========================
// ==============================================================

// Modified fork from Curve Finance: https://github.com/curvefi 
// @title Voting Escrow
// @author Curve Finance
// @license MIT
// @notice Votes have a weight depending on time, so that users are committed to the future of (whatever they are voting for)
// @dev Vote weight decays linearly over time. Lock time cannot be more than `MAXTIME` (4 years).

// Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IVotingEscrow} from "src/interfaces/IVotingEscrow.sol";

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

// todo - add (1) auto-max-relock
contract VotingEscrow is ReentrancyGuard, IVotingEscrow {

    using SafeERC20 for IERC20;

    using SafeCast for uint256;
    using SafeCast for int256;

    // settings

    string public name;
    string public symbol;
    string public version;

    bool public unlocked;

    address public admin; // Can and will be a smart contract
    address public futureAdmin;

    address public immutable token;

    uint256 public supply;

    uint256 public immutable decimals;

    // voting weights variables

    uint256 public epoch;

    mapping(address => uint256) public userPointEpoch;
    mapping(uint256 => int128) public slopeChanges; // time -> signed slope change
    mapping(address => LockedBalance) public locked;
    mapping(uint256 => Point) public pointHistory; // epoch -> unsigned point
    mapping(address => Point[1000000000]) public userPointHistory; // user -> Point[user_epoch]

    // Whitelisted (smart contract) wallets which are allowed to deposit
    // The goal is to prevent tokenizing the escrow
    mapping(address => bool) public contractsWhitelist;

    // constants

    int128 private constant _DEPOSIT_FOR_TYPE = 0;
    int128 private constant _CREATE_LOCK_TYPE = 1;
    int128 private constant _INCREASE_LOCK_AMOUNT = 2;
    int128 private constant _INCREASE_UNLOCK_TIME = 3;
    int128 private constant _MAXTIME = 4 * 365 * 86400;

    uint256 public constant MAXTIME = 4 * 365 * 86400; // 4 years

    uint256 private constant _WEEK = 7 * 86400; // all future times are rounded by week
    uint256 private constant _MULTIPLIER = 10 ** 18;

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
        pointHistory[0].blk = block.number;
        pointHistory[0].ts = block.timestamp;

        uint256 _decimals = IERC20(_token).decimals();
        require(_decimals <= 255, "decimals <= 255");
        decimals = _decimals;

        name = _name;
        symbol = _symbol;
        version = _version;
    }

    // ============================================================================================
    // Modifiers
    // ============================================================================================

    /// @notice Ensures that the caller is an EOA or a whitelisted smart contract
    modifier onlyUserOrWhitelist() {
        if (msg.sender != tx.origin) if (!contractsWhitelist[msg.sender]) revert NotWhitelisted();
        _;
    }

    /// @notice Ensures that the contract is not locked
    modifier notUnlocked() {
        if (unlocked) revert Unlocked();
        _;
    }

    /// @notice Ensures the caller is the contract's Admin
    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    // ============================================================================================
    // External functions
    // ============================================================================================

    // view functions

    /// @inheritdoc IVotingEscrow
    function getLastUserSlope(address _addr) external view returns (int128) {
        uint256 _uepoch = userPointEpoch[_addr];
        return userPointHistory[_addr][_uepoch].slope;
    }

    /// @inheritdoc IVotingEscrow
    function userPointHistoryTs(address _addr, uint256 _idx) external view returns (uint256) {
        return userPointHistory[_addr][_idx].ts;
    }

    /// @inheritdoc IVotingEscrow
    function lockedEnd(address _addr) external view returns (uint256) {
        return locked[_addr].end;
    }

    // NOTE: The following ERC20/minime-compatible methods are not real balanceOf and supply!
    // They measure the weights for the purpose of voting, so they don't represent real coins.

    /// @inheritdoc IVotingEscrow
    function balanceOfAtT(address _addr, uint256 _t) external view returns (uint256) {
        return _balanceOf(_addr, _t);
    }

    /// @inheritdoc IVotingEscrow
    function balanceOf(address _addr) external view returns (uint256) {
        return _balanceOf(_addr, block.timestamp);
    }

    /// @inheritdoc IVotingEscrow
    function balanceOfAt(address _addr, uint256 _block) external view returns (uint256) {
        // Copying and pasting totalSupply code because Vyper cannot pass by
        // reference yet
        require(_block <= block.number);

        // Binary search
        uint256 _min = 0;
        uint256 _max = userPointEpoch[_addr];
        for (uint256 i = 0; i < 128; ++i) { // Will be always enough for 128-bit numbers
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 1) / 2;
            if (userPointHistory[_addr][_mid].blk <= _block) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }

        Point memory upoint = userPointHistory[_addr][_min];

        uint256 _maxEpoch = epoch;
        uint256 _epoch = _findBlockEpoch(_block, _maxEpoch);
        Point memory _point0 = pointHistory[_epoch];
        uint256 _dBlock = 0;
        uint256 _dT = 0;
        if (_epoch < _maxEpoch) {
            Point memory _point1 = pointHistory[_epoch + 1];
            _dBlock = _point1.blk - _point0.blk;
            _dT = _point1.ts - _point0.ts;
        } else {
            _dBlock = block.number - _point0.blk;
            _dT = block.timestamp - _point0.ts;
        }
        uint256 _blockTime = _point0.ts;
        if (_dBlock != 0) {
            _blockTime += (_dT * (_block - _point0.blk)) / _dBlock;
        }

        upoint.bias -= upoint.slope * (_blockTime - upoint.ts).toInt256().toInt128();
        if (upoint.bias >= 0) {
            return int256(upoint.bias).toUint256();
        } else {
            return 0;
        }
    }

    /// @inheritdoc IVotingEscrow
    function totalSupply() external view returns (uint256) {
        return _totalSupply(block.timestamp);
    }

    /// @inheritdoc IVotingEscrow
    function totalSupplyAtT(uint256 _t) external view returns (uint256) {
        return _totalSupply(_t);
    }

    /// @inheritdoc IVotingEscrow
    function totalSupplyAt(uint256 _block) external view returns (uint256) {
        require(_block <= block.number);

        uint256 _epoch = epoch;
        uint256 _targetEpoch = _findBlockEpoch(_block, _epoch);

        Point memory _point = pointHistory[_targetEpoch];
        uint256 _dt = 0;
        if (_targetEpoch < _epoch) {
            Point memory _pointNext = pointHistory[_targetEpoch + 1];
            if (_point.blk != _pointNext.blk) {
                _dt = (_block - _point.blk) * (_pointNext.ts - _point.ts) / (_pointNext.blk - _point.blk);
            }
        } else {
            if (_point.blk != block.number) {
                _dt = (_block - _point.blk) * (block.timestamp - _point.ts) / (block.number - _point.blk);
            }
        }
        // Now dt contains info on how far are we beyond point

        return _supplyAt(_point, _point.ts + _dt);
    }

    // mutated functions

    /// @inheritdoc IVotingEscrow
    function checkpoint() external notUnlocked {
        _checkpoint(address(0), LockedBalance(0, 0), LockedBalance(0, 0));
    }

    /// @inheritdoc IVotingEscrow
    function depositFor(address _addr, uint256 _value) external nonReentrant notUnlocked {
        LockedBalance memory _locked = locked[_addr];

        if (_value == 0) revert ZeroValue();
        if (_locked.amount <= 0) revert NoLockFound();
        if (_locked.end <= block.timestamp) revert LockExpired();

        _depositFor(_addr, _value, 0, locked[_addr], _DEPOSIT_FOR_TYPE);
    }

    /// @notice Deposit `_value` tokens for `msg.sender` and lock until `_unlockTime`
    /// @param _value Amount to deposit
    /// @param _unlockTime Epoch time when tokens unlock, rounded down to whole weeks
    function createLock(uint256 _value, uint256 _unlockTime) external onlyUserOrWhitelist nonReentrant notUnlocked {
        if (_value == 0) revert ZeroValue();
        if (locked[msg.sender].amount != 0) revert WithdrawOldTokensFirst();

        _unlockTime = (_unlockTime / _WEEK) * _WEEK; // Locktime is rounded down to weeks
        if (_unlockTime <= block.timestamp) revert LockTimeInThePast();
        if (_unlockTime > block.timestamp + MAXTIME) revert LockTimeTooLong();

        _depositFor(msg.sender, _value, _unlockTime, locked[msg.sender], _CREATE_LOCK_TYPE);
    }

    /// @inheritdoc IVotingEscrow
    function increaseAmount(uint256 _value) external onlyUserOrWhitelist nonReentrant notUnlocked {
        LockedBalance memory _locked = locked[msg.sender];

        if (_value == 0) revert ZeroValue();
        if (_locked.amount <= 0) revert NoLockFound();
        if (_locked.end <= block.timestamp) revert LockExpired(); // Cannot add to expired lock. Withdraw

        _depositFor(msg.sender, _value, 0, locked[msg.sender], _INCREASE_LOCK_AMOUNT);
    }

    /// @inheritdoc IVotingEscrow
    function increaseUnlockTime(uint256 _unlockTime) external onlyUserOrWhitelist nonReentrant notUnlocked {
        LockedBalance memory _locked = locked[msg.sender];

        if (_locked.amount <= 0) revert NoLockFound();
        if (_locked.end <= block.timestamp) revert LockExpired(); // Cannot add to expired lock. Withdraw

        _unlockTime = (_unlockTime / _WEEK) * _WEEK; // Locktime is rounded down to weeks
        if (_unlockTime <= block.timestamp) revert LockTimeInThePast();
        if (_unlockTime > block.timestamp + MAXTIME) revert LockTimeTooLong();

        _depositFor(msg.sender, 0, _unlockTime, locked[msg.sender], _INCREASE_UNLOCK_TIME);
    }

    /// @inheritdoc IVotingEscrow
    function withdraw() external nonReentrant {
        LockedBalance memory _locked = locked[msg.sender];

        if (_locked.amount <= 0) revert NoLockFound();
        if (!unlocked) if (_locked.end > block.timestamp) revert LockNotExpired();

        uint256 value = int256(_locked.amount).toUint256();

        LockedBalance memory _oldLocked = _locked;
        _locked.end = 0;
        _locked.amount = 0;
        locked[msg.sender] = _locked;
        uint256 _supplyBefore = supply;
        supply = _supplyBefore - value;

        _checkpoint(msg.sender, _oldLocked, _locked);

        IERC20(token).safeTransfer(msg.sender, value);

        emit Withdraw(msg.sender, value, block.timestamp);
        emit Supply(_supplyBefore, _supplyBefore - value);
    }

    /// @inheritdoc IVotingEscrow
    function commitTransferOwnership(address _addr) external onlyAdmin {
        futureAdmin = _addr;
        emit CommitOwnership(_addr);
    }

    /// @inheritdoc IVotingEscrow
    function applyTransferOwnership() external onlyAdmin {
        address _admin = futureAdmin;
        if (_admin == address(0)) revert ZeroAddress();
        admin = _admin;
        emit ApplyOwnership(_admin);
    }

    /// @inheritdoc IVotingEscrow
    function addToWhitelist(address _addr) external onlyAdmin {
        contractsWhitelist[_addr] = true;
    }

    /// @inheritdoc IVotingEscrow
    function removeFromWhitelist(address _addr) external onlyAdmin {
        contractsWhitelist[_addr] = false;
    }

    /// @inheritdoc IVotingEscrow
    function unlock() external onlyAdmin {
        unlocked = true;
    }

    // ============================================================================================
    // Internal functions
    // ============================================================================================

    // view functions

    /// @notice Binary search to estimate timestamp for block number
    /// @param _block Block to find
    /// @param _maxEpoch Don't go beyond this epoch
    /// @return Approximate timestamp for block
    function _findBlockEpoch(uint256 _block, uint256 _maxEpoch) internal view returns (uint256) {
        // Binary search
        uint256 _min = 0;
        uint256 _max = _maxEpoch;
        for (uint256 i = 0; i < 128; i++) { // Will always be enough for 128-bit numbers
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 1) / 2;
            if (pointHistory[_mid].blk <= _block) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }
        return _min;
    }

    function _totalSupply(uint256 _t) internal view returns (uint256) {
        uint256 _epoch = epoch;
        Point memory lastPoint = pointHistory[_epoch];
        return _supplyAt(lastPoint, _t);
    }

    /// @notice Calculate total voting power at some point in the past
    /// @param _point The point (bias/slope) to start search from
    /// @param _t Time to calculate the total voting power at
    /// @return Total voting power at that time
    function _supplyAt(Point memory _point, uint256 _t) internal view returns (uint256) {
        Point memory _lastPoint = _point;
        uint256 _tI = (_lastPoint.ts / _WEEK) * _WEEK;
        for (uint256 i = 0; i < 255; ++i) {
            _tI += _WEEK;
            int128 _dSlope = 0;
            if (_tI > _t) {
                _tI = _t;
            } else {
                _dSlope = slopeChanges[_tI];
            }
            _lastPoint.bias -= _lastPoint.slope * (_tI - _lastPoint.ts).toInt256().toInt128();
            if (_tI == _t) {
                break;
            }
            _lastPoint.slope += _dSlope;
            _lastPoint.ts = _tI;
        }

        if (_lastPoint.bias >= 0) {
            return int256(_lastPoint.bias).toUint256();
        } else {
            return 0;
        }
    }

    /// @notice Get the current voting power for `msg.sender`
    /// @dev Adheres to the ERC20 `balanceOf` interface
    /// @param _addr User wallet address
    /// @param _t Epoch time to return voting power at
    /// @return User voting power
    function _balanceOf(address _addr, uint256 _t) internal view returns (uint256) {
        uint256 _epoch = userPointEpoch[_addr];
        if (_epoch == 0) {
            return 0;
        } else {
            Point memory _lastPoint = userPointHistory[_addr][_epoch];
            _lastPoint.bias -= _lastPoint.slope * (_t - _lastPoint.ts).toInt256().toInt128();
            if (_lastPoint.bias < 0) {
                _lastPoint.bias = 0;
            }
            return uint256(int256(_lastPoint.bias));
        }
    }

    // mutated functions

    /// @notice Record global and per-user data to checkpoint
    /// @param _addr User's wallet address. No user checkpoint if 0x0
    /// @param _oldLocked Pevious locked amount / end lock time for the user
    /// @param _newLocked New locked amount / end lock time for the user
    function _checkpoint(address _addr, LockedBalance memory _oldLocked, LockedBalance memory _newLocked) internal {
        Point memory _uOld;
        Point memory _uNew;
        int128 _oldDslope = 0;
        int128 _newDslope = 0;
        uint256 _epoch = epoch;

        if (_addr != address(0x0)) {
            // Calculate slopes and biases
            // Kept at zero when they have to
            if (_oldLocked.end > block.timestamp && _oldLocked.amount > 0) {
                _uOld.slope = _oldLocked.amount / _MAXTIME;
                _uOld.bias = _uOld.slope * (_oldLocked.end - block.timestamp).toInt256().toInt128();
            }
            if (_newLocked.end > block.timestamp && _newLocked.amount > 0) {
                _uNew.slope = _newLocked.amount / _MAXTIME;
                _uNew.bias = _uNew.slope * (_newLocked.end - block.timestamp).toInt256().toInt128();
            }

            // Read values of scheduled changes in the slope
            // _oldLocked.end can be in the past and in the future
            // _newLocked.end can ONLY by in the FUTURE unless everything expired: than zeros
            _oldDslope = slopeChanges[_oldLocked.end];
            if (_newLocked.end != 0) {
                if (_newLocked.end == _oldLocked.end) {
                    _newDslope = _oldDslope;
                } else {
                    _newDslope = slopeChanges[_newLocked.end];
                }
            }
        }

        Point memory _lastPoint = Point({bias: 0, slope: 0, ts: block.timestamp, blk: block.number});
        if (_epoch > 0) {
            _lastPoint = pointHistory[_epoch];
        }
        uint256 _lastCheckpoint = _lastPoint.ts;
        // initial_last_point is used for extrapolation to calculate block number
        // (approximately, for *At methods) and save them
        // as we cannot figure that out exactly from inside the contract

        uint256 _initialLastPointTs = _lastPoint.ts;
        uint256 _initialLastPointBlk = _lastPoint.blk;

        uint256 _blockSlope = 0; // dblock/dt
        if (block.timestamp > _lastPoint.ts) {
            _blockSlope = (_MULTIPLIER * (block.number - _lastPoint.blk)) / (block.timestamp - _lastPoint.ts);
        }
        // If last point is already recorded in this block, slope=0
        // But that's ok b/c we know the block in such case

        // Go over weeks to fill history and calculate what the current point is
        uint256 _tI = (_lastCheckpoint / _WEEK) * _WEEK;
        for (uint256 i = 0; i < 255; ++i) {
            // Hopefully it won't happen that this won't get used in 5 years!
            // If it does, users will be able to withdraw but vote weight will be broken
            _tI += _WEEK;
            int128 _dSlope = 0;
            if (_tI > block.timestamp) {
                _tI = block.timestamp;
            } else {
                _dSlope = slopeChanges[_tI];
            }
            
            _lastPoint.bias -= _lastPoint.slope * (_tI - _lastCheckpoint).toInt256().toInt128();
            _lastPoint.slope += _dSlope;
            
            if (_lastPoint.bias < 0) {
                // This can happen
                _lastPoint.bias = 0;
            }
            if (_lastPoint.slope < 0) {
                // This cannot happen - just in case
                _lastPoint.slope = 0;
            }
            _lastCheckpoint = _tI;
            _lastPoint.ts = _tI;
            _lastPoint.blk = _initialLastPointBlk + (_blockSlope * (_tI - _initialLastPointTs)) / _MULTIPLIER;
            _epoch += 1;
            if (_tI == block.timestamp) {
                _lastPoint.blk = block.number;
                break;
            } else {
                pointHistory[_epoch] = _lastPoint;
            }
        }

        epoch = _epoch;
        // Now pointHistory is filled until t=now

        if (_addr != address(0x0)) {
            // If last point was in this block, the slope change has been applied already
            // But in such case we have 0 slope(s)
            _lastPoint.slope += (_uNew.slope - _uOld.slope);
            _lastPoint.bias += (_uNew.bias - _uOld.bias);
            if (_lastPoint.slope < 0) {
                _lastPoint.slope = 0;
            }
            if (_lastPoint.bias < 0) {
                _lastPoint.bias = 0;
            }
        }

        // Record the changed point into history
        pointHistory[_epoch] = _lastPoint;

        if (_addr != address(0x0)) {
            // Schedule the slope changes (slope is going down)
            // We subtract new_user_slope from [_newLocked.end]
            // and add old_user_slope to [_oldLocked.end]
            if (_oldLocked.end > block.timestamp) {
                // _oldDslope was <something> - _uOld.slope, so we cancel that
                _oldDslope += _uOld.slope;
                if (_newLocked.end == _oldLocked.end) {
                    _oldDslope -= _uNew.slope; // It was a new deposit, not extension
                }
                slopeChanges[_oldLocked.end] = _oldDslope;
            }

            if (_newLocked.end > block.timestamp) {
                if (_newLocked.end > _oldLocked.end) {
                    _newDslope -= _uNew.slope; // old slope disappeared at this point
                    slopeChanges[_newLocked.end] = _newDslope;
                }
                // else: we recorded it already in _oldDslope
            }
            // Now handle user history
            address addr = _addr;
            uint256 _userEpoch = userPointEpoch[addr] + 1;

            userPointEpoch[addr] = _userEpoch;
            _uNew.ts = block.timestamp;
            _uNew.blk = block.number;
            userPointHistory[addr][_userEpoch] = _uNew;
        }
    }

    /// @notice Deposit and lock tokens for a user
    /// @param _addr User's wallet address
    /// @param _value Amount to deposit
    /// @param _unlockTime New time when to unlock the tokens, or 0 if unchanged
    /// @param _lockedBalance Previous locked amount / timestamp
    function _depositFor(address _addr, uint256 _value, uint256 _unlockTime, LockedBalance memory _lockedBalance, int128 type_) internal {
        LockedBalance memory _locked = _lockedBalance;
        uint256 _supplyBefore = supply;

        supply = _supplyBefore + _value;
        LockedBalance memory _oldLocked;
        (_oldLocked.amount, _oldLocked.end) = (_locked.amount, _locked.end);
        // Adding to existing lock, or if a lock is expired - creating a new one
        _locked.amount += _value.toInt256().toInt128();
        if (_unlockTime != 0) _locked.end = _unlockTime;
        locked[_addr] = _locked;

        // Possibilities:
        // Both _oldLocked.end could be current or expired (>/< block.timestamp)
        // value == 0 (extend lock) or value > 0 (add to lock or extend lock)
        // _locked.end > block.timestamp (always)
        _checkpoint(_addr, _oldLocked, _locked);

        if (_value != 0) IERC20(token).safeTransferFrom(_addr, address(this), _value);

        emit Deposit(_addr, _value, _locked.end, type_, block.timestamp);
        emit Supply(_supplyBefore, _supplyBefore + _value);
    }
}