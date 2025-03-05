// SPDX-License-Identifier: MIT
const { ethers, upgrades } = require("hardhat");
const fs = require('fs');
const path = require('path');

async function main() {
  console.log("Starting deployment of YapLend Protocol to Monad...");
  
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
    
    // Step 1: Deploy NFTVerifier
    console.log("\n📄 Deploying NFTVerifier...");
    const NFTVerifier = await ethers.getContractFactory("NFTVerifier");
    const nftVerifier = await upgrades.deployProxy(NFTVerifier, [], {
      kind: "uups",
      initializer: "initialize"
    });
    await nftVerifier.waitForDeployment();
    
    const nftVerifierAddress = await nftVerifier.getAddress();
    console.log(`✅ NFTVerifier deployed to: ${nftVerifierAddress}`);
    deployedContracts.NFTVerifier = nftVerifierAddress;
    
    // Step 2: Deploy PriceOracle
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
    
    // Step 3: Deploy CollateralManager
    console.log("\n📄 Deploying CollateralManager...");
    const CollateralManager = await ethers.getContractFactory("CollateralManager");
    const collateralManager = await upgrades.deployProxy(CollateralManager, [priceOracleAddress], {
      kind: "uups",
      initializer: "initialize"
    });
    await collateralManager.waitForDeployment();
    
    const collateralManagerAddress = await collateralManager.getAddress();
    console.log(`✅ CollateralManager deployed to: ${collateralManagerAddress}`);
    deployedContracts.CollateralManager = collateralManagerAddress;
    
    // Step 4: Deploy LiquidityPool
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
    
    // Step 5: Set up fee collector address
    console.log("\n📝 Setting up fee collector address...");
    const feeCollectorAddress = process.env.FEE_COLLECTOR_ADDRESS || deployer.address;
    console.log(`Using fee collector address: ${feeCollectorAddress}`);
    
    // Step 6: Deploy YapLendCore (need placeholder for LoanVault address)
    console.log("\n📄 Deploying YapLendCore with placeholder...");
    const placeholderAddress = deployer.address; // Temporary placeholder
    const YapLendCore = await ethers.getContractFactory("YapLendCore");
    const yapLendCore = await upgrades.deployProxy(YapLendCore, [
      collateralManagerAddress,
      nftVerifierAddress,
      placeholderAddress, // Will be updated after LoanVault is deployed
      liquidityPoolAddress,
      feeCollectorAddress
    ], {
      kind: "uups",
      initializer: "initialize"
    });
    await yapLendCore.waitForDeployment();
    
    const yapLendCoreAddress = await yapLendCore.getAddress();
    console.log(`✅ YapLendCore deployed to: ${yapLendCoreAddress}`);
    deployedContracts.YapLendCore = yapLendCoreAddress;
    
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
    
    // Step 8: Update YapLendCore with correct LoanVault address
    console.log("\n📝 Updating YapLendCore with correct LoanVault address...");
    const collateralSetupTx = await yapLendCore.setLoanVault(loanVaultAddress);
    await collateralSetupTx.wait();
    console.log(`✅ YapLendCore updated with LoanVault address: ${loanVaultAddress}`);
    
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
    
    // Save deployment information to file
    console.log("\n💾 Saving deployment information...");
    const deploymentInfo = {
        network: "monad",
        chainId: Number(network.chainId), // Convertido para Number
        deployer: deployer.address,
        timestamp: new Date().toISOString(),
        contracts: deployedContracts
      };
    
    const deploymentsDir = path.join(__dirname, '../deployments');
    if (!fs.existsSync(deploymentsDir)) {
      fs.mkdirSync(deploymentsDir, { recursive: true });
    }
    
    fs.writeFileSync(
      path.join(deploymentsDir, `monad-${new Date().toISOString().split('T')[0]}.json`),
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