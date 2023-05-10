// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import './Descriptor.sol';

contract LendTicketDescriptor is Descriptor {
    /// @dev Initializes the contract by setting a `nftType` and a `svgHelper`
    constructor(ITicketTypeSpecificSVGHelper _svgHelper) Descriptor("Lend", _svgHelper) {}

    /**
     * @notice returns string with lend ticket description details
     * @dev Called by generateDescriptor when populating the description part of the token metadata. 
     */
    function generateDescription(string memory loanId) 
        internal 
        pure 
        override 
        returns (string memory) 
    {
        return string.concat(
            'This Lend Ticket NFT was created when NFT Loan #', 
            loanId,
            ' was lent to. On loan repayment, funds will be transferred to the lend ticket holder. ',
            'If the loan is not paid back on time, the lend ticket holder is entitled to ',
            'seize the NFT collateral.'
        );
    }

}