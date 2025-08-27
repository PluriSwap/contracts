/**
 * Deployment Validation Script
 * 
 * This script helps validate that PluriSwap contracts are properly deployed
 * and configured on Sepolia testnet.
 */

import { parseEther, formatEther } from "viem";

const SEPOLIA_DEPLOYED_ADDRESSES = {
  // Update these after deployment
  EscrowContract: "0x0000000000000000000000000000000000000000",
  ArbitrationProxy: "0x0000000000000000000000000000000000000000", 
  ReputationOracle: "0x0000000000000000000000000000000000000000",
  ReputationIngestion: "0x0000000000000000000000000000000000000000",
  PluriSwapDAO: "0x0000000000000000000000000000000000000000",
  MockStargateRouter: "0x0000000000000000000000000000000000000000",
};

/**
 * Validates deployment and contract configuration
 */
async function validateDeployment() {
  console.log("🔍 Validating PluriSwap Sepolia Deployment...\n");

  // Import hardhat runtime (only works when script is run via hardhat)
  const hre = require("hardhat");
  const { network } = hre;

  if (network.name !== "sepolia") {
    console.error("❌ This script should be run on Sepolia network");
    console.log("Run with: npx hardhat run scripts/validate-deployment.ts --network sepolia");
    process.exit(1);
  }

  console.log(`📡 Network: ${network.name}`);
  console.log(`🔗 Chain ID: ${network.config.chainId || 'Unknown'}`);
  
  try {
    // Connect to network using viem
    const { viem } = await network.connect();
    const publicClient = await viem.getPublicClient();
    const [signer] = await viem.getWalletClients();

    console.log(`👤 Validator Account: ${signer.account.address}`);
    
    // Check account balance
    const balance = await publicClient.getBalance({ 
      address: signer.account.address 
    });
    console.log(`💰 Account Balance: ${formatEther(balance)} ETH\n`);

    if (balance < parseEther("0.1")) {
      console.warn("⚠️  Low balance - you may need more testnet ETH\n");
    }

    // Validate each contract
    await validateContract("EscrowContract", SEPOLIA_DEPLOYED_ADDRESSES.EscrowContract, publicClient);
    await validateContract("ArbitrationProxy", SEPOLIA_DEPLOYED_ADDRESSES.ArbitrationProxy, publicClient);
    await validateContract("ReputationOracle", SEPOLIA_DEPLOYED_ADDRESSES.ReputationOracle, publicClient);
    await validateContract("ReputationIngestion", SEPOLIA_DEPLOYED_ADDRESSES.ReputationIngestion, publicClient);
    await validateContract("PluriSwapDAO", SEPOLIA_DEPLOYED_ADDRESSES.PluriSwapDAO, publicClient);
    
    console.log("\n✅ Deployment validation complete!");
    console.log("\n🎯 Next Steps:");
    console.log("1. Update frontend with contract addresses");
    console.log("2. Test basic escrow workflow");
    console.log("3. Set up monitoring and alerts");
    console.log("4. Document contract addresses for team");

  } catch (error) {
    console.error("❌ Validation failed:", error);
    process.exit(1);
  }
}

/**
 * Validates individual contract deployment
 */
async function validateContract(name: string, address: string, publicClient: any) {
  if (address === "0x0000000000000000000000000000000000000000") {
    console.log(`⚠️  ${name}: Address not set - update SEPOLIA_DEPLOYED_ADDRESSES`);
    return;
  }

  try {
    // Check if contract exists
    const code = await publicClient.getBytecode({ address });
    
    if (!code || code === "0x") {
      console.log(`❌ ${name}: No contract found at ${address}`);
      return;
    }

    console.log(`✅ ${name}: Deployed at ${address}`);
    console.log(`   📦 Bytecode size: ${(code.length - 2) / 2} bytes`);

  } catch (error) {
    console.log(`❌ ${name}: Error validating - ${error}`);
  }
}

// Run validation if script is executed directly
if (require.main === module) {
  validateDeployment().catch(console.error);
}

export { validateDeployment, SEPOLIA_DEPLOYED_ADDRESSES };
