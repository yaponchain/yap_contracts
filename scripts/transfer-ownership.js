// scripts/transfer-ownership.js
const { ethers } = require("hardhat");

async function main() {
  console.log("Iniciando transferência de ownership dos contratos...");
  
  // Nova carteira que será owner
  const newOwner = "0x61ebCcc4572Ba10CF20Cb8780008526361cf6ef0";
  
  // Endereços dos contratos deployados
  const contracts = {
    NFTVerifier: "0x54E466e0932E918b4d390EE66e7371ec4eBB92cd",
    PriceOracle: "0xCB02e345620561435d5a174dc43d6b3e2a7ece7e",
    CollateralManager: "0x8FA2C5Dfbd65811135F2ABd0EBaEAF4710ca1bC0",
    LiquidityPool: "0xf8068Dff989bD9f5cD7eBC689D93710330847A78",
    YapLendCore: "0x5C9057C403c49867004D3C91Cea44A892DAc8009",
    LoanVault: "0x31902a62Fd035FddE1a85a1E9C6928186dbF0EFf",
    ProposalManager: "0xBDd6e00FaDD9E57EE72dd91DE92aC2131CE1fe3C"
  };

  // Obter a carteira do deployer (que é o owner atual)
  const [deployer] = await ethers.getSigners();
  console.log(`Transferindo ownership da carteira ${deployer.address} para ${newOwner}`);

  // Para cada contrato, transferir ownership
  for (const [name, address] of Object.entries(contracts)) {
    console.log(`\nTransferindo ownership do contrato ${name}...`);
    
    try {
      // Carregue o contrato com a interface mínima necessária (apenas a função transferOwnership)
      const contract = await ethers.getContractAt(
        ["function transferOwnership(address newOwner) public"],
        address,
        deployer
      );
      
      // Chame a função transferOwnership
      const tx = await contract.transferOwnership(newOwner);
      await tx.wait();
      
      console.log(`✅ Ownership do contrato ${name} transferido com sucesso!`);
    } catch (error) {
      console.error(`❌ Erro ao transferir ownership do contrato ${name}:`, error.message);
    }
  }

  console.log("\n✨ Processo de transferência de ownership concluído!");
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error("Erro no processo de transferência:", error);
    process.exit(1);
  });