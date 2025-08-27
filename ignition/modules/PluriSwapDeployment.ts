import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { parseEther, encodeAbiParameters } from "viem";

/**
 * Complete PluriSwap System Deployment Module
 * 
 * Deploys all contracts in the correct order with proper configuration:
 * 1. ReputationOracle
 * 2. ReputationIngestion  
 * 3. MockStargateRouter (for testing)
 * 4. ArbitrationProxy
 * 5. EscrowContract
 * 6. Sets up inter-contract connections
 */
export default buildModule("PluriSwapDeployment", (m) => {
  // Deployment account (will be the DAO/owner initially)
  const deployer = m.getAccount(0);

  console.log("🚀 Starting PluriSwap System Deployment...");
  console.log(`📋 Deployer account: ${deployer}`);

  // ========================================================================
  // STEP 1: Deploy Core Infrastructure
  // ========================================================================
  
  console.log("📊 Deploying ReputationOracle...");
  const reputationOracle = m.contract("ReputationOracle", [deployer]);

  console.log("📥 Deploying ReputationIngestion...");
  const reputationIngestion = m.contract("ReputationIngestion", [deployer]);

  console.log("🌉 Deploying MockStargateRouter (for testing)...");
  const mockStargateRouter = m.contract("MockStargateRouter", []);

  // ========================================================================
  // STEP 2: Deploy Arbitration System
  // ========================================================================

  console.log("⚖️ Configuring ArbitrationProxy...");
  
  // ArbitrationProxy configuration
  const arbitrationConfig = encodeAbiParameters(
    [
      { type: 'bool', name: 'paused' },
      { type: 'address', name: 'feeRecipient' }, 
      { type: 'uint256', name: 'baseFee' }
    ],
    [
      false,                    // Not paused initially
      deployer,                 // Fee recipient (DAO)
      parseEther("0.01")       // 0.01 ETH base fee
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
  
  // EscrowContract configuration
  const escrowConfig = encodeAbiParameters(
    [
      { type: 'uint256', name: 'baseFeePercent' },      // 2.5% = 250 basis points
      { type: 'uint256', name: 'minFee' },              // 0.001 ETH minimum
      { type: 'uint256', name: 'maxFee' },              // 1 ETH maximum  
      { type: 'uint256', name: 'disputeFeePercent' },   // 1% = 100 basis points
      { type: 'uint256', name: 'minTimeout' },          // 1 hour minimum
      { type: 'uint256', name: 'maxTimeout' },          // 30 days maximum
      { type: 'address', name: 'feeRecipient' },        // Fee recipient
    ],
    [
      250n,                           // 2.5% base fee
      parseEther("0.001"),           // 0.001 ETH min fee
      parseEther("1.0"),             // 1 ETH max fee
      100n,                          // 1% dispute fee
      3600n,                         // 1 hour min timeout
      BigInt(30 * 24 * 3600),       // 30 days max timeout
      deployer                       // Fee recipient (DAO)
    ]
  );

  console.log("💰 Deploying EscrowContract...");
  const escrowContract = m.contract("EscrowContract", [
    deployer,               // Owner/DAO
    reputationOracle,       // Reputation oracle
    reputationIngestion,    // Reputation events
    mockStargateRouter,     // Stargate router (mock)
    escrowConfig           // Configuration
  ]);

  // ========================================================================
  // STEP 4: Deploy DAO Governance (Optional - can use EOA for testnet)
  // ========================================================================

  console.log("🏛️ Deploying PluriSwapDAO...");
  
  // For testnet, we can use 3 signers with 2/3 threshold
  // In production, you'd want 5 real multisig signers
  const signer1 = deployer;  // Primary deployer
  const signer2 = deployer;  // For testnet, can be same as deployer
  const signer3 = deployer;  // For testnet, can be same as deployer
  const signer4 = deployer;  // For testnet, can be same as deployer
  const signer5 = deployer;  // For testnet, can be same as deployer

  const pluriSwapDAO = m.contract("PluriSwapDAO", [
    [signer1, signer2, signer3, signer4, signer5],  // Signers
    3n,                                              // Required signatures (3/5)
    BigInt(2 * 24 * 3600),                         // 2 day timelock
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

  // Add initial support agent (deployer for testnet)
  m.call(arbitrationProxy, "addSupportAgent", [deployer, "Testnet Admin"], {
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

  console.log("✅ PluriSwap deployment complete!");
  
  return {
    // Core contracts
    escrowContract,
    arbitrationProxy,
    reputationOracle,
    reputationIngestion,
    pluriSwapDAO,
    
    // Infrastructure
    mockStargateRouter,
    abiHelper,
    
    // Deployment info
    deployer
  };
});
