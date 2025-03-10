// scripts/transfer-ownership.js
const { ethers } = require("hardhat");

async function main() {
  console.log("Iniciando transferência de ownership dos contratos...");
  
  // Nova carteira que será owner
  const newOwner = "0x61ebCcc4572Ba10CF20Cb8780008526361cf6ef0";
  
  // Endereços dos novos contratos deployados
  const contracts = {
    NFTVerifier: "0xB0E4609BEBE2553a94A27E7feEc6192678586a6d",
    PriceOracle: "0xb1f20C688a9dA017586Ee30369Be429646A288E7",
    CollateralManager: "0x3AA54e27970fd6E4811aF0CeA22d867e64e572d6",
    LiquidityPool: "0x02b6c799e165366B01ae5426c1E38F1E392d5Fa5",
    YapLendCore: "0xc2c9B6F7DBE1d7028Dd3754751Eb8708b4B7E97a",
    LoanVault: "0x83AeB0B647341c3ed10F7081eC6Ddb458C3d8a42",
    ProposalManager: "0x8aaBa9340B264bF4977C56B059cBe00b84903fb3",
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