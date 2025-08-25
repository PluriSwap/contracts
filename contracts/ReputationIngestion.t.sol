// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "./ReputationIngestion.sol";

/**
 * @title ReputationIngestion Solidity Tests
 * @notice Comprehensive test suite for ReputationIngestion contract
 * @dev Tests all functionality including ingestion, pause behavior, and governance
 */
contract ReputationIngestionTest is Test {
    ReputationIngestion reputation;
    
    // Test accounts
    address dao = makeAddr("dao");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");
    address wallet1 = makeAddr("wallet1");
    address wallet2 = makeAddr("wallet2");
    address newDAO = makeAddr("newDAO");
    address unauthorized = makeAddr("unauthorized");

    // Test data
    string constant EVENT_NAME_1 = "trade_completed";
    string constant EVENT_NAME_2 = "dispute_resolved";
    string constant EVENT_NAME_3 = "payment_failed";
    
    bytes constant SMALL_METADATA = hex"deadbeef";
    bytes mediumMetadata;
    
    function setUp() public {
        reputation = new ReputationIngestion(dao);
        mediumMetadata = abi.encode("Complex metadata with multiple fields", uint256(12345), wallet1);
    }

    // ==================== DEPLOYMENT TESTS ====================

    function test_DeploymentWithValidDAO() public {
        assertEq(reputation.dao(), dao);
        assertFalse(reputation.paused());
    }

    function test_RevertWhen_DeploymentWithZeroAddress() public {
        vm.expectRevert(ReputationIngestion.InvalidAddress.selector);
        new ReputationIngestion(address(0));
    }

    // ==================== CORE INGESTION TESTS ====================

    function test_EventIngestionFromMultipleAddresses() public {
        // Test ingestion from user1
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit ReputationIngestion.ReputationEvent(EVENT_NAME_1, wallet1, user1, SMALL_METADATA, block.timestamp);
        reputation.event_of(EVENT_NAME_1, wallet1, SMALL_METADATA);

        // Test ingestion from user2
        vm.prank(user2);
        vm.expectEmit(true, true, true, true);
        emit ReputationIngestion.ReputationEvent(EVENT_NAME_2, wallet2, user2, mediumMetadata, block.timestamp);
        reputation.event_of(EVENT_NAME_2, wallet2, mediumMetadata);

        // Test ingestion from user3 with same wallet as user1
        vm.prank(user3);
        vm.expectEmit(true, true, true, true);
        emit ReputationIngestion.ReputationEvent(EVENT_NAME_3, wallet1, user3, SMALL_METADATA, block.timestamp);
        reputation.event_of(EVENT_NAME_3, wallet1, SMALL_METADATA);
    }

    function test_EventIngestionWithEmptyMetadata() public {
        bytes memory emptyMetadata = "";
        
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit ReputationIngestion.ReputationEvent(EVENT_NAME_1, wallet1, user1, emptyMetadata, block.timestamp);
        reputation.event_of(EVENT_NAME_1, wallet1, emptyMetadata);
    }

    function test_EventIngestionWithLargeMetadata() public {
        // Create large metadata (but reasonable for testing)
        bytes memory largeMetadata = new bytes(1024);
        for (uint256 i = 0; i < 1024; i++) {
            largeMetadata[i] = bytes1(uint8(i % 256));
        }
        
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit ReputationIngestion.ReputationEvent(EVENT_NAME_1, wallet1, user1, largeMetadata, block.timestamp);
        reputation.event_of(EVENT_NAME_1, wallet1, largeMetadata);
    }

    function test_EventIngestionWithZeroWallet() public {
        // Allow zero wallet address (might be valid use case)
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit ReputationIngestion.ReputationEvent(EVENT_NAME_1, address(0), user1, SMALL_METADATA, block.timestamp);
        reputation.event_of(EVENT_NAME_1, address(0), SMALL_METADATA);
    }

    function test_EventIngestionPreservesTimestamp() public {
        uint256 startTime = block.timestamp;
        
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit ReputationIngestion.ReputationEvent(EVENT_NAME_1, wallet1, user1, SMALL_METADATA, startTime);
        reputation.event_of(EVENT_NAME_1, wallet1, SMALL_METADATA);

        // Move time forward and test again
        vm.warp(block.timestamp + 100);
        
        vm.prank(user2);
        vm.expectEmit(true, true, true, true);
        emit ReputationIngestion.ReputationEvent(EVENT_NAME_2, wallet2, user2, mediumMetadata, block.timestamp);
        reputation.event_of(EVENT_NAME_2, wallet2, mediumMetadata);
    }

    // ==================== PAUSE FUNCTIONALITY TESTS ====================

    function test_PauseByDAO() public {
        assertFalse(reputation.paused());
        
        vm.prank(dao);
        vm.expectEmit(false, false, false, false);
        emit ReputationIngestion.Paused();
        reputation.pause();
        
        assertTrue(reputation.paused());
    }

    function test_UnpauseByDAO() public {
        // First pause
        vm.prank(dao);
        reputation.pause();
        assertTrue(reputation.paused());
        
        // Then unpause
        vm.prank(dao);
        vm.expectEmit(false, false, false, false);
        emit ReputationIngestion.Unpaused();
        reputation.unpause();
        
        assertFalse(reputation.paused());
    }

    function test_RevertWhen_UnauthorizedPause() public {
        vm.prank(unauthorized);
        vm.expectRevert(ReputationIngestion.OnlyDAO.selector);
        reputation.pause();
    }

    function test_RevertWhen_UnauthorizedUnpause() public {
        vm.prank(dao);
        reputation.pause();
        
        vm.prank(unauthorized);
        vm.expectRevert(ReputationIngestion.OnlyDAO.selector);
        reputation.unpause();
    }

    function test_RevertWhen_EventIngestionWhilePaused() public {
        vm.prank(dao);
        reputation.pause();
        
        vm.prank(user1);
        vm.expectRevert(ReputationIngestion.ContractIsPaused.selector);
        reputation.event_of(EVENT_NAME_1, wallet1, SMALL_METADATA);
    }

    function test_EventIngestionAfterUnpause() public {
        // Pause contract
        vm.prank(dao);
        reputation.pause();
        
        // Try to ingest (should fail)
        vm.prank(user1);
        vm.expectRevert(ReputationIngestion.ContractIsPaused.selector);
        reputation.event_of(EVENT_NAME_1, wallet1, SMALL_METADATA);
        
        // Unpause contract
        vm.prank(dao);
        reputation.unpause();
        
        // Now ingestion should work
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit ReputationIngestion.ReputationEvent(EVENT_NAME_1, wallet1, user1, SMALL_METADATA, block.timestamp);
        reputation.event_of(EVENT_NAME_1, wallet1, SMALL_METADATA);
    }

    // ==================== DAO MANAGEMENT TESTS ====================

    function test_UpdateDAOByCurrentDAO() public {
        assertEq(reputation.dao(), dao);
        
        vm.prank(dao);
        vm.expectEmit(true, true, false, false);
        emit ReputationIngestion.DAOUpdated(dao, newDAO);
        reputation.updateDAO(newDAO);
        
        assertEq(reputation.dao(), newDAO);
    }

    function test_RevertWhen_UpdateDAOByUnauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert(ReputationIngestion.OnlyDAO.selector);
        reputation.updateDAO(newDAO);
    }

    function test_RevertWhen_UpdateDAOToZeroAddress() public {
        vm.prank(dao);
        vm.expectRevert(ReputationIngestion.InvalidAddress.selector);
        reputation.updateDAO(address(0));
    }

    function test_NewDAOCanManageContract() public {
        // Update DAO
        vm.prank(dao);
        reputation.updateDAO(newDAO);
        
        // Old DAO should not be able to pause
        vm.prank(dao);
        vm.expectRevert(ReputationIngestion.OnlyDAO.selector);
        reputation.pause();
        
        // New DAO should be able to pause
        vm.prank(newDAO);
        reputation.pause();
        assertTrue(reputation.paused());
        
        // New DAO should be able to unpause
        vm.prank(newDAO);
        reputation.unpause();
        assertFalse(reputation.paused());
    }

    // ==================== VIEW FUNCTIONS TESTS ====================

    function test_IsPausedReflectsState() public {
        assertFalse(reputation.isPaused());
        
        vm.prank(dao);
        reputation.pause();
        assertTrue(reputation.isPaused());
        
        vm.prank(dao);
        reputation.unpause();
        assertFalse(reputation.isPaused());
    }

    function test_GetDAOReturnsCurrentDAO() public {
        assertEq(reputation.getDAO(), dao);
        
        vm.prank(dao);
        reputation.updateDAO(newDAO);
        assertEq(reputation.getDAO(), newDAO);
    }

    // ==================== INTEGRATION TESTS ====================

    function test_CompleteWorkflow() public {
        // Multiple users can ingest events
        vm.prank(user1);
        reputation.event_of(EVENT_NAME_1, wallet1, SMALL_METADATA);
        
        vm.prank(user2);
        reputation.event_of(EVENT_NAME_2, wallet2, mediumMetadata);
        
        // DAO can pause
        vm.prank(dao);
        reputation.pause();
        
        // Ingestion blocked while paused
        vm.prank(user3);
        vm.expectRevert(ReputationIngestion.ContractIsPaused.selector);
        reputation.event_of(EVENT_NAME_3, wallet1, SMALL_METADATA);
        
        // DAO can change ownership
        vm.prank(dao);
        reputation.updateDAO(newDAO);
        
        // New DAO can unpause
        vm.prank(newDAO);
        reputation.unpause();
        
        // Ingestion works again
        vm.prank(user3);
        reputation.event_of(EVENT_NAME_3, wallet1, SMALL_METADATA);
    }

    // ==================== FUZZ TESTS ====================

    function testFuzz_EventIngestion(
        string calldata eventName,
        address wallet,
        bytes calldata metadata,
        address caller
    ) public {
        vm.assume(caller != address(0)); // Avoid issues with zero caller
        
        vm.prank(caller);
        vm.expectEmit(true, true, true, true);
        emit ReputationIngestion.ReputationEvent(eventName, wallet, caller, metadata, block.timestamp);
        reputation.event_of(eventName, wallet, metadata);
    }

    function testFuzz_DAOUpdate(address oldDAO, address targetDAO) public {
        vm.assume(oldDAO != address(0) && targetDAO != address(0));
        vm.assume(oldDAO != targetDAO);
        
        // Deploy with custom DAO
        ReputationIngestion testReputation = new ReputationIngestion(oldDAO);
        
        vm.prank(oldDAO);
        vm.expectEmit(true, true, false, false);
        emit ReputationIngestion.DAOUpdated(oldDAO, targetDAO);
        testReputation.updateDAO(targetDAO);
        
        assertEq(testReputation.dao(), targetDAO);
    }

    function testFuzz_MetadataSize(uint16 size) public {
        vm.assume(size <= 2048); // Reasonable upper bound for testing
        
        bytes memory metadata = new bytes(size);
        for (uint256 i = 0; i < size; i++) {
            metadata[i] = bytes1(uint8(i % 256));
        }
        
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit ReputationIngestion.ReputationEvent(EVENT_NAME_1, wallet1, user1, metadata, block.timestamp);
        reputation.event_of(EVENT_NAME_1, wallet1, metadata);
    }
}
