// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./ReputationOracle.sol";

/**
 * @title ArbitrationProxy
 * @dev Bridge between Escrow contracts and human arbitration agents for dispute resolution.
 * Prioritizes operational simplicity, transparent auditability, and safety.
 * Pricing is reputation-aware to discourage frivolous disputes.
 */
contract ArbitrationProxy {
    /// @dev Structure to hold dispute information
    struct Dispute {
        uint256 escrowId;           // ID of the related escrow
        address escrowContract;     // Address of the escrow contract
        address buyer;              // Buyer address
        address seller;             // Seller address
        uint256 amount;             // Disputed amount
        address disputer;           // Who initiated the dispute
        uint256 createdAt;          // Timestamp of creation
        uint256 resolvedAt;         // Timestamp of resolution (0 if not resolved)
        DisputeStatus status;       // Current status
        uint256 ruling;             // Final ruling (0=refuse, 1=buyer wins, 2=seller wins)
        string resolution;          // Human-readable resolution text
    }

    /// @dev Structure to hold support agent information
    struct SupportAgent {
        string name;                // Agent name
        bool isActive;              // Whether agent is active
        uint256 addedAt;            // Timestamp when added
        uint256 disputesResolved;   // Number of disputes resolved
    }

    /// @dev Structure for arbitration configuration
    struct ArbitrationConfig {
        bool paused;                // Whether new disputes are paused
        uint256 baseDisputeFee;     // Base dispute fee in wei
        uint256 maxDisputeFee;      // Maximum dispute fee in wei
        uint256 minDisputeFee;      // Minimum dispute fee in wei
        address feeRecipient;       // Where dispute fees go
    }

    /// @dev Dispute status enumeration
    enum DisputeStatus {
        Active,      // Dispute is open and can be resolved
        Resolved,    // Dispute has been resolved
        Cancelled    // Dispute was cancelled
    }

    /// @dev DAO address with governance privileges
    address public dao;
    
    /// @dev ReputationOracle for reputation-aware pricing
    ReputationOracle public reputationOracle;
    
    /// @dev Arbitration configuration
    ArbitrationConfig public config;
    
    /// @dev Counter for dispute IDs
    uint256 private disputeCounter;
    
    /// @dev Mapping of dispute ID to dispute data
    mapping(uint256 => Dispute) private disputes;
    
    /// @dev Mapping of agent addresses to their info
    mapping(address => SupportAgent) public supportAgents;
    
    /// @dev Mapping of authorized escrow contracts
    mapping(address => bool) public authorizedContracts;
    
    /// @dev Array to track active disputes for iteration
    uint256[] private activeDisputeIds;
    
    /// @dev Mapping to track position in activeDisputeIds array
    mapping(uint256 => uint256) private activeDisputeIndex;

    /// @notice Emitted when a new dispute is created
    event DisputeCreated(
        uint256 indexed disputeId,
        uint256 indexed escrowId,
        address indexed disputer,
        address escrowContract,
        address buyer,
        address seller,
        uint256 amount
    );
    
    /// @notice Emitted when a dispute is resolved
    event DisputeResolved(
        uint256 indexed disputeId,
        address indexed resolver,
        uint256 ruling,
        string resolution
    );
    
    /// @notice Emitted when a support agent is added
    event SupportAgentAdded(address indexed agent, string name);
    
    /// @notice Emitted when a support agent is removed
    event SupportAgentRemoved(address indexed agent);
    
    /// @notice Emitted when a support agent is updated
    event SupportAgentUpdated(address indexed agent, string name);
    
    /// @notice Emitted when an authorized contract is added
    event AuthorizedContractAdded(address indexed escrowContract);
    
    /// @notice Emitted when an authorized contract is removed
    event AuthorizedContractRemoved(address indexed escrowContract);
    
    /// @notice Emitted when configuration is updated
    event ConfigUpdated();
    
    /// @notice Emitted when the contract is paused
    event Paused(address indexed by);
    
    /// @notice Emitted when the contract is unpaused
    event Unpaused(address indexed by);
    
    /// @notice Emitted when the DAO address is updated
    event DAOUpdated(address indexed previousDAO, address indexed newDAO);

    /// @dev Custom errors
    error Unauthorized();
    error DisputeCreationPaused();
    error DisputeNotFound();
    error DisputeAlreadyResolved();
    error InvalidRuling();
    error InvalidAgentAddress();
    error AgentNotActive();
    error AgentAlreadyExists();
    error ContractAlreadyAuthorized();
    error ContractNotAuthorized();
    error InsufficientDisputeFee();
    error InvalidDAOAddress();
    error InvalidConfigData();
    error CallbackFailed();

    /// @dev Modifier to check if caller is DAO
    modifier onlyDAO() {
        if (msg.sender != dao) revert Unauthorized();
        _;
    }

    /// @dev Modifier to check if caller is authorized escrow contract
    modifier onlyAuthorizedContract() {
        if (!authorizedContracts[msg.sender]) revert Unauthorized();
        _;
    }

    /// @dev Modifier to check if caller is active support agent
    modifier onlyActiveAgent() {
        if (!supportAgents[msg.sender].isActive) revert Unauthorized();
        _;
    }

    /// @dev Modifier to check if dispute creation is not paused
    modifier whenNotPaused() {
        if (config.paused) revert DisputeCreationPaused();
        _;
    }

    /// @dev Reentrancy guard state
    bool private locked;
    modifier noReentrancy() {
        require(!locked, "Reentrant call");
        locked = true;
        _;
        locked = false;
    }

    /// @param _dao DAO address
    /// @param _reputationOracle ReputationOracle contract address
    /// @param _configEncoded Encoded initial configuration
    constructor(
        address _dao,
        address _reputationOracle,
        bytes memory _configEncoded
    ) {
        if (_dao == address(0)) revert InvalidDAOAddress();
        if (_reputationOracle == address(0)) revert InvalidAgentAddress();
        
        dao = _dao;
        reputationOracle = ReputationOracle(_reputationOracle);
        disputeCounter = 0;
        
        // Decode and set initial configuration
        _updateConfig(_configEncoded);
    }

    /// @notice Create a new dispute (called by authorized escrow contracts)
    /// @param escrowId ID of the escrow
    /// @param buyer Buyer address
    /// @param seller Seller address
    /// @param amount Disputed amount
    /// @param disputer Address who initiated the dispute
    /// @return disputeId The ID of the created dispute
    function createDispute(
        uint256 escrowId,
        address buyer,
        address seller,
        uint256 amount,
        address disputer
    ) external payable onlyAuthorizedContract whenNotPaused noReentrancy returns (uint256 disputeId) {
        // Calculate required dispute fee based on disputer's reputation
        uint256 requiredFee = _calculateDisputeFee(disputer);
        if (msg.value < requiredFee) revert InsufficientDisputeFee();
        
        // Create new dispute
        disputeId = ++disputeCounter;
        
        disputes[disputeId] = Dispute({
            escrowId: escrowId,
            escrowContract: msg.sender,
            buyer: buyer,
            seller: seller,
            amount: amount,
            disputer: disputer,
            createdAt: block.timestamp,
            resolvedAt: 0,
            status: DisputeStatus.Active,
            ruling: 0,
            resolution: ""
        });
        
        // Add to active disputes tracking
        activeDisputeIndex[disputeId] = activeDisputeIds.length;
        activeDisputeIds.push(disputeId);
        
        // Transfer dispute fee to fee recipient
        if (requiredFee > 0 && config.feeRecipient != address(0)) {
            (bool success, ) = config.feeRecipient.call{value: requiredFee}("");
            require(success, "Fee transfer failed");
        }
        
        // Refund excess payment
        if (msg.value > requiredFee) {
            (bool success, ) = msg.sender.call{value: msg.value - requiredFee}("");
            require(success, "Refund failed");
        }
        
        emit DisputeCreated(disputeId, escrowId, disputer, msg.sender, buyer, seller, amount);
    }

    /// @notice Resolve a dispute (called by active support agents)
    /// @param disputeId ID of the dispute to resolve
    /// @param ruling The ruling (0=refuse, 1=buyer wins, 2=seller wins)
    /// @param resolution Human-readable resolution description
    function resolveDispute(
        uint256 disputeId,
        uint256 ruling,
        string calldata resolution
    ) external onlyActiveAgent noReentrancy {
        Dispute storage dispute = disputes[disputeId];
        
        if (dispute.createdAt == 0) revert DisputeNotFound();
        if (dispute.status != DisputeStatus.Active) revert DisputeAlreadyResolved();
        if (ruling > 2) revert InvalidRuling();
        
        // Update dispute
        dispute.status = DisputeStatus.Resolved;
        dispute.resolvedAt = block.timestamp;
        dispute.ruling = ruling;
        dispute.resolution = resolution;
        
        // Remove from active disputes
        _removeFromActiveDisputes(disputeId);
        
        // Update agent stats
        supportAgents[msg.sender].disputesResolved++;
        
        // Callback to escrow contract to execute ruling
        (bool success, ) = dispute.escrowContract.call(
            abi.encodeWithSignature(
                "executeRuling(uint256,uint256,string)", 
                disputeId, 
                ruling, 
                resolution
            )
        );
        
        if (!success) revert CallbackFailed();
        
        emit DisputeResolved(disputeId, msg.sender, ruling, resolution);
    }

    /// @notice Add a new support agent
    /// @param agent Address of the agent to add
    /// @param name Name of the agent
    function addSupportAgent(address agent, string calldata name) external onlyDAO {
        if (agent == address(0)) revert InvalidAgentAddress();
        if (supportAgents[agent].addedAt != 0) revert AgentAlreadyExists();
        
        supportAgents[agent] = SupportAgent({
            name: name,
            isActive: true,
            addedAt: block.timestamp,
            disputesResolved: 0
        });
        
        emit SupportAgentAdded(agent, name);
    }

    /// @notice Remove a support agent
    /// @param agent Address of the agent to remove
    function removeSupportAgent(address agent) external onlyDAO {
        if (supportAgents[agent].addedAt == 0) revert InvalidAgentAddress();
        
        supportAgents[agent].isActive = false;
        
        emit SupportAgentRemoved(agent);
    }

    /// @notice Update a support agent's information
    /// @param agent Address of the agent to update
    /// @param name New name for the agent
    function updateSupportAgent(address agent, string calldata name) external onlyDAO {
        if (supportAgents[agent].addedAt == 0) revert InvalidAgentAddress();
        
        supportAgents[agent].name = name;
        
        emit SupportAgentUpdated(agent, name);
    }

    /// @notice Update arbitration configuration
    /// @param newConfigEncoded Encoded new configuration
    function updateConfig(bytes calldata newConfigEncoded) external onlyDAO {
        _updateConfig(newConfigEncoded);
        emit ConfigUpdated();
    }

    /// @notice Add an authorized escrow contract
    /// @param escrowContract Address of the escrow contract
    function addAuthorizedContract(address escrowContract) external onlyDAO {
        if (escrowContract == address(0)) revert InvalidAgentAddress();
        if (authorizedContracts[escrowContract]) revert ContractAlreadyAuthorized();
        
        authorizedContracts[escrowContract] = true;
        
        emit AuthorizedContractAdded(escrowContract);
    }

    /// @notice Remove an authorized escrow contract
    /// @param escrowContract Address of the escrow contract
    function removeAuthorizedContract(address escrowContract) external onlyDAO {
        if (!authorizedContracts[escrowContract]) revert ContractNotAuthorized();
        
        authorizedContracts[escrowContract] = false;
        
        emit AuthorizedContractRemoved(escrowContract);
    }

    /// @notice Pause new dispute creation
    function pause() external onlyDAO {
        config.paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Unpause new dispute creation
    function unpause() external onlyDAO {
        config.paused = false;
        emit Unpaused(msg.sender);
    }

    /// @notice Update the DAO address
    /// @param newDAO New DAO address
    function updateDAO(address newDAO) external onlyDAO {
        if (newDAO == address(0)) revert InvalidDAOAddress();
        
        address previousDAO = dao;
        dao = newDAO;
        
        emit DAOUpdated(previousDAO, newDAO);
    }

    /// @notice Get dispute information
    /// @param disputeId ID of the dispute
    /// @return disputeEncoded ABI-encoded dispute data
    function getDispute(uint256 disputeId) external view returns (bytes memory disputeEncoded) {
        Dispute memory dispute = disputes[disputeId];
        if (dispute.createdAt == 0) revert DisputeNotFound();
        
        return abi.encode(
            dispute.escrowId,
            dispute.escrowContract,
            dispute.buyer,
            dispute.seller,
            dispute.amount,
            dispute.disputer,
            dispute.createdAt,
            dispute.resolvedAt,
            dispute.status,
            dispute.ruling,
            dispute.resolution
        );
    }

    /// @notice Get dispute evidence (placeholder - evidence collected off-chain)
    /// @return evidenceListEncoded Empty array (evidence handled off-chain)
    function getDisputeEvidence(uint256 /*disputeId*/) external pure returns (bytes[] memory evidenceListEncoded) {
        // Evidence is collected off-chain, return empty array
        return new bytes[](0);
    }

    /// @notice Get active disputes with pagination
    /// @param offset Starting index
    /// @param limit Maximum number of disputes to return
    /// @return activeDisputesEncoded Array of encoded active disputes
    function getActiveDisputes(uint256 offset, uint256 limit) external view returns (bytes[] memory activeDisputesEncoded) {
        uint256 totalActive = activeDisputeIds.length;
        
        if (offset >= totalActive) {
            return new bytes[](0);
        }
        
        uint256 end = offset + limit;
        if (end > totalActive) {
            end = totalActive;
        }
        
        uint256 resultCount = end - offset;
        activeDisputesEncoded = new bytes[](resultCount);
        
        for (uint256 i = 0; i < resultCount; i++) {
            uint256 disputeId = activeDisputeIds[offset + i];
            Dispute memory dispute = disputes[disputeId];
            
            activeDisputesEncoded[i] = abi.encode(
                disputeId,
                dispute.escrowId,
                dispute.escrowContract,
                dispute.buyer,
                dispute.seller,
                dispute.amount,
                dispute.disputer,
                dispute.createdAt
            );
        }
    }

    /// @notice Get support agent information
    /// @param agent Address of the agent
    /// @return agentInfoEncoded ABI-encoded agent information
    function getSupportAgent(address agent) external view returns (bytes memory agentInfoEncoded) {
        SupportAgent memory agentInfo = supportAgents[agent];
        
        return abi.encode(
            agentInfo.name,
            agentInfo.isActive,
            agentInfo.addedAt,
            agentInfo.disputesResolved
        );
    }

    /// @notice Calculate dispute fee for a given disputer
    /// @param disputer Address of the potential disputer
    /// @return fee Required dispute fee
    function calculateDisputeFee(address disputer) external view returns (uint256 fee) {
        return _calculateDisputeFee(disputer);
    }

    /// @notice Get total number of active disputes
    /// @return count Number of active disputes
    function getActiveDisputeCount() external view returns (uint256 count) {
        return activeDisputeIds.length;
    }

    /// @notice Check if an agent is active
    /// @param agent Address of the agent
    /// @return isActive Whether the agent is active
    function isActiveAgent(address agent) external view returns (bool isActive) {
        return supportAgents[agent].isActive;
    }

    /// @dev Internal function to calculate dispute fee based on reputation
    function _calculateDisputeFee(address disputer) private view returns (uint256 fee) {
        // Try to get disputer's reputation score
        try reputationOracle.score_of(disputer) returns (bytes memory scoreData) {
            if (scoreData.length > 0) {
                // Decode the reputation score (8th element in the encoded data)
                (, , , , , , , , uint256 score, ,) = abi.decode(
                    scoreData,
                    (uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, bool)
                );
                
                // Calculate fee based on reputation (higher reputation = lower fee)
                // Score ranges from 0-1000, fee ranges from max to min
                if (score > 0) {
                    // Linear interpolation: higher score = lower fee
                    fee = config.maxDisputeFee - ((score * (config.maxDisputeFee - config.minDisputeFee)) / 1000);
                } else {
                    fee = config.maxDisputeFee;
                }
            } else {
                // No reputation data, charge maximum fee
                fee = config.maxDisputeFee;
            }
        } catch {
            // Oracle call failed, use maximum fee as fallback
            fee = config.maxDisputeFee;
        }
        
        // Ensure fee is within bounds
        if (fee < config.minDisputeFee) fee = config.minDisputeFee;
        if (fee > config.maxDisputeFee) fee = config.maxDisputeFee;
    }

    /// @dev Internal function to remove dispute from active tracking
    function _removeFromActiveDisputes(uint256 disputeId) private {
        uint256 index = activeDisputeIndex[disputeId];
        uint256 lastIndex = activeDisputeIds.length - 1;
        
        if (index != lastIndex) {
            uint256 lastDisputeId = activeDisputeIds[lastIndex];
            activeDisputeIds[index] = lastDisputeId;
            activeDisputeIndex[lastDisputeId] = index;
        }
        
        activeDisputeIds.pop();
        delete activeDisputeIndex[disputeId];
    }

    /// @dev Internal function to update configuration
    function _updateConfig(bytes memory configEncoded) private {
        ArbitrationConfig memory newConfig = abi.decode(configEncoded, (ArbitrationConfig));
        
        // Validate configuration
        if (newConfig.baseDisputeFee > newConfig.maxDisputeFee) revert InvalidConfigData();
        if (newConfig.minDisputeFee > newConfig.baseDisputeFee) revert InvalidConfigData();
        
        config = newConfig;
    }

    /// @notice Receive function to accept dispute fees
    receive() external payable {}
}
