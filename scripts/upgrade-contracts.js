// scripts/upgrade-both-contracts.js
const { ethers, upgrades } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Atualizando contratos com a conta:", deployer.address);
  
  // Endereços dos proxies
  const nftVerifierProxyAddress = "0xB0E4609BEBE2553a94A27E7feEc6192678586a6d";
  const proposalManagerProxyAddress = "0x8aaBa9340B264bF4977C56B059cBe00b84903fb3";
  
  // Passo 1: Upgrade do NFTVerifier
  console.log("\nIniciando upgrade do NFTVerifier...");
  const NFTVerifier = await ethers.getContractFactory("NFTVerifier");
  const upgradedNFTVerifier = await upgrades.upgradeProxy(nftVerifierProxyAddress, NFTVerifier);
  await upgradedNFTVerifier.deployed();
  console.log("NFTVerifier atualizado com sucesso no endereço:", upgradedNFTVerifier.address);
  
  // Passo 2: Upgrade do ProposalManager
  console.log("\nIniciando upgrade do ProposalManager...");
  const ProposalManager = await ethers.getContractFactory("ProposalManager");
  const upgradedProposalManager = await upgrades.upgradeProxy(proposalManagerProxyAddress, ProposalManager);
  await upgradedProposalManager.deployed();
  console.log("ProposalManager atualizado com sucesso no endereço:", upgradedProposalManager.address);
  
  console.log("\nAmbos os contratos foram atualizados com sucesso!");
  
  // Verificar se as implementações estão funcionando corretamente
  console.log("\nVerificando as implementações...");
  
  // Verificar se checkOwnership está disponível no NFTVerifier
  try {
    // Simplificando: apenas verificamos se a função existe e não reverte
    // Para um teste real, você usaria um NFT real
    const dummyAddress = "0x0000000000000000000000000000000000000001";
    await upgradedNFTVerifier.callStatic.checkOwnership(deployer.address, dummyAddress, 1);
    console.log("Função checkOwnership funciona no NFTVerifier ✓");
  } catch (error) {
    console.error("Erro ao chamar checkOwnership:", error.message);
  }
  
  console.log("\nAtualização concluída!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });