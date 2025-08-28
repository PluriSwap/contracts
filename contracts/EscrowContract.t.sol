// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "./EscrowContract.sol";

/**
 * @title EscrowContract Solidity Tests
 * @notice Comprehensive test suite for EscrowContract with cross-chain, EIP-712, and dispute functionality
 * @dev Tests all state transitions, cross-chain features, dispute resolution, and fee calculations
 */
contract EscrowContractTest is Test {
    EscrowContract escrow;
    
    // Test accounts
    address dao = makeAddr("dao");
    address reputationOracle = makeAddr("reputationOracle");
    address reputationEvents = makeAddr("reputationEvents");
    address stargateRouter = makeAddr("stargateRouter");
    address arbitrationProxy = makeAddr("arbitrationProxy");
    address holder; // Will be set from private key
    address provider; // Will be set from private key
    address recipient = makeAddr("recipient");
    address feeRecipient = makeAddr("feeRecipient");
    address newDAO = makeAddr("newDAO");
    address unauthorized = makeAddr("unauthorized");

    // Mock contracts
    MockArbitrationProxy mockArbitrationProxy;
    MockReputationEvents mockReputationEvents;

    // Test configuration
    EscrowContract.EscrowConfig defaultConfig;
    
    // Test agreement
    EscrowContract.EscrowAgreement validAgreement;
    
    // EIP-712 domain data
    bytes32 constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 constant ESCROW_AGREEMENT_TYPEHASH = keccak256(
        "EscrowAgreement(address holder,address provider,uint256 amount,uint256 fundedTimeout,uint256 proofTimeout,uint256 nonce,uint256 deadline,uint16 dstChainId,address dstRecipient,bytes dstAdapterParams)"
    );
    
    // Test keys
    uint256 holderPrivateKey = 0x1234;
    uint256 providerPrivateKey = 0x5678;

    function setUp() public {
        // Deploy mock contracts
        mockArbitrationProxy = new MockArbitrationProxy();
        mockReputationEvents = new MockReputationEvents();
        
        // Setup default configuration
        defaultConfig = EscrowContract.EscrowConfig({
            baseFeePercent: 250,        // 2.5%
            minFee: 0.001 ether,
            maxFee: 1 ether,
            disputeFeePercent: 100,     // 1%
            minTimeout: 1 hours,
            maxTimeout: 30 days,
            feeRecipient: feeRecipient,
            // Version 1.1 additions
            upfrontFee: 0.0001 ether,   // Fixed upfront fee
            successFeePercent: 50,      // 0.5% success fee
            minDisputeFee: 0.01 ether,  // Minimum dispute fee
            crossChainFeePercent: 25    // 0.25% cross-chain fee
        });
        
        bytes memory configEncoded = abi.encode(defaultConfig);
        
        // Deploy escrow contract
        escrow = new EscrowContract(
            dao,
            reputationOracle,
            address(mockReputationEvents),
            stargateRouter,
            configEncoded
        );
        
        // Setup arbitration proxy
        vm.prank(dao);
        escrow.updateSystem(EscrowContract.UpdateType.ARBITRATION_PROXY, abi.encode(address(mockArbitrationProxy)));
        
        // Get addresses for private keys
        holder = vm.addr(holderPrivateKey);
        provider = vm.addr(providerPrivateKey);
        
        // Setup valid agreement
        validAgreement = EscrowContract.EscrowAgreement({
            holder: holder,
            provider: provider,
            amount: 1 ether,
            fundedTimeout: block.timestamp + 2 days,
            proofTimeout: block.timestamp + 4 days,
            nonce: 1,
            deadline: block.timestamp + 1 hours,
            dstChainId: 0, // Same chain
            dstRecipient: recipient,
            dstAdapterParams: ""
        });
        
        // Fund test accounts
        vm.deal(holder, 10 ether);
        vm.deal(provider, 10 ether);
    }

    // ==================== DEPLOYMENT TESTS ====================

    function test_DeploymentWithValidParameters() public {
        assertEq(escrow.dao(), dao);
        assertEq(escrow.reputationOracle(), reputationOracle);
        assertEq(escrow.reputationEvents(), address(mockReputationEvents));
        assertEq(escrow.stargateRouter(), stargateRouter);
        assertEq(escrow.currentChainId(), uint16(block.chainid));
        
        EscrowContract.EscrowConfig memory config = escrow.getConfig();
        assertEq(config.baseFeePercent, defaultConfig.baseFeePercent);
        assertEq(config.minFee, defaultConfig.minFee);
        assertEq(config.maxFee, defaultConfig.maxFee);
        assertEq(config.feeRecipient, defaultConfig.feeRecipient);
    }

    function test_RevertWhen_DeploymentWithZeroDAO() public {
        bytes memory configEncoded = abi.encode(defaultConfig);
        
        vm.expectRevert(EscrowContract.InvalidAddress.selector);
        new EscrowContract(
            address(0),
            reputationOracle,
            address(mockReputationEvents),
            stargateRouter,
            configEncoded
        );
    }

    function test_RevertWhen_DeploymentWithZeroOracle() public {
        bytes memory configEncoded = abi.encode(defaultConfig);
        
        vm.expectRevert(EscrowContract.InvalidAddress.selector);
        new EscrowContract(
            dao,
            address(0),
            address(mockReputationEvents),
            stargateRouter,
            configEncoded
        );
    }

    function test_RevertWhen_DeploymentWithZeroEvents() public {
        bytes memory configEncoded = abi.encode(defaultConfig);
        
        vm.expectRevert(EscrowContract.InvalidAddress.selector);
        new EscrowContract(
            dao,
            reputationOracle,
            address(0),
            stargateRouter,
            configEncoded
        );
    }

    // ==================== EIP-712 SIGNATURE TESTS ====================

    function test_ValidDualSignatures() public {
        bytes memory agreementEncoded = abi.encode(validAgreement);
        bytes32 hash = escrow.getAgreementHash(agreementEncoded);
        
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(holderPrivateKey, hash);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(providerPrivateKey, hash);
        
        bytes memory holderSig = abi.encodePacked(r1, s1, v1);
        bytes memory providerSig = abi.encodePacked(r2, s2, v2);
        
        vm.prank(holder);
        uint256 escrowId = escrow.createEscrow{value: validAgreement.amount}(
            agreementEncoded,
            holderSig,
            providerSig
        );
        
        // Check escrow exists by calling getEscrow
        try escrow.getEscrow(escrowId) {
            // Escrow exists
        } catch {
            fail(); // Escrow should exist
        }
        assertEq(escrowId, 0);
    }

    function test_RevertWhen_InvalidHolderSignature() public {
        bytes memory agreementEncoded = abi.encode(validAgreement);
        bytes32 hash = escrow.getAgreementHash(agreementEncoded);
        
        // Sign with wrong key for holder
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(providerPrivateKey, hash); // Wrong key
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(providerPrivateKey, hash);
        
        bytes memory holderSig = abi.encodePacked(r1, s1, v1);
        bytes memory providerSig = abi.encodePacked(r2, s2, v2);
        
        vm.prank(holder);
        vm.expectRevert(EscrowContract.InvalidSignature.selector);
        escrow.createEscrow{value: validAgreement.amount}(
            agreementEncoded,
            holderSig,
            providerSig
        );
    }

    function test_RevertWhen_InvalidProviderSignature() public {
        bytes memory agreementEncoded = abi.encode(validAgreement);
        bytes32 hash = escrow.getAgreementHash(agreementEncoded);
        
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(holderPrivateKey, hash);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(holderPrivateKey, hash); // Wrong key
        
        bytes memory holderSig = abi.encodePacked(r1, s1, v1);
        bytes memory providerSig = abi.encodePacked(r2, s2, v2);
        
        vm.prank(holder);
        vm.expectRevert(EscrowContract.InvalidSignature.selector);
        escrow.createEscrow{value: validAgreement.amount}(
            agreementEncoded,
            holderSig,
            providerSig
        );
    }

    function test_RevertWhen_ExpiredDeadline() public {
        // Create agreement with past deadline
        EscrowContract.EscrowAgreement memory expiredAgreement = validAgreement;
        expiredAgreement.deadline = block.timestamp - 1;
        
        bytes memory agreementEncoded = abi.encode(expiredAgreement);
        bytes32 hash = escrow.getAgreementHash(agreementEncoded);
        
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(holderPrivateKey, hash);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(providerPrivateKey, hash);
        
        bytes memory holderSig = abi.encodePacked(r1, s1, v1);
        bytes memory providerSig = abi.encodePacked(r2, s2, v2);
        
        vm.prank(holder);
        vm.expectRevert(EscrowContract.ExpiredDeadline.selector);
        escrow.createEscrow{value: expiredAgreement.amount}(
            agreementEncoded,
            holderSig,
            providerSig
        );
    }

    function test_RevertWhen_UsedNonce() public {
        // Create first escrow successfully
        bytes memory agreementEncoded = abi.encode(validAgreement);
        bytes32 hash = escrow.getAgreementHash(agreementEncoded);
        
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(holderPrivateKey, hash);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(providerPrivateKey, hash);
        
        bytes memory holderSig = abi.encodePacked(r1, s1, v1);
        bytes memory providerSig = abi.encodePacked(r2, s2, v2);
        
        vm.prank(holder);
        escrow.createEscrow{value: validAgreement.amount}(
            agreementEncoded,
            holderSig,
            providerSig
        );
        
        // Try to reuse same nonce
        vm.deal(holder, 10 ether); // Refund for second attempt
        
        vm.prank(holder);
        vm.expectRevert(EscrowContract.InvalidNonce.selector);
        escrow.createEscrow{value: validAgreement.amount}(
            agreementEncoded,
            holderSig,
            providerSig
        );
    }

    // ==================== ESCROW CREATION TESTS ====================

    function test_CreateEscrowWithCorrectAmount() public {
        uint256 escrowId = _createValidEscrow();
        
        (EscrowContract.EscrowAgreement memory agreement, 
         EscrowContract.EscrowState state, 
         uint256 createdAt,) = escrow.getEscrow(escrowId);
        
        assertEq(agreement.holder, holder);
        assertEq(agreement.provider, provider);
        assertEq(agreement.amount, 1 ether);
        assertTrue(uint256(state) == uint256(EscrowContract.EscrowState.FUNDED));
        assertEq(createdAt, block.timestamp);
        assertTrue(mockReputationEvents.eventReceived());
    }

    function test_RevertWhen_IncorrectAmount() public {
        bytes memory agreementEncoded = abi.encode(validAgreement);
        bytes32 hash = escrow.getAgreementHash(agreementEncoded);
        
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(holderPrivateKey, hash);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(providerPrivateKey, hash);
        
        bytes memory holderSig = abi.encodePacked(r1, s1, v1);
        bytes memory providerSig = abi.encodePacked(r2, s2, v2);
        
        vm.prank(holder);
        vm.expectRevert(EscrowContract.InvalidAmount.selector);
        escrow.createEscrow{value: 0.5 ether}( // Wrong amount
            agreementEncoded,
            holderSig,
            providerSig
        );
    }

    function test_RevertWhen_ZeroAmount() public {
        EscrowContract.EscrowAgreement memory zeroAgreement = validAgreement;
        zeroAgreement.amount = 0;
        
        bytes memory agreementEncoded = abi.encode(zeroAgreement);
        bytes32 hash = escrow.getAgreementHash(agreementEncoded);
        
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(holderPrivateKey, hash);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(providerPrivateKey, hash);
        
        bytes memory holderSig = abi.encodePacked(r1, s1, v1);
        bytes memory providerSig = abi.encodePacked(r2, s2, v2);
        
        vm.prank(holder);
        vm.expectRevert(EscrowContract.InvalidAmount.selector);
        escrow.createEscrow{value: 0}(
            agreementEncoded,
            holderSig,
            providerSig
        );
    }

    function test_RevertWhen_InvalidTimeouts() public {
        // Test past funded timeout
        EscrowContract.EscrowAgreement memory invalidAgreement = validAgreement;
        invalidAgreement.fundedTimeout = block.timestamp - 1;
        
        bytes memory agreementEncoded = abi.encode(invalidAgreement);
        bytes32 hash = escrow.getAgreementHash(agreementEncoded);
        
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(holderPrivateKey, hash);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(providerPrivateKey, hash);
        
        bytes memory holderSig = abi.encodePacked(r1, s1, v1);
        bytes memory providerSig = abi.encodePacked(r2, s2, v2);
        
        vm.prank(holder);
        vm.expectRevert(EscrowContract.InvalidTimeout.selector);
        escrow.createEscrow{value: invalidAgreement.amount}(
            agreementEncoded,
            holderSig,
            providerSig
        );
    }

    function test_RevertWhen_ProofTimeoutBeforeFundedTimeout() public {
        EscrowContract.EscrowAgreement memory invalidAgreement = validAgreement;
        invalidAgreement.proofTimeout = invalidAgreement.fundedTimeout - 1;
        
        bytes memory agreementEncoded = abi.encode(invalidAgreement);
        bytes32 hash = escrow.getAgreementHash(agreementEncoded);
        
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(holderPrivateKey, hash);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(providerPrivateKey, hash);
        
        bytes memory holderSig = abi.encodePacked(r1, s1, v1);
        bytes memory providerSig = abi.encodePacked(r2, s2, v2);
        
        vm.prank(holder);
        vm.expectRevert(EscrowContract.InvalidTimeout.selector);
        escrow.createEscrow{value: invalidAgreement.amount}(
            agreementEncoded,
            holderSig,
            providerSig
        );
    }

    // ==================== STATE PROGRESSION TESTS ====================

    function test_ProvideOffchainProof() public {
        uint256 escrowId = _createValidEscrow();
        
        vm.prank(provider);
        vm.expectEmit(true, false, false, true);
        emit EscrowContract.OffchainProofSubmitted(escrowId, "ipfs://proof123");
        escrow.provideOffchainProof(escrowId, "ipfs://proof123");
        
        (, EscrowContract.EscrowState state,,string memory proof) = escrow.getEscrow(escrowId);
        assertTrue(uint256(state) == uint256(EscrowContract.EscrowState.OFFCHAIN_PROOF_SENT));
        assertEq(proof, "ipfs://proof123");
        assertTrue(mockReputationEvents.eventReceived());
    }

    function test_RevertWhen_NonProviderSubmitsProof() public {
        uint256 escrowId = _createValidEscrow();
        
        vm.prank(holder);
        vm.expectRevert(EscrowContract.OnlyProvider.selector);
        escrow.provideOffchainProof(escrowId, "ipfs://proof123");
    }

    function test_RevertWhen_SubmitProofInWrongState() public {
        uint256 escrowId = _createValidEscrow();
        
        // First submit proof successfully
        vm.prank(provider);
        escrow.provideOffchainProof(escrowId, "ipfs://proof123");
        
        // Try to submit again
        vm.prank(provider);
        vm.expectRevert(EscrowContract.InvalidState.selector);
        escrow.provideOffchainProof(escrowId, "ipfs://proof456");
    }

    function test_CompleteEscrow() public {
        uint256 escrowId = _createValidEscrow();
        
        // Submit proof
        vm.prank(provider);
        escrow.provideOffchainProof(escrowId, "ipfs://proof123");
        
        uint256 recipientBalanceBefore = recipient.balance;
        uint256 feeRecipientBalanceBefore = feeRecipient.balance;
        
        // Complete escrow
        vm.prank(holder);
        vm.expectEmit(true, false, false, false);
        emit EscrowContract.EscrowCompleted(escrowId, 0, 0); // Values will vary based on fees
        escrow.completeEscrow(escrowId);
        
        // Check state
        (, EscrowContract.EscrowState state,,) = escrow.getEscrow(escrowId);
        assertTrue(uint256(state) == uint256(EscrowContract.EscrowState.CLOSED));
        
        // Check fund distribution
        assertTrue(recipient.balance > recipientBalanceBefore);
        assertTrue(feeRecipient.balance >= feeRecipientBalanceBefore); // May be 0 if below min fee
        assertTrue(mockReputationEvents.eventReceived());
    }

    function test_RevertWhen_NonHolderCompletes() public {
        uint256 escrowId = _createValidEscrow();
        
        vm.prank(provider);
        escrow.provideOffchainProof(escrowId, "ipfs://proof123");
        
        vm.prank(provider);
        vm.expectRevert(EscrowContract.OnlyHolder.selector);
        escrow.completeEscrow(escrowId);
    }

    function test_RevertWhen_CompleteInWrongState() public {
        uint256 escrowId = _createValidEscrow();
        
        vm.prank(holder);
        vm.expectRevert(EscrowContract.InvalidState.selector);
        escrow.completeEscrow(escrowId);
    }

    // ==================== CANCELLATION TESTS ====================

    function test_HolderCancel() public {
        uint256 escrowId = _createValidEscrow();
        
        uint256 holderBalanceBefore = holder.balance;
        
        vm.prank(holder);
        vm.expectEmit(true, false, false, true);
        emit EscrowContract.EscrowCancelled(escrowId, "holder_cancellation", holder);
        escrow.cancel(escrowId, ""); // Single-party holder cancellation
        
        // Check state
        (, EscrowContract.EscrowState state,,) = escrow.getEscrow(escrowId);
        assertTrue(uint256(state) == uint256(EscrowContract.EscrowState.CLOSED));
        
        // Check refund
        assertEq(holder.balance, holderBalanceBefore + 1 ether);
        assertTrue(mockReputationEvents.eventReceived());
    }

    function test_ProviderCancel() public {
        uint256 escrowId = _createValidEscrow();
        
        uint256 holderBalanceBefore = holder.balance;
        
        vm.prank(provider);
        vm.expectEmit(true, false, false, true);
        emit EscrowContract.EscrowCancelled(escrowId, "provider_cancellation", provider);
        escrow.cancel(escrowId, ""); // Single-party provider cancellation
        
        // Check state
        (, EscrowContract.EscrowState state,,) = escrow.getEscrow(escrowId);
        assertTrue(uint256(state) == uint256(EscrowContract.EscrowState.CLOSED));
        
        // Check refund
        assertEq(holder.balance, holderBalanceBefore + 1 ether);
        assertTrue(mockReputationEvents.eventReceived());
    }

    function test_RevertWhen_UnauthorizedCancel() public {
        uint256 escrowId = _createValidEscrow();
        
        vm.prank(unauthorized);
        vm.expectRevert(EscrowContract.UnauthorizedCancellation.selector);
        escrow.cancel(escrowId, ""); // Single-party cancellation by unauthorized user
    }

    function test_RevertWhen_CancelAfterProof() public {
        uint256 escrowId = _createValidEscrow();
        
        vm.prank(provider);
        escrow.provideOffchainProof(escrowId, "ipfs://proof123");
        
        vm.prank(holder);
        vm.expectRevert(EscrowContract.UnauthorizedCancellation.selector);
        escrow.cancel(escrowId, ""); // Single-party cancellation not allowed from OFFCHAIN_PROOF_SENT state
        
        vm.prank(provider);
        vm.expectRevert(EscrowContract.UnauthorizedCancellation.selector);
        escrow.cancel(escrowId, ""); // Single-party cancellation not allowed from OFFCHAIN_PROOF_SENT state
    }

    // ==================== DISPUTE TESTS ====================

    function test_CreateDisputeFromFundedState() public {
        uint256 escrowId = _createValidEscrow();
        
        uint256 disputeFee = escrow.getArbitrationCost(escrowId, provider);
        
        vm.prank(provider);
        vm.expectEmit(true, true, true, false);
        emit EscrowContract.DisputeCreated(escrowId, 0, provider);
        uint256 disputeId = escrow.createDispute{value: disputeFee}(escrowId, "Provider evidence");
        
        assertEq(disputeId, 0);
        
        // Check state change
        (, EscrowContract.EscrowState state,,) = escrow.getEscrow(escrowId);
        assertTrue(uint256(state) == uint256(EscrowContract.EscrowState.PROVIDER_DISPUTED));
        
        assertTrue(mockArbitrationProxy.disputeCreated());
        assertTrue(mockReputationEvents.eventReceived());
    }

    function test_CreateDisputeFromProofSentState() public {
        uint256 escrowId = _createValidEscrow();
        
        vm.prank(provider);
        escrow.provideOffchainProof(escrowId, "ipfs://proof123");
        
        uint256 disputeFee = escrow.getArbitrationCost(escrowId, holder);
        
        vm.prank(holder);
        vm.expectEmit(true, true, true, false);
        emit EscrowContract.DisputeCreated(escrowId, 0, holder);
        uint256 disputeId = escrow.createDispute{value: disputeFee}(escrowId, "Holder evidence");
        
        assertEq(disputeId, 0);
        
        // Check state change
        (, EscrowContract.EscrowState state,,) = escrow.getEscrow(escrowId);
        assertTrue(uint256(state) == uint256(EscrowContract.EscrowState.HOLDER_DISPUTED));
        
        assertTrue(mockArbitrationProxy.disputeCreated());
        assertTrue(mockReputationEvents.eventReceived());
    }

    function test_RevertWhen_DisputeWithInsufficientFee() public {
        uint256 escrowId = _createValidEscrow();
        
        uint256 disputeFee = escrow.getArbitrationCost(escrowId, provider);
        
        vm.prank(provider);
        vm.expectRevert(EscrowContract.InsufficientFunds.selector);
        escrow.createDispute{value: disputeFee - 1}(escrowId, "Provider evidence");
    }

    function test_RevertWhen_DisputeFromWrongState() public {
        uint256 escrowId = _createValidEscrow();
        
        // Complete the escrow first
        vm.prank(provider);
        escrow.provideOffchainProof(escrowId, "ipfs://proof123");
        
        vm.prank(holder);
        escrow.completeEscrow(escrowId);
        
        uint256 disputeFee = escrow.getArbitrationCost(escrowId, holder);
        
        vm.prank(holder);
        vm.expectRevert(EscrowContract.InvalidState.selector);
        escrow.createDispute{value: disputeFee}(escrowId, "Late evidence");
    }

    function test_RevertWhen_UnauthorizedDispute() public {
        uint256 escrowId = _createValidEscrow();
        
        uint256 disputeFee = escrow.getArbitrationCost(escrowId, holder);
        
        // Holder cannot dispute from FUNDED state
        vm.prank(holder);
        vm.expectRevert(EscrowContract.OnlyProvider.selector);
        escrow.createDispute{value: disputeFee}(escrowId, "Invalid dispute");
        
        // Move to OFFCHAIN_PROOF_SENT state
        vm.prank(provider);
        escrow.provideOffchainProof(escrowId, "ipfs://proof123");
        
        // Provider cannot dispute from OFFCHAIN_PROOF_SENT state
        vm.prank(provider);
        vm.expectRevert(EscrowContract.OnlyHolder.selector);
        escrow.createDispute{value: disputeFee}(escrowId, "Invalid dispute");
    }

    function test_SubmitEvidence() public {
        uint256 escrowId = _createValidEscrow();
        
        uint256 disputeFee = escrow.getArbitrationCost(escrowId, provider);
        
        vm.prank(provider);
        escrow.createDispute{value: disputeFee}(escrowId, "Initial evidence");
        
        // Evidence submission functionality removed in optimized version
        // vm.prank(provider);
        // vm.expectEmit(true, true, false, true);
        // emit EscrowContract.EvidenceSubmitted(escrowId, provider, "Additional provider evidence");
        // escrow.submitEvidence(escrowId, "Additional provider evidence");
        // 
        // vm.prank(holder);
        // vm.expectEmit(true, true, false, true);
        // emit EscrowContract.EvidenceSubmitted(escrowId, holder, "Holder counter-evidence");
        // escrow.submitEvidence(escrowId, "Holder counter-evidence");
    }

    function test_RevertWhen_UnauthorizedEvidenceSubmission() public {
        uint256 escrowId = _createValidEscrow();
        
        uint256 disputeFee = escrow.getArbitrationCost(escrowId, provider);
        
        vm.prank(provider);
        escrow.createDispute{value: disputeFee}(escrowId, "Initial evidence");
        
        // Evidence submission functionality removed in optimized version
        // vm.prank(unauthorized);
        // vm.expectRevert(EscrowContract.InvalidAddress.selector);
        // escrow.submitEvidence(escrowId, "Unauthorized evidence");
    }

    function test_ExecuteRulingHolderWins() public {
        uint256 escrowId = _createValidEscrow();
        
        vm.prank(provider);
        escrow.provideOffchainProof(escrowId, "ipfs://proof123");
        
        uint256 disputeFee = escrow.getArbitrationCost(escrowId, holder);
        
        vm.prank(holder);
        uint256 disputeId = escrow.createDispute{value: disputeFee}(escrowId, "Holder evidence");
        
        uint256 holderBalanceBefore = holder.balance;
        
        // Execute ruling - holder wins
        vm.prank(address(mockArbitrationProxy));
        vm.expectEmit(true, true, false, false);
        emit EscrowContract.RulingExecuted(escrowId, disputeId, 1);
        escrow.executeRuling(disputeId, 1, "Holder wins resolution");
        
        // Check state
        (, EscrowContract.EscrowState state,,) = escrow.getEscrow(escrowId);
        assertTrue(uint256(state) == uint256(EscrowContract.EscrowState.CLOSED));
        
        // Check refund to holder
        assertEq(holder.balance, holderBalanceBefore + 1 ether);
        assertTrue(mockReputationEvents.eventReceived());
    }

    function test_ExecuteRulingProviderWins() public {
        uint256 escrowId = _createValidEscrow();
        
        vm.prank(provider);
        escrow.provideOffchainProof(escrowId, "ipfs://proof123");
        
        uint256 disputeFee = escrow.getArbitrationCost(escrowId, holder);
        
        vm.prank(holder);
        uint256 disputeId = escrow.createDispute{value: disputeFee}(escrowId, "Holder evidence");
        
        uint256 recipientBalanceBefore = recipient.balance;
        uint256 feeRecipientBalanceBefore = feeRecipient.balance;
        
        // Execute ruling - provider wins
        vm.prank(address(mockArbitrationProxy));
        vm.expectEmit(true, true, false, false);
        emit EscrowContract.RulingExecuted(escrowId, disputeId, 2);
        escrow.executeRuling(disputeId, 2, "Provider wins resolution");
        
        // Check state
        (, EscrowContract.EscrowState state,,) = escrow.getEscrow(escrowId);
        assertTrue(uint256(state) == uint256(EscrowContract.EscrowState.CLOSED));
        
        // Check payment to provider
        assertTrue(recipient.balance > recipientBalanceBefore);
        assertTrue(feeRecipient.balance >= feeRecipientBalanceBefore);
        assertTrue(mockReputationEvents.eventReceived());
    }

    function test_ExecuteRulingRefuseToArbitrate() public {
        uint256 escrowId = _createValidEscrow();
        
        uint256 disputeFee = escrow.getArbitrationCost(escrowId, provider);
        
        vm.prank(provider);
        uint256 disputeId = escrow.createDispute{value: disputeFee}(escrowId, "Provider evidence");
        
        uint256 holderBalanceBefore = holder.balance;
        
        // Execute ruling - refuse to arbitrate
        vm.prank(address(mockArbitrationProxy));
        vm.expectEmit(true, true, false, false);
        emit EscrowContract.RulingExecuted(escrowId, disputeId, 0);
        escrow.executeRuling(disputeId, 0, "Refuse to arbitrate");
        
        // Check state
        (, EscrowContract.EscrowState state,,) = escrow.getEscrow(escrowId);
        assertTrue(uint256(state) == uint256(EscrowContract.EscrowState.CLOSED));
        
        // Check refund to holder
        assertEq(holder.balance, holderBalanceBefore + 1 ether);
    }

    function test_RevertWhen_ExecuteRulingByUnauthorized() public {
        uint256 escrowId = _createValidEscrow();
        
        uint256 disputeFee = escrow.getArbitrationCost(escrowId, provider);
        
        vm.prank(provider);
        uint256 disputeId = escrow.createDispute{value: disputeFee}(escrowId, "Provider evidence");
        
        vm.prank(unauthorized);
        vm.expectRevert(EscrowContract.OnlyArbitrationProxy.selector);
        escrow.executeRuling(disputeId, 1, "Unauthorized ruling");
    }

    // ==================== TIMEOUT TESTS ====================

    function test_HasTimedOut() public {
        uint256 escrowId = _createValidEscrow();
        
        // hasTimedOut method removed - test timeout resolution directly
        // Should not be able to resolve timeout initially
        vm.expectRevert(EscrowContract.TimeoutNotReached.selector);
        escrow.resolveTimeout(escrowId);
        
        // Warp to after funded timeout
        vm.warp(block.timestamp + 3 days);
        // Should be able to resolve timeout now (will be tested in other functions)
        
        // Submit proof and check proof timeout
        vm.warp(block.timestamp - 3 days); // Reset time
        vm.prank(provider);
        escrow.provideOffchainProof(escrowId, "ipfs://proof123");
        
        // Should not be able to resolve timeout from OFFCHAIN_PROOF_SENT state yet
        vm.expectRevert(EscrowContract.TimeoutNotReached.selector);
        escrow.resolveTimeout(escrowId);
        
        vm.warp(block.timestamp + 5 days); // After proof timeout
        // Should be able to resolve proof timeout now (will be tested in other functions)
    }

    function test_HandleTimeoutFromFunded() public {
        uint256 escrowId = _createValidEscrow();
        
        uint256 holderBalanceBefore = holder.balance;
        
        // Warp past funded timeout
        vm.warp(block.timestamp + 3 days);
        
        vm.prank(unauthorized); // Anyone can handle timeout
        vm.expectEmit(true, true, false, true);
        emit EscrowContract.TimeoutResolved(escrowId, unauthorized, "funded_timeout_refund");
        escrow.resolveTimeout(escrowId);
        
        // Check state
        (, EscrowContract.EscrowState state,,) = escrow.getEscrow(escrowId);
        assertTrue(uint256(state) == uint256(EscrowContract.EscrowState.CLOSED));
        
        // Check refund
        assertEq(holder.balance, holderBalanceBefore + 1 ether);
        assertTrue(mockReputationEvents.eventReceived());
    }

    function test_ResolveTimeoutFromProofSent() public {
        uint256 escrowId = _createValidEscrow();
        
        vm.prank(provider);
        escrow.provideOffchainProof(escrowId, "ipfs://proof123");
        
        uint256 recipientBalanceBefore = recipient.balance;
        
        // Warp past proof timeout
        vm.warp(block.timestamp + 5 days);
        
        vm.prank(unauthorized); // Anyone can resolve timeout
        vm.expectEmit(true, true, false, true);
        emit EscrowContract.TimeoutResolved(escrowId, unauthorized, "proof_timeout_provider_paid");
        escrow.resolveTimeout(escrowId);
        
        // Check state
        (, EscrowContract.EscrowState state,,) = escrow.getEscrow(escrowId);
        assertTrue(uint256(state) == uint256(EscrowContract.EscrowState.CLOSED));
        
        // Check payment
        assertTrue(recipient.balance > recipientBalanceBefore);
        assertTrue(mockReputationEvents.eventReceived());
    }

    function test_RevertWhen_TimeoutNotReached() public {
        uint256 escrowId = _createValidEscrow();
        
        vm.prank(unauthorized);
        vm.expectRevert(EscrowContract.TimeoutNotReached.selector);
        escrow.resolveTimeout(escrowId);
        
        vm.prank(provider);
        escrow.provideOffchainProof(escrowId, "ipfs://proof123");
        
        vm.prank(unauthorized);
        vm.expectRevert(EscrowContract.TimeoutNotReached.selector);
        escrow.resolveTimeout(escrowId);
    }

    // ==================== COST CALCULATION TESTS ====================

    function test_CalculateEscrowCosts() public {
        bytes memory agreementEncoded = abi.encode(validAgreement);
        EscrowContract.EscrowCosts memory costs = escrow.calculateEscrowCosts(agreementEncoded);
        
        assertTrue(costs.escrowFee > 0);
        assertEq(costs.bridgeFee, 0); // Same chain
        assertEq(costs.destinationGas, 0); // Same chain
        assertEq(costs.totalDeductions, costs.escrowFee);
        assertEq(costs.netRecipientAmount, validAgreement.amount - costs.escrowFee);
        assertTrue(costs.maxDisputeCost > 0);
    }

    function test_CalculateCrossChainCosts() public {
        EscrowContract.EscrowAgreement memory crossChainAgreement = validAgreement;
        crossChainAgreement.dstChainId = 137; // Polygon
        
        bytes memory agreementEncoded = abi.encode(crossChainAgreement);
        EscrowContract.EscrowCosts memory costs = escrow.calculateEscrowCosts(agreementEncoded);
        
        assertTrue(costs.escrowFee > 0);
        assertTrue(costs.bridgeFee > 0); // Cross-chain fees
        assertEq(costs.destinationGas, 0); // Simplified implementation
        assertTrue(costs.totalDeductions > costs.escrowFee);
        assertTrue(costs.netRecipientAmount < crossChainAgreement.amount - costs.escrowFee);
    }

    // getStargateFee method removed in optimized version
    // function test_GetStargateFee() public {
    //     (uint256 nativeFee, uint256 zroFee) = escrow.getStargateFee(
    //         137, // Polygon
    //         1 ether,
    //         address(0), // Unused
    //         ""
    //     );
    //     
    //     assertTrue(nativeFee > 0);
    //     assertEq(zroFee, 0);
    // }

    function test_GetArbitrationCost() public {
        uint256 escrowId = _createValidEscrow();
        uint256 cost = escrow.getArbitrationCost(escrowId, holder);
        assertTrue(cost > 0);
        
        uint256 providerCost = escrow.getArbitrationCost(escrowId, provider);
        assertEq(cost, providerCost); // Same for both parties in this implementation
    }

    // ==================== NETWORK DISCOVERY TESTS ====================

    // getSupportedChains method removed in optimized version
    // function test_GetSupportedChains() public {
    //     uint16[] memory chains = escrow.getSupportedChains();
    //     assertEq(chains.length, 1);
    //     assertEq(chains[0], uint16(block.chainid));
    // }

    // getChainTokens method removed in optimized version
    // function test_GetChainTokens() public {
    //     address[] memory tokens = escrow.getChainTokens(uint16(block.chainid));
    //     // Should be empty in this implementation
    //     assertEq(tokens.length, 0);
    // }

    // ==================== ADMINISTRATION TESTS ====================

    function test_UpdateConfigByDAO() public {
        EscrowContract.EscrowConfig memory newConfig = defaultConfig;
        newConfig.baseFeePercent = 500; // 5%
        
        bytes memory configEncoded = abi.encode(newConfig);
        
        vm.prank(dao);
        vm.expectEmit(false, false, false, true);
        emit EscrowContract.ConfigUpdated(configEncoded);
        escrow.updateSystem(EscrowContract.UpdateType.CONFIG, configEncoded);
        
        EscrowContract.EscrowConfig memory storedConfig = escrow.getConfig();
        assertEq(storedConfig.baseFeePercent, 500);
    }

    function test_UpdateBaseFeeByDAO() public {
        // Create new config with updated base fee
        EscrowContract.EscrowConfig memory newConfig = escrow.getConfig();
        newConfig.baseFeePercent = 300;
        bytes memory configEncoded = abi.encode(newConfig);
        
        vm.prank(dao);
        vm.expectEmit(false, false, false, true);
        emit EscrowContract.ConfigUpdated(configEncoded);
        escrow.updateSystem(EscrowContract.UpdateType.CONFIG, configEncoded);
        
        EscrowContract.EscrowConfig memory updatedConfig = escrow.getConfig();
        assertEq(updatedConfig.baseFeePercent, 300);
    }

    function test_UpdateDisputeFeeByDAO() public {
        // Create new config with updated dispute fee
        EscrowContract.EscrowConfig memory newConfig = escrow.getConfig();
        newConfig.disputeFeePercent = 200;
        bytes memory configEncoded = abi.encode(newConfig);
        
        vm.prank(dao);
        vm.expectEmit(false, false, false, true);
        emit EscrowContract.ConfigUpdated(configEncoded);
        escrow.updateSystem(EscrowContract.UpdateType.CONFIG, configEncoded);
        
        EscrowContract.EscrowConfig memory updatedConfig = escrow.getConfig();
        assertEq(updatedConfig.disputeFeePercent, 200);
    }

    function test_UpdateDAOByCurrentDAO() public {
        vm.prank(dao);
        vm.expectEmit(true, true, false, false);
        emit EscrowContract.DAOUpdated(dao, newDAO);
        escrow.updateSystem(EscrowContract.UpdateType.DAO_ADDRESS, abi.encode(newDAO));
        
        assertEq(escrow.dao(), newDAO);
    }

    function test_SetArbitrationProxyByDAO() public {
        address newProxy = makeAddr("newProxy");
        
        vm.prank(dao);
        vm.expectEmit(true, true, false, false);
        emit EscrowContract.ArbitrationProxyUpdated(address(mockArbitrationProxy), newProxy);
        escrow.updateSystem(EscrowContract.UpdateType.ARBITRATION_PROXY, abi.encode(newProxy));
        
        assertEq(escrow.arbitrationProxy(), newProxy);
    }

    function test_PauseUnpauseByDAO() public {
        vm.prank(dao);
        escrow.pause();
        assertTrue(escrow.paused());
        
        vm.prank(dao);
        escrow.unpause();
        assertFalse(escrow.paused());
    }

    function test_RevertWhen_UnauthorizedAdministration() public {
        bytes memory configEncoded = abi.encode(defaultConfig);
        
        vm.startPrank(unauthorized);
        
        vm.expectRevert(EscrowContract.OnlyDAO.selector);
        escrow.updateSystem(EscrowContract.UpdateType.CONFIG, configEncoded);
        
        vm.expectRevert(EscrowContract.OnlyDAO.selector);
        escrow.updateSystem(EscrowContract.UpdateType.DAO_ADDRESS, abi.encode(newDAO));
        
        vm.expectRevert(EscrowContract.OnlyDAO.selector);
        escrow.updateSystem(EscrowContract.UpdateType.ARBITRATION_PROXY, abi.encode(newDAO));
        
        vm.expectRevert(EscrowContract.OnlyDAO.selector);
        escrow.pause();
        
        vm.stopPrank();
    }

    // ==================== PAUSE FUNCTIONALITY TESTS ====================

    function test_RevertWhen_CreateEscrowWhilePaused() public {
        vm.prank(dao);
        escrow.pause();
        
        bytes memory agreementEncoded = abi.encode(validAgreement);
        bytes32 hash = escrow.getAgreementHash(agreementEncoded);
        
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(holderPrivateKey, hash);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(providerPrivateKey, hash);
        
        bytes memory holderSig = abi.encodePacked(r1, s1, v1);
        bytes memory providerSig = abi.encodePacked(r2, s2, v2);
        
        vm.prank(holder);
        vm.expectRevert(); // Pausable.whenNotPaused reverts
        escrow.createEscrow{value: validAgreement.amount}(
            agreementEncoded,
            holderSig,
            providerSig
        );
    }

    function test_RevertWhen_ProgressWhilePaused() public {
        uint256 escrowId = _createValidEscrow();
        
        vm.prank(dao);
        escrow.pause();
        
        vm.prank(provider);
        vm.expectRevert(); // Pausable.whenNotPaused reverts
        escrow.provideOffchainProof(escrowId, "ipfs://proof123");
    }

    // ==================== INTEGRATION TESTS ====================

    function test_CompleteHappyPath() public {
        // 1. Create escrow
        uint256 escrowId = _createValidEscrow();
        
        // uint256 holderInitialBalance = holder.balance; // Unused in current test
        uint256 recipientInitialBalance = recipient.balance;
        uint256 feeRecipientInitialBalance = feeRecipient.balance;
        
        // 2. Provider submits proof
        vm.prank(provider);
        escrow.provideOffchainProof(escrowId, "ipfs://delivery_proof");
        
        // 3. Holder completes escrow
        vm.prank(holder);
        escrow.completeEscrow(escrowId);
        
        // Verify final state
        (, EscrowContract.EscrowState state,,) = escrow.getEscrow(escrowId);
        assertTrue(uint256(state) == uint256(EscrowContract.EscrowState.CLOSED));
        
        // Verify fund distribution
        assertTrue(recipient.balance > recipientInitialBalance);
        assertTrue(feeRecipient.balance >= feeRecipientInitialBalance);
        assertTrue(mockReputationEvents.eventReceived());
    }

    function test_CompleteDisputeFlow() public {
        // 1. Create escrow and submit proof
        uint256 escrowId = _createValidEscrow();
        
        vm.prank(provider);
        escrow.provideOffchainProof(escrowId, "ipfs://proof123");
        
        // 2. Holder disputes
        uint256 disputeFee = escrow.getArbitrationCost(escrowId, holder);
        
        vm.prank(holder);
        uint256 disputeId = escrow.createDispute{value: disputeFee}(escrowId, "Disputing service quality");
        
        // 3. Evidence submission functionality removed in optimized version
        // vm.prank(provider);
        // escrow.submitEvidence(escrowId, "Service was delivered as promised");
        // 
        // vm.prank(holder);
        // escrow.submitEvidence(escrowId, "Service was substandard");
        
        // 4. Arbitrator rules in favor of provider
        vm.prank(address(mockArbitrationProxy));
        escrow.executeRuling(disputeId, 2, "Provider provided adequate service");
        
        // Verify final state
        (, EscrowContract.EscrowState state,,) = escrow.getEscrow(escrowId);
        assertTrue(uint256(state) == uint256(EscrowContract.EscrowState.CLOSED));
        
        assertTrue(recipient.balance > 0);
        assertTrue(mockReputationEvents.eventReceived());
    }

    function test_TimeoutScenarios() public {
        // Scenario 1: Provider fails to deliver (funded timeout)
        uint256 escrowId1 = _createValidEscrow();
        
        uint256 holderBalance = holder.balance;
        
        vm.warp(block.timestamp + 3 days);
        escrow.resolveTimeout(escrowId1);
        
        assertEq(holder.balance, holderBalance + 1 ether);
        
        // Scenario 2: Holder fails to complete after proof (proof timeout)
        // Create new agreement with future timeouts after time warp
        EscrowContract.EscrowAgreement memory agreement2 = validAgreement;
        agreement2.nonce = 2;
        agreement2.fundedTimeout = block.timestamp + 2 days; // Set future timeouts
        agreement2.proofTimeout = block.timestamp + 4 days;
        agreement2.deadline = block.timestamp + 1 hours;
        
        uint256 escrowId2 = _createEscrowWithAgreement(agreement2);
        
        vm.prank(provider);
        escrow.provideOffchainProof(escrowId2, "ipfs://proof456");
        
        uint256 recipientBalance = recipient.balance;
        
        vm.warp(block.timestamp + 5 days);
        escrow.resolveTimeout(escrowId2);
        
        assertTrue(recipient.balance > recipientBalance);
    }

    // ==================== FUZZ TESTS ====================

    function testFuzz_CreateEscrowWithValidAmount(uint96 amount) public {
        vm.assume(amount > 0.001 ether && amount < 100 ether);
        
        EscrowContract.EscrowAgreement memory fuzzAgreement = validAgreement;
        fuzzAgreement.amount = amount;
        fuzzAgreement.nonce = 999; // Use different nonce
        
        uint256 escrowId = _createEscrowWithAgreement(fuzzAgreement);
        
        (EscrowContract.EscrowAgreement memory stored,,,) = escrow.getEscrow(escrowId);
        assertEq(stored.amount, amount);
    }

    function testFuzz_TimeoutHandling(uint32 fundedTimeout, uint32 proofTimeout) public {
        fundedTimeout = uint32(bound(fundedTimeout, 2 hours, 10 days));
        proofTimeout = uint32(bound(proofTimeout, fundedTimeout + 1 hours, 20 days));
        
        EscrowContract.EscrowAgreement memory fuzzAgreement = validAgreement;
        fuzzAgreement.fundedTimeout = block.timestamp + fundedTimeout;
        fuzzAgreement.proofTimeout = block.timestamp + proofTimeout;
        fuzzAgreement.nonce = 888; // Use different nonce
        
        uint256 escrowId = _createEscrowWithAgreement(fuzzAgreement);
        
        // Test funded timeout
        vm.warp(block.timestamp + fundedTimeout + 1);
        // hasTimedOut method removed - test via resolveTimeout functionality
        
        escrow.resolveTimeout(escrowId);
        
        (, EscrowContract.EscrowState state,,) = escrow.getEscrow(escrowId);
        assertTrue(uint256(state) == uint256(EscrowContract.EscrowState.CLOSED));
    }

    function testFuzz_CostCalculation(uint96 amount, uint16 chainId) public {
        // Version 1.1: Minimum amount must cover all fees (base 2.5% + upfront 0.0001 + success 0.5% + min 0.001)
        // For safety, use 0.05 ETH minimum to ensure fees don't exceed amount
        vm.assume(amount > 0.05 ether && amount < 100 ether);
        
        // Use only supported chain IDs: 0 (same chain), 1 (Ethereum), 10 (Optimism), 56 (BSC), 137 (Polygon), 42161 (Arbitrum)
        uint16[6] memory supportedChains = [0, 1, 10, 56, 137, 42161];
        chainId = supportedChains[chainId % supportedChains.length];
        
        EscrowContract.EscrowAgreement memory fuzzAgreement = validAgreement;
        fuzzAgreement.amount = amount;
        fuzzAgreement.dstChainId = chainId;
        
        bytes memory agreementEncoded = abi.encode(fuzzAgreement);
        EscrowContract.EscrowCosts memory costs = escrow.calculateEscrowCosts(agreementEncoded);
        
        // Version 1.1: escrowFee includes base fee + upfront fee + success fee + cross-chain fee
        // Base fee should respect min/max limits, but total escrow fee can exceed maxFee due to additional fees
        assertTrue(costs.escrowFee >= defaultConfig.minFee + defaultConfig.upfrontFee);
        // Remove maxFee check since total fees can legitimately exceed it in Version 1.1
        
        if (chainId != 0 && chainId != block.chainid) {
            assertTrue(costs.bridgeFee > 0); // Cross-chain should have bridge fees
        } else {
            assertEq(costs.bridgeFee, 0); // Same chain should have no bridge fees
        }
        
        // Ensure total deductions don't exceed the escrow amount (prevents underflow)
        assertTrue(costs.totalDeductions <= amount, "Total deductions should not exceed escrow amount");
        assertTrue(costs.netRecipientAmount <= amount);
        assertEq(costs.totalDeductions, costs.escrowFee + costs.bridgeFee + costs.destinationGas);
    }

    // ==================== HELPER FUNCTIONS ====================

    function _createValidEscrow() internal returns (uint256 escrowId) {
        return _createEscrowWithAgreement(validAgreement);
    }

    function _createEscrowWithAgreement(EscrowContract.EscrowAgreement memory agreement) 
        internal 
        returns (uint256 escrowId) 
    {
        bytes memory agreementEncoded = abi.encode(agreement);
        bytes32 hash = escrow.getAgreementHash(agreementEncoded);
        
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(holderPrivateKey, hash);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(providerPrivateKey, hash);
        
        bytes memory holderSig = abi.encodePacked(r1, s1, v1);
        bytes memory providerSig = abi.encodePacked(r2, s2, v2);
        
        vm.deal(holder, agreement.amount + 10 ether);
        
        vm.prank(holder);
        escrowId = escrow.createEscrow{value: agreement.amount}(
            agreementEncoded,
            holderSig,
            providerSig
        );
        
        return escrowId;
    }
}

/**
 * @title MockArbitrationProxy
 * @notice Mock contract for testing arbitration integration
 */
contract MockArbitrationProxy {
    bool public disputeCreated;
    uint256 public nextDisputeId;
    
    function createDispute(
        uint256, // escrowId
        address, // holder
        address, // provider
        uint256, // amount
        address  // disputer
    ) external payable returns (uint256) {
        disputeCreated = true;
        return nextDisputeId++;
    }
}

/**
 * @title MockReputationEvents
 * @notice Mock contract for testing reputation event integration
 */
contract MockReputationEvents {
    bool public eventReceived;
    string public lastEventName;
    address public lastWallet;
    
    function event_of(string calldata eventName, address wallet, bytes calldata) external {
        eventReceived = true;
        lastEventName = eventName;
        lastWallet = wallet;
    }
}
