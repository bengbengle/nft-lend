// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.12;

import './Ticket.sol';
import {Facilitator} from './Facilitator.sol';
import {Descriptor} from './descriptors/Descriptor.sol';

contract BorrowTicket is Ticket {

    /// See Ticket
    constructor(Facilitator _facilitator, Descriptor _descriptor)
        Ticket("Backed Borrow Ticket", "BRWT", _facilitator, _descriptor)
    {}
}