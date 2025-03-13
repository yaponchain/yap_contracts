// scripts/transfer-ownership.js
const { ethers } = require("hardhat");

async function main() {
  console.log("Iniciando transferência de ownership dos contratos...");
  
  // Nova carteira que será owner
  const newOwner = "0x61ebCcc4572Ba10CF20Cb8780008526361cf6ef0";
  
  // Endereços dos novos contratos deployados
  const contracts = {
    NFTVerifier: "0x161B38a3e6a4E89222E8fDB2B97C302FBd6Aa53E",
    PriceOracle: "0x068067Ad8926c163d948eCffE4FA3f93BCC9bc85",
    CollateralManager: "0x92e4bA72513C6e2a80235fF5cD8060f9d2F5C65e",
    LiquidityPool: "0xe20a6aa913712dd971178F0e2ab83f37a85311E9",
    YapLendCore: "0x0b79A2fb85b01300C389d6987428FF44F9E99786",
    LoanVault: "0xcd03Bb5f8035bF20dbAf9477C972292FE065CeE6",
    ProposalManager: "0x12a09414eC78bF8BD8832FF93baD0Bc888604320",
    NFTEscrow: "0x6dc29347E508D76083C827402FD20Eb247D150D4",
    
    // Adicionando o NFTEscrow, embora seja possível que não precise de transferência direta
    // já que é gerenciado pelo CollateralManager
    NFTEscrow: "0x361C5a0cef84d05a3EE88e14Fe30446a2697358e"
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
      // Em caso de erro, continue com o próximo contrato
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