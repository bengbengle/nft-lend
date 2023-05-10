const { expect } = require("chai");

describe("LendTicket contract", function () {
    beforeEach(async function () {
        [pretendFacilitator, pretendDescriptor, addr1, addr2, ...addrs] = await ethers.getSigners();

        LendTicketContract = await ethers.getContractFactory("LendTicket");
        LendTicket = await LendTicketContract.deploy(pretendFacilitator.address, pretendDescriptor.address)
        await LendTicket.deployed();

        await LendTicket.connect(pretendFacilitator).mint(addr1.address, "1");
    })

    describe("transfer", function () {
        it('reverts if caller is not loan facilitator', async function(){
            await expect(
                LendTicket.connect(addr1).transfer(addr1.address, addr2.address, "1")
            ).to.be.revertedWith("Ticket: only loan facilitator")
        })

        it('transfers correctly if caller is loan facilitator', async function(){
            await expect(
                LendTicket.connect(pretendFacilitator).transfer(addr1.address, addr2.address, "1")
            ).not.to.be.reverted
            const owner = await LendTicket.ownerOf("1")
            expect(owner).to.equal(addr2.address)
        })
    })  
})