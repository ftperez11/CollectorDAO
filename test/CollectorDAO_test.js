const { expect, use } = require("chai");
const { ethers, waffle } = require("hardhat");
const { provider } = waffle;
const { BigNumber } = ethers;
const { solidity } = require("ethereum-waffle");


use(solidity);

describe("CollectorDAO", function(){
    let owner;
    let addr1;
    let addr2;
    let addr3;
    let DAO;


    beforeEach(async () => {
        [owner, addr1, addr2, addr3] = await ethers.getSigners();
        const CollectorDAOContract = await ethers.getContractFactory("CollectorDAO");
        DAO = await CollectorDAOContract.deploy();
 
        await DAO.deployed();
    })

    describe('Should deploy CollectorDAO', () => {
        it("Should deploy and confirm the owner of CollectorDAO", async () => {
            expect(await DAO.owner()).to.equal(owner.address);
        });
    })
    describe('Membership', () => {
        it("Should allow address to purchase a membership", async () => {
            let amount = ethers.utils.parseEther('4')
            let tx = await DAO.purchaseMembership({ value: amount });
            tx.wait()
            expect(await DAO.members(owner.address)).to.equal(true);
        });
        it("Should revert if amount sent is less than 1 Ether", async () => {
            let amount = ethers.utils.parseEther('0.05')
            let tx = DAO.purchaseMembership({ value: amount });
            await expect(tx).to.be.revertedWith("Please pay 1 eth");

        });
    })
    describe('Proposal', () => {
        it("Should allow member to make a proposal", async () => {
            let amount = ethers.utils.parseEther('3')
            await DAO.connect(addr1).purchaseMembership({ value: amount });
    
            expect(await DAO.members(addr1.address)).to.equal(true);
            let proposal = {
                targets: [addr1.address],
                values: [amount],
                signatures: ["buyNFT(uint id, uint value)"],
                calldatas: [ethers.utils.randomBytes(64)],
                description: "Purchase me NFT",
            }

            let tx_1 = await DAO.connect(addr1).propose(proposal.targets, proposal.values, proposal.signatures, proposal.calldatas, proposal.description);
            tx_1.wait();
            
            let proposalID =  await DAO.recentProposalId(addr1.address);
            let Actual_Proposal =  await DAO.proposals(proposalID);
 
            await expect(tx_1).to.emit(DAO, "ProposalCreated");
            await expect(proposalID).to.equal(Actual_Proposal.id);

        });
    })
    describe('Should allow voting', () => {
        let proposalID;
        beforeEach(async () => {
            let amount = ethers.utils.parseEther('3')
            await DAO.connect(addr1).purchaseMembership({ value: amount });
    
            expect(await DAO.members(addr1.address)).to.equal(true);
            let proposal = {
                targets: [addr1.address],
                values: [amount],
                signatures: ["buyNFT(uint id, uint value)"],
                calldatas: [ethers.utils.randomBytes(64)],
                description: "Purchase me NFT",
            }

            let tx_1 = await DAO.connect(addr1).propose(proposal.targets, proposal.values, proposal.signatures, proposal.calldatas, proposal.description);
            tx_1.wait();
            
            proposalID =  await DAO.recentProposalId(addr1.address);
            let Actual_Proposal =  await DAO.proposals(proposalID);

            types = {
                Ballot: [
                  { name: "proposalId", type: "uint256" },
                  { name: "support", type: "uint8" },
                ],
              };
              domain = {
                name: await DAO.name(),
                chainId: (await provider.getNetwork()).chainId, 
                verifyingContract: DAO.address, 
              };
        });
        
        it("Should allow member to submit forVote", async () => {
            let myVote = {
                proposalId: BigNumber.from(proposalID),
                support: 1,
            }
            const sig = await addr1._signTypedData(domain, types, myVote);
            const { v, r, s } = ethers.utils.splitSignature(sig);
      
            await DAO.submitBulkVotes([proposalID], [1], [v], [r], [s]);
            const voteStatus = await DAO.getVoteStatus(proposalID, addr1.address);

            expect(voteStatus[0]).to.equal(true); 
            expect(voteStatus[1]).to.equal(1);
        });
        it("Should allow member to submit againstVote", async () => {
            let myVote = {
                proposalId: BigNumber.from(proposalID),
                support: 0,
            }
            const sig = await addr1._signTypedData(domain, types, myVote);
            const { v, r, s } = ethers.utils.splitSignature(sig);
      
            await DAO.submitBulkVotes([proposalID], [0], [v], [r], [s]);
            const voteStatus = await DAO.getVoteStatus(proposalID, addr1.address);

            expect(voteStatus[0]).to.equal(true); 
            expect(voteStatus[1]).to.equal(0);
        });
        it("Should allow member to submit abstainVotes", async () => {
            let myVote = {
                proposalId: BigNumber.from(proposalID),
                support: 2,
            }
            const sig = await addr1._signTypedData(domain, types, myVote);
            const { v, r, s } = ethers.utils.splitSignature(sig);
      
            await DAO.submitBulkVotes([proposalID], [2], [v], [r], [s]);
            const voteStatus = await DAO.getVoteStatus(proposalID, addr1.address);

            expect(voteStatus[0]).to.equal(true); 
            expect(voteStatus[1]).to.equal(2);

        });
    })
    describe('Executing Proposals', () => {
        let proposalID;
        beforeEach(async () => {
            let amount = ethers.utils.parseEther('10')
            await DAO.connect(addr1).purchaseMembership({ value: amount });
    
            expect(await DAO.members(addr1.address)).to.equal(true);
            let proposal = {
                targets: [addr1.address],
                values: [amount],
                signatures: ["buyNFT(uint id, uint value)"],
                calldatas: [ethers.utils.randomBytes(64)],
                description: "Purchase me NFT",
            }

            let tx_1 = await DAO.connect(addr1).propose(proposal.targets, proposal.values, proposal.signatures, proposal.calldatas, proposal.description);
            tx_1.wait();
            
            proposalID =  await DAO.recentProposalId(addr1.address);

            types = {
                Ballot: [
                  { name: "proposalId", type: "uint256" },
                  { name: "support", type: "uint8" },
                ],
              };
              domain = {
                name: await DAO.name(),
                chainId: (await provider.getNetwork()).chainId, 
                verifyingContract: DAO.address, 
              };
        });
        
        it("Should not execute proposals if quorum not reached", async () => {
            let myVote = {
                proposalId: BigNumber.from(proposalID),
                support: 1,
            }
            const sig = await addr1._signTypedData(domain, types, myVote);
            const { v, r, s } = ethers.utils.splitSignature(sig);
      
            await DAO.submitBulkVotes([proposalID], [1], [v], [r], [s]);
            const days = 2;
            await ethers.provider.send('evm_increaseTime', [days * 24 * 60 * 60]); 
            await ethers.provider.send('evm_mine');


            let tx1 = DAO.connect(addr1).executeProposal(proposalID);
            await expect(tx1).to.be.revertedWith("proposal can only be executed if it is queued");
        });
        it("Should execute proposals if quorum reached", async () => {

            let myVote = {
                proposalId: BigNumber.from(proposalID),
                support: 1,
            }
            const sig = await addr1._signTypedData(domain, types, myVote);
            const { v, r, s } = ethers.utils.splitSignature(sig);
      
            await DAO.submitBulkVotes([proposalID], [1], [v], [r], [s]);

            const days = 35;
            await ethers.provider.send('evm_increaseTime', [days * 24 * 60 * 60]); 
            await ethers.provider.send('evm_mine');

            let tx1 = await DAO.connect(addr1).executeProposal(proposalID);
            await expect(tx1)
            .to.emit(DAO, 'ProposalExecuted')
            .withArgs(proposalID);

        });

    })
   

});