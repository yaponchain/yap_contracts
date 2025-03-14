// Script para verificar a inicialização e interligação dos contratos YapLend
const { ethers } = require("hardhat");

// Endereços dos contratos implantados
const ADDRESSES = {
  PriceOracle: "0x0b5B462B58bF25bC3445CBF3E5982D184A371c17",
  YapLendCore: "0xb38F84511740227b314c58D7346B643f1D5c4BdD",
  CollateralManager: "0x1EE1BfcFB8514d4c68f20e3119cb43439befa212",
  NFTVerifier: "0x42D3b99Ac1bef5eb3E949b543EdE612F3d90ee4F",
  LiquidityPool: "0xAF2a341Ca209Df41F90FacB5E012312681Af4a73",
  LoanVault: "0xC09d7fD94C8026738554bafc8dBA3d11A6618cBE",
  ProposalManager: "0x8aBa171f3E9417d7F307c01AE45499C2Ae9B9971"
};

async function verificarInicializacao() {
  console.log("===== VERIFICAÇÃO DE INICIALIZAÇÃO DOS CONTRATOS =====\n");
  
  // Obter instâncias dos contratos
  const priceOracle = await ethers.getContractAt("PriceOracle", ADDRESSES.PriceOracle);
  const yapLendCore = await ethers.getContractAt("YapLendCore", ADDRESSES.YapLendCore);
  const collateralManager = await ethers.getContractAt("CollateralManager", ADDRESSES.CollateralManager);
  const nftVerifier = await ethers.getContractAt("NFTVerifier", ADDRESSES.NFTVerifier);
  const liquidityPool = await ethers.getContractAt("LiquidityPool", ADDRESSES.LiquidityPool);
  const loanVault = await ethers.getContractAt("LoanVault", ADDRESSES.LoanVault);
  const proposalManager = await ethers.getContractAt("ProposalManager", ADDRESSES.ProposalManager);
  
  // Verificar valores básicos para confirmar inicialização
  try {
    console.log("==== YapLendCore ====");
    const owner = await yapLendCore.owner();
    console.log("Owner:", owner);
    const feeCollector = await yapLendCore.feeCollector();
    console.log("Fee Collector:", feeCollector);
    const proposalManagerAddress = await yapLendCore.proposalManager();
    console.log("Proposal Manager no YapLendCore:", proposalManagerAddress);
    const cmAddress = await yapLendCore.collateralManager();
    console.log("CollateralManager no YapLendCore:", cmAddress);
    const nftVerifierAddress = await yapLendCore.nftVerifier();
    console.log("NFTVerifier no YapLendCore:", nftVerifierAddress);
    
    console.log("\n==== CollateralManager ====");
    const cmOwner = await collateralManager.owner();
    console.log("Owner:", cmOwner);
    const escrowImpl = await collateralManager.escrowImplementation();
    console.log("Escrow Implementation:", escrowImpl);
    
    console.log("\n==== NFTVerifier ====");
    const nvOwner = await nftVerifier.owner();
    console.log("Owner:", nvOwner);
    const cmInVerifier = await nftVerifier.collateralManager();
    console.log("CollateralManager no NFTVerifier:", cmInVerifier);
    
    console.log("\n==== ProposalManager ====");
    const pmOwner = await proposalManager.owner();
    console.log("Owner:", pmOwner);
    // Tentando acessar o YapLendCore no ProposalManager
    try {
      // Pode não ser uma variável pública acessível diretamente
      const yapLendCoreInPM = await proposalManager._yapLendCore();
      console.log("YapLendCore no ProposalManager:", yapLendCoreInPM);
    } catch (error) {
      console.log("Não foi possível acessar _yapLendCore diretamente");
    }
    
    console.log("\n==== LoanVault ====");
    const lvOwner = await loanVault.owner();
    console.log("Owner:", lvOwner);
    
    console.log("\n==== LiquidityPool ====");
    const lpOwner = await liquidityPool.owner();
    console.log("Owner:", lpOwner);
    
    console.log("\n==== PriceOracle ====");
    const poOwner = await priceOracle.owner();
    console.log("Owner:", poOwner);
    
  } catch (error) {
    console.log("Erro na verificação básica:", error.message);
  }
}

