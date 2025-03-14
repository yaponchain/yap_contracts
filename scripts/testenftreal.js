// Script para testar a verificação de NFT com um exemplo real
async function testarNFTReal() {
    // Substitua estes valores pelos detalhes do NFT real
    const nftAddress = "0xd97bce4518b886a36e345764333d77b5faf6fe2c";  // NFT que o usuário estava tentando usar
    const tokenId =  12548;  // Token ID específico
    const ownerAddress = "0xB170A41F2523220A12F84f17A54bD31953D98027";  // Endereço do usuário
    
    // Obtenha instâncias dos contratos
    const nftVerifier = await ethers.getContractAt("NFTVerifier", "0x42D3b99Ac1bef5eb3E949b543EdE612F3d90ee4F");
    const collateralManager = await ethers.getContractAt("CollateralManager", "0x1EE1BfcFB8514d4c68f20e3119cb43439befa212");
    
    console.log("===== TESTE COM NFT REAL =====");
    
    // Teste 1: Verificar se o NFT existe e quem é o proprietário
    console.log("1. Verificando propriedade básica do NFT...");
    try {
      const nftContract = await ethers.getContractAt("IERC721", nftAddress);
      const actualOwner = await nftContract.ownerOf(tokenId);
      console.log(`   Proprietário real do NFT: ${actualOwner}`);
      console.log(`   Corresponde ao endereço do usuário: ${actualOwner === ownerAddress}`);
    } catch (error) {
      console.log(`   Erro ao verificar o NFT: ${error.message}`);
    }
    
    // Teste 2: Verificar a função checkOwnership diretamente
    console.log("\n2. Testando função checkOwnership do NFTVerifier...");
    try {
      const isOwner = await nftVerifier.checkOwnership(ownerAddress, nftAddress, tokenId);
      console.log(`   Resultado checkOwnership: ${isOwner}`);
    } catch (error) {
      console.log(`   Erro em checkOwnership: ${error.message}`);
      // Log mais detalhado do erro para diagnóstico
      console.log(`   Detalhes do erro:`, error);
    }
    
    // Teste 3: Verificar a função validateCollateral diretamente
    console.log("\n3. Testando função validateCollateral do CollateralManager...");
    try {
      const isValid = await collateralManager.validateCollateral(nftAddress, tokenId);
      console.log(`   Resultado validateCollateral: ${isValid}`);
    } catch (error) {
      console.log(`   Erro em validateCollateral: ${error.message}`);
      console.log(`   Detalhes do erro:`, error);
    }
    
    // Teste 4: Verificar aprovação do NFT para o CollateralManager
    console.log("\n4. Verificando se o NFT está aprovado para o CollateralManager...");
    try {
      const isApproved = await nftVerifier.checkApproval(ownerAddress, nftAddress, tokenId);
      console.log(`   Resultado checkApproval: ${isApproved}`);
    } catch (error) {
      console.log(`   Erro em checkApproval: ${error.message}`);
      console.log(`   Detalhes do erro:`, error);
    }
  }
  
  // Execute o teste
  testarNFTReal()
    .then(() => process.exit(0))
    .catch(error => {
      console.error(error);
      process.exit(1);
    });