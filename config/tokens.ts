/**
 * PluriSwap Token Configuration
 *
 * This file contains the contract addresses for all supported tokens
 * across all supported blockchain networks.
 */

export interface TokenConfig {
  symbol: string;
  name: string;
  decimals: number;
  addresses: {
    [network: string]: `0x${string}`;
  };
}

export const SUPPORTED_TOKENS: TokenConfig[] = [
  {
    symbol: "USDT",
    name: "Tether USD",
    decimals: 6,
    addresses: {
      // Ethereum Mainnet
      mainnet: "0xdAC17F958D2ee523a2206206994597C13D831ec7",

      // Ethereum Sepolia (Testnet)
      sepolia: "0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0",

      // Polygon Mainnet
      polygon: "0xc2132D05D31c914a87C6611C10748AEb04B58e8F",

      // Polygon Amoy (Testnet)
      polygonAmoy: "0xc2C3eAbE036E2E02c02d4f443C8C7c0f6A0b8c4E", // USDT on Amoy

      // BNB Chain Mainnet
      bsc: "0x55d398326f99059fF775485246999027B3197955",

      // BNB Chain Testnet
      bscTestnet: "0x337610d27c682E347C9cD60BD4b3b107C9d34dDd",

      // Arbitrum Mainnet
      arbitrum: "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9",

      // Arbitrum Sepolia (Testnet)
      arbitrumSepolia: "0xf705ddCF35b8c24bb4ee4B64CA5f3b2a2f3a6b6d",

      // Base Mainnet
      base: "0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2",

      // Base Sepolia (Testnet)
      baseSepolia: "0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2", // Same as mainnet for now

      // Celo Mainnet
      celo: "0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e",

      // Celo Alfajores (Testnet)
      celoAlfajores: "0x874069Fa1Eb16D44d622F2e0Ca25eeA172369bC1",
    },
  },
  {
    symbol: "USDC",
    name: "USD Coin",
    decimals: 6,
    addresses: {
      // Ethereum Mainnet
      mainnet: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",

      // Ethereum Sepolia (Testnet)
      sepolia: "0x8267cF9254734C6Eb452a7bb9AAF97B392258b21",

      // Polygon Mainnet
      polygon: "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",

      // Polygon Amoy (Testnet)
      polygonAmoy: "0x41E94Eb019C0762f9Bfcf9Fb1E58725BfB0e7582", // USDC on Amoy

      // BNB Chain Mainnet
      bsc: "0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d",

      // BNB Chain Testnet
      bscTestnet: "0x64544969ed7DBF0B8cf1E6A0d1F2D053c6B6B524",

      // Arbitrum Mainnet
      arbitrum: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",

      // Arbitrum Sepolia (Testnet)
      arbitrumSepolia: "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d",

      // Base Mainnet
      base: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",

      // Base Sepolia (Testnet)
      baseSepolia: "0x036CbD53842c5426634e7929541eC231BcE1e359",

      // Celo Mainnet
      celo: "0x37f750B7cC259A2f741AF45294f6a16572CF5cAd",

      // Celo Alfajores (Testnet)
      celoAlfajores: "0x2F25deB3848C207fc8E0c34035B3Ba7fC157602B",
    },
  },
  {
    symbol: "WBTC",
    name: "Wrapped Bitcoin",
    decimals: 8,
    addresses: {
      // Ethereum Mainnet
      mainnet: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",

      // Ethereum Sepolia (Testnet)
      sepolia: "0x592C5b8b6c4d6A2f8d3B8f4C8E9D8F2A1B6C7D5E", // Placeholder - may need to be updated

      // Polygon Mainnet
      polygon: "0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6",

      // Polygon Amoy (Testnet)
      polygonAmoy: "0x526f0A95EDC3DF4CBDB7BB6136B30F7C0F8F1b4B", // WBTC on Amoy

      // BNB Chain Mainnet
      bsc: "0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c",

      // BNB Chain Testnet
      bscTestnet: "0x2AaFc0aD5581c3a8C7f2299f8F4b7f8e3f0c2bF2", // Placeholder

      // Arbitrum Mainnet
      arbitrum: "0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f",

      // Arbitrum Sepolia (Testnet)
      arbitrumSepolia: "0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f", // Same as mainnet

      // Base Mainnet
      base: "0x0555E30da8f98308EdB960aa94C0Db47230d2B9c",

      // Base Sepolia (Testnet)
      baseSepolia: "0x0555E30da8f98308EdB960aa94C0Db47230d2B9c", // Same as mainnet

      // Celo Mainnet
      celo: "0xBe50a3013A1c94768A1ABb78c3cB79AB28fc1aCE",

      // Celo Alfajores (Testnet)
      celoAlfajores: "0xBe50a3013A1c94768A1ABb78c3cB79AB28fc1aCE", // Same as mainnet
    },
  },
  {
    symbol: "DAI",
    name: "Dai Stablecoin",
    decimals: 18,
    addresses: {
      // Ethereum Mainnet
      mainnet: "0x6B175474E89094C44Da98b954EedeAC495271d0F",

      // Ethereum Sepolia (Testnet)
      sepolia: "0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357",

      // Polygon Mainnet
      polygon: "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063",

      // Polygon Amoy (Testnet)
      polygonAmoy: "0x88541670E55cC00bEEFD87eB2F99f9591c17BC5C", // DAI on Amoy

      // BNB Chain Mainnet
      bsc: "0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3",

      // BNB Chain Testnet
      bscTestnet: "0x337610d27c682E347C9cD60BD4b3b107C9d34dDd", // Same as USDT testnet

      // Arbitrum Mainnet
      arbitrum: "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1",

      // Arbitrum Sepolia (Testnet)
      arbitrumSepolia: "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1", // Same as mainnet

      // Base Mainnet
      base: "0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb",

      // Base Sepolia (Testnet)
      baseSepolia: "0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb", // Same as mainnet

      // Celo Mainnet
      celo: "0x90Ca507a5D4458a4C6C6249d186b6dCb02a5BCCd",

      // Celo Alfajores (Testnet)
      celoAlfajores: "0x90Ca507a5D4458a4C6C6249d186b6dCb02a5BCCd", // Same as mainnet
    },
  },
  {
    symbol: "ETH",
    name: "Ethereum",
    decimals: 18,
    addresses: {
      // Native ETH on all networks - use zero address to indicate native token
      mainnet: "0x0000000000000000000000000000000000000000",
      sepolia: "0x0000000000000000000000000000000000000000",
      polygon: "0x0000000000000000000000000000000000000000",
      polygonAmoy: "0x0000000000000000000000000000000000000000",
      bsc: "0x0000000000000000000000000000000000000000",
      bscTestnet: "0x0000000000000000000000000000000000000000",
      arbitrum: "0x0000000000000000000000000000000000000000",
      arbitrumSepolia: "0x0000000000000000000000000000000000000000",
      base: "0x0000000000000000000000000000000000000000",
      baseSepolia: "0x0000000000000000000000000000000000000000",
      celo: "0x0000000000000000000000000000000000000000",
      celoAlfajores: "0x0000000000000000000000000000000000000000",
    },
  },
];

