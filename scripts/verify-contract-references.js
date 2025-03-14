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

  console.log("Verificando referências entre contratos...");

  // Verificar YapLendCore
  console.log("Verificando YapLendCore...");
  try {
    const cmInCore = await yapLendCore.collateralManager();
    console.log(`CollateralManager no YapLendCore: ${cmInCore}`);
    console.log(`Correto: ${cmInCore === ADDRESSES.CollateralManager}`);
    
    const nvInCore = await yapLendCore.nftVerifier();
    console.log(`NFTVerifier no YapLendCore: ${nvInCore}`);
    console.log(`Correto: ${nvInCore === ADDRESSES.NFTVerifier}`);
    
    const pmInCore = await yapLendCore.proposalManager();
    console.log(`ProposalManager no YapLendCore: ${pmInCore}`);
    console.log(`Correto: ${pmInCore === ADDRESSES.ProposalManager}`);
  } catch (error) {
    console.log("Erro ao verificar YapLendCore:", error.message);
  }

  // Verificar NFTVerifier
  console.log("\nVerificando NFTVerifier...");
  try {
    const cmInVerifier = await nftVerifier.collateralManager();
    console.log(`CollateralManager no NFTVerifier: ${cmInVerifier}`);
    console.log(`Correto: ${cmInVerifier === ADDRESSES.CollateralManager}`);
  } catch (error) {
    console.log("Erro ao verificar NFTVerifier:", error.message);
  }

  // Testar funcionalidade básica
  console.log("\nTestando funcionalidade básica...");
  try {
    // Teste de validação de NFT usando um endereço fictício
    const testNftAddress = "0x0000000000000000000000000000000000000001";
    const testTokenId = 1;
    
    const isValid = await nftVerifier.checkOwnership(
      ADDRESSES.CollateralManager, // Qualquer endereço para teste
      testNftAddress,
      testTokenId
    );
    console.log(`Teste de checkOwnership realizado: ${isValid !== undefined}`);
  } catch (error) {
    console.log("Erro ao testar funcionalidade básica:", error.message);
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });