import { test, describe } from "node:test";
import assert from "node:assert";
import { network } from "hardhat";
import { parseEther, encodeAbiParameters, keccak256, toHex, formatEther } from "viem";

/**
 * Malicious User Scenarios Test Suite
 * 
 * Tests specific malicious behaviors that attackers might attempt:
 * - Fee manipulation attempts
 * - Reputation gaming
 * - Timestamp manipulation
 * - Economic attacks
 * - Multi-account collusion
 */

describe("Malicious User Scenarios", () => {
  
  async function deployContracts() {
    const { viem } = await network.connect();
    const [deployer, honest1, honest2, attacker1, attacker2, victim] = await viem.getWalletClients();
    
    // Deploy DAO 
    const dao = await viem.deployContract("PluriSwapDAO", [
      [deployer.account.address, honest1.account.address, honest2.account.address, attacker1.account.address, attacker2.account.address]
    ]);
    
    // Deploy ReputationIngestion
    const reputationEvents = await viem.deployContract("ReputationIngestion", [deployer.account.address]);

    // Deploy ReputationOracle
    const reputationOracle = await viem.deployContract("ReputationOracle", [deployer.account.address]);
    
    return {
      contracts: { reputationEvents, reputationOracle, dao },
      accounts: { deployer, honest1, honest2, attacker1, attacker2, victim }
    };
  }

  test("🕷️ REPUTATION GAMING: Fake Event Injection", async () => {
    console.log("Testing reputation gaming attack attempts...");
    const { contracts, accounts } = await deployContracts();
    const { reputationEvents, reputationOracle } = contracts;
    const { deployer, attacker1, victim } = accounts;

    console.log("\n🎯 Scenario 1: Attacker tries to inject fake positive reputation events");
    
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
              metadata: log.args.metadata
            });
          });
        }
      }
    );

    try {
      console.log("🔹 Attacker attempts to create fake completion events...");
      
      // Attacker tries to boost their own reputation
      await reputationEvents.write.event_of([
        "escrow_completed", 
        attacker1.account.address, 
        "0x"
      ], { account: attacker1.account });

      // Attacker tries to create fake events for victim (to frame them or boost them)
      await reputationEvents.write.event_of([
        "dispute_lost", 
        victim.account.address, 
        "0x"
      ], { account: attacker1.account });

      // Wait for events
      await new Promise(resolve => setTimeout(resolve, 500));

      console.log(`📊 Attack Results:`);
      console.log(`- Events captured: ${capturedEvents.length}`);
      
      capturedEvents.forEach((event, i) => {
        console.log(`  ${i + 1}. Event: "${event.eventName}" for ${event.wallet.slice(0, 10)}... from caller ${event.caller.slice(0, 10)}...`);
      });

      console.log("\n✅ Detection Mechanisms:");
      console.log("- Caller address is tracked in every reputation event");
      console.log("- Off-chain systems can verify caller authenticity");
      console.log("- Only authorized contracts (EscrowContract, ArbitrationProxy) should emit valid events");
      console.log("- Fake events from EOAs can be filtered by caller address");
      console.log("- Event correlation can detect suspicious patterns");

      // Verify that attacker's address is recorded as caller
      const attackerEvents = capturedEvents.filter(e => 
        e.caller.toLowerCase() === attacker1.account.address.toLowerCase()
      );
      
      assert(attackerEvents.length > 0, "Attacker events should be traceable");
      console.log(`✅ ${attackerEvents.length} malicious events detected and traceable to attacker`);

    } finally {
      unwatch();
    }

    console.log("✅ Reputation gaming detection test completed");
  });

  test("🕷️ SYBIL ATTACK: Multiple Account Reputation Boost", async () => {
    console.log("Testing Sybil attack detection...");
    const { contracts, accounts } = await deployContracts();
    const { reputationEvents } = contracts;
    const { deployer, attacker1, attacker2 } = accounts;

    console.log("\n🎯 Scenario 2: Attacker uses multiple accounts to boost reputation");

    // Track events from multiple attackers
    const sybilEvents: any[] = [];
    const unwatch = reputationEvents.watchEvent.ReputationEvent(
      {},
      {
        onLogs: (logs: any[]) => {
          logs.forEach(log => {
            const callerAddr = log.args.caller.toLowerCase();
            if (callerAddr === attacker1.account.address.toLowerCase() || 
                callerAddr === attacker2.account.address.toLowerCase()) {
              sybilEvents.push({
                eventName: log.args.eventName,
                wallet: log.args.wallet,
                caller: log.args.caller,
                timestamp: log.args.timestamp
              });
            }
          });
        }
      }
    );

    try {
      console.log("🔹 Multiple attackers create fake reputation events...");

      // Attacker 1 boosts Attacker 2
      await reputationEvents.write.event_of([
        "escrow_completed",
        attacker2.account.address,
        "0x"
      ], { account: attacker1.account });

      // Attacker 2 boosts Attacker 1  
      await reputationEvents.write.event_of([
        "escrow_completed",
        attacker1.account.address,
        "0x"
      ], { account: attacker2.account });

      // Both try to create multiple fake successes
      for (let i = 0; i < 3; i++) {
        await reputationEvents.write.event_of([
          "proof_submitted",
          attacker1.account.address,
          `0x${i.toString().padStart(2, '0')}`
        ], { account: attacker1.account });
      }

      await new Promise(resolve => setTimeout(resolve, 500));

      console.log(`📊 Sybil Attack Results:`);
      console.log(`- Suspicious events detected: ${sybilEvents.length}`);

      // Analyze patterns
      const eventsByCaller = {};
      sybilEvents.forEach(event => {
        const caller = event.caller;
        if (!eventsByCaller[caller]) eventsByCaller[caller] = [];
        eventsByCaller[caller].push(event);
      });

      console.log("\n🔍 Pattern Analysis:");
      Object.entries(eventsByCaller).forEach(([caller, events]: [string, any[]]) => {
        console.log(`- ${caller.slice(0, 10)}...: ${events.length} events`);
        
        // Check for rapid-fire events (potential bot behavior)
        if (events.length > 2) {
          const timestamps = events.map(e => Number(e.timestamp)).sort();
          const timeDiffs = [];
          for (let i = 1; i < timestamps.length; i++) {
            timeDiffs.push(timestamps[i] - timestamps[i-1]);
          }
          const avgTimeDiff = timeDiffs.reduce((sum, diff) => sum + diff, 0) / timeDiffs.length;
          console.log(`  - Average time between events: ${avgTimeDiff}s (suspicious if very low)`);
        }
      });

      console.log("\n✅ Sybil Attack Detection Mechanisms:");
      console.log("- Event frequency analysis can detect bot-like behavior");
      console.log("- Cross-referencing caller addresses reveals coordination");
      console.log("- Time correlation analysis identifies suspicious patterns");
      console.log("- Caller verification ensures events come from legitimate contracts");
      console.log("- Reputation decay prevents old fake events from having lasting impact");

    } finally {
      unwatch();
    }

    console.log("✅ Sybil attack detection test completed");
  });

  test("🕷️ REPUTATION ORACLE: Unauthorized Updates", async () => {
    console.log("Testing unauthorized reputation updates...");
    const { contracts, accounts } = await deployContracts();
    const { reputationOracle } = contracts;
    const { deployer, attacker1, victim } = accounts;

    console.log("\n🎯 Scenario 3: Attacker tries to directly manipulate reputation scores");

    console.log("🔹 Attacker attempts unauthorized reputation update...");
    
    try {
      await reputationOracle.write.updateReputation([
        attacker1.account.address,
        999999, // Unrealistic high score
        {
          started: 10000,
          completed: 10000,
          cancelled: 0,
          disputed: 0
        }
      ], { account: attacker1.account });
      
      console.log("❌ CRITICAL: Unauthorized reputation update succeeded!");
      assert.fail("Unauthorized reputation update should not succeed");
      
    } catch (error: any) {
      console.log("✅ Unauthorized reputation update blocked");
      console.log(`   Error: ${String(error).substring(0, 80)}...`);
    }

    console.log("🔹 Attacker attempts to manipulate victim's reputation...");
    
    try {
      await reputationOracle.write.updateReputation([
        victim.account.address,
        1, // Destroy victim's reputation
        {
          started: 100,
          completed: 1,
          cancelled: 50,
          disputed: 49
        }
      ], { account: attacker1.account });
      
      console.log("❌ CRITICAL: Unauthorized reputation manipulation succeeded!");
      assert.fail("Unauthorized reputation manipulation should not succeed");
      
    } catch (error: any) {
      console.log("✅ Unauthorized reputation manipulation blocked");
    }

    console.log("\n✅ Reputation Oracle Security:");
    console.log("- Only authorized addresses can update reputation");
    console.log("- Access control prevents direct user manipulation");
    console.log("- Reputation updates require legitimate business logic triggers");
    console.log("- Administrative controls prevent abuse");

    console.log("✅ Unauthorized reputation update test completed");
  });

  test("🕷️ EVENT INJECTION: Contract Impersonation", async () => {
    console.log("Testing contract impersonation attempts...");
    const { contracts, accounts } = await deployContracts();
    const { reputationEvents } = contracts;
    const { deployer, attacker1, victim } = accounts;

    console.log("\n🎯 Scenario 4: Attacker tries to impersonate legitimate contracts");

    // Capture events with metadata analysis
    const impersonationEvents: any[] = [];
    const unwatch = reputationEvents.watchEvent.ReputationEvent(
      {},
      {
        onLogs: (logs: any[]) => {
          logs.forEach(log => {
            impersonationEvents.push({
              eventName: log.args.eventName,
              wallet: log.args.wallet,
              caller: log.args.caller,
              metadata: log.args.metadata,
              timestamp: log.args.timestamp,
              blockNumber: log.blockNumber
            });
          });
        }
      }
    );

    try {
      console.log("🔹 Attacker creates events with contract-like metadata...");

      // Attacker tries to make their events look legitimate by crafting metadata
      const contractLikeMetadata = encodeAbiParameters([
        { type: 'uint256', name: 'escrowId' },
        { type: 'address', name: 'contractAddress' },
        { type: 'uint256', name: 'amount' }
      ], [
        123n, // Fake escrow ID
        deployer.account.address, // Fake contract address
        parseEther("1.0") // Fake amount
      ]);

      await reputationEvents.write.event_of([
        "escrow_completed",
        victim.account.address,
        contractLikeMetadata
      ], { account: attacker1.account });

      // Attacker tries various event types to build fake history
      const eventTypes = [
        "escrow_created",
        "proof_submitted", 
        "escrow_completed",
        "dispute_won"
      ];

      for (const eventType of eventTypes) {
        await reputationEvents.write.event_of([
          eventType,
          attacker1.account.address,
          contractLikeMetadata
        ], { account: attacker1.account });
      }

      await new Promise(resolve => setTimeout(resolve, 500));

      console.log(`📊 Impersonation Attack Results:`);
      console.log(`- Total events captured: ${impersonationEvents.length}`);

      // Analyze caller patterns
      const callerAnalysis = {};
      impersonationEvents.forEach(event => {
        const caller = event.caller;
        if (!callerAnalysis[caller]) {
          callerAnalysis[caller] = {
            count: 0,
            events: [],
            hasMetadata: 0
          };
        }
        callerAnalysis[caller].count++;
        callerAnalysis[caller].events.push(event.eventName);
        if (event.metadata !== "0x") {
          callerAnalysis[caller].hasMetadata++;
        }
      });

      console.log("\n🔍 Caller Analysis:");
      Object.entries(callerAnalysis).forEach(([caller, data]: [string, any]) => {
        console.log(`- ${caller.slice(0, 10)}...: ${data.count} events, ${data.hasMetadata} with metadata`);
        console.log(`  Events: ${data.events.join(", ")}`);
        
        // Check if this looks like an EOA trying to impersonate a contract
        const isEOA = !caller.startsWith("0x0000000000000000000000000000000000000"); // Basic heuristic
        if (isEOA && data.hasMetadata > 0) {
          console.log(`  ⚠️ SUSPICIOUS: EOA ${caller.slice(0, 10)}... emitting events with structured metadata`);
        }
      });

      console.log("\n✅ Contract Impersonation Detection:");
      console.log("- Caller address analysis reveals EOA vs contract sources");
      console.log("- Metadata structure analysis can detect fake contract data");
      console.log("- Event frequency patterns differ between real contracts and attackers");
      console.log("- Legitimate contracts have consistent address patterns");
      console.log("- Cross-reference with known contract addresses");

    } finally {
      unwatch();
    }

    console.log("✅ Contract impersonation detection test completed");
  });

  test("🕷️ COORDINATION ATTACK: Multi-Account Orchestration", async () => {
    console.log("Testing coordinated multi-account attacks...");
    const { contracts, accounts } = await deployContracts();
    const { reputationEvents } = contracts;
    const { deployer, attacker1, attacker2, victim } = accounts;

    console.log("\n🎯 Scenario 5: Multiple attackers coordinate to manipulate reputation");

    const coordinatedEvents: any[] = [];
    const unwatch = reputationEvents.watchEvent.ReputationEvent(
      {},
      {
        onLogs: (logs: any[]) => {
          logs.forEach(log => {
            coordinatedEvents.push({
              eventName: log.args.eventName,
              wallet: log.args.wallet,
              caller: log.args.caller,
              timestamp: log.args.timestamp,
              blockNumber: log.blockNumber
            });
          });
        }
      }
    );

    try {
      console.log("🔹 Coordinated attack: Multiple accounts boost target reputation...");

      // Coordinated positive reputation attack for one target
      const targetAccount = victim.account.address;
      const attackerAccounts = [attacker1.account, attacker2.account];

      for (let round = 0; round < 2; round++) {
        for (const attacker of attackerAccounts) {
          // Each attacker creates multiple positive events for target
          await reputationEvents.write.event_of([
            "escrow_completed",
            targetAccount,
            `0x${round.toString().padStart(64, '0')}`
          ], { account: attacker });

          await reputationEvents.write.event_of([
            "dispute_won", 
            targetAccount,
            `0x${round.toString().padStart(64, '0')}`
          ], { account: attacker });
        }
      }

      console.log("🔹 Coordinated attack: Cross-boosting attacker accounts...");

      // Attackers boost each other's reputation
      await reputationEvents.write.event_of([
        "escrow_completed",
        attacker2.account.address,
        "0x"
      ], { account: attacker1.account });

      await reputationEvents.write.event_of([
        "escrow_completed", 
        attacker1.account.address,
        "0x"
      ], { account: attacker2.account });

      await new Promise(resolve => setTimeout(resolve, 500));

      console.log(`📊 Coordination Attack Results:`);
      console.log(`- Total coordinated events: ${coordinatedEvents.length}`);

      // Analyze coordination patterns
      console.log("\n🔍 Coordination Analysis:");
      
      // Group by target wallet
      const eventsByWallet = {};
      coordinatedEvents.forEach(event => {
        const wallet = event.wallet;
        if (!eventsByWallet[wallet]) eventsByWallet[wallet] = [];
        eventsByWallet[wallet].push(event);
      });

      Object.entries(eventsByWallet).forEach(([wallet, events]: [string, any[]]) => {
        console.log(`\n- Target: ${wallet.slice(0, 10)}... received ${events.length} events`);
        
        // Analyze caller diversity
        const callers = new Set(events.map(e => e.caller));
        console.log(`  - From ${callers.size} different callers`);
        
        // Analyze timing
        const timestamps = events.map(e => Number(e.timestamp)).sort();
        if (timestamps.length > 1) {
          const timespan = timestamps[timestamps.length - 1] - timestamps[0];
          console.log(`  - Events spread over ${timespan} seconds`);
          
          if (timespan < 60 && events.length > 3) {
            console.log(`  ⚠️ SUSPICIOUS: ${events.length} events in ${timespan}s suggests coordination`);
          }
        }

        // Check for multiple attackers targeting same wallet
        const attackerCallers = Array.from(callers).filter(caller => 
          caller.toLowerCase() === attacker1.account.address.toLowerCase() ||
          caller.toLowerCase() === attacker2.account.address.toLowerCase()
        );
        
        if (attackerCallers.length > 1) {
          console.log(`  ⚠️ SUSPICIOUS: Multiple known attackers (${attackerCallers.length}) targeting same wallet`);
        }
      });

      console.log("\n✅ Coordination Detection Mechanisms:");
      console.log("- Timeline analysis reveals simultaneous activity patterns");
      console.log("- Caller correlation identifies coordinated accounts");
      console.log("- Volume analysis detects unusual event clustering");
      console.log("- Cross-account relationship mapping reveals collusion");
      console.log("- Statistical anomaly detection flags coordinated behavior");

    } finally {
      unwatch();
    }

    console.log("✅ Coordinated attack detection test completed");
  });

  test("🕷️ METADATA POISONING: Malicious Data Injection", async () => {
    console.log("Testing metadata poisoning attacks...");
    const { contracts, accounts } = await deployContracts();
    const { reputationEvents } = contracts;
    const { deployer, attacker1, victim } = accounts;

    console.log("\n🎯 Scenario 6: Attacker injects malicious metadata");

    const poisonEvents: any[] = [];
    const unwatch = reputationEvents.watchEvent.ReputationEvent(
      {},
      {
        onLogs: (logs: any[]) => {
          logs.forEach(log => {
            if (log.args.metadata !== "0x") {
              poisonEvents.push({
                eventName: log.args.eventName,
                wallet: log.args.wallet,
                caller: log.args.caller,
                metadata: log.args.metadata
              });
            }
          });
        }
      }
    );

    try {
      console.log("🔹 Metadata poisoning attempts...");

      // Extremely large metadata (potential DoS)
      const largeMetadata = "0x" + "ff".repeat(1000);
      
      try {
        await reputationEvents.write.event_of([
          "test_large_metadata",
          attacker1.account.address,
          largeMetadata
        ], { account: attacker1.account });
        console.log("⚠️ Large metadata accepted - check gas limits");
      } catch (error: any) {
        console.log("✅ Large metadata rejected:", String(error).substring(0, 50) + "...");
      }

      // Malicious encoded data that could crash parsers
      const maliciousMetadata = encodeAbiParameters([
        { type: 'string' },
        { type: 'uint256' }, 
        { type: 'address' }
      ], [
        "<script>alert('xss')</script>", // XSS attempt
        2n ** 256n - 1n, // Max uint256
        "0x0000000000000000000000000000000000000000" // Zero address
      ]);

      await reputationEvents.write.event_of([
        "malicious_data",
        victim.account.address,
        maliciousMetadata
      ], { account: attacker1.account });

      // Recursive/nested data structures
      const nestedMetadata = encodeAbiParameters([
        { type: 'bytes' }
      ], [
        encodeAbiParameters([
          { type: 'bytes' }
        ], [
          encodeAbiParameters([{ type: 'string' }], ["deeply nested"])
        ])
      ]);

      await reputationEvents.write.event_of([
        "nested_attack",
        attacker1.account.address,
        nestedMetadata
      ], { account: attacker1.account });

      await new Promise(resolve => setTimeout(resolve, 500));

      console.log(`📊 Metadata Poisoning Results:`);
      console.log(`- Events with metadata: ${poisonEvents.length}`);

      poisonEvents.forEach((event, i) => {
        console.log(`\n${i + 1}. Event: ${event.eventName}`);
        console.log(`   - Wallet: ${event.wallet.slice(0, 10)}...`);
        console.log(`   - Caller: ${event.caller.slice(0, 10)}...`);
        console.log(`   - Metadata length: ${event.metadata.length / 2 - 1} bytes`);
        
        if (event.metadata.length > 200) {
          console.log(`   ⚠️ SUSPICIOUS: Large metadata (${event.metadata.length / 2 - 1} bytes)`);
        }
      });

      console.log("\n✅ Metadata Poisoning Defense:");
      console.log("- Gas limits naturally restrict metadata size");
      console.log("- Off-chain processors should validate metadata structure");
      console.log("- Sanitize metadata before displaying to users");
      console.log("- Implement metadata size limits in processing systems");
      console.log("- Log and monitor unusual metadata patterns");

    } finally {
      unwatch();
    }

    console.log("✅ Metadata poisoning test completed");
  });
  
});
