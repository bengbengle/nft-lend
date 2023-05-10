// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

interface IFacilitator {
    /// @notice See loanInfo                                // 查阅 loanInfo
    struct Loan {
        bool closed;                                        // 是否关闭
        uint16 rate;                                        // 年利率
        uint32 duration;                                    // 期限
        uint40 timestamp;                                   // 最后累积时间戳
        address erc721;                                     // 抵押品合约地址
        uint88 originationFeeRate;                          // 起始费率
        address erc20;                                      // 贷款资产合约地址
        uint128 interest;                                   // 累积利息
        uint128 amount;                                     // 贷款金额
        uint256 tokenId;                                    // 抵押品 tokenId
        bool inc;                                           // 是否允许贷款金额增加

    }

    /**
     * @notice The magnitude of SCALAR              // SCALAR 的数量级                
     * @dev 10^INTEREST_RATE_DECIMALS = 1 = 100%    // 10^INTEREST_RATE_DECIMALS = 1 = 100%
     */
    function INTEREST_RATE_DECIMALS() external view returns (uint8);

    /**
     * @notice The SCALAR for all percentages in the facilitator contract                   
     * @dev Any interest rate passed to a function should already been multiplied by SCALAR     
     */
    function SCALAR() external view returns (uint256);

    /**
     * @notice The percent of the loan amount that the facilitator will take as a fee, scaled by SCALAR
     * @dev Starts set to 1%. Can only be set to 0 - 5%. 
     */
    function originationFeeRate() external view returns (uint256);

    /**
     * @notice The lend ticket contract associated with this loan facilitator
     * @dev Once set, cannot be modified
     */
    function lendTicket() external view returns (address);

    /**
     * @notice The borrow ticket contract associated with this loan facilitator
     * @dev Once set, cannot be modified
     */
    function borrowTicket() external view returns (address);

    /**
     * @notice The percent improvement required of at least one loan term when buying out current lender 
     * a loan that already has a lender, scaled by SCALAR. 
     * E.g. setting this value to 100 (10%) means, when replacing a lender, the new loan terms must have
     * at least 10% greater duration or loan amount or at least 10% lower interest rate. 
     * @dev Starts at 100 = 10%. Only owner can set. Cannot be set to 0.
     */
    function requiredImprovementRate() external view returns (uint256);
    
    /**
     * @notice Emitted when the loan is created
     * @param id The id of the new loan, matches the token id of the borrow ticket minted in the same transaction
     * @param minter msg.sender

     * @param erc721 The contract address of the erc721 NFT
     * @param tokenId The token id of the erc721 NFT

     * @param erc20 The contract address of the loan asset
     * @param amount mimimum loan amount

     * @param rate The max per anum interest rate, scaled by SCALAR
     * @param inc  allow loan amount increase
     * @param duration minimum loan duration in seconds
    */
    event CreateLoan (

        uint256 indexed id,
        address indexed minter,

        address erc721,
        uint256 tokenId,
        
        address erc20,
        uint256 amount,

        uint256 rate,
        uint256 duration,
        bool inc                    
    );

    /** 
     * @notice Emitted when ticket is closed
     * @param id The id of the ticket which has been closed
     */
    event Close(uint256 indexed id);

    /** 
     * @notice Emitted when the loan is lent to
     * @param id The id of the loan which is being lent to
     * @param lender msg.sender
     * @param interestRate The per anum interest rate, scaled by SCALAR, for the loan
     * @param amount The loan amount
     * @param duration The loan duration in seconds 
     */
    event Lend(
        uint256 indexed id,
        address indexed lender,
        uint256 interestRate,
        uint256 amount,
        uint256 duration
    );

    /**
     * @notice Emitted when a lender is being bought out:               // 当贷款人被买断时触发
     * the current loan ticket holder is being replaced by a new lender offering better terms 
     * 当前贷款票据持有者正在被提供更好条件的新贷款人所取代
     * @param lender msg.sender
     * @param replacedLoanOwner The current loan ticket holder         // 当前贷款票据持有者
     * @param interestEarned The amount of interest the loan has accrued from first lender to this buyout 
     *                          贷款从第一位贷款人到此次买断所产生的利息
     * @param replacedAmount The loan amount prior to buyout            // 买断前的贷款金额
     */    
    event BuyoutLender(
        uint256 indexed id,
        address indexed lender,
        address indexed replacedLoanOwner,
        uint256 interestEarned,
        uint256 replacedAmount
    );
    
