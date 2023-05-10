// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

interface ILendTicket {
    /**
     * @notice Transfers a lend ticket                          // 转移 借出 票据
     * @dev can only be called by nft loan facilitator          // 只能被 nft 借贷协调器 调用
     * @param from The current holder of the lend ticket        // 票据 持有者 的地址
     * @param to Address to send the lend ticket to             // 票据 接收者 的地址
     * @param loanId The lend ticket token id, which is also the loan id in the facilitator contract, 
     *                                                           借出票据的 tokenId, 也是在 协调器合约中的 loanId
     */
    function transfer(address from, address to, uint256 loanId) external;
}