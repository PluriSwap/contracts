// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "./ReputationOracle.sol";

/**
 * @title ReputationOracle Solidity Tests
 * @notice Comprehensive test suite for ReputationOracle contract
 * @dev Tests all functionality including reads, writes, validation, governance, and batch operations
 */
contract ReputationOracleTest is Test {
    ReputationOracle oracle;
    
    // Test accounts
    address dao = makeAddr("dao");
    address trustedParty1 = makeAddr("trustedParty1");
    address trustedParty2 = makeAddr("trustedParty2");
    address wallet1 = makeAddr("wallet1");
    address wallet2 = makeAddr("wallet2");
    address wallet3 = makeAddr("wallet3");
    address newDAO = makeAddr("newDAO");
    address unauthorized = makeAddr("unauthorized");

    // Test data - Valid reputation data
    uint256[11] validData1;
    uint256[11] validData2;
    uint256[11] validData3;

    function setUp() public {
        oracle = new ReputationOracle(dao);
        
        // Setup valid test data
        // validData1: Good trader with high score
        validData1 = [
            uint256(100), // started
            uint256(95),  // completed
            uint256(3),   // cancelled
            uint256(2),   // disputed
            uint256(2),   // disputes won
            uint256(0),   // disputes lost
            uint256(50000), // volume started
            uint256(47500), // volume completed
            uint256(850),   // score
            uint256(block.timestamp), // last updated
            uint256(1)    // is active
        ];
        
        // validData2: Average trader with medium score
        validData2 = [
            uint256(50),  // started
            uint256(45),  // completed
            uint256(3),   // cancelled
            uint256(2),   // disputed
            uint256(1),   // disputes won
            uint256(1),   // disputes lost
            uint256(25000), // volume started
            uint256(22500), // volume completed
            uint256(600),   // score
            uint256(block.timestamp), // last updated
            uint256(1)    // is active
        ];
        
        // validData3: New trader with low score
        validData3 = [
            uint256(5),   // started
            uint256(4),   // completed
            uint256(1),   // cancelled
            uint256(0),   // disputed
            uint256(0),   // disputes won
            uint256(0),   // disputes lost
            uint256(1000), // volume started
            uint256(800),  // volume completed
            uint256(250),  // score
            uint256(block.timestamp), // last updated
            uint256(1)    // is active
        ];
    }

    // ==================== DEPLOYMENT TESTS ====================

    function test_DeploymentWithValidDAO() public {
        assertEq(oracle.dao(), dao);
        assertFalse(oracle.paused());
    }

    function test_RevertWhen_DeploymentWithZeroAddress() public {
        vm.expectRevert(ReputationOracle.InvalidAddress.selector);
        new ReputationOracle(address(0));
    }

    // ==================== READ TESTS ====================

    function test_ScoreOfReturnsEmptyForNewWallet() public {
        bytes memory scoreData = oracle.score_of(wallet1);
        uint256[11] memory decodedData = abi.decode(scoreData, (uint256[11]));
        
        // All values should be zero for new wallet
        for (uint256 i = 0; i < 11; i++) {
            assertEq(decodedData[i], 0);
        }
    }

    function test_ScoreOfReturnsLoadedData() public {
        // Add trusted party and load data
        vm.prank(dao);
        oracle.addTrustedParty(trustedParty1);
        
        vm.prank(trustedParty1);
        oracle.load(wallet1, validData1);
        
        // Verify data can be read
        bytes memory scoreData = oracle.score_of(wallet1);
        uint256[11] memory decodedData = abi.decode(scoreData, (uint256[11]));
        
        for (uint256 i = 0; i < 11; i++) {
            assertEq(decodedData[i], validData1[i]);
        }
    }

    function test_ScoreOfIsConstantTime() public {
        // This test ensures score_of is a view function (constant-time)
        // and doesn't modify state
        
        bytes memory scoreData1 = oracle.score_of(wallet1);
        bytes memory scoreData2 = oracle.score_of(wallet1);
        
        assertEq(keccak256(scoreData1), keccak256(scoreData2));
    }

    // ==================== WRITE TESTS ====================

    function test_LoadByDAO() public {
        vm.prank(dao);
        vm.expectEmit(true, false, false, true);
        emit ReputationOracle.WalletScoreLoaded(wallet1, validData1[8], true);
        oracle.load(wallet1, validData1);
        
        // Verify data was stored
        uint256[11] memory storedData = oracle.getWalletData(wallet1);
        for (uint256 i = 0; i < 11; i++) {
            assertEq(storedData[i], validData1[i]);
        }
    }

    function test_LoadByTrustedParty() public {
        vm.prank(dao);
        oracle.addTrustedParty(trustedParty1);
        
        vm.prank(trustedParty1);
        oracle.load(wallet1, validData2);
        
        // Verify data was stored
        uint256[11] memory storedData = oracle.getWalletData(wallet1);
        for (uint256 i = 0; i < 11; i++) {
            assertEq(storedData[i], validData2[i]);
        }
    }

    function test_RevertWhen_LoadByUnauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert(ReputationOracle.OnlyDAOOrTrustedParty.selector);
        oracle.load(wallet1, validData1);
    }

    function test_RevertWhen_LoadWithZeroWallet() public {
        vm.prank(dao);
        vm.expectRevert(ReputationOracle.InvalidAddress.selector);
        oracle.load(address(0), validData1);
    }

    function test_RevertWhen_LoadWhilePaused() public {
        vm.startPrank(dao);
        oracle.addTrustedParty(trustedParty1);
        oracle.pause();
        vm.stopPrank();
        
        vm.prank(trustedParty1);
        vm.expectRevert(ReputationOracle.ContractIsPaused.selector);
        oracle.load(wallet1, validData1);
    }

    // ==================== BATCH LOAD TESTS ====================

    function test_BatchLoadByDAO() public {
        address[] memory wallets = new address[](2);
        wallets[0] = wallet1;
        wallets[1] = wallet2;
        
        uint256[11][] memory dataArray = new uint256[11][](2);
        dataArray[0] = validData1;
        dataArray[1] = validData2;
        
        vm.prank(dao);
        vm.expectEmit(false, false, false, true);
        emit ReputationOracle.BatchWalletScoresLoaded(2);
        oracle.batchLoad(wallets, dataArray);
        
        // Verify both wallets were updated
        uint256[11] memory storedData1 = oracle.getWalletData(wallet1);
        uint256[11] memory storedData2 = oracle.getWalletData(wallet2);
        
        for (uint256 i = 0; i < 11; i++) {
            assertEq(storedData1[i], validData1[i]);
            assertEq(storedData2[i], validData2[i]);
        }
    }

    function test_BatchLoadByTrustedParty() public {
        vm.prank(dao);
        oracle.addTrustedParty(trustedParty1);
        
        address[] memory wallets = new address[](3);
        wallets[0] = wallet1;
        wallets[1] = wallet2;
        wallets[2] = wallet3;
        
        uint256[11][] memory dataArray = new uint256[11][](3);
        dataArray[0] = validData1;
        dataArray[1] = validData2;
        dataArray[2] = validData3;
        
        vm.prank(trustedParty1);
        oracle.batchLoad(wallets, dataArray);
        
        // Verify all wallets were updated
        for (uint256 j = 0; j < 3; j++) {
            uint256[11] memory storedData = oracle.getWalletData(wallets[j]);
            for (uint256 i = 0; i < 11; i++) {
                assertEq(storedData[i], dataArray[j][i]);
            }
        }
    }

    function test_RevertWhen_BatchLoadArrayLengthMismatch() public {
        address[] memory wallets = new address[](2);
        wallets[0] = wallet1;
        wallets[1] = wallet2;
        
        uint256[11][] memory dataArray = new uint256[11][](1); // Wrong length
        dataArray[0] = validData1;
        
        vm.prank(dao);
        vm.expectRevert(ReputationOracle.ArrayLengthMismatch.selector);
        oracle.batchLoad(wallets, dataArray);
    }

    function test_RevertWhen_BatchLoadWithZeroWallet() public {
        address[] memory wallets = new address[](1);
        wallets[0] = address(0); // Zero address
        
        uint256[11][] memory dataArray = new uint256[11][](1);
        dataArray[0] = validData1;
        
        vm.prank(dao);
        vm.expectRevert(ReputationOracle.InvalidAddress.selector);
        oracle.batchLoad(wallets, dataArray);
    }

    // ==================== DATA VALIDATION TESTS ====================

    function test_RevertWhen_ScoreExceedsMaximum() public {
        uint256[11] memory invalidData = validData1;
        invalidData[8] = 1001; // Score > 1000
        
        vm.prank(dao);
        vm.expectRevert(abi.encodeWithSelector(ReputationOracle.InvalidScore.selector, 1001));
        oracle.load(wallet1, invalidData);
    }

    function test_RevertWhen_CompletedExceedsStarted() public {
        uint256[11] memory invalidData = validData1;
        invalidData[0] = 50;  // started
        invalidData[1] = 51;  // completed > started
        
        vm.prank(dao);
        vm.expectRevert(abi.encodeWithSelector(ReputationOracle.InvalidTransactionData.selector, "Completed > Started"));
        oracle.load(wallet1, invalidData);
    }

    function test_RevertWhen_CancelledExceedsStarted() public {
        uint256[11] memory invalidData = validData1;
        invalidData[0] = 50;  // started
        invalidData[1] = 40;  // completed (valid, less than started)
        invalidData[2] = 51;  // cancelled > started
        
        vm.prank(dao);
        vm.expectRevert(abi.encodeWithSelector(ReputationOracle.InvalidTransactionData.selector, "Cancelled > Started"));
        oracle.load(wallet1, invalidData);
    }

    function test_RevertWhen_DisputedExceedsStarted() public {
        uint256[11] memory invalidData = validData1;
        invalidData[0] = 50;  // started
        invalidData[1] = 40;  // completed (valid, less than started)
        invalidData[2] = 5;   // cancelled (valid, less than started)
        invalidData[3] = 51;  // disputed > started
        
        vm.prank(dao);
        vm.expectRevert(abi.encodeWithSelector(ReputationOracle.InvalidTransactionData.selector, "Disputed > Started"));
        oracle.load(wallet1, invalidData);
    }

    function test_RevertWhen_VolumeCompletedExceedsStarted() public {
        uint256[11] memory invalidData = validData1;
        invalidData[6] = 1000;  // volume started
        invalidData[7] = 1001;  // volume completed > started
        
        vm.prank(dao);
        vm.expectRevert(abi.encodeWithSelector(ReputationOracle.InvalidTransactionData.selector, "VolumeCompleted > VolumeStarted"));
        oracle.load(wallet1, invalidData);
    }

    function test_RevertWhen_DisputeWinLossExceedsDisputed() public {
        uint256[11] memory invalidData = validData1;
        invalidData[3] = 5;   // disputed
        invalidData[4] = 3;   // disputes won
        invalidData[5] = 3;   // disputes lost (won + lost = 6 > disputed = 5)
        
        vm.prank(dao);
        vm.expectRevert(abi.encodeWithSelector(ReputationOracle.InvalidTransactionData.selector, "DisputesWon + DisputesLost > Disputed"));
        oracle.load(wallet1, invalidData);
    }

    function test_RevertWhen_InvalidIsActiveValue() public {
        uint256[11] memory invalidData = validData1;
        invalidData[10] = 2;  // isActive must be 0 or 1
        
        vm.prank(dao);
        vm.expectRevert(abi.encodeWithSelector(ReputationOracle.InvalidTransactionData.selector, "isActive must be 0 or 1"));
        oracle.load(wallet1, invalidData);
    }

    function test_ValidDataAtBoundaries() public {
        uint256[11] memory boundaryData = [
            uint256(1000), // started
            uint256(1000), // completed (equal to started is valid)
            uint256(0),    // cancelled
            uint256(1000), // disputed (equal to started is valid)
            uint256(500),  // disputes won
            uint256(500),  // disputes lost (won + lost = disputed is valid)
            uint256(type(uint256).max), // volume started (max value)
            uint256(type(uint256).max), // volume completed (equal to started is valid)
            uint256(1000), // score (max valid score)
            uint256(block.timestamp), // last updated
            uint256(0)     // is active (0 is valid)
        ];
        
        vm.prank(dao);
        oracle.load(wallet1, boundaryData);
        
        // Should not revert and data should be stored
        uint256[11] memory storedData = oracle.getWalletData(wallet1);
        for (uint256 i = 0; i < 11; i++) {
            assertEq(storedData[i], boundaryData[i]);
        }
    }

    // ==================== TRUSTED PARTY MANAGEMENT TESTS ====================

    function test_AddTrustedPartyByDAO() public {
        vm.prank(dao);
        vm.expectEmit(true, false, false, false);
        emit ReputationOracle.TrustedPartyAdded(trustedParty1);
        oracle.addTrustedParty(trustedParty1);
        
        assertTrue(oracle.isTrustedParty(trustedParty1));
    }

    function test_RevertWhen_AddTrustedPartyByUnauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert(ReputationOracle.OnlyDAO.selector);
        oracle.addTrustedParty(trustedParty1);
    }

    function test_RevertWhen_AddZeroAddressAsTrustedParty() public {
        vm.prank(dao);
        vm.expectRevert(ReputationOracle.InvalidAddress.selector);
        oracle.addTrustedParty(address(0));
    }

    function test_RevertWhen_AddExistingTrustedParty() public {
        vm.prank(dao);
        oracle.addTrustedParty(trustedParty1);
        
        vm.prank(dao);
        vm.expectRevert(ReputationOracle.TrustedPartyAlreadyExists.selector);
        oracle.addTrustedParty(trustedParty1);
    }

    function test_RemoveTrustedPartyByDAO() public {
        vm.prank(dao);
        oracle.addTrustedParty(trustedParty1);
        assertTrue(oracle.isTrustedParty(trustedParty1));
        
        vm.prank(dao);
        vm.expectEmit(true, false, false, false);
        emit ReputationOracle.TrustedPartyRemoved(trustedParty1);
        oracle.removeTrustedParty(trustedParty1);
        
        assertFalse(oracle.isTrustedParty(trustedParty1));
    }

    function test_RevertWhen_RemoveNonExistentTrustedParty() public {
        vm.prank(dao);
        vm.expectRevert(ReputationOracle.TrustedPartyNotFound.selector);
        oracle.removeTrustedParty(trustedParty1);
    }

    function test_RemovedTrustedPartyCannotLoad() public {
        vm.prank(dao);
        oracle.addTrustedParty(trustedParty1);
        
        // Can load while trusted
        vm.prank(trustedParty1);
        oracle.load(wallet1, validData1);
        
        // Remove trust
        vm.prank(dao);
        oracle.removeTrustedParty(trustedParty1);
        
        // Cannot load after removal
        vm.prank(trustedParty1);
        vm.expectRevert(ReputationOracle.OnlyDAOOrTrustedParty.selector);
        oracle.load(wallet1, validData2);
    }

    // ==================== PAUSE FUNCTIONALITY TESTS ====================

    function test_PauseByDAO() public {
        assertFalse(oracle.paused());
        
        vm.prank(dao);
        vm.expectEmit(false, false, false, false);
        emit ReputationOracle.Paused();
        oracle.pause();
        
        assertTrue(oracle.paused());
    }

    function test_UnpauseByDAO() public {
        vm.prank(dao);
        oracle.pause();
        assertTrue(oracle.paused());
        
        vm.prank(dao);
        vm.expectEmit(false, false, false, false);
        emit ReputationOracle.Unpaused();
        oracle.unpause();
        
        assertFalse(oracle.paused());
    }

    function test_RevertWhen_UnauthorizedPause() public {
        vm.prank(unauthorized);
        vm.expectRevert(ReputationOracle.OnlyDAO.selector);
        oracle.pause();
    }

    function test_RevertWhen_UnauthorizedUnpause() public {
        vm.prank(dao);
        oracle.pause();
        
        vm.prank(unauthorized);
        vm.expectRevert(ReputationOracle.OnlyDAO.selector);
        oracle.unpause();
    }

    function test_ReadsFunctionWhilePaused() public {
        vm.startPrank(dao);
        oracle.load(wallet1, validData1);
        oracle.pause();
        vm.stopPrank();
        
        // Reads should still work while paused
        bytes memory scoreData = oracle.score_of(wallet1);
        uint256[11] memory decodedData = abi.decode(scoreData, (uint256[11]));
        assertEq(decodedData[8], validData1[8]); // Check score
    }

    // ==================== DAO MANAGEMENT TESTS ====================

    function test_UpdateDAOByCurrentDAO() public {
        assertEq(oracle.dao(), dao);
        
        vm.prank(dao);
        vm.expectEmit(true, true, false, false);
        emit ReputationOracle.DAOUpdated(dao, newDAO);
        oracle.updateDAO(newDAO);
        
        assertEq(oracle.dao(), newDAO);
    }

    function test_RevertWhen_UpdateDAOByUnauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert(ReputationOracle.OnlyDAO.selector);
        oracle.updateDAO(newDAO);
    }

    function test_RevertWhen_UpdateDAOToZeroAddress() public {
        vm.prank(dao);
        vm.expectRevert(ReputationOracle.InvalidAddress.selector);
        oracle.updateDAO(address(0));
    }

    function test_NewDAOCanManageContract() public {
        // Update DAO
        vm.prank(dao);
        oracle.updateDAO(newDAO);
        
        // Old DAO should not be able to pause
        vm.prank(dao);
        vm.expectRevert(ReputationOracle.OnlyDAO.selector);
        oracle.pause();
        
        // New DAO should be able to pause
        vm.prank(newDAO);
        oracle.pause();
        assertTrue(oracle.paused());
        
        // New DAO should be able to add trusted parties
        vm.prank(newDAO);
        oracle.addTrustedParty(trustedParty1);
        assertTrue(oracle.isTrustedParty(trustedParty1));
    }

    // ==================== VIEW FUNCTIONS TESTS ====================

    function test_IsPausedReflectsState() public {
        assertFalse(oracle.isPaused());
        
        vm.prank(dao);
        oracle.pause();
        assertTrue(oracle.isPaused());
        
        vm.prank(dao);
        oracle.unpause();
        assertFalse(oracle.isPaused());
    }

    function test_GetDAOReturnsCurrentDAO() public {
        assertEq(oracle.getDAO(), dao);
        
        vm.prank(dao);
        oracle.updateDAO(newDAO);
        assertEq(oracle.getDAO(), newDAO);
    }

    function test_IsTrustedPartyReturnsCorrectStatus() public {
        assertFalse(oracle.isTrustedParty(trustedParty1));
        
        vm.prank(dao);
        oracle.addTrustedParty(trustedParty1);
        assertTrue(oracle.isTrustedParty(trustedParty1));
        
        vm.prank(dao);
        oracle.removeTrustedParty(trustedParty1);
        assertFalse(oracle.isTrustedParty(trustedParty1));
    }

    // ==================== INTEGRATION TESTS ====================

    function test_CompleteWorkflow() public {
        // Add trusted parties
        vm.prank(dao);
        oracle.addTrustedParty(trustedParty1);
        vm.prank(dao);
        oracle.addTrustedParty(trustedParty2);
        
        // Load data from different trusted parties
        vm.prank(trustedParty1);
        oracle.load(wallet1, validData1);
        
        vm.prank(trustedParty2);
        oracle.load(wallet2, validData2);
        
        // Batch load from DAO
        address[] memory wallets = new address[](1);
        wallets[0] = wallet3;
        uint256[11][] memory dataArray = new uint256[11][](1);
        dataArray[0] = validData3;
        
        vm.prank(dao);
        oracle.batchLoad(wallets, dataArray);
        
        // Verify all data is accessible
        bytes memory score1 = oracle.score_of(wallet1);
        bytes memory score2 = oracle.score_of(wallet2);
        bytes memory score3 = oracle.score_of(wallet3);
        
        uint256[11] memory decoded1 = abi.decode(score1, (uint256[11]));
        uint256[11] memory decoded2 = abi.decode(score2, (uint256[11]));
        uint256[11] memory decoded3 = abi.decode(score3, (uint256[11]));
        
        assertEq(decoded1[8], validData1[8]); // Check scores
        assertEq(decoded2[8], validData2[8]);
        assertEq(decoded3[8], validData3[8]);
        
        // Pause and verify reads still work but writes don't
        vm.prank(dao);
        oracle.pause();
        
        // Reads should work
        oracle.score_of(wallet1);
        
        // Writes should fail
        vm.prank(trustedParty1);
        vm.expectRevert(ReputationOracle.ContractIsPaused.selector);
        oracle.load(wallet1, validData2);
    }

    // ==================== FUZZ TESTS ====================

    function testFuzz_ValidScoreLoad(uint256 score) public {
        vm.assume(score <= 1000); // Valid score range
        
        uint256[11] memory fuzzData = validData1;
        fuzzData[8] = score;
        
        vm.prank(dao);
        oracle.load(wallet1, fuzzData);
        
        uint256[11] memory storedData = oracle.getWalletData(wallet1);
        assertEq(storedData[8], score);
    }

    function testFuzz_TransactionCounts(
        uint256 started,
        uint256 completed,
        uint256 cancelled,
        uint256 disputed
    ) public {
        started = bound(started, 0, 1000000);
        completed = bound(completed, 0, started);
        cancelled = bound(cancelled, 0, started);
        disputed = bound(disputed, 0, started);
        
        uint256[11] memory fuzzData = [
            started,
            completed,
            cancelled,
            disputed,
            uint256(0), // disputes won
            uint256(0), // disputes lost
            uint256(10000), // volume started
            uint256(8000),  // volume completed
            uint256(500),   // score
            uint256(block.timestamp), // last updated
            uint256(1)      // is active
        ];
        
        vm.prank(dao);
        oracle.load(wallet1, fuzzData);
        
        uint256[11] memory storedData = oracle.getWalletData(wallet1);
        assertEq(storedData[0], started);
        assertEq(storedData[1], completed);
        assertEq(storedData[2], cancelled);
        assertEq(storedData[3], disputed);
    }

    function testFuzz_BatchLoadSize(uint8 batchSize) public {
        vm.assume(batchSize > 0 && batchSize <= 50); // Reasonable batch size
        
        address[] memory wallets = new address[](batchSize);
        uint256[11][] memory dataArray = new uint256[11][](batchSize);
        
        for (uint256 i = 0; i < batchSize; i++) {
            wallets[i] = address(uint160(i + 1)); // Non-zero addresses
            dataArray[i] = validData1;
            dataArray[i][8] = i; // Different score for each
        }
        
        vm.prank(dao);
        oracle.batchLoad(wallets, dataArray);
        
        // Verify all were loaded
        for (uint256 i = 0; i < batchSize; i++) {
            uint256[11] memory storedData = oracle.getWalletData(wallets[i]);
            assertEq(storedData[8], i); // Check unique scores
        }
    }
}
