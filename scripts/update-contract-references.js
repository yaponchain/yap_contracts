const { ethers } = require("hardhat");

async function main() {
  // Endereços dos novos contratos
  const ADDRESSES = {
    PriceOracle: "0x00f1e427E0A42961ddAf74d023031151429CCF7C",
    YapLendCore: "0xE54559aDB84b59Cc11b2D472C1C65971EA6c36af",
    CollateralManager: "0xecb85226744B135c56659C92f22DACEF1F444a20",
    NFTVerifier: "0xDE82B245755FAa114C731B328eA93cF3E80Fd0e0",
    LiquidityPool: "0x5C7b529e03B527De8A849acAbE5fB3f411B47263",
    LoanVault: "0xC7BDc1F908bCEC19Eb12C2713a2cd387C1324fB9",
    ProposalManager: "0xAD81698b128e73Fe580A118294fAE0fcfD05F45d"
  };

  // Conexão aos contratos
  const yapLendCore = await ethers.getContractAt("YapLendCore", ADDRESSES.YapLendCore);
  const nftVerifier = await ethers.getContractAt("NFTVerifier", ADDRESSES.NFTVerifier);
  const collateralManager = await ethers.getContractAt("CollateralManager", ADDRESSES.CollateralManager);
  const proposalManager = await ethers.getContractAt("ProposalManager", ADDRESSES.ProposalManager);

  console.log("Atualizando referências entre contratos...");

  // Atualizar YapLendCore
  console.log("Atualizando YapLendCore...");
  try {
    await yapLendCore.setCollateralManager(ADDRESSES.CollateralManager);
    console.log("CollateralManager atualizado no YapLendCore");
    
    await yapLendCore.setNFTVerifier(ADDRESSES.NFTVerifier);
    console.log("NFTVerifier atualizado no YapLendCore");
    
    await yapLendCore.setProposalManager(ADDRESSES.ProposalManager);
    console.log("ProposalManager atualizado no YapLendCore");
    
    await yapLendCore.setLoanVault(ADDRESSES.LoanVault);
    console.log("LoanVault atualizado no YapLendCore");
    
    await yapLendCore.setLiquidityPool(ADDRESSES.LiquidityPool);
    console.log("LiquidityPool atualizado no YapLendCore");
  } catch (error) {
    console.log("Erro ao atualizar YapLendCore:", error.message);
  }

  // Atualizar NFTVerifier
  console.log("\nAtualizando NFTVerifier...");
  try {
    await nftVerifier.setCollateralManager(ADDRESSES.CollateralManager);
    console.log("CollateralManager atualizado no NFTVerifier");
  } catch (error) {
    console.log("Erro ao atualizar NFTVerifier:", error.message);
  }

  // Atualizar ProposalManager
  console.log("\nAtualizando ProposalManager...");
  try {
    await proposalManager.updateNFTVerifier();
    console.log("NFTVerifier atualizado no ProposalManager");
  } catch (error) {
    console.log("Erro ao atualizar ProposalManager:", error.message);
  }

  console.log("\nAtualizações concluídas!");
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });