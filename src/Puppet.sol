// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract Puppet {

    // playing with contracts
    // GMX - long ETH 2x using ETH as collateral using https://arbiscan.io/address/0xaBF1d1251Edb352f5ce601d644D44f78BDA90693:
    // 1. approve plugin (txn hash https://arbiscan.io/tx/0xff7f1e22f0985e5bbfb064f82588938f562e3f9882c5cf57bd7fe7126dae6596) --> approve the address of the PositionRouter
    // 2. createIncreasePositionETH (txn hash https://arbiscan.io/tx/0xbb36ce8459e5b8333adde68953622ec1d6026e542120629bbeeb04daff16f6a3)
    // 3. createIncreasePositionETH (just added collateral to exsisting position) (txn hash https://arbiscan.io/tx/0x4ae678f80b38bc4d1396052d37ea6b6fa9627dd859307f630fccaa9a55ba3fec)
    // 4. *removing collateral* createDecreasePosition (txn hash https://arbiscan.io/tx/0xddeac229f6190861f93185acb69111fe963ad9de282a52ad6da23300a1ac1539)
    // 5. *closing position* createDecreasePosition (txn hash https://arbiscan.io/tx/0x0aa093c2709d3f2a42b7c41345cfa4588e736bb5d98b2d0eca47f029f74a930e)

    // docs
    // https://gmxio.gitbook.io/gmx/contracts#opening-increasing-a-position

    // user flow
    // 1. trader registers
    // 2. investors can now select the trader and deposit funds
    // 3. trader can now open a position using the funds deposited by him + investors that have selected him
    // 4. investor can withdraw funds only if trader has closed the position

    // questions:
    // require the trader's collateral to be x% of the total funds deposited by investors? (e.g. in order to use 1000$ of investors funds, trader will need 10% so 100$)
    // cut trader collateral on loss? (to make sure incentives are alligned on all scenarios)
    // limit performance fee to x% of TVL? (to disincentivize over risk taking)
}