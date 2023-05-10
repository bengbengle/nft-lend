
const { expect } = require("chai");
const { waffle } = require("hardhat");
const { singletons } = require('@openzeppelin/test-helpers');
const provider = waffle.provider;

describe("Facilitator contract", function () {

    let Facilitator;
    let LendTicket;
    let TestERC721;
    // defaults
    var interestRateDecimals
    var originationFeeRate
    var scalar
    var interest = ethers.BigNumber.from(10);
    var duration = ethers.BigNumber.from(10);
    var amount = ethers.BigNumber.from(505).mul(ethers.BigNumber.from(10).pow(17))

    var tokenId = ethers.BigNumber.from(1000);
    let BorrowTicketDescriptor;

    beforeEach(async function () {
        [manager, erc721Holder, erc20Holder, addr4, addr5, ...addrs] = await ethers.getSigners();   
        
        await singletons.ERC1820Registry(addr4.address);

        BorrowTicketSVGHelperContract = await ethers.getContractFactory("BorrowTicketSVGHelper");
        BorrowTicketSVGHelper = await BorrowTicketSVGHelperContract.deploy()
        await BorrowTicketSVGHelper.deployed();

        LendTicketSVGHelperContract = await ethers.getContractFactory("LendTicketSVGHelper");
        LendTicketSVGHelper = await LendTicketSVGHelperContract.deploy()
        await LendTicketSVGHelper.deployed();

        BorrowTicketDescriptorContract = await ethers.getContractFactory("BorrowTicketDescriptor");
        BorrowTicketDescriptor = await BorrowTicketDescriptorContract.deploy(BorrowTicketSVGHelper.address)
        await BorrowTicketDescriptor.deployed();

        LendTicketDescriptorContract = await ethers.getContractFactory("LendTicketDescriptor");
        LendTicketDescriptor = await LendTicketDescriptorContract.deploy(LendTicketSVGHelper.address)
        await LendTicketDescriptor.deployed();
        
        FacilitatorContract = await ethers.getContractFactory("Facilitator");
        Facilitator = await FacilitatorContract.deploy(manager.address);
        await Facilitator.deployed();

        interestRateDecimals = await Facilitator.INTEREST_RATE_DECIMALS();
        originationFeeRate = ethers.BigNumber.from(10).pow(interestRateDecimals - 2);
        scalar = ethers.BigNumber.from(10).pow(interestRateDecimals);

        LendTicketContract = await ethers.getContractFactory("LendTicket");
        LendTicket = await LendTicketContract.deploy(Facilitator.address, LendTicketDescriptor.address);
        await LendTicket.deployed();

        BorrowTicketContract = await ethers.getContractFactory("BorrowTicket");
        BorrowTicket = await BorrowTicketContract.deploy(Facilitator.address, BorrowTicketDescriptor.address);
        await BorrowTicket.deployed();

        await Facilitator.connect(manager).setLendTicketContract(LendTicket.address)
        await Facilitator.connect(manager).setBorrowTicketContract(BorrowTicket.address)

        TestERC721Contract = await ethers.getContractFactory("TestERC721");
        TestERC721 = await TestERC721Contract.deploy();
        await TestERC721.deployed();

        await TestERC721.connect(erc721Holder).mint();
        await TestERC721.connect(erc721Holder).approve(Facilitator.address, tokenId)


        ERC20Contract = await ethers.getContractFactory("TestERC20");
        ERC20 = await ERC20Contract.deploy();
        await ERC20.deployed();  
        ERC20.mint(erc20Holder.address, ethers.BigNumber.from(10).pow(30));
      });
      
    describe("tokenURI", function() {
        it("retrieves successfully", async function(){
            await Facilitator.connect(erc721Holder).createLoan(
                tokenId, 
                TestERC721.address, 
                interest,
                amount, 
                ERC20.address, 
                duration, 
                erc721Holder.address,
                true,
            )
            await expect(
                BorrowTicket.tokenURI("1")
            ).not.to.be.reverted
            const u = await BorrowTicket.tokenURI("1")
            // console.log(u)
        })
    })


    describe("createLoan", function () {

        // 设置值正确
        it("sets values correctly", async function(){

            await Facilitator.connect(erc721Holder).createLoan(
                tokenId,
                TestERC721.address,
                interest,
                amount,
                ERC20.address,
                duration,
                addr4.address,
                true
            )
            const ticket = await Facilitator.loanInfo("1")
            expect(ticket.erc20Address).to.equal(ERC20.address)
            expect(ticket.amount).to.equal(amount)
            expect(ticket.tokenId).to.equal(tokenId)
            expect(ticket.erc721).to.equal(TestERC721.address)
            expect(ticket.rate).to.equal(interest)
            expect(ticket.duration).to.equal(duration)
            expect(ticket.interest).to.equal(0)
        })

        // 转移NFT到合约，铸造借贷票据
        it("transfers NFT to contract, mints ticket", async function(){

            await Facilitator.connect(erc721Holder).createLoan(
                tokenId,
                TestERC721.address,
                interest,
                amount, 
                ERC20.address,
                duration,
                addr4.address,
                true,

            )
            const erc721Owner = await  TestERC721.ownerOf(tokenId)
            const ticketOwner = await BorrowTicket.ownerOf("1")
            expect(erc721Owner).to.equal(Facilitator.address)
            expect(ticketOwner).to.equal(addr4.address)
        })

        // 如果 NFT 没有被批准，应该失败
        it('reverts if not approved', async function(){
            await TestERC721.connect(erc721Holder).mint();
            await expect(
                Facilitator.connect(erc721Holder).createLoan(
                    tokenId.add(1), 
                    TestERC721.address, 
                    interest, 
                    amount, 
                    ERC20.address,
                    duration, 
                    addr4.address,
                    true,

                )
            ).to.be.revertedWith("ERC721: transfer caller is not owner nor approved")
        })

        // 如果 抵押品 是 loan ticket or borrow ticket ，应该失败
        it('reverts if collateral is loan ticket or borrow ticket', async function(){
            await expect(
                Facilitator.connect(erc721Holder).createLoan(
                    tokenId, 
                    LendTicket.address, 
                    interest,
                    amount,
                    ERC20.address,
                    duration,
                    addr4.address,
                    true, 

                )
            ).to.be.revertedWith('lend ticket collateral')
            
            await expect(
                Facilitator.connect(erc721Holder).createLoan(
                    tokenId,
                    BorrowTicket.address,
                    interest,
                    amount,
                    ERC20.address,
                    duration,
                    addr4.address,
                    true,

                )
            ).to.be.revertedWith('borrow ticket collateral')
        })

        it('reverts if duration is 0', async function(){
            await expect(
                Facilitator.connect(erc721Holder).createLoan(
                    tokenId,
                    TestERC721.address,
                    interest,
                    amount,
                    ERC20.address,
                    0,
                    addr4.address,
                    true,

                )
            ).to.be.revertedWith('0 duration')
        })

        it('reverts if loan amount is 0', async function(){
            await expect(
                Facilitator.connect(erc721Holder).createLoan(
                    tokenId,
                    TestERC721.address,
                    interest,
                    0,
                    ERC20.address,
                    duration,
                    addr4.address,
                    true,

                )
            ).to.be.revertedWith('0 loan amount')
        })

        it('does not reverts if interest rate is 0', async function(){
            await expect(
                Facilitator.connect(erc721Holder).createLoan(
                    tokenId,
                    TestERC721.address,
                    0,
                    amount,
                    ERC20.address,
                    duration,
                    addr4.address,
                    true,

                )
            ).not.to.be.reverted
        })
    });

    describe("closeLoan", function () {
        beforeEach(async function() {
            await TestERC721.connect(erc721Holder).mint();
            await TestERC721.connect(erc721Holder).approve(Facilitator.address, tokenId.add(1))
            await ERC20.connect(erc20Holder).approve(Facilitator.address, amount.mul(2))

            await Facilitator.connect(erc721Holder).createLoan(
                    tokenId.add(1), 
                    TestERC721.address, 
                    interest, 
                    amount, 
                    ERC20.address, 
                    duration, 
                    erc721Holder.address,
                    true
                )
        })

        it("transfers ERC721 and closes ticket", async function(){
            await Facilitator.connect(erc721Holder).closeLoan("1", addr4.address)
            const owner = await TestERC721.ownerOf(tokenId.add(1))
            expect(owner).to.equal(addr4.address)
            const ticket = await Facilitator.loanInfo("1")
            expect(ticket.closed).to.equal(true)
        });

        it("reverts if loan does not exist", async function(){
            await expect(
                Facilitator.connect(erc20Holder).closeLoan("2", addr4.address)
                ).to.be.revertedWith("NOT_MINTED")
        });

        it("reverts if caller is not ticket owner", async function(){
            await expect(
                Facilitator.connect(erc20Holder).closeLoan("1", addr4.address)
                ).to.be.revertedWith("borrow ticket holder only")
        });

        it("reverts if loan closed", async function(){
            await Facilitator.connect(erc721Holder).closeLoan("1", addr4.address)
            await expect(
                Facilitator.connect(erc721Holder).closeLoan("1", addr4.address)
            ).to.be.revertedWith("loan closed")
        });

        it("reverts if ticket has lender", async function(){
            await Facilitator.connect(erc20Holder).lend("1", interest, amount, duration, erc20Holder.address)
            await expect(
                Facilitator.connect(erc721Holder).closeLoan("1", addr4.address)
            ).to.be.revertedWith("has lender")
        });
    })

    describe("lend", function () {
        context("when loan does not have lender", function () {
            beforeEach(async function() {
                await Facilitator.connect(erc721Holder).createLoan(
                    tokenId, 
                    TestERC721.address, 
                    interest, 
                    amount, 
                    ERC20.address, 
                    duration, 
                    erc721Holder.address,
                    true, 
                )
                await ERC20.connect(erc20Holder).approve(Facilitator.address, amount)
            })

            it("reverts if loan does not exist", async function(){
                await expect(
                    Facilitator.connect(erc20Holder).lend("2", 0, 0, 0, erc20Holder.address)
                    ).to.be.revertedWith("invalid loan")
            })

            it("reverts if amount is too low", async function(){
                await expect(
                    Facilitator.connect(erc20Holder).lend("1", interest, amount.sub(1), duration, erc20Holder.address)
                    ).to.be.revertedWith("amount too low")
            })

            it("reverts if interest is too high", async function(){
                await expect(
                    Facilitator.connect(erc20Holder).lend("1", interest.add(1), amount, duration, erc20Holder.address)
                    ).to.be.revertedWith("rate too high")
            })

            it("reverts if block duration is too low", async function(){
                await expect(
                    Facilitator.connect(erc20Holder).lend("1", interest, amount, duration.sub(1), erc20Holder.address)
                    ).to.be.revertedWith("duration too low")
            })

            it("sets values correctly", async function(){
                await expect(
                        Facilitator.connect(erc20Holder).lend("1", interest, amount, duration, erc20Holder.address)
                        ).not.to.be.reverted
                const ticket = await Facilitator.loanInfo("1")
                expect(ticket.amount).to.equal(amount)
                expect(ticket.rate).to.equal(interest)
                expect(ticket.duration).to.equal(duration)
                expect(ticket.interest).to.equal(0)
                const block = await provider.getBlock()
                expect(ticket.lastAccumulatedTimestamp).to.equal(block.timestamp)
            })
            it("transfers loan NFT to lender", async function(){
                await Facilitator.connect(erc20Holder).lend("1", interest, amount, duration, addr5.address)
                const owner = await LendTicket.ownerOf("1")
                expect(owner).to.equal(addr5.address)
            });

            it("leaves origination fee in contract", async function(){
                var value = await ERC20.balanceOf(Facilitator.address)
                expect(value).to.equal(0)
                await Facilitator.connect(erc20Holder).lend("1", interest, amount, duration, erc20Holder.address)
                value = await ERC20.balanceOf(Facilitator.address)
                expect(value).to.equal(amount.mul(originationFeeRate).div(scalar))
            })

            it("transfers loan asset borrower", async function(){
                var value = await ERC20.balanceOf(erc721Holder.address)
                expect(value).to.equal(0)
                await Facilitator.connect(erc20Holder).lend("1", interest, amount, duration, erc20Holder.address)
                value = await ERC20.balanceOf(erc721Holder.address)
                expect(value).to.equal(amount.sub(amount.mul(originationFeeRate).div(scalar)))
            })

        });

        context("malicious ERC20", function () {
            beforeEach(async function () {
                // deploy malicious erc20
                MaliciousERC20Contract = await ethers.getContractFactory("CloseLoanERC20");
                MAL = await MaliciousERC20Contract.connect(erc20Holder).deploy(Facilitator.address);
                await MAL.deployed();
                await MAL.mint(erc20Holder.address, amount);
        
                // make sure we mint borrow ticket to the erc20 contract address
                await Facilitator.connect(erc721Holder).createLoan(
                    tokenId, 
                    TestERC721.address, 
                    interest, 
                    amount, 
                    MAL.address, 
                    duration, 
                    MAL.address,
                    true, 
                )
                await MAL.connect(erc20Holder).approve(Facilitator.address, amount)
            })
        
            it("does not complete lend function if loan asset is malicious", async function () {
                var value = await MAL.balanceOf(erc721Holder.address)
                expect(value).to.equal(0)
        
                await expect(
                    Facilitator.connect(erc20Holder).lend("1", interest, amount, duration, erc20Holder.address)
                ).to.be.revertedWith("has lender")
        
                value = await MAL.balanceOf(erc721Holder.address)
                expect(value).to.equal(0)
            })
        })

        context("when loan has lender", function () {
            beforeEach(async function() {
                await ERC20.connect(erc20Holder).approve(Facilitator.address, amount)

                await Facilitator.connect(erc721Holder).createLoan(
                    tokenId, 
                    TestERC721.address, 
                    interest, 
                    amount, 
                    ERC20.address, 
                    duration, 
                    erc721Holder.address,
                    true,
                )
                await Facilitator.connect(erc20Holder).lend("1", interest, amount, duration, erc20Holder.address)

                await ERC20.connect(erc20Holder).transfer(addr4.address, amount.mul(2))
                await ERC20.connect(addr4).approve(Facilitator.address, amount.mul(2))
            })

            it("reverts if terms are not improved", async function(){
                await expect(
                    Facilitator.connect(addr4).lend("1", interest, amount, duration, erc20Holder.address)
                ).to.be.revertedWith("insufficient improvement")
            })

            it("reverts interest is already 0", async function(){
                await Facilitator.connect(addr4).lend("1", 0, amount, duration, erc20Holder.address)
                await expect(
                    Facilitator.connect(addr4).lend("1", 0, amount, duration, erc20Holder.address)
                ).to.be.revertedWith("insufficient improvement")
            })

            it("reverts if one value does not meet or beat exisiting, even if others are improved", async function(){
                await expect(
                        Facilitator.connect(addr4).lend("1", interest.mul(90).div(100), amount.sub(1), duration, addr4.address)
                        ).to.be.reverted
            })

            it("does not revert if interest is less", async function(){
                await expect(
                        Facilitator.connect(addr4).lend("1", interest.mul(90).div(100), amount, duration, addr4.address)
                        ).not.to.be.reverted
            })

            it("does not revert if duration greater", async function(){
                await expect(
                        Facilitator.connect(addr4).lend("1", interest, amount, duration.add(duration.mul(10).div(100)), addr4.address)
                        ).not.to.be.reverted
            })

            it("does not revert if loan amount greater", async function(){
                await expect(
                        Facilitator.connect(addr4).lend("1", interest, amount.add(amount.mul(10).div(100)), duration, addr4.address)
                        ).not.to.be.reverted
            })

            it("transfers loan token to the new lender", async function(){
                await Facilitator.connect(addr4).lend("1", interest, amount.add(amount.mul(10).div(100)), duration, manager.address)
                const owner = await LendTicket.ownerOf("1")
                expect(owner).to.equal(manager.address)
            });

            it("pays back previous owner", async function(){
                const beforeValue = await ERC20.balanceOf(erc20Holder.address)
                await Facilitator.connect(addr4).lend("1", interest, amount.add(amount.mul(10).div(100)), duration, addr4.address)
                const interestOwed = await interestOwedTotal("1")
                const afterValue = await ERC20.balanceOf(erc20Holder.address)
                expect(afterValue).to.equal(beforeValue.add(amount).add(interestOwed))
            })

            it("sets values correctly", async function(){
                const newLoanAmount = amount.add(amount.mul(10).div(100))
                await Facilitator.connect(addr4).lend("1", interest, newLoanAmount, duration, addr4.address)
                const interest = await interestOwedTotal("1")
                const ticket = await Facilitator.loanInfo("1")
                expect(ticket.amount).to.equal(newLoanAmount)
                expect(ticket.rate).to.equal(interest)
                expect(ticket.duration).to.equal(duration)
                expect(ticket.interest).to.equal(interest)
                const block = await provider.getBlock()
                expect(ticket.lastAccumulatedTimestamp).to.equal(block.timestamp)
            })

            it("takes origination fee correctly", async function(){
                const increase = amount.mul(10).div(100)
                const newLoanAmount = amount.add(increase)
                await Facilitator.connect(addr4).lend("1", interest, newLoanAmount, duration, addr4.address)
                value = await ERC20.balanceOf(Facilitator.address)
                expect(value).to.equal(amount.mul(originationFeeRate).div(scalar).add(increase.mul(originationFeeRate).div(scalar)))
            })

            context("when loan amount is the same", function () {
                it('does not increase cash drawer balance', async function(){
                    var valueBefore = await ERC20.balanceOf(Facilitator.address)
                    await Facilitator.connect(addr4).lend("1", interest, amount, duration.add(duration.mul(10).div(100)), addr4.address)
                    var valueAfter = await ERC20.balanceOf(Facilitator.address)
                    expect(valueBefore).to.equal(valueAfter)
                })

                it("sets values correctly", async function(){
                    const newDuration = duration.add(duration.mul(10).div(100))
                    await Facilitator.connect(addr4).lend("1", interest, amount, newDuration, addr4.address)
                    const interest = await interestOwedTotal("1")
                    const ticket = await Facilitator.loanInfo("1")
                    expect(ticket.amount).to.equal(amount)
                    expect(ticket.rate).to.equal(interest)
                    expect(ticket.duration).to.equal(newDuration)
                    expect(ticket.interest).to.equal(interest)
                    const block = await provider.getBlock()
                    expect(ticket.lastAccumulatedTimestamp).to.equal(block.timestamp)
                })
                
                // 偿还 给前任借款人
                it("pays back previous owner", async function(){
                    const beforeValue = await ERC20.balanceOf(erc20Holder.address)
                    await Facilitator.connect(addr4).lend("1", interest, amount, duration.add(duration.mul(10).div(100)), addr4.address)
                    const interestOwed = await interestOwedTotal("1")
                    const afterValue = await ERC20.balanceOf(erc20Holder.address)
                    expect(afterValue).to.equal(beforeValue.add(amount).add(interestOwed))
                })
            })

            context('when bought out again', function() {
                it('transfers payout correctly', async function(){
                    const buyout1LoanAmount = amount.add(amount.mul(10).div(100))
                    const buyout2LoanAmount = buyout1LoanAmount.add(buyout1LoanAmount.mul(10).div(100))
                    
                    await ERC20.connect(erc20Holder).approve(Facilitator.address, buyout2LoanAmount.mul(2))
                    
                    await Facilitator.connect(addr4).lend("1", interest, buyout1LoanAmount, duration, addr4.address)
                    const addr4BeforeBalance = await ERC20.balanceOf(addr4.address)
                    await Facilitator.connect(erc20Holder).lend("1", interest, buyout2LoanAmount, duration, erc20Holder.address)
                    const interestOwed = await interestOwedTotal("1")
                    const addr4AfterBalance = await ERC20.balanceOf(addr4.address)
                    expect(addr4AfterBalance).to.equal(addr4BeforeBalance.add(buyout1LoanAmount).add(interestOwed))
                })
            })
        });
        
    });

    describe("repayAndCloseLoan", function () {
        beforeEach(async function() {
            await ERC20.connect(erc20Holder).approve(Facilitator.address, amount.mul(2))

            await Facilitator.connect(erc721Holder).createLoan(
                tokenId, 
                TestERC721.address, 
                interest, 
                amount, 
                ERC20.address, 
                duration, 
                erc721Holder.address,
                true,
            )
            await Facilitator.connect(erc20Holder).lend("1", interest, amount, duration, erc20Holder.address)
            await ERC20.connect(erc20Holder).transfer(erc721Holder.address, amount.mul(2))
            await ERC20.connect(erc721Holder).approve(Facilitator.address, amount.mul(2))
        })

        it("pays back lender", async function(){
            const balanceBefore = await ERC20.balanceOf(erc20Holder.address)
            await Facilitator.connect(erc721Holder).repayAndCloseLoan("1")
            const interest = await interestOwedTotal("1")
            const balanceAfter = await ERC20.balanceOf(erc20Holder.address)
            expect(balanceAfter).to.equal(balanceBefore.add(amount.add(interest)))
        })

        it("transfers collateral back to lendee", async function(){
            await Facilitator.connect(erc721Holder).repayAndCloseLoan("1")
            const erc721Owner = await  TestERC721.ownerOf(tokenId)
            expect(erc721Owner).to.equal(erc721Holder.address)
        })

        it("closes ticket", async function(){
            await Facilitator.connect(erc721Holder).repayAndCloseLoan("1")
            const ticket = await Facilitator.loanInfo("1")
            expect(ticket.closed).to.equal(true)
        })

        it("reverts if ticket is closed", async function(){
            await Facilitator.connect(erc721Holder).repayAndCloseLoan("1")
            await expect(
                Facilitator.connect(erc721Holder).repayAndCloseLoan("1")
            ).to.be.revertedWith("loan closed")
        })

        it("reverts if loan does not exist", async function(){
            await expect(
                Facilitator.connect(erc721Holder).repayAndCloseLoan("10")
            ).to.be.revertedWith("NOT_MINTED")
        })
    })

    describe("seize", function () {
        beforeEach(async function() {
            await TestERC721.connect(erc721Holder).mint();
            await TestERC721.connect(erc721Holder).approve(Facilitator.address, tokenId.add(1))
            await ERC20.connect(erc20Holder).approve(Facilitator.address, amount.mul(2))

            await Facilitator.connect(erc721Holder).createLoan(
                tokenId.add(1), 
                TestERC721.address, 
                interest, 
                amount, 
                ERC20.address, 
                1, 
                erc721Holder.address,
                true,
            )
            await Facilitator.connect(erc20Holder).lend("1", interest, amount, 1, erc20Holder.address)
        })

        it("transfers collateral to given address, closed", async function(){
            // mine on block
            await ERC20.connect(erc20Holder).transfer(addr4.address, ethers.BigNumber.from(1))
            // 
            await Facilitator.connect(erc20Holder).seize("1", addr4.address)
            const ticket = await Facilitator.loanInfo("1")
            expect(ticket.closed).to.equal(true)
            const erc721Owner = await TestERC721.ownerOf(tokenId.add(1))
            expect(erc721Owner).to.equal(addr4.address)
        })

        it('reverts if non-loan-owner calls', async function(){
            // mine on block
            await ERC20.connect(erc20Holder).transfer(addr4.address, ethers.BigNumber.from(1))
            // 
            await expect(
                Facilitator.connect(addr4).seize("1", addr4.address)
            ).to.be.revertedWith("lend ticket holder only")
        })

        it("reverts if ticket is closed", async function(){
            await ERC20.connect(erc20Holder).approve(Facilitator.address, amount.mul(1))
            // repay and close
            await ERC20.connect(erc20Holder).transfer(erc721Holder.address, amount.mul(2))
            await ERC20.connect(erc721Holder).approve(Facilitator.address, amount.mul(2))
            await Facilitator.connect(erc721Holder).repayAndCloseLoan("1")
            // 
            await expect(
                Facilitator.connect(erc20Holder).seize("1", addr4.address)
            ).to.be.revertedWith("loan closed")
        })

        it("reverts if payment is not late", async function(){
            await expect(
                Facilitator.connect(erc20Holder).seize("1", addr4.address)
            ).to.be.revertedWith("payment is not late")
        })

        it("reverts loan does not exist", async function(){
            await expect(
                Facilitator.connect(erc20Holder).seize("2", addr4.address)
            ).to.be.revertedWith("NOT_MINTED")
        })
    })

    describe("withdrawOriginationFees", function () {
        beforeEach(async function() {
            await ERC20.connect(erc20Holder).approve(Facilitator.address, amount.mul(2))

            await Facilitator.connect(erc721Holder).createLoan(
                tokenId, 
                TestERC721.address, 
                interest, 
                amount, 
                ERC20.address, 
                duration, 
                erc721Holder.address,
                true
            )
            await Facilitator.connect(erc20Holder).lend("1", interest, amount, duration, erc20Holder.address)
            await ERC20.connect(erc20Holder).transfer(erc721Holder.address, amount.mul(2))
            await ERC20.connect(erc721Holder).approve(Facilitator.address, amount.mul(2))
            await Facilitator.connect(erc721Holder).repayAndCloseLoan("1")
        })

        it("transfers ERC20 value, reduces loan payment balance", async function(){
            await expect(
                Facilitator.connect(erc20Holder).withdrawOriginationFees(ERC20.address, amount, manager.address)
                ).to.be.reverted
        });

        it("transfers ERC20 value, reduces loan payment balance", async function(){
            const balanceBefore = await ERC20.balanceOf(manager.address)
            const value = await ERC20.balanceOf(Facilitator.address)
            expect(value).to.be.above(0)
            await expect(
                Facilitator.connect(manager).withdrawOriginationFees(ERC20.address, value, manager.address)
                ).not.to.be.reverted
            const balanceAfter = await ERC20.balanceOf(manager.address)
            expect(balanceAfter).to.equal(balanceBefore.add(value))

        })
        
        it("reverts if amount is greater than what is available", async function(){
            const balanceBefore = await ERC20.balanceOf(manager.address)
            const value = await ERC20.balanceOf(Facilitator.address)
            await expect(
                Facilitator.connect(manager).withdrawOriginationFees(ERC20.address, value.add(1), manager.address)
                ).to.be.reverted
        })
    })

    describe("updateOriginationFee", function () {
        it("updates", async function(){
            const originalTake = ethers.BigNumber.from(1).mul(ethers.BigNumber.from(10).pow(interestRateDecimals - 2))
            var FacilitatorTakeRate = await Facilitator.originationFeeRate();
            expect(FacilitatorTakeRate).to.equal(originalTake)
            const newTake = ethers.BigNumber.from(5).mul(ethers.BigNumber.from(10).pow(interestRateDecimals - 2))
            await Facilitator.connect(manager).updateOriginationFeeRate(newTake)
            await expect(
                Facilitator.connect(manager).updateOriginationFeeRate(newTake)
            ).to.emit(Facilitator, "UpdateOriginationFeeRate")
            FacilitatorTakeRate = await Facilitator.originationFeeRate();
            expect(FacilitatorTakeRate).to.equal(newTake)
        })

        it("reverts if take > 5%", async function(){
            const newTake = ethers.BigNumber.from(6).mul(ethers.BigNumber.from(10).pow(interestRateDecimals - 2))
            await expect(
                Facilitator.connect(manager).updateOriginationFeeRate(newTake)
            ).to.be.revertedWith("max fee 5%")
        })

        it("reverts if not called by manager", async function(){
            const newTake = ethers.BigNumber.from(2).mul(ethers.BigNumber.from(10).pow(interestRateDecimals - 2))
            await expect(
                Facilitator.connect(erc20Holder).updateOriginationFeeRate(newTake)
            ).to.be.revertedWith("Ownable: caller is not the owner")
        })
    })

    describe("updateRequiredImprovementRate", function () {
        it("updates", async function(){ 
            const newPercentage = ethers.BigNumber.from(5);
            await expect(
                Facilitator.connect(manager).updateRequiredImprovementRate(newPercentage)
            ).to.emit(Facilitator, "UpdateRequiredImprovementRate")
            const percentage = await Facilitator.requiredImprovementRate();
            expect(percentage).to.eq(newPercentage)
        })

        it("reverts if not called by manager", async function(){
            await expect(
                Facilitator.connect(erc20Holder).updateRequiredImprovementRate(5)
            ).to.be.revertedWith("Ownable: caller is not the owner")
        })
    })

    async function interestOwedTotal(ticketID) {
        const ticket = await Facilitator.loanInfo(ticketID)
        const interest = ticket.rate
        const startTimestamp = ticket.lastAccumulatedTimestamp
        const height = await provider.getBlockNumber()
        const curBlock = await provider.getBlock(height)
        const curTimestamp = curBlock.timestamp
        const secondsInYear = 60*60*24*365;
        return ticket.amount
            .mul(ethers.BigNumber.from(curTimestamp - startTimestamp))
            .mul(Math.floor(interest * 1e18 / secondsInYear))
            .div(ethers.BigNumber.from(10).pow(18))
            .div(scalar)
            .add(ticket.interest)
    }
});
    