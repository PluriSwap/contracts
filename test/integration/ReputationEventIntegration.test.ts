import { test, describe } from "node:test";
import assert from "node:assert";
import { network } from "hardhat";
import { parseEther, encodeAbiParameters, keccak256, toBytes } from "viem";

describe("Reputation Event Integration Tests", () => {

  // Helper to compute event name hash (since eventName is indexed)
  function getEventNameHash(eventName: string): string {
    return keccak256(toBytes(eventName));
  }

  async function deployContracts() {
    const { viem } = await network.connect();
    const [deployer, holder, provider, arbitrator, admin] = await viem.getWalletClients();
    
    // Deploy DAO with unique signers
    const dao = await viem.deployContract("PluriSwapDAO", [
      [deployer.account.address, holder.account.address, provider.account.address, arbitrator.account.address, admin.account.address]
    ]);
    
    // Deploy ReputationIngestion
    const reputationEvents = await viem.deployContract("ReputationIngestion", [deployer.account.address]);
    
    return {
      contracts: { reputationEvents },
      accounts: { deployer, holder, provider, arbitrator, admin }
    };
  }

  test("🎯 INTEGRATION: ReputationIngestion Direct Event Testing", async () => {
    console.log("Testing ReputationIngestion contract directly...");
    const { contracts, accounts } = await deployContracts();
    const { reputationEvents } = contracts;
    const { deployer, holder, provider } = accounts;

    // Track reputation events
    const capturedEvents: any[] = [];
    const unwatch = reputationEvents.watchEvent.ReputationEvent(
      {},
      {
        onLogs: (logs: any[]) => {
          logs.forEach(log => {
            capturedEvents.push({
              eventName: log.args.eventName,
              wallet: log.args.wallet,
              caller: log.args.caller,
              timestamp: log.args.timestamp,
              metadata: log.args.metadata
            });
            console.log(`✅ Event captured: "${log.args.eventName}" for ${log.args.wallet}`);
          });
        }
      }
    );

    try {
      console.log("\n🔹 Testing direct reputation event emissions...");

      // Test 1: Simulate escrow creation
      await reputationEvents.write.event_of(["escrow_created", holder.account.address, "0x"], {
        account: deployer.account
      });

      await reputationEvents.write.event_of(["escrow_created", provider.account.address, "0x"], {
        account: deployer.account
      });

      // Test 2: Simulate proof submission
      await reputationEvents.write.event_of(["proof_submitted", provider.account.address, "0x"], {
        account: deployer.account
      });

      // Test 3: Simulate completion
      await reputationEvents.write.event_of(["escrow_completed", holder.account.address, "0x"], {
        account: deployer.account
      });

      await reputationEvents.write.event_of(["escrow_completed", provider.account.address, "0x"], {
        account: deployer.account
      });

      // Test 4: Simulate dispute
      await reputationEvents.write.event_of(["dispute_created", holder.account.address, "0x"], {
        account: deployer.account
      });

      // Test 5: Simulate dispute resolution
      await reputationEvents.write.event_of(["dispute_won", provider.account.address, "0x"], {
        account: deployer.account
      });

      await reputationEvents.write.event_of(["dispute_lost", holder.account.address, "0x"], {
        account: deployer.account
      });

      // Test 6: Simulate cancellation
      await reputationEvents.write.event_of(["escrow_cancelled", holder.account.address, "0x"], {
        account: deployer.account
      });

      // Wait for events to be processed
      await new Promise(resolve => setTimeout(resolve, 1000));

      console.log(`\n📊 Reputation Event Results:`);
      console.log(`- Total events captured: ${capturedEvents.length}`);
      
      console.log("\nCaptured event hashes:");
      capturedEvents.forEach((event, i) => {
        console.log(`  ${i + 1}. Event hash: ${event.eventName} for wallet: ${event.wallet.slice(0, 10)}...`);
      });

      // Verify all expected events were captured  
      // Note: eventName is indexed, so we get hashes instead of original strings
      const expectedEvents = [
        { name: 'escrow_created', hash: getEventNameHash('escrow_created'), wallet: holder.account.address },
        { name: 'escrow_created', hash: getEventNameHash('escrow_created'), wallet: provider.account.address },
        { name: 'proof_submitted', hash: getEventNameHash('proof_submitted'), wallet: provider.account.address },
        { name: 'escrow_completed', hash: getEventNameHash('escrow_completed'), wallet: holder.account.address },
        { name: 'escrow_completed', hash: getEventNameHash('escrow_completed'), wallet: provider.account.address },
        { name: 'dispute_created', hash: getEventNameHash('dispute_created'), wallet: holder.account.address },
        { name: 'dispute_won', hash: getEventNameHash('dispute_won'), wallet: provider.account.address },
        { name: 'dispute_lost', hash: getEventNameHash('dispute_lost'), wallet: holder.account.address },
        { name: 'escrow_cancelled', hash: getEventNameHash('escrow_cancelled'), wallet: holder.account.address }
      ];

      console.log("\nEvent verification (using event name hashes):");
      expectedEvents.forEach((expected, i) => {
        const found = capturedEvents.some(event => 
          event.eventName === expected.hash && 
          event.wallet.toLowerCase() === expected.wallet.toLowerCase()
        );
        console.log(`  ${i + 1}. ${expected.name} (${expected.wallet.slice(0, 8)}...): ${found ? '✅' : '❌'}`);
        console.log(`     Hash: ${expected.hash}`);
        assert(found, `Missing reputation event: ${expected.name} for ${expected.wallet}`);
      });

      // Verify all events came from the correct caller (deployer simulating EscrowContract)
      capturedEvents.forEach(event => {
        assert.strictEqual(
          event.caller.toLowerCase(), 
          deployer.account.address.toLowerCase(),
          `Event ${event.eventName} should be called by deployer (simulating EscrowContract)`
        );
      });

      assert.strictEqual(capturedEvents.length, expectedEvents.length, "Should capture all expected events");

      console.log("\n✅ All reputation events verified!");
      console.log("✅ ReputationIngestion contract working correctly!");
      console.log("✅ Event emission and capture mechanism functional!");

    } finally {
      unwatch();
    }

    console.log("✅ Reputation event integration test completed!");
  });

  test("🎯 INTEGRATION: Reputation Event Pause/Unpause Functionality", async () => {
    console.log("Testing reputation event pause/unpause functionality...");
    const { contracts, accounts } = await deployContracts();
    const { reputationEvents } = contracts;
    const { deployer, holder } = accounts;

    console.log("\n🔹 Testing normal operation...");
    
    // Normal operation should work
    await reputationEvents.write.event_of(["test_event", holder.account.address, "0x"], {
      account: deployer.account
    });
    console.log("✅ Normal event emission working");

    console.log("\n🔹 Testing pause functionality...");
    
    // Pause the contract
    await reputationEvents.write.pause({ account: deployer.account });
    console.log("✅ Contract paused");

    // Verify paused state
    const isPaused = await reputationEvents.read.paused();
    assert.strictEqual(isPaused, true, "Contract should be paused");

    // Events should fail while paused
    try {
      await reputationEvents.write.event_of(["test_event_paused", holder.account.address, "0x"], {
        account: deployer.account
      });
      assert.fail("Event emission should fail when paused");
    } catch (error: any) {
      console.log("✅ Event emission correctly blocked while paused");
      assert(error.message.includes("ContractIsPaused") || error.message.includes("paused"), "Should revert with paused error");
    }

    console.log("\n🔹 Testing unpause functionality...");
    
    // Unpause the contract
    await reputationEvents.write.unpause({ account: deployer.account });
    console.log("✅ Contract unpaused");

    // Verify unpaused state
    const isStillPaused = await reputationEvents.read.paused();
    assert.strictEqual(isStillPaused, false, "Contract should not be paused");

    // Events should work again after unpause
    await reputationEvents.write.event_of(["test_event_unpaused", holder.account.address, "0x"], {
      account: deployer.account
    });
    console.log("✅ Event emission working after unpause");

    console.log("\n✅ Pause/unpause functionality verified!");
    console.log("✅ ReputationIngestion administrative controls working correctly!");
    console.log("✅ Pause/unpause reputation event integration test completed!");
  });

  test("🎯 INTEGRATION: Reputation Event Metadata Handling", async () => {
    console.log("Testing reputation event metadata handling...");
    const { contracts, accounts } = await deployContracts();
    const { reputationEvents } = contracts;
    const { deployer, holder, provider } = accounts;

    // Track reputation events with metadata
    const capturedEvents: any[] = [];
    const unwatch = reputationEvents.watchEvent.ReputationEvent(
      {},
      {
        onLogs: (logs: any[]) => {
          logs.forEach(log => {
            capturedEvents.push({
              eventName: log.args.eventName,
              wallet: log.args.wallet,
              caller: log.args.caller,
              metadata: log.args.metadata,
              timestamp: log.args.timestamp
            });
          });
        }
      }
    );

    try {
      console.log("\n🔹 Testing different metadata formats...");

      // Test 1: Empty metadata
      await reputationEvents.write.event_of(["test_empty", holder.account.address, "0x"], {
        account: deployer.account
      });

      // Test 2: Simple hex metadata
      const simpleMetadata = "0xdeadbeef";
      await reputationEvents.write.event_of(["test_simple", provider.account.address, simpleMetadata], {
        account: deployer.account
      });

      // Test 3: Encoded metadata (simulating structured data)
      const encodedMetadata = encodeAbiParameters(
        [{ type: 'string' }, { type: 'uint256' }, { type: 'address' }],
        ["Transaction completed", parseEther("1.0"), holder.account.address]
      );
      await reputationEvents.write.event_of(["test_structured", provider.account.address, encodedMetadata], {
        account: deployer.account
      });

      // Wait for events
      await new Promise(resolve => setTimeout(resolve, 500));

      console.log(`\n📊 Metadata Test Results:`);
      console.log(`- Events captured: ${capturedEvents.length}`);

      // Verify all events were captured
      assert.strictEqual(capturedEvents.length, 3, "Should capture all 3 metadata test events");

      // Check each event (using event name hashes)
      const emptyEventHash = getEventNameHash('test_empty');
      const simpleEventHash = getEventNameHash('test_simple');
      const structuredEventHash = getEventNameHash('test_structured');

      const emptyEvent = capturedEvents.find(e => e.eventName === emptyEventHash);
      assert(emptyEvent, "Empty metadata event should be captured");
      assert.strictEqual(emptyEvent.metadata, "0x", "Empty metadata should be 0x");

      const simpleEvent = capturedEvents.find(e => e.eventName === simpleEventHash);
      assert(simpleEvent, "Simple metadata event should be captured");
      assert.strictEqual(simpleEvent.metadata.toLowerCase(), simpleMetadata.toLowerCase(), "Simple metadata should match");

      const structuredEvent = capturedEvents.find(e => e.eventName === structuredEventHash);
      assert(structuredEvent, "Structured metadata event should be captured");
      assert.strictEqual(structuredEvent.metadata.toLowerCase(), encodedMetadata.toLowerCase(), "Structured metadata should match");

      // Verify timestamps are reasonable (should be blockchain timestamps)
      capturedEvents.forEach(event => {
        const eventTime = Number(event.timestamp);
        assert(eventTime > 0, "Event timestamp should be positive");
        assert(eventTime < Date.now() / 1000 + 86400, "Event timestamp should not be too far in future"); // within 1 day
      });

      console.log("✅ All metadata formats handled correctly!");
      console.log("✅ Event timestamps verified!");
      console.log("✅ Metadata encoding/decoding working!");

    } finally {
      unwatch();
    }

    console.log("✅ Reputation event metadata handling test completed!");
  });

  test("🎯 INTEGRATION: Multiple Caller Simulation", async () => {
    console.log("Testing multiple callers (simulating different contracts)...");
    const { contracts, accounts } = await deployContracts();
    const { reputationEvents } = contracts;
    const { deployer, holder, provider, arbitrator } = accounts;

    // Track reputation events from multiple callers
    const capturedEvents: any[] = [];
    const unwatch = reputationEvents.watchEvent.ReputationEvent(
      {},
      {
        onLogs: (logs: any[]) => {
          logs.forEach(log => {
            capturedEvents.push({
              eventName: log.args.eventName,
              wallet: log.args.wallet,
              caller: log.args.caller,
              timestamp: log.args.timestamp
            });
          });
        }
      }
    );

    try {
      console.log("\n🔹 Simulating events from different contract addresses...");

      // Simulate events from different "contracts" (different accounts)
      // In reality, this would be EscrowContract, ArbitrationProxy, etc.

      // Deployer acts as EscrowContract
      await reputationEvents.write.event_of(["escrow_created", holder.account.address, "0x"], {
        account: deployer.account
      });

      // Arbitrator acts as ArbitrationProxy
      await reputationEvents.write.event_of(["dispute_created", provider.account.address, "0x"], {
        account: arbitrator.account
      });

      // Provider acts as another contract
      await reputationEvents.write.event_of(["custom_event", holder.account.address, "0x"], {
        account: provider.account
      });

      // Wait for events
      await new Promise(resolve => setTimeout(resolve, 500));

      console.log(`\n📊 Multiple Caller Results:`);
      console.log(`- Events captured: ${capturedEvents.length}`);

      // Verify events from different callers
      const deployerEvents = capturedEvents.filter(e => e.caller.toLowerCase() === deployer.account.address.toLowerCase());
      const arbitratorEvents = capturedEvents.filter(e => e.caller.toLowerCase() === arbitrator.account.address.toLowerCase());
      const providerEvents = capturedEvents.filter(e => e.caller.toLowerCase() === provider.account.address.toLowerCase());

      assert.strictEqual(deployerEvents.length, 1, "Should have 1 event from deployer (EscrowContract)");
      assert.strictEqual(arbitratorEvents.length, 1, "Should have 1 event from arbitrator (ArbitrationProxy)");
      assert.strictEqual(providerEvents.length, 1, "Should have 1 event from provider (custom contract)");

      // Verify caller information is preserved correctly (using event name hashes)
      const escrowCreatedHash = getEventNameHash('escrow_created');
      const disputeCreatedHash = getEventNameHash('dispute_created');
      const customEventHash = getEventNameHash('custom_event');

      assert.strictEqual(deployerEvents[0].eventName, escrowCreatedHash, "Escrow event should be from deployer");
      assert.strictEqual(arbitratorEvents[0].eventName, disputeCreatedHash, "Dispute event should be from arbitrator");
      assert.strictEqual(providerEvents[0].eventName, customEventHash, "Custom event should be from provider");

      console.log("✅ Events from multiple callers tracked correctly!");
      console.log("✅ Caller identity preserved in events!");
      console.log("✅ Multi-contract integration scenario validated!");

    } finally {
      unwatch();
    }

    console.log("✅ Multiple caller simulation test completed!");
  });
});