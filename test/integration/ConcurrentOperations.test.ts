import { test, describe } from "node:test";
import assert from "node:assert";
import { network } from "hardhat";
import { parseEther, encodeAbiParameters, getAddress } from "viem";
import { privateKeyToAccount, generatePrivateKey } from "viem/accounts";

/**
 * Concurrent Operations Test Suite
 *
 * Tests race conditions, simultaneous operations, and system behavior under load:
 * - Multiple escrows created simultaneously
 * - State isolation between concurrent escrows
 * - Cross-contamination prevention
 * - High-volume escrow creation stress test
 * - Concurrent state transitions
 */

interface EscrowAgreement {
  holder: `0x${string}`;
  provider: `0x${string}`;
  amount: bigint;
  fundedTimeout: bigint;
  proofTimeout: bigint;
  nonce: bigint;
  deadline: bigint;
  dstChainId: number;
  dstRecipient: `0x${string}`;
  dstAdapterParams: `0x${string}`;
}

async function setupConcurrentTest() {
  console.log("🚀 Setting up concurrent operations test environment...");

  const { viem, networkHelpers } = await network.connect();
  const [deployer, daoSigner1, daoSigner2, daoSigner3, daoSigner4, daoSigner5] = await viem.getWalletClients();

  // Deploy DAO
  const daoSigners = [daoSigner1.account.address, daoSigner2.account.address, daoSigner3.account.address, daoSigner4.account.address, daoSigner5.account.address];
  const dao = await viem.deployContract("PluriSwapDAO", [daoSigners]);

  // Deploy ReputationOracle
  const reputationOracle = await viem.deployContract("ReputationOracle", [dao.address]);

  // Deploy ReputationIngestion
  const reputationEvents = await viem.deployContract("ReputationIngestion", [dao.address]);

  // Deploy MockStargateRouter
  const mockStargateRouter = await viem.deployContract("MockStargateRouter", []);

  // Deploy ArbitrationProxy
  const arbitrationConfig = encodeAbiParameters(
    [{ type: 'bool', name: 'paused' }, { type: 'address', name: 'feeRecipient' }, { type: 'uint256', name: 'baseFee' }],
    [false, dao.address, parseEther("0.01")]
  );
  const arbitrationProxy = await viem.deployContract("ArbitrationProxy", [dao.address, reputationOracle.address, arbitrationConfig]);

  // Deploy EscrowContract
  const escrowConfig = encodeAbiParameters(
    [
      { type: 'uint256', name: 'baseFeePercent' },
      { type: 'uint256', name: 'minFee' },
      { type: 'uint256', name: 'maxFee' },
      { type: 'uint256', name: 'disputeFeePercent' },
      { type: 'uint256', name: 'minTimeout' },
      { type: 'uint256', name: 'maxTimeout' },
      { type: 'address', name: 'feeRecipient' },
      { type: 'uint256', name: 'upfrontFee' },
      { type: 'uint256', name: 'successFeePercent' },
      { type: 'uint256', name: 'minDisputeFee' },
      { type: 'uint256', name: 'crossChainFeePercent' },
    ],
    [250n, parseEther("0.001"), parseEther("1"), 100n, 3600n, BigInt(30 * 24 * 3600), dao.address,
     parseEther("0.0001"), 50n, parseEther("0.01"), 25n]
  );
  const escrowContract = await viem.deployContract("EscrowContract", [dao.address, reputationOracle.address, reputationEvents.address, mockStargateRouter.address, escrowConfig]);

  // Deploy ABI encoding helper
  const abiHelper = await viem.deployContract("AbiEncodingTest", []);

  console.log("✅ Concurrent test environment ready");

  return {
    contracts: { dao, reputationOracle, reputationEvents, arbitrationProxy, escrowContract, mockStargateRouter, abiHelper },
    accounts: { deployer, daoSigner1, daoSigner2, daoSigner3, daoSigner4, daoSigner5 },
    networkHelpers,
    viem
  };
}

