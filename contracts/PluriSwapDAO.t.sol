// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "./PluriSwapDAO.sol";

/**
 * @title PluriSwapDAO Solidity Tests
 * @notice Comprehensive test suite using Hardhat 3 Solidity testing framework
 * @dev Tests all acceptance criteria from the specification using forge-std
 */
contract PluriSwapDAOTest is Test {
    PluriSwapDAO dao;
    
    // Test accounts
    address signer1 = makeAddr("signer1");
    address signer2 = makeAddr("signer2");
    address signer3 = makeAddr("signer3");
    address signer4 = makeAddr("signer4");
    address signer5 = makeAddr("signer5");
    address recipient = makeAddr("recipient");
    address newSigner = makeAddr("newSigner");
    address unauthorized = makeAddr("unauthorized");

    address[] signers;

    function setUp() public {
        signers = new address[](5);
        signers[0] = signer1;
        signers[1] = signer2;
        signers[2] = signer3;
        signers[3] = signer4;
        signers[4] = signer5;
        
        dao = new PluriSwapDAO(signers);
        
        // Fund the DAO with some ETH for testing treasury operations
        vm.deal(address(dao), 100 ether);
    }

    // ==================== DEPLOYMENT TESTS ====================
    
    function test_DeploymentWithCorrectInitialSigners() public {
        for (uint i = 0; i < signers.length; i++) {
            assertTrue(dao.signers(signers[i]));
            assertTrue(dao.isSigner(signers[i]));
        }
        
        address[] memory activeSigners = dao.getActiveSigners();
        assertEq(activeSigners.length, 5);
    }

    function test_DeploymentConstants() public {
        assertEq(dao.MAX_SIGNERS(), 5);
        assertEq(dao.STANDARD_THRESHOLD(), 3);
        assertEq(dao.SIGNER_THRESHOLD(), 4);
    }

    function test_RevertWhen_DeploymentWithWrongNumberOfSigners() public {
        address[] memory wrongSigners = new address[](3);
        wrongSigners[0] = signer1;
        wrongSigners[1] = signer2;
        wrongSigners[2] = signer3;
        
        vm.expectRevert(PluriSwapDAO.InvalidSigner.selector);
        new PluriSwapDAO(wrongSigners);
    }

    function test_RevertWhen_DeploymentWithZeroAddress() public {
        address[] memory invalidSigners = new address[](5);
        invalidSigners[0] = address(0);
        invalidSigners[1] = signer2;
        invalidSigners[2] = signer3;
        invalidSigners[3] = signer4;
        invalidSigners[4] = signer5;
        
        vm.expectRevert(PluriSwapDAO.InvalidAddress.selector);
        new PluriSwapDAO(invalidSigners);
    }

    function test_RevertWhen_DeploymentWithDuplicateSigners() public {
        address[] memory duplicateSigners = new address[](5);
        duplicateSigners[0] = signer1;
        duplicateSigners[1] = signer1; // Duplicate
        duplicateSigners[2] = signer3;
        duplicateSigners[3] = signer4;
        duplicateSigners[4] = signer5;
        
        vm.expectRevert(PluriSwapDAO.DuplicateSigner.selector);
        new PluriSwapDAO(duplicateSigners);
    }

    // ==================== ACCESS CONTROL TESTS ====================
    
    function test_RevertWhen_UnauthorizedUserProposesTransaction() public {
        vm.prank(unauthorized);
        vm.expectRevert(PluriSwapDAO.InvalidSigner.selector);
        dao.proposeTreasuryTransfer(recipient, 1 ether, address(0), "Test transfer");
    }

    function test_RevertWhen_UnauthorizedUserApprovesTransaction() public {
        vm.prank(signer1);
        uint256 txId = dao.proposeTreasuryTransfer(recipient, 1 ether, address(0), "Test transfer");

        vm.prank(unauthorized);
        vm.expectRevert(PluriSwapDAO.InvalidSigner.selector);
        dao.approveTransaction(txId);
    }

    function test_RevertWhen_UnauthorizedUserExecutesTransaction() public {
        vm.prank(signer1);
        uint256 txId = dao.proposeTreasuryTransfer(recipient, 1 ether, address(0), "Test transfer");

        // Fast-forward time to bypass timelock
        vm.warp(block.timestamp + 2 days + 1);

        // executeTransaction doesn't have onlySigner modifier, it checks for insufficient approvals first
        vm.prank(unauthorized);
        vm.expectRevert(PluriSwapDAO.InsufficientApprovals.selector);
        dao.executeTransaction(txId);
    }

    // ==================== TREASURY MANAGEMENT TESTS ====================
    
    function test_ProposeTreasuryTransfer() public {
        vm.prank(signer1);
        uint256 txId = dao.proposeTreasuryTransfer(recipient, 1 ether, address(0), "Test transfer");
        
        (PluriSwapDAO.TransactionType txType, address proposer, bytes memory data, string memory description,
         uint256 proposedAt, uint256 executedAt, uint256 executeAfter, PluriSwapDAO.TransactionStatus status, uint256 approvalCount, bool isEmergency) 
         = dao.getTransaction(txId);
        
        assertEq(uint256(txType), uint256(PluriSwapDAO.TransactionType.TREASURY));
        assertEq(proposer, signer1);
        assertEq(description, "Test transfer");
        assertEq(approvalCount, 1); // Proposer approval
        assertEq(uint256(status), uint256(PluriSwapDAO.TransactionStatus.PROPOSED));
        assertFalse(isEmergency);
        assertTrue(proposedAt > 0);
        assertEq(executedAt, 0);
    }

    function test_ExecuteTreasuryTransferWith3of5Approvals() public {
        uint256 initialBalance = recipient.balance;
        uint256 amount = 5 ether;
        
        vm.prank(signer1);
        uint256 txId = dao.proposeTreasuryTransfer(recipient, amount, address(0), "Test transfer");

        // Add 2 more approvals to reach 3-of-5 threshold
        vm.prank(signer2);
        dao.approveTransaction(txId);
        
        vm.prank(signer3);
        dao.approveTransaction(txId);
        
        // Fast-forward time to bypass timelock (2 days)
        vm.warp(block.timestamp + 2 days + 1);
        
        // Execute the transaction manually
        dao.executeTransaction(txId);
        
        // Check recipient received the funds
        assertEq(recipient.balance, initialBalance + amount);
        
        // Check transaction status
        (, , , , , , , PluriSwapDAO.TransactionStatus status, ,) = dao.getTransaction(txId);
        assertEq(uint256(status), uint256(PluriSwapDAO.TransactionStatus.EXECUTED));
    }

    function test_RevertWhen_TreasuryTransferWithInsufficientApprovals() public {
        vm.prank(signer1);
        uint256 txId = dao.proposeTreasuryTransfer(recipient, 1 ether, address(0), "Test transfer");

        // Fast-forward time to bypass timelock
        vm.warp(block.timestamp + 2 days + 1);

        // Only 1 approval (proposer), need 3 total
        vm.expectRevert(PluriSwapDAO.InsufficientApprovals.selector);
        dao.executeTransaction(txId);
    }

    function test_RevertWhen_DuplicateApproval() public {
        vm.prank(signer1);
        uint256 txId = dao.proposeTreasuryTransfer(recipient, 1 ether, address(0), "Test transfer");

        // Try to approve again (proposer already approved implicitly)
        vm.prank(signer1);
        vm.expectRevert(PluriSwapDAO.TransactionAlreadyApproved.selector);
        dao.approveTransaction(txId);
    }

    function test_TransactionCancellationByProposer() public {
        vm.prank(signer1);
        uint256 txId = dao.proposeTreasuryTransfer(recipient, 1 ether, address(0), "Test transfer");

        vm.prank(signer1);
        dao.cancelTransaction(txId);

        // Verify transaction was cancelled
        (, , , , , , , PluriSwapDAO.TransactionStatus status, ,) = dao.getTransaction(txId);
        assertEq(uint256(status), uint256(PluriSwapDAO.TransactionStatus.CANCELLED));
    }

    function test_RevertWhen_CancellationByNonProposer() public {
        vm.prank(signer1);
        uint256 txId = dao.proposeTreasuryTransfer(recipient, 1 ether, address(0), "Test transfer");

        vm.prank(signer2);
        vm.expectRevert(PluriSwapDAO.OnlyProposerCanCancel.selector);
        dao.cancelTransaction(txId);
    }

    // ==================== ORACLE MANAGEMENT TESTS ====================
    
    function test_ProposeOracleOperations() public {
        vm.startPrank(signer1);
        
        uint256 txId1 = dao.proposeAddOracleTrustedParty(recipient, "Add trusted party");
        uint256 txId2 = dao.proposeRemoveOracleTrustedParty(recipient, "Remove trusted party");
        uint256 txId3 = dao.proposePauseOracle("Emergency pause");
        uint256 txId4 = dao.proposeUnpauseOracle("Resume operations");
        uint256 txId5 = dao.proposeUpdateOracleDAO(newSigner, "Update DAO address");

        vm.stopPrank();

        // Verify all transactions were created with correct types
        (PluriSwapDAO.TransactionType txType1, , , , , , , , ,) = dao.getTransaction(txId1);
        (PluriSwapDAO.TransactionType txType2, , , , , , , , ,) = dao.getTransaction(txId2);
        (PluriSwapDAO.TransactionType txType3, , , , , , , , ,) = dao.getTransaction(txId3);
        (PluriSwapDAO.TransactionType txType4, , , , , , , , ,) = dao.getTransaction(txId4);
        (PluriSwapDAO.TransactionType txType5, , , , , , , , ,) = dao.getTransaction(txId5);
        
        assertEq(uint256(txType1), uint256(PluriSwapDAO.TransactionType.ORACLE_ADD_TRUSTED_PARTY));
        assertEq(uint256(txType2), uint256(PluriSwapDAO.TransactionType.ORACLE_REMOVE_TRUSTED_PARTY));
        assertEq(uint256(txType3), uint256(PluriSwapDAO.TransactionType.ORACLE_PAUSE));
        assertEq(uint256(txType4), uint256(PluriSwapDAO.TransactionType.ORACLE_UNPAUSE));
        assertEq(uint256(txType5), uint256(PluriSwapDAO.TransactionType.ORACLE_UPDATE_DAO));
    }

    function test_ExecuteOracleOperationWithSufficientApprovals() public {
        vm.prank(signer1);
        uint256 txId = dao.proposeAddOracleTrustedParty(recipient, "Add trusted party");

        // Add approvals to reach threshold
        vm.prank(signer2);
        dao.approveTransaction(txId);
        
        vm.prank(signer3);
        dao.approveTransaction(txId);

        // Fast-forward time to bypass timelock
        vm.warp(block.timestamp + 2 days + 1);
        
        // Execute the transaction
        dao.executeTransaction(txId);

        // Verify transaction was executed
        (, , , , , , , PluriSwapDAO.TransactionStatus status, ,) = dao.getTransaction(txId);
        assertEq(uint256(status), uint256(PluriSwapDAO.TransactionStatus.EXECUTED));
    }

    // ==================== SIGNER MANAGEMENT TESTS ====================
    
    function test_ProposeAddSigner() public {
        // First remove a signer to make space
        vm.prank(signer1);
        uint256 removeTxId = dao.proposeRemoveSigner(signer5, "Make space for new signer");

        // Get 4-of-5 approvals for removal
        vm.prank(signer2);
        dao.approveTransaction(removeTxId);
        vm.prank(signer3);
        dao.approveTransaction(removeTxId);
        vm.prank(signer4);
        dao.approveTransaction(removeTxId);

        // Fast-forward time to bypass timelock
        vm.warp(block.timestamp + 2 days + 1);
        
        // Execute the removal
        dao.executeTransaction(removeTxId);

        // Now propose to add new signer
        vm.prank(signer1);
        uint256 txId = dao.proposeAddSigner(newSigner, "New Signer", "Adding replacement");
        
        (PluriSwapDAO.TransactionType txType, , , , , , , , ,) = dao.getTransaction(txId);
        assertEq(uint256(txType), uint256(PluriSwapDAO.TransactionType.ADD_SIGNER));
    }

    function test_ProposeRemoveSigner() public {
        vm.prank(signer1);
        uint256 txId = dao.proposeRemoveSigner(signer5, "Remove inactive signer");
        
        (PluriSwapDAO.TransactionType txType, , , , , , , , ,) = dao.getTransaction(txId);
        assertEq(uint256(txType), uint256(PluriSwapDAO.TransactionType.REMOVE_SIGNER));
    }

    function test_ExecuteSignerAdditionWith4of5Approvals() public {
        // First make space by removing a signer
        vm.prank(signer1);
        uint256 removeTxId = dao.proposeRemoveSigner(signer5, "Make space");

        vm.prank(signer2);
        dao.approveTransaction(removeTxId);
        vm.prank(signer3);
        dao.approveTransaction(removeTxId);
        vm.prank(signer4);
        dao.approveTransaction(removeTxId);

        // Fast-forward time to bypass timelock for removal
        vm.warp(block.timestamp + 2 days + 1);
        
        // Execute the removal
        dao.executeTransaction(removeTxId);

        // Now add new signer
        vm.prank(signer1);
        uint256 addTxId = dao.proposeAddSigner(newSigner, "New Signer", "Adding new signer");

        vm.prank(signer2);
        dao.approveTransaction(addTxId);
        vm.prank(signer3);
        dao.approveTransaction(addTxId);
        vm.prank(signer4);
        dao.approveTransaction(addTxId);

        // Fast-forward time to bypass timelock for addition
        vm.warp(block.timestamp + 2 days + 1);
        
        // Execute the addition
        dao.executeTransaction(addTxId);

        // Verify new signer was added
        assertTrue(dao.isSigner(newSigner));
    }

    function test_ExecuteSignerRemovalWith4of5Approvals() public {
        vm.prank(signer1);
        uint256 txId = dao.proposeRemoveSigner(signer5, "Remove signer");

        vm.prank(signer2);
        dao.approveTransaction(txId);
        vm.prank(signer3);
        dao.approveTransaction(txId);
        vm.prank(signer4);
        dao.approveTransaction(txId);

        // Fast-forward time to bypass timelock
        vm.warp(block.timestamp + 2 days + 1);
        
        // Execute the transaction
        dao.executeTransaction(txId);

        // Verify signer was removed
        assertFalse(dao.isSigner(signer5));
        
        address[] memory activeSigners = dao.getActiveSigners();
        assertEq(activeSigners.length, 4);
    }

    function test_RevertWhen_SignerManagementWithInsufficientApprovals() public {
        vm.prank(signer1);
        uint256 txId = dao.proposeRemoveSigner(signer5, "Remove signer");

        // Only 3 approvals (need 4 for signer management)
        vm.prank(signer2);
        dao.approveTransaction(txId);
        vm.prank(signer3);
        dao.approveTransaction(txId);

        // Fast-forward time to bypass timelock
        vm.warp(block.timestamp + 2 days + 1);

        vm.expectRevert(PluriSwapDAO.InsufficientApprovals.selector);
        dao.executeTransaction(txId);
    }

    function test_RevertWhen_AddingExistingSigner() public {
        vm.expectRevert(PluriSwapDAO.SignerAlreadyExists.selector);
        vm.prank(signer1);
        dao.proposeAddSigner(signer1, "Existing Signer", "Should fail");
    }

    function test_RevertWhen_RemovingNonExistentSigner() public {
        vm.expectRevert(PluriSwapDAO.SignerNotFound.selector);
        vm.prank(signer1);
        dao.proposeRemoveSigner(newSigner, "Should fail");
    }

    // ==================== EMERGENCY ACTIONS TESTS ====================
    
    function test_ProposeEmergencyActions() public {
        vm.startPrank(signer1);
        
        uint256 txId1 = dao.proposeEmergencyPause("Critical security issue");
        uint256 txId2 = dao.proposeEmergencyUnpause("Issue resolved");

        vm.stopPrank();

        // Verify transactions are marked as emergency
        (, , , , , , , , , bool isEmergency1) = dao.getTransaction(txId1);
        (, , , , , , , , , bool isEmergency2) = dao.getTransaction(txId2);
        assertTrue(isEmergency1);
        assertTrue(isEmergency2);
    }

    function test_ExecuteEmergencyActionsWithSufficientApprovals() public {
        vm.prank(signer1);
        uint256 txId = dao.proposeEmergencyPause("Critical issue");

        // Emergency actions need 2-of-5 approvals (proposer + 1 more)
        vm.prank(signer2);
        dao.approveTransaction(txId);
        
        // Execute the transaction (no timelock for emergency actions)
        dao.executeTransaction(txId);

        // Verify transaction was executed
        (, , , , , , , PluriSwapDAO.TransactionStatus status, ,) = dao.getTransaction(txId);
        assertEq(uint256(status), uint256(PluriSwapDAO.TransactionStatus.EXECUTED));
    }

    // ==================== DAILY LIMITS TESTS ====================
    
    function test_DailyLimitsInitialization() public {
        (uint256 limit, uint256 spent, uint256 resetTime) = dao.dailyLimits(address(0));
        assertEq(limit, 10 ether); // Default limit
        assertEq(spent, 0); // Initial spent
        assertTrue(resetTime > 0); // Reset time set
    }

    function test_TrackSpendingWithinDailyLimits() public {
        uint256 amount = 3 ether;
        
        // Ensure DAO has enough funds
        vm.deal(address(dao), amount);
        
        // Make first transfer
        vm.prank(signer1);
        uint256 txId1 = dao.proposeTreasuryTransfer(recipient, amount, address(0), "First transfer");

        vm.prank(signer2);
        dao.approveTransaction(txId1);
        vm.prank(signer3);
        dao.approveTransaction(txId1);

        // Fast-forward time to bypass timelock
        vm.warp(block.timestamp + 2 days + 1);
        
        // Execute the transaction
        dao.executeTransaction(txId1);

        // Check daily limit was updated
        (uint256 limit, uint256 spent,) = dao.dailyLimits(address(0));
        assertEq(spent, amount);
    }

    // ==================== VIEW FUNCTIONS TESTS ====================
    
    function test_GetTransactionDetails() public {
        vm.prank(signer1);
        uint256 txId = dao.proposeTreasuryTransfer(recipient, 1 ether, address(0), "Test transfer for details");

        (PluriSwapDAO.TransactionType txType, address proposer, , string memory description, 
         uint256 proposedAt, uint256 executedAt, uint256 executeAfter, PluriSwapDAO.TransactionStatus status, 
         uint256 approvalCount, bool isEmergency) = dao.getTransaction(txId);

        assertEq(uint256(txType), uint256(PluriSwapDAO.TransactionType.TREASURY));
        assertEq(proposer, signer1);
        assertEq(description, "Test transfer for details");
        assertEq(approvalCount, 1); // Proposer approval
        assertFalse(isEmergency);
        assertEq(uint256(status), uint256(PluriSwapDAO.TransactionStatus.PROPOSED));
        assertEq(executedAt, 0); // Not executed yet
        assertTrue(proposedAt > 0);
    }

    function test_ApprovalStatusTracking() public {
        vm.prank(signer1);
        uint256 txId = dao.proposeTreasuryTransfer(recipient, 1 ether, address(0), "Test approval tracking");

        // Check initial approvals
        assertTrue(dao.hasApproved(txId, signer1)); // Proposer
        assertFalse(dao.hasApproved(txId, signer2));

        // Add approval
        vm.prank(signer2);
        dao.approveTransaction(txId);
        assertTrue(dao.hasApproved(txId, signer2));
    }

    function test_TransactionCounter() public {
        uint256 initialCounter = dao.getCurrentTransactionId();
        
        vm.prank(signer1);
        dao.proposeTreasuryTransfer(recipient, 1 ether, address(0), "Test counter");

        uint256 newCounter = dao.getCurrentTransactionId();
        assertEq(newCounter, initialCounter + 1);
    }

    function test_SignerInformation() public {
        for (uint i = 0; i < signers.length; i++) {
            assertTrue(dao.isSigner(signers[i]));
            assertTrue(dao.signers(signers[i]));
        }

        assertFalse(dao.isSigner(unauthorized));
        assertFalse(dao.signers(unauthorized));
        
        address[] memory activeSigners = dao.getActiveSigners();
        assertEq(activeSigners.length, 5);
    }

    // ==================== EDGE CASES TESTS ====================
    
    function test_RevertWhen_OperatingOnNonExistentTransaction() public {
        uint256 nonExistentTxId = 99999;

        // approveTransaction checks onlySigner first, so use valid signer
        vm.prank(signer1);
        vm.expectRevert(PluriSwapDAO.TransactionNotFound.selector);
        dao.approveTransaction(nonExistentTxId);

        // getTransaction is a view function, doesn't check signer
        vm.expectRevert(PluriSwapDAO.TransactionNotFound.selector);
        dao.getTransaction(nonExistentTxId);
    }

    function test_RevertWhen_ExecutingAlreadyExecutedTransaction() public {
        vm.prank(signer1);
        uint256 txId = dao.proposeTreasuryTransfer(recipient, 1 ether, address(0), "Execute first");

        // Get enough approvals 
        vm.prank(signer2);
        dao.approveTransaction(txId);
        vm.prank(signer3);
        dao.approveTransaction(txId);

        // Fast-forward time to bypass timelock
        vm.warp(block.timestamp + 2 days + 1);
        
        // Execute the transaction
        dao.executeTransaction(txId);

        // Try to execute again - should revert because transaction is already executed
        vm.expectRevert(PluriSwapDAO.TransactionAlreadyExecuted.selector);
        dao.executeTransaction(txId);
    }

    function test_RevertWhen_ExecutingCancelledTransaction() public {
        vm.prank(signer1);
        uint256 txId = dao.proposeTreasuryTransfer(recipient, 1 ether, address(0), "Cancel this");

        // Cancel the transaction
        vm.prank(signer1);
        dao.cancelTransaction(txId);

        // Try to approve - should revert because transaction is cancelled
        vm.prank(signer2);
        vm.expectRevert(); // Transaction not in PROPOSED state
        dao.approveTransaction(txId);
    }

    // ==================== FUZZ TESTS ====================
    
    function testFuzz_TreasuryTransferAmounts(uint96 amount) public {
        vm.assume(amount > 0 && amount <= 10 ether); // Within daily limit
        
        // Ensure DAO has enough funds
        vm.deal(address(dao), amount);
        
        uint256 initialBalance = recipient.balance;
        
        vm.prank(signer1);
        uint256 txId = dao.proposeTreasuryTransfer(recipient, amount, address(0), "Fuzz test transfer");

        vm.prank(signer2);
        dao.approveTransaction(txId);
        vm.prank(signer3);
        dao.approveTransaction(txId);

        // Fast-forward time to bypass timelock
        vm.warp(block.timestamp + 2 days + 1);
        
        // Execute the transaction
        dao.executeTransaction(txId);

        // Verify recipient received the correct amount
        assertEq(recipient.balance, initialBalance + amount);
    }

    function testFuzz_MultipleApprovals(uint8 approverCount) public {
        vm.assume(approverCount >= 1 && approverCount <= 5);
        
        // Ensure DAO has enough funds
        vm.deal(address(dao), 1 ether);
        
        vm.prank(signer1);
        uint256 txId = dao.proposeTreasuryTransfer(recipient, 1 ether, address(0), "Fuzz approvals");

        uint256 expectedApprovals = 1; // Proposer already approved
        
        // Add approvals from other signers up to approverCount
        if (approverCount >= 2) {
            vm.prank(signer2);
            dao.approveTransaction(txId);
            expectedApprovals++;
        }
        
        if (approverCount >= 3) {
            vm.prank(signer3);
            dao.approveTransaction(txId);
            expectedApprovals++;
        }
        
        if (approverCount >= 4) {
            vm.prank(signer4);
            dao.approveTransaction(txId);
            expectedApprovals++;
        }
        
        if (approverCount >= 5) {
            vm.prank(signer5);
            dao.approveTransaction(txId);
            expectedApprovals++;
        }

        // Check approval count
        (, , , , , , , PluriSwapDAO.TransactionStatus status, uint256 approvalCount,) = dao.getTransaction(txId);
        assertEq(approvalCount, expectedApprovals);
        
        // Transaction should still be PROPOSED (no auto-execution)
        assertEq(uint256(status), uint256(PluriSwapDAO.TransactionStatus.PROPOSED));
        
        // Try to execute if we have enough approvals
        if (expectedApprovals >= 3) {
            vm.warp(block.timestamp + 2 days + 1); // Bypass timelock
            dao.executeTransaction(txId);
            
            // Check it was executed
            (, , , , , , , PluriSwapDAO.TransactionStatus finalStatus, ,) = dao.getTransaction(txId);
            assertEq(uint256(finalStatus), uint256(PluriSwapDAO.TransactionStatus.EXECUTED));
        }
    }

    // ==================== RECEIVE FUNCTION TEST ====================
    
    function test_ReceiveEther() public {
        uint256 initialBalance = address(dao).balance;
        uint256 sendAmount = 1 ether;
        
        (bool success,) = address(dao).call{value: sendAmount}("");
        assertTrue(success);
        
        assertEq(address(dao).balance, initialBalance + sendAmount);
    }
}
