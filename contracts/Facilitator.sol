// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.12;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeTransferLib, ERC20} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC1820Registry} from "@openzeppelin/contracts/utils/introspection/IERC1820Registry.sol";
import {IERC777Recipient} from "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";

import {IFacilitator} from './interfaces/IFacilitator.sol';
import {IERC721Mintable} from './interfaces/IERC721Mintable.sol';
import {ILendTicket} from './interfaces/ILendTicket.sol';

contract Facilitator is Ownable, IFacilitator, IERC777Recipient {
    using SafeTransferLib for ERC20;

    // ==== constants ====

    /** 
     * See {IFacilitator-INTEREST_RATE_DECIMALS}.     
     * @dev lowest non-zero APR possible = (1/10^3) = 0.001 = 0.1%  // 最低非零 APR = (1/10^3) = 0.001 = 0.1%
     */
    uint8 public constant override INTEREST_RATE_DECIMALS = 3;

    /// See {IFacilitator-SCALAR}. 
    uint256 public constant override SCALAR = 10 ** INTEREST_RATE_DECIMALS; // 1000

    
    // ==== state variables ====

    /// See {IFacilitator-originationFeeRate}.
    /// @dev starts at 1%
    uint256 public override originationFeeRate = 10 ** (INTEREST_RATE_DECIMALS - 2);

    /// See {IFacilitator-requiredImprovementRate}.
    /// @dev starts at 10%
    uint256 public override requiredImprovementRate = 10 ** (INTEREST_RATE_DECIMALS - 1);

    /// See {IFacilitator-lendTicket}.
    address public override lendTicket;

    /// See {IFacilitator-borrowTicket}.
    address public override borrowTicket;

    mapping(uint256 => Loan) public override loanInfo;

    /// @dev tracks loan count
    uint256 private _nonce = 1;

    
    // ==== modifiers ====

    modifier notClosed(uint256 loanId) { 
        require(!loanInfo[loanId].closed, "loan closed");
        _; 
    }


    // ==== constructor ====

    constructor(address _manager) {
        transferOwnership(_manager);

        IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24)
            .setInterfaceImplementer(address(this), keccak256("ERC777TokensRecipient"), address(this)
        );
    }

    
    // ==== state changing external functions ====

    function createLoan(                            
        uint256 tokenId,                  
        address erc721,

        uint16 rate,
        
        uint128 amount,
        address erc20,

        uint32 duration,
        address borrower,
        bool inc
    )
        external
        override
        returns (uint256 id) 
    {
        require(duration != 0, '0 duration');
        require(amount != 0, '0 loan amount');
        require(erc721 != lendTicket, 'lend ticket collateral');
        require(erc721 != borrowTicket, 'borrow ticket collateral');
        
        IERC721(erc721).transferFrom(msg.sender, address(this), tokenId);

        unchecked {
            id = _nonce++;
        }

        Loan storage loan = loanInfo[id];

        loan.originationFeeRate = uint88(originationFeeRate);               // 初始的 贷款手续费率
        
        loan.erc721 = erc721;
        loan.tokenId = tokenId;

        loan.erc20 = erc20;
        loan.amount = amount;

        loan.inc = inc;                                                     // 是否允许增加贷款
        loan.rate = rate;
        loan.duration = duration;
        
        IERC721Mintable(borrowTicket).mint(borrower, id);

        address minter = msg.sender;
        emit CreateLoan(
            id,
            minter,

            erc721,
            tokenId,

            erc20,
            amount,

            rate,
            duration,
            inc
        );
    }

    /// 关闭借贷
    function closeLoan(uint256 loanId, address to) 
        external 
        override 
        notClosed(loanId) 
    {

        require(
            IERC721(borrowTicket).ownerOf(loanId) == msg.sender,
            "borrow ticket holder only"
        );

        Loan storage loan = loanInfo[loanId];
        require(loan.timestamp == 0, "has lender");
        
        loan.closed = true;

        IERC721(loan.erc721)
            .transferFrom(address(this), to, loan.tokenId);
        
        emit Close(loanId);
    }

    /// 借出
    function lend(uint256 loanId, uint16 interestRate, uint128 amount, uint32 duration, address to)
        external
        override
        notClosed(loanId)
    {
        Loan storage loan = loanInfo[loanId];
        
        // 首次借出
        if (loan.timestamp == 0) {
            
            address erc20 = loan.erc20;       // 贷款资产 的 合约地址, Eq: USDT, WETH, DAI, USDC

            require(erc20.code.length != 0, "invalid loan");     // 贷款资产 的 合约地址不为空
            require(loan.rate >= interestRate, 'rate too high');    // 借款利率 <= 贷款利率
            require(loan.duration <= duration, 'duration too low');   // 借款期限 >= 贷款期限

            if (loan.inc) { // 可以增加贷款金额
                require(amount >= loan.amount, 'amount too low');
            } else {
                require(amount == loan.amount, 'invalid amount');
            }
        
            loan.rate = interestRate;                               // 设置 借款利率
            loan.timestamp = uint40(block.timestamp);                // 设置 最后累积时间戳
            loan.duration = duration;                                 // 设置 借款期限
            loan.amount = amount;                                               // 设置 借款金额
            
            uint256 facilitatorTake = amount * uint256(loan.originationFeeRate) / SCALAR;   // 借款金额 * 贷款利率 / 1000
            
            // 平台扣留 贷款利息
            ERC20(erc20)
                .safeTransferFrom(msg.sender, address(this), facilitatorTake);
            
            ERC20(erc20)
                .safeTransferFrom(msg.sender, IERC721(borrowTicket).ownerOf(loanId), amount - facilitatorTake);

            IERC721Mintable(lendTicket)
                .mint(to, loanId);

        } else {

            uint256 initAmount = loan.amount;                                              // 原始贷款金额
            uint256 _inc = amount - initAmount;                                      // 增加的贷款金额
            if (!loan.inc) {                                            // 不允许增加贷款金额
                require(_inc == 0, 'amount increase not allowed');                
            }

            uint256 _interest;                                                                          // 累积利息

            {
                uint256 previousInterestRate = loan.rate;                                               // 原始年利率
                uint256 previousDurationSeconds = loan.duration;                                        // 原始借款期限

                require(interestRate <= previousInterestRate, 'rate too high');                         // 借款利率 要小于 初始 贷款利率
                require(duration >= previousDurationSeconds, 'duration too low');                       // 借款期限 要大于 初始 贷款期限
                
                bool isvalid = Math.ceilDiv(initAmount * requiredImprovementRate, SCALAR) <= _inc;      // 增加的贷款金额 >= 原始贷款金额
                
                bool isvalid1 = duration - previousDurationSeconds >= 
                    Math.ceilDiv(previousDurationSeconds * requiredImprovementRate, SCALAR);                            // 借款期限 >= 原始借款期限
                
                bool isvalid2 = previousInterestRate != 0 && previousInterestRate - interestRate >= 
                    Math.ceilDiv(previousInterestRate * requiredImprovementRate, SCALAR) ;                              // 借款利率 >= 原始年利率

                require(isvalid || isvalid1 || isvalid2, "insufficient improvement");
                
                _interest = _interestOwed(                              // 计算利息
                    initAmount,                                         // 贷款金额
                    loan.timestamp,                                     // 上次计息时间
                    previousInterestRate,                               // 年利率
                    loan.interest                                       // 累计利息
                );
            }

            require(_interest < 1 << 128, "interest exceeds uint128");

            loan.rate = interestRate;
            loan.timestamp = uint40(block.timestamp);
            loan.duration = duration;
            loan.amount = amount;
            loan.interest = uint128(_interest);

            address _owner = IERC721(lendTicket).ownerOf(loanId);
            
            ILendTicket(lendTicket).transfer(_owner, to, loanId);

            address _token = loan.erc20;                                        // 借出的 Token 合约地址, Eq: USDT, WETH, DAI, USDC
            uint256 _rate = loan.originationFeeRate;                            // 贷款利率

            if(_inc > 0) {

                handle_inc(
                    loanId, 
                    _token,
                    _inc,
                    _rate,            
                    _owner,
                    _interest,
                    initAmount
                );

            } else {

                uint256 _total = _interest + initAmount;

                ERC20(_token)
                    .safeTransferFrom(msg.sender, _owner, _total);
            }
            
            emit BuyoutLender(loanId, msg.sender, _owner, _interest, initAmount);
        }

        emit Lend(loanId, msg.sender, interestRate, amount, duration);
    }

    /// 还款 + 关闭 借贷
    function repayAndCloseLoan(uint256 loanId) 
        external 
        override 
        notClosed(loanId) 
    {

        Loan storage loan = loanInfo[loanId];

        uint256 amount = loan.amount; // 初始 借贷金额

        // 计算 利息
        uint256 interest = _interestOwed(
            amount,                         // 贷款金额
            loan.timestamp,      // 上次计息时间
            loan.rate,          // 年利率
            loan.interest            // 累计利息
        );
        
        address lender = IERC721(lendTicket).ownerOf(loanId);
        loan.closed = true;
        
        // transfer interest + loan amount to lender 
        ERC20(loan.erc20)
            .safeTransferFrom(msg.sender, lender, interest + amount);

        // transfer collateral to borrower
        IERC721(loan.erc721)
            .transferFrom(address(this), IERC721(borrowTicket).ownerOf(loanId), loan.tokenId);

        // 触发 还款事件
        emit Repay(loanId, msg.sender, lender, interest, amount);
        
        // 触发 关闭事件
        emit Close(loanId);
    }

    /// See {IFacilitator-seize}.
    function seize(uint256 loanId, address to) 
        external 
        override 
        notClosed(loanId) 
    {
        require(IERC721(lendTicket).ownerOf(loanId) == msg.sender, "lend ticket holder only");

        Loan storage loan = loanInfo[loanId];
        require(block.timestamp > loan.duration + loan.timestamp, "payment is not late");

        loan.closed = true;

        IERC721(loan.erc721).transferFrom(address(this), to, loan.tokenId);

        emit Seize(loanId);
        emit Close(loanId);
    }

    /// @dev If we allowed ERC777 tokens, 
    /// a malicious lender could revert in 
    /// tokensReceived and block buyouts or repayment.
    /// So we do not support ERC777 tokens.
    function tokensReceived(
        address,
        address,
        address,
        uint256,
        bytes calldata,
        bytes calldata
    ) external pure override {
        revert('ERC777 unsupported');
    }

    
    // === owner state changing ===

    /**
     * @notice Sets lendTicket to _contract
     * @dev cannot be set if lendTicket is already set
     */
    function setLendTicketContract(address _contract) 
        external 
        onlyOwner 
    {
        require(lendTicket == address(0), 'already set');

        lendTicket = _contract;
    }

    /**
     * @notice Sets borrowTicket to _contract
     * @dev cannot be set if borrowTicket is already set
     */
    function setBorrowTicketContract(address _contract) external onlyOwner {
        require(borrowTicket == address(0), 'already set');

        borrowTicket = _contract;
    }

    /// @notice Transfers `amount` of loan origination fees for `asset` to `to`
    function withdrawOriginationFees(address asset, uint256 amount, address to) external onlyOwner {
        ERC20(asset).safeTransfer(to, amount);

        emit WithdrawOriginationFees(asset, amount, to);
    }

    /**
     * @notice Updates originationFeeRate the facilitator keeps of each loan amount
     * @dev Cannot be set higher than 5%
     */
    function updateOriginationFeeRate(uint32 _originationFeeRate) external onlyOwner {
        require(_originationFeeRate <= 5 * (10 ** (INTEREST_RATE_DECIMALS - 2)), "max fee 5%");
        
        originationFeeRate = _originationFeeRate;

        emit UpdateOriginationFeeRate(_originationFeeRate);
    }

    /**
     * @notice updates the percent improvement required of at least one loan term when buying out lender 
     * a loan that already has a lender. E.g. setting this value to 100 means duration or amount
     * must be 10% higher or interest rate must be 10% lower. 
     * @dev Cannot be 0.
     */
    function updateRequiredImprovementRate(uint256 _improvementRate) external onlyOwner {
        require(_improvementRate != 0, '0 improvement rate');

        requiredImprovementRate = _improvementRate;

        emit UpdateRequiredImprovementRate(_improvementRate);
    }

    
    // ==== external view ====

    /// See {IFacilitator-loanInfoStruct}.
    function loanInfoStruct(uint256 loanId) external view override returns (Loan memory) {
        return loanInfo[loanId];
    }

    /// See {IFacilitator-totalOwed}.
    function totalOwed(uint256 loanId) external view override returns (uint256) {
        Loan storage loan = loanInfo[loanId];
        uint256 lastAccumulated = loan.timestamp;
        if (loan.closed || lastAccumulated == 0) return 0;

        return loanInfo[loanId].amount + _interestOwed(
            loan.amount,
            lastAccumulated,
            loan.rate,
            loan.interest
        );
    }

    /// See {IFacilitator-interestOwed}.
    function interestOwed(uint256 loanId) external view override returns (uint256) {
        Loan storage loan = loanInfo[loanId];
        uint256 lastAccumulated = loan.timestamp;
        if (loan.closed || lastAccumulated == 0) return 0;

        return _interestOwed(
            loan.amount,
            lastAccumulated,
            loan.rate,
            loan.interest
        );
    }

    /// See {IFacilitator-loanEndSeconds}.
    function loanEndSeconds(uint256 loanId) external view override returns (uint256) {
        Loan storage loan = loanInfo[loanId];
        uint256 lastAccumulated;
        require((lastAccumulated = loan.timestamp) != 0, 'loan has no lender');
        
        return loan.duration + lastAccumulated;
    }

    
    // === internal & private ===

    /// @dev Returns the total interest owed on loan
    /// @dev 返回贷款的 总利息
    function _interestOwed(uint256 amount, uint256 timestamp, uint256 rate, uint256 interest) 
        internal 
        view 
        returns (uint256) 
    {
        return amount
            * (block.timestamp - timestamp)
            * (rate * 1e18 / 365 days) / 1e21 //    1e18 * 1e18 / 365 days / 1e3
            + interest;
    }

    /// @dev 在 lender 买断 的情况下 处理 erc20 付款 增加贷款金额
    function handle_inc(
        uint256 loanId,
        address erc20,
        uint256 amountIncrease,
        uint256 loanOriginationFeeRate,
        address currentLoanOwner,
        uint256 interest,
        uint256 previousamount
    ) 
        private 
    {
        uint256 facilitatorTake = (amountIncrease * loanOriginationFeeRate / SCALAR);

        ERC20(erc20).safeTransferFrom(msg.sender, address(this), facilitatorTake);

        ERC20(erc20).safeTransferFrom(
            msg.sender,
            currentLoanOwner,
            interest + previousamount
        );

        ERC20(erc20)
            .safeTransferFrom(msg.sender, IERC721(borrowTicket).ownerOf(loanId), amountIncrease - facilitatorTake);
    }
}
