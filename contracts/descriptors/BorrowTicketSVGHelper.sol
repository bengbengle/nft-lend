// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import './TicketTypeSpecificSVGHelper.sol';

contract BorrowTicketSVGHelper is TicketTypeSpecificSVGHelper {
    /**
     * @dev Returns SVG styles where the primary background color is derived    
     * from the collateral asset address and the secondary background color     
     * is derived from the loan asset address                                    
     * 返回 SVG 样式， 其中
     *      主要背景颜色 派生自 抵押资产地址
     *      次要背景颜色 派生自 借贷资产地址
     */
    function backgroundColorsStyles(string memory collateralAsset, string memory loanAsset) 
        external 
        pure
        override 
        returns (string memory)
    {
        return colorStyles(collateralAsset, loanAsset);
    }


    function ticketIdXCoordinate() external pure override returns (string memory) {
        return '134';
    }
    

    function backgroundTitleRectsXTranslate() external pure override returns (string memory) {
        return '31';
    }


    function titlesPositionClass() external pure override returns (string memory) {
        return 'right';
    }


    function titlesXTranslate() external pure override returns (string memory) {
        return '121';
    }


    function backgroundValueRectsXTranslate() external pure override returns (string memory) {
        return '129';
    }


    function alignmentClass() external pure override returns (string memory) {
        return 'left';
    }


    function valuesXTranslate() external pure override returns (string memory) {
        return '136';
    }
}