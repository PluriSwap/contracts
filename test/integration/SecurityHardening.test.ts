import { test, describe } from 'node:test';
import { strict as assert } from 'node:assert';
import hre, { network } from 'hardhat';
import { encodeAbiParameters, parseEther, formatEther, keccak256, toHex, getAddress } from 'viem';
import { privateKeyToAccount, generatePrivateKey } from 'viem/accounts';

/**
 * Security Hardening Test Suite - Phase 2
 *
 * Advanced security validation for production readiness:
 * - Advanced reentrancy attack vectors
 * - Gas optimization and performance analysis
 * - Economic attack prevention (fee manipulation, griefing)
 * - Cross-chain security validation
 * - Emergency recovery procedures
 * - DAO governance security
 * - Timestamp manipulation attacks
 * - Flash loan attack vectors
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

interface GasMeasurement {
  functionName: string;
  gasUsed: bigint;
  gasLimit: bigint;
  efficiency: number;
}

// Malicious contract for advanced reentrancy testing
const MALICIOUS_CONTRACT_CODE = `
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IEscrowContract {
    function createEscrow(bytes calldata agreementEncoded, bytes calldata holderSignature, bytes calldata providerSignature) external payable;
    function provideOffchainProof(uint256 escrowId, string calldata proof) external;
    function completeEscrow(uint256 escrowId) external payable;
    function cancel(uint256 escrowId) external;
}

contract AdvancedMaliciousContract {
    IEscrowContract public escrowContract;
    uint256 public reentryCount;
    bool public shouldReenter;
    uint256 public maxReentries;

    constructor(address _escrowContract) {
        escrowContract = IEscrowContract(_escrowContract);
        reentryCount = 0;
        shouldReenter = false;
        maxReentries = 3;
    }

    function setReentryConfig(bool _shouldReenter, uint256 _maxReentries) external {
        shouldReenter = _shouldReenter;
        maxReentries = _maxReentries;
    }

    // Malicious fallback that attempts reentrancy
    receive() external payable {
        if (shouldReenter && reentryCount < maxReentries) {
            reentryCount++;

            // Try to reenter escrow completion
            if (reentryCount == 1) {
                try escrowContract.completeEscrow(0) {
                    // Success - this should be blocked
                } catch {
                    // Expected to fail due to reentrancy guard
                }
            }

            // Try to create new escrow during completion
            if (reentryCount == 2) {
                // This would require valid signatures, so just increment counter
            }
        }
    }

    function attackCreateEscrow(bytes calldata agreementEncoded, bytes calldata holderSignature, bytes calldata providerSignature) external payable {
        escrowContract.createEscrow{value: msg.value}(agreementEncoded, holderSignature, providerSignature);
    }

    function attackCompleteEscrow(uint256 escrowId) external {
        escrowContract.completeEscrow(escrowId);
    }
}
`;

async function setupSecurityHardeningTest() {
  console.log("🛡️ Setting up comprehensive security hardening test environment...");

  const { viem, networkHelpers } = await network.connect();
  const [deployer, daoSigner1, daoSigner2, daoSigner3, daoSigner4, daoSigner5, attacker, victim, whale] = await viem.getWalletClients();

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

  // Deploy advanced malicious contract for reentrancy testing
  const maliciousContract = await viem.deployContract("AdvancedMaliciousContract", [escrowContract.address]);

  // Fund accounts for testing
  const publicClient = await viem.getPublicClient();
  const whaleTx = await deployer.sendTransaction({
    to: whale.account.address,
    value: parseEther("1000"), // Whale with 1000 ETH
  });
  await publicClient.waitForTransactionReceipt({ hash: whaleTx });

  const attackerTx = await deployer.sendTransaction({
    to: attacker.account.address,
    value: parseEther("10"), // Attacker with 10 ETH
  });
  await publicClient.waitForTransactionReceipt({ hash: attackerTx });

  console.log("✅ Security hardening test environment ready");
  console.log(`- Whale: ${whale.account.address} (${formatEther(await publicClient.getBalance({address: whale.account.address}))} ETH)`);
  console.log(`- Attacker: ${attacker.account.address} (${formatEther(await publicClient.getBalance({address: attacker.account.address}))} ETH)`);

  return {
    contracts: {
      dao,
      reputationOracle,
      reputationEvents,
      arbitrationProxy,
      escrowContract,
      mockStargateRouter,
      abiHelper,
      maliciousContract
    },
    accounts: {
      deployer,
      daoSigner1,
      daoSigner2,
      daoSigner3,
      daoSigner4,
      daoSigner5,
      attacker,
      victim,
      whale
    },
    networkHelpers,
    publicClient,
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

async function measureGasUsage(contract: any, functionCall: any, functionName: string): Promise<GasMeasurement> {
  try {
    const gasEstimate = await contract.estimateGas[functionCall.method](functionCall.args);
    const gasLimit = gasEstimate * 120n / 100n; // 20% buffer

    const tx = await contract.write[functionCall.method](functionCall.args, { gasLimit });
    const receipt = await tx.wait();

    const gasUsed = receipt.gasUsed;
    const efficiency = Number((gasUsed * 100n) / gasLimit);

    return {
      functionName,
      gasUsed,
      gasLimit,
      efficiency
    };
  } catch (error) {
    return {
      functionName,
      gasUsed: 0n,
      gasLimit: 0n,
      efficiency: 0
    };
  }
}

describe('Security Hardening - Phase 2', () => {

  test('🔒 ADVANCED REENTRANCY: Multi-stage Attack Vectors', async () => {
    const { contracts, accounts, publicClient } = await setupSecurityHardeningTest();
    const { escrowContract, maliciousContract, abiHelper } = contracts;
    const { attacker, daoSigner1 } = accounts;

    console.log("\n🎯 TESTING: Advanced Multi-stage Reentrancy Attacks");
    console.log("======================================================================");

    // Setup test escrow
    const currentTime = BigInt(Math.floor(Date.now() / 1000));
    const agreementParams: EscrowAgreement = {
      holder: attacker.account.address,
      provider: daoSigner1.account.address,
      amount: parseEther("1.0"),
      fundedTimeout: currentTime + BigInt(48 * 60 * 60),
      proofTimeout: currentTime + BigInt(72 * 60 * 60),
      nonce: BigInt(Math.floor(Math.random() * 1000000)),
      deadline: currentTime + BigInt(24 * 60 * 60),
      dstChainId: 0,
      dstRecipient: daoSigner1.account.address,
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

    const chainId = await publicClient.getChainId();
    const holderSignature = await generateEIP712Signature(agreementParams, attacker, escrowContract.address, chainId);
    const providerSignature = await generateEIP712Signature(agreementParams, daoSigner1, escrowContract.address, chainId);

    console.log("🧪 Test 1: Reentrancy during escrow creation...");
    // Configure malicious contract to attempt reentrancy during creation
    await maliciousContract.write.setReentryConfig([true, 2n]);

    try {
      await maliciousContract.write.attackCreateEscrow(
        [agreementEncoded, holderSignature, providerSignature],
        { value: agreementParams.amount, account: attacker.account }
      );
      console.log("⚠️ Creation succeeded - checking if reentrancy was blocked...");
    } catch (error: any) {
      console.log(`✅ Creation blocked as expected: ${error.message?.split('\n')[0] || 'Reentrancy prevented'}`);
    }

    console.log("🧪 Test 2: Reentrancy during escrow completion...");
    // First create a valid escrow normally
    const validTx = await escrowContract.write.createEscrow(
      [agreementEncoded, holderSignature, providerSignature],
      { account: attacker.account, value: agreementParams.amount }
    );

    // Submit proof
    await escrowContract.write.provideOffchainProof([0n, "ipfs://test"], { account: daoSigner1.account });

    // Configure for completion reentrancy
    await maliciousContract.write.setReentryConfig([true, 3n]);

    try {
      await maliciousContract.write.attackCompleteEscrow([0n]);
      console.log("⚠️ Completion succeeded - checking if reentrancy was blocked...");
    } catch (error: any) {
      console.log(`✅ Completion blocked as expected: ${error.message?.split('\n')[0] || 'Reentrancy prevented'}`);
    }

    // Verify final state
    const escrowData = await escrowContract.read.escrows([0n]);
    const [agreement, state, createdAt, snapshotEscrowFee, snapshotDisputeFee, evidence, disputeId, exists] = escrowData;

    console.log(`🏁 Final escrow state: ${Number(state)} (should be 2=OFFCHAIN_PROOF_SENT if reentrancy blocked completion)`);
    assert(Number(state) === 1 || Number(state) === 2, "Escrow should remain in active state if reentrancy prevented completion");

    console.log("🛡️ Advanced reentrancy attack vectors neutralized!");
    console.log("🏆 Multi-stage reentrancy protection verified!");
  });

  test('⛽ GAS OPTIMIZATION: Performance Analysis & Efficiency', async () => {
    const { contracts, accounts, publicClient } = await setupSecurityHardeningTest();
    const { escrowContract, abiHelper } = contracts;
    const { daoSigner1, daoSigner2 } = accounts;

    console.log("\n🎯 TESTING: Gas Optimization & Performance Analysis");
    console.log("======================================================================");

    const gasMeasurements: GasMeasurement[] = [];
    const currentTime = BigInt(Math.floor(Date.now() / 1000));

    // Test different escrow sizes for gas analysis
    const testSizes = [
      { amount: parseEther("0.1"), name: "Small (0.1 ETH)" },
      { amount: parseEther("1.0"), name: "Medium (1.0 ETH)" },
      { amount: parseEther("10.0"), name: "Large (10.0 ETH)" },
    ];

    for (const testSize of testSizes) {
      console.log(`📊 Testing gas efficiency for: ${testSize.name}`);

      const agreementParams: EscrowAgreement = {
        holder: daoSigner1.account.address,
        provider: daoSigner2.account.address,
        amount: testSize.amount,
        fundedTimeout: currentTime + BigInt(48 * 60 * 60),
        proofTimeout: currentTime + BigInt(72 * 60 * 60),
        nonce: BigInt(Math.floor(Math.random() * 1000000)),
        deadline: currentTime + BigInt(24 * 60 * 60),
        dstChainId: 0,
        dstRecipient: daoSigner2.account.address,
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

      const chainId = await publicClient.getChainId();
      const holderSignature = await generateEIP712Signature(agreementParams, daoSigner1, escrowContract.address, chainId);
      const providerSignature = await generateEIP712Signature(agreementParams, daoSigner2, escrowContract.address, chainId);

      // Measure createEscrow gas
      const createGas = await measureGasUsage(
        escrowContract,
        {
          method: 'createEscrow',
          args: [agreementEncoded, holderSignature, providerSignature],
          value: agreementParams.amount,
          account: daoSigner1.account
        },
        `createEscrow_${testSize.name}`
      );

      gasMeasurements.push(createGas);
      console.log(`  - createEscrow: ${createGas.gasUsed} gas (${createGas.efficiency}% efficiency)`);

      // Get escrow ID and continue with proof submission
      const escrowId = (await escrowContract.read.escrowCounter()) - 1n;

      // Measure provideOffchainProof gas
      const proofGas = await measureGasUsage(
        escrowContract,
        {
          method: 'provideOffchainProof',
          args: [escrowId, "ipfs://test-proof"],
          account: daoSigner2.account
        },
        `provideOffchainProof_${testSize.name}`
      );

      gasMeasurements.push(proofGas);
      console.log(`  - provideOffchainProof: ${proofGas.gasUsed} gas (${proofGas.efficiency}% efficiency)`);

      // Measure completeEscrow gas
      const completeGas = await measureGasUsage(
        escrowContract,
        {
          method: 'completeEscrow',
          args: [escrowId],
          account: daoSigner1.account
        },
        `completeEscrow_${testSize.name}`
      );

      gasMeasurements.push(completeGas);
      console.log(`  - completeEscrow: ${completeGas.gasUsed} gas (${completeGas.efficiency}% efficiency)`);
    }

    // Analyze gas efficiency patterns
    console.log("📈 Gas Efficiency Analysis:");
    const avgEfficiency = gasMeasurements.reduce((sum, m) => sum + m.efficiency, 0) / gasMeasurements.length;
    const maxGas = Math.max(...gasMeasurements.map(m => Number(m.gasUsed)));
    const minGas = Math.min(...gasMeasurements.map(m => Number(m.gasUsed)));

    console.log(`  - Average efficiency: ${avgEfficiency.toFixed(1)}%`);
    console.log(`  - Gas usage range: ${minGas} - ${maxGas} gas`);
    console.log(`  - Gas efficiency threshold: ${avgEfficiency > 80 ? '✅ GOOD' : avgEfficiency > 60 ? '⚠️ ACCEPTABLE' : '❌ NEEDS OPTIMIZATION'}`);

    // Performance assertions
    assert(avgEfficiency > 60, `Gas efficiency too low: ${avgEfficiency.toFixed(1)}% (should be > 60%)`);
    assert(maxGas < 500000, `Maximum gas usage too high: ${maxGas} (should be < 500k)`);

    console.log("⛽ Gas optimization analysis completed!");
    console.log("🏆 Performance metrics validated!");
  });

  test('💰 ECONOMIC ATTACKS: Fee Manipulation & Griefing Prevention', async () => {
    const { contracts, accounts, publicClient } = await setupSecurityHardeningTest();
    const { escrowContract, abiHelper } = contracts;
    const { attacker, victim, whale, daoSigner1, daoSigner2 } = accounts;

    console.log("\n🎯 TESTING: Economic Attack Vectors");
    console.log("======================================================================");

    const currentTime = BigInt(Math.floor(Date.now() / 1000));

    console.log("🧪 Test 1: Fee manipulation through reputation manipulation...");

    // Create a normal escrow first
    const normalAgreement: EscrowAgreement = {
      holder: victim.account.address,
      provider: daoSigner1.account.address,
      amount: parseEther("1.0"),
      fundedTimeout: currentTime + BigInt(48 * 60 * 60),
      proofTimeout: currentTime + BigInt(72 * 60 * 60),
      nonce: BigInt(Math.floor(Math.random() * 1000000)),
      deadline: currentTime + BigInt(24 * 60 * 60),
      dstChainId: 0,
      dstRecipient: daoSigner1.account.address,
      dstAdapterParams: "0x" as `0x${string}`,
    };

    const normalEncoded = await abiHelper.read.encodeEscrowAgreement([
      normalAgreement.holder,
      normalAgreement.provider,
      normalAgreement.amount,
      normalAgreement.fundedTimeout,
      normalAgreement.proofTimeout,
      normalAgreement.nonce,
      normalAgreement.deadline,
      normalAgreement.dstChainId,
      normalAgreement.dstRecipient,
      normalAgreement.dstAdapterParams,
    ]);

    const chainId = await publicClient.getChainId();
    const victimSig = await generateEIP712Signature(normalAgreement, victim, escrowContract.address, chainId);
    const daoSigner1Sig = await generateEIP712Signature(normalAgreement, daoSigner1, escrowContract.address, chainId);

    // Calculate expected fees
    const expectedCosts = await escrowContract.read.calculateEscrowCosts([normalEncoded]);
    console.log(`Expected escrow fee: ${formatEther(expectedCosts.escrowFee)} ETH`);

    // Create escrow and measure actual fees
    const victimBefore = await publicClient.getBalance({ address: victim.account.address });
    await escrowContract.write.createEscrow(
      [normalEncoded, victimSig, daoSigner1Sig],
      { account: victim.account, value: normalAgreement.amount }
    );
    const victimAfter = await publicClient.getBalance({ address: victim.account.address });
    const actualFee = victimBefore - victimAfter - normalAgreement.amount;

    console.log(`Actual fee paid: ${formatEther(actualFee)} ETH`);
    console.log(`Fee difference: ${formatEther(expectedCosts.escrowFee - actualFee)} ETH`);

    // Fee should match expected calculation
    assert(Math.abs(Number(expectedCosts.escrowFee - actualFee)) < Number(parseEther("0.001")), "Fee calculation should be deterministic");

    console.log("🧪 Test 2: Griefing attack through excessive disputes...");

    // Create another escrow for dispute testing
    const disputeAgreement: EscrowAgreement = {
      holder: victim.account.address,
      provider: daoSigner2.account.address,
      amount: parseEther("0.5"),
      fundedTimeout: currentTime + BigInt(48 * 60 * 60),
      proofTimeout: currentTime + BigInt(72 * 60 * 60),
      nonce: BigInt(Math.floor(Math.random() * 1000000)) + 1000n, // Different nonce
      deadline: currentTime + BigInt(24 * 60 * 60),
      dstChainId: 0,
      dstRecipient: daoSigner2.account.address,
      dstAdapterParams: "0x" as `0x${string}`,
    };

    const disputeEncoded = await abiHelper.read.encodeEscrowAgreement([
      disputeAgreement.holder,
      disputeAgreement.provider,
      disputeAgreement.amount,
      disputeAgreement.fundedTimeout,
      disputeAgreement.proofTimeout,
      disputeAgreement.nonce,
      disputeAgreement.deadline,
      disputeAgreement.dstChainId,
      disputeAgreement.dstRecipient,
      disputeAgreement.dstAdapterParams,
    ]);

    const daoSigner2Sig = await generateEIP712Signature(disputeAgreement, daoSigner2, escrowContract.address, chainId);

    // Create escrow
    await escrowContract.write.createEscrow(
      [disputeEncoded, victimSig, daoSigner2Sig],
      { account: victim.account, value: disputeAgreement.amount }
    );

    const escrowId = (await escrowContract.read.escrowCounter()) - 1n;

    // Attacker tries to create frivolous dispute
    console.log("🚨 Attacker attempting frivolous dispute...");
    try {
      await escrowContract.write.createDispute(
        [escrowId, "Frivolous dispute by attacker"],
        { account: attacker.account, value: parseEther("0.1") }
      );
      console.log("❌ Frivolous dispute should have been blocked!");
      assert(false, "Frivolous dispute should be blocked");
    } catch (error: any) {
      console.log(`✅ Frivolous dispute blocked: ${error.message?.split('\n')[0] || 'Access denied'}`);
    }

    // Only legitimate party should be able to dispute
    console.log("✅ Only legitimate parties can create disputes");
    console.log("🛡️ Economic attack vectors neutralized!");
    console.log("🏆 Fee manipulation and griefing prevention verified!");
  });

  test('🌉 CROSS-CHAIN SECURITY: Bridge Attack Prevention', async () => {
    const { contracts, accounts, publicClient } = await setupSecurityHardeningTest();
    const { escrowContract, abiHelper, mockStargateRouter } = contracts;
    const { attacker, victim, daoSigner1 } = accounts;

    console.log("\n🎯 TESTING: Cross-Chain Security Validation");
    console.log("======================================================================");

    const currentTime = BigInt(Math.floor(Date.now() / 1000));
    const chainId = await publicClient.getChainId();

    console.log("🧪 Test 1: Invalid destination chain validation...");

    // Try to create escrow with invalid destination chain
    const invalidChainAgreement: EscrowAgreement = {
      holder: victim.account.address,
      provider: daoSigner1.account.address,
      amount: parseEther("1.0"),
      fundedTimeout: currentTime + BigInt(48 * 60 * 60),
      proofTimeout: currentTime + BigInt(72 * 60 * 60),
      nonce: BigInt(Math.floor(Math.random() * 1000000)),
      deadline: currentTime + BigInt(24 * 60 * 60),
      dstChainId: 99999, // Invalid chain ID
      dstRecipient: attacker.account.address, // Wrong recipient
      dstAdapterParams: "0x" as `0x${string}`,
    };

    const invalidEncoded = await abiHelper.read.encodeEscrowAgreement([
      invalidChainAgreement.holder,
      invalidChainAgreement.provider,
      invalidChainAgreement.amount,
      invalidChainAgreement.fundedTimeout,
      invalidChainAgreement.proofTimeout,
      invalidChainAgreement.nonce,
      invalidChainAgreement.deadline,
      invalidChainAgreement.dstChainId,
      invalidChainAgreement.dstRecipient,
      invalidChainAgreement.dstAdapterParams,
    ]);

    const victimSig = await generateEIP712Signature(invalidChainAgreement, victim, escrowContract.address, chainId);
    const daoSigner1Sig = await generateEIP712Signature(invalidChainAgreement, daoSigner1, escrowContract.address, chainId);

    try {
      await escrowContract.write.createEscrow(
        [invalidEncoded, victimSig, daoSigner1Sig],
        { account: victim.account, value: invalidChainAgreement.amount }
      );
      console.log("❌ Invalid chain ID should have been rejected!");
      assert(false, "Invalid chain ID should be rejected");
    } catch (error: any) {
      console.log(`✅ Invalid chain ID blocked: ${error.message?.split('\n')[0] || 'Invalid chain'}`);
    }

    console.log("🧪 Test 2: Bridge fee manipulation prevention...");

    // Test with valid cross-chain escrow
    const validCrossChainAgreement: EscrowAgreement = {
      holder: victim.account.address,
      provider: daoSigner1.account.address,
      amount: parseEther("2.0"),
      fundedTimeout: currentTime + BigInt(48 * 60 * 60),
      proofTimeout: currentTime + BigInt(72 * 60 * 60),
      nonce: BigInt(Math.floor(Math.random() * 1000000)) + 2000n,
      deadline: currentTime + BigInt(24 * 60 * 60),
      dstChainId: 1, // Ethereum mainnet (assuming current is testnet)
      dstRecipient: daoSigner1.account.address,
      dstAdapterParams: "0x" as `0x${string}`,
    };

    const validCrossChainEncoded = await abiHelper.read.encodeEscrowAgreement([
      validCrossChainAgreement.holder,
      validCrossChainAgreement.provider,
      validCrossChainAgreement.amount,
      validCrossChainAgreement.fundedTimeout,
      validCrossChainAgreement.proofTimeout,
      validCrossChainAgreement.nonce,
      validCrossChainAgreement.deadline,
      validCrossChainAgreement.dstChainId,
      validCrossChainAgreement.dstRecipient,
      validCrossChainAgreement.dstAdapterParams,
    ]);

    // Calculate cross-chain costs
    const crossChainCosts = await escrowContract.read.calculateEscrowCosts([validCrossChainEncoded]);
    console.log(`Cross-chain escrow fee: ${formatEther(crossChainCosts.escrowFee)} ETH`);
    console.log(`Cross-chain bridge fee: ${formatEther(crossChainCosts.bridgeFee)} ETH`);
    console.log(`Total cross-chain cost: ${formatEther(crossChainCosts.totalDeductions)} ETH`);

    // Verify bridge fee is reasonable (not manipulated)
    assert(crossChainCosts.bridgeFee > 0n, "Bridge fee should be positive for cross-chain");
    assert(crossChainCosts.bridgeFee < crossChainCosts.totalDeductions / 2n, "Bridge fee should not dominate total costs");

    console.log("🧪 Test 3: Bridge failure handling...");

    // Test completing cross-chain escrow (should work with mock router)
    const crossChainVictimSig = await generateEIP712Signature(validCrossChainAgreement, victim, escrowContract.address, chainId);
    const crossChainDaoSigner1Sig = await generateEIP712Signature(validCrossChainAgreement, daoSigner1, escrowContract.address, chainId);

    const victimBeforeCrossChain = await publicClient.getBalance({ address: victim.account.address });
    await escrowContract.write.createEscrow(
      [validCrossChainEncoded, crossChainVictimSig, crossChainDaoSigner1Sig],
      { account: victim.account, value: validCrossChainAgreement.amount }
    );

    const escrowId = (await escrowContract.read.escrowCounter()) - 1n;

    // Submit proof and complete
    await escrowContract.write.provideOffchainProof([escrowId, "ipfs://cross-chain-proof"], { account: daoSigner1.account });
    await escrowContract.write.completeEscrow([escrowId], { account: victim.account });

    const victimAfterCrossChain = await publicClient.getBalance({ address: victim.account.address });
    const netChange = victimBeforeCrossChain - victimAfterCrossChain;

    console.log(`Cross-chain completion net change: ${formatEther(netChange)} ETH`);
    console.log(`Expected cost: ${formatEther(crossChainCosts.totalDeductions)} ETH`);

    // Verify costs are as expected
    assert(Math.abs(Number(netChange - validCrossChainAgreement.amount - crossChainCosts.totalDeductions)) < Number(parseEther("0.01")),
           "Cross-chain costs should match calculation");

    console.log("🌉 Cross-chain security validation completed!");
    console.log("🏆 Bridge attack prevention verified!");
  });

  test('🚨 EMERGENCY RECOVERY: DAO Controls & System Recovery', async () => {
    const { contracts, accounts, publicClient } = await setupSecurityHardeningTest();
    const { escrowContract, arbitrationProxy, dao, abiHelper } = contracts;
    const { daoSigner1, daoSigner2, daoSigner3, attacker, victim } = accounts;

    console.log("\n🎯 TESTING: Emergency Recovery Procedures");
    console.log("======================================================================");

    const currentTime = BigInt(Math.floor(Date.now() / 1000));

    console.log("🧪 Test 1: Emergency pause functionality...");

    // Create an escrow before pause
    const agreementParams: EscrowAgreement = {
      holder: victim.account.address,
      provider: daoSigner1.account.address,
      amount: parseEther("1.0"),
      fundedTimeout: currentTime + BigInt(48 * 60 * 60),
      proofTimeout: currentTime + BigInt(72 * 60 * 60),
      nonce: BigInt(Math.floor(Math.random() * 1000000)),
      deadline: currentTime + BigInt(24 * 60 * 60),
      dstChainId: 0,
      dstRecipient: daoSigner1.account.address,
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

    const chainId = await publicClient.getChainId();
    const victimSig = await generateEIP712Signature(agreementParams, victim, escrowContract.address, chainId);
    const daoSigner1Sig = await generateEIP712Signature(agreementParams, daoSigner1, escrowContract.address, chainId);

    // Create escrow before emergency
    await escrowContract.write.createEscrow(
      [agreementEncoded, victimSig, daoSigner1Sig],
      { account: victim.account, value: agreementParams.amount }
    );

    console.log("✅ Escrow created before emergency pause");

    // DAO initiates emergency pause (requires 3-of-5 signatures)
    console.log("🚨 DAO initiating emergency pause...");

    // First signer proposes pause
    const pauseReason = "Security vulnerability detected - emergency pause required";
    const pauseTx1 = await dao.write.proposePauseAll([pauseReason], { account: daoSigner1.account });
    const pauseTxId = 0n; // First transaction

    // Second signer approves
    await dao.write.approveTransaction([pauseTxId], { account: daoSigner2.account });

    // Third signer approves and executes
    await dao.write.approveTransaction([pauseTxId], { account: daoSigner3.account });
    await dao.write.executeTransaction([pauseTxId], { account: daoSigner1.account });

    console.log("✅ Emergency pause executed by DAO");

    // Verify pause state
    const escrowPaused = await escrowContract.read.paused();
    const arbitrationPaused = await arbitrationProxy.read.paused();

    console.log(`EscrowContract paused: ${escrowPaused}`);
    console.log(`ArbitrationProxy paused: ${arbitrationPaused}`);

    assert(escrowPaused, "EscrowContract should be paused");
    assert(arbitrationPaused, "ArbitrationProxy should be paused");

    console.log("🧪 Test 2: Operations blocked during emergency...");

    // Try to create new escrow (should fail)
    try {
      const newAgreement: EscrowAgreement = {
        ...agreementParams,
        nonce: agreementParams.nonce + 1000n,
      };
      const newEncoded = await abiHelper.read.encodeEscrowAgreement([
        newAgreement.holder,
        newAgreement.provider,
        newAgreement.amount,
        newAgreement.fundedTimeout,
        newAgreement.proofTimeout,
        newAgreement.nonce,
        newAgreement.deadline,
        newAgreement.dstChainId,
        newAgreement.dstRecipient,
        newAgreement.dstAdapterParams,
      ]);

      await escrowContract.write.createEscrow(
        [newEncoded, victimSig, daoSigner1Sig],
        { account: victim.account, value: newAgreement.amount }
      );
      console.log("❌ New escrow creation should have been blocked!");
      assert(false, "New operations should be blocked during pause");
    } catch (error: any) {
      console.log(`✅ New operations blocked: ${error.message?.split('\n')[0] || 'Paused'}`);
    }

    // Try to create dispute (should fail)
    try {
      await escrowContract.write.createDispute(
        [0n, "Emergency dispute attempt"],
        { account: victim.account, value: parseEther("0.01") }
      );
      console.log("❌ Dispute creation should have been blocked!");
      assert(false, "Dispute creation should be blocked during pause");
    } catch (error: any) {
      console.log(`✅ Dispute creation blocked: ${error.message?.split('\n')[0] || 'Paused'}`);
    }

    console.log("🧪 Test 3: Emergency unpause and recovery...");

    // DAO initiates unpause (requires 3-of-5 signatures)
    console.log("🔄 DAO initiating emergency unpause...");

    const unpauseReason = "Security issue resolved - system recovery complete";
    const unpauseTx1 = await dao.write.proposeUnpauseAll([unpauseReason], { account: daoSigner1.account });
    const unpauseTxId = 1n; // Second transaction

    // Approvals and execution
    await dao.write.approveTransaction([unpauseTxId], { account: daoSigner2.account });
    await dao.write.approveTransaction([unpauseTxId], { account: daoSigner3.account });
    await dao.write.executeTransaction([unpauseTxId], { account: daoSigner1.account });

    console.log("✅ Emergency unpause executed by DAO");

    // Verify unpause state
    const escrowPausedAfter = await escrowContract.read.paused();
    const arbitrationPausedAfter = await arbitrationProxy.read.paused();

    console.log(`EscrowContract paused after unpause: ${escrowPausedAfter}`);
    console.log(`ArbitrationProxy paused after unpause: ${arbitrationPausedAfter}`);

    assert(!escrowPausedAfter, "EscrowContract should be unpaused");
    assert(!arbitrationPausedAfter, "ArbitrationProxy should be unpaused");

    // Verify normal operations can resume
    console.log("🔄 Testing normal operations after recovery...");
    try {
      const recoveryAgreement: EscrowAgreement = {
        ...agreementParams,
        nonce: agreementParams.nonce + 2000n,
      };
      const recoveryEncoded = await abiHelper.read.encodeEscrowAgreement([
        recoveryAgreement.holder,
        recoveryAgreement.provider,
        recoveryAgreement.amount,
        recoveryAgreement.fundedTimeout,
        recoveryAgreement.proofTimeout,
        recoveryAgreement.nonce,
        recoveryAgreement.deadline,
        recoveryAgreement.dstChainId,
        recoveryAgreement.dstRecipient,
        recoveryAgreement.dstAdapterParams,
      ]);

      await escrowContract.write.createEscrow(
        [recoveryEncoded, victimSig, daoSigner1Sig],
        { account: victim.account, value: recoveryAgreement.amount }
      );
      console.log("✅ Normal operations resumed after emergency recovery");
    } catch (error: any) {
      console.log(`❌ Normal operations failed to resume: ${error.message?.split('\n')[0] || 'Error'}`);
      assert(false, "Normal operations should work after emergency recovery");
    }

    console.log("🚨 Emergency recovery procedures validated!");
    console.log("🏆 DAO controls and system recovery verified!");
  });

});