    /**
     * @notice Emitted when loan is repaid                              // 当贷款被还清时触发
     * @param id The loan id                                            // 贷款 id
     * @param repayer msg.sender                                        // 还款人
     * @param loanOwner The current holder of the lend ticket for this loan, token id matching the loan id
     *                      // 此贷款的 lend ticket 的当前持有者, token id 与贷款 id 匹配
     * @param interestEarned The total interest accumulated on the loan // 贷款上累计的总利息
     * @param amount The loan amount                                // 贷款金额
     */
    event Repay(
        uint256 indexed id,
        address indexed repayer,
        address indexed loanOwner,
        uint256 interestEarned,
        uint256 amount
    );

    /**
     * @notice Emitted when loan NFT erc721 is seized               // 当贷款 NFT 抵押品被查封时触发
     * @param id The ticket id                                          // 票据 id
     */
    event Seize(uint256 indexed id);

     /**
      * @notice Emitted when origination fees are withdrawn             // 当 origination fees 被提取时触发
      * @dev only owner can call                                        // 只有所有者可以调用
      * @param asset the ERC20 asset withdrawn                          // 提取的 ERC20 资产
      * @param amount the amount withdrawn                              // 提取的数量
      * @param to the address the withdrawn amount was sent to          // 发送到的地址
      */
     event WithdrawOriginationFees(address asset, uint256 amount, address to);

      /**
      * @notice Emitted when originationFeeRate is updated                  // 当 originationFeeRate 被更新时触发
      * @dev only owner can call, value is scaled by SCALAR, 100% = SCALAR  // 只有所有者可以调用，值由 SCALAR 缩放，100% = SCALAR
      * @param feeRate the new origination fee rate                         // 新的 origination fee rate
      */
     event UpdateOriginationFeeRate(uint32 feeRate);

     /**
      * @notice Emitted when requiredImprovementRate is updated
      * @dev only owner can call, value is scaled by SCALAR, 100% = SCALAR
      * @param improvementRate the new required improvementRate
      */
     event UpdateRequiredImprovementRate(uint256 improvementRate);

    /**
     * @notice (1) transfers the erc721 NFT to the facilitator contract    // 将抵押品 NFT 转移到贷款 促进合约 
     * (2) creates the loan, populating loanInfo in the facilitator contract,       // 创建贷款，填充贷款促进合约中的 loanInfo
     * and (3) mints a Borrow Ticket to to
     * @dev loan duration or loan amount cannot be 0, 
     * this is done to protect borrowers from accidentally passing a default value
     * and also because it creates odd lending and buyout behavior: possible to lend
     * for 0 value or 0 duration, and possible to buyout with no improvement because, for example
     * previousDurationSeconds + (previousDurationSeconds * requiredImprovementRate / SCALAR) <= duration
     * evaluates to true if previousDurationSeconds is 0 and duration is 0.
     * erc20 cannot be address(0), we check this because Solmate SafeTransferLib
     * does not revert with address(0) and this could cause odd behavior.
     * erc721 cannot be address(borrowTicket) or address(lendTicket).
     * @param tokenId The token id of the erc721 NFT 
     * @param erc721 The contract address of the erc721 NFT
     * @param rate The maximum per anum interest rate for this loan, scaled by SCALAR            // 贷款的 最大年利率, 由 SCALAR 缩放
     * @param inc Whether the borrower is open to lenders offerring greater than amount
     * @param amount The minimum acceptable loan amount for this loan
     * @param erc20 The address of the loan asset
     * @param duration The minimum duration for this loan
     * @param to An address to mint the Borrow Ticket corresponding to this loan to
     * @return id of the created loan
     */
    function createLoan(
            uint256 tokenId,
            address erc721,
            uint16 rate,
            uint128 amount,
            address erc20,
            uint32 duration,
            address to,
            bool inc
    ) external returns (uint256 id);

    /**
     * @notice Closes the loan, sends the NFT erc721 to senderc721To
     * @dev Can only be called by the holder of the Borrow Ticket with tokenId
     * matching the loanId. Can only be called if loan has no lender,
     * i.e. lastinterestTimestamp = 0
     * @param loanId The loan id
     * @param senderc721To The address to send the erc721 NFT to
     */
    function closeLoan(uint256 loanId, address senderc721To) external;

    /**
     * @notice Lends, meeting or beating the proposed loan terms, 
     * transferring `amount` of the loan asset 
     * to the facilitator contract. If the loan has not yet been lent to, 
     * a Lend Ticket is minted to `sendLendTicketTo`. If the loan has already been 
     * lent to, then this is a buyout, and the Lend Ticket will be transferred
     * from the current holder to `sendLendTicketTo`. Also in the case of a buyout, interestOwed()
     * is transferred from the caller to the facilitator contract, in addition to `amount`, and
     * totalOwed() is paid to the current Lend Ticket holder.
     * @dev Loan terms must meet or beat loan terms. If a buyout, at least one loan term
     * must be improved by at least 10%. E.g. 10% longer duration, 10% lower interest, 
     * 10% higher amount
     * @param loanId The loan id
     * @param interestRate The per anum interest rate, scaled by SCALAR
     * @param amount The loan amount
     * @param duration The loan duration in seconds
     * @param sendLendTicketTo The address to send the Lend Ticket to
     */
    function lend(
            uint256 loanId,
            uint16 interestRate,
            uint128 amount,
            uint32 duration,
            address sendLendTicketTo
    ) external;

    /**
     * @notice repays and closes the loan, transferring totalOwed() to the current Lend Ticket holder
     * and transferring the erc721 NFT to the Borrow Ticket holder.
     * @param loanId The loan id
     */
    function repayAndCloseLoan(uint256 loanId) external;

    /**
     * @notice Transfers the erc721 NFT to `senderc721To` and closes the loan.
     * @dev Can only be called by Lend Ticket holder. Can only be called 
     * if block.timestamp > loanEndSeconds()
     * @param loanId The loan id
     * @param to The address to send the erc721 NFT to
     */
    function seize(uint256 loanId, address to) external;

    /**
     * @notice returns the info for this loan
     * @param loanId The id of the loan
     * @return closed Whether or not the ticket is closed
     * @return rate The per anum interest rate, scaled by SCALAR
     * @return duration The loan duration in seconds
     * @return timestamp The timestamp (in seconds) when interest was last accumulated, the timestamp of the most recent lend
     * @return erc721 The contract address of the NFT erc721 
     * @return originationFeeRate
     * @return erc20 The contract address of the loan asset.
     * @return interest The amount of interest accumulated on the loan prior to the current lender
     * @return amount The loan amount
     * @return tokenId The token ID of the NFT erc721
     * @return inc Whether the borrower is open to lenders offerring greater than amount
     */
    function loanInfo(uint256 loanId)
        external 
        view 
        returns (
            bool closed,
            uint16 rate,
            uint32 duration,
            uint40 timestamp,
            address erc721,
            uint88 originationFeeRate,
            address erc20,
            uint128 interest,
            uint128 amount,
            uint256 tokenId,
            bool inc
        );


    /**
     * @notice returns the info for this loan
     * @dev this is a convenience method for other contracts that would prefer to have the 
     * Loan object not decomposed. 
     * @param loanId The id of the loan
     * @return Loan struct corresponding to loanId
     */
    function loanInfoStruct(uint256 loanId) external view returns (Loan memory);

    /**
     * @notice returns the total amount owed for the loan, i.e. principal + interest
     * @param loanId The loan id
     * @return amount required to repay and close the loan corresponding to loanId
     */
    function totalOwed(uint256 loanId) view external returns (uint256);

    /**
     * @notice returns the interest owed on the loan, in loan asset units
     * @param loanId The loan id
     * @return amount of interest owed on loan corresonding to loanId
     */
    function interestOwed(uint256 loanId) view external returns (uint256);

    /**
     * @notice returns the unix timestamp (seconds) of the loan end
     * @param loanId The loan id
     * @return timestamp at which loan payment is due, after which lend ticket holder
     * can seize erc721
     */
    function loanEndSeconds(uint256 loanId) view external returns (uint256);
}