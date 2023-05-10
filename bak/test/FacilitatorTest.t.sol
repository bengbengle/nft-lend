// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.12;

import {DSTest} from "./helpers/test.sol";
import {Vm} from "./helpers/Vm.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IFacilitator} from "contracts/interfaces/IFacilitator.sol";
import {Facilitator} from "contracts/Facilitator.sol";
import {FacilitatorFactory} from "./helpers/FacilitatorFactory.sol";
import {BorrowTicket} from "contracts/BorrowTicket.sol";
import {LendTicket} from "contracts/LendTicket.sol";

import {TestERC721} from "./mocks/TestERC721.sol";
import {TestERC20} from "./mocks/TestERC20.sol";
// import {TestERC777} from "./mocks/TestERC777.sol";
import {FeeOnTransferERC20} from "./mocks/FeeOnTransferERC20.sol";
import {RepayAndCloseERC20} from "./mocks/RepayAndCloseERC20.sol";
import {ReLendERC20} from "./mocks/ReLendERC20.sol";

contract FacilitatorGasBenchMarkTest is DSTest {
    Vm vm = Vm(HEVM_ADDRESS);
    Facilitator facilitator;
    TestERC721 erc721 = new TestERC721();
    TestERC20 erc20 = new TestERC20();
    uint256 tokenId;
    uint16 rate = 15;
    uint128 amount = 1e20;
    uint32 duration = 1000;
    uint256 startTimestamp = 5;
    bool inc = true;

    function setUp() public {
        FacilitatorFactory factory = new FacilitatorFactory();
        (, , facilitator) = factory.newFacilitator(address(this));

        // approve for lending
        erc20.mint(address(this), amount * 3);
        erc20.approve(address(facilitator), amount * 3);

        // create a loan so we can close it or lend against it
        tokenId = erc721.mint();
        erc721.approve(address(facilitator), tokenId);
        facilitator.createLoan(
            tokenId,
            address(erc721),
            rate,
            amount,
            address(erc20),
            duration,
            address(this),
            inc
        );

        // mint another erc721 so we can create a second loan
        erc721.mint();
        erc721.approve(address(facilitator), tokenId + 1);

        // prevent errors from timestamp 0
        vm.warp(startTimestamp);

        // create another loan and lend against it so we can buyout or repay
        erc721.mint();
        erc721.approve(address(facilitator), tokenId + 2);
        facilitator.createLoan(
            tokenId + 2,
            address(erc721),
            rate,
            amount,
            address(erc20),
            duration,
            address(this),
            inc
        );
        facilitator.lend(
            2,
            rate,
            amount,
            duration,
            address(this)
        );
    }

    function testCreateLoan() public {
        facilitator.createLoan(
            tokenId + 1,
            address(erc721),
            rate,
            amount,
            address(erc20),
            duration,
            address(this),
            inc
        );
    }

    function testCloseLoan() public {
        facilitator.closeLoan(1, address(this));
    }

    function testLend() public {
        facilitator.lend(
            1,
            rate,
            amount,
            duration,
            address(this)
        );
    }

    function testLendBuyout() public {
        facilitator.lend(
            2,
            rate,
            amount + ((amount * 10) / 100),
            duration,
            address(this)
        );
    }

    function testRepayAndClose() public {
        facilitator.repayAndCloseLoan(2);
    }

    function testSeizeCollateral() public {
        vm.warp(startTimestamp + duration + 1);
        facilitator.seize(2, address(this));
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

contract FacilitatorTest is DSTest {
    event CreateLoan(
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

    event Lend(
        uint256 indexed id,
        address indexed lender,
        uint256 rate,
        uint256 amount,
        uint256 duration
    );

    event BuyoutLender(
        uint256 indexed id,
        address indexed lender,
        address indexed replacedLoanOwner,
        uint256 interestEarned,
        uint256 replacedAmount
    );

    Vm vm = Vm(HEVM_ADDRESS);

    Facilitator facilitator;
    BorrowTicket borrowTicket;
    LendTicket lendTicket;

    address borrower = address(1);
    address lender = address(2);

    TestERC721 erc721 = new TestERC721();
    TestERC20 erc20 = new TestERC20();

    uint16 rate = 15;
    uint128 amount = 1e20;
    uint32 duration = 1000;
    bool inc = true;
    uint256 startTimestamp = 5;
    uint256 tokenId;

    function setUp() public {
        FacilitatorFactory factory = new FacilitatorFactory();
        (borrowTicket, lendTicket, facilitator) = factory.newFacilitator(
            address(this)
        );
        vm.warp(startTimestamp);

        vm.startPrank(borrower);
        tokenId = erc721.mint();
        erc721.approve(address(facilitator), tokenId);
        vm.stopPrank();
    }

    function testCreateLoanEmitsCorrectly() public {
        vm.expectEmit(true, true, true, true);
        
        emit CreateLoan(1, borrower, address(erc721), tokenId, address(erc20), amount, rate, duration, inc);

        vm.prank(borrower);
        facilitator.createLoan(
            tokenId,
            address(erc721),
            rate,
            amount,
            address(erc20),
            duration,
            borrower,
            inc
        );
    }

    function testCreateLoanTransfersCollateralToSelf() public {
        vm.prank(borrower);
        facilitator.createLoan(
            tokenId,
            address(erc721),
            rate,
            amount,
            address(erc20),
            duration,
            borrower,
            inc
        );

        assertEq(erc721.ownerOf(tokenId), address(facilitator));
    }

    function testCreateLoanMintsBorrowTicketCorrectly() public {
        address mintBorrowTicketTo = address(3);
        vm.prank(borrower);
        uint256 loanId = facilitator.createLoan(
            tokenId,
            address(erc721),
            rate,
            amount,
            address(erc20),
            duration,
            mintBorrowTicketTo,
            inc
        );

        assertEq(borrowTicket.ownerOf(loanId), mintBorrowTicketTo);
    }

    function testCreateLoanSetsValuesCorrectly(
        uint16 maxPerAnnumInterest,
        uint128 amount,
        uint32 duration,
        address mintTo
    ) public {
        vm.assume(amount > 0);
        vm.assume(duration > 0);
        vm.assume(mintTo != address(0));

        vm.prank(borrower);
        uint256 loanId = facilitator.createLoan(
            tokenId,
            address(erc721),
            maxPerAnnumInterest,
            amount,
            address(erc20),
            duration,
            mintTo,
            inc
        );
     
        IFacilitator.Loan memory loan = facilitator.loanInfoStruct(loanId);

        assertTrue(!loan.closed);
        assertEq(loan.duration, duration);
        assertEq(loan.rate, maxPerAnnumInterest);
        assertEq(loan.amount, amount);
        assertEq(loan.timestamp, 0);
        assertEq(loan.interest, 0);
        assertEq(loan.erc721, address(erc721));
        assertEq(loan.tokenId, tokenId);
        assertEq(loan.erc20, address(erc20));
        assertEq(loan.originationFeeRate, facilitator.originationFeeRate());
        assertTrue(loan.inc == inc);
    }

    function testCreateLoanZeroDurationNotAllowed() public {
        vm.startPrank(borrower);
        vm.expectRevert("0 duration");
        facilitator.createLoan(
            tokenId,
            address(erc721),
            rate,
            amount,
            address(erc20),
            0,
            borrower,
            inc
        );
    }

    function testCreateLoanZeroAmountNotAllowed() public {
        vm.startPrank(borrower);
        vm.expectRevert("0 loan amount");
        facilitator.createLoan(
            tokenId,
            address(erc721),
            rate,
            0,
            address(erc20),
            duration,
            borrower,
            inc
        );
    }

    function testCreateLoanAddressZeroCollateralFails() public {
        vm.startPrank(borrower);
        vm.expectRevert(bytes(""));
        facilitator.createLoan(
            tokenId,
            address(0),
            rate,
            amount,
            address(erc20),
            duration,
            borrower,
            inc
        );
    }

    function testBorrowTicketUnusableAsCollateral() public {
        (, uint256 loanId) = setUpLoanForTest(borrower);
        vm.startPrank(borrower);

        borrowTicket.approve(address(facilitator), loanId);
        vm.expectRevert("borrow ticket collateral");
        facilitator.createLoan(
            loanId,
            address(borrowTicket),
            rate,
            amount,
            address(erc20),
            duration,
            borrower,
            inc
        );
    }

    function testLendTicketUnusableAsCollateral() public {
        (, uint256 loanId) = setUpLoanWithLenderForTest(borrower, lender);
        vm.startPrank(lender);

        lendTicket.approve(address(facilitator), loanId);
        vm.expectRevert("lend ticket collateral");
        facilitator.createLoan(
            loanId,
            address(lendTicket),
            rate,
            amount,
            address(erc20),
            duration,
            borrower,
            inc
        );
    }

    function testSuccessfulCloseLoan() public {
        (uint256 tokenId, uint256 loanId) = setUpLoanForTest(borrower);
        vm.startPrank(borrower);

        facilitator.closeLoan(loanId, borrower);
        assertEq(erc721.ownerOf(tokenId), borrower); // make sure borrower gets their NFT back
        (bool closed, , , , , , , , , , ) = facilitator.loanInfo(loanId);
        assertTrue(closed); // make sure loan was closed
    }

    function testClosingAlreadyClosedLoan() public {
        (, uint256 loanId) = setUpLoanForTest(borrower);
        vm.startPrank(borrower);

        facilitator.closeLoan(loanId, borrower);

        // closing an already closed loan should revert
        vm.expectRevert("loan closed");
        facilitator.closeLoan(loanId, borrower);
    }

    function testClosingLoanWithLender() public {
        (, uint256 loanId) = setUpLoanForTest(borrower);
        vm.startPrank(borrower);

        erc20.mint(borrower, amount);
        erc20.approve(address(facilitator), amount); // approve for lending
        vm.warp(startTimestamp); // make sure there's a non-zero timestamp
        facilitator.lend(
            loanId,
            rate,
            amount,
            duration,
            borrower
        ); // have borrower lend, this is not realistic, but will do for this test

        // loan has lender, should now revert
        vm.expectRevert(
            "has lender"
        );
        facilitator.closeLoan(loanId, borrower);
    }

    function testClosingLoanFromNonBorrower() public {
        (, uint256 loanId) = setUpLoanForTest(borrower);

        vm.startPrank(address(2));
        vm.expectRevert("borrow ticket holder only");
        facilitator.closeLoan(loanId, borrower);
        vm.stopPrank();
    }

    function testInterestExceedingUint128BuyoutReverts() public {
        amount = type(uint128).max;
        // 100% APR
        rate = 1000;
        (, uint256 loanId) = setUpLoanWithLenderForTest(borrower, lender);
        facilitator.interestOwed(loanId);
        vm.warp(startTimestamp + 366 days);

        vm.expectRevert(
            "interest exceeds uint128"
        );
        facilitator.lend(loanId, 0, amount, duration, address(4));
    }

    function testInterestExceedingUint128InterestOwed() public {
        amount = type(uint128).max;
        // 100% APR
        rate = 1000;
        (, uint256 loanId) = setUpLoanWithLenderForTest(borrower, lender);
        vm.warp(startTimestamp + 366 days);
        facilitator.interestOwed(loanId);
    }

    function testRepayInterestOwedExceedingUint128() public {
        amount = type(uint128).max;
        // 100% APR
        rate = 1000;
        (, uint256 loanId) = setUpLoanWithLenderForTest(borrower, lender);
        vm.warp(startTimestamp + 366 days);
        uint256 t = facilitator.totalOwed(loanId);
        vm.startPrank(address(3));
        erc20.mint(address(3), t);
        erc20.approve(address(facilitator), t);
        facilitator.repayAndCloseLoan(loanId);
        vm.stopPrank();
    }

    function testLendMintsLendTicketCorrectly() public {
        (, uint256 loanId) = setUpLoanForTest(borrower);
        setUpLender(lender);
        vm.startPrank(lender);
        facilitator.lend(
            loanId,
            rate,
            amount,
            duration,
            lender
        );

        assertEq(lendTicket.ownerOf(loanId), lender);
    }

    function testLendFailsWithAddressZeroLoanAsset() public {
        erc20 = TestERC20(address(0));
        (, uint256 loanId) = setUpLoanForTest(borrower);
    
        vm.expectRevert('invalid loan');
        facilitator.lend(
            loanId,
            rate,
            amount,
            duration,
            lender
        );
    }

    // function testLendFailsWithERC777Token() public {
    //     TestERC777 token = new TestERC777();
    //     erc20 = TestERC20(address(token));
    //     (, uint256 loanId) = setUpLoanForTest(borrower);

    //     erc20.mint(address(this), amount);
    //     erc20.approve(address(facilitator), amount);

    //     vm.expectRevert("ERC777 unsupported");
    //     facilitator.lend(
    //         loanId,
    //         rate,
    //         amount,
    //         duration,
    //         lender
    //     );
    // }

    function testLendFailsWithEOALoanAsset() public {
        erc20 = TestERC20(address(1));
        (, uint256 loanId) = setUpLoanForTest(borrower);
    
        vm.expectRevert('invalid loan');
        facilitator.lend(
            loanId,
            rate,
            amount,
            duration,
            lender
        );
    }

    function testLendTransfersERC20Correctly() public {
        (, uint256 loanId) = setUpLoanForTest(borrower);
        setUpLender(lender);

        uint256 lenderBalance = erc20.balanceOf(lender);

        vm.startPrank(lender);
        facilitator.lend(
            loanId,
            rate,
            amount,
            duration,
            lender
        );

        assertEq(erc20.balanceOf(lender), lenderBalance - amount);
        uint256 facilitatorTake = (amount *
            facilitator.originationFeeRate()) / facilitator.SCALAR();
        assertEq(erc20.balanceOf(address(facilitator)), facilitatorTake);
        assertEq(erc20.balanceOf(borrower), amount - facilitatorTake);
    }

    function testLendUpdatesValuesCorrectly(
        uint16 rate,
        uint128 amount,
        uint32 duration,
        address sendTo
    ) public {
        vm.assume(rate <= rate);
        vm.assume(amount >= amount);
        vm.assume(duration >= duration);
        vm.assume(sendTo != address(0));

        (uint256 tokenId, uint256 loanId) = setUpLoanForTest(borrower);

        erc20.mint(address(this), amount);
        erc20.approve(address(facilitator), amount);

        facilitator.lend(loanId, rate, amount, duration, sendTo);
       
        IFacilitator.Loan memory loan = facilitator.loanInfoStruct(loanId);

        assertTrue(!loan.closed);
        assertEq(loan.duration, duration);
        assertEq(loan.rate, rate);
        assertEq(loan.amount, amount);
        assertEq(loan.timestamp, block.timestamp);
        assertEq(loan.interest, 0);
        assertEq(loan.erc721, address(erc721));
        assertEq(loan.tokenId, tokenId);
        assertEq(loan.erc20, address(erc20));
        assertEq(loan.originationFeeRate, facilitator.originationFeeRate());
        assertTrue(loan.inc == inc);
    }

    function testLendEmitsCorrectly() public {
        (, uint256 loanId) = setUpLoanForTest(borrower);

        erc20.mint(address(this), amount);
        erc20.approve(address(facilitator), amount);

        vm.expectEmit(true, true, false, true);
        emit Lend(
            loanId,
            address(this),
            rate,
            amount,
            duration
        );

        facilitator.lend(
            loanId,
            rate,
            amount,
            duration,
            address(1)
        );
    }

    function testSuccessfulLend() public {
        (, uint256 loanId) = setUpLoanForTest(borrower);

        setUpLender(lender);
        vm.startPrank(lender);
        uint256 lenderBalance = erc20.balanceOf(lender);

        facilitator.lend(
            loanId,
            rate,
            amount,
            duration,
            lender
        );
        (
            ,
            ,
            ,
            uint40 lastAccumulatedTimestamp,
            ,
            ,
            ,
            ,
            uint256 interest,
            ,

        ) = facilitator.loanInfo(loanId);
        assertEq(lastAccumulatedTimestamp, startTimestamp);
        assertEq(interest, 0);

        // make sure lenders erc20 is transfered and lender gets lend ticket
        assertEq(erc20.balanceOf(lender), lenderBalance - amount);
        assertEq(lendTicket.ownerOf(loanId), lender);

        // make sure Facilitator subtracted origination fee
        uint256 facilitatorTake = (amount *
            facilitator.originationFeeRate()) / facilitator.SCALAR();
        assertEq(erc20.balanceOf(address(facilitator)), facilitatorTake);

        // make sure borrower got their loan in TestERC20
        assertEq(erc20.balanceOf(borrower), amount - facilitatorTake);
    }

    function testLoanValuesNotChangedAfterLend() public {
        (uint256 tokenId, uint256 loanId) = setUpLoanForTest(borrower);

        setUpLender(lender);
        vm.startPrank(lender);

        facilitator.lend(
            loanId,
            rate,
            amount,
            duration,
            lender
        );
        
        IFacilitator.Loan memory loan = facilitator.loanInfoStruct(loanId);

        assertTrue(!loan.closed);
        assertEq(rate, loan.rate);
        assertEq(loan.timestamp, startTimestamp);
        assertEq(loan.duration, duration);
        assertEq(loan.interest, 0);
        assertEq(loan.amount, amount);
        assertEq(loan.erc721, address(erc721));
        assertEq(loan.erc20, address(erc20));
        assertEq(loan.tokenId, tokenId);
        assertTrue(loan.inc == inc);
    }

    function testLendFailsIfHigherrate(
        uint16 rate,
        uint32 duration,
        uint128 amount
    ) public {
        vm.assume(rate > rate);
        vm.assume(duration >= duration);
        vm.assume(amount >= amount);
        (, uint256 loanId) = setUpLoanForTest(borrower);

        setUpLender(lender);
        vm.startPrank(lender);
        vm.expectRevert("rate too high");
        facilitator.lend(loanId, rate, amount, duration, lender);
    }

    function testLendFailsIfLowerAmount(
        uint16 rate,
        uint32 duration,
        uint128 amount
    ) public {
        vm.assume(rate <= rate);
        vm.assume(duration >= duration);
        vm.assume(amount < amount);
        (, uint256 loanId) = setUpLoanForTest(borrower);

        setUpLender(lender);
        vm.startPrank(lender);
        vm.expectRevert("amount too low");
        facilitator.lend(loanId, rate, amount, duration, lender);
    }

    function testLendFailsIfLowerDuration(
        uint16 rate,
        uint32 duration,
        uint128 amount
    ) public {
        vm.assume(rate <= rate);
        vm.assume(duration < duration);
        vm.assume(amount >= amount);
        (, uint256 loanId) = setUpLoanForTest(borrower);

        setUpLender(lender);
        vm.startPrank(lender);
        vm.expectRevert("duration too low");
        facilitator.lend(loanId, rate, amount, duration, lender);
    }

    function testLendFailsIfAmountGreaterAndIncreaseNotAllowed(uint128 amount) public {
        vm.assume(amount > amount);
        inc = false;
        (, uint256 loanId) = setUpLoanForTest(borrower);

        setUpLender(lender);
        vm.startPrank(lender);
        vm.expectRevert("invalid amount");
        facilitator.lend(loanId, rate, amount, duration, lender);
    }

    function testLendFailsIfAmountLessAndIncreaseNotAllowed(uint128 amount) public {
        vm.assume(amount < amount);
        inc = false;
        (, uint256 loanId) = setUpLoanForTest(borrower);

        setUpLender(lender);
        vm.startPrank(lender);
        vm.expectRevert("invalid amount");
        facilitator.lend(loanId, rate, amount, duration, lender);
    }

    function testLendWorksWithAmountSameAndIncreaseNotAllowed() public {
        inc = false;
        (, uint256 loanId) = setUpLoanForTest(borrower);

        setUpLender(lender);
        vm.startPrank(lender);
        facilitator.lend(loanId, rate, amount, duration, lender);
    }

    function testLendWithFeeOnTransferToken(
        uint128 amount
    ) public {
        vm.assume(amount > 0);
        amount = amount;
        FeeOnTransferERC20 token = new FeeOnTransferERC20();
        erc20 = TestERC20(address(token));
        (, uint256 loanId) = setUpLoanForTest(borrower);
        erc20.mint(address(this), amount);
        erc20.approve(address(facilitator), amount);

        facilitator.lend(loanId, rate, amount, duration, borrower);

        uint256 facilitatorBalance = erc20.balanceOf(address(facilitator));
        uint256 borrowerBalance = erc20.balanceOf(borrower);

        uint256 normalTake = calculateTake(amount);
        uint256 expectedTake = normalTake - (normalTake * token.feeBips() / 10_000);
        uint256 normalBorrowerBalance = (amount - normalTake);
        uint256 expectedBorrowerBalance = normalBorrowerBalance - (normalBorrowerBalance * token.feeBips() / 10_000);

        assertEq(
            facilitatorBalance,
            expectedTake
        );
        assertEq(
            borrowerBalance,
            expectedBorrowerBalance
        );
    }

    function testInterestAccruesCorrectly() public {
        (, uint256 loanId) = setUpLoanForTest(borrower);
        setUpLender(lender);
        vm.startPrank(lender);
        facilitator.lend(
            loanId,
            10, // 1% annual rate
            amount,
            duration,
            lender
        );

        uint256 interestAccrued = facilitator.interestOwed(loanId);
        assertEq(interestAccrued, 0);

        uint256 elapsedTime = 1; // simulate fast forwarding 100 seconds
        vm.warp(startTimestamp + elapsedTime);

        // 1 second with 1% annual = 0.000000031709792% per second
        // 0.00000000031709792 * 10^20 = 31709791983
        assertEq(facilitator.interestOwed(loanId), 31709791983);

        // 1 year with 1% annual on 10^20 = 10^18
        // tiny loss of precision, 10^18 - 999999999997963200 = 2036800
        // => 0.000000000002037 in the case of currencies with 18 decimals
        vm.warp(startTimestamp + 365 days);
        assertEq(facilitator.interestOwed(loanId), 999999999997963200);
    }

    function testBuyoutSucceedsIfRateImproved(uint16 rate) public {
        vm.assume(rate <= decreaseByMinPercent(rate));
        (, uint256 loanId) = setUpLoanWithLenderForTest(borrower, lender);

        address newLender = address(3);
        setUpLender(newLender);
        vm.startPrank(newLender);

        facilitator.lend(loanId, rate, amount, duration, newLender);
    }

    function testBuyoutSucceedsIfAmountImproved(uint128 amount) public {
        vm.assume(amount >= increaseByMinPercent(amount));
        (, uint256 loanId) = setUpLoanWithLenderForTest(borrower, lender);

        address newLender = address(3);
        setUpLender(newLender);
        uint256 amountIncrease = amount - amount;
        erc20.mint(newLender, amountIncrease);

        vm.startPrank(newLender);
        facilitator.lend(loanId, rate, amount, duration, newLender);
    }

    function testBuyoutFailsWithAmountImprovedIfIncreaseNotAllowed(
        uint128 amount
    ) 
        public 
    {
        vm.assume(amount >= increaseByMinPercent(amount));
        inc = false;
        (, uint256 loanId) = setUpLoanWithLenderForTest(borrower, lender);

        address newLender = address(3);
        setUpLender(newLender);
        uint256 amountIncrease = amount - amount;
        erc20.mint(newLender, amountIncrease);

        vm.startPrank(newLender);
        vm.expectRevert('amount increase not allowed');
        facilitator.lend(loanId, rate, amount, duration, newLender);
    }

    function testBuyoutFailsWithAmountAndDurationIncreasedIfAmountIncreaseNotAllowed(
        uint128 amount,
        uint32 duration
    )
        public 
    {
        vm.assume(amount >= increaseByMinPercent(amount));
        vm.assume(duration >= increaseByMinPercent(duration));
        inc = false;
        (, uint256 loanId) = setUpLoanWithLenderForTest(borrower, lender);

        address newLender = address(3);
        setUpLender(newLender);
        uint256 amountIncrease = amount - amount;
        erc20.mint(newLender, amountIncrease);

        vm.startPrank(newLender);
        vm.expectRevert('amount increase not allowed');
        facilitator.lend(loanId, rate, amount, duration, newLender);
    }

    function testBuyoutSucceedsIfDurationImproved(uint32 duration) public {
        vm.assume(duration >= increaseByMinPercent(duration));
        (, uint256 loanId) = setUpLoanWithLenderForTest(borrower, lender);

        address newLender = address(3);
        setUpLender(newLender);
        vm.startPrank(newLender);

        facilitator.lend(loanId, rate, amount, duration, newLender);
    }

    function testBuyoutSucceedsIfDurationImprovedAmoutIncreaseNotAllowed() public {
        // sanity check + want to log gas (because fuzz don't log)
        (, uint256 loanId) = setUpLoanWithLenderForTest(borrower, lender);

        address newLender = address(3);
        setUpLender(newLender);
        vm.startPrank(newLender);

        facilitator.lend(
            loanId, 
            rate,
            amount, 
            uint32(increaseByMinPercent(duration)),
            newLender
        );
    }

    function testBuyoutUpdatesValuesCorrectly() public {
        (uint256 tokenId, uint256 loanId) = setUpLoanWithLenderForTest(
            borrower,
            lender
        );

        address newLender = address(3);
        setUpLender(newLender);
        uint32 newDuration = uint32(increaseByMinPercent(duration));

        vm.prank(newLender);
        facilitator.lend(
            loanId,
            rate,
            amount,
            newDuration,
            address(1)
        );

        IFacilitator.Loan memory loan = facilitator.loanInfoStruct(loanId);

        assertTrue(!loan.closed);
        assertEq(loan.rate, rate);
        assertEq(newDuration, loan.duration);
        assertEq(amount, loan.amount);
        assertEq(loan.timestamp, startTimestamp);
        assertEq(loan.interest, 0);
        // does not change immutable values
        assertEq(loan.erc721, address(erc721));
        assertEq(loan.erc20, address(erc20));
        assertEq(loan.tokenId, tokenId);
        assertTrue(inc == loan.inc);
    }

    function testBuyoutUpdatesAccumulatedInterestCorrectly() public {
        (, uint256 loanId) = setUpLoanWithLenderForTest(borrower, lender);
        uint256 elapsedTime = 100;
        vm.warp(startTimestamp + elapsedTime);
        uint256 interest = facilitator.interestOwed(loanId);
        uint32 newDuration = uint32(increaseByMinPercent(duration));

        erc20.mint(address(this), amount + interest);
        erc20.approve(address(facilitator), amount + interest);

        facilitator.lend(
            loanId,
            rate,
            amount,
            newDuration,
            address(1)
        );

        IFacilitator.Loan memory loan = facilitator.loanInfoStruct(loanId);

        assertEq(loan.timestamp, startTimestamp + elapsedTime);
        assertEq(loan.interest, interest);
    }

    function testBuyoutTransfersLendTicket() public {
        (, uint256 loanId) = setUpLoanWithLenderForTest(borrower, lender);

        address newLender = address(3);
        setUpLender(newLender);
        uint32 newDuration = uint32(increaseByMinPercent(duration));

        vm.prank(newLender);
        facilitator.lend(
            loanId,
            rate,
            amount,
            newDuration,
            newLender
        );

        assertEq(lendTicket.ownerOf(loanId), newLender);
    }

    function testBuyoutPaysPreviousLenderCorrectly(uint128 amount) public {
        vm.assume(amount >= amount);
        (, uint256 loanId) = setUpLoanWithLenderForTest(borrower, lender);

        vm.warp(startTimestamp + 100);
        uint256 interest = facilitator.interestOwed(loanId);

        erc20.mint(address(this), amount + interest);
        erc20.approve(address(facilitator), amount + interest);

        uint256 beforeBalance = erc20.balanceOf(lender);

        facilitator.lend(
            loanId,
            rate,
            amount,
            uint32(increaseByMinPercent(duration)),
            address(1)
        );

        assertEq(beforeBalance + amount + interest, erc20.balanceOf(lender));
    }

    function testBuyoutPaysBorrowerCorrectly(uint128 amount) public {
        vm.assume(amount >= amount);
        (, uint256 loanId) = setUpLoanWithLenderForTest(borrower, lender);

        erc20.mint(address(this), amount);
        erc20.approve(address(facilitator), amount);

        uint256 beforeBalance = erc20.balanceOf(borrower);

        facilitator.lend(
            loanId,
            rate,
            amount,
            uint32(increaseByMinPercent(duration)),
            address(1)
        );

        uint256 amountIncrease = amount - amount;
        uint256 originationFee = (amountIncrease *
            facilitator.originationFeeRate()) / facilitator.SCALAR();
        assertEq(
            beforeBalance + (amountIncrease - originationFee),
            erc20.balanceOf(borrower)
        );
    }

    function testBuyoutPaysFacilitatorCorrectly(uint128 amount) public {
        vm.assume(amount >= amount);
        (, uint256 loanId) = setUpLoanWithLenderForTest(borrower, lender);

        address newLender = address(3);
        erc20.mint(newLender, amount);
        vm.startPrank(newLender);
        erc20.approve(address(facilitator), amount);

        uint256 beforeBalance = erc20.balanceOf(address(facilitator));

        facilitator.lend(
            loanId,
            rate,
            amount,
            uint32(increaseByMinPercent(duration)),
            address(1)
        );

        uint256 amountIncrease = amount - amount;
        uint256 originationFee = (amountIncrease *
            facilitator.originationFeeRate()) / facilitator.SCALAR();
        assertEq(
            beforeBalance + originationFee,
            erc20.balanceOf(address(facilitator))
        );
    }
    
    function testBuyoutFeeOnTransferPaysPreviousLenderCorrectly(
        uint128 amount
    ) public {
        vm.assume(amount >= amount);
        FeeOnTransferERC20 token = new FeeOnTransferERC20();
        erc20 = TestERC20(address(token));
        (, uint256 loanId) = setUpLoanWithLenderForTest(borrower, lender);

        vm.warp(startTimestamp + 100);
        uint256 interest = facilitator.interestOwed(loanId);

        erc20.mint(address(this), amount + interest);
        erc20.approve(address(facilitator), amount + interest);

        uint256 beforeBalance = erc20.balanceOf(lender);

        facilitator.lend(
            loanId,
            rate,
            amount,
            uint32(increaseByMinPercent(duration)),
            address(1)
        );

        uint256 expectedIncrease = (amount + interest)
            - ((amount + interest) * token.feeBips() / 10_000);
        assertEq(beforeBalance + expectedIncrease, erc20.balanceOf(lender));
    }

    function testBuyoutFeeOnTransferPaysBorrowerCorrectly(
        uint128 amount
    ) public {
        vm.assume(amount >= amount);
        FeeOnTransferERC20 token = new FeeOnTransferERC20();
        erc20 = TestERC20(address(token));
        (, uint256 loanId) = setUpLoanWithLenderForTest(borrower, lender);

        erc20.mint(address(this), amount);
        erc20.approve(address(facilitator), amount);

        uint256 beforeBalance = erc20.balanceOf(borrower);

        facilitator.lend(
            loanId,
            rate,
            amount,
            uint32(increaseByMinPercent(duration)),
            address(1)
        );

        uint256 amountIncrease = amount - amount;
        uint256 originationFee = calculateTake(amountIncrease);
        uint256 expectedIncrease = (amountIncrease - originationFee)
            - ((amountIncrease - originationFee) * token.feeBips() / 10_000);
        assertEq(
            beforeBalance + expectedIncrease,
            erc20.balanceOf(borrower)
        );
    }

    function testBuyoutFeeOnTransferPaysFacilitatorCorrectly(uint128 amount) public {
        vm.assume(amount >= amount);
        FeeOnTransferERC20 token = new FeeOnTransferERC20();
        erc20 = TestERC20(address(token));
        (, uint256 loanId) = setUpLoanWithLenderForTest(borrower, lender);

        address newLender = address(3);
        erc20.mint(newLender, amount);
        vm.startPrank(newLender);
        erc20.approve(address(facilitator), amount);

        uint256 beforeBalance = erc20.balanceOf(address(facilitator));

        facilitator.lend(
            loanId,
            rate,
            amount,
            uint32(increaseByMinPercent(duration)),
            address(1)
        );

        uint256 amountIncrease = amount - amount;
        uint256 originationFee = calculateTake(amountIncrease)
            - calculateTake(amountIncrease) * token.feeBips() / 10_000;
        assertEq(
            beforeBalance + originationFee,
            erc20.balanceOf(address(facilitator))
        );
    }

    function testBuyoutPaysFacilitatorCorrectlyWhenFeeChanged(uint128 amount) public {
        vm.assume(amount >= amount);
        (, uint256 loanId) = setUpLoanWithLenderForTest(borrower, lender);
        uint256 oldOriginationFee = facilitator.originationFeeRate();
        facilitator.updateOriginationFeeRate(50);

        address newLender = address(3);
        erc20.mint(newLender, amount);
        vm.startPrank(newLender);
        erc20.approve(address(facilitator), amount);

        uint256 beforeBalance = erc20.balanceOf(address(facilitator));

        facilitator.lend(
            loanId,
            rate,
            amount,
            uint32(increaseByMinPercent(duration)),
            address(1)
        );

        uint256 amountIncrease = amount - amount;
        uint256 originationFee = (amountIncrease *
            oldOriginationFee) / facilitator.SCALAR();
        assertEq(
            beforeBalance + originationFee,
            erc20.balanceOf(address(facilitator))
        );
    }

    function testBuyoutEmitsCorrectly() public {
        (, uint256 loanId) = setUpLoanWithLenderForTest(borrower, lender);

        address newLender = address(3);
        setUpLender(newLender);
        uint32 newDuration = uint32(increaseByMinPercent(duration));

        vm.expectEmit(true, true, true, true);
        emit BuyoutLender(loanId, newLender, lender, 0, amount);

        vm.expectEmit(true, true, false, true);
        emit Lend(loanId, newLender, rate, amount, newDuration);

        vm.prank(newLender);
        facilitator.lend(
            loanId,
            rate,
            amount,
            newDuration,
            address(1)
        );
    }

    function testBuyoutFailsIfTermsNotImproved() public {
        (, uint256 loanId) = setUpLoanWithLenderForTest(borrower, lender);

        address newLender = address(3);
        setUpLender(newLender);
        vm.startPrank(newLender);
        vm.expectRevert(
            "insufficient improvement"
        );
        facilitator.lend(
            loanId,
            rate,
            amount,
            duration,
            newLender
        );
    }

    function testBuyoutFailsIfamountNotSufficientlyImproved(uint128 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < decreaseByMinPercent(type(uint128).max));
        amount = amount;
        (, uint256 loanId) = setUpLoanWithLenderForTest(borrower, lender);

        address newLender = address(3);
        setUpLender(newLender);
        vm.startPrank(newLender);
        uint256 newAmount = increaseByMinPercent(amount) - 1;
        vm.expectRevert(
            "insufficient improvement"
        );
        facilitator.lend(
            loanId,
            rate,
            uint128(newAmount),
            duration,
            newLender
        );
        vm.stopPrank();
    }

    function testBuyoutFailsIfdurationNotSufficientlyImproved(uint32 duration) public {
        vm.assume(duration > 0);
        vm.assume(duration < decreaseByMinPercent(type(uint32).max));
        duration = duration;
        (, uint256 loanId) = setUpLoanWithLenderForTest(borrower, lender);

        address newLender = address(3);
        setUpLender(newLender);
        vm.startPrank(newLender);
        uint32 newDuration = uint32(increaseByMinPercent(duration) - 1);
        vm.expectRevert(
            "insufficient improvement"
        );
        facilitator.lend(
            loanId,
            rate,
            amount,
            newDuration,
            newLender
        );
        vm.stopPrank();
    }

    function testBuyoutFailsIfrateNotSufficientlyImproved(uint16 rate) public {
        rate = rate;
        (, uint256 loanId) = setUpLoanWithLenderForTest(borrower, lender);

        address newLender = address(3);
        setUpLender(newLender);
        vm.startPrank(newLender);
        uint16 newRate = uint16(decreaseByMinPercent(rate) + 1);
        // handle case where rate is 0
        newRate = newRate < rate ? newRate : rate;
        emit log_uint(rate);
        emit log_uint(newRate);
        vm.expectRevert(
            "insufficient improvement"
        );
        facilitator.lend(loanId, newRate, amount, duration, newLender);
        vm.stopPrank();
    }

    function testBuyoutFailsIfamountRegressed(
        uint16 newRate,
        uint32 newDuration,
        uint128 newAmount
    ) public {
        vm.assume(newRate <= rate);
        vm.assume(newDuration >= duration);
        vm.assume(newAmount < amount);
        (, uint256 loanId) = setUpLoanWithLenderForTest(borrower, lender);

        address newLender = address(3);
        setUpLender(newLender);
        vm.startPrank(newLender);
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        facilitator.lend(
            loanId,
            newRate,
            uint128(newAmount),
            newDuration,
            newLender
        );
        vm.stopPrank();
    }

    function testBuyoutFailsIfrateRegressed(
        uint16 newRate,
        uint32 newDuration,
        uint128 newAmount
    ) public {
        vm.assume(newRate > rate);
        vm.assume(newDuration >= duration);
        vm.assume(newAmount >= amount);
        (, uint256 loanId) = setUpLoanWithLenderForTest(borrower, lender);

        address newLender = address(3);
        setUpLender(newLender);
        vm.startPrank(newLender);
        vm.expectRevert("rate too high");
        facilitator.lend(
            loanId,
            newRate,
            uint128(newAmount),
            newDuration,
            newLender
        );
        vm.stopPrank();
    }

    function testBuyoutFailsIfDurationRegressed(
        uint16 newRate,
        uint32 newDuration,
        uint128 newAmount
    ) public {
        vm.assume(newRate <= rate);
        vm.assume(newDuration < duration);
        vm.assume(newAmount >= amount);
        (, uint256 loanId) = setUpLoanWithLenderForTest(borrower, lender);

        address newLender = address(3);
        setUpLender(newLender);
        vm.startPrank(newLender);
        vm.expectRevert("duration too low");
        facilitator.lend(
            loanId,
            newRate,
            uint128(newAmount),
            newDuration,
            newLender
        );
        vm.stopPrank();
    }

    function testRepayReentryOnBuyoutPaysNewOwner() public {
        vm.prank(borrower);
        RepayAndCloseERC20 token = new RepayAndCloseERC20(address(facilitator));
        erc20 = TestERC20(address(token));
        (, uint256 loanId) = setUpLoanWithLenderForTest(
            borrower,
            borrower
        );
        token.mint(lender, amount);
        vm.startPrank(lender);
        token.approve(address(facilitator), amount);
        facilitator.lend(loanId, rate, amount, uint32(increaseByMinPercent(duration)), lender);
        IFacilitator.Loan memory loan = facilitator.loanInfoStruct(loanId);
        // before the fix the previous lender could reenter and pay themselves 
        // and close the loan
        assertEq(loan.amount, token.balanceOf(lender));
    }

    function testLendReentryOnBuyoutIsNormalLend() public {
        address attacker = address(4);
        vm.prank(attacker);
        ReLendERC20 token = new ReLendERC20(address(facilitator));
        erc20 = TestERC20(address(token));
        (, uint256 loanId) = setUpLoanWithLenderForTest(
            attacker,
            attacker
        );
        token.mint(lender, amount);
        vm.startPrank(lender);
        token.approve(address(facilitator), amount);
        facilitator.lend(loanId, rate, amount, uint32(increaseByMinPercent(duration)), lender);
        IFacilitator.Loan memory loan = facilitator.loanInfoStruct(loanId);
        // before the fix the previous lender could reenter, change loan terms
        // and leave other lender with them
        assertEq(loan.amount, token.balanceOf(lender));
        assertEq(lendTicket.ownerOf(loanId), attacker);
    }

    function testRepayAndCloseSuccessful() public {
        (uint256 tokenId, uint256 loanId) = setUpLoanWithLenderForTest(
            borrower,
            lender
        );
        vm.warp(startTimestamp + 10); // warp so we have some interest accrued on the loan
        vm.startPrank(borrower);

        uint256 interestAccrued = facilitator.interestOwed(loanId);
        // give borrower enough money to pay back the loan
        erc20.mint(borrower, interestAccrued + calculateTake(amount)); 
        erc20.approve(address(facilitator), amount + interestAccrued);
        uint256 balanceOfBorrower = erc20.balanceOf(borrower);

        facilitator.repayAndCloseLoan(loanId);

        // ensure ERC20 balances are correct
        assertEq(
            erc20.balanceOf(borrower),
            balanceOfBorrower - (amount + interestAccrued)
        );
        assertEq(erc20.balanceOf(lender), amount + interestAccrued);

        assertEq(erc721.ownerOf(tokenId), borrower); // ensure borrower gets their NFT back
        IFacilitator.Loan memory loan = facilitator.loanInfoStruct(loanId);
        assertTrue(loan.closed);
    }

    function testRepayAndCloseFailsIfLoanClosed() public {
        (, uint256 loanId) = setUpLoanForTest(borrower);
        vm.startPrank(borrower);
        facilitator.closeLoan(loanId, borrower);
        vm.expectRevert("loan closed");
        facilitator.repayAndCloseLoan(loanId);
    }

    function testRepayAndCloseFailsIfNoLender() public {
        (, uint256 loanId) = setUpLoanForTest(borrower);
        vm.startPrank(borrower);
        vm.expectRevert("NOT_MINTED");
        facilitator.repayAndCloseLoan(loanId);
    }

    function testSeizeCollateralSuccessful() public {
        (uint256 tokenId, uint256 loanId) = setUpLoanWithLenderForTest(
            borrower,
            lender
        );
        vm.warp(startTimestamp + duration + 1); // fast forward to timestamp where loan would be overdue
        vm.prank(lender);

        facilitator.seize(loanId, lender);
        assertEq(erc721.ownerOf(tokenId), lender); // ensure lender seized collateral

        IFacilitator.Loan memory loan = facilitator.loanInfoStruct(loanId); // ensure loan is closed on-chain
        assertTrue(loan.closed);
    }

    function testSeizeCollateralFailsIfLoanNotOverdue() public {
        (, uint256 loanId) = setUpLoanWithLenderForTest(borrower, lender);
        vm.warp(startTimestamp + duration); // fast forward to timestamp where loan would not be overdue
        vm.prank(lender);

        vm.expectRevert("payment is not late");
        facilitator.seize(loanId, lender);
    }

    function testSeizeCollateralFailsIfNonLoanOwnerCalls() public {
        (, uint256 loanId) = setUpLoanWithLenderForTest(borrower, lender);
        address randomAddress = address(4);
        vm.prank(randomAddress);

        vm.expectRevert("lend ticket holder only");
        facilitator.seize(loanId, randomAddress);
    }

    function testSeizeCollateralFailsIfLoanIsClosed() public {
        (, uint256 loanId) = setUpLoanForTest(borrower);
        vm.prank(borrower);
        facilitator.closeLoan(loanId, borrower);

        vm.startPrank(lender);
        vm.expectRevert("loan closed");
        facilitator.seize(loanId, lender);
        vm.stopPrank();
    }

    function testUpdateOriginationFeeRevertsIfNotCalledByManager() public {
        vm.startPrank(address(1));
        vm.expectRevert("Ownable: caller is not the owner");
        facilitator.updateOriginationFeeRate(1);
    }

    function testUpdateOriginationFeeRevertsIfGreaterThanFivePercent() public {
        uint256 rateDecimals = facilitator.INTEREST_RATE_DECIMALS();
        vm.startPrank(address(this));
        vm.expectRevert("max fee 5%");
        facilitator.updateOriginationFeeRate(
            uint32(6 * (10**(rateDecimals - 2)))
        );
    }

    function testUpdateOriginationFeeWorks() public {
        uint256 oldRate = facilitator.originationFeeRate();
        (, uint256 loanId) = setUpLoanForTest(address(this));

        uint256 rateDecimals = facilitator.INTEREST_RATE_DECIMALS();
        uint256 newRate = 2 * (10**(rateDecimals - 2));
        facilitator.updateOriginationFeeRate(
            uint32(newRate)
        );
        assertEq(
            facilitator.originationFeeRate(),
            uint32(newRate)
        );

        (, uint256 loanId2) = setUpLoanForTest(address(this));
        assertEq(facilitator.loanInfoStruct(loanId2).originationFeeRate, uint96(newRate));
        assertEq(facilitator.loanInfoStruct(loanId).originationFeeRate, uint96(oldRate));
    }

    function testUpdateRequiredImprovementRateRevertsIfNotCalledByManager()
        public
    {
        vm.startPrank(address(1));
        vm.expectRevert("Ownable: caller is not the owner");
        facilitator.updateRequiredImprovementRate(1);
    }

    function testUpdateRequiredImprovementRateRevertsIf0() public {
        vm.startPrank(address(this));
        vm.expectRevert("0 improvement rate");
        facilitator.updateRequiredImprovementRate(0);
    }

    function testUpdateRequiredImprovementRateWorks() public {
        vm.startPrank(address(this));
        facilitator.updateRequiredImprovementRate(20 * facilitator.SCALAR());
        assertEq(
            facilitator.requiredImprovementRate(),
            20 * facilitator.SCALAR()
        );
    }

    function testLoanEndSecondsRevertsIfNoLender() public {
        (, uint256 loanId) = setUpLoanForTest(borrower);
        vm.expectRevert('loan has no lender');
        facilitator.loanEndSeconds(loanId);
    }

    function testLoanEndSecondsRevertsIfDoesNotExist() public {
        vm.expectRevert('loan has no lender');
        facilitator.loanEndSeconds(10);
    }

    function testLoanEndSecondsReturnsCorrectly() public {
        (, uint256 loanId) = setUpLoanWithLenderForTest(borrower,lender);
        uint256 end = facilitator.loanEndSeconds(loanId);
        assertEq(end, block.timestamp + duration);
    }

    function setUpLender(address lenderAddress) public {
        // create a lender address and give them some approved erc20
        vm.startPrank(lenderAddress);
        erc20.mint(lenderAddress, amount);
        erc20.approve(address(facilitator), 2**256 - 1); // approve for lending
        vm.stopPrank();
    }

    // returns tokenId of NFT used as collateral for the loan and loanId to be used in other test methods
    // 返回 用作 贷款 抵押品 的 NFT 的 tokenId 和 在 其他测试方法中 使用的 loanId
    function setUpLoanWithLenderForTest(address _borrower, address _lender)
        public 
        returns (uint256 tokenId, uint256 loanId) 
    {
        (tokenId, loanId) = setUpLoanForTest(_borrower);
        setUpLender(_lender);

        vm.startPrank(_lender);
        facilitator.lend(loanId, rate, amount, duration, _lender);
        vm.stopPrank();
    }

    // returns tokenId of NFT used as collateral for the loan and loanId to be used in other test methods
    // 返回 用作 贷款 抵押品 的 NFT 的 tokenId 和 在 其他测试方法中 使用的 loanId
    function setUpLoanForTest(address borrower)
        public
        returns (uint256 tokenId, uint256 loanId)
    {
        vm.startPrank(borrower);
        tokenId = erc721.mint();
        erc721.approve(address(facilitator), tokenId);

        loanId = facilitator.createLoan(
            tokenId,
            address(erc721),
            rate,
            amount,
            address(erc20),
            duration,
            borrower,
            inc
        );
        vm.stopPrank();
    }

    function increaseByMinPercent(uint256 old) public view returns (uint256) {
        return
            old +
            Math.ceilDiv(old * facilitator.requiredImprovementRate(),
            facilitator.SCALAR());
    }

    function decreaseByMinPercent(uint256 old) public view returns (uint256) {
        return
            old -
            Math.ceilDiv(old * facilitator.requiredImprovementRate(),
            facilitator.SCALAR());
    }

    function calculateTake(uint256 amount) public view returns (uint256) {
        return
            (amount * facilitator.originationFeeRate()) / facilitator.SCALAR();
    }
}

contract NFTLendTicketTest is DSTest {
    Vm vm = Vm(HEVM_ADDRESS);
    Facilitator facilitator;
    BorrowTicket borrowTicket;
    LendTicket lendTicket;

    function setUp() public {
        FacilitatorFactory factory = new FacilitatorFactory();
        (borrowTicket, lendTicket, facilitator) = factory.newFacilitator(
            address(this)
        );
    }

    function testFacilitatorTransferSuccessful() public {
        address holder = address(1);
        address receiver = address(2);
        uint256 loanId = 0;

        vm.startPrank(address(facilitator));

        lendTicket.mint(holder, loanId);
        assertEq(lendTicket.ownerOf(loanId), holder);

        lendTicket.transfer(holder, receiver, 0);
        assertEq(lendTicket.ownerOf(loanId), receiver);
    }

    function testFacilitatorTransferRevertsIfNotFacilitator() public {
        vm.startPrank(address(1));
        vm.expectRevert("Ticket: only loan facilitator");
        lendTicket.transfer(address(1), address(2), 0);
    }
}
