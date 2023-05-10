// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

interface IERC721Mintable {
    /**
     * @notice mints an ERC721 token of tokenId to the to address           // 铸造 tokenId 的 ERC721 代币到 to 地址
     * @dev only callable by nft loan facilitator                           // 只能被 nft 借贷协调器 调用
     * @param to The address to send the token to                           // 代币 接收者 的地址
     * @param tokenId The id of the token to mint                           // 要铸造的 tokenId
     */
    function mint(address to, uint256 tokenId) external;
}