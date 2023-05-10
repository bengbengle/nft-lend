// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

interface ITicketTypeSpecificSVGHelper {
    /**
     * @notice returns a string of styles for use within an SVG
     * @param collateralAsset A string of the collateral asset address  // 抵押资产地址的字符串
     * @param loanAsset A string of the loan asset address              // 借贷资产地址的字符串
     */
    function backgroundColorsStyles(string memory collateralAsset, string memory loanAsset) 
        external pure 
        returns (string memory);

    /**
     * @dev All the below methods return ticket-type-specific values
     * used in building the ticket svg image. See TicketSVG for usage.
     */

    function ticketIdXCoordinate() external pure returns (string memory);

    function backgroundTitleRectsXTranslate() external pure returns (string memory);

    function titlesPositionClass() external pure returns (string memory);

    function titlesXTranslate() external pure returns (string memory);

    function backgroundValueRectsXTranslate() external pure returns (string memory);

    function alignmentClass() external pure returns (string memory);

    function valuesXTranslate() external pure returns (string memory);
}