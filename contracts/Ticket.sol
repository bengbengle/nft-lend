// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.12;

import {ERC721} from "./ERC721.sol";

import {Facilitator} from './Facilitator.sol';
import {Descriptor} from './descriptors/Descriptor.sol';

import {IERC721Mintable} from './interfaces/IERC721Mintable.sol';

contract Ticket is ERC721, IERC721Mintable {

    Facilitator public immutable facilitator;
    Descriptor public immutable descriptor;

    modifier OnlyFacilitator() { 
        require(msg.sender == address(facilitator), "Ticket: only loan facilitator");
        _; 
    }

    /// @dev Sets the values for {name} and {symbol} and {facilitator} and {descriptor}.
    constructor(
        string memory name, 
        string memory symbol, 
        Facilitator _facilitator, 
        Descriptor _descriptor
    ) 
        ERC721(name, symbol) 
    {
        facilitator = _facilitator;
        descriptor = _descriptor;
    }

    /// See {IERC721Mintable-mint}.
    function mint(address to, uint256 tokenId) 
        external 
        override 
        OnlyFacilitator 
    {
        _mint(to, tokenId);
    }

    /// @notice returns a base64 encoded data uri containing the token metadata in JSON format 
    /// 返回一个 base64 编码的数据 uri, 包含 JSON 格式的 token 元数据
    function tokenURI(uint256 tokenId) 
        public 
        view 
        override 
        returns (string memory) 
    {
        require(_ownerOf[tokenId] != address(0), 'nonexistent token');
        
        return descriptor.uri(facilitator, tokenId);
    }
}