import { HardhatUserConfig } from 'hardhat/config';
import '@nomicfoundation/hardhat-toolbox';

// Load .env for SEPOLIA_RPC_URL and DEPLOYER_PRIVATE_KEY
// eslint-disable-next-line @typescript-eslint/no-require-imports
require('dotenv').config();

const config: HardhatUserConfig = {
  solidity: '0.8.24',
  paths: {
    sources: './contracts',
    tests: './test',
    cache: './cache',
    artifacts: './artifacts',
  },
  networks: {
    localhost: {
      url: process.env.HARDHAT_RPC_URL ?? 'http://127.0.0.1:8545',
    },
    hardhat: {
      chainId: 31337,
    },
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL ?? '',
      accounts: process.env.DEPLOYER_PRIVATE_KEY
        ? [process.env.DEPLOYER_PRIVATE_KEY]
        : [],
      chainId: 11155111,
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY ?? '',
  },
};

export default config;
