const { ethers, upgrades } = require("hardhat");

async function main() {
  console.log("Starting LoanVault upgrade process...");

  // Endereço do proxy existente do LoanVault
  const LOAN_VAULT_PROXY_ADDRESS = "0xcd03Bb5f8035bF20dbAf9477C972292FE065CeE6";
  
  // Endereço do YapLendCore para inicialização
  const YAP_LEND_CORE_ADDRESS = "0x0b79A2fb85b01300C389d6987428FF44F9E99786";
  
  // 1. Faça o upgrade do LoanVault
  console.log("Deploying new LoanVault implementation...");
  const LoanVault = await ethers.getContractFactory("LoanVault");
  const upgradedLoanVault = await upgrades.upgradeProxy(LOAN_VAULT_PROXY_ADDRESS, LoanVault);
  
  // Removida chamada para deployed() que estava causando o erro
  console.log("LoanVault upgraded at:", upgradedLoanVault.address);
  
  // 2. Atualize a referência no YapLendCore
  console.log("Updating LoanVault reference in YapLendCore...");
  const YapLendCore = await ethers.getContractFactory("YapLendCore");
  const yapLendCore = YapLendCore.attach(YAP_LEND_CORE_ADDRESS);
  
  try {
    // Verificar se o getter loanVault existe
    const currentLoanVault = await yapLendCore.loanVault();
    console.log("Current LoanVault address in YapLendCore:", currentLoanVault);

    // Atualizar o endereço se necessário
    if (currentLoanVault.toLowerCase() !== upgradedLoanVault.address.toLowerCase()) {
      const tx = await yapLendCore.setLoanVault(upgradedLoanVault.address);
      await tx.wait();
      console.log("YapLendCore updated with new LoanVault address");
      
      // Verificar se a atualização foi bem-sucedida
      const newLoanVaultAddress = await yapLendCore.loanVault();
      if (newLoanVaultAddress.toLowerCase() === upgradedLoanVault.address.toLowerCase()) {
        console.log("✅ YapLendCore reference updated successfully!");
      } else {
        console.log("❌ YapLendCore reference update failed!");
      }
    } else {
      console.log("✅ YapLendCore already has the correct LoanVault reference");
    }
  } catch (error) {
    console.error("Error accessing YapLendCore loanVault:", error.message);
    console.log("Trying to update reference directly...");
    try {
      const tx = await yapLendCore.setLoanVault(upgradedLoanVault.address);
      await tx.wait();
      console.log("✅ YapLendCore reference update command sent");
    } catch (updateError) {
      console.error("Failed to update YapLendCore reference:", updateError.message);
    }
  }
  
  console.log("Upgrade process completed!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });