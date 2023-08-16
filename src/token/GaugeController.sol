// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ====================== GaugeController =======================
// ==============================================================

// Modified fork from Curve Finance: https://github.com/curvefi 
// @title Gauge Controller
// @author Curve Finance
// @license MIT
// @notice Controls liquidity gauges and the issuance of coins through the gauges

// Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IGaugeController} from "src/interfaces/IGaugeController.sol";
import {IVotingEscrow} from "src/interfaces/IVotingEscrow.sol";
import {IScoreGauge} from "src/interfaces/IScoreGauge.sol";
import {IPuppet} from "src/interfaces/IPuppet.sol";

contract GaugeController is IGaugeController {

    using SafeCast for int256;

    // settings

    address public admin;
    address public future_admin; // can and will be a smart contract
    address public token;
    address public votingEscrow;

    uint256 public currentEpochEndTime;

    uint256 private _currentEpoch;
    uint256 private _profitWeight;
    uint256 private _volumeWeight;

    // Gauge parameters
    // All numbers are "fixed point" on the basis of 1e18
    int128 public n_gauge_types;
    int128 public n_gauges;
    mapping(int128 => string) public gauge_type_names;

    // Needed for enumeration
    address[1000000000] public gauges;

    // we increment values by 1 prior to storing them here so we can rely on a value
    // of zero as meaning the gauge has not been set
    mapping(address => int128) public gauge_types_;
    mapping(address => uint256) public vote_user_power; // Total vote power used by user
    mapping(address => mapping(address => VotedSlope)) public vote_user_slopes; // user -> gauge_addr -> VotedSlope
    mapping(address => mapping(address => uint256)) public last_user_vote; // Last user vote's timestamp for each gauge address

    // Past and scheduled points for gauge weight, sum of weights per type, total weight
    // Point is for bias+slope
    // changes_* are for changes in slope
    // time_* are for the last change timestamp
    // timestamps are rounded to whole weeks

    mapping(address => mapping(uint256 => Point)) public points_weight; // gauge_addr -> time -> Point
    mapping(address => mapping(uint256 => uint256)) public changes_weight; // gauge_addr -> time -> slope
    mapping(address => uint256) public time_weight; // gauge_addr -> last scheduled time (next week)

    mapping(int128 => mapping(uint256 => Point)) public points_sum; // type_id -> time -> Point
    mapping(int128 => mapping(uint256 => uint256)) public changes_sum; // type_id -> time -> slope
    uint256[1000000000] public time_sum; // type_id -> last scheduled time (next week)

    mapping(uint256 => uint256) public points_total; // time -> total weight
    uint256 public timeTotal; // last scheduled time

    mapping(int128 => mapping(uint256 => uint256)) public points_type_weight; // type_id -> time -> type weight
    uint256[1000000000] public time_type_weight; // type_id -> last scheduled time (next week)

    mapping(uint256 => EpochData) public epochData; // epoch -> EpochData

    // constants
    uint256 constant WEEK = 1 weeks;
    uint256 constant MULTIPLIER = 1e18;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    /// @notice Contract constructor
    /// @param _token `ERC20PUPPET` contract address
    /// @param _votingEscrow `VotingEscrow` contract address
    constructor(address _token, address _votingEscrow) {
        if (_token == address(0)) revert ZeroAddress();
        if (_votingEscrow == address(0)) revert ZeroAddress();

        admin = msg.sender;
        token = _token;
        votingEscrow = _votingEscrow;
        timeTotal = block.timestamp / WEEK * WEEK;

        _profitWeight = 2000; // 20%
        _volumeWeight = 8000; // 80%
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
    // External functions
    // ============================================================================================

    // view functions

    /// @inheritdoc IGaugeController
    function profitWeight() external view returns (uint256) {
        return _profitWeight;
    }

    /// @inheritdoc IGaugeController
    function volumeWeight() external view returns (uint256) {
        return _volumeWeight;
    }

    /// @inheritdoc IGaugeController
    function getGaugeWeight(address _gauge) external view returns (uint256) {
        return points_weight[_gauge][time_weight[_gauge]].bias;
    }

    /// @inheritdoc IGaugeController
    function getTypeWeight(int128 _typeID) external view returns (uint256) {
        return points_type_weight[_typeID][time_type_weight[int256(_typeID).toUint256()]];
    }

    /// @inheritdoc IGaugeController
    function getTotalWeight() external view returns (uint256) {
        return points_total[timeTotal];
    }

    /// @inheritdoc IGaugeController
    function getWeightsSumPerType(int128 type_id) external view returns (uint256) {
        return points_sum[type_id][time_sum[uint256(int256(type_id))]].bias;
    }

    /// @inheritdoc IGaugeController
    function gaugeTypes(address _gauge) external view returns (int128) {
        int128 gauge_type = gauge_types_[_gauge];
        if (gauge_type == 0) revert GaugeTypeNotSet();

        return gauge_type - 1;
    }

    /// @inheritdoc IGaugeController
    function gaugeRelativeWeight(address _gauge, uint256 _time) external view returns (uint256) {
        return _gaugeRelativeWeight(_gauge, _time);
    }

    /// @inheritdoc IGaugeController
    function epoch() external view returns (uint256) {
        return _currentEpoch;
    }

    /// @inheritdoc IGaugeController
    function epochTimeframe(uint256 _epoch) external view returns (uint256, uint256) {
        return (epochData[_epoch].startTime, epochData[_epoch].endTime);
    }

    /// @inheritdoc IGaugeController
    function gaugeWeightForEpoch(uint256 _epoch, address _gauge) external view returns (uint256) {
        return epochData[_epoch].gaugeWeights[_gauge];
    }

    /// @inheritdoc IGaugeController
    function hasEpochEnded(uint256 _epoch) external view returns (bool) {
        return epochData[_epoch].hasEnded;
    }

    // mutated functions

    /// @inheritdoc IGaugeController
    function gaugeRelativeWeightWrite(address addr, uint256 time) external returns (uint256) {
        _getWeight(addr);
        _getTotal(); // Also calculates get_sum
        return _gaugeRelativeWeight(addr, time);
    }

    /// @inheritdoc IGaugeController
    function checkpoint() external {
        _getTotal();
    }

    /// @inheritdoc IGaugeController
    function checkpointGauge(address _gauge) external {
        _getWeight(_gauge);
        _getTotal();
    }

    /// @inheritdoc IGaugeController
    function addGauge(address _gauge, int128 _gaugeType, uint256 _weight) external onlyAdmin {
        if (_gaugeType < 0 || _gaugeType >= n_gauge_types) revert InvalidGaugeType();
        if (gauge_types_[_gauge] != 0) revert GaugeAlreadyAdded();

        int128 n = n_gauges;
        n_gauges = n + 1;
        gauges[int256(n).toUint256()] = _gauge;

        gauge_types_[_gauge] = _gaugeType + 1;
        uint256 next_time = (block.timestamp + WEEK) / WEEK * WEEK;

        if (_weight > 0) {
            uint256 _type_weight = _getTypeWeight(_gaugeType);
            uint256 _old_sum = _getSum(_gaugeType);
            uint256 _old_total = _getTotal();

            points_sum[_gaugeType][next_time].bias = _weight + _old_sum;
            time_sum[int256(_gaugeType).toUint256()] = next_time;
            points_total[next_time] = _old_total + _type_weight * _weight;
            timeTotal = next_time;

            points_weight[_gauge][next_time].bias = _weight;
        }

        if (time_sum[int256(_gaugeType).toUint256()] == 0) {
            time_sum[int256(_gaugeType).toUint256()] = next_time;
        }
        time_weight[_gauge] = next_time;

        emit NewGauge(_gauge, _gaugeType, _weight);
    }

    /// @inheritdoc IGaugeController
    function addType(string memory _name, uint256 _weight) external onlyAdmin {
        int128 type_id = n_gauge_types;
        gauge_type_names[type_id] = _name;
        n_gauge_types = type_id + 1;
        if (_weight != 0) {
            _changeTypeWeight(type_id, _weight);
            emit AddType(_name, type_id);
        }
    }

    /// @inheritdoc IGaugeController
    function changeTypeWeight(int128 _typeID, uint256 _weight) external onlyAdmin {
        _changeTypeWeight(_typeID, _weight);
    }

    /// @inheritdoc IGaugeController
    function changeGaugeWeight(address _gauge, uint256 _weight) external onlyAdmin {
        _changeGaugeWeight(_gauge, _weight);
    }

    /// @inheritdoc IGaugeController
    function voteForGaugeWeights(address _gauge, uint256 _userWeight) external {
        if (_userWeight > 10000) revert InvalidUserWeight();
        if (_currentEpoch == 0) revert EpochNotSet();
        if (last_user_vote[msg.sender][_gauge] >= _currentEpoch) revert AlreadyVoted();

        uint256 lock_end = IVotingEscrow(votingEscrow).lockedEnd(msg.sender);
        uint256 next_time = (block.timestamp + WEEK) / WEEK * WEEK;
        if (lock_end <= next_time) revert TokenLockExpiresTooSoon();

        int128 gauge_type = gauge_types_[_gauge] - 1;
        if (gauge_type < 0) revert GaugeNotAdded();

        VotedSlope memory old_slope = vote_user_slopes[msg.sender][_gauge];
        uint256 old_bias = old_slope.slope * _oldDT(old_slope.end, next_time);
        VotedSlope memory new_slope = _createNewSlope(_userWeight, lock_end);

        _updatePowerUsed(new_slope.power, old_slope.power);
        _updateSlopes(_gauge, gauge_type, old_slope, new_slope, next_time, old_bias, lock_end);
        _getTotal();

        vote_user_slopes[msg.sender][_gauge] = new_slope;

        last_user_vote[msg.sender][_gauge] = _currentEpoch;

        emit VoteForGauge(block.timestamp, msg.sender, _gauge, _userWeight);
    }

    /// @inheritdoc IGaugeController
    function initializeEpoch() external onlyAdmin {
        if (_currentEpoch != 0) revert AlreadyInitialized();

        _currentEpoch = 1;
        currentEpochEndTime = block.timestamp + WEEK;

        IPuppet(token).updateMiningParameters();
    }

    /// @inheritdoc IGaugeController
    function advanceEpoch() external {
        if (_currentEpoch == 0) revert EpochNotSet();
        if (block.timestamp < currentEpochEndTime) revert EpochNotEnded();

        uint256 _n_gauges = int256(n_gauges).toUint256();
        for (uint256 i = 0; i < _n_gauges; i++) {
            _getWeight(gauges[i]);
            _getTotal();
        }

        EpochData storage _epochData = epochData[_currentEpoch];
        for (uint256 i = 0; i < _n_gauges; i++) {
            address _gauge = gauges[i];
            if (IScoreGauge(_gauge).isKilled()) continue;

            _epochData.gaugeWeights[_gauge] = _gaugeRelativeWeight(_gauge, block.timestamp);
        }

        _epochData.startTime = currentEpochEndTime - WEEK;
        _epochData.endTime = currentEpochEndTime;
        _epochData.hasEnded = true;

        _currentEpoch += 1;
        currentEpochEndTime += WEEK;
    }


    /// @inheritdoc IGaugeController
    function commitTransferOwnership(address _futureAdmin) external onlyAdmin {
        future_admin = _futureAdmin;

        emit CommitOwnership(_futureAdmin);
    }

    /// @inheritdoc IGaugeController
    function applyTransferOwnership() external onlyAdmin {
        address _admin = future_admin;
        if (_admin == address(0)) revert AdminNotSet();

        admin = _admin;

        emit ApplyOwnership(_admin);
    }

    /// @inheritdoc IGaugeController
    function setWeights(uint256 _profit, uint256 _volume) external onlyAdmin {
        if (_profit + _volume != 10000) revert InvalidWeights();

        _profitWeight = _profit;
        _volumeWeight = _volume;
    }

    // ============================================================================================
    // Internal functions
    // ============================================================================================

    // mutated functions

    /// @notice Fill historic type weights week-over-week for missed checkins and return the type weight for the future week
    /// @param gauge_type Gauge type id
    /// @return Type weight
    function _getTypeWeight(int128 gauge_type) internal returns (uint256) {
        uint256 t = time_type_weight[int256(gauge_type).toUint256()];
        if (t > 0) {
            uint256 w = points_type_weight[gauge_type][t];
            for (uint256 i = 0; i < 500; i++) {
                if (t > block.timestamp) {
                    break;
                }
                t += WEEK;
                points_type_weight[gauge_type][t] = w;
                if (t > block.timestamp) {
                    time_type_weight[int256(gauge_type).toUint256()] = t;
                }
            }
            return w;
        } else {
            return 0;
        }
    }

    /// @notice Fill sum of gauge weights for the same type week-over-week for missed checkins and return the sum for the future week
    /// @param gauge_type Gauge type id
    /// @return Sum of weights
    function _getSum(int128 gauge_type) internal returns (uint256) {
        uint256 t = time_sum[int256(gauge_type).toUint256()];
        if (t > 0) {
            Point memory pt = points_sum[gauge_type][t];
            for (uint256 i = 0; i < 500; i++) {
                if (t > block.timestamp) {
                    break;
                }
                t += WEEK;
                uint256 d_bias = pt.slope * WEEK;
                if (pt.bias > d_bias) {
                    pt.bias -= d_bias;
                    uint256 d_slope = changes_sum[gauge_type][t];
                    pt.slope -= d_slope;
                } else {
                    pt.bias = 0;
                    pt.slope = 0;
                }
                points_sum[gauge_type][t] = pt;
                if (t > block.timestamp) {
                    time_sum[int256(gauge_type).toUint256()] = t;
                }
            }
            return pt.bias;
        } else {
            return 0;
        }
    }

    /// @notice Fill historic total weights week-over-week for missed checkins and return the total for the future week
    /// @return Total weight
    function _getTotal() internal returns (uint256) {
        uint256 t = timeTotal;
        int128 _n_gauge_types = n_gauge_types;
        if (t > block.timestamp) {
            // If we have already checkpointed - still need to change the value
            t -= WEEK;
        }
        uint256 pt = points_total[t];

        for (int128 gauge_type = 0; gauge_type < 100; gauge_type++) {
            if (gauge_type == _n_gauge_types) {
                break;
            }
            _getSum(gauge_type);
            _getTypeWeight(gauge_type);
        }

        for (uint256 i = 0; i < 500; i++) {
            if (t > block.timestamp) {
                break;
            }
            t += WEEK;
            pt = 0;
            // Scales as n_types * n_unchecked_weeks (hopefully 1 at most)
            for (int128 gauge_type = 0; gauge_type < 100; gauge_type++) {
                if (gauge_type == _n_gauge_types) {
                    break;
                }
                uint256 type_sum = points_sum[gauge_type][t].bias;
                uint256 type_weight = points_type_weight[gauge_type][t];
                pt += type_sum * type_weight;
            }
            points_total[t] = pt;

            if (t > block.timestamp) {
                timeTotal = t;
            }
        }
        return pt;
    }

    /// @notice Fill historic gauge weights week-over-week for missed checkins and return the total for the future week
    /// @param gauge_addr Address of the gauge
    /// @return Gauge weight
    function _getWeight(address gauge_addr) internal returns (uint256) {
        uint256 t = time_weight[gauge_addr];
        if (t > 0) {
            Point memory pt = points_weight[gauge_addr][t];
            for (uint256 i = 0; i < 500; i++) {
                if (t > block.timestamp) {
                    break;
                }
                t += WEEK;
                uint256 d_bias = pt.slope * WEEK;
                if (pt.bias > d_bias) {
                    pt.bias -= d_bias;
                    uint256 d_slope = changes_weight[gauge_addr][t];
                    pt.slope -= d_slope;
                } else {
                    pt.bias = 0;
                    pt.slope = 0;
                }
                points_weight[gauge_addr][t] = pt;
                if (t > block.timestamp) {
                    time_weight[gauge_addr] = t;
                }
            }
            return pt.bias;
        } else {
            return 0;
        }
    }

    /// @notice Get Gauge relative weight (not more than 1.0) normalized to 1e18
    //          (e.g. 1.0 == 1e18). Inflation which will be received by it is
    //          inflation_rate * relative_weight / 1e18
    /// @param addr Gauge address
    /// @param time Relative weight at the specified timestamp in the past or present
    /// @return Value of relative weight normalized to 1e18
    function _gaugeRelativeWeight(address addr, uint256 time) internal view returns (uint256) {
        uint256 t = time / WEEK * WEEK;
        uint256 _total_weight = points_total[t];

        if (_total_weight > 0) {
            int128 gauge_type = gauge_types_[addr] - 1;
            uint256 _type_weight = points_type_weight[gauge_type][t];
            uint256 _gauge_weight = points_weight[addr][t].bias;
            return MULTIPLIER * _type_weight * _gauge_weight / _total_weight;
        } else {
            return 0;
        }
    }

    /// @notice Change type weight
    /// @param type_id Type id
    /// @param weight New type weight
    function _changeTypeWeight(int128 type_id, uint256 weight) internal {
        uint256 old_weight = _getTypeWeight(type_id);
        uint256 old_sum = _getSum(type_id);
        uint256 _total_weight = _getTotal();
        uint256 next_time = (block.timestamp + WEEK) / WEEK * WEEK;

        _total_weight = _total_weight + old_sum * weight - old_sum * old_weight;
        points_total[next_time] = _total_weight;
        points_type_weight[type_id][next_time] = weight;
        timeTotal = next_time;
        time_type_weight[int256(type_id).toUint256()] = next_time;

        emit NewTypeWeight(type_id, next_time, weight, _total_weight);
    }

    function _changeGaugeWeight(address addr, uint256 weight) internal {
        // Change gauge weight
        // Only needed when testing in reality
        int128 gauge_type = gauge_types_[addr] - 1;
        uint256 old_gauge_weight = _getWeight(addr);
        uint256 type_weight = _getTypeWeight(gauge_type);
        uint256 old_sum = _getSum(gauge_type);
        uint256 _total_weight = _getTotal();
        uint256 next_time = (block.timestamp + WEEK) / WEEK * WEEK;

        points_weight[addr][next_time].bias = weight;
        time_weight[addr] = next_time;

        uint256 new_sum = old_sum + weight - old_gauge_weight;
        points_sum[gauge_type][next_time].bias = new_sum;
        time_sum[int256(gauge_type).toUint256()] = next_time;

        _total_weight = _total_weight + new_sum * type_weight - old_sum * type_weight;
        points_total[next_time] = _total_weight;
        timeTotal = next_time;

        emit NewGaugeWeight(addr, block.timestamp, weight, _total_weight);
    }

    function _oldDT(uint256 old_slope_end, uint256 next_time) internal pure returns (uint256) {
        if (old_slope_end > next_time) {
            return old_slope_end - next_time;
        } else {
            return 0;
        }
    }

    function _createNewSlope(uint256 _user_weight, uint256 lock_end) internal view returns (VotedSlope memory) {
        return VotedSlope({
            slope: uint256(int256(IVotingEscrow(votingEscrow).getLastUserSlope(msg.sender))) * _user_weight / 10000,
            end: lock_end,
            power: _user_weight
        });
    }

    function _updatePowerUsed(uint256 new_slope_power, uint256 old_slope_power) internal {
        uint256 power_used = vote_user_power[msg.sender];
        power_used = power_used + new_slope_power - old_slope_power;
        vote_user_power[msg.sender] = power_used;
        if (power_used > 10000) revert TooMuchPowerUsed();
    }

    function _updateSlopes(
        address _gauge_addr,
        int128 gauge_type,
        VotedSlope memory old_slope,
        VotedSlope memory new_slope,
        uint256 next_time,
        uint256 old_bias,
        uint256 lock_end
    ) internal {
        uint256 new_dt = lock_end - next_time; // dev: raises when expired
        uint256 new_bias = new_slope.slope * new_dt;

        // Remove old and schedule new slope changes
        // Remove slope changes for old slopes
        // Schedule recording of initial slope for next_time
        uint256 old_weight_bias = _getWeight(_gauge_addr);
        uint256 old_weight_slope = points_weight[_gauge_addr][next_time].slope;
        uint256 old_sum_bias = _getSum(gauge_type);
        uint256 old_sum_slope = points_sum[gauge_type][next_time].slope;

        points_weight[_gauge_addr][next_time].bias = max(old_weight_bias + new_bias, old_bias) - old_bias;
        points_sum[gauge_type][next_time].bias = max(old_sum_bias + new_bias, old_bias) - old_bias;
        if (old_slope.end > next_time) {
            points_weight[_gauge_addr][next_time].slope = max(old_weight_slope + new_slope.slope, old_slope.slope) - old_slope.slope;

            points_sum[gauge_type][next_time].slope = max(old_sum_slope + new_slope.slope, old_slope.slope) - old_slope.slope;
        } else {
            points_weight[_gauge_addr][next_time].slope += new_slope.slope;
            points_sum[gauge_type][next_time].slope += new_slope.slope;
        }
        if (old_slope.end > block.timestamp) {
            // Cancel old slope changes if they still didn't happen
            changes_weight[_gauge_addr][old_slope.end] -= old_slope.slope;
            changes_sum[gauge_type][old_slope.end] -= old_slope.slope;
        }
        // Add slope changes for new slopes
        changes_weight[_gauge_addr][new_slope.end] += new_slope.slope;
        changes_sum[gauge_type][new_slope.end] += new_slope.slope;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }
}