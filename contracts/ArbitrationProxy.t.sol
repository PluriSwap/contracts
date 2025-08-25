// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "./ArbitrationProxy.sol";

/**
 * @title ArbitrationProxy Solidity Tests
 * @notice Comprehensive test suite for ArbitrationProxy contract
 * @dev Tests all functionality including dispute lifecycle, access control, and DAO management
 */
contract ArbitrationProxyTest is Test {
    ArbitrationProxy arbitration;
    
    // Test accounts
    address dao = makeAddr("dao");
    address reputationOracle = makeAddr("reputationOracle");
    address escrowContract1 = makeAddr("escrowContract1");
    address escrowContract2 = makeAddr("escrowContract2");
    address supportAgent1 = makeAddr("supportAgent1");
    address supportAgent2 = makeAddr("supportAgent2");
    address buyer1 = makeAddr("buyer1");
    address seller1 = makeAddr("seller1");
    address disputer1 = makeAddr("disputer1");
    address newDAO = makeAddr("newDAO");
    address unauthorized = makeAddr("unauthorized");

    // Mock escrow contract for testing callbacks
    MockEscrowContract mockEscrow;

    // Test data
    ArbitrationProxy.ArbitrationConfig defaultConfig;
    
    function setUp() public {
        // Setup default config
        defaultConfig = ArbitrationProxy.ArbitrationConfig({
            paused: false,
            feeRecipient: dao,
            baseFee: 0.01 ether
        });
        
        bytes memory configEncoded = abi.encode(defaultConfig);
        
        arbitration = new ArbitrationProxy(dao, reputationOracle, configEncoded);
        
        // Deploy mock escrow contract
        mockEscrow = new MockEscrowContract();
    }

    // ==================== DEPLOYMENT TESTS ====================

    function test_DeploymentWithValidParameters() public {
        assertEq(arbitration.dao(), dao);
        assertEq(arbitration.reputationOracle(), reputationOracle);
        assertFalse(arbitration.isPaused());
        
        ArbitrationProxy.ArbitrationConfig memory config = arbitration.getConfig();
        assertEq(config.feeRecipient, defaultConfig.feeRecipient);
        assertEq(config.baseFee, defaultConfig.baseFee);
        assertEq(config.paused, defaultConfig.paused);
    }

    function test_RevertWhen_DeploymentWithZeroDAO() public {
        bytes memory configEncoded = abi.encode(defaultConfig);
        
        vm.expectRevert(ArbitrationProxy.InvalidAddress.selector);
        new ArbitrationProxy(address(0), reputationOracle, configEncoded);
    }

    function test_RevertWhen_DeploymentWithZeroOracle() public {
        bytes memory configEncoded = abi.encode(defaultConfig);
        
        vm.expectRevert(ArbitrationProxy.InvalidAddress.selector);
        new ArbitrationProxy(dao, address(0), configEncoded);
    }

    // ==================== SUPPORT AGENT MANAGEMENT TESTS ====================

    function test_AddSupportAgentByDAO() public {
        vm.prank(dao);
        vm.expectEmit(true, false, false, true);
        emit ArbitrationProxy.SupportAgentAdded(supportAgent1, "Agent One");
        arbitration.addSupportAgent(supportAgent1, "Agent One");
        
        assertTrue(arbitration.isActiveSupportAgent(supportAgent1));
        
        bytes memory agentData = arbitration.getSupportAgent(supportAgent1);
        ArbitrationProxy.SupportAgent memory agent = abi.decode(agentData, (ArbitrationProxy.SupportAgent));
        assertEq(agent.agentAddress, supportAgent1);
        assertEq(agent.name, "Agent One");
        assertTrue(agent.isActive);
        assertEq(agent.disputesResolved, 0);
    }

    function test_RevertWhen_AddSupportAgentByUnauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert(ArbitrationProxy.OnlyDAO.selector);
        arbitration.addSupportAgent(supportAgent1, "Agent One");
    }

    function test_RevertWhen_AddZeroAddressAgent() public {
        vm.prank(dao);
        vm.expectRevert(ArbitrationProxy.InvalidAddress.selector);
        arbitration.addSupportAgent(address(0), "Agent Zero");
    }

    function test_RevertWhen_AddExistingAgent() public {
        vm.prank(dao);
        arbitration.addSupportAgent(supportAgent1, "Agent One");
        
        vm.prank(dao);
        vm.expectRevert(ArbitrationProxy.AgentAlreadyExists.selector);
        arbitration.addSupportAgent(supportAgent1, "Agent One Again");
    }

    function test_RemoveSupportAgentByDAO() public {
        vm.prank(dao);
        arbitration.addSupportAgent(supportAgent1, "Agent One");
        assertTrue(arbitration.isActiveSupportAgent(supportAgent1));
        
        vm.prank(dao);
        vm.expectEmit(true, false, false, false);
        emit ArbitrationProxy.SupportAgentRemoved(supportAgent1);
        arbitration.removeSupportAgent(supportAgent1);
        
        assertFalse(arbitration.isActiveSupportAgent(supportAgent1));
    }

    function test_RevertWhen_RemoveNonExistentAgent() public {
        vm.prank(dao);
        vm.expectRevert(ArbitrationProxy.AgentNotFound.selector);
        arbitration.removeSupportAgent(supportAgent1);
    }

    function test_UpdateSupportAgentByDAO() public {
        vm.prank(dao);
        arbitration.addSupportAgent(supportAgent1, "Agent One");
        
        vm.prank(dao);
        vm.expectEmit(true, false, false, true);
        emit ArbitrationProxy.SupportAgentUpdated(supportAgent1, "Agent One Updated");
        arbitration.updateSupportAgent(supportAgent1, "Agent One Updated");
        
        bytes memory agentData = arbitration.getSupportAgent(supportAgent1);
        ArbitrationProxy.SupportAgent memory agent = abi.decode(agentData, (ArbitrationProxy.SupportAgent));
        assertEq(agent.name, "Agent One Updated");
    }

    // ==================== AUTHORIZED CONTRACT MANAGEMENT TESTS ====================

    function test_AddAuthorizedContractByDAO() public {
        vm.prank(dao);
        vm.expectEmit(true, false, false, false);
        emit ArbitrationProxy.AuthorizedContractAdded(escrowContract1);
        arbitration.addAuthorizedContract(escrowContract1);
        
        assertTrue(arbitration.isAuthorizedContract(escrowContract1));
    }

    function test_RevertWhen_AddZeroAddressContract() public {
        vm.prank(dao);
        vm.expectRevert(ArbitrationProxy.InvalidAddress.selector);
        arbitration.addAuthorizedContract(address(0));
    }

    function test_RevertWhen_AddExistingContract() public {
        vm.prank(dao);
        arbitration.addAuthorizedContract(escrowContract1);
        
        vm.prank(dao);
        vm.expectRevert(ArbitrationProxy.ContractAlreadyAuthorized.selector);
        arbitration.addAuthorizedContract(escrowContract1);
    }

    function test_RemoveAuthorizedContractByDAO() public {
        vm.prank(dao);
        arbitration.addAuthorizedContract(escrowContract1);
        assertTrue(arbitration.isAuthorizedContract(escrowContract1));
        
        vm.prank(dao);
        vm.expectEmit(true, false, false, false);
        emit ArbitrationProxy.AuthorizedContractRemoved(escrowContract1);
        arbitration.removeAuthorizedContract(escrowContract1);
        
        assertFalse(arbitration.isAuthorizedContract(escrowContract1));
    }

    function test_RevertWhen_RemoveNonAuthorizedContract() public {
        vm.prank(dao);
        vm.expectRevert(ArbitrationProxy.ContractNotAuthorized.selector);
        arbitration.removeAuthorizedContract(escrowContract1);
    }

    // ==================== DISPUTE CREATION TESTS ====================

    function test_CreateDisputeByAuthorizedContract() public {
        // First authorize the contract and add agent
        vm.prank(dao);
        arbitration.addAuthorizedContract(escrowContract1);
        
        vm.prank(escrowContract1);
        vm.expectEmit(true, true, true, true);
        emit ArbitrationProxy.DisputeCreated(0, 123, escrowContract1, buyer1, seller1, 1 ether, disputer1);
        uint256 disputeId = arbitration.createDispute(123, buyer1, seller1, 1 ether, disputer1);
        
        assertEq(disputeId, 0);
        assertEq(arbitration.getActiveDisputeCount(), 1);
        
        bytes memory disputeData = arbitration.getDispute(disputeId);
        ArbitrationProxy.Dispute memory dispute = abi.decode(disputeData, (ArbitrationProxy.Dispute));
        
        assertEq(dispute.id, 0);
        assertEq(dispute.escrowId, 123);
        assertEq(dispute.escrowContract, escrowContract1);
        assertEq(dispute.buyer, buyer1);
        assertEq(dispute.seller, seller1);
        assertEq(dispute.amount, 1 ether);
        assertEq(dispute.disputer, disputer1);
        assertEq(uint256(dispute.status), uint256(ArbitrationProxy.DisputeStatus.ACTIVE));
    }

    function test_RevertWhen_CreateDisputeByUnauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert(ArbitrationProxy.OnlyAuthorizedContract.selector);
        arbitration.createDispute(123, buyer1, seller1, 1 ether, disputer1);
    }

    function test_RevertWhen_CreateDisputeWhilePaused() public {
        vm.startPrank(dao);
        arbitration.addAuthorizedContract(escrowContract1);
        arbitration.pause();
        vm.stopPrank();
        
        vm.prank(escrowContract1);
        vm.expectRevert(ArbitrationProxy.ContractPaused.selector);
        arbitration.createDispute(123, buyer1, seller1, 1 ether, disputer1);
    }

    function test_RevertWhen_CreateDisputeWithZeroAddresses() public {
        vm.prank(dao);
        arbitration.addAuthorizedContract(escrowContract1);
        
        vm.prank(escrowContract1);
        vm.expectRevert(ArbitrationProxy.InvalidAddress.selector);
        arbitration.createDispute(123, address(0), seller1, 1 ether, disputer1);
        
        vm.prank(escrowContract1);
        vm.expectRevert(ArbitrationProxy.InvalidAddress.selector);
        arbitration.createDispute(123, buyer1, address(0), 1 ether, disputer1);
        
        vm.prank(escrowContract1);
        vm.expectRevert(ArbitrationProxy.InvalidAddress.selector);
        arbitration.createDispute(123, buyer1, seller1, 1 ether, address(0));
    }

    // ==================== DISPUTE RESOLUTION TESTS ====================

    function test_ResolveDisputeBySupportAgent() public {
        // Setup: authorize contract, add agent, create dispute
        vm.startPrank(dao);
        arbitration.addAuthorizedContract(address(mockEscrow));
        arbitration.addSupportAgent(supportAgent1, "Agent One");
        vm.stopPrank();
        
        vm.prank(address(mockEscrow));
        uint256 disputeId = arbitration.createDispute(123, buyer1, seller1, 1 ether, disputer1);
        
        // Resolve dispute
        vm.prank(supportAgent1);
        vm.expectEmit(true, false, true, true);
        emit ArbitrationProxy.DisputeResolved(disputeId, ArbitrationProxy.Ruling.BUYER_WINS, supportAgent1, "Buyer provided valid proof");
        arbitration.resolveDispute(disputeId, uint256(ArbitrationProxy.Ruling.BUYER_WINS), "Buyer provided valid proof");
        
        // Check dispute was resolved
        bytes memory disputeData = arbitration.getDispute(disputeId);
        ArbitrationProxy.Dispute memory dispute = abi.decode(disputeData, (ArbitrationProxy.Dispute));
        assertEq(uint256(dispute.status), uint256(ArbitrationProxy.DisputeStatus.RESOLVED));
        assertEq(uint256(dispute.ruling), uint256(ArbitrationProxy.Ruling.BUYER_WINS));
        assertEq(dispute.resolution, "Buyer provided valid proof");
        assertTrue(dispute.resolvedAt > 0);
        
        // Check active dispute count decreased
        assertEq(arbitration.getActiveDisputeCount(), 0);
        
        // Check agent stats updated
        bytes memory agentData = arbitration.getSupportAgent(supportAgent1);
        ArbitrationProxy.SupportAgent memory agent = abi.decode(agentData, (ArbitrationProxy.SupportAgent));
        assertEq(agent.disputesResolved, 1);
        
        // Check escrow callback was made
        assertTrue(mockEscrow.callbackReceived());
        assertEq(mockEscrow.lastEscrowId(), 123);
        assertEq(mockEscrow.lastRuling(), uint256(ArbitrationProxy.Ruling.BUYER_WINS));
    }

    function test_ResolveDisputeWithDifferentRulings() public {
        vm.startPrank(dao);
        arbitration.addAuthorizedContract(address(mockEscrow));
        arbitration.addSupportAgent(supportAgent1, "Agent One");
        vm.stopPrank();
        
        // Test TIE_REFUSE ruling
        vm.prank(address(mockEscrow));
        uint256 disputeId1 = arbitration.createDispute(123, buyer1, seller1, 1 ether, disputer1);
        
        vm.prank(supportAgent1);
        arbitration.resolveDispute(disputeId1, uint256(ArbitrationProxy.Ruling.TIE_REFUSE), "Insufficient evidence");
        
        bytes memory disputeData1 = arbitration.getDispute(disputeId1);
        ArbitrationProxy.Dispute memory dispute1 = abi.decode(disputeData1, (ArbitrationProxy.Dispute));
        assertEq(uint256(dispute1.ruling), uint256(ArbitrationProxy.Ruling.TIE_REFUSE));
        
        // Test SELLER_WINS ruling
        vm.prank(address(mockEscrow));
        uint256 disputeId2 = arbitration.createDispute(124, buyer1, seller1, 1 ether, disputer1);
        
        vm.prank(supportAgent1);
        arbitration.resolveDispute(disputeId2, uint256(ArbitrationProxy.Ruling.SELLER_WINS), "Seller provided valid proof");
        
        bytes memory disputeData2 = arbitration.getDispute(disputeId2);
        ArbitrationProxy.Dispute memory dispute2 = abi.decode(disputeData2, (ArbitrationProxy.Dispute));
        assertEq(uint256(dispute2.ruling), uint256(ArbitrationProxy.Ruling.SELLER_WINS));
    }

    function test_RevertWhen_ResolveDisputeByNonAgent() public {
        vm.prank(dao);
        arbitration.addAuthorizedContract(escrowContract1);
        
        vm.prank(escrowContract1);
        uint256 disputeId = arbitration.createDispute(123, buyer1, seller1, 1 ether, disputer1);
        
        vm.prank(unauthorized);
        vm.expectRevert(ArbitrationProxy.OnlyActiveSupportAgent.selector);
        arbitration.resolveDispute(disputeId, uint256(ArbitrationProxy.Ruling.BUYER_WINS), "Resolution");
    }

    function test_RevertWhen_ResolveNonExistentDispute() public {
        vm.prank(dao);
        arbitration.addSupportAgent(supportAgent1, "Agent One");
        
        vm.prank(supportAgent1);
        vm.expectRevert(ArbitrationProxy.DisputeNotFound.selector);
        arbitration.resolveDispute(999, uint256(ArbitrationProxy.Ruling.BUYER_WINS), "Resolution");
    }

    function test_RevertWhen_ResolveAlreadyResolvedDispute() public {
        vm.startPrank(dao);
        arbitration.addAuthorizedContract(address(mockEscrow));
        arbitration.addSupportAgent(supportAgent1, "Agent One");
        vm.stopPrank();
        
        vm.prank(address(mockEscrow));
        uint256 disputeId = arbitration.createDispute(123, buyer1, seller1, 1 ether, disputer1);
        
        vm.prank(supportAgent1);
        arbitration.resolveDispute(disputeId, uint256(ArbitrationProxy.Ruling.BUYER_WINS), "First resolution");
        
        vm.prank(supportAgent1);
        vm.expectRevert(ArbitrationProxy.DisputeAlreadyResolved.selector);
        arbitration.resolveDispute(disputeId, uint256(ArbitrationProxy.Ruling.SELLER_WINS), "Second resolution");
    }

    function test_RevertWhen_ResolveWithInvalidRuling() public {
        vm.startPrank(dao);
        arbitration.addAuthorizedContract(escrowContract1);
        arbitration.addSupportAgent(supportAgent1, "Agent One");
        vm.stopPrank();
        
        vm.prank(escrowContract1);
        uint256 disputeId = arbitration.createDispute(123, buyer1, seller1, 1 ether, disputer1);
        
        vm.prank(supportAgent1);
        vm.expectRevert(ArbitrationProxy.InvalidRuling.selector);
        arbitration.resolveDispute(disputeId, 999, "Invalid ruling");
    }

    // ==================== PAUSE FUNCTIONALITY TESTS ====================

    function test_PauseByDAO() public {
        assertFalse(arbitration.isPaused());
        
        vm.prank(dao);
        vm.expectEmit(false, false, false, false);
        emit ArbitrationProxy.Paused();
        arbitration.pause();
        
        assertTrue(arbitration.isPaused());
    }

    function test_UnpauseByDAO() public {
        vm.prank(dao);
        arbitration.pause();
        assertTrue(arbitration.isPaused());
        
        vm.prank(dao);
        vm.expectEmit(false, false, false, false);
        emit ArbitrationProxy.Unpaused();
        arbitration.unpause();
        
        assertFalse(arbitration.isPaused());
    }

    function test_ResolutionWorksWhilePaused() public {
        // Setup dispute while not paused
        vm.startPrank(dao);
        arbitration.addAuthorizedContract(address(mockEscrow));
        arbitration.addSupportAgent(supportAgent1, "Agent One");
        vm.stopPrank();
        
        vm.prank(address(mockEscrow));
        uint256 disputeId = arbitration.createDispute(123, buyer1, seller1, 1 ether, disputer1);
        
        // Pause the contract
        vm.prank(dao);
        arbitration.pause();
        
        // Resolution should still work
        vm.prank(supportAgent1);
        arbitration.resolveDispute(disputeId, uint256(ArbitrationProxy.Ruling.BUYER_WINS), "Resolution while paused");
        
        bytes memory disputeData = arbitration.getDispute(disputeId);
        ArbitrationProxy.Dispute memory dispute = abi.decode(disputeData, (ArbitrationProxy.Dispute));
        assertEq(uint256(dispute.status), uint256(ArbitrationProxy.DisputeStatus.RESOLVED));
    }

    // ==================== CONFIGURATION MANAGEMENT TESTS ====================

    function test_UpdateConfigByDAO() public {
        ArbitrationProxy.ArbitrationConfig memory newConfig = ArbitrationProxy.ArbitrationConfig({
            paused: true,
            feeRecipient: newDAO,
            baseFee: 0.02 ether
        });
        
        bytes memory configEncoded = abi.encode(newConfig);
        
        vm.prank(dao);
        vm.expectEmit(false, false, false, true);
        emit ArbitrationProxy.ConfigUpdated(configEncoded);
        arbitration.updateConfig(configEncoded);
        
        ArbitrationProxy.ArbitrationConfig memory storedConfig = arbitration.getConfig();
        assertEq(storedConfig.paused, true);
        assertEq(storedConfig.feeRecipient, newDAO);
        assertEq(storedConfig.baseFee, 0.02 ether);
    }

    // ==================== DAO MANAGEMENT TESTS ====================

    function test_UpdateDAOByCurrentDAO() public {
        assertEq(arbitration.dao(), dao);
        
        vm.prank(dao);
        vm.expectEmit(true, true, false, false);
        emit ArbitrationProxy.DAOUpdated(dao, newDAO);
        arbitration.updateDAO(newDAO);
        
        assertEq(arbitration.dao(), newDAO);
    }

    function test_RevertWhen_UpdateDAOByUnauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert(ArbitrationProxy.OnlyDAO.selector);
        arbitration.updateDAO(newDAO);
    }

    function test_RevertWhen_UpdateDAOToZeroAddress() public {
        vm.prank(dao);
        vm.expectRevert(ArbitrationProxy.InvalidAddress.selector);
        arbitration.updateDAO(address(0));
    }

    // ==================== VIEW FUNCTION TESTS ====================

    function test_GetActiveDisputesWithPagination() public {
        vm.prank(dao);
        arbitration.addAuthorizedContract(escrowContract1);
        
        // Create multiple disputes
        vm.startPrank(escrowContract1);
        arbitration.createDispute(101, buyer1, seller1, 1 ether, disputer1);
        arbitration.createDispute(102, buyer1, seller1, 1 ether, disputer1);
        arbitration.createDispute(103, buyer1, seller1, 1 ether, disputer1);
        vm.stopPrank();
        
        // Test pagination
        bytes[] memory disputes = arbitration.getActiveDisputes(0, 2);
        assertEq(disputes.length, 2);
        
        // Test offset
        bytes[] memory disputes2 = arbitration.getActiveDisputes(1, 2);
        assertEq(disputes2.length, 2);
        
        // Test limit beyond available
        bytes[] memory disputes3 = arbitration.getActiveDisputes(2, 5);
        assertEq(disputes3.length, 1);
    }

    function test_RevertWhen_GetActiveDisputesWithZeroLimit() public {
        vm.expectRevert(ArbitrationProxy.InvalidLimit.selector);
        arbitration.getActiveDisputes(0, 0);
    }

    function test_RevertWhen_GetActiveDisputesWithInvalidOffset() public {
        vm.expectRevert(ArbitrationProxy.InvalidOffset.selector);
        arbitration.getActiveDisputes(1, 1); // No disputes exist, so offset 1 is invalid
    }

    function test_GetDisputeEvidence() public {
        vm.prank(dao);
        arbitration.addAuthorizedContract(escrowContract1);
        
        vm.prank(escrowContract1);
        uint256 disputeId = arbitration.createDispute(123, buyer1, seller1, 1 ether, disputer1);
        
        bytes[] memory evidence = arbitration.getDisputeEvidence(disputeId);
        assertEq(evidence.length, 0); // Evidence is off-chain for now
    }

    function test_RevertWhen_GetNonExistentDispute() public {
        vm.expectRevert(ArbitrationProxy.DisputeNotFound.selector);
        arbitration.getDispute(999);
    }

    function test_RevertWhen_GetNonExistentAgent() public {
        vm.expectRevert(ArbitrationProxy.AgentNotFound.selector);
        arbitration.getSupportAgent(unauthorized);
    }

    // ==================== INTEGRATION TESTS ====================

    function test_CompleteWorkflow() public {
        // Setup: Add authorized contract and support agent
        vm.startPrank(dao);
        arbitration.addAuthorizedContract(address(mockEscrow));
        arbitration.addSupportAgent(supportAgent1, "Agent One");
        arbitration.addSupportAgent(supportAgent2, "Agent Two");
        vm.stopPrank();
        
        // Create multiple disputes
        vm.startPrank(address(mockEscrow));
        uint256 disputeId1 = arbitration.createDispute(101, buyer1, seller1, 1 ether, disputer1);
        uint256 disputeId2 = arbitration.createDispute(102, buyer1, seller1, 2 ether, disputer1);
        vm.stopPrank();
        
        assertEq(arbitration.getActiveDisputeCount(), 2);
        
        // Resolve first dispute
        vm.prank(supportAgent1);
        arbitration.resolveDispute(disputeId1, uint256(ArbitrationProxy.Ruling.BUYER_WINS), "Buyer wins dispute 1");
        
        assertEq(arbitration.getActiveDisputeCount(), 1);
        
        // Resolve second dispute
        vm.prank(supportAgent2);
        arbitration.resolveDispute(disputeId2, uint256(ArbitrationProxy.Ruling.SELLER_WINS), "Seller wins dispute 2");
        
        assertEq(arbitration.getActiveDisputeCount(), 0);
        
        // Check agent stats
        bytes memory agent1Data = arbitration.getSupportAgent(supportAgent1);
        bytes memory agent2Data = arbitration.getSupportAgent(supportAgent2);
        
        ArbitrationProxy.SupportAgent memory agent1 = abi.decode(agent1Data, (ArbitrationProxy.SupportAgent));
        ArbitrationProxy.SupportAgent memory agent2 = abi.decode(agent2Data, (ArbitrationProxy.SupportAgent));
        
        assertEq(agent1.disputesResolved, 1);
        assertEq(agent2.disputesResolved, 1);
        
        // Verify callbacks were made
        assertTrue(mockEscrow.callbackReceived());
    }

    function test_AccessControlEnforcement() public {
        // Test all DAO-only functions with unauthorized user
        vm.startPrank(unauthorized);
        
        vm.expectRevert(ArbitrationProxy.OnlyDAO.selector);
        arbitration.addSupportAgent(supportAgent1, "Agent");
        
        vm.expectRevert(ArbitrationProxy.OnlyDAO.selector);
        arbitration.removeSupportAgent(supportAgent1);
        
        vm.expectRevert(ArbitrationProxy.OnlyDAO.selector);
        arbitration.updateSupportAgent(supportAgent1, "New Name");
        
        vm.expectRevert(ArbitrationProxy.OnlyDAO.selector);
        arbitration.addAuthorizedContract(escrowContract1);
        
        vm.expectRevert(ArbitrationProxy.OnlyDAO.selector);
        arbitration.removeAuthorizedContract(escrowContract1);
        
        vm.expectRevert(ArbitrationProxy.OnlyDAO.selector);
        arbitration.updateConfig(abi.encode(defaultConfig));
        
        vm.expectRevert(ArbitrationProxy.OnlyDAO.selector);
        arbitration.pause();
        
        vm.expectRevert(ArbitrationProxy.OnlyDAO.selector);
        arbitration.unpause();
        
        vm.expectRevert(ArbitrationProxy.OnlyDAO.selector);
        arbitration.updateDAO(newDAO);
        
        vm.stopPrank();
    }

    // ==================== FUZZ TESTS ====================

    function testFuzz_CreateMultipleDisputes(uint8 numDisputes) public {
        vm.assume(numDisputes > 0 && numDisputes <= 10); // Reasonable bounds
        
        vm.prank(dao);
        arbitration.addAuthorizedContract(escrowContract1);
        
        vm.startPrank(escrowContract1);
        for (uint256 i = 0; i < numDisputes; i++) {
            arbitration.createDispute(100 + i, buyer1, seller1, 1 ether, disputer1);
        }
        vm.stopPrank();
        
        assertEq(arbitration.getActiveDisputeCount(), numDisputes);
    }

    function testFuzz_ResolveDisputeWithValidRuling(uint256 ruling) public {
        ruling = bound(ruling, 0, 2); // Valid ruling range
        
        vm.startPrank(dao);
        arbitration.addAuthorizedContract(address(mockEscrow));
        arbitration.addSupportAgent(supportAgent1, "Agent");
        vm.stopPrank();
        
        vm.prank(address(mockEscrow));
        uint256 disputeId = arbitration.createDispute(123, buyer1, seller1, 1 ether, disputer1);
        
        vm.prank(supportAgent1);
        arbitration.resolveDispute(disputeId, ruling, "Fuzz test resolution");
        
        bytes memory disputeData = arbitration.getDispute(disputeId);
        ArbitrationProxy.Dispute memory dispute = abi.decode(disputeData, (ArbitrationProxy.Dispute));
        assertEq(uint256(dispute.ruling), ruling);
        assertEq(uint256(dispute.status), uint256(ArbitrationProxy.DisputeStatus.RESOLVED));
    }

    function testFuzz_PaginationBounds(uint256 offset, uint256 limit) public {
        offset = bound(offset, 0, 50);
        limit = bound(limit, 1, 20);
        
        vm.prank(dao);
        arbitration.addAuthorizedContract(escrowContract1);
        
        // Create some disputes
        vm.startPrank(escrowContract1);
        for (uint256 i = 0; i < 5; i++) {
            arbitration.createDispute(100 + i, buyer1, seller1, 1 ether, disputer1);
        }
        vm.stopPrank();
        
        if (offset < 5) {
            bytes[] memory disputes = arbitration.getActiveDisputes(offset, limit);
            assertTrue(disputes.length <= limit);
            assertTrue(disputes.length <= (5 - offset));
        } else {
            vm.expectRevert(ArbitrationProxy.InvalidOffset.selector);
            arbitration.getActiveDisputes(offset, limit);
        }
    }
}

/**
 * @title MockEscrowContract
 * @notice Mock contract to test arbitration callbacks
 */
contract MockEscrowContract {
    bool public callbackReceived;
    uint256 public lastEscrowId;
    uint256 public lastRuling;
    
    function handleArbitrationRuling(uint256 escrowId, uint256 ruling) external {
        callbackReceived = true;
        lastEscrowId = escrowId;
        lastRuling = ruling;
    }
}
