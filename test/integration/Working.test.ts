import { test, describe } from "node:test";
import assert from "node:assert";
import { network } from "hardhat";
import { parseEther, encodeAbiParameters } from "viem";

describe("Working Integration Tests", () => {
  test("should deploy all contracts successfully", async () => {
    const { viem } = await network.connect();
    
    // Get test accounts
    const [deployer, signer1, signer2, signer3, signer4, buyer, seller] = await viem.getWalletClients();
    
    console.log("Deploying contracts...");
    
    // 1. Deploy DAO with 5 signers as required by contract
    const daoSigners = [
      deployer.account.address,
      signer1.account.address, 
      signer2.account.address,
      signer3.account.address,
      signer4.account.address,
    ];
    const dao = await viem.deployContract("PluriSwapDAO", [daoSigners]);
    assert(dao.address, "DAO should be deployed");
    console.log("✅ DAO deployed:", dao.address);
    
    // 2. Deploy ReputationOracle
    const reputationOracle = await viem.deployContract("ReputationOracle", [dao.address]);
    assert(reputationOracle.address, "ReputationOracle should be deployed");
    console.log("✅ ReputationOracle deployed:", reputationOracle.address);
    
    // 3. Deploy ReputationIngestion
    const reputationEvents = await viem.deployContract("ReputationIngestion", [dao.address]);
    assert(reputationEvents.address, "ReputationIngestion should be deployed");
    console.log("✅ ReputationIngestion deployed:", reputationEvents.address);
    
    // 4. Deploy MockStargateRouter
    const mockStargateRouter = await viem.deployContract("MockStargateRouter", []);
    assert(mockStargateRouter.address, "MockStargateRouter should be deployed");
    console.log("✅ MockStargateRouter deployed:", mockStargateRouter.address);
    
    // 5. Deploy ArbitrationProxy
    const arbitrationConfig = encodeAbiParameters(
      [
        { type: 'bool', name: 'paused' },
        { type: 'address', name: 'feeRecipient' },
        { type: 'uint256', name: 'baseFee' },
      ],
      [
        false, // not paused
        dao.address, // fee recipient
        parseEther("0.01"), // base fee
      ]
    );
    
    const arbitrationProxy = await viem.deployContract("ArbitrationProxy", [
      dao.address,
      reputationOracle.address,
      arbitrationConfig,
    ]);
    assert(arbitrationProxy.address, "ArbitrationProxy should be deployed");
    console.log("✅ ArbitrationProxy deployed:", arbitrationProxy.address);
    
    console.log("\n🎉 All contracts deployed successfully!");
  });

  test("should verify contract basic functionality", async () => {
    const { viem } = await network.connect();
    
    const [deployer, signer1, signer2, signer3, signer4] = await viem.getWalletClients();
    
    // Deploy DAO
    const daoSigners = [
      deployer.account.address,
      signer1.account.address, 
      signer2.account.address,
      signer3.account.address,
      signer4.account.address,
    ];
    const dao = await viem.deployContract("PluriSwapDAO", [daoSigners]);
    
    // Deploy ReputationOracle
    const reputationOracle = await viem.deployContract("ReputationOracle", [dao.address]);
    
    // Test basic functionality
    const isPaused = await dao.read.paused();
    assert(isPaused === false, "DAO should not be paused initially");
    
    const oraclePaused = await reputationOracle.read.paused();
    assert(oraclePaused === false, "Oracle should not be paused initially");
    
    console.log("✅ Basic contract functionality verified");
  });

  test("should deploy MockStargateRouter and verify functionality", async () => {
    const { viem } = await network.connect();
    
    const mockStargateRouter = await viem.deployContract("MockStargateRouter", []);
    
    // Test basic router functionality
    const isChainSupported = await mockStargateRouter.read.isChainSupported([137]); // Polygon
    assert(isChainSupported === true, "Chain 137 (Polygon) should be supported");
    
    const unsupportedChain = await mockStargateRouter.read.isChainSupported([999]);
    assert(unsupportedChain === false, "Chain 999 should not be supported");
    
    console.log("✅ MockStargateRouter functionality verified");
  });
});
