const { ethers } = require("hardhat");

async function main() {
  console.log("Iniciando transferência de ownership dos contratos...");
  
  // Nova carteira que será owner
  let newOwner = "0x61ebCcc4572Ba10CF20Cb8780008526361cf6ef0";
  
  // Endereços dos novos contratos deployados
  const contracts = {
    NFTVerifier: "0xDE82B245755FAa114C731B328eA93cF3E80Fd0e0",
    PriceOracle: "0x08f1e427E0A42561ddAf74d023031151429CCF7C",
    CollateralManager: "0xecb85226744B135c56659C92f22DACEF1F444a20",
    LiquidityPool: "0x5C7b529e03B527De8A849acAbE5fB3f411B47263",
    YapLendCore: "0xE54559aDB84b59Cc11b2D472C1C65971EA6c36af",
    LoanVault: "0xC7BDc1F908bCEC19Eb12C2713a2cd387C1324fB9",
    ProposalManager: "0xAD81698b128e73Fe580A118294fAE0fcfD05F45d",
    NFTEscrow: "0x41DA9EC21Cca9429518d42eB01730d982746bBD9"
  };

  // Normalizar todos os endereços para o formato de checksum correto
  for (const name in contracts) {
    try {
      contracts[name] = ethers.getAddress(contracts[name]);
      console.log(`Endereço de ${name} normalizado: ${contracts[name]}`);
    } catch (error) {
      console.error(`Erro ao normalizar endereço de ${name}:`, error.message);
    }
  }

  // Também normalize o endereço do novo owner
  newOwner = ethers.getAddress(newOwner);
  console.log(`Endereço do novo owner normalizado: ${newOwner}`);

  // Obter a carteira do deployer (que é o owner atual)
  const [deployer] = await ethers.getSigners();
  console.log(`Transferindo ownership da carteira ${deployer.address} para ${newOwner}`);

  // Para cada contrato, transferir ownership
  for (const [name, address] of Object.entries(contracts)) {
    // Pular o NFTEscrow pois é gerenciado pelo CollateralManager
    if (name === "NFTEscrow" || name === "NFTEscrowImpl") {
      console.log(`\nPulando ${name} pois é gerenciado pelo CollateralManager...`);
      continue;
    }
    
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