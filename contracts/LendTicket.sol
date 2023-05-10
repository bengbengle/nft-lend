// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.12;

import {ILendTicket} from './interfaces/ILendTicket.sol';
import {Ticket} from './Ticket.sol';

import {Facilitator} from './Facilitator.sol';
import {Descriptor} from './descriptors/Descriptor.sol';

contract LendTicket is Ticket, ILendTicket {

    /// See Ticket
    constructor(Facilitator _facilitator, Descriptor _descriptor)
        Ticket("Backed Lend Ticket", "LNDT", _facilitator, _descriptor) 
    {}

    /// See {ILendTicket-transfer}
    function transfer(address from, address to, uint256 loanId) 
        external 
        override 
        OnlyFacilitator 
    {
        _transfer(from, to, loanId);
    }

    /// @dev exact copy of transferFrom in ./ERC721.sol
    /// with L91 - L93 removed to enable transfer
    /// also L87 removed because Facilitator calls ownerOf when 
    /// passing `from` to transfer
    function _transfer(address from, address to, uint256 id) internal {
        require(to != address(0), "INVALID_RECIPIENT");

        // Underflow of the sender's balance is impossible because we check for 
        // ownership above and the recipient's balance can't realistically overflow.
        // 发送者的余额不可能为负数, 因为我们检查了所有权, 并且接收者的余额不可能溢出 
        unchecked {
            _balanceOf[from]--;

            _balanceOf[to]++;
        }

        _ownerOf[id] = to;

        delete getApproved[id];

        emit Transfer(from, to, id);
    }
}