async function verificarIntegracao() {
  console.log("\n\n===== VERIFICAÇÃO DE INTEGRAÇÃO ENTRE CONTRATOS =====\n");
  
  // Obter instâncias dos contratos
  const yapLendCore = await ethers.getContractAt("YapLendCore", ADDRESSES.YapLendCore);
  const collateralManager = await ethers.getContractAt("CollateralManager", ADDRESSES.CollateralManager);
  const nftVerifier = await ethers.getContractAt("NFTVerifier", ADDRESSES.NFTVerifier);
  const proposalManager = await ethers.getContractAt("ProposalManager", ADDRESSES.ProposalManager);
  
  // Verificar integração entre os contratos
  try {
    // Verificar endereços no YapLendCore
    console.log("Verificando integração do YapLendCore...");
    
    // CollateralManager no YapLendCore
    const cmInCore = await yapLendCore.collateralManager();
    const integracaoCM = cmInCore === ADDRESSES.CollateralManager;
    console.log("CollateralManager correto no YapLendCore:", integracaoCM);
    if (!integracaoCM) {
      console.log("  Esperado:", ADDRESSES.CollateralManager);
      console.log("  Atual:", cmInCore);
    }
    
    // NFTVerifier no YapLendCore
    const nvInCore = await yapLendCore.nftVerifier();
    const integracaoNV = nvInCore === ADDRESSES.NFTVerifier;
    console.log("NFTVerifier correto no YapLendCore:", integracaoNV);
    if (!integracaoNV) {
      console.log("  Esperado:", ADDRESSES.NFTVerifier);
      console.log("  Atual:", nvInCore);
    }
    
    // ProposalManager no YapLendCore
    const pmInCore = await yapLendCore.proposalManager();
    const integracaoPM = pmInCore === ADDRESSES.ProposalManager;
    console.log("ProposalManager correto no YapLendCore:", integracaoPM);
    if (!integracaoPM) {
      console.log("  Esperado:", ADDRESSES.ProposalManager);
      console.log("  Atual:", pmInCore);
    }
    
    // Verificar CollateralManager no NFTVerifier
    console.log("\nVerificando integração do NFTVerifier...");
    try {
      const cmInVerifier = await nftVerifier.collateralManager();
      const integracaoCMInVerifier = cmInVerifier === ADDRESSES.CollateralManager;
      console.log("CollateralManager correto no NFTVerifier:", integracaoCMInVerifier);
      if (!integracaoCMInVerifier) {
        console.log("  Esperado:", ADDRESSES.CollateralManager);
        console.log("  Atual:", cmInVerifier);
      }
    } catch (error) {
      console.log("Erro ao verificar CollateralManager no NFTVerifier:", error.message);
    }
    
    // Verificar YapLendCore no ProposalManager (se acessível)
    console.log("\nVerificando integração do ProposalManager...");
    try {
      // A seguinte chamada pode falhar se _yapLendCore não for público
      const coreInPM = await proposalManager._yapLendCore();
      const integracaoCoreInPM = coreInPM === ADDRESSES.YapLendCore;
      console.log("YapLendCore correto no ProposalManager:", integracaoCoreInPM);
      if (!integracaoCoreInPM) {
        console.log("  Esperado:", ADDRESSES.YapLendCore);
        console.log("  Atual:", coreInPM);
      }
    } catch (error) {
      console.log("Não foi possível verificar _yapLendCore no ProposalManager:", error.message);
      console.log("Isso pode ocorrer se a variável não for pública ou se a integração estiver errada");
    }
    
  } catch (error) {
    console.log("Erro na verificação de integração:", error.message);
  }
}

async function verificarFuncionalidades() {
  console.log("\n\n===== VERIFICAÇÃO DE FUNCIONALIDADES ESPECÍFICAS =====\n");
  
  const yapLendCore = await ethers.getContractAt("YapLendCore", ADDRESSES.YapLendCore);
  const nftVerifier = await ethers.getContractAt("NFTVerifier", ADDRESSES.NFTVerifier);
  const collateralManager = await ethers.getContractAt("CollateralManager", ADDRESSES.CollateralManager);
  
  try {
    // Verificar parâmetros de juros no YapLendCore
    console.log("Verificando parâmetros de juros...");
    const minRate = await yapLendCore.minInterestRate();
    const maxRate = await yapLendCore.maxInterestRate();
    console.log("Taxa mínima de juros:", minRate.toString());
    console.log("Taxa máxima de juros:", maxRate.toString());
    
    // Verificar se o CollateralManager pode validar um NFT (teste com endereço zero)
    console.log("\nVerificando funcionalidade de validação de NFT...");
    try {
      const validacaoNFT = await collateralManager.validateCollateral(
        "0x0000000000000000000000000000000000000001", // endereço qualquer
        1 // tokenId qualquer
      );
      console.log("Validação de NFT funcionando:", validacaoNFT !== undefined);
    } catch (error) {
      console.log("Erro na validação de NFT:", error.message);
    }
    
    // Verificar se o NFTVerifier está operacional
    console.log("\nVerificando funcionalidade do NFTVerifier...");
    try {
      const checkOwnership = await nftVerifier.checkOwnership(
        "0x0000000000000000000000000000000000000001", // endereço de dono qualquer
        "0x0000000000000000000000000000000000000002", // endereço de NFT qualquer
        1 // tokenId qualquer
      );
      console.log("Função checkOwnership funcionando:", checkOwnership !== undefined);
    } catch (error) {
      console.log("Erro no checkOwnership:", error.message);
    }
    
  } catch (error) {
    console.log("Erro na verificação de funcionalidades:", error.message);
  }
}

async function main() {
  await verificarInicializacao();
  await verificarIntegracao();
  await verificarFuncionalidades();
}

// Execute a verificação
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });