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
    sepolia: {
      type: "http",
      chainType: "l1",
      url: configVariable("SEPOLIA_RPC_URL"),
      accounts: [configVariable("SEPOLIA_PRIVATE_KEY")],
      gasPrice: "auto",
      gas: "auto",
      timeout: 120000,
    },
    // Mainnet configuration (for future use) 
    // mainnet: {
    //   type: "http",
    //   chainType: "l1", 
    //   url: configVariable("MAINNET_RPC_URL"),
    //   accounts: [configVariable("MAINNET_PRIVATE_KEY")],
    //   gasPrice: "auto",
    // },
  },
  // Etherscan configuration - set ETHERSCAN_API_KEY for verification
  // etherscan: {
  //   apiKey: {
  //     sepolia: configVariable("ETHERSCAN_API_KEY"),
  //   },
  // },
  ignition: {
    requiredConfirmations: {
      sepolia: 2,
      mainnet: 5,
    },
  },
};

export default config;
