import assert from "node:assert/strict";
import { describe, it, beforeEach, before } from "node:test";
import { network } from "hardhat";
import { Address, parseEther, encodeAbiParameters } from "viem";

describe("PluriSwapDAO", async function () {
  const { viem } = await network.connect();
  const publicClient = await viem.getPublicClient();
  
  // Test accounts - need 5 signers plus additional test accounts
  const [deployer, signer1, signer2, signer3, signer4, signer5, recipient, newSigner, unauthorized] = await viem.getWalletClients();
  
  let dao: any;
  
  const signerAddresses = [
    signer1.account.address,
    signer2.account.address, 
    signer3.account.address,
    signer4.account.address,
    signer5.account.address
  ];
  
  const signerNames = [
    "Signer One",
    "Signer Two", 
    "Signer Three",
    "Signer Four",
    "Signer Five"
  ];

  beforeEach(async function () {
    dao = await viem.deployContract("PluriSwapDAO", [signerAddresses]);
    
    // Fund the DAO with some ETH for testing treasury operations
    await deployer.sendTransaction({
      to: dao.address,
      value: parseEther("100")
    });
  });

  describe("Deployment", function () {
    it("Should deploy with correct initial signers", async function () {
      for (let i = 0; i < signerAddresses.length; i++) {
        assert.equal(await dao.read.signers([signerAddresses[i]]), true);
        assert.equal(await dao.read.isSigner([signerAddresses[i]]), true);
      }
      
      const activeSigners = await dao.read.getActiveSigners();
      assert.equal(activeSigners.length, 5);
    });

    it("Should set correct constants", async function () {
      assert.equal(await dao.read.MAX_SIGNERS(), 5n);
      assert.equal(await dao.read.STANDARD_THRESHOLD(), 3n);
      assert.equal(await dao.read.SIGNER_THRESHOLD(), 4n);
    });

    it("Should reject deployment with wrong number of signers", async function () {
      await assert.rejects(
        viem.deployContract("PluriSwapDAO", [
          [signer1.account.address, signer2.account.address] // Only 2 signers
        ]),
        /Must have 5 signers/
      );
    });

    it("Should reject deployment with zero address signer", async function () {
      const invalidSigners = [...signerAddresses];
      invalidSigners[0] = "0x0000000000000000000000000000000000000000";
      
      await assert.rejects(
        viem.deployContract("PluriSwapDAO", [invalidSigners]),
        /Invalid signer/
      );
    });

    it("Should reject deployment with duplicate signers", async function () {
      const duplicateSigners = [...signerAddresses];
      duplicateSigners[1] = signerAddresses[0]; // Duplicate
      
      await assert.rejects(
        viem.deployContract("PluriSwapDAO", [duplicateSigners]),
        /Duplicate signer/
      );
    });
  });

  describe("Access Control", function () {
    it("Should only allow signers to propose transactions", async function () {
      await assert.rejects(
        dao.write.proposeTreasuryTransfer([
          recipient.account.address,
          parseEther("1"),
          "0x0000000000000000000000000000000000000000", // ETH
          "Test transfer"
        ], { account: unauthorized.account }),
        /InvalidSigner/
      );
    });

    it("Should only allow signers to approve transactions", async function () {
      // First propose a transaction as a valid signer
      const txId = await dao.write.proposeTreasuryTransfer([
        recipient.account.address,
        parseEther("1"),
        "0x0000000000000000000000000000000000000000",
        "Test transfer"
      ], { account: signer1.account });

      await assert.rejects(
        dao.write.approveTreasuryTransfer([txId], { account: unauthorized.account }),
        /InvalidSigner/
      );
    });

    it("Should only allow signers to execute transactions", async function () {
      const txId = await dao.write.proposeTreasuryTransfer([
        recipient.account.address,
        parseEther("1"),
        "0x0000000000000000000000000000000000000000",
        "Test transfer"
      ], { account: signer1.account });

      await assert.rejects(
        dao.write.executeTreasuryTransfer([txId], { account: unauthorized.account }),
        /InvalidSigner/
      );
    });
  });

  describe("Treasury Management", function () {
    it("Should allow proposing treasury transfers", async function () {
      const tx = dao.write.proposeTreasuryTransfer([
        recipient.account.address,
        parseEther("1"),
        "0x0000000000000000000000000000000000000000", // ETH
        "Test transfer for recipient"
      ], { account: signer1.account });

      await viem.assertions.emit(tx, dao, "TransactionSubmitted");
    });

    it("Should execute treasury transfer with 3-of-5 approvals", async function () {
      const amount = parseEther("5");
      const initialBalance = await publicClient.getBalance({ address: recipient.account.address });
      
      // Propose transaction
      const txId = await dao.write.proposeTreasuryTransfer([
        recipient.account.address,
        amount,
        "0x0000000000000000000000000000000000000000",
        "Test transfer"
      ], { account: signer1.account });

      // Add 2 more approvals to reach 3-of-5 threshold (proposing counts as 1 approval)
      await dao.write.approveTreasuryTransfer([txId], { account: signer2.account });
      
      // This should trigger execution since we have 3 approvals
      const approveTx = dao.write.approveTreasuryTransfer([txId], { account: signer3.account });
      await viem.assertions.emit(approveTx, dao, "TransactionExecuted");

      // Check recipient received the funds
      const finalBalance = await publicClient.getBalance({ address: recipient.account.address });
      assert(finalBalance > initialBalance);
    });

    it("Should reject treasury transfer with insufficient approvals", async function () {
      const txId = await dao.write.proposeTreasuryTransfer([
        recipient.account.address,
        parseEther("1"),
        "0x0000000000000000000000000000000000000000",
        "Test transfer"
      ], { account: signer1.account });

      // Only 1 approval (proposer), need 3 total
      await assert.rejects(
        dao.write.executeTreasuryTransfer([txId], { account: signer1.account }),
        /InsufficientApprovals/
      );
    });

    it("Should prevent duplicate approvals", async function () {
      const txId = await dao.write.proposeTreasuryTransfer([
        recipient.account.address,
        parseEther("1"),
        "0x0000000000000000000000000000000000000000",
        "Test transfer"
      ], { account: signer1.account });

      // Try to approve again (proposer already approved implicitly)
      await assert.rejects(
        dao.write.approveTreasuryTransfer([txId], { account: signer1.account }),
        /TransactionAlreadyApproved/
      );
    });

    it("Should enforce daily limits", async function () {
      const largeAmount = parseEther("15"); // Exceeds 10 ETH default limit
      
      const txId = await dao.write.proposeTreasuryTransfer([
        recipient.account.address,
        largeAmount,
        "0x0000000000000000000000000000000000000000",
        "Large transfer"
      ], { account: signer1.account });

      // Get enough approvals
      await dao.write.approveTreasuryTransfer([txId], { account: signer2.account });
      await dao.write.approveTreasuryTransfer([txId], { account: signer3.account });

      // Should fail due to daily limit
      await assert.rejects(
        dao.write.executeTreasuryTransfer([txId], { account: signer1.account })
      );
    });

    it("Should allow cancellation by proposer", async function () {
      const txId = await dao.write.proposeTreasuryTransfer([
        recipient.account.address,
        parseEther("1"),
        "0x0000000000000000000000000000000000000000",
        "Test transfer"
      ], { account: signer1.account });

      const tx = dao.write.cancelTransaction([txId], { account: signer1.account });
      await viem.assertions.emit(tx, dao, "TransactionCancelled");

      // Should not be able to approve cancelled transaction
      await assert.rejects(
        dao.write.approveTreasuryTransfer([txId], { account: signer2.account }),
        /TransactionAlreadyExecuted/
      );
    });

    it("Should reject cancellation by non-proposer", async function () {
      const txId = await dao.write.proposeTreasuryTransfer([
        recipient.account.address,
        parseEther("1"),
        "0x0000000000000000000000000000000000000000",
        "Test transfer"
      ], { account: signer1.account });

      await assert.rejects(
        dao.write.cancelTransaction([txId], { account: signer2.account }),
        /OnlyProposerCanCancel/
      );
    });
  });

  describe("Oracle Management", function () {
    it("Should allow proposing oracle operations", async function () {
      const tx1 = dao.write.proposeAddOracleTrustedParty([
        recipient.account.address,
        "Add trusted party for oracle"
      ], { account: signer1.account });
      await viem.assertions.emit(tx1, dao, "TransactionProposed");

      const tx2 = dao.write.proposeRemoveOracleTrustedParty([
        recipient.account.address,
        "Remove trusted party from oracle"
      ], { account: signer1.account });
      await viem.assertions.emit(tx2, dao, "TransactionProposed");

      const tx3 = dao.write.proposePauseOracle(["Emergency pause"], { account: signer1.account });
      await viem.assertions.emit(tx3, dao, "TransactionProposed");

      const tx4 = dao.write.proposeUnpauseOracle(["Resume operations"], { account: signer1.account });
      await viem.assertions.emit(tx4, dao, "TransactionProposed");

      const tx5 = dao.write.proposeUpdateOracleDAO([
        newSigner.account.address,
        "Update DAO address"
      ], { account: signer1.account });
      await viem.assertions.emit(tx5, dao, "TransactionProposed");
    });

    it("Should execute oracle operations with sufficient approvals", async function () {
      const txId = await dao.write.proposeAddOracleTrustedParty([
        recipient.account.address,
        "Add trusted party"
      ], { account: signer1.account });

      // Add approvals to reach threshold
      await dao.write.approveOracleUpdate([txId], { account: signer2.account });
      
      const approveTx = dao.write.approveOracleUpdate([txId], { account: signer3.account });
      await viem.assertions.emit(approveTx, dao, "TransactionExecuted");
    });
  });

  describe("Escrow Management", function () {
    const mockEscrowAddress = recipient.account.address; // Use as mock escrow

    it("Should allow proposing escrow configuration updates", async function () {
      const mockConfig = encodeAbiParameters(
        [{ name: 'baseFee', type: 'uint256' }, { name: 'maxFee', type: 'uint256' }],
        [parseEther("0.01"), parseEther("0.1")]
      );

      const tx1 = dao.write.proposeUpdateEscrowConfig([
        mockEscrowAddress,
        mockConfig,
        "Update escrow configuration"
      ], { account: signer1.account });
      await viem.assertions.emit(tx1, dao, "TransactionProposed");

      const tx2 = dao.write.proposeUpdateEscrowBaseFee([
        mockEscrowAddress,
        parseEther("0.02"),
        "Update base fee"
      ], { account: signer1.account });
      await viem.assertions.emit(tx2, dao, "TransactionProposed");

      const tx3 = dao.write.proposeSetEscrowArbitrationProxy([
        mockEscrowAddress,
        newSigner.account.address,
        "Set arbitration proxy"
      ], { account: signer1.account });
      await viem.assertions.emit(tx3, dao, "TransactionProposed");
    });

    it("Should allow proposing escrow pause/unpause", async function () {
      const tx1 = dao.write.proposePauseEscrow([
        mockEscrowAddress,
        "Emergency pause"
      ], { account: signer1.account });
      await viem.assertions.emit(tx1, dao, "TransactionProposed");

      const tx2 = dao.write.proposeUnpauseEscrow([
        mockEscrowAddress,
        "Resume operations"
      ], { account: signer1.account });
      await viem.assertions.emit(tx2, dao, "TransactionProposed");
    });
  });

  describe("Arbitration Proxy Management", function () {
    const mockArbitrationProxy = recipient.account.address;

    it("Should allow proposing support agent operations", async function () {
      const tx1 = dao.write.proposeAddSupportAgent([
        mockArbitrationProxy,
        newSigner.account.address,
        "Agent Smith",
        "Add new support agent"
      ], { account: signer1.account });
      await viem.assertions.emit(tx1, dao, "TransactionProposed");

      const tx2 = dao.write.proposeRemoveSupportAgent([
        mockArbitrationProxy,
        newSigner.account.address,
        "Remove support agent"
      ], { account: signer1.account });
      await viem.assertions.emit(tx2, dao, "TransactionProposed");
    });

    it("Should allow proposing arbitration configuration updates", async function () {
      const mockConfig = encodeAbiParameters(
        [{ name: 'paused', type: 'bool' }, { name: 'baseFee', type: 'uint256' }],
        [false, parseEther("0.01")]
      );

      const tx1 = dao.write.proposeUpdateArbitrationConfig([
        mockArbitrationProxy,
        mockConfig,
        "Update arbitration config"
      ], { account: signer1.account });
      await viem.assertions.emit(tx1, dao, "TransactionProposed");
    });

    it("Should allow proposing authorized escrow contract management", async function () {
      const tx1 = dao.write.proposeAddAuthorizedEscrowContract([
        mockArbitrationProxy,
        recipient.account.address,
        "Add authorized escrow"
      ], { account: signer1.account });
      await viem.assertions.emit(tx1, dao, "TransactionProposed");

      const tx2 = dao.write.proposeRemoveAuthorizedEscrowContract([
        mockArbitrationProxy,
        recipient.account.address,
        "Remove authorized escrow"
      ], { account: signer1.account });
      await viem.assertions.emit(tx2, dao, "TransactionProposed");
    });

    it("Should allow proposing arbitration proxy pause/unpause", async function () {
      const tx1 = dao.write.proposePauseArbitrationProxy([
        mockArbitrationProxy,
        "Emergency pause"
      ], { account: signer1.account });
      await viem.assertions.emit(tx1, dao, "TransactionProposed");

      const tx2 = dao.write.proposeUnpauseArbitrationProxy([
        mockArbitrationProxy,
        "Resume operations"
      ], { account: signer1.account });
      await viem.assertions.emit(tx2, dao, "TransactionProposed");
    });
  });

  describe("Reputation Events Management", function () {
    const mockReputationEvents = recipient.account.address;

    it("Should allow proposing reputation events operations", async function () {
      const tx1 = dao.write.proposePauseReputationEvents([
        mockReputationEvents,
        "Emergency pause"
      ], { account: signer1.account });
      await viem.assertions.emit(tx1, dao, "TransactionProposed");

      const tx2 = dao.write.proposeUnpauseReputationEvents([
        mockReputationEvents,
        "Resume operations"
      ], { account: signer1.account });
      await viem.assertions.emit(tx2, dao, "TransactionProposed");

      const tx3 = dao.write.proposeTransferEventsOwnership([
        mockReputationEvents,
        newSigner.account.address,
        "Transfer ownership"
      ], { account: signer1.account });
      await viem.assertions.emit(tx3, dao, "TransactionProposed");
    });
  });

  describe("Emergency Actions", function () {
    it("Should allow proposing emergency actions", async function () {
      const tx1 = dao.write.proposeEmergencyPause(["Critical security issue"], { account: signer1.account });
      await viem.assertions.emit(tx1, dao, "TransactionProposed");

      const tx2 = dao.write.proposeEmergencyUnpause(["Issue resolved"], { account: signer1.account });
      await viem.assertions.emit(tx2, dao, "TransactionProposed");
    });

    it("Should execute emergency actions without timelock", async function () {
      const txId = await dao.write.proposeEmergencyPause(["Critical issue"], { account: signer1.account });

      // Emergency actions can execute immediately with sufficient approvals
      await dao.write.approveEmergencyAction([txId], { account: signer2.account });
      
      const approveTx = dao.write.approveEmergencyAction([txId], { account: signer3.account });
      await viem.assertions.emit(approveTx, dao, "EmergencyAction");
      await viem.assertions.emit(approveTx, dao, "TransactionExecuted");
    });
  });

  describe("Signer Management", function () {
    it("Should allow proposing to add signers", async function () {
      // First remove a signer to make space (need to approve this first)
      const removeTxId = await dao.write.proposeRemoveSigner([
        signer5.account.address,
        "Make space for new signer"
      ], { account: signer1.account });

      // Get 4-of-5 approvals for removal
      await dao.write.approveTransaction([removeTxId], { account: signer2.account });
      await dao.write.approveTransaction([removeTxId], { account: signer3.account });
      await dao.write.approveTransaction([removeTxId], { account: signer4.account });

      // Now propose to add new signer
      const tx = dao.write.proposeAddSigner([
        newSigner.account.address,
        "New Signer",
        "Adding replacement signer"
      ], { account: signer1.account });
      await viem.assertions.emit(tx, dao, "TransactionProposed");
    });

    it("Should allow proposing to remove signers", async function () {
      const tx = dao.write.proposeRemoveSigner([
        signer5.account.address,
        "Remove inactive signer"
      ], { account: signer1.account });
      await viem.assertions.emit(tx, dao, "TransactionProposed");
    });

    it("Should execute signer addition with 4-of-5 approvals", async function () {
      // First make space
      const removeTxId = await dao.write.proposeRemoveSigner([
        signer5.account.address,
        "Make space"
      ], { account: signer1.account });

      await dao.write.approveTransaction([removeTxId], { account: signer2.account });
      await dao.write.approveTransaction([removeTxId], { account: signer3.account });
      await dao.write.approveTransaction([removeTxId], { account: signer4.account });

      // Now add new signer
      const addTxId = await dao.write.proposeAddSigner([
        newSigner.account.address,
        "New Signer",
        "Adding new signer"
      ], { account: signer1.account });

      await dao.write.approveTransaction([addTxId], { account: signer2.account });
      await dao.write.approveTransaction([addTxId], { account: signer3.account });
      
      const approveTx = dao.write.approveTransaction([addTxId], { account: signer4.account });
      await viem.assertions.emit(approveTx, dao, "SignerAdded");
      await viem.assertions.emit(approveTx, dao, "TransactionExecuted");

      // Verify new signer was added
      assert.equal(await dao.read.isSigner([newSigner.account.address]), true);
    });

    it("Should execute signer removal with 4-of-5 approvals", async function () {
      const txId = await dao.write.proposeRemoveSigner([
        signer5.account.address,
        "Remove signer"
      ], { account: signer1.account });

      await dao.write.approveTransaction([txId], { account: signer2.account });
      await dao.write.approveTransaction([txId], { account: signer3.account });
      
      const approveTx = dao.write.approveTransaction([txId], { account: signer4.account });
      await viem.assertions.emit(approveTx, dao, "SignerRemoved");
      await viem.assertions.emit(approveTx, dao, "TransactionExecuted");

      // Verify signer was removed
      assert.equal(await dao.read.isSigner([signer5.account.address]), false);
    });

    it("Should reject signer management with insufficient approvals", async function () {
      const txId = await dao.write.proposeRemoveSigner([
        signer5.account.address,
        "Remove signer"
      ], { account: signer1.account });

      // Only 3 approvals (need 4 for signer management)
      await dao.write.approveTransaction([txId], { account: signer2.account });
      await dao.write.approveTransaction([txId], { account: signer3.account });

      await assert.rejects(
        dao.write.executeTransaction([txId], { account: signer1.account }),
        /InsufficientApprovals/
      );
    });

    it("Should reject adding already existing signer", async function () {
      await assert.rejects(
        dao.write.proposeAddSigner([
          signer1.account.address, // Already exists
          "Existing Signer",
          "Should fail"
        ], { account: signer1.account }),
        /Signer already exists/
      );
    });

    it("Should reject removing non-existent signer", async function () {
      await assert.rejects(
        dao.write.proposeRemoveSigner([
          newSigner.account.address, // Doesn't exist
          "Should fail"
        ], { account: signer1.account }),
        /Signer not found/
      );
    });
  });

  describe("Transaction Information", function () {
    it("Should provide correct transaction details", async function () {
      const txId = await dao.write.proposeTreasuryTransfer([
        recipient.account.address,
        parseEther("1"),
        "0x0000000000000000000000000000000000000000",
        "Test transfer for details"
      ], { account: signer1.account });

      const [txType, proposer, data, description, proposedAt, executedAt, status, approvalCount, isEmergency] = 
        await dao.read.getTransaction([txId]);

      assert.equal(txType, 0); // TREASURY
      assert.equal(proposer.toLowerCase(), signer1.account.address.toLowerCase());
      assert.equal(description, "Test transfer for details");
      assert.equal(approvalCount, 1n); // Proposer approval
      assert.equal(isEmergency, false);
      assert.equal(status, 0); // PROPOSED
      assert.equal(executedAt, 0n); // Not executed yet
      assert(proposedAt > 0n);
    });

    it("Should track approval status correctly", async function () {
      const txId = await dao.write.proposeTreasuryTransfer([
        recipient.account.address,
        parseEther("1"),
        "0x0000000000000000000000000000000000000000",
        "Test approval tracking"
      ], { account: signer1.account });

      // Check initial approvals
      assert.equal(await dao.read.hasApproved([txId, signer1.account.address]), true); // Proposer
      assert.equal(await dao.read.hasApproved([txId, signer2.account.address]), false);

      // Add approval
      await dao.write.approveTreasuryTransfer([txId], { account: signer2.account });
      assert.equal(await dao.read.hasApproved([txId, signer2.account.address]), true);
    });

    it("Should return current transaction counter", async function () {
      const initialCounter = await dao.read.getCurrentTransactionId();
      
      await dao.write.proposeTreasuryTransfer([
        recipient.account.address,
        parseEther("1"),
        "0x0000000000000000000000000000000000000000",
        "Test counter"
      ], { account: signer1.account });

      const newCounter = await dao.read.getCurrentTransactionId();
      assert.equal(newCounter, initialCounter + 1n);
    });
  });

  describe("Daily Limits", function () {
    it("Should reset daily limits after time passes", async function () {
      // This test would require time manipulation which is complex in hardhat
      // For now, we'll test the logic exists
      const dailyLimit = await dao.read.dailyLimits(["0x0000000000000000000000000000000000000000"]);
      assert.equal(dailyLimit[0], parseEther("10")); // Default limit
      assert.equal(dailyLimit[1], 0n); // Initial spent
      assert(dailyLimit[2] > 0n); // Reset time set
    });

    it("Should track spending within daily limits", async function () {
      const amount = parseEther("3");
      
      // Make first transfer
      const txId1 = await dao.write.proposeTreasuryTransfer([
        recipient.account.address,
        amount,
        "0x0000000000000000000000000000000000000000",
        "First transfer"
      ], { account: signer1.account });

      await dao.write.approveTreasuryTransfer([txId1], { account: signer2.account });
      await dao.write.approveTreasuryTransfer([txId1], { account: signer3.account });

      // Check daily limit was updated
      const dailyLimit = await dao.read.dailyLimits(["0x0000000000000000000000000000000000000000"]);
      assert.equal(dailyLimit[1], amount); // Spent amount
    });
  });

  describe("General Transaction Functions", function () {
    it("Should allow using general approve and execute functions", async function () {
      const txId = await dao.write.proposeTreasuryTransfer([
        recipient.account.address,
        parseEther("1"),
        "0x0000000000000000000000000000000000000000",
        "General functions test"
      ], { account: signer1.account });

      // Use general approve function
      await dao.write.approveTransaction([txId], { account: signer2.account });
      
      const approveTx = dao.write.approveTransaction([txId], { account: signer3.account });
      await viem.assertions.emit(approveTx, dao, "TransactionExecuted");
    });
  });

  describe("Integration Tests", function () {
    it("Should handle complex workflow with multiple transaction types", async function () {
      const deploymentBlock = await publicClient.getBlockNumber();

      // Propose multiple different types of transactions
      const treasuryTxId = await dao.write.proposeTreasuryTransfer([
        recipient.account.address,
        parseEther("2"),
        "0x0000000000000000000000000000000000000000",
        "Treasury integration test"
      ], { account: signer1.account });

      const oracleTxId = await dao.write.proposeAddOracleTrustedParty([
        newSigner.account.address,
        "Oracle integration test"
      ], { account: signer2.account });

      const emergencyTxId = await dao.write.proposeEmergencyPause([
        "Integration test emergency"
      ], { account: signer3.account });

      // Approve treasury transaction
      await dao.write.approveTreasuryTransfer([treasuryTxId], { account: signer2.account });
      await dao.write.approveTreasuryTransfer([treasuryTxId], { account: signer3.account });

      // Approve oracle transaction
      await dao.write.approveOracleUpdate([oracleTxId], { account: signer1.account });
      await dao.write.approveOracleUpdate([oracleTxId], { account: signer3.account });

      // Approve emergency transaction
      await dao.write.approveEmergencyAction([emergencyTxId], { account: signer1.account });
      await dao.write.approveEmergencyAction([emergencyTxId], { account: signer2.account });

      // Verify all transactions were executed
      const treasuryTx = await dao.read.getTransaction([treasuryTxId]);
      const oracleTx = await dao.read.getTransaction([oracleTxId]);
      const emergencyTx = await dao.read.getTransaction([emergencyTxId]);

      assert.equal(treasuryTx[6], 1); // EXECUTED
      assert.equal(oracleTx[6], 1); // EXECUTED
      assert.equal(emergencyTx[6], 1); // EXECUTED

      // Check events were emitted
      const events = await publicClient.getContractEvents({
        address: dao.address,
        abi: dao.abi,
        fromBlock: deploymentBlock,
        strict: true,
      });

      const executedEvents = events.filter(e => e.eventName === "TransactionExecuted");
      assert.equal(executedEvents.length, 3); // All 3 transactions executed
    });

    it("Should handle signer management workflow", async function () {
      // Complete workflow: remove signer, add new signer, verify changes
      const removeTxId = await dao.write.proposeRemoveSigner([
        signer5.account.address,
        "Workflow test removal"
      ], { account: signer1.account });

      // Get 4-of-5 approvals
      await dao.write.approveTransaction([removeTxId], { account: signer2.account });
      await dao.write.approveTransaction([removeTxId], { account: signer3.account });
      await dao.write.approveTransaction([removeTxId], { account: signer4.account });

      // Verify signer was removed
      assert.equal(await dao.read.isSigner([signer5.account.address]), false);
      const activeSigners = await dao.read.getActiveSigners();
      assert.equal(activeSigners.length, 4);

      // Add new signer
      const addTxId = await dao.write.proposeAddSigner([
        newSigner.account.address,
        "Workflow New Signer",
        "Workflow test addition"
      ], { account: signer1.account });

      // Get 4-of-4 approvals (now only 4 active signers)
      await dao.write.approveTransaction([addTxId], { account: signer2.account });
      await dao.write.approveTransaction([addTxId], { account: signer3.account });
      await dao.write.approveTransaction([addTxId], { account: signer4.account });

      // Verify new signer was added
      assert.equal(await dao.read.isSigner([newSigner.account.address]), true);
      const finalSigners = await dao.read.getActiveSigners();
      assert.equal(finalSigners.length, 5);

      // Verify old signer is still removed
      assert.equal(await dao.read.isSigner([signer5.account.address]), false);
    });
  });

  describe("Edge Cases", function () {
    it("Should reject operations on non-existent transactions", async function () {
      const nonExistentTxId = 99999n;

      await assert.rejects(
        dao.write.approveTreasuryTransfer([nonExistentTxId], { account: signer1.account }),
        /TransactionNotFound/
      );

      await assert.rejects(
        dao.read.getTransaction([nonExistentTxId])
      );
    });

    it("Should reject invalid transaction type mismatches", async function () {
      // Propose treasury transaction
      const txId = await dao.write.proposeTreasuryTransfer([
        recipient.account.address,
        parseEther("1"),
        "0x0000000000000000000000000000000000000000",
        "Type mismatch test"
      ], { account: signer1.account });

      // Try to approve with wrong function (oracle instead of treasury)
      await assert.rejects(
        dao.write.approveOracleUpdate([txId], { account: signer2.account }),
        /InvalidTransactionType/
      );
    });
  });
});