/**
 * Get token address for a specific network
 */
export function getTokenAddress(symbol: string, network: string): `0x${string}` | null {
  const token = SUPPORTED_TOKENS.find(t => t.symbol === symbol);
  if (!token) return null;

  return token.addresses[network] || null;
}

/**
 * Get all supported tokens for a network
 */
export function getSupportedTokensForNetwork(network: string): Array<{ symbol: string; address: `0x${string}`; decimals: number }> {
  return SUPPORTED_TOKENS
    .filter(token => token.addresses[network])
    .map(token => ({
      symbol: token.symbol,
      address: token.addresses[network],
      decimals: token.decimals,
    }));
}

/**
 * Check if a token is supported on a network
 */
export function isTokenSupported(symbol: string, network: string): boolean {
  const address = getTokenAddress(symbol, network);
  return address !== null;
}

/**
 * Get token decimals
 */
export function getTokenDecimals(symbol: string): number {
  const token = SUPPORTED_TOKENS.find(t => t.symbol === symbol);
  return token?.decimals || 18; // Default to 18 for unknown tokens
}

/**
 * Get all supported networks
 */
export function getSupportedNetworks(): string[] {
  return [
    "mainnet",
    "sepolia",
    "polygon",
    "polygonAmoy",
    "bsc",
    "bscTestnet",
    "arbitrum",
    "arbitrumSepolia",
    "base",
    "baseSepolia",
    "celo",
    "celoAlfajores",
  ];
}

/**
 * Get network display name
 */
export function getNetworkDisplayName(network: string): string {
  const networkNames: { [key: string]: string } = {
    mainnet: "Ethereum Mainnet",
    sepolia: "Ethereum Sepolia",
    polygon: "Polygon Mainnet",
    polygonAmoy: "Polygon Amoy",
    bsc: "BNB Chain Mainnet",
    bscTestnet: "BNB Chain Testnet",
    arbitrum: "Arbitrum Mainnet",
    arbitrumSepolia: "Arbitrum Sepolia",
    base: "Base Mainnet",
    baseSepolia: "Base Sepolia",
    celo: "Celo Mainnet",
    celoAlfajores: "Celo Alfajores",
  };

  return networkNames[network] || network;
}
