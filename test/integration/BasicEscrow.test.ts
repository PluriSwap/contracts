import { test, describe } from "node:test";
import assert from "node:assert";
import { network } from "hardhat";
import { parseEther, encodeAbiParameters } from "viem";

describe("Basic Escrow Contract Deployment", () => {
  test("should deploy all required contracts successfully", async () => {
    const { viem } = await network.connect();
    
    // Get test accounts
    const [deployer, signer1, signer2, signer3, signer4] = await viem.getWalletClients();
    
    console.log("Deploying PluriSwap contract system...");
    
    // 1. Deploy DAO with 5 signers as required
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
    
    // 5. Deploy EscrowContract with proper configuration
    const escrowConfig = encodeAbiParameters(
      [
        { type: 'uint256', name: 'baseFeePercent' },
        { type: 'uint256', name: 'minFee' },
        { type: 'uint256', name: 'maxFee' },
        { type: 'uint256', name: 'disputeFeePercent' },
        { type: 'uint256', name: 'minTimeout' },
        { type: 'uint256', name: 'maxTimeout' },
        { type: 'address', name: 'feeRecipient' },
      ],
      [
        500n, // 5% base fee in basis points
        parseEther("0.001"), // min fee
        parseEther("1"), // max fee
        100n, // 1% dispute fee in basis points
        3600n, // 1 hour min timeout
        BigInt(30 * 24 * 3600), // 30 days max timeout
        dao.address, // fee recipient
      ]
    );
    
    const escrowContract = await viem.deployContract("EscrowContract", [
      dao.address,
      reputationOracle.address,
      reputationEvents.address,
      mockStargateRouter.address,
      escrowConfig,
    ]);
    assert(escrowContract.address, "EscrowContract should be deployed");
    console.log("✅ EscrowContract deployed:", escrowContract.address);
    
    console.log("\n🎉 All core contracts deployed successfully!");
    console.log("PluriSwap system ready for escrow operations.");
    
    // Verify basic contract functionality
    const escrowCounter = await escrowContract.read.escrowCounter();
    assert(escrowCounter === 0n, "Initial escrow counter should be 0");
    console.log("✅ EscrowContract counter initialized correctly:", escrowCounter.toString());
    
    console.log("\n✅ Basic escrow deployment test completed successfully!");
  });
});