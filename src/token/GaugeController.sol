// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// @title Gauge Controller
// @author Curve Finance
// @license MIT
// @notice Controls liquidity gauges and the issuance of coins through the gauges

// interface VotingEscrow:
//     def get_last_user_slope(addr: address) -> int128: view
//     def locked__end(addr: address) -> uint256: view

contract GaugeContoller {
    // # 7 * 86400 seconds - all future times are rounded by week
    // WEEK: constant(uint256) = 604800
    uint256 constant WEEK = 604800;

    // # Cannot change weight votes more often than once in 10 days
    // WEIGHT_VOTE_DELAY: constant(uint256) = 10 * 86400
    uint256 constant WEIGHT_VOTE_DELAY = 864000;

    // struct Point:
    //     bias: uint256
    //     slope: uint256
    struct Point {
        uint256 bias;
        uint256 slope;
    }

    // struct VotedSlope:
    //     slope: uint256
    //     power: uint256
    //     end: uint256
    struct VotedSlope {
        uint256 slope;
        uint256 power;
        uint256 end;
    }

    // event CommitOwnership:
    //     admin: address
    event CommitOwnership(address admin);

    // event ApplyOwnership:
    //     admin: address
    event ApplyOwnership(address admin);

    // event AddType:
    //     name: String[64]
    //     type_id: int128
    event AddType(string name, int128 type_id);

    // event NewTypeWeight:
    //     type_id: int128
    //     time: uint256
    //     weight: uint256
    //     total_weight: uint256
    event NewTypeWeight(int128 type_id, uint256 time, uint256 weight, uint256 total_weight);

    // event NewGaugeWeight:
    //     gauge_address: address
    //     time: uint256
    //     weight: uint256
    //     total_weight: uint256
    event NewGaugeWeight(address gauge_address, uint256 time, uint256 weight, uint256 total_weight);

    // event VoteForGauge:
    //     time: uint256
    //     user: address
    //     gauge_addr: address
    //     weight: uint256
    event VoteForGauge(uint256 time, address user, address gauge_addr, uint256 weight);

    // event NewGauge:
    //     addr: address
    //     gauge_type: int128
    //     weight: uint256
    event NewGauge(address addr, int128 gauge_type, uint256 weight);

    // MULTIPLIER: constant(uint256) = 10 ** 18
    uint256 constant MULTIPLIER = 10 ** 18;

    // admin: public(address)  # Can and will be a smart contract
    address public admin; // Can and will be a smart contract
    // future_admin: public(address)  # Can and will be a smart contract
    address public future_admin; // Can and will be a smart contract

    // token: public(address)  # CRV token
    address public token; // CRV token
    // voting_escrow: public(address)  # Voting escrow
    address public voting_escrow; // Voting escrow

    // Gauge parameters
    // All numbers are "fixed point" on the basis of 1e18
    // n_gauge_types: public(int128)
    int128 public n_gauge_types;
    // n_gauges: public(int128)
    int128 public n_gauges;
    // gauge_type_names: public(HashMap[int128, String[64]])
    mapping(int128 => string) public gauge_type_names;

    // # Needed for enumeration
    // gauges: public(address[1000000000])
    address[1000000000] public gauges;

    // we increment values by 1 prior to storing them here so we can rely on a value
    // of zero as meaning the gauge has not been set
    // gauge_types_: HashMap[address, int128]
    mapping(address => int128) public gauge_types_;

    // vote_user_slopes: public(HashMap[address, HashMap[address, VotedSlope]])  # user -> gauge_addr -> VotedSlope
    mapping(address => mapping(address => VotedSlope)) public vote_user_slopes; // user -> gauge_addr -> VotedSlope
    // vote_user_power: public(HashMap[address, uint256])  # Total vote power used by user
    mapping(address => uint256) public vote_user_power; // Total vote power used by user
    // last_user_vote: public(HashMap[address, HashMap[address, uint256]])  # Last user vote's timestamp for each gauge address
    mapping(address => mapping(address => uint256)) public last_user_vote; // Last user vote's timestamp for each gauge address

    // Past and scheduled points for gauge weight, sum of weights per type, total weight
    // Point is for bias+slope
    // changes_* are for changes in slope
    // time_* are for the last change timestamp
    // timestamps are rounded to whole weeks

    // points_weight: public(HashMap[address, HashMap[uint256, Point]])  # gauge_addr -> time -> Point
    mapping(address => mapping(uint256 => Point)) public points_weight; // gauge_addr -> time -> Point
    // changes_weight: HashMap[address, HashMap[uint256, uint256]]  # gauge_addr -> time -> slope
    mapping(address => mapping(uint256 => uint256)) public changes_weight; // gauge_addr -> time -> slope
    // time_weight: public(HashMap[address, uint256])  # gauge_addr -> last scheduled time (next week)
    mapping(address => uint256) public time_weight; // gauge_addr -> last scheduled time (next week)

    // points_sum: public(HashMap[int128, HashMap[uint256, Point]])  # type_id -> time -> Point
    mapping(int128 => mapping(uint256 => Point)) public points_sum; // type_id -> time -> Point
    // changes_sum: HashMap[int128, HashMap[uint256, uint256]]  # type_id -> time -> slope
    mapping(int128 => mapping(uint256 => uint256)) public changes_sum; // type_id -> time -> slope
    // time_sum: public(uint256[1000000000])  # type_id -> last scheduled time (next week)
    uint256[1000000000] public time_sum; // type_id -> last scheduled time (next week)

    // points_total: public(HashMap[uint256, uint256])  # time -> total weight
    mapping(uint256 => uint256) public points_total; // time -> total weight
    // time_total: public(uint256)  # last scheduled time
    uint256 public time_total; // last scheduled time

    // points_type_weight: public(HashMap[int128, HashMap[uint256, uint256]])  # type_id -> time -> type weight
    mapping(int128 => mapping(uint256 => uint256)) public points_type_weight; // type_id -> time -> type weight
    // time_type_weight: public(uint256[1000000000])  # type_id -> last scheduled time (next week)
    uint256[1000000000] public time_type_weight; // type_id -> last scheduled time (next week)

    // @external
    // def __init__(_token: address, _voting_escrow: address):
    //     assert _token != ZERO_ADDRESS
    //     assert _voting_escrow != ZERO_ADDRESS

    //     self.admin = msg.sender
    //     self.token = _token
    //     self.voting_escrow = _voting_escrow
    //     self.time_total = block.timestamp / WEEK * WEEK
    /// @notice Contract constructor
    /// @param _token `ERC20CRV` contract address
    /// @param _voting_escrow `VotingEscrow` contract address
    constructor(address _token, address _voting_escrow) {
        require(_token != address(0), "token address cannot be 0");
        require(_voting_escrow != address(0), "voting escrow address cannot be 0");

        admin = msg.sender;
        token = _token;
        voting_escrow = _voting_escrow;
        time_total = block.timestamp / WEEK * WEEK;
    }

    // @external
    // def commit_transfer_ownership(addr: address):
    //     assert msg.sender == self.admin  # dev: admin only
    //     self.future_admin = addr
    //     log CommitOwnership(addr)
    /// @notice Transfer ownership of GaugeController to `addr`
    /// @param addr Address to have ownership transferred to
    function commit_transfer_ownership(address addr) external {
        require(msg.sender == admin, "admin only");
        future_admin = addr;
        emit CommitOwnership(addr);
    }

    // @external
    // def apply_transfer_ownership():
    //     assert msg.sender == self.admin  # dev: admin only
    //     _admin: address = self.future_admin
    //     assert _admin != ZERO_ADDRESS  # dev: admin not set
    //     self.admin = _admin
    //     log ApplyOwnership(_admin)
    /// @notice Apply pending ownership transfer
    function apply_transfer_ownership() external {
        require(msg.sender == admin, "admin only");
        address _admin = future_admin;
        require(_admin != address(0), "admin not set");
        admin = _admin;
        emit ApplyOwnership(_admin);
    }

    // @external
    // @view
    // def gauge_types(_addr: address) -> int128:
    //     gauge_type: int128 = self.gauge_types_[_addr]
    //     assert gauge_type != 0

    //     return gauge_type - 1
    /// @notice Get gauge type for address
    /// @param _addr Gauge address
    /// @return Gauge type id
    function gauge_types(address _addr) external view returns (int128) {
        int128 gauge_type = gauge_types_[_addr];
        require(gauge_type != 0, "gauge type not set");

        return gauge_type - 1;
    }

    // @internal
    // def _get_type_weight(gauge_type: int128) -> uint256:
    //     t: uint256 = self.time_type_weight[gauge_type]
    //     if t > 0:
    //         w: uint256 = self.points_type_weight[gauge_type][t]
    //         for i in range(500):
    //             if t > block.timestamp:
    //                 break
    //             t += WEEK
    //             self.points_type_weight[gauge_type][t] = w
    //             if t > block.timestamp:
    //                 self.time_type_weight[gauge_type] = t
    //         return w
    //     else:
    //         return 0
    /// @notice Fill historic type weights week-over-week for missed checkins and return the type weight for the future week
    /// @param gauge_type Gauge type id
    /// @return Type weight
    function _get_type_weight(int128 gauge_type) internal returns (uint256) {
        uint256 t = time_type_weight[uint256(int256(gauge_type))]; // todo - make sure this conversion is correct
        if (t > 0) {
            uint256 w = points_type_weight[gauge_type][t];
            for (uint256 i = 0; i < 500; i++) {
                if (t > block.timestamp) {
                    break;
                }
                t += WEEK;
                points_type_weight[gauge_type][t] = w;
                if (t > block.timestamp) {
                    time_type_weight[uint256(int256(gauge_type))] = t; // todo - make sure this conversion is correct
                }
            }
            return w;
        } else {
            return 0;
        }
    }

    // @internal
    // def _get_sum(gauge_type: int128) -> uint256:
    //     t: uint256 = self.time_sum[gauge_type]
    //     if t > 0:
    //         pt: Point = self.points_sum[gauge_type][t]
    //         for i in range(500):
    //             if t > block.timestamp:
    //                 break
    //             t += WEEK
    //             d_bias: uint256 = pt.slope * WEEK
    //             if pt.bias > d_bias:
    //                 pt.bias -= d_bias
    //                 d_slope: uint256 = self.changes_sum[gauge_type][t]
    //                 pt.slope -= d_slope
    //             else:
    //                 pt.bias = 0
    //                 pt.slope = 0
    //             self.points_sum[gauge_type][t] = pt
    //             if t > block.timestamp:
    //                 self.time_sum[gauge_type] = t
    //         return pt.bias
    //     else:
    //         return 0
    /// @notice Fill sum of gauge weights for the same type week-over-week for missed checkins and return the sum for the future week
    /// @param gauge_type Gauge type id
    /// @return Sum of weights
    function _get_sum(int128 gauge_type) internal returns (uint256) {
        uint256 t = time_sum[uint256(int256(gauge_type))]; // todo - make sure this conversion is correct
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
                    time_sum[uint256(int256(gauge_type))] = t; // todo - make sure this conversion is correct
                }
            }
            return pt.bias;
        } else {
            return 0;
        }
    }

    // @internal
    // def _get_total() -> uint256:
    //     t: uint256 = self.time_total
    //     _n_gauge_types: int128 = self.n_gauge_types
    //     if t > block.timestamp:
    //         # If we have already checkpointed - still need to change the value
    //         t -= WEEK
    //     pt: uint256 = self.points_total[t]

    //     for gauge_type in range(100):
    //         if gauge_type == _n_gauge_types:
    //             break
    //         self._get_sum(gauge_type)
    //         self._get_type_weight(gauge_type)

    //     for i in range(500):
    //         if t > block.timestamp:
    //             break
    //         t += WEEK
    //         pt = 0
    //         # Scales as n_types * n_unchecked_weeks (hopefully 1 at most)
    //         for gauge_type in range(100):
    //             if gauge_type == _n_gauge_types:
    //                 break
    //             type_sum: uint256 = self.points_sum[gauge_type][t].bias
    //             type_weight: uint256 = self.points_type_weight[gauge_type][t]
    //             pt += type_sum * type_weight
    //         self.points_total[t] = pt

    //         if t > block.timestamp:
    //             self.time_total = t
    //     return pt
    /// @notice Fill historic total weights week-over-week for missed checkins and return the total for the future week
    /// @return Total weight
    function _get_total() internal returns (uint256) {
        uint256 t = time_total;
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
            _get_sum(gauge_type);
            _get_type_weight(gauge_type);
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
                time_total = t;
            }
        }
        return pt;
    }

    // @internal
    // def _get_weight(gauge_addr: address) -> uint256:
    //     t: uint256 = self.time_weight[gauge_addr]
    //     if t > 0:
    //         pt: Point = self.points_weight[gauge_addr][t]
    //         for i in range(500):
    //             if t > block.timestamp:
    //                 break
    //             t += WEEK
    //             d_bias: uint256 = pt.slope * WEEK
    //             if pt.bias > d_bias:
    //                 pt.bias -= d_bias
    //                 d_slope: uint256 = self.changes_weight[gauge_addr][t]
    //                 pt.slope -= d_slope
    //             else:
    //                 pt.bias = 0
    //                 pt.slope = 0
    //             self.points_weight[gauge_addr][t] = pt
    //             if t > block.timestamp:
    //                 self.time_weight[gauge_addr] = t
    //         return pt.bias
    //     else:
    //         return 0
    /// @notice Fill historic gauge weights week-over-week for missed checkins and return the total for the future week
    /// @param gauge_addr Address of the gauge
    /// @return Gauge weight
    function _get_weight(address gauge_addr) internal returns (uint256) {
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

    // @external
    // def add_gauge(addr: address, gauge_type: int128, weight: uint256 = 0):
    //     assert msg.sender == self.admin
    //     assert (gauge_type >= 0) and (gauge_type < self.n_gauge_types)
    //     assert self.gauge_types_[addr] == 0  # dev: cannot add the same gauge twice

    //     n: int128 = self.n_gauges
    //     self.n_gauges = n + 1
    //     self.gauges[n] = addr

    //     self.gauge_types_[addr] = gauge_type + 1
    //     next_time: uint256 = (block.timestamp + WEEK) / WEEK * WEEK

    //     if weight > 0:
    //         _type_weight: uint256 = self._get_type_weight(gauge_type)
    //         _old_sum: uint256 = self._get_sum(gauge_type)
    //         _old_total: uint256 = self._get_total()

    //         self.points_sum[gauge_type][next_time].bias = weight + _old_sum
    //         self.time_sum[gauge_type] = next_time
    //         self.points_total[next_time] = _old_total + _type_weight * weight
    //         self.time_total = next_time

    //         self.points_weight[addr][next_time].bias = weight

    //     if self.time_sum[gauge_type] == 0:
    //         self.time_sum[gauge_type] = next_time
    //     self.time_weight[addr] = next_time

    //     log NewGauge(addr, gauge_type, weight)
    /// @notice Add gauge `addr` of type `gauge_type` with weight `weight`
    /// @param addr Gauge address
    /// @param gauge_type Gauge type
    /// @param weight Gauge weight
    function add_gauge(address addr, int128 gauge_type, uint256 weight) external {
        require(msg.sender == admin, "dev: admin only");
        require(gauge_type >= 0 && gauge_type < n_gauge_types, "dev: invalid gauge type");
        require(gauge_types_[addr] == 0, "dev: cannot add the same gauge twice");

        int128 n = n_gauges;
        n_gauges = n + 1;
        gauges[uint256(int256(n))] = addr; // todo - check that conversion is correct

        gauge_types_[addr] = gauge_type + 1;
        uint256 next_time = (block.timestamp + WEEK) / WEEK * WEEK;

        if (weight > 0) {
            uint256 _type_weight = _get_type_weight(gauge_type);
            uint256 _old_sum = _get_sum(gauge_type);
            uint256 _old_total = _get_total();

            points_sum[gauge_type][next_time].bias = weight + _old_sum;
            time_sum[uint256(int256(gauge_type))] = next_time; // todo - check that conversion is correct
            points_total[next_time] = _old_total + _type_weight * weight;
            time_total = next_time;

            points_weight[addr][next_time].bias = weight;
        }

        if (time_sum[uint256(int256(gauge_type))] == 0) { // todo - check that conversion is correct
            time_sum[uint256(int256(gauge_type))] = next_time; // todo - check that conversion is correct
        }
        time_weight[addr] = next_time;

        emit NewGauge(addr, gauge_type, weight);
    }

    // @external
    // def checkpoint():
    //     self._get_total()
    /// @notice Checkpoint to fill data common for all gauges
    function checkpoint() external {
        _get_total();
    }

    // @external
    // def checkpoint_gauge(addr: address):
    //     self._get_weight(addr)
    //     self._get_total()
    /// @notice Checkpoint to fill data for both a specific gauge and common for all gauges
    /// @param addr Gauge address
    function checkpoint_gauge(address addr) external {
        _get_weight(addr);
        _get_total();
    }

    // @internal
    // @view
    // def _gauge_relative_weight(addr: address, time: uint256) -> uint256:
    //     t: uint256 = time / WEEK * WEEK
    //     _total_weight: uint256 = self.points_total[t]

    //     if _total_weight > 0:
    //         gauge_type: int128 = self.gauge_types_[addr] - 1
    //         _type_weight: uint256 = self.points_type_weight[gauge_type][t]
    //         _gauge_weight: uint256 = self.points_weight[addr][t].bias
    //         return MULTIPLIER * _type_weight * _gauge_weight / _total_weight

    //     else:
    //         return 0
    /// @notice Get Gauge relative weight (not more than 1.0) normalized to 1e18
    //          (e.g. 1.0 == 1e18). Inflation which will be received by it is
    //          inflation_rate * relative_weight / 1e18
    /// @param addr Gauge address
    /// @param time Relative weight at the specified timestamp in the past or present
    /// @return Value of relative weight normalized to 1e18
    function _gauge_relative_weight(address addr, uint256 time) internal view returns (uint256) {
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

    // @external
    // @view
    // def gauge_relative_weight(addr: address, time: uint256 = block.timestamp) -> uint256:
    //     return self._gauge_relative_weight(addr, time)
    /// @notice Get Gauge relative weight (not more than 1.0) normalized to 1e18
    //          (e.g. 1.0 == 1e18). Inflation which will be received by it is
    //          inflation_rate * relative_weight / 1e18
    /// @param addr Gauge address
    /// @param time Relative weight at the specified timestamp in the past or present
    /// @return Value of relative weight normalized to 1e18
    function gauge_relative_weight(address addr, uint256 time) external view returns (uint256) {
        return _gauge_relative_weight(addr, time);
    }

    // @external
    // def gauge_relative_weight_write(addr: address, time: uint256 = block.timestamp) -> uint256:
    //     self._get_weight(addr)
    //     self._get_total()  # Also calculates get_sum
    //     return self._gauge_relative_weight(addr, time)
    /// @notice Get gauge weight normalized to 1e18 and also fill all the unfilled values for type and gauge records
    /// @dev Any address can call, however nothing is recorded if the values are filled already
    /// @param addr Gauge address
    /// @param time Relative weight at the specified timestamp in the past or present
    /// @return Value of relative weight normalized to 1e18
    function gauge_relative_weight_write(address addr, uint256 time) external returns (uint256) {
        _get_weight(addr);
        _get_total();
        return _gauge_relative_weight(addr, time);
    }

    // @internal
    // def _change_type_weight(type_id: int128, weight: uint256):
    //     old_weight: uint256 = self._get_type_weight(type_id)
    //     old_sum: uint256 = self._get_sum(type_id)
    //     _total_weight: uint256 = self._get_total()
    //     next_time: uint256 = (block.timestamp + WEEK) / WEEK * WEEK

    //     _total_weight = _total_weight + old_sum * weight - old_sum * old_weight
    //     self.points_total[next_time] = _total_weight
    //     self.points_type_weight[type_id][next_time] = weight
    //     self.time_total = next_time
    //     self.time_type_weight[type_id] = next_time

    //     log NewTypeWeight(type_id, next_time, weight, _total_weight)
    /// @notice Change type weight
    /// @param type_id Type id
    /// @param weight New type weight
    function _change_type_weight(int128 type_id, uint256 weight) internal {
        uint256 old_weight = _get_type_weight(type_id);
        uint256 old_sum = _get_sum(type_id);
        uint256 _total_weight = _get_total();
        uint256 next_time = (block.timestamp + WEEK) / WEEK * WEEK;

        _total_weight = _total_weight + old_sum * weight - old_sum * old_weight;
        points_total[next_time] = _total_weight;
        points_type_weight[type_id][next_time] = weight;
        time_total = next_time;
        time_type_weight[uint256(int256(type_id))] = next_time; // todo - make sure this conversion is correct

        emit NewTypeWeight(type_id, next_time, weight, _total_weight);
    }

    // @external
    // def add_type(_name: String[64], weight: uint256 = 0):
    //     assert msg.sender == self.admin
    //     type_id: int128 = self.n_gauge_types
    //     self.gauge_type_names[type_id] = _name
    //     self.n_gauge_types = type_id + 1
    //     if weight != 0:
    //         self._change_type_weight(type_id, weight)
    //         log AddType(_name, type_id)
    /// @notice Add gauge type with name `_name` and weight `weight`
    /// @param _name Name of gauge type
    /// @param weight Weight of gauge type
    function add_type(string memory _name, uint256 weight) external {
        require(msg.sender == admin, "only admin");
        int128 type_id = n_gauge_types;
        gauge_type_names[type_id] = _name;
        n_gauge_types = type_id + 1;
        if (weight != 0) {
            _change_type_weight(type_id, weight);
            emit AddType(_name, type_id);
        }
    }

    // @external
    // def change_type_weight(type_id: int128, weight: uint256):
    //     assert msg.sender == self.admin
    //     self._change_type_weight(type_id, weight)
    /// @notice Change gauge type `type_id` weight to `weight`
    /// @param type_id Gauge type id
    /// @param weight New Gauge weight
    function change_type_weight(int128 type_id, uint256 weight) external {
        require(msg.sender == admin, "only admin");
        _change_type_weight(type_id, weight);
    }

    // @internal
    // def _change_gauge_weight(addr: address, weight: uint256):
    //     # Change gauge weight
    //     # Only needed when testing in reality
    //     gauge_type: int128 = self.gauge_types_[addr] - 1
    //     old_gauge_weight: uint256 = self._get_weight(addr)
    //     type_weight: uint256 = self._get_type_weight(gauge_type)
    //     old_sum: uint256 = self._get_sum(gauge_type)
    //     _total_weight: uint256 = self._get_total()
    //     next_time: uint256 = (block.timestamp + WEEK) / WEEK * WEEK

    //     self.points_weight[addr][next_time].bias = weight
    //     self.time_weight[addr] = next_time

    //     new_sum: uint256 = old_sum + weight - old_gauge_weight
    //     self.points_sum[gauge_type][next_time].bias = new_sum
    //     self.time_sum[gauge_type] = next_time

    //     _total_weight = _total_weight + new_sum * type_weight - old_sum * type_weight
    //     self.points_total[next_time] = _total_weight
    //     self.time_total = next_time

    //     log NewGaugeWeight(addr, block.timestamp, weight, _total_weight)
    function _change_gauge_weight(address addr, uint256 weight) internal {
        // Change gauge weight
        // Only needed when testing in reality
        int128 gauge_type = gauge_types_[addr] - 1;
        uint256 old_gauge_weight = _get_weight(addr);
        uint256 type_weight = _get_type_weight(gauge_type);
        uint256 old_sum = _get_sum(gauge_type);
        uint256 _total_weight = _get_total();
        uint256 next_time = (block.timestamp + WEEK) / WEEK * WEEK;

        points_weight[addr][next_time].bias = weight;
        time_weight[addr] = next_time;

        uint256 new_sum = old_sum + weight - old_gauge_weight;
        points_sum[gauge_type][next_time].bias = new_sum;
        time_sum[uint256(int256(gauge_type))] = next_time; // todo - make sure this conversion is correct

        _total_weight = _total_weight + new_sum * type_weight - old_sum * type_weight;
        points_total[next_time] = _total_weight;
        time_total = next_time;

        emit NewGaugeWeight(addr, block.timestamp, weight, _total_weight);
    }

    // @external
    // def change_gauge_weight(addr: address, weight: uint256):
    //     assert msg.sender == self.admin
    //     self._change_gauge_weight(addr, weight)
    /// @notice Change weight of gauge `addr` to `weight`
    /// @param addr `GaugeController` contract address
    /// @param weight New Gauge weight
    function change_gauge_weight(address addr, uint256 weight) external {
        require(msg.sender == admin, "only admin");
        _change_gauge_weight(addr, weight);
    }

    // @external
    // def vote_for_gauge_weights(_gauge_addr: address, _user_weight: uint256):
    //     escrow: address = self.voting_escrow
    //     slope: uint256 = convert(VotingEscrow(escrow).get_last_user_slope(msg.sender), uint256)
    //     lock_end: uint256 = VotingEscrow(escrow).locked__end(msg.sender)
    //     _n_gauges: int128 = self.n_gauges
    //     next_time: uint256 = (block.timestamp + WEEK) / WEEK * WEEK
    //     assert lock_end > next_time, "Your token lock expires too soon"
    //     assert (_user_weight >= 0) and (_user_weight <= 10000), "You used all your voting power"
    //     assert block.timestamp >= self.last_user_vote[msg.sender][_gauge_addr] + WEIGHT_VOTE_DELAY, "Cannot vote so often"

    //     gauge_type: int128 = self.gauge_types_[_gauge_addr] - 1
    //     assert gauge_type >= 0, "Gauge not added"
    //     # Prepare slopes and biases in memory
    //     old_slope: VotedSlope = self.vote_user_slopes[msg.sender][_gauge_addr]
    //     old_dt: uint256 = 0
    //     if old_slope.end > next_time:
    //         old_dt = old_slope.end - next_time
    //     old_bias: uint256 = old_slope.slope * old_dt
    //     new_slope: VotedSlope = VotedSlope({
    //         slope: slope * _user_weight / 10000,
    //         end: lock_end,
    //         power: _user_weight
    //     })
    //     new_dt: uint256 = lock_end - next_time  # dev: raises when expired
    //     new_bias: uint256 = new_slope.slope * new_dt

    //     # Check and update powers (weights) used
    //     power_used: uint256 = self.vote_user_power[msg.sender]
    //     power_used = power_used + new_slope.power - old_slope.power
    //     self.vote_user_power[msg.sender] = power_used
    //     assert (power_used >= 0) and (power_used <= 10000), 'Used too much power'

    //     ## Remove old and schedule new slope changes
    //     # Remove slope changes for old slopes
    //     # Schedule recording of initial slope for next_time
    //     old_weight_bias: uint256 = self._get_weight(_gauge_addr)
    //     old_weight_slope: uint256 = self.points_weight[_gauge_addr][next_time].slope
    //     old_sum_bias: uint256 = self._get_sum(gauge_type)
    //     old_sum_slope: uint256 = self.points_sum[gauge_type][next_time].slope

    //     self.points_weight[_gauge_addr][next_time].bias = max(old_weight_bias + new_bias, old_bias) - old_bias
    //     self.points_sum[gauge_type][next_time].bias = max(old_sum_bias + new_bias, old_bias) - old_bias
    //     if old_slope.end > next_time:
    //         self.points_weight[_gauge_addr][next_time].slope = max(old_weight_slope + new_slope.slope, old_slope.slope) - old_slope.slope
    //         self.points_sum[gauge_type][next_time].slope = max(old_sum_slope + new_slope.slope, old_slope.slope) - old_slope.slope
    //     else:
    //         self.points_weight[_gauge_addr][next_time].slope += new_slope.slope
    //         self.points_sum[gauge_type][next_time].slope += new_slope.slope
    //     if old_slope.end > block.timestamp:
    //         # Cancel old slope changes if they still didn't happen
    //         self.changes_weight[_gauge_addr][old_slope.end] -= old_slope.slope
    //         self.changes_sum[gauge_type][old_slope.end] -= old_slope.slope
    //     # Add slope changes for new slopes
    //     self.changes_weight[_gauge_addr][new_slope.end] += new_slope.slope
    //     self.changes_sum[gauge_type][new_slope.end] += new_slope.slope

    //     self._get_total()

    //     self.vote_user_slopes[msg.sender][_gauge_addr] = new_slope

    //     # Record last action time
    //     self.last_user_vote[msg.sender][_gauge_addr] = block.timestamp

    //     log VoteForGauge(block.timestamp, msg.sender, _gauge_addr, _user_weight)
    /// @notice Allocate voting power for changing pool weights
    /// @param _gauge_addr Gauge which `msg.sender` votes for
    /// @param _user_weight Weight for a gauge in bps (units of 0.01%). Minimal is 0.01%. Ignored if 0
    function vote_for_gauge_weights(address _gauge_addr, uint256 _user_weight) external {
        address escrow = voting_escrow;
        uint256 slope = IVotingEscrow(escrow).get_last_user_slope(msg.sender); // todo add interface
        uint256 lock_end = IVotingEscrow(escrow).locked__end(msg.sender); // todo add interface
        int128 _n_gauges = n_gauges;
        uint256 next_time = (block.timestamp + WEEK) / WEEK * WEEK;
        require(lock_end > next_time, "Your token lock expires too soon");
        require(_user_weight >= 0 && _user_weight <= 10000, "You used all your voting power");
        require(block.timestamp >= last_user_vote[msg.sender][_gauge_addr] + WEIGHT_VOTE_DELAY, "Cannot vote so often");

        int128 gauge_type = gauge_types_[_gauge_addr] - 1;
        require(gauge_type >= 0, "Gauge not added");
        // Prepare slopes and biases in memory
        VotedSlope memory old_slope = vote_user_slopes[msg.sender][_gauge_addr];
        uint256 old_dt = 0;
        if (old_slope.end > next_time) {
            old_dt = old_slope.end - next_time;
        }
        uint256 old_bias = old_slope.slope * old_dt;
        VotedSlope memory new_slope = VotedSlope({
            slope: slope * _user_weight / 10000,
            end: lock_end,
            power: _user_weight
        });
        uint256 new_dt = lock_end - next_time; // dev: raises when expired
        uint256 new_bias = new_slope.slope * new_dt;

        // Check and update powers (weights) used
        uint256 power_used = vote_user_power[msg.sender];
        power_used = power_used + new_slope.power - old_slope.power;
        vote_user_power[msg.sender] = power_used;
        require(power_used >= 0 && power_used <= 10000, "Used too much power");

        // Remove old and schedule new slope changes
        // Remove slope changes for old slopes
        // Schedule recording of initial slope for next_time
        uint256 old_weight_bias = _get_weight(_gauge_addr);
        uint256 old_weight_slope = points_weight[_gauge_addr][next_time].slope;
        uint256 old_sum_bias = _get_sum(gauge_type);
        uint256 old_sum_slope = points_sum[gauge_type][next_time].slope;

        points_weight[_gauge_addr][next_time].bias = max(old_weight_bias + new_bias, old_bias) - old_bias; // todo implement max
        points_sum[gauge_type][next_time].bias = max(old_sum_bias + new_bias, old_bias) - old_bias; // todo implement max
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

        _get_total();

        vote_user_slopes[msg.sender][_gauge_addr] = new_slope;

        // Record last action time
        last_user_vote[msg.sender][_gauge_addr] = block.timestamp;

        emit VoteForGauge(block.timestamp, msg.sender, _gauge_addr, _user_weight);
    }

    // @external
    // @view
    // def get_gauge_weight(addr: address) -> uint256:
    //     return self.points_weight[addr][self.time_weight[addr]].bias
    /// @notice Get current gauge weight
    /// @param addr Gauge address
    /// @return Gauge weight
    function get_gauge_weight(address addr) external view returns (uint256) {
        return points_weight[addr][time_weight[addr]].bias;
    }

    // @external
    // @view
    // def get_type_weight(type_id: int128) -> uint256:
    //     return self.points_type_weight[type_id][self.time_type_weight[type_id]]
    /// @notice Get current type weight
    /// @param type_id Type id
    /// @return Type weight
    function get_type_weight(int128 type_id) external view returns (uint256) {
        return points_type_weight[type_id][time_type_weight[type_id]];
    }

    // @external
    // @view
    // def get_total_weight() -> uint256:
    //     return self.points_total[self.time_total]
    /// @notice Get current total (type-weighted) weight
    /// @return Total weight
    function get_total_weight() external view returns (uint256) {
        return points_total[time_total];
    }

    // @external
    // @view
    // def get_weights_sum_per_type(type_id: int128) -> uint256:
    //     return self.points_sum[type_id][self.time_sum[type_id]].bias
    /// @notice Get sum of gauge weights per type
    /// @param type_id Type id
    /// @return Sum of gauge weights
    function get_weights_sum_per_type(int128 type_id) external view returns (uint256) {
        return points_sum[type_id][time_sum[type_id]].bias;
    }
}