// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import 'base64-sol/base64.sol';
import '../Facilitator.sol';
import './libraries/TicketSVG.sol';
import './libraries/PopulateSVGParams.sol';

contract Descriptor {
    // Lend or Borrow 
    string public nftType;
    ITicketTypeSpecificSVGHelper immutable public svgHelper;

    /// @dev Initializes the contract by setting a `nftType` and `svgHelper`
    constructor(string memory _nftType, ITicketTypeSpecificSVGHelper _svgHelper) {
        nftType = _nftType;
        svgHelper = _svgHelper;
    }

    /**
     * @dev Returns a string which is a data uri of base64 encoded JSON,
     * the JSON contains the token metadata: name, description, image
     * which reflect information about `id` loan in `facilitator`
     */ 
    function uri(Facilitator facilitator, uint256 id)
        external
        view
        returns (string memory)
    {
        TicketSVG.SVGParams memory svgParams;
        svgParams.nftType = nftType;
        svgParams = PopulateSVGParams.populate(svgParams, facilitator, id);
        
        return generateDescriptor(svgParams);
    }

    /**
     * @dev Returns a string which is a data uri of base64 encoded JSON,
     * the JSON contains the token metadata: name, description, image.
     * The metadata values come from `svgParams`
     */ 
    function generateDescriptor(TicketSVG.SVGParams memory svgParams)
        private
        view
        returns (string memory)
    {
        return string.concat(
            'data:application/json;base64,',
            Base64.encode(
                bytes(
                    string.concat(
                        '{"name":"',
                        svgParams.nftType,
                        ' ticket',
                        ' #',
                        svgParams.id,
                        '", "description":"',
                        generateDescription(svgParams.id),
                        generateDescriptionDetails(
                            svgParams.erc20,
                            svgParams.symbol,
                            svgParams.erc721, 
                            svgParams.nft_symbol,
                            svgParams.tokenId),
                        '", "image": "',
                        'data:image/svg+xml;base64,',
                        Base64.encode(bytes(TicketSVG.generateSVG(svgParams, svgHelper))),
                        '"}'
                    )
                )
            )
        );
    }

    /// @dev Returns string, ticket type (borrow or lend) specific description   
    /// @dev 返回 string，借贷类型（借入或借出）特定描述   
    function generateDescription(string memory loanId) internal pure virtual returns (string memory) {}

    /// @dev Returns string, important info about the loan that this ticket is related to 
    function generateDescriptionDetails(
        string memory loanAsset,
        string memory symbol,
        string memory collateralAsset,
        string memory nft_symbol,
        string memory collateralAssetId
    ) 
        private 
        pure 
        returns (string memory) 
    {
        return string.concat(
            '\\n\\nCollateral Address: ',
            collateralAsset,
            ' (',
            nft_symbol,
            ')\\n\\n',
            'Collateral ID: ',
            collateralAssetId,
            '\\n\\n',
            'Loan Asset Address: ',
            loanAsset,
            ' (',
            symbol,
            ')\\n\\n',
            'WARNING: Do your own research to verify the legitimacy of the assets related to this ticket'
        );
    }
}