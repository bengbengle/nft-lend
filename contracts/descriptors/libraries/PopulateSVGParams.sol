// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import './BokkyPooBahsDateTimeLibrary.sol';
import './UintStrings.sol';
import '../../interfaces/IFacilitator.sol';
import '../../interfaces/IERC20Metadata.sol';
import './HexStrings.sol';
import './TicketSVG.sol';


library PopulateSVGParams{
    /**
     * @notice Populates and returns the passed `svgParams` with loan info retrieved from
     * `facilitator` for `id`, the loan id
     * @param svgParams The svg params to populate, which already has `nftType` populated from Descriptor
     * @param facilitator The facilitator contract to get loan info from for loan `id`
     * @param id The id of the loan
     * @return `svgParams`, with all values now populated
     */
    function populate(TicketSVG.SVGParams memory svgParams, IFacilitator facilitator, uint256 id)
        internal
        view
        returns (TicketSVG.SVGParams memory)
    {
        IFacilitator.Loan memory loan = facilitator.loanInfoStruct(id);

        svgParams.id = Strings.toString(id);
        svgParams.status = loanStatus(loan.timestamp, loan.duration, loan.closed);
        svgParams.interestRate = interestRateString(facilitator, loan.rate); 
        svgParams.erc20 = HexStrings.toHexString(uint160(loan.erc20), 20);
        svgParams.symbol = symbol(loan.erc20);
        svgParams.erc721 = HexStrings.toHexString(uint160(loan.erc721), 20);
        svgParams.erc721Partial = HexStrings.partialHexString(uint160(loan.erc721), 10, 40);
        svgParams.nft_symbol = nft_symbol(loan.erc721);
        svgParams.tokenId = Strings.toString(loan.tokenId);
        svgParams.amount = amountString(loan.amount, loan.erc20);
        svgParams.interestAccrued = accruedInterest(facilitator, id, loan.erc20);
        svgParams.durationDays = Strings.toString(loan.duration / (24 * 60 * 60));
        svgParams.endDateTime = loan.timestamp == 0 ? "n/a" 
        : endDateTime(loan.timestamp + loan.duration);
        
        return svgParams;
    }

    function interestRateString(IFacilitator facilitator, uint256 rate) 
        private 
        view 
        returns (string memory)
    {
        return UintStrings.decimalString(
            rate,
            facilitator.INTEREST_RATE_DECIMALS() - 2,
            true
            );
    }

    function amountString(uint256 amount, address asset) private view returns (string memory) {
        return UintStrings.decimalString(amount, IERC20Metadata(asset).decimals(), false);
    }

    function symbol(address asset) private view returns (string memory) {
        return IERC20Metadata(asset).symbol();
    }

    function nft_symbol(address asset) private view returns (string memory) {
        return ERC721(asset).symbol();
    }

    function accruedInterest(IFacilitator facilitator, uint256 loanId, address loanAsset) 
        private 
        view 
        returns (string memory)
    {
        return UintStrings.decimalString(
            facilitator.interestOwed(loanId),
            IERC20Metadata(loanAsset).decimals(),
            false);
    }

    function loanStatus(uint256 lastAccumulatedTimestamp, uint256 duration, bool closed) 
        view 
        private 
        returns (string memory)
    {
        if (lastAccumulatedTimestamp == 0) return "awaiting lender";

        if (closed) return "closed";

        if (block.timestamp > (lastAccumulatedTimestamp + duration)) return "past due";

        return "accruing interest";
    }

    /** 
     * @param endDateSeconds The unix seconds timestamp of the loan end date
     * @return a string representation of the UTC end date and time of the loan,
     * in format YYYY-MM-DD HH:MM:SS
     */
    function endDateTime(uint256 endDateSeconds) private pure returns (string memory) {
        (uint year, uint month, 
        uint day, uint hour, 
        uint minute, uint second) = BokkyPooBahsDateTimeLibrary.timestampToDateTime(endDateSeconds);
        return string.concat(
                Strings.toString(year),
                '-',
                Strings.toString(month),
                '-',
                Strings.toString(day),
                ' ',
                Strings.toString(hour),
                ':',
                Strings.toString(minute),
                ':',
                Strings.toString(second),
                ' UTC'
        );
    } 
}