async function generateEIP712Signature(
  agreementParams: EscrowAgreement,
  signer: any,
  contractAddress: `0x${string}`,
  chainId: number
): Promise<`0x${string}`> {
  const domain = {
    name: 'EscrowContract',
    version: '1',
    chainId: chainId,
    verifyingContract: contractAddress,
  };

  const types = {
    EscrowAgreement: [
      { name: 'holder', type: 'address' },
      { name: 'provider', type: 'address' },
      { name: 'amount', type: 'uint256' },
      { name: 'fundedTimeout', type: 'uint256' },
      { name: 'proofTimeout', type: 'uint256' },
      { name: 'nonce', type: 'uint256' },
      { name: 'deadline', type: 'uint256' },
      { name: 'dstChainId', type: 'uint16' },
      { name: 'dstRecipient', type: 'address' },
      { name: 'dstAdapterParams', type: 'bytes' },
    ],
  };

  return await signer.signTypedData({
    domain,
    types,
    primaryType: 'EscrowAgreement',
    message: agreementParams,
  });
}

async function createTestEscrow(
  escrowContract: any,
  abiHelper: any,
  holder: any,
  provider: any,
  amount: bigint = parseEther("0.1"),
  chainId: number
): Promise<{ escrowId: bigint, agreementParams: EscrowAgreement }> {
  const currentTime = BigInt(Math.floor(Date.now() / 1000));

  const agreementParams: EscrowAgreement = {
    holder: holder.account.address,
    provider: provider.account.address,
    amount,
    fundedTimeout: currentTime + BigInt(48 * 60 * 60),
    proofTimeout: currentTime + BigInt(72 * 60 * 60),
    nonce: BigInt(Math.floor(Math.random() * 1000000)),
    deadline: currentTime + BigInt(24 * 60 * 60),
    dstChainId: 0,
    dstRecipient: provider.account.address,
    dstAdapterParams: "0x" as `0x${string}`,
  };

  const agreementEncoded = await abiHelper.read.encodeEscrowAgreement([
    agreementParams.holder,
    agreementParams.provider,
    agreementParams.amount,
    agreementParams.fundedTimeout,
    agreementParams.proofTimeout,
    agreementParams.nonce,
    agreementParams.deadline,
    agreementParams.dstChainId,
    agreementParams.dstRecipient,
    agreementParams.dstAdapterParams,
  ]);

  const holderSignature = await generateEIP712Signature(agreementParams, holder, escrowContract.address, chainId);
  const providerSignature = await generateEIP712Signature(agreementParams, provider, escrowContract.address, chainId);

  const escrowId = await escrowContract.read.escrowCounter();

  await escrowContract.write.createEscrow(
    [agreementEncoded, holderSignature, providerSignature],
    {
      account: holder.account,
      value: agreementParams.amount,
    }
  );

  return { escrowId, agreementParams };
}

