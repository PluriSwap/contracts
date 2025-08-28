/**
 * PluriSwap Deployment Configuration
 *
 * Network-specific configuration for contract deployments
 */

import { parseEther } from "viem";

export interface NetworkConfig {
  name: string;
  displayName: string;
  chainId: number;
  isTestnet: boolean;
  nativeCurrency: {
    name: string;
    symbol: string;
    decimals: number;
  };
  blockTime: number; // seconds
  gasPrice: {
    min: bigint;
    max: bigint;
  };
  deploymentConfig: {
    escrowFeePercent: number; // basis points
    disputeFeePercent: number; // basis points
    minFee: bigint;
    maxFee: bigint;
    minTimeout: number; // seconds
    maxTimeout: number; // seconds
  };
  stargateRouter?: `0x${string}`; // Stargate router address for cross-chain
  wethAddress?: `0x${string}`; // WETH address for the network
}

export const NETWORK_CONFIGS: { [network: string]: NetworkConfig } = {
  // Ethereum Mainnet
  mainnet: {
    name: "mainnet",
    displayName: "Ethereum Mainnet",
    chainId: 1,
    isTestnet: false,
    nativeCurrency: {
      name: "Ether",
      symbol: "ETH",
      decimals: 18,
    },
    blockTime: 12,
    gasPrice: {
      min: parseEther("0.00000001"), // 10 gwei
      max: parseEther("0.0001"), // 100 gwei
    },
    deploymentConfig: {
      escrowFeePercent: 250, // 2.5%
      disputeFeePercent: 100, // 1%
      minFee: parseEther("0.001"),
      maxFee: parseEther("1.0"),
      minTimeout: 3600, // 1 hour
      maxTimeout: 2592000, // 30 days
    },
    wethAddress: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
  },

  // Ethereum Sepolia Testnet
  sepolia: {
    name: "sepolia",
    displayName: "Ethereum Sepolia",
    chainId: 11155111,
    isTestnet: true,
    nativeCurrency: {
      name: "Sepolia Ether",
      symbol: "ETH",
      decimals: 18,
    },
    blockTime: 12,
    gasPrice: {
      min: parseEther("0.000000001"), // 1 gwei
      max: parseEther("0.00001"), // 10 gwei
    },
    deploymentConfig: {
      escrowFeePercent: 250, // 2.5%
      disputeFeePercent: 100, // 1%
      minFee: parseEther("0.001"),
      maxFee: parseEther("1.0"),
      minTimeout: 3600, // 1 hour
      maxTimeout: 2592000, // 30 days
    },
    wethAddress: "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14",
  },

  // Polygon Mainnet
  polygon: {
    name: "polygon",
    displayName: "Polygon Mainnet",
    chainId: 137,
    isTestnet: false,
    nativeCurrency: {
      name: "Matic",
      symbol: "MATIC",
      decimals: 18,
    },
    blockTime: 2,
    gasPrice: {
      min: parseEther("0.00000003"), // 30 gwei
      max: parseEther("0.000005"), // 5000 gwei
    },
    deploymentConfig: {
      escrowFeePercent: 200, // 2% (lower due to cheaper gas)
      disputeFeePercent: 80, // 0.8%
      minFee: parseEther("0.01"), // Higher min fee due to MATIC price
      maxFee: parseEther("10.0"),
      minTimeout: 3600,
      maxTimeout: 2592000,
    },
    wethAddress: "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270", // WMATIC
    stargateRouter: "0x45A01E4e04F14f7A4a6702c74187c5F622203379",
  },

  // Polygon Amoy Testnet
  polygonAmoy: {
    name: "polygonAmoy",
    displayName: "Polygon Amoy",
    chainId: 80002,
    isTestnet: true,
    nativeCurrency: {
      name: "Matic",
      symbol: "MATIC",
      decimals: 18,
    },
    blockTime: 2,
    gasPrice: {
      min: parseEther("0.000000001"), // 1 gwei
      max: parseEther("0.000001"), // 1000 gwei
    },
    deploymentConfig: {
      escrowFeePercent: 200, // 2%
      disputeFeePercent: 80, // 0.8%
      minFee: parseEther("0.01"),
      maxFee: parseEther("10.0"),
      minTimeout: 3600,
      maxTimeout: 2592000,
    },
    wethAddress: "0x360ad4f9a9A8EFe9A8DCB5f461c4Cc1047E1Dcf9", // WMATIC on Amoy
    stargateRouter: "0x9AdD0F32eB7e8f4C8c7f8a2c3b4D5E6F7A8B9C0D", // Placeholder - needs update
  },

  // BNB Chain Mainnet
  bsc: {
    name: "bsc",
    displayName: "BNB Chain Mainnet",
    chainId: 56,
    isTestnet: false,
    nativeCurrency: {
      name: "BNB",
      symbol: "BNB",
      decimals: 18,
    },
    blockTime: 3,
    gasPrice: {
      min: parseEther("0.000000005"), // 5 gwei
      max: parseEther("0.00001"), // 10 gwei
    },
    deploymentConfig: {
      escrowFeePercent: 200, // 2%
      disputeFeePercent: 80, // 0.8%
      minFee: parseEther("0.001"),
      maxFee: parseEther("5.0"),
      minTimeout: 3600,
      maxTimeout: 2592000,
    },
    wethAddress: "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c", // WBNB
    stargateRouter: "0x4a364f8c717cAAD9A442737Eb7b8A55cc6cf18D8",
  },

  // BNB Chain Testnet
  bscTestnet: {
    name: "bscTestnet",
    displayName: "BNB Chain Testnet",
    chainId: 97,
    isTestnet: true,
    nativeCurrency: {
      name: "BNB",
      symbol: "BNB",
      decimals: 18,
    },
    blockTime: 3,
    gasPrice: {
      min: parseEther("0.00000001"), // 10 gwei
      max: parseEther("0.00002"), // 20 gwei
    },
    deploymentConfig: {
      escrowFeePercent: 200, // 2%
      disputeFeePercent: 80, // 0.8%
      minFee: parseEther("0.001"),
      maxFee: parseEther("5.0"),
      minTimeout: 3600,
      maxTimeout: 2592000,
    },
    wethAddress: "0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd", // WBNB
    stargateRouter: "0xbB0f1be1E9CE9cB27EA69b2055f81e7776A0d7bE",
  },

  // Arbitrum Mainnet
  arbitrum: {
    name: "arbitrum",
    displayName: "Arbitrum Mainnet",
    chainId: 42161,
    isTestnet: false,
    nativeCurrency: {
      name: "Ether",
      symbol: "ETH",
      decimals: 18,
    },
    blockTime: 0.25, // 0.25 seconds (250ms)
    gasPrice: {
      min: parseEther("0.0000000001"), // 0.1 gwei
      max: parseEther("0.0000001"), // 0.1 gwei (Arbitrum has fixed gas)
    },
    deploymentConfig: {
      escrowFeePercent: 200, // 2% (lower due to cheaper L2 gas)
      disputeFeePercent: 80, // 0.8%
      minFee: parseEther("0.0001"), // Lower min fee due to cheap gas
      maxFee: parseEther("0.5"),
      minTimeout: 3600,
      maxTimeout: 2592000,
    },
    stargateRouter: "0x53Bf833A5d6c4ddA888F69c22C88C9f356a41614",
  },

  // Arbitrum Sepolia Testnet
  arbitrumSepolia: {
    name: "arbitrumSepolia",
    displayName: "Arbitrum Sepolia",
    chainId: 421614,
    isTestnet: true,
    nativeCurrency: {
      name: "Ether",
      symbol: "ETH",
      decimals: 18,
    },
    blockTime: 0.25,
    gasPrice: {
      min: parseEther("0.0000000001"), // 0.1 gwei
      max: parseEther("0.0000001"), // 0.1 gwei
    },
    deploymentConfig: {
      escrowFeePercent: 200, // 2%
      disputeFeePercent: 80, // 0.8%
      minFee: parseEther("0.0001"),
      maxFee: parseEther("0.5"),
      minTimeout: 3600,
      maxTimeout: 2592000,
    },
    stargateRouter: "0x6EDCE65403992e310A62460808c4b910D972f10f",
  },

  // Base Mainnet
  base: {
    name: "base",
    displayName: "Base Mainnet",
    chainId: 8453,
    isTestnet: false,
    nativeCurrency: {
      name: "Ether",
      symbol: "ETH",
      decimals: 18,
    },
    blockTime: 2,
    gasPrice: {
      min: parseEther("0.0000000007"), // 0.7 gwei
      max: parseEther("0.00000001"), // 10 gwei
    },
    deploymentConfig: {
      escrowFeePercent: 200, // 2%
      disputeFeePercent: 80, // 0.8%
      minFee: parseEther("0.0001"),
      maxFee: parseEther("0.5"),
      minTimeout: 3600,
      maxTimeout: 2592000,
    },
    stargateRouter: "0x45f1A95A4D3f3836523F5c83673c797f4d4d2631",
  },

  // Base Sepolia Testnet
  baseSepolia: {
    name: "baseSepolia",
    displayName: "Base Sepolia",
    chainId: 84532,
    isTestnet: true,
    nativeCurrency: {
      name: "Ether",
      symbol: "ETH",
      decimals: 18,
    },
    blockTime: 2,
    gasPrice: {
      min: parseEther("0.0000000007"), // 0.7 gwei
      max: parseEther("0.00000001"), // 10 gwei
    },
    deploymentConfig: {
      escrowFeePercent: 200, // 2%
      disputeFeePercent: 80, // 0.8%
      minFee: parseEther("0.0001"),
      maxFee: parseEther("0.5"),
      minTimeout: 3600,
      maxTimeout: 2592000,
    },
    stargateRouter: "0xD5d4805b0b575fBf6a55E7e1b4D4a6C0E8A4f1e9", // Placeholder - may need update
  },

  // Celo Mainnet
  celo: {
    name: "celo",
    displayName: "Celo Mainnet",
    chainId: 42220,
    isTestnet: false,
    nativeCurrency: {
      name: "CELO",
      symbol: "CELO",
      decimals: 18,
    },
    blockTime: 5,
    gasPrice: {
      min: parseEther("0.0000000005"), // 0.5 gwei
      max: parseEther("0.00000002"), // 20 gwei
    },
    deploymentConfig: {
      escrowFeePercent: 300, // 3% (higher due to CELO volatility)
      disputeFeePercent: 150, // 1.5%
      minFee: parseEther("0.01"),
      maxFee: parseEther("5.0"),
      minTimeout: 3600,
      maxTimeout: 2592000,
    },
    wethAddress: "0x471EcE3750Da237f93B8E339c536989b8978a438", // WCELO
    stargateRouter: "0x45A01E4e04F14f7A4a6702c74187c5F622203379", // Placeholder - may need update
  },

  // Celo Alfajores Testnet
  celoAlfajores: {
    name: "celoAlfajores",
    displayName: "Celo Alfajores",
    chainId: 44787,
    isTestnet: true,
    nativeCurrency: {
      name: "CELO",
      symbol: "CELO",
      decimals: 18,
    },
    blockTime: 5,
    gasPrice: {
      min: parseEther("0.0000000005"), // 0.5 gwei
      max: parseEther("0.00000002"), // 20 gwei
    },
    deploymentConfig: {
      escrowFeePercent: 300, // 3%
      disputeFeePercent: 150, // 1.5%
      minFee: parseEther("0.01"),
      maxFee: parseEther("5.0"),
      minTimeout: 3600,
      maxTimeout: 2592000,
    },
    wethAddress: "0xF194afDf50B03e69Bd7D057c1Aa9e10c9954E4C9", // WCELO
    stargateRouter: "0x6EDCE65403992e310A62460808c4b910D972f10f", // Placeholder - may need update
  },
};

/**
 * Get network configuration for a specific network
 */
export function getNetworkConfig(network: string): NetworkConfig {
  const config = NETWORK_CONFIGS[network];
  if (!config) {
    throw new Error(`Network configuration not found for: ${network}`);
  }
  return config;
}

/**
 * Get all supported networks
 */
export function getSupportedNetworks(): string[] {
  return Object.keys(NETWORK_CONFIGS);
}

/**
 * Check if a network is a testnet
 */
export function isTestnet(network: string): boolean {
  return NETWORK_CONFIGS[network]?.isTestnet || false;
}

/**
 * Get deployment configuration for a network
 */
export function getDeploymentConfig(network: string) {
  return getNetworkConfig(network).deploymentConfig;
}
