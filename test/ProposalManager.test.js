const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("ProposalManager - cancelProposal", function () {
  let ProposalManagerFactory, proposalManager;
  let NFTVerifierMock, nftVerifier;
  let YapLendCoreMock, yapLendCore;
  let owner, borrower, lender, other;
  
  // Define a variável com o valor de 1 Ether usando ethers v6
  const oneEth = ethers.parseEther("1");

  beforeEach(async function () {
    [owner, borrower, lender, other] = await ethers.getSigners();

    // Deploy do mock NFTVerifier
    const NFTVerifierMockFactory = await ethers.getContractFactory("NFTVerifierMock");
    nftVerifier = await NFTVerifierMockFactory.deploy();
    await nftVerifier.waitForDeployment();

    // Deploy do mock YapLendCore, que retorna o endereço do NFTVerifier
    const YapLendCoreMockFactory = await ethers.getContractFactory("YapLendCoreMock");
    yapLendCore = await YapLendCoreMockFactory.deploy(nftVerifier.address);
    await yapLendCore.waitForDeployment();

    // Defina a factory do ProposalManager
    ProposalManagerFactory = await ethers.getContractFactory("ProposalManager");

    // Deploy do ProposalManager usando o proxy upgradeable
    const yapLendCoreAddress = await yapLendCore.getAddress();
    console.log("yapLendCore address:", yapLendCoreAddress);
    proposalManager = await upgrades.deployProxy(ProposalManagerFactory, [yapLendCoreAddress], { initializer: "initialize" });
    await proposalManager.waitForDeployment();
  });

  describe("Cancel original proposal", function () {
    it("should cancel an original proposal and mark it inactive", async function () {
      const nftAddresses = [other.address];
      const tokenIds = [1];
      const requestedAmount = oneEth;
      const duration = 3600; // 1 hora
      const interestRate = 4000; // 40%
      
      await proposalManager.connect(borrower).createProposal(nftAddresses, tokenIds, requestedAmount, duration, interestRate);
      
      let proposal = await proposalManager.proposals(1);
      expect(proposal.isActive).to.be.true;
      expect(proposal.isCounterOffer).to.be.false;

      await proposalManager.connect(borrower).cancelProposal(1);
      
      proposal = await proposalManager.proposals(1);
      expect(proposal.isActive).to.be.false;
    });
  });

  describe("Cancel counter offer before expiration", function () {
    it("should cancel a counter offer and refund funds to lender", async function () {
      const nftAddresses = [other.address];
      const tokenIds = [1];
      const requestedAmount = oneEth;
      const duration = 3600;
      const interestRate = 4000;
      
      await proposalManager.connect(borrower).createProposal(nftAddresses, tokenIds, requestedAmount, duration, interestRate);
      
      const offerAmount = oneEth;
      const counterDuration = 3600;
      const counterInterestRate = 5000;
      const validityPeriod = 3600; // 1 hora de validade
      await proposalManager.connect(lender).createCounterOffer(1, offerAmount, counterDuration, counterInterestRate, validityPeriod, { value: offerAmount });
      
      let counterProposal = await proposalManager.proposals(2);
      expect(counterProposal.isActive).to.be.true;
      expect(counterProposal.isCounterOffer).to.be.true;
      expect(counterProposal.expiresAt).to.be.gt(0);
      
      let lockedBefore = await proposalManager.getLockedFunds(lender.address);
      expect(lockedBefore).to.equal(offerAmount);
      
      await expect(proposalManager.connect(borrower).cancelProposal(2))
        .to.emit(proposalManager, "ProposalCancelled")
        .withArgs(2, borrower.address);
      
      counterProposal = await proposalManager.proposals(2);
      expect(counterProposal.isActive).to.be.false;
      
      let lockedAfter = await proposalManager.getLockedFunds(lender.address);
      expect(lockedAfter).to.equal(0);
    });
  });

  describe("Cancel counter offer after expiration", function () {
    it("should revert when trying to cancel an expired counter offer", async function () {
      const nftAddresses = [other.address];
      const tokenIds = [1];
      const requestedAmount = oneEth;
      const duration = 3600;
      const interestRate = 4000;
      
      await proposalManager.connect(borrower).createProposal(nftAddresses, tokenIds, requestedAmount, duration, interestRate);
      
      const offerAmount = oneEth;
      const counterDuration = 3600;
      const counterInterestRate = 5000;
      const validityPeriod = 10; // 10 segundos de validade
      await proposalManager.connect(lender).createCounterOffer(1, offerAmount, counterDuration, counterInterestRate, validityPeriod, { value: offerAmount });
      
      // Avança o tempo para que a contra-oferta expire
      await ethers.provider.send("evm_increaseTime", [20]);
      await ethers.provider.send("evm_mine", []);
      
      await expect(
        proposalManager.connect(borrower).cancelProposal(2)
      ).to.be.revertedWith("Counter offer already expired");
    });
  });
});
