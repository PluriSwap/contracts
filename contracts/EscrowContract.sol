// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/**
 * @title EscrowContract
 * @notice P2P escrow for crypto against off-chain settlement with cross-chain support
 * @dev Supports dual EIP-712 signatures, Stargate integration, reputation-aware fees, and dispute resolution
 */
contract EscrowContract is ReentrancyGuard, Pausable, EIP712 {
    using ECDSA for bytes32;

    // State enumeration
    enum EscrowState {
        FUNDED,              // 0: Escrow is funded and awaiting service delivery
        OFFCHAIN_PROOF_SENT, // 1: Provider has submitted proof of service delivery
        COMPLETE,            // 2: Holder has completed, funds distributed
        CLOSED,              // 3: Escrow is closed (terminal state)
        HOLDER_DISPUTED,     // 4: Holder has disputed after proof sent
        PROVIDER_DISPUTED    // 5: Provider has disputed from funded state
    }

    // EIP-712 type hash
    bytes32 private constant ESCROW_AGREEMENT_TYPEHASH = keccak256(
        "EscrowAgreement(address holder,address provider,uint256 amount,uint256 fundedTimeout,uint256 proofTimeout,uint256 nonce,uint256 deadline,uint16 dstChainId,address dstRecipient,bytes dstAdapterParams)"
    );

    bytes32 private constant CANCELLATION_TYPEHASH = keccak256(
        "CancellationAuthorization(uint256 escrowId,uint256 nonce,uint256 deadline)"
    );

    // Escrow agreement structure
    struct EscrowAgreement {
        address holder;             // Holder's address on contract network
        address provider;           // Provider's address on contract network  
        uint256 amount;             // Escrow amount in native token
        uint256 fundedTimeout;      // Timeout for FUNDED state (provider must deliver service)
        uint256 proofTimeout;       // Timeout for OFFCHAIN_PROOF_SENT state (holder must complete)
        uint256 nonce;              // Scoped nonce for replay protection
        uint256 deadline;           // Signature validity deadline
        // Destination Configuration
        uint16 dstChainId;          // Destination chain ID (0 = same chain as contract)
        address dstRecipient;       // Final recipient address
        bytes dstAdapterParams;     // Stargate parameters (gas for destination, etc.)
    }

    // Cost breakdown structure
    struct EscrowCosts {
        uint256 escrowFee;          // Platform fee (deducted from deposit, goes to DAO)
        uint256 bridgeFee;          // Stargate bridge fee (deducted from deposit)
        uint256 destinationGas;     // Gas for destination chain (deducted from deposit)
        uint256 totalDeductions;    // Sum of deductions from deposit
        uint256 netRecipientAmount; // Amount recipient receives after fees
        uint256 maxDisputeCost;     // Max potential dispute cost (paid separately by disputer)
    }

    // Escrow configuration
    struct EscrowConfig {
        uint256 baseFeePercent;     // Base fee percentage (basis points)
        uint256 minFee;             // Minimum fee amount
        uint256 maxFee;             // Maximum fee amount
        uint256 disputeFeePercent;  // Dispute fee percentage (basis points)
        uint256 minTimeout;         // Minimum timeout period
        uint256 maxTimeout;         // Maximum timeout period
        address feeRecipient;       // Fee recipient address
    }

    // Escrow instance data
    struct Escrow {
        EscrowAgreement agreement;
        EscrowState state;
        uint256 createdAt;
        uint256 snapshotEscrowFee;  // Fee snapshotted at creation
        uint256 snapshotDisputeFee; // Dispute fee snapshotted at creation
        string offchainProof;
        uint256 disputeId;
        bool exists;
    }

    // State variables
    address public dao;
    address public reputationOracle;
    address public reputationEvents;
    address public arbitrationProxy;
    address public stargateRouter;
    EscrowConfig public config;
    
    mapping(uint256 => Escrow) public escrows;
    mapping(address => mapping(uint256 => bool)) public usedNonces; // holder/provider => nonce => used
    mapping(uint256 => uint256) public disputeToEscrow; // disputeId => escrowId + 1 (to avoid 0 collision)
    
    uint256 public escrowCounter;
    uint16 public currentChainId;
    uint16[] private supportedChainIds;
    mapping(uint16 => address[]) private chainTokens;

    // Events
    event EscrowCreated(
        uint256 indexed escrowId,
        address indexed holder,
        address indexed provider,
        uint256 amount,
        uint16 dstChainId,
        address dstRecipient
    );
    
    event OffchainProofSubmitted(uint256 indexed escrowId, string proof);
    event EscrowCompleted(uint256 indexed escrowId, uint256 netAmount, uint256 totalFees);
    event EscrowCancelled(uint256 indexed escrowId, string reason);
    event DisputeCreated(uint256 indexed escrowId, uint256 indexed disputeId, address disputer);
    event EvidenceSubmitted(uint256 indexed escrowId, address indexed submitter, string evidence);
    event RulingExecuted(uint256 indexed escrowId, uint256 indexed disputeId, uint256 ruling);
    event TimeoutResolved(uint256 indexed escrowId, address resolver, string outcome);
    
    event ConfigUpdated(bytes newConfig);
    event ArbitrationProxyUpdated(address indexed oldProxy, address indexed newProxy);
    event DAOUpdated(address indexed oldDAO, address indexed newDAO);

    // Custom errors
    error OnlyDAO();
    error OnlyHolder();
    error OnlyProvider();
    error OnlyArbitrationProxy();
    error InvalidState();
    error InvalidSignature();
    error InvalidAmount();
    error InvalidTimeout();
    error InvalidAddress();
    error InvalidNonce();
    error ExpiredDeadline();
    error EscrowNotFound();
    error InsufficientFunds();
    error TimeoutNotReached();
    error DisputeNotFound();
    error TransferFailed();
    error InvalidChainId();
    error UnsupportedDestination();
    error InvalidConfiguration();

    modifier onlyDAO() {
        if (msg.sender != dao) revert OnlyDAO();
        _;
    }

    modifier onlyArbitrationProxy() {
        if (msg.sender != arbitrationProxy) revert OnlyArbitrationProxy();
        _;
    }

    modifier escrowExists(uint256 escrowId) {
        if (!escrows[escrowId].exists) revert EscrowNotFound();
        _;
    }

    modifier inState(uint256 escrowId, EscrowState requiredState) {
        if (escrows[escrowId].state != requiredState) revert InvalidState();
        _;
    }

    constructor(
        address initialDAO,
        address initialReputationOracle,
        address initialReputationEvents,
        address initialStargateRouter,
        bytes memory initialConfigEncoded
    ) EIP712("EscrowContract", "1") {
        if (initialDAO == address(0) || initialReputationOracle == address(0) || 
            initialReputationEvents == address(0)) revert InvalidAddress();
        
        dao = initialDAO;
        reputationOracle = initialReputationOracle;
        reputationEvents = initialReputationEvents;
        stargateRouter = initialStargateRouter;
        currentChainId = uint16(block.chainid);
        
        // Decode and set initial config
        EscrowConfig memory decodedConfig = abi.decode(initialConfigEncoded, (EscrowConfig));
        _validateConfig(decodedConfig);
        config = decodedConfig;
        
        // Initialize with current chain as supported
        supportedChainIds.push(currentChainId);
    }

    // ==================== ESCROW CREATION ====================

    /**
     * @notice Create a new escrow with dual signatures
     * @param agreementEncoded ABI-encoded EscrowAgreement
     * @param holderSignature Holder's EIP-712 signature
     * @param providerSignature Provider's EIP-712 signature
     * @return escrowId The unique escrow identifier
     */
    function createEscrow(
        bytes calldata agreementEncoded,
        bytes calldata holderSignature,
        bytes calldata providerSignature
    ) external payable whenNotPaused nonReentrant returns (uint256 escrowId) {
        EscrowAgreement memory agreement = abi.decode(agreementEncoded, (EscrowAgreement));
        
        // Validate agreement
        _validateAgreement(agreement);
        
        // Check exact payment
        if (msg.value != agreement.amount) revert InvalidAmount();
        
        // Validate signatures
        bytes32 structHash = _getStructHash(agreement);
        bytes32 digest = _hashTypedDataV4(structHash);
        
        address holderSigner = digest.recover(holderSignature);
        address providerSigner = digest.recover(providerSignature);
        
        if (holderSigner != agreement.holder || providerSigner != agreement.provider) {
            revert InvalidSignature();
        }
        
        // Check nonces
        if (usedNonces[agreement.holder][agreement.nonce] || 
            usedNonces[agreement.provider][agreement.nonce]) {
            revert InvalidNonce();
        }
        
        // Check deadline
        if (block.timestamp > agreement.deadline) revert ExpiredDeadline();
        
        // Mark nonces as used
        usedNonces[agreement.holder][agreement.nonce] = true;
        usedNonces[agreement.provider][agreement.nonce] = true;
        
        // Snapshot fees at creation
        uint256 snapshotEscrowFee = _calculateEscrowFee(agreement.holder, agreement.provider, agreement.amount);
        uint256 snapshotDisputeFee = _calculateDisputeFee(agreement.holder, agreement.amount);
        
        // Create escrow
        escrowId = escrowCounter++;
        
        Escrow storage escrow = escrows[escrowId];
        escrow.agreement = agreement;
        escrow.state = EscrowState.FUNDED;
        escrow.createdAt = block.timestamp;
        escrow.snapshotEscrowFee = snapshotEscrowFee;
        escrow.snapshotDisputeFee = snapshotDisputeFee;
        escrow.exists = true;
        
        emit EscrowCreated(escrowId, agreement.holder, agreement.provider, agreement.amount, agreement.dstChainId, agreement.dstRecipient);
        
        // Emit reputation events
        _emitReputationEvent("escrow_created", agreement.holder);
        _emitReputationEvent("escrow_created", agreement.provider);
        
        return escrowId;
    }

    /**
     * @notice Get the EIP-712 hash of an agreement
     * @param agreementEncoded ABI-encoded EscrowAgreement
     * @return hash The EIP-712 hash
     */
    function getAgreementHash(bytes calldata agreementEncoded) external view returns (bytes32 hash) {
        EscrowAgreement memory agreement = abi.decode(agreementEncoded, (EscrowAgreement));
        bytes32 structHash = _getStructHash(agreement);
        return _hashTypedDataV4(structHash);
    }

    // ==================== ESCROW PROGRESSION ====================

    /**
     * @notice Submit proof of off-chain service delivery
     * @param escrowId The escrow ID
     * @param proof IPFS CID or reference to off-chain service proof
     */
    function provideOffchainProof(uint256 escrowId, string calldata proof) 
        external 
        whenNotPaused 
        escrowExists(escrowId) 
        inState(escrowId, EscrowState.FUNDED) 
    {
        Escrow storage escrow = escrows[escrowId];
        if (msg.sender != escrow.agreement.provider) revert OnlyProvider();
        
        escrow.state = EscrowState.OFFCHAIN_PROOF_SENT;
        escrow.offchainProof = proof;
        
        emit OffchainProofSubmitted(escrowId, proof);
        _emitReputationEvent("proof_submitted", escrow.agreement.provider);
    }

    /**
     * @notice Complete the escrow and distribute funds
     * @param escrowId The escrow ID
     */
    function completeEscrow(uint256 escrowId) 
        external 
        whenNotPaused 
        escrowExists(escrowId) 
        inState(escrowId, EscrowState.OFFCHAIN_PROOF_SENT) 
        nonReentrant 
    {
        Escrow storage escrow = escrows[escrowId];
        if (msg.sender != escrow.agreement.holder) revert OnlyHolder();
        
        escrow.state = EscrowState.COMPLETE;
        
        // Calculate final costs
        EscrowCosts memory costs = _calculateCostsForEscrow(escrowId);
        
        // Send platform fee to DAO/fee recipient
        if (costs.escrowFee > 0) {
            _safeTransfer(config.feeRecipient, costs.escrowFee);
        }
        
        // Handle fund delivery
        if (_isCrossChain(escrow.agreement.dstChainId)) {
            _bridgeFunds(escrow.agreement, costs);
        } else {
            _directTransfer(escrow.agreement.dstRecipient, costs.netRecipientAmount);
        }
        
        escrow.state = EscrowState.CLOSED;
        
        emit EscrowCompleted(escrowId, costs.netRecipientAmount, costs.totalDeductions);
        _emitReputationEvent("escrow_completed", escrow.agreement.holder);
        _emitReputationEvent("escrow_completed", escrow.agreement.provider);
    }

    // ==================== CANCELLATION ====================

    /**
     * @notice Mutual cancellation with counterparty signature
     * @param escrowId The escrow ID
     * @param counterpartySignature The other party's cancellation signature
     */
    function mutualCancel(uint256 escrowId, bytes calldata counterpartySignature) 
        external 
        whenNotPaused 
        escrowExists(escrowId) 
        nonReentrant 
    {
        Escrow storage escrow = escrows[escrowId];
        if (escrow.state != EscrowState.FUNDED && escrow.state != EscrowState.OFFCHAIN_PROOF_SENT) {
            revert InvalidState();
        }
        
        // Verify counterparty signature
        bytes32 structHash = keccak256(abi.encode(
            CANCELLATION_TYPEHASH,
            escrowId,
            block.timestamp, // Simple nonce using timestamp
            block.timestamp + 1 hours // 1 hour deadline for cancellation
        ));
        bytes32 digest = _hashTypedDataV4(structHash);
        
        address counterparty = msg.sender == escrow.agreement.holder ? 
            escrow.agreement.provider : escrow.agreement.holder;
        
        if (digest.recover(counterpartySignature) != counterparty) {
            revert InvalidSignature();
        }
        
        escrow.state = EscrowState.CLOSED;
        
        // Full refund to holder
        _safeTransfer(escrow.agreement.holder, escrow.agreement.amount);
        
        emit EscrowCancelled(escrowId, "mutual_cancellation");
        _emitReputationEvent("escrow_cancelled", escrow.agreement.holder);
        _emitReputationEvent("escrow_cancelled", escrow.agreement.provider);
    }

    /**
     * @notice Holder cancellation (policy-dependent)
     * @param escrowId The escrow ID
     */
    function holderCancel(uint256 escrowId) 
        external 
        whenNotPaused 
        escrowExists(escrowId) 
        inState(escrowId, EscrowState.FUNDED) 
        nonReentrant 
    {
        Escrow storage escrow = escrows[escrowId];
        if (msg.sender != escrow.agreement.holder) revert OnlyHolder();
        
        escrow.state = EscrowState.CLOSED;
        
        // Full refund to holder
        _safeTransfer(escrow.agreement.holder, escrow.agreement.amount);
        
        emit EscrowCancelled(escrowId, "holder_cancellation");
        _emitReputationEvent("escrow_cancelled", escrow.agreement.holder);
    }

    /**
     * @notice Provider cancellation
     * @param escrowId The escrow ID
     */
    function providerCancel(uint256 escrowId) 
        external 
        whenNotPaused 
        escrowExists(escrowId) 
        inState(escrowId, EscrowState.FUNDED) 
        nonReentrant 
    {
        Escrow storage escrow = escrows[escrowId];
        if (msg.sender != escrow.agreement.provider) revert OnlyProvider();
        
        escrow.state = EscrowState.CLOSED;
        
        // Full refund to holder
        _safeTransfer(escrow.agreement.holder, escrow.agreement.amount);
        
        emit EscrowCancelled(escrowId, "provider_cancellation");
        _emitReputationEvent("escrow_cancelled", escrow.agreement.provider);
    }

    // ==================== DISPUTE HANDLING ====================

    /**
     * @notice Create a dispute via arbitration proxy
     * @param escrowId The escrow ID
     * @param evidence Initial evidence
     * @return disputeId The dispute ID from arbitration proxy
     */
    function createDispute(uint256 escrowId, string calldata evidence) 
        external 
        payable 
        whenNotPaused 
        escrowExists(escrowId) 
        returns (uint256 disputeId) 
    {
        Escrow storage escrow = escrows[escrowId];
        
        // Check valid states for dispute
        if (escrow.state == EscrowState.FUNDED) {
            if (msg.sender != escrow.agreement.provider) revert OnlyProvider();
            escrow.state = EscrowState.PROVIDER_DISPUTED;
        } else if (escrow.state == EscrowState.OFFCHAIN_PROOF_SENT) {
            if (msg.sender != escrow.agreement.holder) revert OnlyHolder();
            escrow.state = EscrowState.HOLDER_DISPUTED;
        } else {
            revert InvalidState();
        }
        
        // Verify dispute fee
        uint256 requiredFee = getArbitrationCost(escrowId, msg.sender);
        if (msg.value != requiredFee) revert InsufficientFunds();
        
        // Create dispute via arbitration proxy
        disputeId = _createArbitrationDispute(escrowId, evidence, requiredFee);
        escrow.disputeId = disputeId;
        disputeToEscrow[disputeId] = escrowId + 1; // Store escrowId + 1 to avoid 0 collision
        
        emit DisputeCreated(escrowId, disputeId, msg.sender);
        _emitReputationEvent("dispute_created", msg.sender);
        
        return disputeId;
    }

    /**
     * @notice Submit additional evidence during dispute
     * @param escrowId The escrow ID
     * @param evidence Additional evidence
     */
    function submitEvidence(uint256 escrowId, string calldata evidence) 
        external 
        whenNotPaused 
        escrowExists(escrowId) 
    {
        Escrow storage escrow = escrows[escrowId];
        if (escrow.state != EscrowState.HOLDER_DISPUTED && 
            escrow.state != EscrowState.PROVIDER_DISPUTED) {
            revert InvalidState();
        }
        
        if (msg.sender != escrow.agreement.holder && 
            msg.sender != escrow.agreement.provider) {
            revert InvalidAddress();
        }
        
        emit EvidenceSubmitted(escrowId, msg.sender, evidence);
    }

    /**
     * @notice Execute arbitration ruling (called by arbitration proxy)
     * @param disputeId The dispute ID
     * @param ruling 0=refuse, 1=holder wins, 2=provider wins
     * @param resolution Arbitrator's resolution text
     */
    function executeRuling(uint256 disputeId, uint256 ruling, string calldata resolution) 
        external 
        onlyArbitrationProxy 
        nonReentrant 
    {
        uint256 escrowIdPlusOne = disputeToEscrow[disputeId];
        if (escrowIdPlusOne == 0) revert DisputeNotFound();
        uint256 escrowId = escrowIdPlusOne - 1; // Subtract 1 to get actual escrowId
        
        Escrow storage escrow = escrows[escrowId];
        if (escrow.state != EscrowState.HOLDER_DISPUTED && 
            escrow.state != EscrowState.PROVIDER_DISPUTED) {
            revert InvalidState();
        }
        
        // Determine winner and loser
        address winner;
        address loser;
        bool holderWins = (ruling == 1);
        
        if (holderWins) {
            winner = escrow.agreement.holder;
            loser = escrow.agreement.provider;
        } else if (ruling == 2) {
            winner = escrow.agreement.provider;
            loser = escrow.agreement.holder;
        }
        
        // Handle fund distribution based on ruling
        if (ruling == 0) {
            // Refuse to arbitrate - return funds to holder
            _safeTransfer(escrow.agreement.holder, escrow.agreement.amount);
            escrow.state = EscrowState.CLOSED;
        } else if (holderWins) {
            // Holder wins - refund to holder
            _safeTransfer(escrow.agreement.holder, escrow.agreement.amount);
            escrow.state = EscrowState.CLOSED;
        } else {
            // Provider wins - complete the escrow
            escrow.state = EscrowState.COMPLETE;
            
            EscrowCosts memory costs = _calculateCostsForEscrow(escrowId);
            
            // Send platform fee
            if (costs.escrowFee > 0) {
                _safeTransfer(config.feeRecipient, costs.escrowFee);
            }
            
            // Handle fund delivery
            if (_isCrossChain(escrow.agreement.dstChainId)) {
                _bridgeFunds(escrow.agreement, costs);
            } else {
                _directTransfer(escrow.agreement.dstRecipient, costs.netRecipientAmount);
            }
            
            escrow.state = EscrowState.CLOSED;
        }
        
        emit RulingExecuted(escrowId, disputeId, ruling);
        
        if (winner != address(0)) {
            _emitReputationEvent("dispute_won", winner);
            _emitReputationEvent("dispute_lost", loser);
        }
    }

    // ==================== TIMEOUT HANDLING ====================

    /**
     * @notice Check if escrow has timed out
     * @param escrowId The escrow ID
     * @return True if timed out
     */
    function hasTimedOut(uint256 escrowId) external view escrowExists(escrowId) returns (bool) {
        Escrow storage escrow = escrows[escrowId];
        
        if (escrow.state == EscrowState.FUNDED) {
            return block.timestamp > escrow.agreement.fundedTimeout;
        } else if (escrow.state == EscrowState.OFFCHAIN_PROOF_SENT) {
            return block.timestamp > escrow.agreement.proofTimeout;
        }
        
        return false;
    }

    /**
     * @notice Handle timeout from FUNDED state
     * @param escrowId The escrow ID
     */
    function handleTimeout(uint256 escrowId) 
        external 
        whenNotPaused 
        escrowExists(escrowId) 
        inState(escrowId, EscrowState.FUNDED) 
        nonReentrant 
    {
        Escrow storage escrow = escrows[escrowId];
        if (block.timestamp <= escrow.agreement.fundedTimeout) revert TimeoutNotReached();
        
        escrow.state = EscrowState.CLOSED;
        
        // Full refund to holder (provider failed to deliver)
        _safeTransfer(escrow.agreement.holder, escrow.agreement.amount);
        
        emit TimeoutResolved(escrowId, msg.sender, "funded_timeout_refund");
        _emitReputationEvent("timeout_refund", escrow.agreement.holder);
        _emitReputationEvent("timeout_failed", escrow.agreement.provider);
    }

    /**
     * @notice Resolve timeout from OFFCHAIN_PROOF_SENT state
     * @param escrowId The escrow ID
     */
    function resolveTimeout(uint256 escrowId) 
        external 
        whenNotPaused 
        escrowExists(escrowId) 
        inState(escrowId, EscrowState.OFFCHAIN_PROOF_SENT) 
        nonReentrant 
    {
        Escrow storage escrow = escrows[escrowId];
        if (block.timestamp <= escrow.agreement.proofTimeout) revert TimeoutNotReached();
        
        escrow.state = EscrowState.COMPLETE;
        
        // Provider gets paid (provider delivered, holder didn't complete)
        EscrowCosts memory costs = _calculateCostsForEscrow(escrowId);
        
        // Send platform fee
        if (costs.escrowFee > 0) {
            _safeTransfer(config.feeRecipient, costs.escrowFee);
        }
        
        // Handle fund delivery
        if (_isCrossChain(escrow.agreement.dstChainId)) {
            _bridgeFunds(escrow.agreement, costs);
        } else {
            _directTransfer(escrow.agreement.dstRecipient, costs.netRecipientAmount);
        }
        
        escrow.state = EscrowState.CLOSED;
        
        emit TimeoutResolved(escrowId, msg.sender, "proof_timeout_provider_paid");
        _emitReputationEvent("timeout_completed", escrow.agreement.provider);
        _emitReputationEvent("timeout_defaulted", escrow.agreement.holder);
    }

    // ==================== COST CALCULATION ====================

    /**
     * @notice Calculate comprehensive escrow costs
     * @param agreementEncoded ABI-encoded EscrowAgreement
     * @return costs Complete cost breakdown
     */
    function calculateEscrowCosts(bytes calldata agreementEncoded) 
        external 
        view 
        returns (EscrowCosts memory costs) 
    {
        EscrowAgreement memory agreement = abi.decode(agreementEncoded, (EscrowAgreement));
        
        costs.escrowFee = _calculateEscrowFee(agreement.holder, agreement.provider, agreement.amount);
        costs.maxDisputeCost = _calculateDisputeFee(agreement.holder, agreement.amount);
        
        if (_isCrossChain(agreement.dstChainId)) {
            (costs.bridgeFee, costs.destinationGas) = _getStargateFees(
                agreement.dstChainId, 
                agreement.amount - costs.escrowFee,
                agreement.dstAdapterParams
            );
        }
        
        costs.totalDeductions = costs.escrowFee + costs.bridgeFee + costs.destinationGas;
        costs.netRecipientAmount = agreement.amount - costs.totalDeductions;
        
        return costs;
    }

    /**
     * @notice Get Stargate bridge fees
     * @param dstChainId Destination chain ID
     * @param amount Amount to bridge
     * @param dstToken Destination token address (unused in this implementation)
     * @param adapterParams Adapter parameters
     * @return nativeFee Native token fee
     * @return zroFee ZRO token fee (typically 0)
     */
    function getStargateFee(
        uint16 dstChainId,
        uint256 amount,
        address dstToken, // unused but kept for interface compatibility
        bytes calldata adapterParams
    ) external view returns (uint256 nativeFee, uint256 zroFee) {
        return _getStargateFees(dstChainId, amount, adapterParams);
    }

    /**
     * @notice Get arbitration cost for a potential disputer
     * @param escrowId The escrow ID
     * @param disputer The disputer address
     * @return The required arbitration fee
     */
    function getArbitrationCost(uint256 escrowId, address disputer) 
        public 
        view 
        escrowExists(escrowId) 
        returns (uint256) 
    {
        return escrows[escrowId].snapshotDisputeFee;
    }

    // ==================== NETWORK DISCOVERY ====================

    /**
     * @notice Get supported chain IDs
     * @return chainIds Array of supported chain IDs
     */
    function getSupportedChains() external view returns (uint16[] memory chainIds) {
        return supportedChainIds;
    }

    /**
     * @notice Get supported tokens for a chain
     * @param chainId The chain ID
     * @return tokens Array of token addresses
     */
    function getChainTokens(uint16 chainId) external view returns (address[] memory tokens) {
        return chainTokens[chainId];
    }

    // ==================== ADMINISTRATION ====================

    /**
     * @notice Update escrow configuration
     * @param newConfigEncoded ABI-encoded EscrowConfig
     */
    function updateConfig(bytes calldata newConfigEncoded) external onlyDAO {
        EscrowConfig memory newConfig = abi.decode(newConfigEncoded, (EscrowConfig));
        _validateConfig(newConfig);
        config = newConfig;
        emit ConfigUpdated(newConfigEncoded);
    }

    /**
     * @notice Update base fee
     * @param newBaseFee New base fee percentage
     */
    function updateBaseFee(uint256 newBaseFee) external onlyDAO {
        config.baseFeePercent = newBaseFee;
    }

    /**
     * @notice Update dispute fee
     * @param newDisputeFee New dispute fee percentage
     */
    function updateDisputeFee(uint256 newDisputeFee) external onlyDAO {
        config.disputeFeePercent = newDisputeFee;
    }

    /**
     * @notice Update DAO address
     * @param newDAO New DAO address
     */
    function updateDAO(address newDAO) external onlyDAO {
        if (newDAO == address(0)) revert InvalidAddress();
        address oldDAO = dao;
        dao = newDAO;
        emit DAOUpdated(oldDAO, newDAO);
    }

    /**
     * @notice Set arbitration proxy address
     * @param newArbitrationProxy New arbitration proxy address
     */
    function setArbitrationProxy(address newArbitrationProxy) external onlyDAO {
        if (newArbitrationProxy == address(0)) revert InvalidAddress();
        address oldProxy = arbitrationProxy;
        arbitrationProxy = newArbitrationProxy;
        emit ArbitrationProxyUpdated(oldProxy, newArbitrationProxy);
    }

    /**
     * @notice Pause the contract
     */
    function pause() external onlyDAO {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyDAO {
        _unpause();
    }

    // ==================== INTERNAL FUNCTIONS ====================

    /**
     * @notice Get EIP-712 struct hash for agreement
     */
    function _getStructHash(EscrowAgreement memory agreement) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            ESCROW_AGREEMENT_TYPEHASH,
            agreement.holder,
            agreement.provider,
            agreement.amount,
            agreement.fundedTimeout,
            agreement.proofTimeout,
            agreement.nonce,
            agreement.deadline,
            agreement.dstChainId,
            agreement.dstRecipient,
            keccak256(agreement.dstAdapterParams)
        ));
    }

    /**
     * @notice Validate escrow agreement
     */
    function _validateAgreement(EscrowAgreement memory agreement) internal view {
        if (agreement.holder == address(0) || agreement.provider == address(0) || 
            agreement.dstRecipient == address(0)) revert InvalidAddress();
        if (agreement.amount == 0) revert InvalidAmount();
        if (agreement.fundedTimeout <= block.timestamp || agreement.proofTimeout <= agreement.fundedTimeout) {
            revert InvalidTimeout();
        }
        if (agreement.fundedTimeout - block.timestamp < config.minTimeout ||
            agreement.fundedTimeout - block.timestamp > config.maxTimeout) {
            revert InvalidTimeout();
        }
    }

    /**
     * @notice Validate escrow configuration
     */
    function _validateConfig(EscrowConfig memory newConfig) internal pure {
        if (newConfig.feeRecipient == address(0)) revert InvalidAddress();
        if (newConfig.baseFeePercent > 10000 || newConfig.disputeFeePercent > 10000) {
            revert InvalidConfiguration();
        }
        if (newConfig.minFee > newConfig.maxFee) revert InvalidConfiguration();
        if (newConfig.minTimeout > newConfig.maxTimeout) revert InvalidConfiguration();
    }

    /**
     * @notice Calculate escrow fee based on reputation
     */
    function _calculateEscrowFee(address holder, address provider, uint256 amount) internal view returns (uint256) {
        // Simplified fee calculation - in real implementation would use reputation oracle
        uint256 feeAmount = (amount * config.baseFeePercent) / 10000;
        
        if (feeAmount < config.minFee) feeAmount = config.minFee;
        if (feeAmount > config.maxFee) feeAmount = config.maxFee;
        
        return feeAmount;
    }

    /**
     * @notice Calculate dispute fee based on reputation
     */
    function _calculateDisputeFee(address disputer, uint256 amount) internal view returns (uint256) {
        // Simplified dispute fee calculation
        uint256 disputeFee = (amount * config.disputeFeePercent) / 10000;
        return disputeFee > 0 ? disputeFee : 0.01 ether; // Minimum dispute fee
    }

    /**
     * @notice Calculate costs for existing escrow
     */
    function _calculateCostsForEscrow(uint256 escrowId) internal view returns (EscrowCosts memory costs) {
        Escrow storage escrow = escrows[escrowId];
        
        costs.escrowFee = escrow.snapshotEscrowFee;
        costs.maxDisputeCost = escrow.snapshotDisputeFee;
        
        if (_isCrossChain(escrow.agreement.dstChainId)) {
            (costs.bridgeFee, costs.destinationGas) = _getStargateFees(
                escrow.agreement.dstChainId,
                escrow.agreement.amount - costs.escrowFee,
                escrow.agreement.dstAdapterParams
            );
        }
        
        costs.totalDeductions = costs.escrowFee + costs.bridgeFee + costs.destinationGas;
        costs.netRecipientAmount = escrow.agreement.amount - costs.totalDeductions;
        
        return costs;
    }

    /**
     * @notice Check if destination is cross-chain
     */
    function _isCrossChain(uint16 dstChainId) internal view returns (bool) {
        return dstChainId != 0 && dstChainId != currentChainId;
    }

    /**
     * @notice Get Stargate fees (simplified implementation)
     */
    function _getStargateFees(uint16 dstChainId, uint256 amount, bytes memory adapterParams) 
        internal 
        view 
        returns (uint256 nativeFee, uint256 zroFee) 
    {
        // Simplified fee calculation - real implementation would query Stargate
        nativeFee = amount / 1000; // 0.1% bridge fee
        zroFee = 0;
        return (nativeFee, zroFee);
    }

    /**
     * @notice Bridge funds via Stargate (simplified implementation)
     */
    function _bridgeFunds(EscrowAgreement memory agreement, EscrowCosts memory costs) internal {
        // Simplified bridging - real implementation would call Stargate router
        // For now, just send to a bridge contract or hold in escrow
        
        // In production, this would:
        // 1. Call Stargate router with proper parameters
        // 2. Handle cross-chain message passing
        // 3. Ensure funds reach destination chain
        
        // Placeholder: send to a bridge address or keep in contract
        address bridgeRecipient = address(this); // In production: actual bridge
        _safeTransfer(bridgeRecipient, costs.netRecipientAmount);
    }

    /**
     * @notice Direct transfer for same-chain delivery
     */
    function _directTransfer(address recipient, uint256 amount) internal {
        _safeTransfer(recipient, amount);
    }

    /**
     * @notice Safe ETH transfer
     */
    function _safeTransfer(address recipient, uint256 amount) internal {
        if (amount == 0) return;
        
        (bool success, ) = recipient.call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    /**
     * @notice Create dispute in arbitration proxy
     */
    function _createArbitrationDispute(uint256 escrowId, string calldata evidence, uint256 fee) 
        internal 
        returns (uint256 disputeId) 
    {
        // Forward call to arbitration proxy with fee
        bytes memory data = abi.encodeWithSignature(
            "createDispute(uint256,address,address,uint256,address)",
            escrowId,
            escrows[escrowId].agreement.holder,
            escrows[escrowId].agreement.provider,
            escrows[escrowId].agreement.amount,
            msg.sender
        );
        
        (bool success, bytes memory result) = arbitrationProxy.call{value: fee}(data);
        if (!success) revert TransferFailed();
        
        return abi.decode(result, (uint256));
    }

    /**
     * @notice Emit reputation event
     */
    function _emitReputationEvent(string memory eventName, address wallet) internal {
        if (reputationEvents != address(0)) {
            bytes memory data = abi.encodeWithSignature(
                "event_of(string,address,bytes)",
                eventName,
                wallet,
                ""
            );
            
            (bool success,) = reputationEvents.call(data);
            // Ignore failures for reputation events to not block escrow operations
            success;
        }
    }

    // ==================== VIEW FUNCTIONS ====================

    /**
     * @notice Get escrow details
     * @param escrowId The escrow ID
     * @return agreement The escrow agreement
     * @return state The current state
     * @return createdAt Creation timestamp
     * @return offchainProof The off-chain proof (if any)
     */
    function getEscrow(uint256 escrowId) 
        external 
        view 
        escrowExists(escrowId) 
        returns (
            EscrowAgreement memory agreement,
            EscrowState state,
            uint256 createdAt,
            string memory offchainProof
        ) 
    {
        Escrow storage escrow = escrows[escrowId];
        return (escrow.agreement, escrow.state, escrow.createdAt, escrow.offchainProof);
    }

    /**
     * @notice Get current configuration
     * @return The current EscrowConfig
     */
    function getConfig() external view returns (EscrowConfig memory) {
        return config;
    }

    /**
     * @notice Check if escrow exists
     * @param escrowId The escrow ID
     * @return True if exists
     */
    function isEscrowExists(uint256 escrowId) external view returns (bool) {
        return escrows[escrowId].exists;
    }
}
