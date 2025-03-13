const { ethers } = require("hardhat");

async function main() {
  console.log("Starting ownership transfer process...");
  
  // Endereços dos contratos
  const LOAN_VAULT_ADDRESS = "0xcd03Bb5f8035bF20dbAf9477C972292FE065CeE6";
  const YAP_LEND_CORE_ADDRESS = "0x0b79A2fb85b01300C389d6987428FF44F9E99786";
  
  // Endereço do desenvolvedor web2 que receberá a propriedade
  const WEB2_DEV_ADDRESS = "0x61ebCcc4572Ba10CF20Cb8780008526361cf6ef0"; 
  
  const [signer] = await ethers.getSigners();
  console.log("Using address for transfers:", await signer.getAddress());
  
  // Transferir propriedade do LoanVault
  console.log("\n1. Transferring LoanVault ownership...");
  try {
    const LoanVault = await ethers.getContractFactory("LoanVault");
    const loanVault = LoanVault.attach(LOAN_VAULT_ADDRESS);
    
    const currentOwner = await loanVault.owner();
    console.log("Current LoanVault owner:", currentOwner);
    
    if ((await signer.getAddress()).toLowerCase() === currentOwner.toLowerCase()) {
      console.log("Initiating ownership transfer to:", WEB2_DEV_ADDRESS);
      const tx = await loanVault.transferOwnership(WEB2_DEV_ADDRESS);
      await tx.wait();
      console.log("Transaction hash:", tx.hash);
      
      const newOwner = await loanVault.owner();
      console.log("New LoanVault owner:", newOwner);
      console.log("LoanVault ownership transfer completed!");
    } else {
      console.log("You are not the current owner of LoanVault, cannot transfer ownership.");
    }
  } catch (error) {
    console.error("Error transferring LoanVault ownership:", error.message);
  }
  
  // Transferir propriedade do YapLendCore
  console.log("\n2. Transferring YapLendCore ownership...");
  try {
    const YapLendCore = await ethers.getContractFactory("YapLendCore");
    const yapLendCore = YapLendCore.attach(YAP_LEND_CORE_ADDRESS);
    
    const currentOwner = await yapLendCore.owner();
    console.log("Current YapLendCore owner:", currentOwner);
    
    if ((await signer.getAddress()).toLowerCase() === currentOwner.toLowerCase()) {
      console.log("Initiating ownership transfer to:", WEB2_DEV_ADDRESS);
      const tx = await yapLendCore.transferOwnership(WEB2_DEV_ADDRESS);
      await tx.wait();
      console.log("Transaction hash:", tx.hash);
      
      const newOwner = await yapLendCore.owner();
      console.log("New YapLendCore owner:", newOwner);
      console.log("YapLendCore ownership transfer completed!");
    } else {
      console.log("You are not the current owner of YapLendCore, cannot transfer ownership.");
    }
  } catch (error) {
    console.error("Error transferring YapLendCore ownership:", error.message);
  }
  
  console.log("\nAll ownership transfers attempted!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });