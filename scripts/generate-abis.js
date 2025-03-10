// scripts/generate-abis.js
const fs = require('fs');
const path = require('path');
const hre = require('hardhat');

async function main() {
  console.log("Iniciando geração de arquivos ABI para integração com front-end...");
  
  // Lista de contratos para gerar ABIs
  const contracts = [
    "NFTVerifier",
    "PriceOracle",
    "CollateralManager",
    "LiquidityPool",
    "YapLendCore",
    "LoanVault",
    "ProposalManager",
    "NFTEscrow"
  ];

  // Lista de endereços implantados (para incluir nos arquivos)
  const addresses = {
    NFTVerifier: "0xB0E4609BEBE2553a94A27E7feEc6192678586a6d",
    PriceOracle: "0xb1f20C688a9dA017586Ee30369Be429646A288E7",
    CollateralManager: "0x3AA54e27970fd6E4811aF0CeA22d867e64e572d6",
    LiquidityPool: "0x02b6c799e165366B01ae5426c1E38F1E392d5Fa5",
    YapLendCore: "0xc2c9B6F7DBE1d7028Dd3754751Eb8708b4B7E97a",
    LoanVault: "0x83AeB0B647341c3ed10F7081eC6Ddb458C3d8a42",
    ProposalManager: "0x8aaBa9340B264bF4977C56B059cBe00b84903fb3",
    NFTEscrow: "0x361C5a0cef84d05a3EE88e14Fe30446a2697358e"
  };

  // Criar pasta abis se não existir
  const abisDir = path.join(__dirname, '../abis');
  if (!fs.existsSync(abisDir)) {
    fs.mkdirSync(abisDir, { recursive: true });
  }

  // Para cada contrato, gerar e salvar o ABI
  for (const contractName of contracts) {
    try {
      console.log(`\nGerando ABI para ${contractName}...`);
      
      // Buscar o artefato do contrato compilado
      const artifact = await hre.artifacts.readArtifact(contractName);
      
      // Criar objeto com ABI e endereço
      const contractInfo = {
        contractName: contractName,
        address: addresses[contractName],
        abi: artifact.abi
      };
      
      // Salvar em formato JSON
      const filePath = path.join(abisDir, `${contractName}.json`);
      fs.writeFileSync(
        filePath,
        JSON.stringify(contractInfo, null, 2)
      );
      
      console.log(`✅ ABI de ${contractName} gerado com sucesso em: ${filePath}`);
    } catch (error) {
      console.error(`❌ Erro ao gerar ABI para ${contractName}:`, error.message);
    }
  }

  // Adicionalmente, criar um arquivo index.js para facilitar o import no front-end
  let indexContent = `// Generated ABIs index file\n\n`;
  
  for (const contractName of contracts) {
    indexContent += `const ${contractName}ABI = require('./${contractName}.json');\n`;
  }
  
  indexContent += `\nmodule.exports = {\n`;
  contracts.forEach((contractName, index) => {
    indexContent += `  ${contractName}ABI${index < contracts.length - 1 ? ',' : ''}\n`;
  });
  indexContent += `};\n`;
  
  fs.writeFileSync(path.join(abisDir, 'index.js'), indexContent);
  
  console.log("\n✨ Processo de geração de ABIs concluído!");
  console.log(`📁 Todos os arquivos foram salvos na pasta: ${abisDir}`);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error("Erro no processo de geração de ABIs:", error);
    process.exit(1);
  });