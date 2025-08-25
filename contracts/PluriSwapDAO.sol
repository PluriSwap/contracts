// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title PluriSwapDAO
 * @notice 5-signer multisig governance contract managing system parameters, authorization, and emergency controls
 * @dev Implements 3-of-5 for standard operations, 4-of-5 for signer management
 */
contract PluriSwapDAO is ReentrancyGuard {
    // Constants
    uint256 public constant MAX_SIGNERS = 5;
    uint256 public constant STANDARD_THRESHOLD = 3;
    uint256 public constant SIGNER_THRESHOLD = 4;
    uint256 public constant TIMELOCK_DELAY = 2 days;
    uint256 public constant MIN_EMERGENCY_THRESHOLD = 2;
    
    // Configurable thresholds
    uint256 public emergencyThreshold = 2;

    // Transaction types
    enum TransactionType {
        TREASURY,
        ORACLE_ADD_TRUSTED_PARTY,
        ORACLE_REMOVE_TRUSTED_PARTY,
        ORACLE_PAUSE,
        ORACLE_UNPAUSE,
        ORACLE_UPDATE_DAO,
        ESCROW_UPDATE_CONFIG,
        ESCROW_UPDATE_BASE_FEE,
        ESCROW_SET_ARBITRATION_PROXY,
        ESCROW_PAUSE,
        ESCROW_UNPAUSE,
        ESCROW_UPDATE_DAO,
        ARBITRATION_ADD_SUPPORT_AGENT,
        ARBITRATION_REMOVE_SUPPORT_AGENT,
        ARBITRATION_UPDATE_CONFIG,
        ARBITRATION_ADD_AUTHORIZED_ESCROW,
        ARBITRATION_REMOVE_AUTHORIZED_ESCROW,
        ARBITRATION_PAUSE,
        ARBITRATION_UNPAUSE,
        ARBITRATION_UPDATE_DAO,
        REPUTATION_EVENTS_PAUSE,
        REPUTATION_EVENTS_UNPAUSE,
        REPUTATION_EVENTS_TRANSFER_OWNERSHIP,
        REPUTATION_EVENTS_UPDATE_DAO,
        EMERGENCY_PAUSE,
        EMERGENCY_UNPAUSE,
        PAUSE_ALL,
        UNPAUSE_ALL,
        UPDATE_DAO,
        ADD_DAO,
        REMOVE_DAO,
        ADD_SIGNER,
        REMOVE_SIGNER,
        UPDATE_DAILY_LIMIT,
        UPDATE_EMERGENCY_THRESHOLD,
        UNPAUSE_CONTRACT
    }

    // Transaction status
    enum TransactionStatus {
        PROPOSED,
        EXECUTED,
        CANCELLED
    }

    // Transaction structure  
    struct Transaction {
        TransactionType txType;
        address proposer;
        bytes data;
        string description;
        uint256 proposedAt;
        uint256 executedAt;
        uint256 executeAfter; // Timelock timestamp
        TransactionStatus status;
        uint256 approvalCount;
        bool isEmergency;
        mapping(address => bool) approvals;
    }

    // Daily limit structure
    struct DailyLimit {
        uint256 limit;
        uint256 spent;
        uint256 resetTime;
    }

    // State variables
    mapping(address => bool) public signers;
    address[] public activeSigners;
    mapping(uint256 => Transaction) public transactions;
    mapping(address => uint256) public nonces;
    mapping(address => DailyLimit) public dailyLimits;
    uint256 public transactionCounter;
    bool public paused;

    // Events
    event TransactionProposed(uint256 indexed transactionId, TransactionType indexed txType, address indexed proposer, bytes data, string description);
    event TransactionApproved(uint256 indexed transactionId, address indexed signer);
    event TransactionExecuted(uint256 indexed transactionId, bool success);
    event TransactionCancelled(uint256 indexed transactionId);
    event SignerAdded(address indexed signer, string name);
    event SignerRemoved(address indexed signer);
    event EmergencyAction(string reason);
    event DailyLimitUpdated(address indexed token, uint256 newLimit);
    event EmergencyThresholdUpdated(uint256 newThreshold);
    event ContractPaused();
    event ContractUnpaused();

    // Custom errors
    error InvalidSigner();
    error TransactionNotFound();
    error TransactionAlreadyApproved();
    error TransactionAlreadyExecuted();
    error TransactionAlreadyCancelled();
    error InsufficientApprovals();
    error OnlyProposerCanCancel();
    error InvalidTransactionType();
    error DuplicateSigner();
    error SignerNotFound();
    error SignerAlreadyExists();
    error DailyLimitExceeded();
    error InvalidAddress();
    error ContractIsPaused();
    error TimelockNotMet();
    error InvalidThreshold();
    error ExternalCallFailed();

    modifier onlySigner() {
        if (!signers[msg.sender]) revert InvalidSigner();
        _;
    }
    
    modifier whenNotPaused() {
        if (paused) revert ContractIsPaused();
        _;
    }

    modifier validTransaction(uint256 transactionId) {
        if (transactionId >= transactionCounter) revert TransactionNotFound();
        if (transactions[transactionId].status != TransactionStatus.PROPOSED) revert TransactionAlreadyExecuted();
        _;
    }
    
    modifier timelockMet(uint256 transactionId) {
        Transaction storage txn = transactions[transactionId];
        if (!txn.isEmergency && block.timestamp < txn.executeAfter) revert TimelockNotMet();
        _;
    }

    constructor(address[] memory initialSigners) {
        if (initialSigners.length != MAX_SIGNERS) revert InvalidSigner();
        
        for (uint256 i = 0; i < initialSigners.length; i++) {
            if (initialSigners[i] == address(0)) revert InvalidAddress();
            for (uint256 j = i + 1; j < initialSigners.length; j++) {
                if (initialSigners[i] == initialSigners[j]) revert DuplicateSigner();
            }
            signers[initialSigners[i]] = true;
            activeSigners.push(initialSigners[i]);
        }

        // Set default daily limits (10 ETH for ETH)
        dailyLimits[address(0)] = DailyLimit({
            limit: 10 ether,
            spent: 0,
            resetTime: block.timestamp + 1 days
        });
    }

    // ==================== GENERAL MANAGEMENT ====================

    function proposePauseAll(string calldata reason) external onlySigner whenNotPaused returns (uint256 transactionId) {
        bytes memory data = abi.encode(reason);
        return _proposeTransaction(TransactionType.PAUSE_ALL, data, reason, false);
    }

    function proposeUnpauseAll(string calldata reason) external onlySigner returns (uint256 transactionId) {
        bytes memory data = abi.encode(reason);
        return _proposeTransaction(TransactionType.UNPAUSE_ALL, data, reason, false);
    }

    function proposeUpdateDAO(address newDAO, string calldata justification) external onlySigner returns (uint256 transactionId) {
        if (newDAO == address(0)) revert InvalidAddress();
        bytes memory data = abi.encode(newDAO, justification);
        return _proposeTransaction(TransactionType.UPDATE_DAO, data, justification, false);
    }

    // ==================== TREASURY ====================

    function proposeTreasuryTransfer(address recipient, uint256 amount, address token, string calldata description) 
        external onlySigner whenNotPaused returns (uint256 transactionId) {
        if (recipient == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAddress(); // Reuse error for simplicity
        if (bytes(description).length == 0) revert InvalidAddress();
        
        bytes memory data = abi.encode(recipient, amount, token);
        return _proposeTransaction(TransactionType.TREASURY, data, description, false);
    }

    // ==================== ORACLE MANAGEMENT ====================

    function proposeAddOracleTrustedParty(address party, string calldata description) 
        external onlySigner returns (uint256 transactionId) {
        if (party == address(0)) revert InvalidAddress();
        bytes memory data = abi.encode(party, description);
        return _proposeTransaction(TransactionType.ORACLE_ADD_TRUSTED_PARTY, data, description, false);
    }

    function proposeRemoveOracleTrustedParty(address party, string calldata description) 
        external onlySigner returns (uint256 transactionId) {
        if (party == address(0)) revert InvalidAddress();
        bytes memory data = abi.encode(party, description);
        return _proposeTransaction(TransactionType.ORACLE_REMOVE_TRUSTED_PARTY, data, description, false);
    }

    function proposePauseOracle(string calldata reason) external onlySigner returns (uint256 transactionId) {
        bytes memory data = abi.encode(reason);
        return _proposeTransaction(TransactionType.ORACLE_PAUSE, data, reason, false);
    }

    function proposeUnpauseOracle(string calldata reason) external onlySigner returns (uint256 transactionId) {
        bytes memory data = abi.encode(reason);
        return _proposeTransaction(TransactionType.ORACLE_UNPAUSE, data, reason, false);
    }

    function proposeUpdateOracleDAO(address newDAO, string calldata description) 
        external onlySigner returns (uint256 transactionId) {
        if (newDAO == address(0)) revert InvalidAddress();
        bytes memory data = abi.encode(newDAO, description);
        return _proposeTransaction(TransactionType.ORACLE_UPDATE_DAO, data, description, false);
    }

    // ==================== ESCROW MANAGEMENT ====================

    function proposeUpdateEscrowConfig(address escrowContract, bytes calldata configEncoded, string calldata description) 
        external onlySigner returns (uint256 transactionId) {
        if (escrowContract == address(0)) revert InvalidAddress();
        bytes memory data = abi.encode(escrowContract, configEncoded, description);
        return _proposeTransaction(TransactionType.ESCROW_UPDATE_CONFIG, data, description, false);
    }

    function proposeUpdateEscrowBaseFee(address escrowContract, uint256 newBaseFee, string calldata description) 
        external onlySigner returns (uint256 transactionId) {
        if (escrowContract == address(0)) revert InvalidAddress();
        bytes memory data = abi.encode(escrowContract, newBaseFee, description);
        return _proposeTransaction(TransactionType.ESCROW_UPDATE_BASE_FEE, data, description, false);
    }

    function proposeSetEscrowArbitrationProxy(address escrowContract, address arbitrationProxy, string calldata description) 
        external onlySigner returns (uint256 transactionId) {
        if (escrowContract == address(0) || arbitrationProxy == address(0)) revert InvalidAddress();
        bytes memory data = abi.encode(escrowContract, arbitrationProxy, description);
        return _proposeTransaction(TransactionType.ESCROW_SET_ARBITRATION_PROXY, data, description, false);
    }

    function proposePauseEscrow(address escrowContract, string calldata reason) 
        external onlySigner returns (uint256 transactionId) {
        if (escrowContract == address(0)) revert InvalidAddress();
        bytes memory data = abi.encode(escrowContract, reason);
        return _proposeTransaction(TransactionType.ESCROW_PAUSE, data, reason, false);
    }

    function proposeUnpauseEscrow(address escrowContract, string calldata reason) 
        external onlySigner returns (uint256 transactionId) {
        if (escrowContract == address(0)) revert InvalidAddress();
        bytes memory data = abi.encode(escrowContract, reason);
        return _proposeTransaction(TransactionType.ESCROW_UNPAUSE, data, reason, false);
    }

    function proposeUpdateEscrowDAO(address escrowContract, address newDAO, string calldata description) 
        external onlySigner returns (uint256 transactionId) {
        if (escrowContract == address(0) || newDAO == address(0)) revert InvalidAddress();
        bytes memory data = abi.encode(escrowContract, newDAO, description);
        return _proposeTransaction(TransactionType.ESCROW_UPDATE_DAO, data, description, false);
    }

    // ==================== ARBITRATION PROXY MANAGEMENT ====================

    function proposeAddSupportAgent(address arbitrationProxy, address agent, string calldata name, string calldata description) 
        external onlySigner returns (uint256 transactionId) {
        if (arbitrationProxy == address(0) || agent == address(0)) revert InvalidAddress();
        bytes memory data = abi.encode(arbitrationProxy, agent, name, description);
        return _proposeTransaction(TransactionType.ARBITRATION_ADD_SUPPORT_AGENT, data, description, false);
    }

    function proposeRemoveSupportAgent(address arbitrationProxy, address agent, string calldata description) 
        external onlySigner returns (uint256 transactionId) {
        if (arbitrationProxy == address(0) || agent == address(0)) revert InvalidAddress();
        bytes memory data = abi.encode(arbitrationProxy, agent, description);
        return _proposeTransaction(TransactionType.ARBITRATION_REMOVE_SUPPORT_AGENT, data, description, false);
    }

    function proposeUpdateArbitrationConfig(address arbitrationProxy, bytes calldata configEncoded, string calldata description) 
        external onlySigner returns (uint256 transactionId) {
        if (arbitrationProxy == address(0)) revert InvalidAddress();
        bytes memory data = abi.encode(arbitrationProxy, configEncoded, description);
        return _proposeTransaction(TransactionType.ARBITRATION_UPDATE_CONFIG, data, description, false);
    }

    function proposeAddAuthorizedEscrowContract(address arbitrationProxy, address escrowContract, string calldata description) 
        external onlySigner returns (uint256 transactionId) {
        if (arbitrationProxy == address(0) || escrowContract == address(0)) revert InvalidAddress();
        bytes memory data = abi.encode(arbitrationProxy, escrowContract, description);
        return _proposeTransaction(TransactionType.ARBITRATION_ADD_AUTHORIZED_ESCROW, data, description, false);
    }

    function proposeRemoveAuthorizedEscrowContract(address arbitrationProxy, address escrowContract, string calldata description) 
        external onlySigner returns (uint256 transactionId) {
        if (arbitrationProxy == address(0) || escrowContract == address(0)) revert InvalidAddress();
        bytes memory data = abi.encode(arbitrationProxy, escrowContract, description);
        return _proposeTransaction(TransactionType.ARBITRATION_REMOVE_AUTHORIZED_ESCROW, data, description, false);
    }

    function proposePauseArbitrationProxy(address arbitrationProxy, string calldata reason) 
        external onlySigner returns (uint256 transactionId) {
        if (arbitrationProxy == address(0)) revert InvalidAddress();
        bytes memory data = abi.encode(arbitrationProxy, reason);
        return _proposeTransaction(TransactionType.ARBITRATION_PAUSE, data, reason, false);
    }

    function proposeUnpauseArbitrationProxy(address arbitrationProxy, string calldata reason) 
        external onlySigner returns (uint256 transactionId) {
        if (arbitrationProxy == address(0)) revert InvalidAddress();
        bytes memory data = abi.encode(arbitrationProxy, reason);
        return _proposeTransaction(TransactionType.ARBITRATION_UNPAUSE, data, reason, false);
    }

    function proposeUpdateArbitrationDAO(address arbitrationProxy, address newDAO, string calldata description) 
        external onlySigner returns (uint256 transactionId) {
        if (arbitrationProxy == address(0) || newDAO == address(0)) revert InvalidAddress();
        bytes memory data = abi.encode(arbitrationProxy, newDAO, description);
        return _proposeTransaction(TransactionType.ARBITRATION_UPDATE_DAO, data, description, false);
    }

    // ==================== REPUTATION EVENTS MANAGEMENT ====================

    function proposePauseReputationEvents(address reputationEvents, string calldata reason) 
        external onlySigner returns (uint256 transactionId) {
        if (reputationEvents == address(0)) revert InvalidAddress();
        bytes memory data = abi.encode(reputationEvents, reason);
        return _proposeTransaction(TransactionType.REPUTATION_EVENTS_PAUSE, data, reason, false);
    }

    function proposeUnpauseReputationEvents(address reputationEvents, string calldata reason) 
        external onlySigner returns (uint256 transactionId) {
        if (reputationEvents == address(0)) revert InvalidAddress();
        bytes memory data = abi.encode(reputationEvents, reason);
        return _proposeTransaction(TransactionType.REPUTATION_EVENTS_UNPAUSE, data, reason, false);
    }

    function proposeTransferEventsOwnership(address reputationEvents, address newOwner, string calldata description) 
        external onlySigner returns (uint256 transactionId) {
        if (reputationEvents == address(0) || newOwner == address(0)) revert InvalidAddress();
        bytes memory data = abi.encode(reputationEvents, newOwner, description);
        return _proposeTransaction(TransactionType.REPUTATION_EVENTS_TRANSFER_OWNERSHIP, data, description, false);
    }

    function proposeUpdateReputationEventsDAO(address reputationEvents, address newDAO, string calldata description) 
        external onlySigner returns (uint256 transactionId) {
        if (reputationEvents == address(0) || newDAO == address(0)) revert InvalidAddress();
        bytes memory data = abi.encode(reputationEvents, newDAO, description);
        return _proposeTransaction(TransactionType.REPUTATION_EVENTS_UPDATE_DAO, data, description, false);
    }

    // ==================== DAO ADDRESS MANAGEMENT ====================

    function proposeAddDAO(address daoAddress, string calldata description) external onlySigner returns (uint256 transactionId) {
        if (daoAddress == address(0)) revert InvalidAddress();
        bytes memory data = abi.encode(daoAddress, description);
        return _proposeTransaction(TransactionType.ADD_DAO, data, description, false);
    }

    function proposeRemoveDAO(address daoAddress, string calldata description) external onlySigner returns (uint256 transactionId) {
        if (daoAddress == address(0)) revert InvalidAddress();
        bytes memory data = abi.encode(daoAddress, description);
        return _proposeTransaction(TransactionType.REMOVE_DAO, data, description, false);
    }

    // ==================== EMERGENCY ACTIONS ====================

    function proposeEmergencyPause(string calldata reason) external onlySigner returns (uint256 transactionId) {
        bytes memory data = abi.encode(reason);
        return _proposeTransaction(TransactionType.EMERGENCY_PAUSE, data, reason, true);
    }

    function proposeEmergencyUnpause(string calldata reason) external onlySigner returns (uint256 transactionId) {
        bytes memory data = abi.encode(reason);
        return _proposeTransaction(TransactionType.EMERGENCY_UNPAUSE, data, reason, true);
    }

    // ==================== SIGNER MANAGEMENT ====================

    function proposeAddSigner(address newSigner, string calldata name, string calldata justification) 
        external onlySigner returns (uint256 transactionId) {
        if (newSigner == address(0)) revert InvalidAddress();
        if (signers[newSigner]) revert SignerAlreadyExists();
        if (activeSigners.length >= MAX_SIGNERS) revert InvalidSigner();
        
        bytes memory data = abi.encode(newSigner, name, justification);
        return _proposeTransaction(TransactionType.ADD_SIGNER, data, justification, false);
    }

    function proposeRemoveSigner(address signerToRemove, string calldata reason) 
        external onlySigner returns (uint256 transactionId) {
        if (!signers[signerToRemove]) revert SignerNotFound();
        if (activeSigners.length <= SIGNER_THRESHOLD) revert InvalidSigner();
        
        bytes memory data = abi.encode(signerToRemove, reason);
        return _proposeTransaction(TransactionType.REMOVE_SIGNER, data, reason, false);
    }

    // ==================== TRANSACTION MANAGEMENT ====================

    function approveTransaction(uint256 transactionId) external onlySigner validTransaction(transactionId) whenNotPaused {
        Transaction storage txn = transactions[transactionId];
        
        if (txn.approvals[msg.sender]) revert TransactionAlreadyApproved();
        
        txn.approvals[msg.sender] = true;
        txn.approvalCount++;
        
        emit TransactionApproved(transactionId, msg.sender);
    }

    function executeTransaction(uint256 transactionId) external validTransaction(transactionId) timelockMet(transactionId) whenNotPaused {
        Transaction storage txn = transactions[transactionId];
        uint256 requiredApprovals = _getRequiredApprovals(txn.txType);
        
        if (txn.approvalCount < requiredApprovals) revert InsufficientApprovals();
        
        _executeTransaction(transactionId);
    }

    // Internal helper function for transaction type validation
    function _approveTransactionWithTypeCheck(uint256 transactionId, TransactionType[] memory allowedTypes) internal {
        Transaction storage txn = transactions[transactionId];
        
        // Validate transaction type
        bool validType = false;
        for (uint256 i = 0; i < allowedTypes.length; i++) {
            if (txn.txType == allowedTypes[i]) {
                validType = true;
                break;
            }
        }
        if (!validType) revert InvalidTransactionType();
        
        if (txn.approvals[msg.sender]) revert TransactionAlreadyApproved();
        
        txn.approvals[msg.sender] = true;
        txn.approvalCount++;
        
        emit TransactionApproved(transactionId, msg.sender);
    }

    // Specific approval functions for different transaction types (for test compatibility)
    function approveTreasuryTransfer(uint256 transactionId) external onlySigner validTransaction(transactionId) whenNotPaused {
        TransactionType[] memory allowedTypes = new TransactionType[](1);
        allowedTypes[0] = TransactionType.TREASURY;
        _approveTransactionWithTypeCheck(transactionId, allowedTypes);
    }

    function approveOracleUpdate(uint256 transactionId) external onlySigner validTransaction(transactionId) whenNotPaused {
        TransactionType[] memory allowedTypes = new TransactionType[](5);
        allowedTypes[0] = TransactionType.ORACLE_ADD_TRUSTED_PARTY;
        allowedTypes[1] = TransactionType.ORACLE_REMOVE_TRUSTED_PARTY;
        allowedTypes[2] = TransactionType.ORACLE_PAUSE;
        allowedTypes[3] = TransactionType.ORACLE_UNPAUSE;
        allowedTypes[4] = TransactionType.ORACLE_UPDATE_DAO;
        _approveTransactionWithTypeCheck(transactionId, allowedTypes);
    }

    function approveEmergencyAction(uint256 transactionId) external onlySigner validTransaction(transactionId) {
        TransactionType[] memory allowedTypes = new TransactionType[](2);
        allowedTypes[0] = TransactionType.EMERGENCY_PAUSE;
        allowedTypes[1] = TransactionType.EMERGENCY_UNPAUSE;
        _approveTransactionWithTypeCheck(transactionId, allowedTypes);
    }

    // Specific execution functions for test compatibility
    function executeTreasuryTransfer(uint256 transactionId) external validTransaction(transactionId) timelockMet(transactionId) whenNotPaused {
        _validateTransactionType(transactionId, TransactionType.TREASURY);
        
        Transaction storage txn = transactions[transactionId];
        uint256 requiredApprovals = _getRequiredApprovals(txn.txType);
        
        if (txn.approvalCount < requiredApprovals) revert InsufficientApprovals();
        
        _executeTransaction(transactionId);
    }

    function cancelTransaction(uint256 transactionId) external validTransaction(transactionId) {
        Transaction storage txn = transactions[transactionId];
        
        if (txn.proposer != msg.sender) revert OnlyProposerCanCancel();
        
        txn.status = TransactionStatus.CANCELLED;
        emit TransactionCancelled(transactionId);
    }

    // ==================== INTERNAL FUNCTIONS ====================

    function _proposeTransaction(
        TransactionType txType,
        bytes memory data,
        string calldata description,
        bool isEmergency
    ) internal returns (uint256 transactionId) {
        transactionId = transactionCounter++;
        
        Transaction storage txn = transactions[transactionId];
        txn.txType = txType;
        txn.proposer = msg.sender;
        txn.data = data;
        txn.description = description;
        txn.proposedAt = block.timestamp;
        txn.executeAfter = isEmergency ? block.timestamp : block.timestamp + TIMELOCK_DELAY;
        txn.status = TransactionStatus.PROPOSED;
        txn.approvalCount = 1; // Proposer implicitly approves
        txn.isEmergency = isEmergency;
        txn.approvals[msg.sender] = true;
        
        nonces[msg.sender]++;
        
        emit TransactionProposed(transactionId, txType, msg.sender, data, description);
        emit TransactionApproved(transactionId, msg.sender);
        
        return transactionId;
    }

    function _executeTransaction(uint256 transactionId) internal nonReentrant {
        Transaction storage txn = transactions[transactionId];
        
        txn.status = TransactionStatus.EXECUTED;
        txn.executedAt = block.timestamp;
        
        bool success = true;
        
        if (txn.txType == TransactionType.TREASURY) {
            (address recipient, uint256 amount, address token) = abi.decode(txn.data, (address, uint256, address));
            success = _executeTreasuryTransfer(recipient, amount, token);
        } else if (txn.txType == TransactionType.ADD_SIGNER) {
            (address newSigner, string memory name,) = abi.decode(txn.data, (address, string, string));
            _addSigner(newSigner, name);
        } else if (txn.txType == TransactionType.REMOVE_SIGNER) {
            (address signerToRemove,) = abi.decode(txn.data, (address, string));
            _removeSigner(signerToRemove);
        } else if (txn.txType == TransactionType.UPDATE_DAILY_LIMIT) {
            (address token, uint256 newLimit,) = abi.decode(txn.data, (address, uint256, string));
            dailyLimits[token].limit = newLimit;
            emit DailyLimitUpdated(token, newLimit);
        } else if (txn.txType == TransactionType.UPDATE_EMERGENCY_THRESHOLD) {
            (uint256 newThreshold,) = abi.decode(txn.data, (uint256, string));
            emergencyThreshold = newThreshold;
            emit EmergencyThresholdUpdated(newThreshold);
        } else if (txn.txType == TransactionType.UNPAUSE_CONTRACT) {
            paused = false;
            emit ContractUnpaused();
        } else if (txn.txType == TransactionType.EMERGENCY_PAUSE || txn.txType == TransactionType.EMERGENCY_UNPAUSE) {
            (string memory reason) = abi.decode(txn.data, (string));
            emit EmergencyAction(reason);
        } else {
            // Handle external contract calls
            success = _executeExternalCall(txn.txType, txn.data);
        }
        
        emit TransactionExecuted(transactionId, success);
    }

    function _executeTreasuryTransfer(address recipient, uint256 amount, address token) internal returns (bool) {
        // Check and update daily limits atomically
        if (!_checkAndUpdateDailySpending(token, amount)) {
            return false;
        }
        
        if (token == address(0)) {
            // ETH transfer
            (bool success,) = recipient.call{value: amount}("");
            return success;
        } else {
            // ERC20 transfer
            try IERC20(token).transfer(recipient, amount) returns (bool success) {
                return success;
            } catch {
                return false;
            }
        }
    }

    function _executeExternalCall(TransactionType txType, bytes memory data) internal returns (bool) {
        // Oracle operations
        if (txType == TransactionType.ORACLE_ADD_TRUSTED_PARTY || 
            txType == TransactionType.ORACLE_REMOVE_TRUSTED_PARTY ||
            txType == TransactionType.ORACLE_PAUSE ||
            txType == TransactionType.ORACLE_UNPAUSE ||
            txType == TransactionType.ORACLE_UPDATE_DAO) {
            return _executeOracleCall(txType, data);
        }
        
        // Escrow operations  
        if (txType == TransactionType.ESCROW_UPDATE_CONFIG ||
            txType == TransactionType.ESCROW_UPDATE_BASE_FEE ||
            txType == TransactionType.ESCROW_SET_ARBITRATION_PROXY ||
            txType == TransactionType.ESCROW_PAUSE ||
            txType == TransactionType.ESCROW_UNPAUSE ||
            txType == TransactionType.ESCROW_UPDATE_DAO) {
            return _executeEscrowCall(txType, data);
        }
        
        // Arbitration operations
        if (txType == TransactionType.ARBITRATION_ADD_SUPPORT_AGENT ||
            txType == TransactionType.ARBITRATION_REMOVE_SUPPORT_AGENT ||
            txType == TransactionType.ARBITRATION_UPDATE_CONFIG ||
            txType == TransactionType.ARBITRATION_ADD_AUTHORIZED_ESCROW ||
            txType == TransactionType.ARBITRATION_REMOVE_AUTHORIZED_ESCROW ||
            txType == TransactionType.ARBITRATION_PAUSE ||
            txType == TransactionType.ARBITRATION_UNPAUSE ||
            txType == TransactionType.ARBITRATION_UPDATE_DAO) {
            return _executeArbitrationCall(txType, data);
        }
        
        // Reputation Events operations
        if (txType == TransactionType.REPUTATION_EVENTS_PAUSE ||
            txType == TransactionType.REPUTATION_EVENTS_UNPAUSE ||
            txType == TransactionType.REPUTATION_EVENTS_TRANSFER_OWNERSHIP ||
            txType == TransactionType.REPUTATION_EVENTS_UPDATE_DAO) {
            return _executeReputationEventsCall(txType, data);
        }
        
        return false;
    }
    
    function _executeOracleCall(TransactionType /* txType */, bytes memory /* data */) internal pure returns (bool) {
        // Placeholder for Oracle contract calls
        // In production, this would make actual external calls to Oracle contract
        return true; 
    }
    
    function _executeEscrowCall(TransactionType /* txType */, bytes memory /* data */) internal pure returns (bool) {
        // Placeholder for Escrow contract calls  
        // In production, this would make actual external calls to Escrow contracts
        return true;
    }
    
    function _executeArbitrationCall(TransactionType /* txType */, bytes memory /* data */) internal pure returns (bool) {
        // Placeholder for ArbitrationProxy contract calls
        // In production, this would make actual external calls to ArbitrationProxy contract
        return true;
    }
    
    function _executeReputationEventsCall(TransactionType /* txType */, bytes memory /* data */) internal pure returns (bool) {
        // Placeholder for ReputationEvents contract calls
        // In production, this would make actual external calls to ReputationEvents contract
        return true;
    }

    function _addSigner(address newSigner, string memory name) internal {
        signers[newSigner] = true;
        activeSigners.push(newSigner);
        emit SignerAdded(newSigner, name);
    }

    function _removeSigner(address signerToRemove) internal {
        signers[signerToRemove] = false;
        
        // Remove from activeSigners array
        uint256 length = activeSigners.length;
        for (uint256 i = 0; i < length; i++) {
            if (activeSigners[i] == signerToRemove) {
                activeSigners[i] = activeSigners[length - 1];
                activeSigners.pop();
                break;
            }
        }
        
        emit SignerRemoved(signerToRemove);
    }

    function _getRequiredApprovals(TransactionType txType) internal view returns (uint256) {
        if (txType == TransactionType.ADD_SIGNER || txType == TransactionType.REMOVE_SIGNER) {
            return SIGNER_THRESHOLD;
        }
        if (txType == TransactionType.EMERGENCY_PAUSE || txType == TransactionType.EMERGENCY_UNPAUSE) {
            return emergencyThreshold;
        }
        return STANDARD_THRESHOLD;
    }

    function _validateTransactionType(uint256 transactionId, TransactionType expectedType) internal view {
        if (transactionId >= transactionCounter) revert TransactionNotFound();
        if (transactions[transactionId].txType != expectedType) revert InvalidTransactionType();
    }

    function _checkAndUpdateDailySpending(address token, uint256 amount) internal returns (bool) {
        DailyLimit storage limit = dailyLimits[token];
        
        // Reset if past reset time (atomic operation)
        if (block.timestamp >= limit.resetTime) {
            if (amount > limit.limit) {
                return false;
            }
            limit.spent = amount;
            limit.resetTime = block.timestamp + 1 days;
            return true;
        }
        
        // Check if adding amount would exceed limit
        if (limit.spent + amount > limit.limit) {
            return false;
        }
        
        // Update spending
        limit.spent += amount;
        return true;
    }

    // ==================== ADMIN FUNCTIONS ====================
    
    function proposeUpdateDailyLimit(address token, uint256 newLimit, string calldata description) external onlySigner returns (uint256 transactionId) {
        bytes memory data = abi.encode(token, newLimit, description);
        return _proposeTransaction(TransactionType.UPDATE_DAILY_LIMIT, data, description, false);
    }
    
    function proposeUpdateEmergencyThreshold(uint256 newThreshold, string calldata description) external onlySigner returns (uint256 transactionId) {
        if (newThreshold < MIN_EMERGENCY_THRESHOLD || newThreshold > activeSigners.length) revert InvalidThreshold();
        bytes memory data = abi.encode(newThreshold, description);
        return _proposeTransaction(TransactionType.UPDATE_EMERGENCY_THRESHOLD, data, description, false);
    }
    
    function emergencyPauseContract(string calldata reason) external onlySigner {
        // Emergency pause can be done by any signer immediately
        paused = true;
        emit ContractPaused();
        emit EmergencyAction(reason);
    }
    
    function proposeUnpauseContract(string calldata reason) external onlySigner returns (uint256 transactionId) {
        bytes memory data = abi.encode(reason);
        return _proposeTransaction(TransactionType.UNPAUSE_CONTRACT, data, reason, false);
    }

    // ==================== VIEW FUNCTIONS ====================

    function isSigner(address account) external view returns (bool) {
        return signers[account];
    }

    function getActiveSigners() external view returns (address[] memory) {
        return activeSigners;
    }

    function getTransaction(uint256 transactionId) external view returns (
        TransactionType txType,
        address proposer,
        bytes memory data,
        string memory description,
        uint256 proposedAt,
        uint256 executedAt,
        uint256 executeAfter,
        TransactionStatus status,
        uint256 approvalCount,
        bool isEmergency
    ) {
        if (transactionId >= transactionCounter) revert TransactionNotFound();
        Transaction storage txn = transactions[transactionId];
        return (
            txn.txType,
            txn.proposer,
            txn.data,
            txn.description,
            txn.proposedAt,
            txn.executedAt,
            txn.executeAfter,
            txn.status,
            txn.approvalCount,
            txn.isEmergency
        );
    }

    function hasApproved(uint256 transactionId, address signer) external view returns (bool) {
        if (transactionId >= transactionCounter) return false;
        return transactions[transactionId].approvals[signer];
    }

    function getCurrentTransactionId() external view returns (uint256) {
        return transactionCounter;
    }

    function getNonce(address signer) external view returns (uint256) {
        return nonces[signer];
    }

    function computeTransactionId(uint256 txType, bytes calldata data, uint256 nonce) external pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(txType, data, nonce)));
    }

    // ==================== RECEIVE FUNCTION ====================

    receive() external payable {}
}
