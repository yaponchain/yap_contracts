require("@nomicfoundation/hardhat-toolbox");
require('@openzeppelin/hardhat-upgrades');
require('dotenv').config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.26",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    // Configuration for localhost development
    localhost: {
      url: "http://127.0.0.1:8545",
      chainId: 31337,
    },
    // Configuration for Monad testnet
    monad: {
      url: process.env.MONAD_RPC_URL || "https://testnet-rpc2.monad.xyz/52227f026fa8fac9e2014c58fbf5643369b3bfc6",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 10143,
      gas: 8000000,           // Limite de gas explícito
      timeout: 240000,         // Timeout maior (60 segundos)
    },
    // Configuration for testnet (Sepolia)
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL || "https://rpc.sepolia.org",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 11155111,
    },
    // Configuration for mainnet
    mainnet: {
      url: process.env.MAINNET_RPC_URL || "https://eth.llamarpc.com",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 1,
      // Higher gas price for mainnet to ensure transactions go through
      gasPrice: 30000000000, // 30 gwei
    }
  },
  // For Monad verification using Sourcify
  sourcify: {
    enabled: true,
    apiUrl: "https://sourcify-api-monad.blockvision.org",
    browserUrl: "https://testnet.monadexplorer.com/"
  },
  etherscan: {
    enabled: false, // Disabled for Monad as we're using Sourcify instead
    apiKey: process.env.ETHERSCAN_API_KEY // Kept for other networks
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS ? true : false,
    currency: 'USD',
    coinmarketcap: process.env.COINMARKETCAP_API_KEY,
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  mocha: {
    timeout: 40000
  }
};