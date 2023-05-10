const { expect } = require("chai");

describe("Ticket contract", function () {
    let name = 'Ticket'
    let symbol = 'T'

    beforeEach(async function () {
        [pretendFacilitator, pretendDescriptor, addr1, ...addrs] = await ethers.getSigners();

        TicketContract = await ethers.getContractFactory("Ticket");
        Ticket = await TicketContract.deploy(name, symbol, pretendFacilitator.address, pretendDescriptor.address)
        await Ticket.deployed();
    })

    describe("contructor", function () {
        it("sets name correctly", async function(){
            const n = await Ticket.name();
            expect(n).to.equal(name)
        })

        it("sets symbol correctly", async function(){
            const s = await Ticket.symbol();
            expect(s).to.equal(symbol)
        })

        it("sets facilitator correctly", async function(){
            const p = await Ticket.facilitator();
            expect(p).to.equal(pretendFacilitator.address)
        })

        it("sets descriptor correctly", async function(){
            const d = await Ticket.descriptor();
            expect(d).to.equal(pretendDescriptor.address)
        })
    })

    describe("mint", function () {
        context('when caller is not loan facilitator', function(){
            it('reverts', async function(){
                await expect(
                    Ticket.connect(addr1).mint(addr1.address, "1")
                ).to.be.revertedWith("Ticket: only loan facilitator")
            })
        })
        
        context('when caller is loan facilitator', function(){
            it('mints', async function(){
                await expect(
                    Ticket.connect(pretendFacilitator).mint(addr1.address, "1")
                ).not.to.be.reverted
                const owner = await Ticket.ownerOf("1")
                expect(owner).to.equal(addr1.address)
            })

            context('when tokenId exists', function(){
                it('reverts', async function(){
                    await Ticket.connect(pretendFacilitator).mint(addr1.address, "1")
                    await expect(
                        Ticket.connect(pretendFacilitator).mint(addr1.address, "1")
                    ).to.be.revertedWith('ALREADY_MINTED')
                    const owner = await Ticket.ownerOf("1")
                    expect(owner).to.equal(addr1.address)
                })
            })
        })
    })
})