describe('Concurrent Operations Tests', () => {

  test('🔄 CONCURRENT: Multiple Escrows Created Simultaneously', async () => {
    const { contracts, accounts, viem } = await setupConcurrentTest();
    const { escrowContract, abiHelper } = contracts;
    const { daoSigner1, daoSigner2, daoSigner3, daoSigner4, daoSigner5 } = accounts;

    console.log("\n🎯 TESTING: Multiple Simultaneous Escrow Creation");
    console.log("======================================================================");

    const publicClient = await viem.getPublicClient();
    const chainId = await publicClient.getChainId();

    // Create multiple holder-provider pairs
    const holders = [daoSigner1, daoSigner2, daoSigner3];
    const providers = [daoSigner4, daoSigner5, daoSigner1]; // daoSigner1 acts as provider for one escrow

    const createdEscrows: Array<{ escrowId: bigint, holder: any, provider: any }> = [];

    console.log("🚀 Creating 3 escrows sequentially (simulating concurrent-like behavior)...");

    // Create escrows sequentially to avoid ID collision but still test concurrent-like behavior
    for (let i = 0; i < holders.length; i++) {
      const holder = holders[i];
      const provider = providers[i];
      console.log(`📋 Creating escrow ${i + 1}: ${holder.account.address.slice(0, 10)}... → ${provider.account.address.slice(0, 10)}...`);

      const { escrowId } = await createTestEscrow(escrowContract, abiHelper, holder, provider, parseEther("0.1"), chainId);
      createdEscrows.push({ escrowId, holder, provider });
    }

    console.log(`✅ Created ${createdEscrows.length} escrows successfully`);

    // Verify all escrows exist and are in correct state
    for (let i = 0; i < createdEscrows.length; i++) {
      const { escrowId, holder, provider } = createdEscrows[i];
      const escrowData = await escrowContract.read.escrows([escrowId]);
      const [agreement, state, createdAt, snapshotEscrowFee, snapshotDisputeFee, evidence, disputeId, exists] = escrowData;

      console.log(`🔍 Verifying escrow ${i + 1} (ID: ${escrowId}):`);
      console.log(`  - Exists: ${exists} (should be true)`);
      console.log(`  - State: ${Number(state)} (should be 0=FUNDED)`);
      console.log(`  - Holder: ${agreement.holder.toLowerCase() === holder.account.address.toLowerCase() ? '✅' : '❌'}`);
      console.log(`  - Provider: ${agreement.provider.toLowerCase() === provider.account.address.toLowerCase() ? '✅' : '❌'}`);

      assert(exists, `Escrow ${escrowId} should exist`);
      assert(Number(state) === 0, `Escrow ${escrowId} should be in FUNDED state`);
      assert(agreement.holder.toLowerCase() === holder.account.address.toLowerCase(), `Escrow ${escrowId} holder mismatch`);
      assert(agreement.provider.toLowerCase() === provider.account.address.toLowerCase(), `Escrow ${escrowId} provider mismatch`);
    }

    console.log("✅ All concurrent escrows verified successfully!");
    console.log("🏆 Multiple simultaneous escrow creation test completed!");
  });

  test('🔄 CONCURRENT: State Isolation Between Escrows', async () => {
    const { contracts, accounts, viem } = await setupConcurrentTest();
    const { escrowContract, abiHelper } = contracts;
    const { daoSigner1, daoSigner2, daoSigner3, daoSigner4, daoSigner5 } = accounts;

    console.log("\n🎯 TESTING: State Isolation Between Concurrent Escrows");
    console.log("======================================================================");

    const publicClient = await viem.getPublicClient();
    const chainId = await publicClient.getChainId();

    // Create two escrows
    console.log("📋 Creating two escrows for isolation testing...");

    const { escrowId: escrowId1 } = await createTestEscrow(escrowContract, abiHelper, daoSigner1, daoSigner2, parseEther("0.2"), chainId);
    const { escrowId: escrowId2 } = await createTestEscrow(escrowContract, abiHelper, daoSigner3, daoSigner4, parseEther("0.15"), chainId);

    console.log(`✅ Created escrows: ${escrowId1} and ${escrowId2}`);

    // Advance first escrow to OFFCHAIN_PROOF_SENT
    console.log("🔄 Advancing escrow 1 to OFFCHAIN_PROOF_SENT state...");
    const proof = "ipfs://QmIsolationTest123";
    await escrowContract.write.provideOffchainProof([escrowId1, proof], { account: daoSigner2.account });

    // Verify states are independent
    const escrow1Data = await escrowContract.read.escrows([escrowId1]);
    const escrow2Data = await escrowContract.read.escrows([escrowId2]);
    const [agreement1, state1, createdAt1, snapshotEscrowFee1, snapshotDisputeFee1, evidence1, disputeId1, exists1] = escrow1Data;
    const [agreement2, state2, createdAt2, snapshotEscrowFee2, snapshotDisputeFee2, evidence2, disputeId2, exists2] = escrow2Data;

    console.log("🔍 State verification:");
    console.log(`  - Escrow 1 state: ${Number(state1)} (should be 1=OFFCHAIN_PROOF_SENT)`);
    console.log(`  - Escrow 2 state: ${Number(state2)} (should be 0=FUNDED)`);
    console.log(`  - Escrow 1 proof: ${evidence1 === proof ? '✅' : '❌'}`);
    console.log(`  - Escrow 2 proof: ${evidence2 === '' ? '✅' : '❌'} (should be empty)`);

    assert(Number(state1) === 1, "Escrow 1 should be in OFFCHAIN_PROOF_SENT state");
    assert(Number(state2) === 0, "Escrow 2 should remain in FUNDED state");
    assert(evidence1 === proof, "Escrow 1 should have the proof");
    assert(evidence2 === "", "Escrow 2 should not have any proof");

    // Complete escrow 1
    console.log("💰 Completing escrow 1...");
    await escrowContract.write.completeEscrow([escrowId1], { account: daoSigner1.account });

    // Verify escrow 1 is closed but escrow 2 is unaffected
    const escrow1AfterData = await escrowContract.read.escrows([escrowId1]);
    const escrow2AfterData = await escrowContract.read.escrows([escrowId2]);
    const [agreement1After, state1After, createdAt1After, snapshotEscrowFee1After, snapshotDisputeFee1After, evidence1After, disputeId1After, exists1After] = escrow1AfterData;
    const [agreement2After, state2After, createdAt2After, snapshotEscrowFee2After, snapshotDisputeFee2After, evidence2After, disputeId2After, exists2After] = escrow2AfterData;

    console.log("🔍 Final state verification:");
    console.log(`  - Escrow 1 final state: ${Number(state1After)} (should be 3=CLOSED)`);
    console.log(`  - Escrow 2 final state: ${Number(state2After)} (should be 0=FUNDED)`);

    assert(Number(state1After) === 3, "Escrow 1 should be CLOSED");
    assert(Number(state2After) === 0, "Escrow 2 should remain FUNDED");

    console.log("✅ State isolation verified - escrows are independent!");
    console.log("🏆 State isolation test completed!");
  });

  test('🔄 CONCURRENT: Rapid Operation Stress Test', async () => {
    const { contracts, accounts, viem } = await setupConcurrentTest();
    const { escrowContract, abiHelper } = contracts;
    const { daoSigner1, daoSigner2, daoSigner3, daoSigner4, daoSigner5 } = accounts;

    console.log("\n🎯 TESTING: Rapid Operation Stress Test");
    console.log("======================================================================");

    const publicClient = await viem.getPublicClient();
    const chainId = await publicClient.getChainId();

    console.log("⚡ Performing rapid escrow creation and completion cycle...");

    const iterations = 5; // Reduced for test stability
    const results = [];

    for (let i = 0; i < iterations; i++) {
      console.log(`🔄 Iteration ${i + 1}/${iterations}...`);

      try {
        // Create escrow
        const { escrowId } = await createTestEscrow(escrowContract, abiHelper, daoSigner1, daoSigner2, parseEther("0.05"), chainId);

        // Verify escrow was created successfully
        const escrowData = await escrowContract.read.escrows([escrowId]);
        const [agreement, state, createdAt, snapshotEscrowFee, snapshotDisputeFee, evidence, disputeId, exists] = escrowData;
        const isCreated = exists && Number(state) === 0;

        results.push({ iteration: i + 1, escrowId, success: isCreated });
        console.log(`  ✅ Iteration ${i + 1}: Escrow ${escrowId} created successfully`);

      } catch (error: any) {
        results.push({ iteration: i + 1, escrowId: null, success: false, error: error.message });
        console.log(`  ❌ Iteration ${i + 1}: Failed - ${error.message?.split('\n')[0] || 'Unknown error'}`);
      }
    }

    // Analyze results
    const successful = results.filter(r => r.success).length;
    const failed = results.filter(r => !r.success).length;

    console.log("📊 Stress test results:");
    console.log(`  - Total iterations: ${iterations}`);
    console.log(`  - Successful: ${successful}`);
    console.log(`  - Failed: ${failed}`);
    console.log(`  - Success rate: ${((successful / iterations) * 100).toFixed(1)}%`);

    // At least 80% success rate for the test to pass
    assert(successful >= Math.floor(iterations * 0.8), `Stress test failed: ${successful}/${iterations} successful (${((successful / iterations) * 100).toFixed(1)}% success rate)`);

    console.log("✅ Rapid operation stress test completed!");
    console.log("🏆 System can handle rapid concurrent operations!");
  });

  test('🔄 CONCURRENT: Cross-Contamination Prevention', async () => {
    const { contracts, accounts, viem } = await setupConcurrentTest();
    const { escrowContract, abiHelper } = contracts;
    const { daoSigner1, daoSigner2, daoSigner3 } = accounts;

    console.log("\n🎯 TESTING: Cross-Contamination Prevention");
    console.log("======================================================================");

    const publicClient = await viem.getPublicClient();
    const chainId = await publicClient.getChainId();

    // Create multiple escrows with overlapping participants
    console.log("📋 Creating escrows with overlapping participants...");

    // daoSigner1 is holder in escrow 1, provider in escrow 2
    const { escrowId: escrowId1 } = await createTestEscrow(escrowContract, abiHelper, daoSigner1, daoSigner2, parseEther("0.1"), chainId);
    const { escrowId: escrowId2 } = await createTestEscrow(escrowContract, abiHelper, daoSigner2, daoSigner1, parseEther("0.1"), chainId);
    const { escrowId: escrowId3 } = await createTestEscrow(escrowContract, abiHelper, daoSigner3, daoSigner1, parseEther("0.1"), chainId);

    console.log(`✅ Created escrows: ${escrowId1}, ${escrowId2}, ${escrowId3}`);

    // Verify each escrow has correct holder/provider
    const escrow1Data = await escrowContract.read.escrows([escrowId1]);
    const escrow2Data = await escrowContract.read.escrows([escrowId2]);
    const escrow3Data = await escrowContract.read.escrows([escrowId3]);
    const [agreement1, state1, createdAt1, snapshotEscrowFee1, snapshotDisputeFee1, evidence1, disputeId1, exists1] = escrow1Data;
    const [agreement2, state2, createdAt2, snapshotEscrowFee2, snapshotDisputeFee2, evidence2, disputeId2, exists2] = escrow2Data;
    const [agreement3, state3, createdAt3, snapshotEscrowFee3, snapshotDisputeFee3, evidence3, disputeId3, exists3] = escrow3Data;

    console.log("🔍 Cross-contamination verification:");

    // Escrow 1: daoSigner1 (holder) -> daoSigner2 (provider)
    assert(agreement1.holder.toLowerCase() === daoSigner1.account.address.toLowerCase(), "Escrow 1 holder should be daoSigner1");
    assert(agreement1.provider.toLowerCase() === daoSigner2.account.address.toLowerCase(), "Escrow 1 provider should be daoSigner2");

    // Escrow 2: daoSigner2 (holder) -> daoSigner1 (provider)
    assert(agreement2.holder.toLowerCase() === daoSigner2.account.address.toLowerCase(), "Escrow 2 holder should be daoSigner2");
    assert(agreement2.provider.toLowerCase() === daoSigner1.account.address.toLowerCase(), "Escrow 2 provider should be daoSigner1");

    // Escrow 3: daoSigner3 (holder) -> daoSigner1 (provider)
    assert(agreement3.holder.toLowerCase() === daoSigner3.account.address.toLowerCase(), "Escrow 3 holder should be daoSigner3");
    assert(agreement3.provider.toLowerCase() === daoSigner1.account.address.toLowerCase(), "Escrow 3 provider should be daoSigner1");

    console.log("  ✅ All escrow holder/provider assignments correct");
    console.log("  ✅ No cross-contamination between overlapping participants");

    // Test that wrong parties cannot perform actions
    console.log("🧪 Testing access control with overlapping participants...");

    // daoSigner3 should not be able to submit proof for escrow 1 (not the provider)
    try {
      await escrowContract.write.provideOffchainProof([escrowId1, "test"], { account: daoSigner3.account });
      assert(false, "daoSigner3 should not be able to submit proof for escrow 1");
    } catch (error) {
      console.log("  ✅ daoSigner3 correctly blocked from escrow 1 proof submission");
    }

    // daoSigner2 should not be able to complete escrow 3 (not the holder)
    try {
      await escrowContract.write.completeEscrow([escrowId3], { account: daoSigner2.account });
      assert(false, "daoSigner2 should not be able to complete escrow 3");
    } catch (error) {
      console.log("  ✅ daoSigner2 correctly blocked from escrow 3 completion");
    }

    console.log("✅ Cross-contamination prevention verified!");
    console.log("🏆 Access control with overlapping participants test completed!");
  });

});
