// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import './TicketTypeSpecificSVGHelper.sol';

contract LendTicketSVGHelper is TicketTypeSpecificSVGHelper {
    /**
     * @dev Returns SVG styles where the primary background color is derived
     * from the loan asset address and the secondary background color 
     * is derived from the collateral asset address
     */
    function backgroundColorsStyles(string memory collateralAsset, string memory loanAsset) 
        external
        pure
        override
        returns (string memory)
    {
        return colorStyles(loanAsset, collateralAsset);
    }

    
    function ticketIdXCoordinate() external pure override returns (string memory) {
        return '165';
    }

    
    function backgroundTitleRectsXTranslate() external pure override returns (string memory) {
        return '171';
    }

    
    function titlesPositionClass() external pure override returns (string memory) {
        return 'left';
    }

    
    function titlesXTranslate() external pure override returns (string memory) {
        return '179';
    }

    
    function backgroundValueRectsXTranslate() external pure override returns (string memory) {
        return '0';
    }

    
    function alignmentClass() external pure override returns (string memory) {
        return 'right';
    }

    
    function valuesXTranslate() external pure override returns (string memory) {
        return '163';
    }
}