const { ethers } = require("hardhat");

async function checkOwnership() {
  // Endereço do proxy do LoanVault
  const LOAN_VAULT_PROXY_ADDRESS = "0x..."; // Seu endereço
  
  // Conectar com a carteira
  const [signer] = await ethers.getSigners();
  const signerAddress = await signer.getAddress();
  console.log("Using address:", signerAddress);
  
  // Interface mínima para verificar owner
  const abi = [
    "function owner() external view returns (address)"
  ];
  
  const loanVault = new ethers.Contract(LOAN_VAULT_PROXY_ADDRESS, abi, signer);
  
  try {
    const owner = await loanVault.owner();
    console.log("Contract owner:", owner);
    console.log("You are the owner:", owner.toLowerCase() === signerAddress.toLowerCase());
  } catch (error) {
    console.error("Error checking ownership:", error.message);
    console.log("This might not be an upgradeable proxy or the function doesn't exist");
  }
}

checkOwnership()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });