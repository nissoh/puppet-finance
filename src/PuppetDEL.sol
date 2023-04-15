// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract Puppet {}

//     // playing with contracts
//     // GMX - long ETH 2x using ETH as collateral using https://arbiscan.io/address/0xaBF1d1251Edb352f5ce601d644D44f78BDA90693:
//     // 1. approve plugin (txn hash https://arbiscan.io/tx/0xff7f1e22f0985e5bbfb064f82588938f562e3f9882c5cf57bd7fe7126dae6596) --> approve the address of the PositionRouter
//     // 2. createIncreasePositionETH (txn hash https://arbiscan.io/tx/0xbb36ce8459e5b8333adde68953622ec1d6026e542120629bbeeb04daff16f6a3)
//     // 3. createIncreasePositionETH (just added collateral to exsisting position) (txn hash https://arbiscan.io/tx/0x4ae678f80b38bc4d1396052d37ea6b6fa9627dd859307f630fccaa9a55ba3fec)
//     // 4. *removing collateral* createDecreasePosition (txn hash https://arbiscan.io/tx/0xddeac229f6190861f93185acb69111fe963ad9de282a52ad6da23300a1ac1539)
//     // 5. *closing position* createDecreasePosition (txn hash https://arbiscan.io/tx/0x0aa093c2709d3f2a42b7c41345cfa4588e736bb5d98b2d0eca47f029f74a930e)

//     // docs
//     // https://gmxio.gitbook.io/gmx/contracts#opening-increasing-a-position

//     // user flow
//     // 1. trader registers
//     // 2. investors can now select the trader and deposit funds
//     // 3. trader can now open a position using the funds deposited by him + investors that have selected him
//     // 4. investor can withdraw funds only if trader has closed the position

//     // questions:
//     // 1. require the trader's collateral to be x% of the total funds deposited by investors? (e.g. in order to use 1000$ of investors funds, trader will need 10% so 100$)
//     // 2. cut trader collateral on loss?
//     // 3. limit performance fee to x% of TVL? (to disincentivize over risk taking)
//     //
//     // one of the first 2 is a must in order to allign incentives on all scenarios. ideally both. but probably only #1 makes sense here
//     // #3 might not make sense here

//     struct Vault {
//         uint256 totalAssets;
//         uint256 totalShares;
//         bool isPositionOpen;
//         bool isActive;
//     }

//     // trader => token => isLong => vault
//     mapping (address => mapping (address => mapping (bool => Vault))) traderVaults;

//     // investor => trader => token => isLong => shares
//     mapping (address => mapping (address => mapping (bool => uint256))) investorShares;

//     //
//     // -------------------------------------- EXTERNAL --------------------------------------
//     //

//     function registerVault(address _trader, address _token, bool _isLong) external {
//         if (traderVaults[_trader][_token][_isLong].isActive) revert(); // vault already registered
//         if (!tokenWhitelist[_token]) revert();
        
//         traderVaults[_trader][_token][_isLong].isActive = true;
//     }

//     function deposit(address[] memory _traders, uint256[] memory _amounts, address _token, address _receiver, bool _isLong) external {
//         if (_traders.length != _amounts.length) revert(); // arrays not the same length

//         uint256 _totalAmount;
//         for (uint256 i = 0; i < _traders.length; i++) {
//             _deposit(_traders[i], _token, msg.sender, _receiver, _amounts[i], _isLong);
//             _totalAmount += _amounts[i];
//         }

//         IERC20(_token).transferFrom(msg.sender, address(this), _totalAmount);
//     }

//     //
//     // -------------------------------------- INTERNAL --------------------------------------
//     //
    
//     function _deposit(address _trader, address _token, address _caller, address _receiver, uint256 _assets, bool _isLong) internal override {
//         Vault storage _vault = traderVaults[_trader][_token][_isLong];

//         if (!_vault.isActive) revert();
//         if (_vault.isPositionOpen) revert();
//         if (pauseDeposit) revert DepositPaused();
//         if (_receiver == address(0)) revert ZeroAddress();
//         if (!(_assets > 0)) revert ZeroAmount();

//         uint256 _shares = convertToShares(_vault.totalAssets, _vault.totalShares, _assets);
//         if (!(_shares > 0)) revert ZeroAmount();

//         investorShares[_receiver][_trader][_token][_isLong] += _shares;

//         _vault.totalShares += _shares;
//         _vault.totalAssets += _assets;

//         emit Deposit(_trader, _token, _isLong, _caller, _receiver, _assets, _shares);
//     }

//     // function _withdraw(address _caller, address _receiver, address _owner, uint256 _assets, uint256 _shares) internal override {
//     //     if (settings.pauseWithdraw) revert WithdrawPaused();
//     //     if (_receiver == address(0)) revert ZeroAddress();
//     //     if (_owner == address(0)) revert ZeroAddress();
//     //     if (!(_shares > 0)) revert ZeroAmount();
//     //     if (!(_assets > 0)) revert ZeroAmount();
        
//     //     if (_caller != _owner) {
//     //         uint256 _allowed = allowance[_owner][_caller];
//     //         if (_allowed < _shares) revert InsufficientAllowance();
//     //         if (_allowed != type(uint256).max) allowance[_owner][_caller] = _allowed - _shares;
//     //     }
        
//     //     _burn(_owner, _shares);
//     //     totalAUM -= _assets;
        
//     //     emit Withdraw(_caller, _receiver, _owner, _assets, _shares);
//     // }
// }