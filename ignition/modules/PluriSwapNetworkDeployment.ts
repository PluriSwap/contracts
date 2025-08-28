import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { parseEther, encodeAbiParameters } from "viem";
import { getNetworkConfig, getDeploymentConfig } from "../../config/deployment-config";

/**
 * Network-Specific PluriSwap Deployment Module
 *
 * This module deploys PluriSwap contracts with network-specific configurations.
 * Use this for deploying to different networks with optimized parameters.
 *
 * @param network - The network name (e.g., 'polygon', 'bsc', 'arbitrum')
 */
export default function createPluriSwapDeployment(network: string) {
  return buildModule(`PluriSwap${network.charAt(0).toUpperCase() + network.slice(1)}Deployment`, (m) => {
    // Get network-specific configuration
    const networkConfig = getNetworkConfig(network);
    const deploymentConfig = getDeploymentConfig(network);

    console.log(`🚀 Starting PluriSwap Deployment on ${networkConfig.displayName}...`);
    console.log(`📋 Network: ${networkConfig.name} (Chain ID: ${networkConfig.chainId})`);
    console.log(`⛽ Gas Price Range: ${networkConfig.gasPrice.min} - ${networkConfig.gasPrice.max} wei`);
    console.log(`💰 Escrow Fee: ${deploymentConfig.escrowFeePercent / 100}%`);
    console.log(`⚖️ Dispute Fee: ${deploymentConfig.disputeFeePercent / 100}%`);

    // Deployment account (will be the DAO/owner initially)
    const deployer = m.getAccount(0);

    console.log(`👤 Deployer account: ${deployer}`);

    // ========================================================================
    // STEP 1: Deploy Core Infrastructure
    // ========================================================================

    console.log("📊 Deploying ReputationOracle...");
    const reputationOracle = m.contract("ReputationOracle", [deployer]);

    console.log("📥 Deploying ReputationIngestion...");
    const reputationIngestion = m.contract("ReputationIngestion", [deployer]);

    // Deploy Stargate Router mock only on testnets or if no real router is available
    let stargateRouter;
    if (networkConfig.stargateRouter) {
      console.log(`🌉 Using Stargate Router: ${networkConfig.stargateRouter}`);
      // In production, we'd use the real Stargate router contract
      // For now, we'll deploy a mock for testing purposes
      stargateRouter = m.contract("MockStargateRouter", []);
    } else {
      console.log("🌉 Deploying MockStargateRouter (cross-chain not available on this network)...");
      stargateRouter = m.contract("MockStargateRouter", []);
    }

    // ========================================================================
    // STEP 2: Deploy Arbitration System
    // ========================================================================

    console.log("⚖️ Configuring ArbitrationProxy...");

    // ArbitrationProxy configuration - network-specific fees
    const arbitrationConfig = encodeAbiParameters(
      [
        { type: 'bool', name: 'paused' },
        { type: 'address', name: 'feeRecipient' },
        { type: 'uint256', name: 'baseFee' }
      ],
      [
        false,                    // Not paused initially
        deployer,                 // Fee recipient (DAO)
        deploymentConfig.minFee   // Network-specific minimum fee
      ]
    );

    console.log("⚖️ Deploying ArbitrationProxy...");
    const arbitrationProxy = m.contract("ArbitrationProxy", [
      deployer,              // Owner/DAO
      reputationOracle,      // Reputation oracle
      arbitrationConfig      // Configuration
    ]);

    // ========================================================================
    // STEP 3: Deploy Main Escrow System
    // ========================================================================

    console.log("💰 Configuring EscrowContract...");

    // EscrowContract configuration - network-specific parameters
    const escrowConfig = encodeAbiParameters(
      [
        { type: 'uint256', name: 'baseFeePercent' },      // Escrow fee percentage
        { type: 'uint256', name: 'minFee' },              // Minimum fee
        { type: 'uint256', name: 'maxFee' },              // Maximum fee
        { type: 'uint256', name: 'disputeFeePercent' },   // Dispute fee percentage
        { type: 'uint256', name: 'minTimeout' },          // Minimum timeout
        { type: 'uint256', name: 'maxTimeout' },          // Maximum timeout
        { type: 'address', name: 'feeRecipient' },        // Fee recipient
      ],
      [
        BigInt(deploymentConfig.escrowFeePercent),     // Network-specific escrow fee
        deploymentConfig.minFee,                        // Network-specific minimum fee
        deploymentConfig.maxFee,                        // Network-specific maximum fee
        BigInt(deploymentConfig.disputeFeePercent),     // Network-specific dispute fee
        BigInt(deploymentConfig.minTimeout),            // Network-specific minimum timeout
        BigInt(deploymentConfig.maxTimeout),            // Network-specific maximum timeout
        deployer                                        // Fee recipient (DAO)
      ]
    );

    console.log("💰 Deploying EscrowContract...");
    const escrowContract = m.contract("EscrowContract", [
      deployer,               // Owner/DAO
      reputationOracle,       // Reputation oracle
      reputationIngestion,    // Reputation events
      stargateRouter,         // Stargate router (mock or real)
      escrowConfig           // Network-specific configuration
    ]);

    // ========================================================================
    // STEP 4: Deploy DAO Governance
    // ========================================================================

    console.log("🏛️ Deploying PluriSwapDAO...");

    // For production deployments, you would use real multisig signers
    // For testnet deployments, we can use placeholder signers
    const signer1 = deployer;  // Primary deployer
    const signer2 = deployer;  // For testnet, can be same as deployer
    const signer3 = deployer;  // For testnet, can be same as deployer
    const signer4 = deployer;  // For testnet, can be same as deployer
    const signer5 = deployer;  // For testnet, can be same as deployer

    const pluriSwapDAO = m.contract("PluriSwapDAO", [
      [signer1, signer2, signer3, signer4, signer5],  // Signers
      3n,                                              // Required signatures (3/5)
      BigInt(networkConfig.isTestnet ? 2 * 24 * 3600 : 7 * 24 * 3600), // Shorter timelock for testnets
    ]);

    // ========================================================================
    // STEP 5: Set Up Inter-Contract Connections
    // ========================================================================

    console.log("🔗 Setting up contract connections...");

    // Connect EscrowContract to ArbitrationProxy
    m.call(escrowContract, "setArbitrationProxy", [arbitrationProxy], {
      from: deployer,
      id: "setArbitrationProxy"
    });

    // Authorize EscrowContract in ArbitrationProxy
    m.call(arbitrationProxy, "addAuthorizedContract", [escrowContract], {
      from: deployer,
      id: "authorizeEscrowContract"
    });

    // Add initial support agent (deployer for initial setup)
    m.call(arbitrationProxy, "addSupportAgent", [deployer, `${networkConfig.displayName} Admin`], {
      from: deployer,
      id: "addInitialSupportAgent"
    });

    // ========================================================================
    // STEP 6: Deploy Helper Contracts
    // ========================================================================

    console.log("🔧 Deploying ABI helper for testing...");
    const abiHelper = m.contract("AbiEncodingTest", []);

    // ========================================================================
    // Return all deployed contracts
    // ========================================================================

    console.log(`✅ PluriSwap deployment on ${networkConfig.displayName} complete!`);

    return {
      // Core contracts
      escrowContract,
      arbitrationProxy,
      reputationOracle,
      reputationIngestion,
      pluriSwapDAO,

      // Infrastructure
      stargateRouter,
      abiHelper,

      // Deployment info
      deployer,
      network: networkConfig.name,
      networkConfig
    };
  });
}

// Export network-specific deployment modules
export const PluriSwapPolygonDeployment = createPluriSwapDeployment("polygon");
export const PluriSwapBscDeployment = createPluriSwapDeployment("bsc");
export const PluriSwapArbitrumDeployment = createPluriSwapDeployment("arbitrum");
export const PluriSwapBaseDeployment = createPluriSwapDeployment("base");
export const PluriSwapCeloDeployment = createPluriSwapDeployment("celo");
export const PluriSwapMainnetDeployment = createPluriSwapDeployment("mainnet");

// Testnet deployments
export const PluriSwapPolygonAmoyDeployment = createPluriSwapDeployment("polygonAmoy");
export const PluriSwapBscTestnetDeployment = createPluriSwapDeployment("bscTestnet");
export const PluriSwapArbitrumSepoliaDeployment = createPluriSwapDeployment("arbitrumSepolia");
export const PluriSwapBaseSepoliaDeployment = createPluriSwapDeployment("baseSepolia");
export const PluriSwapCeloAlfajoresDeployment = createPluriSwapDeployment("celoAlfajores");
export const PluriSwapSepoliaDeployment = createPluriSwapDeployment("sepolia");
