// SPDX-License-Identifier: MIT
const { ethers, upgrades } = require("hardhat");
const fs = require('fs');
const path = require('path');

async function main() {
  console.log("Starting deployment of YapLend Protocol with NFT Escrow to Monad...");
  
  let deployedContracts = {};
  
  try {
    // Get deployer account
    const [deployer] = await ethers.getSigners();
    console.log(`Deploying contracts with account: ${deployer.address}`);
    
    // Check deployer balance
    const deployerBalance = await ethers.provider.getBalance(deployer.address);
    console.log(`Account balance: ${ethers.formatEther(deployerBalance)} ETH`);
    
    // Get network info for logging
    const network = await ethers.provider.getNetwork();
    console.log(`Deploying to Monad network (${network.chainId})`);
    
    // Step 1: Deploy PriceOracle
    console.log("\n📄 Deploying PriceOracle...");
    const PriceOracle = await ethers.getContractFactory("PriceOracle");
    const priceOracle = await upgrades.deployProxy(PriceOracle, [], {
      kind: "uups",
      initializer: "initialize"
    });
    await priceOracle.waitForDeployment();
    
    const priceOracleAddress = await priceOracle.getAddress();
    console.log(`✅ PriceOracle deployed to: ${priceOracleAddress}`);
    deployedContracts.PriceOracle = priceOracleAddress;
    
    // Step 2: Set up temporary placeholder address
    console.log("\n📝 Setting up temporary placeholder address...");
    const placeholderAddress = deployer.address; // Temporary placeholder
    console.log(`Using placeholder address: ${placeholderAddress}`);
    
    // Step 3: Deploy YapLendCore (need placeholder for other addresses that will be updated later)
    console.log("\n📄 Deploying YapLendCore with placeholders...");
    const YapLendCore = await ethers.getContractFactory("YapLendCore");
    const yapLendCore = await upgrades.deployProxy(YapLendCore, [
      placeholderAddress, // CollateralManager address (will be updated)
      placeholderAddress, // NFTVerifier address (will be updated)
      placeholderAddress, // LoanVault address (will be updated)
      placeholderAddress, // LiquidityPool address (will be updated)
      deployer.address    // Fee collector address
    ], {
      kind: "uups",
      initializer: "initialize"
    });
    await yapLendCore.waitForDeployment();
    
    const yapLendCoreAddress = await yapLendCore.getAddress();
    console.log(`✅ YapLendCore deployed to: ${yapLendCoreAddress}`);
    deployedContracts.YapLendCore = yapLendCoreAddress;
    
    // Step 4: Deploy CollateralManager (needs YapLendCore and PriceOracle)
    console.log("\n📄 Deploying CollateralManager...");
    const CollateralManager = await ethers.getContractFactory("CollateralManager");
    const collateralManager = await upgrades.deployProxy(CollateralManager, 
      [priceOracleAddress, yapLendCoreAddress], // Now needs both PriceOracle and YapLendCore
      {
        kind: "uups",
        initializer: "initialize"
      }
    );
    await collateralManager.waitForDeployment();
    
    const collateralManagerAddress = await collateralManager.getAddress();
    console.log(`✅ CollateralManager deployed to: ${collateralManagerAddress}`);
    deployedContracts.CollateralManager = collateralManagerAddress;
    
    // Step 5: Deploy NFTVerifier (needs CollateralManager)
    console.log("\n📄 Deploying NFTVerifier...");
    const NFTVerifier = await ethers.getContractFactory("NFTVerifier");
    const nftVerifier = await upgrades.deployProxy(NFTVerifier, [collateralManagerAddress], {
      kind: "uups",
      initializer: "initialize"
    });
    await nftVerifier.waitForDeployment();
    
    const nftVerifierAddress = await nftVerifier.getAddress();
    console.log(`✅ NFTVerifier deployed to: ${nftVerifierAddress}`);
    deployedContracts.NFTVerifier = nftVerifierAddress;
    
    // Step 6: Deploy LiquidityPool
    console.log("\n📄 Deploying LiquidityPool...");
    const LiquidityPool = await ethers.getContractFactory("LiquidityPool");
    const liquidityPool = await upgrades.deployProxy(LiquidityPool, [], {
      kind: "uups",
      initializer: "initialize"
    });
    await liquidityPool.waitForDeployment();
    
    const liquidityPoolAddress = await liquidityPool.getAddress();
    console.log(`✅ LiquidityPool deployed to: ${liquidityPoolAddress}`);
    deployedContracts.LiquidityPool = liquidityPoolAddress;
    
    // Step 7: Deploy LoanVault with YapLendCore address
    console.log("\n📄 Deploying LoanVault...");
    const LoanVault = await ethers.getContractFactory("LoanVault");
    const loanVault = await upgrades.deployProxy(LoanVault, [yapLendCoreAddress], {
      kind: "uups",
      initializer: "initialize"
    });
    await loanVault.waitForDeployment();
    
    const loanVaultAddress = await loanVault.getAddress();
    console.log(`✅ LoanVault deployed to: ${loanVaultAddress}`);
    deployedContracts.LoanVault = loanVaultAddress;
    
    // Step 8: Update YapLendCore with actual addresses
    console.log("\n📝 Updating YapLendCore with correct contract addresses...");
    
    const updateCollateralManagerTx = await yapLendCore.setCollateralManager(collateralManagerAddress);
    await updateCollateralManagerTx.wait();
    console.log(`✅ YapLendCore updated with CollateralManager address: ${collateralManagerAddress}`);
    
    const updateNFTVerifierTx = await yapLendCore.setNFTVerifier(nftVerifierAddress);
    await updateNFTVerifierTx.wait();
    console.log(`✅ YapLendCore updated with NFTVerifier address: ${nftVerifierAddress}`);
    
    const updateLoanVaultTx = await yapLendCore.setLoanVault(loanVaultAddress);
    await updateLoanVaultTx.wait();
    console.log(`✅ YapLendCore updated with LoanVault address: ${loanVaultAddress}`);
    
    const updateLiquidityPoolTx = await yapLendCore.setLiquidityPool(liquidityPoolAddress);
    await updateLiquidityPoolTx.wait();
    console.log(`✅ YapLendCore updated with LiquidityPool address: ${liquidityPoolAddress}`);
    
    // Step 9: Deploy ProposalManager
    console.log("\n📄 Deploying ProposalManager...");
    const ProposalManager = await ethers.getContractFactory("ProposalManager");
    const proposalManager = await upgrades.deployProxy(ProposalManager, [yapLendCoreAddress], {
      kind: "uups",
      initializer: "initialize"
    });
    await proposalManager.waitForDeployment();
    
    const proposalManagerAddress = await proposalManager.getAddress();
    console.log(`✅ ProposalManager deployed to: ${proposalManagerAddress}`);
    deployedContracts.ProposalManager = proposalManagerAddress;
    
    // Step 10: Set ProposalManager in YapLendCore
    console.log("\n📝 Setting ProposalManager in YapLendCore...");
    const proposalManagerSetupTx = await yapLendCore.setProposalManager(proposalManagerAddress);
    await proposalManagerSetupTx.wait();
    console.log(`✅ YapLendCore updated with ProposalManager address: ${proposalManagerAddress}`);
    
    // Step 11: Update CollateralManager with YapLendCore address (needed for loanIdCounter)
    console.log("\n📝 Updating CollateralManager with YapLendCore address...");
    const updateYapLendCoreTx = await collateralManager.setYapLendCore(yapLendCoreAddress);
    await updateYapLendCoreTx.wait();
    console.log(`✅ CollateralManager updated with YapLendCore address: ${yapLendCoreAddress}`);
    
    // Step 12: Verify NFTEscrow implementation address for reference
    console.log("\n📝 Getting NFTEscrow implementation address...");
    const escrowImplAddress = await collateralManager.escrowImplementation();
    console.log(`✅ NFTEscrow implementation address: ${escrowImplAddress}`);
    deployedContracts.NFTEscrowImpl = escrowImplAddress;
    
    // Save deployment information to file
    console.log("\n💾 Saving deployment information...");
    const deploymentInfo = {
        network: "monad",
        chainId: Number(network.chainId),
        deployer: deployer.address,
        timestamp: new Date().toISOString(),
        contracts: deployedContracts
      };
    
    const deploymentsDir = path.join(__dirname, '../deployments');
    if (!fs.existsSync(deploymentsDir)) {
      fs.mkdirSync(deploymentsDir, { recursive: true });
    }
    
    fs.writeFileSync(
      path.join(deploymentsDir, `monad-escrow-${new Date().toISOString().split('T')[0]}.json`),
      JSON.stringify(deploymentInfo, null, 2)
    );
    
    console.log("\n✨ Deployment completed successfully!");
    console.log("=================================");
    console.log("Deployed Contracts:");
    Object.entries(deployedContracts).forEach(([name, address]) => {
      console.log(`${name}: ${address}`);
    });
    
  } catch (error) {
    console.error("❌ Deployment failed:", error);
    throw error;
  }
}

// Execute the deployment
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });