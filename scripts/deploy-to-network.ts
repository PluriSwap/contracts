/**
 * Multi-Network Deployment Script
 *
 * This script deploys PluriSwap contracts to any supported network
 * with network-specific optimizations and configurations.
 */

import { network } from "hardhat";
import { getNetworkConfig, getSupportedNetworks } from "../config/deployment-config";
import { getSupportedTokensForNetwork } from "../config/tokens";

interface DeploymentResult {
  network: string;
  contracts: {
    escrowContract: string;
    arbitrationProxy: string;
    reputationOracle: string;
    reputationIngestion: string;
    pluriSwapDAO: string;
    stargateRouter: string;
  };
  timestamp: number;
  deployer: string;
}

/**
 * Deploy PluriSwap to a specific network
 */
async function deployToNetwork(targetNetwork: string): Promise<DeploymentResult> {
  console.log(`🚀 Starting deployment to ${targetNetwork}...\n`);

  // Validate network
  const supportedNetworks = getSupportedNetworks();
  if (!supportedNetworks.includes(targetNetwork)) {
    throw new Error(`Network '${targetNetwork}' is not supported. Supported networks: ${supportedNetworks.join(', ')}`);
  }

  // Check if we're on the correct network
  if (network.name !== targetNetwork) {
    throw new Error(`Please run this script on the '${targetNetwork}' network. Current network: ${network.name}`);
  }

  const networkConfig = getNetworkConfig(targetNetwork);
  const supportedTokens = getSupportedTokensForNetwork(targetNetwork);

  console.log(`📋 Network Details:`);
  console.log(`   Name: ${networkConfig.displayName}`);
  console.log(`   Chain ID: ${networkConfig.chainId}`);
  console.log(`   Testnet: ${networkConfig.isTestnet ? 'Yes' : 'No'}`);
  console.log(`   Native Currency: ${networkConfig.nativeCurrency.symbol}`);
  console.log(`   Supported Tokens: ${supportedTokens.map(t => t.symbol).join(', ')}\n`);

  try {
    // Import the network-specific deployment module
    const deploymentModule = await import(`../ignition/modules/PluriSwapNetworkDeployment`);

    let deploymentFunction;
    switch (targetNetwork) {
      case 'polygon':
        deploymentFunction = deploymentModule.PluriSwapPolygonDeployment;
        break;
      case 'bsc':
        deploymentFunction = deploymentModule.PluriSwapBscDeployment;
        break;
      case 'arbitrum':
        deploymentFunction = deploymentModule.PluriSwapArbitrumDeployment;
        break;
      case 'base':
        deploymentFunction = deploymentModule.PluriSwapBaseDeployment;
        break;
      case 'celo':
        deploymentFunction = deploymentModule.PluriSwapCeloDeployment;
        break;
      case 'mainnet':
        deploymentFunction = deploymentModule.PluriSwapMainnetDeployment;
        break;
      case 'polygonAmoy':
        deploymentFunction = deploymentModule.PluriSwapPolygonAmoyDeployment;
        break;
      case 'bscTestnet':
        deploymentFunction = deploymentModule.PluriSwapBscTestnetDeployment;
        break;
      case 'arbitrumSepolia':
        deploymentFunction = deploymentModule.PluriSwapArbitrumSepoliaDeployment;
        break;
      case 'baseSepolia':
        deploymentFunction = deploymentModule.PluriSwapBaseSepoliaDeployment;
        break;
      case 'celoAlfajores':
        deploymentFunction = deploymentModule.PluriSwapCeloAlfajoresDeployment;
        break;
      case 'sepolia':
        deploymentFunction = deploymentModule.PluriSwapSepoliaDeployment;
        break;
      default:
        throw new Error(`No deployment function found for network: ${targetNetwork}`);
    }

    // Execute deployment
    const result = await network.deploy(deploymentFunction);

    // Extract contract addresses
    const contracts = {
      escrowContract: result.escrowContract,
      arbitrationProxy: result.arbitrationProxy,
      reputationOracle: result.reputationOracle,
      reputationIngestion: result.reputationIngestion,
      pluriSwapDAO: result.pluriSwapDAO,
      stargateRouter: result.stargateRouter,
    };

    const deploymentResult: DeploymentResult = {
      network: targetNetwork,
      contracts,
      timestamp: Date.now(),
      deployer: result.deployer,
    };

    console.log(`\n✅ Deployment to ${networkConfig.displayName} successful!`);
    console.log(`📋 Contract Addresses:`);
    Object.entries(contracts).forEach(([name, address]) => {
      console.log(`   ${name}: ${address}`);
    });

    return deploymentResult;

  } catch (error) {
    console.error(`❌ Deployment to ${targetNetwork} failed:`, error);
    throw error;
  }
}

/**
 * Deploy to multiple networks
 */
async function deployToMultipleNetworks(networks: string[]): Promise<DeploymentResult[]> {
  const results: DeploymentResult[] = [];

  for (const targetNetwork of networks) {
    try {
      const result = await deployToNetwork(targetNetwork);
      results.push(result);

      // Add a delay between deployments to avoid rate limiting
      if (networks.indexOf(targetNetwork) < networks.length - 1) {
        console.log(`⏳ Waiting 10 seconds before next deployment...\n`);
        await new Promise(resolve => setTimeout(resolve, 10000));
      }
    } catch (error) {
      console.error(`❌ Failed to deploy to ${targetNetwork}:`, error);
      // Continue with other networks
    }
  }

  return results;
}

/**
 * Main deployment function
 */
async function main() {
  const args = process.argv.slice(2);

  if (args.length === 0) {
    console.log("Usage:");
    console.log("  npm run deploy:network <network>     - Deploy to specific network");
    console.log("  npm run deploy:multi <network1> <network2> ... - Deploy to multiple networks");
    console.log("  npm run deploy:testnets             - Deploy to all testnets");
    console.log("  npm run deploy:mainnets             - Deploy to all mainnets");
    console.log("\nSupported networks:");
    getSupportedNetworks().forEach(network => {
      const config = getNetworkConfig(network);
      console.log(`  ${network.padEnd(15)} - ${config.displayName} (${config.isTestnet ? 'Testnet' : 'Mainnet'})`);
    });
    return;
  }

  const command = args[0];

  switch (command) {
    case 'testnets':
      const testnets = getSupportedNetworks().filter(n => getNetworkConfig(n).isTestnet);
      console.log(`🚀 Deploying to all testnets: ${testnets.join(', ')}\n`);
      await deployToMultipleNetworks(testnets);
      break;

    case 'mainnets':
      const mainnets = getSupportedNetworks().filter(n => !getNetworkConfig(n).isTestnet);
      console.log(`🚀 Deploying to all mainnets: ${mainnets.join(', ')}\n`);
      await deployToMultipleNetworks(mainnets);
      break;

    default:
      // Single network deployment
      const targetNetwork = command;
      await deployToNetwork(targetNetwork);
      break;
  }
}

// Export functions for programmatic use
export { deployToNetwork, deployToMultipleNetworks, DeploymentResult };

// Run main if script is executed directly
if (require.main === module) {
  main().catch(console.error);
}
