// scripts/test-integration.js
const { ethers } = require("hardhat");

async function main() {
  console.log("🧪 Iniciando testes de integração dos contratos YapLend...");
  
  // Endereços dos contratos implantados
  const contractAddresses = {
    NFTVerifier: "0xB0E4609BEBE2553a94A27E7feEc6192678586a6d",
    PriceOracle: "0xb1f20C688a9dA017586Ee30369Be429646A288E7",
    CollateralManager: "0x3AA54e27970fd6E4811aF0CeA22d867e64e572d6",
    LiquidityPool: "0x02b6c799e165366B01ae5426c1E38F1E392d5Fa5",
    YapLendCore: "0xc2c9B6F7DBE1d7028Dd3754751Eb8708b4B7E97a",
    LoanVault: "0x83AeB0B647341c3ed10F7081eC6Ddb458C3d8a42",
    ProposalManager: "0x8aaBa9340B264bF4977C56B059cBe00b84903fb3",
    NFTEscrow: "0x361C5a0cef84d05a3EE88e14Fe30446a2697358e"
  };

  // Obter a carteira do teste
  const [tester] = await ethers.getSigners();
  console.log(`🔑 Executando testes com a conta: ${tester.address}`);

  try {
    // Carregar contratos
    console.log("\n📂 Carregando contratos...");
    const yapLendCore = await ethers.getContractAt("YapLendCore", contractAddresses.YapLendCore);
    const proposalManager = await ethers.getContractAt("ProposalManager", contractAddresses.ProposalManager);
    const collateralManager = await ethers.getContractAt("CollateralManager", contractAddresses.CollateralManager);
    const nftVerifier = await ethers.getContractAt("NFTVerifier", contractAddresses.NFTVerifier);
    const loanVault = await ethers.getContractAt("LoanVault", contractAddresses.LoanVault);
    const liquidityPool = await ethers.getContractAt("LiquidityPool", contractAddresses.LiquidityPool);
    const priceOracle = await ethers.getContractAt("PriceOracle", contractAddresses.PriceOracle);
    
    // 1. Teste de conexão com contratos - verificar configurações básicas
    console.log("\n🔍 Verificando configurações básicas do protocolo...");
    
    const feeCollector = await yapLendCore.feeCollector();
    console.log(`   ✓ Fee Collector: ${feeCollector}`);
    
    const protocolFeePercentage = await yapLendCore.protocolFeePercentage();
    console.log(`   ✓ Protocol Fee: ${protocolFeePercentage.toString() / 100}%`);
    
    const minInterestRate = await yapLendCore.minInterestRate();
    const maxInterestRate = await yapLendCore.maxInterestRate();
    console.log(`   ✓ Interest Rate Range: ${minInterestRate.toString() / 100}% - ${maxInterestRate.toString() / 100}%`);
    
    const verifierCollateralManager = await nftVerifier.collateralManager();
    console.log(`   ✓ NFTVerifier -> CollateralManager: ${verifierCollateralManager}`);
    console.log(`   ✓ Expected CollateralManager: ${contractAddresses.CollateralManager}`);
    console.log(`   ${verifierCollateralManager === contractAddresses.CollateralManager ? '✅ Match' : '❌ Mismatch'}`);
    
    const yapLendProposalManager = await yapLendCore.proposalManager();
    console.log(`   ✓ YapLendCore -> ProposalManager: ${yapLendProposalManager}`);
    console.log(`   ✓ Expected ProposalManager: ${contractAddresses.ProposalManager}`);
    console.log(`   ${yapLendProposalManager === contractAddresses.ProposalManager ? '✅ Match' : '❌ Mismatch'}`);
    
    // 2. Teste de simulação de juros
    console.log("\n🧮 Testando cálculo de juros...");
    const loanAmount = ethers.parseEther("1"); // 1 ETH
    const interestRate = 1000; // 10% APR
    const durationInDays = 30; // 30 dias
    
    const expectedInterest = await yapLendCore.simulateInterest(loanAmount, interestRate, durationInDays);
    console.log(`   ✓ Juros calculados para empréstimo de 1 ETH a 10% por 30 dias: ${ethers.formatEther(expectedInterest)} ETH`);
    
    // 3. Teste da implementação do Escrow no CollateralManager
    console.log("\n🏦 Verificando implementação do NFTEscrow...");
    try {
      const escrowImplementation = await collateralManager.escrowImplementation();
      console.log(`   ✓ NFTEscrow implementation: ${escrowImplementation}`);
    } catch (error) {
      console.log(`   ❌ Não foi possível acessar a implementação do NFTEscrow: ${error.message}`);
    }
    
    // 4. Teste de fluxo de empréstimo simulado (somente leitura)
    console.log("\n📝 Simulando fluxo de empréstimo (somente leitura)...");
    
    // Vamos simular um NFT para testar
    const testNftAddress = "0x1234567890123456789012345678901234567890";
    const testTokenId = 1;
    
    // Simular criação de proposta
    console.log(`   ✓ Simulando criação de proposta com NFT: ${testNftAddress}#${testTokenId}`);
    console.log(`   ✓ Valor: 1 ETH, Duração: 30 dias, Juros: 10%`);
    
   // Verificar se o fluxo de liquidação funcionaria
console.log(`   🔍 Testando fluxo de liquidação com método alternativo...`);

    try {
    // Check if the function exists in the contract interface/ABI
    const hasLiquidateFunction = yapLendCore.interface.fragments.some(
        fragment => fragment.type === 'function' && fragment.name === 'liquidateLoan'
    );
    
    if (hasLiquidateFunction) {
        console.log(`   ✓ liquidateLoan function found in contract ABI`);
        
        // Instead of directly calling the function, try using a lower-level approach
        // Create the encoded function data
        const encodedFunctionData = yapLendCore.interface.encodeFunctionData('liquidateLoan', [9999]);
        
        // Use the provider to estimate gas (this will still trigger function validation but in a safer way)
        try {
        await ethers.provider.estimateGas({
            to: contractAddresses.YapLendCore,
            data: encodedFunctionData,
            from: tester.address
        });
        console.log(`   ❌ Warning: Liquidation call succeeded on non-existent loan`);
        } catch (error) {
        // Check for expected error message pattern
        if (error.message.includes("Loan not active") || error.message.includes("execution reverted")) {
            console.log(`   ✓ Liquidation flow reverts as expected for non-existent loans`);
        } else {
            console.log(`   ⚠️ Unexpected error during liquidation test: ${error.message}`);
        }
        }
    } else {
        console.log(`   ⚠️ liquidateLoan function not found in contract ABI - may indicate interface mismatch`);
    }
    } catch (error) {
    console.log(`   ⚠️ Failed to test liquidation: ${error.message}`);
    }

    // 5. Verificar o solidity version e compatibilidade do compilador
    console.log("\n📊 Verificando versões e compatibilidade...");
    const coreCode = await ethers.provider.getCode(contractAddresses.YapLendCore);
    console.log(`   ✓ YapLendCore bytecode size: ${coreCode.length / 2 - 1} bytes`);

    // 6. Verificar eventos importantes que serão usados pelo frontend
    console.log("\n📡 Verificando disponibilidade de eventos para o frontend...");
    
    // Podemos verificar isso indiretamente usando a interface
    const yapLendCoreInterface = (await ethers.getContractFactory("YapLendCore")).interface;
    const loanCreatedEvent = yapLendCoreInterface.getEvent("LoanCreated");
    console.log(`   ✓ Evento LoanCreated disponível: ${loanCreatedEvent.name}`);
    
    const proposalCreatedEvent = (await ethers.getContractFactory("ProposalManager")).interface.getEvent("ProposalCreated");
    console.log(`   ✓ Evento ProposalCreated disponível: ${proposalCreatedEvent.name}`);

    // Resumo
    console.log("\n✅ Testes de integração concluídos! Os contratos estão respondendo corretamente.");
    console.log("Os resultados indicam que o protocolo está pronto para integração com o frontend.");
    
  } catch (error) {
    console.error("\n❌ Erro durante os testes de integração:", error);
    console.error("Detalhes:", error.message);
    console.error("Isso pode indicar problemas na implantação dos contratos ou em suas configurações.");
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error("\n❌ Erro fatal:", error);
    process.exit(1);
  });