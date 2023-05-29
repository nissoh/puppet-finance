// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RevenueDistributor is ReentrancyGuard, Auth {

    using Address for address payable;
    using SafeERC20 for IERC20;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    constructor(Authority _authority) Auth(address(0), _authority) {}

    // ============================================================================================
    // Authority Functions
    // ============================================================================================

    function claim(address[] memory _tokens, address _receiver) external nonReentrant requiresAuth {
        for (uint256 i = 0; i < _tokens.length; i++) {
            uint256 _tokenBalance = IERC20(_tokens[i]).balanceOf(address(this));
            if (_tokenBalance > 0) {
                IERC20(_tokens[i]).safeTransfer(_receiver, _tokenBalance);

                emit Claimed(_tokens[i], _receiver, _tokenBalance);
            }
        }

        uint256 _ethBalance = address(this).balance;
        if (_ethBalance > 0) {
            payable(_receiver).sendValue(_ethBalance);

            emit ClaimedETH(_receiver, _ethBalance);
        }
    }

    // ============================================================================================
    // Receive Function
    // ============================================================================================
 
    receive() external payable {}

    // ============================================================================================
    // Events
    // ============================================================================================

    event Claimed(address indexed token, address indexed receiver, uint256 amount);
    event ClaimedETH(address indexed receiver, uint256 amount);
}