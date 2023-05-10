// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import './Descriptor.sol';

contract BorrowTicketDescriptor is Descriptor {
    /// @dev see Descriptor
    constructor(ITicketTypeSpecificSVGHelper _svgHelper) Descriptor("Borrow", _svgHelper) {}

    /**
     * @notice returns string with borrow ticket description details
     * @dev Called by generateDescriptor when populating the description part of the token metadata. 
     */
    function generateDescription(string memory) 
        internal 
        pure 
        override 
        returns (string memory) 
    {
        return 'This Borrow Ticket NFT was created by the deposit of an NFT into the NFT Loan Faciliator '
                'contract to serve as collateral for a loan. If the loan is lent to, funds will be transferred '
                'to the borrow ticket holder. If the loan is repaid, the NFT collateral is transferred to the borrow '
                'ticket holder. If the loan is marked closed, the collateral has been withdrawn.';
                
    }

}