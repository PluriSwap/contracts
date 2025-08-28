import type { HardhatUserConfig } from "hardhat/config";

import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import { configVariable } from "hardhat/config";

const config: HardhatUserConfig = {
  plugins: [hardhatToolboxViemPlugin],
  solidity: {
    profiles: {
      default: {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      production: {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000, // Higher runs for production deployment
          },
        },
      },
    },
  },
  networks: {
    // Local development networks
    hardhat: {
      type: "edr-simulated",
      chainId: 31337,
    },
    hardhatMainnet: {
      type: "edr-simulated",
      chainType: "l1",
    },
    hardhatOp: {
      type: "edr-simulated",
      chainType: "op",
    },

    // Ethereum networks
    sepolia: {
      type: "http",
      chainType: "l1",
      url: configVariable("SEPOLIA_RPC_URL"),
      accounts: [configVariable("SEPOLIA_PRIVATE_KEY")],
      gasPrice: "auto",
      gas: "auto",
      timeout: 120000,
      chainId: 11155111,
    },
    mainnet: {
      type: "http",
      chainType: "l1",
      url: configVariable("MAINNET_RPC_URL"),
      accounts: [configVariable("MAINNET_PRIVATE_KEY")],
      gasPrice: "auto",
      gas: "auto",
      timeout: 120000,
      chainId: 1,
    },

    // Polygon networks
    polygon: {
      type: "http",
      url: configVariable("POLYGON_RPC_URL"),
      accounts: [configVariable("POLYGON_PRIVATE_KEY")],
      gasPrice: "auto",
      gas: "auto",
      timeout: 120000,
      chainId: 137,
    },
    polygonAmoy: {
      type: "http",
      url: configVariable("POLYGON_AMOY_RPC_URL"),
      accounts: [configVariable("POLYGON_AMOY_PRIVATE_KEY")],
      gasPrice: "auto",
      gas: "auto",
      timeout: 120000,
      chainId: 80002,
    },

    // BNB Chain (BSC) networks
    bsc: {
      type: "http",
      url: configVariable("BSC_RPC_URL"),
      accounts: [configVariable("BSC_PRIVATE_KEY")],
      gasPrice: "auto",
      gas: "auto",
      timeout: 120000,
      chainId: 56,
    },
    bscTestnet: {
      type: "http",
      url: configVariable("BSC_TESTNET_RPC_URL"),
      accounts: [configVariable("BSC_TESTNET_PRIVATE_KEY")],
      gasPrice: "auto",
      gas: "auto",
      timeout: 120000,
      chainId: 97,
    },

    // Arbitrum networks
    arbitrum: {
      type: "http",
      url: configVariable("ARBITRUM_RPC_URL"),
      accounts: [configVariable("ARBITRUM_PRIVATE_KEY")],
      gasPrice: "auto",
      gas: "auto",
      timeout: 120000,
      chainId: 42161,
    },
    arbitrumSepolia: {
      type: "http",
      url: configVariable("ARBITRUM_SEPOLIA_RPC_URL"),
      accounts: [configVariable("ARBITRUM_SEPOLIA_PRIVATE_KEY")],
      gasPrice: "auto",
      gas: "auto",
      timeout: 120000,
      chainId: 421614,
    },

    // Base networks
    base: {
      type: "http",
      url: configVariable("BASE_RPC_URL"),
      accounts: [configVariable("BASE_PRIVATE_KEY")],
      gasPrice: "auto",
      gas: "auto",
      timeout: 120000,
      chainId: 8453,
    },
    baseSepolia: {
      type: "http",
      url: configVariable("BASE_SEPOLIA_RPC_URL"),
      accounts: [configVariable("BASE_SEPOLIA_PRIVATE_KEY")],
      gasPrice: "auto",
      gas: "auto",
      timeout: 120000,
      chainId: 84532,
    },

    // Celo networks
    celo: {
      type: "http",
      url: configVariable("CELO_RPC_URL"),
      accounts: [configVariable("CELO_PRIVATE_KEY")],
      gasPrice: "auto",
      gas: "auto",
      timeout: 120000,
      chainId: 42220,
    },
    celoAlfajores: {
      type: "http",
      url: configVariable("CELO_ALFAJORES_RPC_URL"),
      accounts: [configVariable("CELO_ALFAJORES_PRIVATE_KEY")],
      gasPrice: "auto",
      gas: "auto",
      timeout: 120000,
      chainId: 44787,
    },
  },
  // Etherscan configuration for contract verification
  etherscan: {
    apiKey: {
      // Ethereum networks
      mainnet: configVariable("ETHERSCAN_API_KEY"),
      sepolia: configVariable("ETHERSCAN_API_KEY"),

      // Polygon networks
      polygon: configVariable("POLYGONSCAN_API_KEY"),
      polygonAmoy: configVariable("POLYGONSCAN_API_KEY"),

      // BNB Chain networks
      bsc: configVariable("BSCSCAN_API_KEY"),
      bscTestnet: configVariable("BSCSCAN_API_KEY"),

      // Arbitrum networks
      arbitrum: configVariable("ARBISCAN_API_KEY"),
      arbitrumSepolia: configVariable("ARBISCAN_API_KEY"),

      // Base networks
      base: configVariable("BASESCAN_API_KEY"),
      baseSepolia: configVariable("BASESCAN_API_KEY"),

      // Celo networks
      celo: configVariable("CELO_EXPLORER_API_KEY"),
      celoAlfajores: configVariable("CELO_EXPLORER_API_KEY"),
    },
    customChains: [
      {
        network: "celo",
        chainId: 42220,
        urls: {
          apiURL: "https://api.celoscan.io/api",
          browserURL: "https://celoscan.io/",
        },
      },
      {
        network: "celoAlfajores",
        chainId: 44787,
        urls: {
          apiURL: "https://api-alfajores.celoscan.io/api",
          browserURL: "https://alfajores.celoscan.io/",
        },
      },
    ],
  },
  ignition: {
    requiredConfirmations: {
      // Ethereum networks
      sepolia: 2,
      mainnet: 5,

      // Polygon networks
      polygon: 2,
      polygonAmoy: 2,

      // BNB Chain networks
      bsc: 3,
      bscTestnet: 2,

      // Arbitrum networks
      arbitrum: 1,
      arbitrumSepolia: 1,

      // Base networks
      base: 2,
      baseSepolia: 2,

      // Celo networks
      celo: 1,
      celoAlfajores: 1,
    },
  },
};

export default config;
