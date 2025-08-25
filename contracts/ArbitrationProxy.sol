// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ArbitrationProxy
 * @notice Bridge between Escrow contracts and operational support team for dispute resolution
 * @dev Allows authorized human agents to resolve disputes with callbacks to originating escrow contracts
 */
contract ArbitrationProxy is ReentrancyGuard {
    // Dispute status enumeration
    enum DisputeStatus {
        ACTIVE,      // 0: Dispute is open and awaiting resolution
        RESOLVED     // 1: Dispute has been resolved
    }

    // Valid ruling options
    enum Ruling {
        TIE_REFUSE,  // 0: Tie/refuse to decide
        BUYER_WINS,  // 1: Buyer wins
        SELLER_WINS  // 2: Seller wins
    }

    // Dispute data structure
    struct Dispute {
        uint256 id;
        uint256 escrowId;
        address escrowContract;
        address buyer;
        address seller;
        uint256 amount;
        address disputer;
        uint256 createdAt;
        uint256 resolvedAt;
        DisputeStatus status;
        Ruling ruling;
        string resolution;
    }

    // Support agent data structure
    struct SupportAgent {
        address agentAddress;
        string name;
        bool isActive;
        uint256 addedAt;
        uint256 disputesResolved;
    }

    // Arbitration configuration
    struct ArbitrationConfig {
        bool paused;
        address feeRecipient;
        uint256 baseFee;
    }

    // State variables
    address public dao;
    address public reputationOracle;
    ArbitrationConfig public config;
    
    mapping(uint256 => Dispute) public disputes;
    mapping(address => SupportAgent) public supportAgents;
    mapping(address => bool) public authorizedContracts;
    
    uint256 public disputeCounter;
    uint256[] private activeDisputeIds;
    mapping(uint256 => uint256) private activeDisputeIndex; // Maps disputeId to index in activeDisputeIds

    // Events
    event DisputeCreated(
        uint256 indexed disputeId,
        uint256 indexed escrowId,
        address indexed escrowContract,
        address buyer,
        address seller,
        uint256 amount,
        address disputer
    );
    
    event DisputeResolved(
        uint256 indexed disputeId,
        Ruling ruling,
        address indexed resolver,
        string resolution
    );
    
    event SupportAgentAdded(address indexed agent, string name);
    event SupportAgentRemoved(address indexed agent);
    event SupportAgentUpdated(address indexed agent, string name);
    
    event AuthorizedContractAdded(address indexed escrowContract);
    event AuthorizedContractRemoved(address indexed escrowContract);
    
    event ConfigUpdated(bytes newConfig);
    event Paused();
    event Unpaused();
    event DAOUpdated(address indexed oldDAO, address indexed newDAO);

    // Custom errors
    error OnlyDAO();
    error OnlyAuthorizedContract();
    error OnlyActiveSupportAgent();
    error ContractPaused();
    error DisputeNotFound();
    error DisputeAlreadyResolved();
    error InvalidRuling();
    error InvalidAddress();
    error AgentNotFound();
    error AgentAlreadyExists();
    error ContractNotAuthorized();
    error ContractAlreadyAuthorized();
    error InvalidOffset();
    error InvalidLimit();
    error EscrowCallbackFailed();

    modifier onlyDAO() {
        if (msg.sender != dao) revert OnlyDAO();
        _;
    }

    modifier onlyAuthorizedContract() {
        if (!authorizedContracts[msg.sender]) revert OnlyAuthorizedContract();
        _;
    }

    modifier onlyActiveSupportAgent() {
        if (!supportAgents[msg.sender].isActive) revert OnlyActiveSupportAgent();
        _;
    }

    modifier whenNotPaused() {
        if (config.paused) revert ContractPaused();
        _;
    }

    constructor(
        address initialDAO,
        address initialReputationOracle,
        bytes memory initialConfig
    ) {
        if (initialDAO == address(0) || initialReputationOracle == address(0)) revert InvalidAddress();
        
        dao = initialDAO;
        reputationOracle = initialReputationOracle;
        
        // Decode initial config
        ArbitrationConfig memory decodedConfig = abi.decode(initialConfig, (ArbitrationConfig));
        config = decodedConfig;
    }

    // ==================== DISPUTE MANAGEMENT ====================

    /**
     * @notice Create a new dispute
     * @param escrowId The escrow transaction ID
     * @param buyer The buyer address
     * @param seller The seller address
     * @param amount The disputed amount
     * @param disputer The address initiating the dispute
     * @return disputeId The unique dispute identifier
     * @dev Only callable by authorized escrow contracts when not paused
     */
    function createDispute(
        uint256 escrowId,
        address buyer,
        address seller,
        uint256 amount,
        address disputer
    ) external payable onlyAuthorizedContract whenNotPaused returns (uint256 disputeId) {
        if (buyer == address(0) || seller == address(0) || disputer == address(0)) revert InvalidAddress();
        
        disputeId = disputeCounter++;
        
        Dispute storage dispute = disputes[disputeId];
        dispute.id = disputeId;
        dispute.escrowId = escrowId;
        dispute.escrowContract = msg.sender;
        dispute.buyer = buyer;
        dispute.seller = seller;
        dispute.amount = amount;
        dispute.disputer = disputer;
        dispute.createdAt = block.timestamp;
        dispute.status = DisputeStatus.ACTIVE;
        
        // Add to active disputes
        activeDisputeIndex[disputeId] = activeDisputeIds.length;
        activeDisputeIds.push(disputeId);
        
        emit DisputeCreated(disputeId, escrowId, msg.sender, buyer, seller, amount, disputer);
        
        return disputeId;
    }

    /**
     * @notice Resolve an active dispute
     * @param disputeId The dispute ID to resolve
     * @param ruling The ruling decision (0=tie/refuse, 1=buyer wins, 2=seller wins)
     * @param resolution Human-readable description of the resolution
     * @dev Only callable by active support agents
     */
    function resolveDispute(
        uint256 disputeId,
        uint256 ruling,
        string calldata resolution
    ) external onlyActiveSupportAgent nonReentrant {
        if (disputeId >= disputeCounter) revert DisputeNotFound();
        if (ruling > uint256(Ruling.SELLER_WINS)) revert InvalidRuling();
        
        Dispute storage dispute = disputes[disputeId];
        if (dispute.status != DisputeStatus.ACTIVE) revert DisputeAlreadyResolved();
        
        // Update dispute
        dispute.status = DisputeStatus.RESOLVED;
        dispute.ruling = Ruling(ruling);
        dispute.resolution = resolution;
        dispute.resolvedAt = block.timestamp;
        
        // Remove from active disputes
        _removeFromActiveDisputes(disputeId);
        
        // Update agent stats
        supportAgents[msg.sender].disputesResolved++;
        
        emit DisputeResolved(disputeId, Ruling(ruling), msg.sender, resolution);
        
        // Callback to escrow contract
        _callbackEscrow(dispute.escrowContract, dispute.escrowId, ruling);
    }

    // ==================== SUPPORT AGENT MANAGEMENT ====================

    /**
     * @notice Add a new support agent
     * @param agent The agent address
     * @param name The agent's name
     * @dev Only callable by DAO
     */
    function addSupportAgent(address agent, string calldata name) external onlyDAO {
        if (agent == address(0)) revert InvalidAddress();
        if (supportAgents[agent].agentAddress != address(0)) revert AgentAlreadyExists();
        
        supportAgents[agent] = SupportAgent({
            agentAddress: agent,
            name: name,
            isActive: true,
            addedAt: block.timestamp,
            disputesResolved: 0
        });
        
        emit SupportAgentAdded(agent, name);
    }

    /**
     * @notice Remove a support agent
     * @param agent The agent address to remove
     * @dev Only callable by DAO
     */
    function removeSupportAgent(address agent) external onlyDAO {
        if (supportAgents[agent].agentAddress == address(0)) revert AgentNotFound();
        
        supportAgents[agent].isActive = false;
        
        emit SupportAgentRemoved(agent);
    }

    /**
     * @notice Update a support agent's information
     * @param agent The agent address
     * @param name The new name
     * @dev Only callable by DAO
     */
    function updateSupportAgent(address agent, string calldata name) external onlyDAO {
        if (supportAgents[agent].agentAddress == address(0)) revert AgentNotFound();
        
        supportAgents[agent].name = name;
        
        emit SupportAgentUpdated(agent, name);
    }

    // ==================== CONFIGURATION MANAGEMENT ====================

    /**
     * @notice Update arbitration configuration
     * @param newConfigEncoded ABI-encoded ArbitrationConfig
     * @dev Only callable by DAO
     */
    function updateConfig(bytes calldata newConfigEncoded) external onlyDAO {
        ArbitrationConfig memory newConfig = abi.decode(newConfigEncoded, (ArbitrationConfig));
        config = newConfig;
        
        emit ConfigUpdated(newConfigEncoded);
    }

    // ==================== AUTHORIZED CONTRACT MANAGEMENT ====================

    /**
     * @notice Add an authorized escrow contract
     * @param escrowContract The escrow contract address
     * @dev Only callable by DAO
     */
    function addAuthorizedContract(address escrowContract) external onlyDAO {
        if (escrowContract == address(0)) revert InvalidAddress();
        if (authorizedContracts[escrowContract]) revert ContractAlreadyAuthorized();
        
        authorizedContracts[escrowContract] = true;
        
        emit AuthorizedContractAdded(escrowContract);
    }

    /**
     * @notice Remove an authorized escrow contract
     * @param escrowContract The escrow contract address
     * @dev Only callable by DAO
     */
    function removeAuthorizedContract(address escrowContract) external onlyDAO {
        if (!authorizedContracts[escrowContract]) revert ContractNotAuthorized();
        
        authorizedContracts[escrowContract] = false;
        
        emit AuthorizedContractRemoved(escrowContract);
    }

    // ==================== PAUSE MANAGEMENT ====================

    /**
     * @notice Pause the contract (blocks new disputes)
     * @dev Only callable by DAO
     */
    function pause() external onlyDAO {
        config.paused = true;
        emit Paused();
    }

    /**
     * @notice Unpause the contract
     * @dev Only callable by DAO
     */
    function unpause() external onlyDAO {
        config.paused = false;
        emit Unpaused();
    }

    // ==================== DAO MANAGEMENT ====================

    /**
     * @notice Update the DAO address
     * @param newDAO The new DAO address
     * @dev Only callable by current DAO
     */
    function updateDAO(address newDAO) external onlyDAO {
        if (newDAO == address(0)) revert InvalidAddress();
        
        address oldDAO = dao;
        dao = newDAO;
        
        emit DAOUpdated(oldDAO, newDAO);
    }

    // ==================== VIEW FUNCTIONS ====================

    /**
     * @notice Get dispute information
     * @param disputeId The dispute ID
     * @return disputeEncoded ABI-encoded dispute data
     */
    function getDispute(uint256 disputeId) external view returns (bytes memory disputeEncoded) {
        if (disputeId >= disputeCounter) revert DisputeNotFound();
        return abi.encode(disputes[disputeId]);
    }

    /**
     * @notice Get dispute evidence (placeholder for future implementation)
     * @param disputeId The dispute ID
     * @return evidenceListEncoded ABI-encoded evidence list
     */
    function getDisputeEvidence(uint256 disputeId) external view returns (bytes[] memory evidenceListEncoded) {
        if (disputeId >= disputeCounter) revert DisputeNotFound();
        // Evidence collection is off-chain for now, return empty array
        return new bytes[](0);
    }

    /**
     * @notice Get active disputes with pagination
     * @param offset The starting index
     * @param limit The maximum number of disputes to return
     * @return activeDisputesEncoded ABI-encoded array of active dispute data
     */
    function getActiveDisputes(uint256 offset, uint256 limit) external view returns (bytes[] memory activeDisputesEncoded) {
        if (limit == 0) revert InvalidLimit();
        if ((activeDisputeIds.length == 0 && offset > 0) || (activeDisputeIds.length > 0 && offset >= activeDisputeIds.length)) revert InvalidOffset();
        
        uint256 end = offset + limit;
        if (end > activeDisputeIds.length) {
            end = activeDisputeIds.length;
        }
        
        uint256 resultLength = end > offset ? end - offset : 0;
        activeDisputesEncoded = new bytes[](resultLength);
        
        for (uint256 i = 0; i < resultLength; i++) {
            uint256 disputeId = activeDisputeIds[offset + i];
            activeDisputesEncoded[i] = abi.encode(disputes[disputeId]);
        }
        
        return activeDisputesEncoded;
    }

    /**
     * @notice Get support agent information
     * @param agent The agent address
     * @return agentInfoEncoded ABI-encoded agent data
     */
    function getSupportAgent(address agent) external view returns (bytes memory agentInfoEncoded) {
        if (supportAgents[agent].agentAddress == address(0)) revert AgentNotFound();
        return abi.encode(supportAgents[agent]);
    }

    /**
     * @notice Check if contract is paused
     * @return True if paused
     */
    function isPaused() external view returns (bool) {
        return config.paused;
    }

    /**
     * @notice Check if an address is an authorized contract
     * @param contractAddr The contract address to check
     * @return True if authorized
     */
    function isAuthorizedContract(address contractAddr) external view returns (bool) {
        return authorizedContracts[contractAddr];
    }

    /**
     * @notice Check if an address is an active support agent
     * @param agent The agent address to check
     * @return True if active agent
     */
    function isActiveSupportAgent(address agent) external view returns (bool) {
        return supportAgents[agent].isActive;
    }

    /**
     * @notice Get the number of active disputes
     * @return The count of active disputes
     */
    function getActiveDisputeCount() external view returns (uint256) {
        return activeDisputeIds.length;
    }

    /**
     * @notice Get current configuration
     * @return The current ArbitrationConfig
     */
    function getConfig() external view returns (ArbitrationConfig memory) {
        return config;
    }

    // ==================== INTERNAL FUNCTIONS ====================

    /**
     * @notice Remove a dispute from the active disputes list
     * @param disputeId The dispute ID to remove
     */
    function _removeFromActiveDisputes(uint256 disputeId) internal {
        uint256 indexToRemove = activeDisputeIndex[disputeId];
        uint256 lastIndex = activeDisputeIds.length - 1;
        
        if (indexToRemove != lastIndex) {
            uint256 lastDisputeId = activeDisputeIds[lastIndex];
            activeDisputeIds[indexToRemove] = lastDisputeId;
            activeDisputeIndex[lastDisputeId] = indexToRemove;
        }
        
        activeDisputeIds.pop();
        delete activeDisputeIndex[disputeId];
    }

    /**
     * @notice Callback to escrow contract after dispute resolution
     * @param escrowContract The escrow contract address
     * @param escrowId The escrow ID
     * @param ruling The ruling decision
     */
    function _callbackEscrow(address escrowContract, uint256 escrowId, uint256 ruling) internal {
        // Prepare callback data
        bytes memory callData = abi.encodeWithSignature(
            "handleArbitrationRuling(uint256,uint256)",
            escrowId,
            ruling
        );
        
        // Make the callback
        (bool success, ) = escrowContract.call(callData);
        if (!success) revert EscrowCallbackFailed();
    }
}
