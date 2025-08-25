import assert from "node:assert/strict";
import { describe, it, beforeEach } from "node:test";
import { network } from "hardhat";
import { Address, decodeAbiParameters } from "viem";

describe("ReputationOracle", async function () {
  const { viem } = await network.connect();
  const publicClient = await viem.getPublicClient();
  
  // Test accounts
  const [deployer, dao, trustedParty1, trustedParty2, user1, user2, unauthorized] = await viem.getWalletClients();

  // Valid test data for reputation scores
  const validScoreData: bigint[] = [
    100n, // started
    95n,  // completed
    3n,   // cancelled
    2n,   // disputed
    1n,   // disputesWon
    1n,   // disputesLost
    1000000n, // volumeStarted
    950000n,  // volumeCompleted
    750n, // score
    BigInt(Math.floor(Date.now() / 1000)), // lastUpdated
    1n    // isActive
  ];

  describe("Deployment", function () {
    it("Should deploy with correct initial state", async function () {
      const oracle = await viem.deployContract("ReputationOracle", [dao.account.address]);
      
      assert.equal((await oracle.read.dao()).toLowerCase(), dao.account.address.toLowerCase());
      assert.equal(await oracle.read.paused(), false);
    });

    it("Should revert when deploying with zero address DAO", async function () {
      await assert.rejects(
        viem.deployContract("ReputationOracle", ["0x0000000000000000000000000000000000000000"]),
        /InvalidDAOAddress/
      );
    });
  });

  describe("Access Control", function () {
    let oracle: any;

    beforeEach(async function () {
      oracle = await viem.deployContract("ReputationOracle", [dao.account.address]);
    });

    it("Should allow DAO to add trusted parties", async function () {
      const tx = oracle.write.addTrustedParty([trustedParty1.account.address], {
        account: dao.account,
      });

      await viem.assertions.emit(tx, oracle, "TrustedPartyAdded");
      
      assert.equal(await oracle.read.isTrustedParty([trustedParty1.account.address]), true);
      assert.equal(await oracle.read.trustedParties([trustedParty1.account.address]), true);
    });

    it("Should allow DAO to remove trusted parties", async function () {
      // First add a trusted party
      await oracle.write.addTrustedParty([trustedParty1.account.address], {
        account: dao.account,
      });
      
      // Then remove it
      const tx = oracle.write.removeTrustedParty([trustedParty1.account.address], {
        account: dao.account,
      });

      await viem.assertions.emit(tx, oracle, "TrustedPartyRemoved");
      
      assert.equal(await oracle.read.isTrustedParty([trustedParty1.account.address]), false);
    });

    it("Should reject adding trusted party from non-DAO address", async function () {
      await assert.rejects(
        oracle.write.addTrustedParty([trustedParty1.account.address], {
          account: unauthorized.account,
        }),
        /Unauthorized/
      );
    });

    it("Should reject removing trusted party from non-DAO address", async function () {
      await oracle.write.addTrustedParty([trustedParty1.account.address], {
        account: dao.account,
      });

      await assert.rejects(
        oracle.write.removeTrustedParty([trustedParty1.account.address], {
          account: unauthorized.account,
        }),
        /Unauthorized/
      );
    });

    it("Should reject adding zero address as trusted party", async function () {
      await assert.rejects(
        oracle.write.addTrustedParty(["0x0000000000000000000000000000000000000000"], {
          account: dao.account,
        }),
        /InvalidWalletAddress/
      );
    });

    it("Should reject adding already trusted party", async function () {
      await oracle.write.addTrustedParty([trustedParty1.account.address], {
        account: dao.account,
      });

      await assert.rejects(
        oracle.write.addTrustedParty([trustedParty1.account.address], {
          account: dao.account,
        }),
        /PartyAlreadyTrusted/
      );
    });

    it("Should reject removing non-trusted party", async function () {
      await assert.rejects(
        oracle.write.removeTrustedParty([trustedParty1.account.address], {
          account: dao.account,
        }),
        /PartyNotTrusted/
      );
    });
  });

  describe("Pause Functionality", function () {
    let oracle: any;

    beforeEach(async function () {
      oracle = await viem.deployContract("ReputationOracle", [dao.account.address]);
      // Add a trusted party for testing
      await oracle.write.addTrustedParty([trustedParty1.account.address], {
        account: dao.account,
      });
    });

    it("Should allow DAO to pause the contract", async function () {
      const tx = oracle.write.pause({ account: dao.account });
      await viem.assertions.emit(tx, oracle, "Paused");

      assert.equal(await oracle.read.paused(), true);
    });

    it("Should allow DAO to unpause the contract", async function () {
      await oracle.write.pause({ account: dao.account });
      
      const tx = oracle.write.unpause({ account: dao.account });
      await viem.assertions.emit(tx, oracle, "Unpaused");

      assert.equal(await oracle.read.paused(), false);
    });

    it("Should reject score loading when paused", async function () {
      await oracle.write.pause({ account: dao.account });

      await assert.rejects(
        oracle.write.load([user1.account.address, validScoreData], {
          account: trustedParty1.account,
        }),
        /ContractPaused/
      );
    });

    it("Should reject batch loading when paused", async function () {
      await oracle.write.pause({ account: dao.account });

      await assert.rejects(
        oracle.write.batchLoad([[user1.account.address], [validScoreData]], {
          account: trustedParty1.account,
        }),
        /ContractPaused/
      );
    });

    it("Should reject pause from non-DAO address", async function () {
      await assert.rejects(
        oracle.write.pause({ account: unauthorized.account }),
        /Unauthorized/
      );
    });
  });

  describe("Score Loading", function () {
    let oracle: any;

    beforeEach(async function () {
      oracle = await viem.deployContract("ReputationOracle", [dao.account.address]);
      await oracle.write.addTrustedParty([trustedParty1.account.address], {
        account: dao.account,
      });
    });

    it("Should allow DAO to load scores", async function () {
      const tx = oracle.write.load([user1.account.address, validScoreData], {
        account: dao.account,
      });

      await viem.assertions.emit(tx, oracle, "ScoreLoaded");
    });

    it("Should allow trusted party to load scores", async function () {
      const tx = oracle.write.load([user1.account.address, validScoreData], {
        account: trustedParty1.account,
      });

      await viem.assertions.emit(tx, oracle, "ScoreLoaded");
    });

    it("Should reject score loading from unauthorized party", async function () {
      await assert.rejects(
        oracle.write.load([user1.account.address, validScoreData], {
          account: unauthorized.account,
        }),
        /Unauthorized/
      );
    });

    it("Should store and return correct score data", async function () {
      await oracle.write.load([user1.account.address, validScoreData], {
        account: trustedParty1.account,
      });

      const encodedScore = await oracle.read.score_of([user1.account.address]);
      
      // Decode the returned data
      const decodedData = decodeAbiParameters(
        [
          { name: 'started', type: 'uint256' },
          { name: 'completed', type: 'uint256' },
          { name: 'cancelled', type: 'uint256' },
          { name: 'disputed', type: 'uint256' },
          { name: 'disputesWon', type: 'uint256' },
          { name: 'disputesLost', type: 'uint256' },
          { name: 'volumeStarted', type: 'uint256' },
          { name: 'volumeCompleted', type: 'uint256' },
          { name: 'score', type: 'uint256' },
          { name: 'lastUpdated', type: 'uint256' },
          { name: 'isActive', type: 'bool' }
        ],
        encodedScore
      );

      assert.equal(decodedData[0], validScoreData[0]); // started
      assert.equal(decodedData[1], validScoreData[1]); // completed
      assert.equal(decodedData[8], validScoreData[8]); // score
      assert.equal(decodedData[10], true); // isActive
    });

    it("Should return correct wallet info", async function () {
      await oracle.write.load([user1.account.address, validScoreData], {
        account: trustedParty1.account,
      });

      const [score, isActive, lastUpdated] = await oracle.read.getWalletInfo([user1.account.address]);
      
      assert.equal(score, validScoreData[8]); // score
      assert.equal(isActive, true);
      assert.equal(lastUpdated, validScoreData[9]); // lastUpdated
    });

    it("Should return empty data for non-existent wallet", async function () {
      const [score, isActive, lastUpdated] = await oracle.read.getWalletInfo([user2.account.address]);
      
      assert.equal(score, 0n);
      assert.equal(isActive, false);
      assert.equal(lastUpdated, 0n);
    });
  });

  describe("Batch Loading", function () {
    let oracle: any;

    beforeEach(async function () {
      oracle = await viem.deployContract("ReputationOracle", [dao.account.address]);
      await oracle.write.addTrustedParty([trustedParty1.account.address], {
        account: dao.account,
      });
    });

    it("Should allow batch loading multiple scores", async function () {
      const validScoreData2: bigint[] = [
        50n, 45n, 2n, 1n, 1n, 0n, 500000n, 450000n, 650n,
        BigInt(Math.floor(Date.now() / 1000)), 1n
      ];

      const wallets = [user1.account.address, user2.account.address];
      const scores = [validScoreData, validScoreData2];

      const tx = oracle.write.batchLoad([wallets, scores], {
        account: trustedParty1.account,
      });

      await viem.assertions.emit(tx, oracle, "BatchScoreLoaded");

      // Verify both wallets have scores
      const [score1] = await oracle.read.getWalletInfo([user1.account.address]);
      const [score2] = await oracle.read.getWalletInfo([user2.account.address]);
      
      assert.equal(score1, validScoreData[8]);
      assert.equal(score2, validScoreData2[8]);
    });

    it("Should reject batch loading with mismatched array lengths", async function () {
      const wallets = [user1.account.address, user2.account.address];
      const scores = [validScoreData]; // Only one score for two wallets

      await assert.rejects(
        oracle.write.batchLoad([wallets, scores], {
          account: trustedParty1.account,
        }),
        /ArrayLengthMismatch/
      );
    });

    it("Should handle empty batch loading", async function () {
      // Empty arrays should not revert but also do nothing
      await oracle.write.batchLoad([[], []], {
        account: trustedParty1.account,
      });
    });

    it("Should reject batch loading from unauthorized party", async function () {
      const wallets = [user1.account.address];
      const scores = [validScoreData];

      await assert.rejects(
        oracle.write.batchLoad([wallets, scores], {
          account: unauthorized.account,
        }),
        /Unauthorized/
      );
    });
  });

  describe("Data Validation", function () {
    let oracle: any;

    beforeEach(async function () {
      oracle = await viem.deployContract("ReputationOracle", [dao.account.address]);
      await oracle.write.addTrustedParty([trustedParty1.account.address], {
        account: dao.account,
      });
    });

    it("Should reject loading scores for zero address", async function () {
      await assert.rejects(
        oracle.write.load(["0x0000000000000000000000000000000000000000", validScoreData], {
          account: trustedParty1.account,
        }),
        /InvalidWalletAddress/
      );
    });

    it("Should reject invalid score (> 1000)", async function () {
      const invalidScoreData = [...validScoreData];
      invalidScoreData[8] = 1001n; // Invalid score

      await assert.rejects(
        oracle.write.load([user1.account.address, invalidScoreData], {
          account: trustedParty1.account,
        }),
        /InvalidScore/
      );
    });

    it("Should reject when completed > started", async function () {
      const invalidScoreData = [...validScoreData];
      invalidScoreData[0] = 90n; // started
      invalidScoreData[1] = 95n; // completed > started

      await assert.rejects(
        oracle.write.load([user1.account.address, invalidScoreData], {
          account: trustedParty1.account,
        }),
        /InvalidCounterRelationship/
      );
    });

    it("Should reject when disputed > started", async function () {
      const invalidScoreData = [...validScoreData];
      invalidScoreData[0] = 90n; // started
      invalidScoreData[3] = 95n; // disputed > started

      await assert.rejects(
        oracle.write.load([user1.account.address, invalidScoreData], {
          account: trustedParty1.account,
        }),
        /InvalidCounterRelationship/
      );
    });

    it("Should reject when cancelled > started", async function () {
      const invalidScoreData = [...validScoreData];
      invalidScoreData[0] = 90n; // started
      invalidScoreData[2] = 95n; // cancelled > started

      await assert.rejects(
        oracle.write.load([user1.account.address, invalidScoreData], {
          account: trustedParty1.account,
        }),
        /InvalidCounterRelationship/
      );
    });

    it("Should reject when volumeCompleted > volumeStarted", async function () {
      const invalidScoreData = [...validScoreData];
      invalidScoreData[6] = 900000n; // volumeStarted
      invalidScoreData[7] = 950000n; // volumeCompleted > volumeStarted

      await assert.rejects(
        oracle.write.load([user1.account.address, invalidScoreData], {
          account: trustedParty1.account,
        }),
        /InvalidVolumeRelationship/
      );
    });

    it("Should reject when disputesWon + disputesLost > disputed", async function () {
      const invalidScoreData = [...validScoreData];
      invalidScoreData[3] = 5n;  // disputed
      invalidScoreData[4] = 3n;  // disputesWon
      invalidScoreData[5] = 3n;  // disputesLost (3+3 > 5)

      await assert.rejects(
        oracle.write.load([user1.account.address, invalidScoreData], {
          account: trustedParty1.account,
        }),
        /InvalidDisputeRelationship/
      );
    });

    it("Should accept valid edge case data", async function () {
      const edgeCaseData: bigint[] = [
        0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n, // All zeros
        BigInt(Math.floor(Date.now() / 1000)), 0n // timestamp, inactive
      ];

      await oracle.write.load([user1.account.address, edgeCaseData], {
        account: trustedParty1.account,
      });

      const [score, isActive] = await oracle.read.getWalletInfo([user1.account.address]);
      assert.equal(score, 0n);
      assert.equal(isActive, false);
    });

    it("Should accept maximum valid score", async function () {
      const maxScoreData = [...validScoreData];
      maxScoreData[8] = 1000n; // Maximum valid score

      await oracle.write.load([user1.account.address, maxScoreData], {
        account: trustedParty1.account,
      });

      const [score] = await oracle.read.getWalletInfo([user1.account.address]);
      assert.equal(score, 1000n);
    });
  });

  describe("DAO Management", function () {
    let oracle: any;

    beforeEach(async function () {
      oracle = await viem.deployContract("ReputationOracle", [dao.account.address]);
    });

    it("Should allow DAO to update DAO address", async function () {
      const newDAO = user1.account.address;

      const tx = oracle.write.updateDAO([newDAO], { account: dao.account });
      await viem.assertions.emit(tx, oracle, "DAOUpdated");

      assert.equal((await oracle.read.dao()).toLowerCase(), newDAO.toLowerCase());
    });

    it("Should reject DAO update from non-DAO address", async function () {
      await assert.rejects(
        oracle.write.updateDAO([user1.account.address], { account: unauthorized.account }),
        /Unauthorized/
      );
    });

    it("Should reject DAO update to zero address", async function () {
      await assert.rejects(
        oracle.write.updateDAO(["0x0000000000000000000000000000000000000000"], { account: dao.account }),
        /InvalidDAOAddress/
      );
    });

    it("Should allow new DAO to perform privileged operations", async function () {
      const newDAO = user1.account.address;

      // Update DAO
      await oracle.write.updateDAO([newDAO], { account: dao.account });

      // New DAO should be able to add trusted parties
      await oracle.write.addTrustedParty([trustedParty1.account.address], {
        account: user1.account,
      });

      // Old DAO should not be able to add trusted parties
      await assert.rejects(
        oracle.write.addTrustedParty([trustedParty2.account.address], {
          account: dao.account,
        }),
        /Unauthorized/
      );
    });
  });

  describe("Score Reading", function () {
    let oracle: any;

    beforeEach(async function () {
      oracle = await viem.deployContract("ReputationOracle", [dao.account.address]);
      await oracle.write.addTrustedParty([trustedParty1.account.address], {
        account: dao.account,
      });
    });

    it("Should allow anyone to read scores", async function () {
      // Load a score
      await oracle.write.load([user1.account.address, validScoreData], {
        account: trustedParty1.account,
      });

      // Anyone should be able to read it
      const encodedScore1 = await oracle.read.score_of([user1.account.address], {
        account: unauthorized.account,
      });
      const encodedScore2 = await oracle.read.score_of([user1.account.address], {
        account: user2.account,
      });

      assert.equal(encodedScore1, encodedScore2);
    });

    it("Should return consistent data structure", async function () {
      await oracle.write.load([user1.account.address, validScoreData], {
        account: trustedParty1.account,
      });

      const encodedScore = await oracle.read.score_of([user1.account.address]);
      
      // Should be able to decode successfully
      const decodedData = decodeAbiParameters(
        [
          { name: 'started', type: 'uint256' },
          { name: 'completed', type: 'uint256' },
          { name: 'cancelled', type: 'uint256' },
          { name: 'disputed', type: 'uint256' },
          { name: 'disputesWon', type: 'uint256' },
          { name: 'disputesLost', type: 'uint256' },
          { name: 'volumeStarted', type: 'uint256' },
          { name: 'volumeCompleted', type: 'uint256' },
          { name: 'score', type: 'uint256' },
          { name: 'lastUpdated', type: 'uint256' },
          { name: 'isActive', type: 'bool' }
        ],
        encodedScore
      );

      assert.equal(decodedData.length, 11);
    });
  });

  describe("Integration Tests", function () {
    it("Should handle complex workflow with multiple operations", async function () {
      const oracle = await viem.deployContract("ReputationOracle", [dao.account.address]);
      const deploymentBlock = await publicClient.getBlockNumber();

      // Add multiple trusted parties
      await oracle.write.addTrustedParty([trustedParty1.account.address], {
        account: dao.account,
      });
      await oracle.write.addTrustedParty([trustedParty2.account.address], {
        account: dao.account,
      });

      // Load scores from different trusted parties
      await oracle.write.load([user1.account.address, validScoreData], {
        account: trustedParty1.account,
      });

      const validScoreData2: bigint[] = [
        50n, 45n, 2n, 1n, 1n, 0n, 500000n, 450000n, 650n,
        BigInt(Math.floor(Date.now() / 1000)), 1n
      ];

      await oracle.write.load([user2.account.address, validScoreData2], {
        account: trustedParty2.account,
      });

      // Batch load more scores
      const validScoreData3: bigint[] = [
        25n, 20n, 3n, 2n, 1n, 1n, 250000n, 200000n, 500n,
        BigInt(Math.floor(Date.now() / 1000)), 1n
      ];

      await oracle.write.batchLoad(
        [[deployer.account.address], [validScoreData3]], 
        { account: trustedParty1.account }
      );

      // Pause contract
      await oracle.write.pause({ account: dao.account });

      // Attempt operations while paused should fail
      await assert.rejects(
        oracle.write.load([unauthorized.account.address, validScoreData], {
          account: trustedParty1.account,
        }),
        /ContractPaused/
      );

      // Unpause and continue
      await oracle.write.unpause({ account: dao.account });

      // Change DAO
      await oracle.write.updateDAO([user1.account.address], { account: dao.account });

      // Old DAO can't operate, new DAO can
      await assert.rejects(
        oracle.write.pause({ account: dao.account }),
        /Unauthorized/
      );

      await oracle.write.pause({ account: user1.account });

      // Verify all scores are accessible
      const [score1] = await oracle.read.getWalletInfo([user1.account.address]);
      const [score2] = await oracle.read.getWalletInfo([user2.account.address]);
      const [score3] = await oracle.read.getWalletInfo([deployer.account.address]);
      
      assert.equal(score1, validScoreData[8]);
      assert.equal(score2, validScoreData2[8]);
      assert.equal(score3, validScoreData3[8]);

      // Verify events were emitted
      const events = await publicClient.getContractEvents({
        address: oracle.address,
        abi: oracle.abi,
        fromBlock: deploymentBlock,
        strict: true,
      });

      // Should have various events: TrustedPartyAdded (2), ScoreLoaded (2), BatchScoreLoaded (1), Paused (2), Unpaused (1), DAOUpdated (1)
      assert(events.length > 8);
    });

    it("Should handle score updates correctly", async function () {
      const oracle = await viem.deployContract("ReputationOracle", [dao.account.address]);
      await oracle.write.addTrustedParty([trustedParty1.account.address], {
        account: dao.account,
      });

      // Load initial score
      await oracle.write.load([user1.account.address, validScoreData], {
        account: trustedParty1.account,
      });

      let [score] = await oracle.read.getWalletInfo([user1.account.address]);
      assert.equal(score, validScoreData[8]);

      // Update the score
      const updatedScoreData = [...validScoreData];
      updatedScoreData[8] = 850n; // New score
      updatedScoreData[9] = BigInt(Math.floor(Date.now() / 1000) + 3600); // Updated timestamp

      await oracle.write.load([user1.account.address, updatedScoreData], {
        account: trustedParty1.account,
      });

      [score] = await oracle.read.getWalletInfo([user1.account.address]);
      assert.equal(score, 850n);
    });
  });
});
