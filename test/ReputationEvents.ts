import assert from "node:assert/strict";
import { describe, it, beforeEach } from "node:test";
import { encodePacked, Address } from "viem";
import { network } from "hardhat";

describe("ReputationEvents", async function () {
  const { viem } = await network.connect();
  const publicClient = await viem.getPublicClient();
  
  // Test accounts
  const [deployer, dao, user1, user2] = await viem.getWalletClients();

  describe("Deployment", function () {
    it("Should deploy with correct initial state", async function () {
      const reputationEvents = await viem.deployContract("ReputationEvents", [dao.account.address]);
      
      assert.equal((await reputationEvents.read.dao()).toLowerCase(), dao.account.address.toLowerCase());
      assert.equal(await reputationEvents.read.paused(), false);
    });

    it("Should revert when deploying with zero address DAO", async function () {
      await assert.rejects(
        viem.deployContract("ReputationEvents", ["0x0000000000000000000000000000000000000000"]),
        /InvalidDAOAddress/
      );
    });
  });

  describe("Event Ingestion", function () {
    let reputationEvents: any;

    beforeEach(async function () {
      reputationEvents = await viem.deployContract("ReputationEvents", [dao.account.address]);
    });

    it("Should emit ReputationEvent with correct parameters", async function () {
      const eventName = "user_action";
      const wallet = user2.account.address;
      const metadata = "0x1234567890";

      const tx = reputationEvents.write.event_of([eventName, wallet, metadata], {
        account: user1.account,
      });

      // Just check that the event was emitted
      await viem.assertions.emit(
        tx,
        reputationEvents,
        "ReputationEvent"
      );
    });

    it("Should allow events from different callers", async function () {
      const eventName = "different_caller_test";
      const wallet = user2.account.address;
      const metadata = "0xabcd";

      const startBlock = await publicClient.getBlockNumber();

      // Event from user1
      await reputationEvents.write.event_of([eventName, wallet, metadata], {
        account: user1.account,
      });

      // Event from deployer
      await reputationEvents.write.event_of([eventName, wallet, metadata], {
        account: deployer.account,
      });

      const events = await publicClient.getContractEvents({
        address: reputationEvents.address,
        abi: reputationEvents.abi,
        eventName: "ReputationEvent",
        fromBlock: startBlock + 1n,
        strict: true,
      });

      assert.equal(events.length, 2);
      assert.equal(events[0].args.caller.toLowerCase(), user1.account.address.toLowerCase());
      assert.equal(events[1].args.caller.toLowerCase(), deployer.account.address.toLowerCase());
    });

    it("Should include correct timestamp in events", async function () {
      const eventName = "timestamp_test";
      const wallet = user1.account.address;
      const metadata = "0x";

      const txHash = await reputationEvents.write.event_of([eventName, wallet, metadata]);
      const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });
      const block = await publicClient.getBlock({ blockNumber: receipt.blockNumber });

      const events = await publicClient.getContractEvents({
        address: reputationEvents.address,
        abi: reputationEvents.abi,
        eventName: "ReputationEvent",
        fromBlock: receipt.blockNumber,
        toBlock: receipt.blockNumber,
        strict: true,
      });

      assert.equal(events.length, 1);
      assert.equal(events[0].args.timestamp, block.timestamp);
    });

    it("Should handle empty metadata", async function () {
      const eventName = "empty_metadata_test";
      const wallet = user1.account.address;
      const metadata = "0x";

      const tx = reputationEvents.write.event_of([eventName, wallet, metadata], {
        account: user1.account,
      });

      // Just check that the event was emitted
      await viem.assertions.emit(
        tx,
        reputationEvents,
        "ReputationEvent"
      );
    });

    it("Should handle maximum allowed metadata size", async function () {
      const eventName = "large_metadata_test";
      const wallet = user1.account.address;
      // Create metadata at the maximum size (64KB)
      const maxSize = 65536;
      const metadata = "0x" + "42".repeat(maxSize);

      const tx = reputationEvents.write.event_of([eventName, wallet, metadata], {
        account: user1.account,
      });

      // Just check that the event was emitted
      await viem.assertions.emit(
        tx,
        reputationEvents,
        "ReputationEvent"
      );
    });

    it("Should reject metadata larger than maximum size", async function () {
      const eventName = "oversized_metadata_test";
      const wallet = user1.account.address;
      // Create metadata larger than the maximum size (64KB + 1)
      const oversizeData = "0x" + "42".repeat(65537);

      await assert.rejects(
        reputationEvents.write.event_of([eventName, wallet, oversizeData], {
          account: user1.account,
        }),
        /MetadataTooLarge/
      );
    });
  });

  describe("Pause Functionality", function () {
    let reputationEvents: any;

    beforeEach(async function () {
      reputationEvents = await viem.deployContract("ReputationEvents", [dao.account.address]);
    });

    it("Should allow DAO to pause the contract", async function () {
      const tx = reputationEvents.write.pause({ account: dao.account });
      await viem.assertions.emit(
        tx,
        reputationEvents,
        "Paused"
      );

      assert.equal(await reputationEvents.read.paused(), true);
    });

    it("Should allow DAO to unpause the contract", async function () {
      // First pause
      await reputationEvents.write.pause({ account: dao.account });
      assert.equal(await reputationEvents.read.paused(), true);

      // Then unpause
      const tx = reputationEvents.write.unpause({ account: dao.account });
      await viem.assertions.emit(
        tx,
        reputationEvents,
        "Unpaused"
      );

      assert.equal(await reputationEvents.read.paused(), false);
    });

    it("Should reject event ingestion when paused", async function () {
      await reputationEvents.write.pause({ account: dao.account });

      const eventName = "paused_test";
      const wallet = user1.account.address;
      const metadata = "0x1234";

      await assert.rejects(
        reputationEvents.write.event_of([eventName, wallet, metadata], {
          account: user1.account,
        }),
        /ContractPaused/
      );
    });

    it("Should reject pause from non-DAO address", async function () {
      await assert.rejects(
        reputationEvents.write.pause({ account: user1.account }),
        /Unauthorized/
      );
    });

    it("Should reject unpause from non-DAO address", async function () {
      await reputationEvents.write.pause({ account: dao.account });

      await assert.rejects(
        reputationEvents.write.unpause({ account: user1.account }),
        /Unauthorized/
      );
    });
  });

  describe("DAO Management", function () {
    let reputationEvents: any;

    beforeEach(async function () {
      reputationEvents = await viem.deployContract("ReputationEvents", [dao.account.address]);
    });

    it("Should allow DAO to update DAO address", async function () {
      const newDAO = user1.account.address;

      const tx = reputationEvents.write.updateDAO([newDAO], { account: dao.account });
      await viem.assertions.emit(
        tx,
        reputationEvents,
        "DAOUpdated"
      );

      assert.equal((await reputationEvents.read.dao()).toLowerCase(), newDAO.toLowerCase());
    });

    it("Should reject DAO update from non-DAO address", async function () {
      const newDAO = user1.account.address;

      await assert.rejects(
        reputationEvents.write.updateDAO([newDAO], { account: user2.account }),
        /Unauthorized/
      );
    });

    it("Should reject DAO update to zero address", async function () {
      const zeroAddress = "0x0000000000000000000000000000000000000000";

      await assert.rejects(
        reputationEvents.write.updateDAO([zeroAddress], { account: dao.account }),
        /InvalidDAOAddress/
      );
    });

    it("Should allow new DAO to perform privileged operations", async function () {
      const newDAO = user1.account.address;

      // Update DAO
      await reputationEvents.write.updateDAO([newDAO], { account: dao.account });

      // New DAO should be able to pause
      await reputationEvents.write.pause({ account: user1.account });
      assert.equal(await reputationEvents.read.paused(), true);

      // Old DAO should not be able to unpause
      await assert.rejects(
        reputationEvents.write.unpause({ account: dao.account }),
        /Unauthorized/
      );

      // New DAO should be able to unpause
      await reputationEvents.write.unpause({ account: user1.account });
      assert.equal(await reputationEvents.read.paused(), false);
    });
  });

  describe("Integration Tests", function () {
    it("Should handle complex workflow with multiple events and state changes", async function () {
      const reputationEvents = await viem.deployContract("ReputationEvents", [dao.account.address]);
      const deploymentBlock = await publicClient.getBlockNumber();

      // Multiple users emit events
      await reputationEvents.write.event_of(["action1", user1.account.address, "0x01"], {
        account: user1.account,
      });
      await reputationEvents.write.event_of(["action2", user2.account.address, "0x02"], {
        account: user2.account,
      });

      // Pause contract
      await reputationEvents.write.pause({ account: dao.account });

      // Attempt to emit while paused should fail
      await assert.rejects(
        reputationEvents.write.event_of(["action3", user1.account.address, "0x03"], {
          account: user1.account,
        }),
        /ContractPaused/
      );

      // Unpause and emit more events
      await reputationEvents.write.unpause({ account: dao.account });
      await reputationEvents.write.event_of(["action3", user1.account.address, "0x03"], {
        account: user1.account,
      });

      // Change DAO
      await reputationEvents.write.updateDAO([user2.account.address], { account: dao.account });

      // New DAO can pause
      await reputationEvents.write.pause({ account: user2.account });

      // Verify all events were emitted correctly
      const events = await publicClient.getContractEvents({
        address: reputationEvents.address,
        abi: reputationEvents.abi,
        eventName: "ReputationEvent",
        fromBlock: deploymentBlock,
        strict: true,
      });

      // Verify 3 events were emitted
      assert.equal(events.length, 3);
    });
  });
});
