import { test, describe } from "node:test";
import assert from "node:assert";
import { network } from "hardhat";
import { parseEther, encodeAbiParameters, keccak256, encodePacked } from "viem";

describe("Contract Validation Debugging", () => {
  
  async function setupContracts() {
    const { viem, networkHelpers } = await network.connect();
    const [deployer, holder, provider, signer1, signer2, signer3, signer4] = await viem.getWalletClients();
    
    console.log("🔧 Setting up contracts for validation debugging...");
    
    // Deploy DAO
    const daoSigners = [deployer.account.address, signer1.account.address, signer2.account.address, signer3.account.address, signer4.account.address];
    const dao = await viem.deployContract("PluriSwapDAO", [daoSigners]);
    
    // Deploy supporting contracts
    const reputationOracle = await viem.deployContract("ReputationOracle", [dao.address]);
    const reputationEvents = await viem.deployContract("ReputationIngestion", [dao.address]);
    const mockStargateRouter = await viem.deployContract("MockStargateRouter", []);
    
    // Deploy EscrowContract with proper configuration
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
        500n,              // 5% base fee
        parseEther("0.001"), // 0.001 ETH min fee
        parseEther("1"),     // 1 ETH max fee
        100n,              // 1% dispute fee
        3600n,             // 1 hour min timeout
        BigInt(30 * 24 * 3600), // 30 days max timeout
        dao.address
      ]
    );
    
    const escrowContract = await viem.deployContract("EscrowContract", [
      dao.address,
      reputationOracle.address,
      reputationEvents.address,
      mockStargateRouter.address,
      escrowConfig
    ]);
    
    // Deploy ArbitrationProxy
    const arbitrationConfig = encodeAbiParameters(
      [
        { type: 'bool', name: 'paused' },
        { type: 'address', name: 'feeRecipient' },
        { type: 'uint256', name: 'baseFee' },
      ],
      [false, dao.address, parseEther("0.01")]
    );
    const arbitrationProxy = await viem.deployContract("ArbitrationProxy", [
      dao.address,
      reputationOracle.address,
      arbitrationConfig
    ]);
    
    console.log("✅ All contracts deployed for debugging");
    
    return {
      contracts: { dao, reputationOracle, reputationEvents, escrowContract, arbitrationProxy, mockStargateRouter },
      accounts: { deployer, holder, provider, signer1, signer2, signer3, signer4 },
      networkHelpers
    };
  }

  test("Debug 1: Validate Configuration and Setup", async () => {
    const { contracts, accounts } = await setupContracts();
    const { escrowContract, dao, arbitrationProxy } = contracts;
    const { viem } = await network.connect();
    
    console.log("🔍 DEBUGGING STEP 1: Configuration Validation");
    console.log("=" .repeat(50));
    
    // Check contract configuration
    const config = await escrowContract.read.getConfig();
    console.log("📋 Escrow Configuration:");
    console.log(`- Base fee percent: ${config.baseFeePercent.toString()} basis points`);
    console.log(`- Min timeout: ${config.minTimeout.toString()} seconds (${Number(config.minTimeout) / 3600} hours)`);
    console.log(`- Max timeout: ${config.maxTimeout.toString()} seconds (${Number(config.maxTimeout) / (24 * 3600)} days)`);
    console.log(`- Fee recipient: ${config.feeRecipient}`);
    console.log(`- DAO address: ${dao.address}`);
    
    // Check arbitration proxy setup
    const currentArbitrationProxy = await escrowContract.read.arbitrationProxy();
    console.log(`- Current arbitration proxy: ${currentArbitrationProxy}`);
    
    if (currentArbitrationProxy === "0x0000000000000000000000000000000000000000") {
      console.log("⚠️  WARNING: ArbitrationProxy not set - this could cause validation issues!");
      
      // Try to set arbitration proxy via DAO
      console.log("🔧 Attempting to set arbitration proxy via DAO...");
      try {
        // Use viem's encodeFunctionData
        const setArbitrationProxyCall = viem.encodeFunctionData({
          abi: escrowContract.abi,
          functionName: "setArbitrationProxy",
          args: [arbitrationProxy.address]
        });
        
        await dao.write.execute([escrowContract.address, 0n, setArbitrationProxyCall], { account: accounts.deployer.account });
        
        const newArbitrationProxy = await escrowContract.read.arbitrationProxy();
        console.log(`✅ ArbitrationProxy set to: ${newArbitrationProxy}`);
      } catch (error) {
        console.log(`❌ Failed to set arbitration proxy: ${error.message}`);
        console.log("📝 Note: ArbitrationProxy setting may require different DAO governance approach");
      }
    }
    
    console.log("✅ Configuration validation completed\n");
  });

  test("Debug 2: Timeout Validation", async () => {
    const { contracts, accounts, networkHelpers } = await setupContracts();
    const { escrowContract } = contracts;
    const { holder, provider } = accounts;
    
    console.log("🔍 DEBUGGING STEP 2: Timeout Validation");
    console.log("=" .repeat(50));
    
    const currentTime = BigInt(await networkHelpers.time.latest());
    const config = await escrowContract.read.getConfig();
    
    console.log(`⏰ Current blockchain time: ${currentTime.toString()}`);
    console.log(`📏 Min timeout requirement: ${config.minTimeout.toString()} seconds`);
    console.log(`📏 Max timeout requirement: ${config.maxTimeout.toString()} seconds`);
    
    // Test various timeout scenarios
    const timeoutScenarios = [
      { name: "Too short (30 min)", fundedTimeout: currentTime + 1800n, proofTimeout: currentTime + 3600n },
      { name: "Minimum valid (1 hour)", fundedTimeout: currentTime + 3600n, proofTimeout: currentTime + 7200n },
      { name: "Standard (2 hours)", fundedTimeout: currentTime + 7200n, proofTimeout: currentTime + 14400n },
      { name: "Maximum valid (30 days)", fundedTimeout: currentTime + BigInt(30 * 24 * 3600), proofTimeout: currentTime + BigInt(30 * 24 * 3600) + 3600n },
      { name: "Too long (40 days)", fundedTimeout: currentTime + BigInt(40 * 24 * 3600), proofTimeout: currentTime + BigInt(40 * 24 * 3600) + 3600n }
    ];
    
    for (const scenario of timeoutScenarios) {
      console.log(`\n🧪 Testing: ${scenario.name}`);
      console.log(`- Funded timeout: ${scenario.fundedTimeout.toString()} (in ${(Number(scenario.fundedTimeout - currentTime) / 3600).toFixed(1)} hours)`);
      console.log(`- Proof timeout: ${scenario.proofTimeout.toString()} (in ${(Number(scenario.proofTimeout - currentTime) / 3600).toFixed(1)} hours)`);
      
      const agreement = encodeAbiParameters(
        [
          { type: 'address', name: 'holder' },
          { type: 'address', name: 'provider' },
          { type: 'uint256', name: 'amount' },
          { type: 'uint256', name: 'fundedTimeout' },
          { type: 'uint256', name: 'proofTimeout' },
          { type: 'uint256', name: 'nonce' },
          { type: 'uint256', name: 'deadline' },
          { type: 'uint16', name: 'dstChainId' },
          { type: 'address', name: 'dstRecipient' },
          { type: 'bytes', name: 'dstAdapterParams' },
        ],
        [
          holder.account.address,
          provider.account.address,
          parseEther("1"),
          scenario.fundedTimeout,
          scenario.proofTimeout,
          1n,
          currentTime + 3600n, // 1 hour deadline
          0,
          provider.account.address,
          "0x"
        ]
      );
      
      try {
        const costs = await escrowContract.read.calculateEscrowCosts([agreement]);
        console.log(`  ✅ Timeout validation passed`);
        console.log(`  📊 Escrow fee: ${costs.escrowFee.toString()}`);
        console.log(`  📊 Total deductions: ${costs.totalDeductions.toString()}`);
      } catch (error: any) {
        if (error.message.includes("InvalidTimeout")) {
          console.log(`  ❌ InvalidTimeout error (expected for edge cases)`);
        } else {
          console.log(`  ❌ Unexpected error: ${error.message.split('\n')[0]}`);
        }
      }
    }
    
    console.log("\n✅ Timeout validation testing completed\n");
  });

  test("Debug 3: EIP-712 Signature Validation", async () => {
    const { contracts, accounts, networkHelpers } = await setupContracts();
    const { escrowContract } = contracts;
    const { holder, provider } = accounts;
    const { viem } = await network.connect();
    
    console.log("🔍 DEBUGGING STEP 3: EIP-712 Signature Validation");
    console.log("=" .repeat(50));
    
    const currentTime = BigInt(await networkHelpers.time.latest());
    const publicClient = await viem.getPublicClient();
    const chainId = await publicClient.getChainId();
    
    console.log(`🔗 Chain ID: ${chainId}`);
    console.log(`📍 Contract address: ${escrowContract.address}`);
    
    // Create a minimal valid agreement
    const agreement = {
      holder: holder.account.address,
      provider: provider.account.address,
      amount: parseEther("1"),
      fundedTimeout: currentTime + 7200n, // 2 hours (well above minimum)
      proofTimeout: currentTime + 14400n, // 4 hours
      nonce: 1n,
      deadline: currentTime + 3600n, // 1 hour validity
      dstChainId: 0,
      dstRecipient: provider.account.address,
      dstAdapterParams: "0x"
    };
    
    const agreementEncoded = encodeAbiParameters(
      [
        { type: 'address', name: 'holder' },
        { type: 'address', name: 'provider' },
        { type: 'uint256', name: 'amount' },
        { type: 'uint256', name: 'fundedTimeout' },
        { type: 'uint256', name: 'proofTimeout' },
        { type: 'uint256', name: 'nonce' },
        { type: 'uint256', name: 'deadline' },
        { type: 'uint16', name: 'dstChainId' },
        { type: 'address', name: 'dstRecipient' },
        { type: 'bytes', name: 'dstAdapterParams' },
      ],
      [
        agreement.holder,
        agreement.provider,
        agreement.amount,
        agreement.fundedTimeout,
        agreement.proofTimeout,
        agreement.nonce,
        agreement.deadline,
        agreement.dstChainId,
        agreement.dstRecipient,
        agreement.dstAdapterParams,
      ]
    );
    
    console.log("📝 Test agreement:");
    console.log(`- Holder: ${agreement.holder}`);
    console.log(`- Provider: ${agreement.provider}`);
    console.log(`- Amount: ${agreement.amount.toString()} wei`);
    console.log(`- Funded timeout: ${new Date(Number(agreement.fundedTimeout) * 1000).toLocaleString()}`);
    console.log(`- Proof timeout: ${new Date(Number(agreement.proofTimeout) * 1000).toLocaleString()}`);
    console.log(`- Deadline: ${new Date(Number(agreement.deadline) * 1000).toLocaleString()}`);
    
    // Test agreement hash calculation
    try {
      const agreementHash = await escrowContract.read.getAgreementHash([agreementEncoded]);
      console.log(`✅ Agreement hash calculated: ${agreementHash}`);
    } catch (error: any) {
      console.log(`❌ Agreement hash failed: ${error.message.split('\n')[0]}`);
      return; // Can't proceed without hash working
    }
    
    // Generate EIP-712 signatures
    console.log("\n✍️  Generating EIP-712 signatures...");
    
    const domain = {
      name: "EscrowContract",
      version: "1",
      chainId: chainId,
      verifyingContract: escrowContract.address as `0x${string}`
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
        { name: 'dstAdapterParams', type: 'bytes' }
      ]
    };

    const message = {
      holder: agreement.holder as `0x${string}`,
      provider: agreement.provider as `0x${string}`,
      amount: agreement.amount,
      fundedTimeout: agreement.fundedTimeout,
      proofTimeout: agreement.proofTimeout,
      nonce: agreement.nonce,
      deadline: agreement.deadline,
      dstChainId: agreement.dstChainId,
      dstRecipient: agreement.dstRecipient as `0x${string}`,
      dstAdapterParams: agreement.dstAdapterParams as `0x${string}`
    };
    
    const holderSignature = await holder.signTypedData({ domain, types, primaryType: 'EscrowAgreement', message });
    const providerSignature = await provider.signTypedData({ domain, types, primaryType: 'EscrowAgreement', message });
    
    console.log(`✅ Holder signature: ${holderSignature.slice(0, 20)}...${holderSignature.slice(-20)}`);
    console.log(`✅ Provider signature: ${providerSignature.slice(0, 20)}...${providerSignature.slice(-20)}`);
    
    console.log("\n✅ EIP-712 signature generation completed\n");
  });

  test("Debug 4: Minimal Escrow Creation Attempt", async () => {
    const { contracts, accounts, networkHelpers } = await setupContracts();
    const { escrowContract, dao, arbitrationProxy } = contracts;
    const { deployer, holder, provider } = accounts;
    const { viem } = await network.connect();
    
    console.log("🔍 DEBUGGING STEP 4: Minimal Escrow Creation");
    console.log("=" .repeat(50));
    
    // First, ensure arbitration proxy is set
    try {
      const setArbitrationProxyCall = viem.encodeFunctionData({
        abi: escrowContract.abi,
        functionName: "setArbitrationProxy",
        args: [arbitrationProxy.address]
      });
      await dao.write.execute([escrowContract.address, 0n, setArbitrationProxyCall], { account: deployer.account });
      console.log("✅ ArbitrationProxy set via DAO");
    } catch (error) {
      console.log(`⚠️  ArbitrationProxy setting failed: ${error.message}`);
    }
    
    const currentTime = BigInt(await networkHelpers.time.latest());
    const publicClient = await viem.getPublicClient();
    const chainId = await publicClient.getChainId();
    
    // Create minimal valid agreement with generous timeouts
    const agreement = {
      holder: holder.account.address,
      provider: provider.account.address,
      amount: parseEther("1"),
      fundedTimeout: currentTime + 7200n, // 2 hours (well above 1 hour minimum)
      proofTimeout: currentTime + 14400n, // 4 hours
      nonce: 1n,
      deadline: currentTime + 3600n, // 1 hour validity
      dstChainId: 0,
      dstRecipient: provider.account.address,
      dstAdapterParams: "0x"
    };
    
    const agreementEncoded = encodeAbiParameters(
      [
        { type: 'address', name: 'holder' },
        { type: 'address', name: 'provider' },
        { type: 'uint256', name: 'amount' },
        { type: 'uint256', name: 'fundedTimeout' },
        { type: 'uint256', name: 'proofTimeout' },
        { type: 'uint256', name: 'nonce' },
        { type: 'uint256', name: 'deadline' },
        { type: 'uint16', name: 'dstChainId' },
        { type: 'address', name: 'dstRecipient' },
        { type: 'bytes', name: 'dstAdapterParams' },
      ],
      [
        agreement.holder,
        agreement.provider,
        agreement.amount,
        agreement.fundedTimeout,
        agreement.proofTimeout,
        agreement.nonce,
        agreement.deadline,
        agreement.dstChainId,
        agreement.dstRecipient,
        agreement.dstAdapterParams,
      ]
    );
    
    // Generate signatures
    const domain = {
      name: "EscrowContract",
      version: "1",
      chainId: chainId,
      verifyingContract: escrowContract.address as `0x${string}`
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
        { name: 'dstAdapterParams', type: 'bytes' }
      ]
    };

    const message = {
      holder: agreement.holder as `0x${string}`,
      provider: agreement.provider as `0x${string}`,
      amount: agreement.amount,
      fundedTimeout: agreement.fundedTimeout,
      proofTimeout: agreement.proofTimeout,
      nonce: agreement.nonce,
      deadline: agreement.deadline,
      dstChainId: agreement.dstChainId,
      dstRecipient: agreement.dstRecipient as `0x${string}`,
      dstAdapterParams: agreement.dstAdapterParams as `0x${string}`
    };
    
    const holderSignature = await holder.signTypedData({ domain, types, primaryType: 'EscrowAgreement', message });
    const providerSignature = await provider.signTypedData({ domain, types, primaryType: 'EscrowAgreement', message });
    
    console.log("🎯 Attempting escrow creation with:");
    console.log(`- Holder: ${agreement.holder}`);
    console.log(`- Provider: ${agreement.provider}`);
    console.log(`- Amount: ${agreement.amount.toString()} wei`);
    console.log(`- Funded timeout: ${agreement.fundedTimeout.toString()} (${(Number(agreement.fundedTimeout - currentTime) / 3600).toFixed(1)} hours from now)`);
    console.log(`- Proof timeout: ${agreement.proofTimeout.toString()} (${(Number(agreement.proofTimeout - currentTime) / 3600).toFixed(1)} hours from now)`);
    
    try {
      console.log("\n🚀 Creating escrow...");
      
      const createTxHash = await escrowContract.write.createEscrow([
        agreementEncoded,
        holderSignature,
        providerSignature
      ], {
        value: agreement.amount,
        account: holder.account
      });
      
      console.log(`🎉 SUCCESS! Escrow created!`);
      console.log(`Transaction hash: ${createTxHash}`);
      
      // Verify escrow was created
      const escrowCounter = await escrowContract.read.escrowCounter();
      console.log(`✅ Escrow counter: ${escrowCounter.toString()}`);
      
      if (Number(escrowCounter) > 0) {
        const escrow = await escrowContract.read.escrows([0n]);
        console.log(`✅ Escrow state: ${escrow.state} (should be 0 = FUNDED)`);
        console.log(`✅ Escrow amount: ${escrow.agreement.amount.toString()}`);
        console.log(`✅ Escrow exists: ${escrow.exists}`);
      }
      
    } catch (error: any) {
      console.log(`❌ ESCROW CREATION FAILED`);
      console.log(`Error: ${error.message}`);
      
      if (error.message.includes("InvalidTimeout")) {
        console.log("🔍 Diagnosis: Timeout validation failed");
        console.log(`- Current time: ${currentTime.toString()}`);
        console.log(`- Funded timeout: ${agreement.fundedTimeout.toString()}`);
        console.log(`- Time difference: ${agreement.fundedTimeout - currentTime} seconds`);
        console.log(`- Required minimum: 3600 seconds (1 hour)`);
      } else if (error.message.includes("InvalidSignature")) {
        console.log("🔍 Diagnosis: EIP-712 signature validation failed");
      } else if (error.message.includes("InvalidAmount")) {
        console.log("🔍 Diagnosis: Amount validation failed");
        console.log(`- msg.value: ${agreement.amount.toString()}`);
        console.log(`- agreement.amount: ${agreement.amount.toString()}`);
      } else if (error.message.includes("InvalidAddress")) {
        console.log("🔍 Diagnosis: Address validation failed");
      } else {
        console.log("🔍 Diagnosis: Unknown validation error - may need deeper investigation");
      }
    }
    
    console.log("\n✅ Minimal escrow creation test completed");
  });
});
