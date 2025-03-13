// Script para teste completo do fluxo principal do YAP LEND
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");

// Endereços dos contratos implantados
const ADDRESSES = {
  // Contratos principais
  PROPOSAL_MANAGER: "0x12a09414eC78bF8BD8832FF93baD0Bc888604320",
  YAP_LEND_CORE: "0x0b79A2fb85b01300C389d6987428FF44F9E99786",
  NFT_VERIFIER: "0x161B38a3e6a4E89222E8fDB2B97C302FBd6Aa53E",
  COLLATERAL_MANAGER: "0x92e4bA72513C6e2a80235fF5cD8060f9d2F5C65e",
  LOAN_VAULT: "0xcd03Bb5f8035bF20dbAf9477C972292FE065CeE6",

  // Endereço do NFT para teste
  NFT_ADDRESS: "0xf79203fc06f9fcc7d48866cb7e8b8b56cd44e3b5",
  TOKEN_ID: 248,
};

async function main() {
  console.log("Iniciando script de teste do fluxo principal do YAP LEND...");
  
  // Obter signers disponíveis
  const signers = await ethers.getSigners();
  const deployer = signers[0];
  console.log(`Deployer: ${deployer.address}`);
  
  // Usar o mesmo signer para todos os papéis
  const borrower = deployer;
  const lender = deployer;
  console.log(`Usando ${deployer.address} como borrower e lender`);
  
  // Conectar aos contratos
  const proposalManager = await ethers.getContractAt("ProposalManager", ADDRESSES.PROPOSAL_MANAGER, deployer);
  const yapLendCore = await ethers.getContractAt("YapLendCore", ADDRESSES.YAP_LEND_CORE, deployer);
  const nftVerifier = await ethers.getContractAt("NFTVerifier", ADDRESSES.NFT_VERIFIER, deployer);
  const collateralManager = await ethers.getContractAt("CollateralManager", ADDRESSES.COLLATERAL_MANAGER, deployer);
  const nftContract = await ethers.getContractAt("IERC721", ADDRESSES.NFT_ADDRESS, deployer);
  const loanVault = await ethers.getContractAt("LoanVault", ADDRESSES.LOAN_VAULT, deployer);
  
  console.log("Contratos conectados com sucesso");
  
  // Verificar se deployer é proprietário do NFT
  try {
    const currentOwner = await nftContract.ownerOf(ADDRESSES.TOKEN_ID);
    console.log(`Proprietário atual do NFT: ${currentOwner}`);
    
    if (currentOwner.toLowerCase() !== deployer.address.toLowerCase()) {
      console.log(`AVISO: O NFT não pertence ao deployer. Você precisa ter a propriedade do NFT para testar.`);
      console.log(`Por favor, transfira o NFT ${ADDRESSES.TOKEN_ID} para ${deployer.address} antes de executar este script.`);
      return;
    }
  } catch (error) {
    console.error("Erro ao verificar propriedade do NFT:", error);
    return;
  }
  
  // Aprovar o NFT para o CollateralManager (importante: mudança de NFTVerifier para CollateralManager)
  console.log(`Aprovando NFT para o CollateralManager (${ADDRESSES.COLLATERAL_MANAGER})...`);
  try {
    await nftContract.connect(deployer).approve(ADDRESSES.COLLATERAL_MANAGER, ADDRESSES.TOKEN_ID);
    console.log("NFT aprovado com sucesso para o CollateralManager");
    
    // Verificar aprovação
    const approvedAddress = await nftContract.getApproved(ADDRESSES.TOKEN_ID);
    console.log(`Endereço aprovado: ${approvedAddress}`);
    if (approvedAddress.toLowerCase() !== ADDRESSES.COLLATERAL_MANAGER.toLowerCase()) {
      console.log("AVISO: O NFT não foi aprovado corretamente para o CollateralManager!");
      return;
    }
  } catch (error) {
    console.error("Erro ao aprovar NFT:", error);
    return;
  }
  
  console.log("\n--- FASE 1: CRIAÇÃO DE PROPOSTA ---");
  
  // Parâmetros para a proposta
  const nftAddresses = [ADDRESSES.NFT_ADDRESS];
  const tokenIds = [ADDRESSES.TOKEN_ID];
  const requestedAmount = ethers.utils.parseEther("0.01"); // 0.01 ETH para teste
  const duration = 7 * 24 * 60 * 60; // 7 dias em segundos
  const interestRate = 1000; // 10% APR em basis points
  
  console.log("Parâmetros da proposta:");
  console.log(`- NFT Addresses: ${nftAddresses}`);
  console.log(`- Token IDs: ${tokenIds}`);
  console.log(`- Requested Amount: ${ethers.utils.formatEther(requestedAmount)} ETH`);
  console.log(`- Duration: ${duration} segundos (${duration / (24 * 60 * 60)} dias)`);
  console.log(`- Interest Rate: ${interestRate / 100}%`);
  
  // Criar proposta
  console.log("\nCriando proposta...");
  
  try {
    // Verificar primeiro usando callStatic para simular a chamada
    console.log("Simulando a criação da proposta...");
    await proposalManager.connect(deployer).callStatic.createProposal(
      nftAddresses,
      tokenIds,
      requestedAmount,
      duration,
      interestRate
    );
    console.log("Simulação bem-sucedida, prosseguindo com a transação real");
    
    const tx = await proposalManager.connect(deployer).createProposal(
      nftAddresses,
      tokenIds,
      requestedAmount,
      duration,
      interestRate
    );
    
    console.log("Transação enviada, aguardando confirmação...");
    const receipt = await tx.wait();
    console.log("Transação confirmada!");
    
    // Encontrar o evento ProposalCreated para obter o proposalId
    const proposalCreatedEvent = receipt.events.find(event => event.event === "ProposalCreated");
    if (!proposalCreatedEvent) {
      console.log("Não foi possível encontrar o evento ProposalCreated no recibo da transação.");
      console.log("Eventos encontrados:", receipt.events.map(e => e.event).join(', '));
      return;
    }
    
    const proposalId = proposalCreatedEvent.args.proposalId;
    console.log(`Proposta criada com sucesso! ID: ${proposalId}`);
    
    console.log("\n--- FASE 2: CRIAÇÃO DE CONTRA-OFERTA ---");
    
    // Parâmetros para a contra-oferta
    const offerAmount = requestedAmount; // Mesma quantia
    const offerDuration = duration; // Mesma duração
    const offerInterestRate = interestRate; // Mesma taxa de juros
    const validityPeriod = 24 * 60 * 60; // 1 dia em segundos
    
    console.log("Parâmetros da contra-oferta:");
    console.log(`- Offer Amount: ${ethers.utils.formatEther(offerAmount)} ETH`);
    console.log(`- Offer Duration: ${offerDuration} segundos (${offerDuration / (24 * 60 * 60)} dias)`);
    console.log(`- Offer Interest Rate: ${offerInterestRate / 100}%`);
    console.log(`- Validity Period: ${validityPeriod} segundos (${validityPeriod / (24 * 60 * 60)} dias)`);
    
    // Criar contra-oferta
    console.log("\nCriando contra-oferta...");
    
    const counterOfferTx = await proposalManager.connect(deployer).createCounterOffer(
      proposalId,
      offerAmount,
      offerDuration,
      offerInterestRate,
      validityPeriod,
      { value: offerAmount.add(ethers.utils.parseEther("0.001")) } // Adicionar um pouco mais para cobrir gás
    );
    
    console.log("Contra-oferta enviada, aguardando confirmação...");
    const counterOfferReceipt = await counterOfferTx.wait();
    console.log("Contra-oferta confirmada!");
    
    // Encontrar o evento CounterOfferCreated para obter o counterProposalId
    const counterOfferCreatedEvent = counterOfferReceipt.events.find(event => event.event === "CounterOfferCreated");
    if (!counterOfferCreatedEvent) {
      console.log("Não foi possível encontrar o evento CounterOfferCreated no recibo da transação.");
      return;
    }
    
    const counterProposalId = counterOfferCreatedEvent.args.proposalId;
    console.log(`Contra-oferta criada com sucesso! ID: ${counterProposalId}`);
    
    console.log("\n--- FASE 3: ACEITAÇÃO DA CONTRA-OFERTA ---");
    
    // Aceitar a contra-oferta
    console.log("\nAceitando contra-oferta...");
    
    // Como estamos usando o mesmo signer para borrower e lender, isso pode causar problemas
    // devido às verificações de remetente no contrato. Verificamos se isso é possível:
    try {
      const proposal = await proposalManager.getProposal(counterProposalId);
      console.log("Detalhes da proposta:", {
        borrower: proposal[0],
        lender: proposal[1],
        amount: ethers.utils.formatEther(proposal[2]),
        isActive: proposal[7],
        isCounterOffer: proposal[8]
      });
      
      // Verificar se podemos aceitar (se o borrower não é o mesmo que lender no contrato)
      if (proposal[0].toLowerCase() === proposal[1].toLowerCase()) {
        console.log("AVISO: O borrower e o lender são o mesmo endereço no contrato.");
        console.log("Isso pode não ser permitido pela lógica do contrato. Pulando aceitação.");
        return;
      }
    } catch (error) {
      console.error("Erro ao verificar proposta:", error);
      return;
    }
    
    const acceptTx = await proposalManager.connect(deployer).acceptProposal(counterProposalId);
    console.log("Aceitação enviada, aguardando confirmação...");
    const acceptReceipt = await acceptTx.wait();
    console.log("Aceitação confirmada!");
    
    // Encontrar o evento ProposalAccepted para obter o loanId
    const proposalAcceptedEvent = acceptReceipt.events.find(event => event.event === "ProposalAccepted");
    if (!proposalAcceptedEvent) {
      console.log("Não foi possível encontrar o evento ProposalAccepted no recibo da transação.");
      return;
    }
    
    const loanId = proposalAcceptedEvent.args.loanId;
    console.log(`Contra-oferta aceita com sucesso! Empréstimo criado com ID: ${loanId}`);
    
    // Verificar detalhes do empréstimo
    const loan = await yapLendCore.loans(loanId);
    console.log("\nDetalhes do empréstimo:");
    console.log(`- Borrower: ${loan.borrower}`);
    console.log(`- Lender: ${loan.lender}`);
    console.log(`- Amount: ${ethers.utils.formatEther(loan.amount)} ETH`);
    console.log(`- Start Time: ${new Date(loan.startTime.toNumber() * 1000).toLocaleString()}`);
    console.log(`- Duration: ${loan.duration} segundos (${loan.duration / (24 * 60 * 60)} dias)`);
    console.log(`- Interest Rate: ${loan.interestRate / 100}%`);
    console.log(`- Active: ${loan.active}`);
    console.log(`- Liquidated: ${loan.liquidated}`);
    
    // Verificar endereços de escrow
    const escrowAddresses = await yapLendCore.getLoanEscrowAddresses(loanId);
    console.log(`\nEscrow Addresses: ${escrowAddresses}`);
    
    console.log("\n--- FASE 4: REPAGAMENTO DO EMPRÉSTIMO ---");
    
    // Calcular juros
    const interest = await loanVault.calculateInterest(loanId);
    const totalRepayment = loan.amount.add(interest);
    
    console.log(`\nJuros calculados: ${ethers.utils.formatEther(interest)} ETH`);
    console.log(`Total a pagar: ${ethers.utils.formatEther(totalRepayment)} ETH`);
    
    // Repagar o empréstimo
    console.log("\nRepagando empréstimo...");
    
    const repayTx = await yapLendCore.connect(deployer).repayLoan(loanId, { value: totalRepayment.add(ethers.utils.parseEther("0.001")) }); // Adicionar um pouco mais para cobrir gás
    console.log("Repagamento enviado, aguardando confirmação...");
    await repayTx.wait();
    console.log("Repagamento confirmado!");
    
    // Verificar se o empréstimo foi atualizado
    const updatedLoan = await yapLendCore.loans(loanId);
    console.log("\nDetalhes do empréstimo após repagamento:");
    console.log(`- Active: ${updatedLoan.active}`);
    console.log(`- Liquidated: ${updatedLoan.liquidated}`);
    
    // Verificar propriedade do NFT após repagamento
    const newOwner = await nftContract.ownerOf(ADDRESSES.TOKEN_ID);
    console.log(`\nProprietário do NFT após repagamento: ${newOwner}`);
    console.log(`O NFT retornou para o borrower? ${newOwner.toLowerCase() === deployer.address.toLowerCase()}`);
    
    console.log("\nTeste do fluxo principal concluído com sucesso!");
  } catch (error) {
    console.error("Erro durante o teste:", error);
    
    if (error.error) {
      console.log("Detalhes do erro:", error.error);
    }
    
    if (error.reason) {
      console.log("Razão do erro:", error.reason);
    }
    
    // Imprimir todas as informações disponíveis para depuração
    console.log("\nInformações adicionais para depuração:");
    console.log(JSON.stringify(error, null, 2));
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });