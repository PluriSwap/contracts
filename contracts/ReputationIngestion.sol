// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title ReputationIngestion
 * @notice Minimal ingestion point for reputation-relevant events from upstream contracts
 * @dev Emits canonical events with sender, wallet, metadata, and timestamp for off-chain analysis
 */
contract ReputationIngestion {
    // State variables
    address public dao;
    bool public paused;

    // Events
    event ReputationEvent(
        string indexed eventName,
        address indexed wallet, 
        address indexed caller,
        bytes metadata,
        uint256 timestamp
    );
    event DAOUpdated(address indexed oldDAO, address indexed newDAO);
    event Paused();
    event Unpaused();

    // Custom errors
    error ContractIsPaused();
    error OnlyDAO();
    error InvalidAddress();

    modifier onlyDAO() {
        if (msg.sender != dao) revert OnlyDAO();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert ContractIsPaused();
        _;
    }

    constructor(address initialDAO) {
        if (initialDAO == address(0)) revert InvalidAddress();
        dao = initialDAO;
    }

    // ==================== CORE INGESTION ====================

    /**
     * @notice Ingest a reputation-relevant event
     * @param eventName The name/type of the reputation event
     * @param wallet The wallet address that the reputation event concerns
     * @param metadata Opaque metadata bytes for off-chain interpretation
     * @dev Anyone can call this function - the caller address is included in the emitted event
     */
    function event_of(
        string calldata eventName,
        address wallet,
        bytes calldata metadata
    ) external whenNotPaused {
        emit ReputationEvent(eventName, wallet, msg.sender, metadata, block.timestamp);
    }

    // ==================== GOVERNANCE ====================

    /**
     * @notice Pause the contract to halt event ingestion
     * @dev Only callable by DAO
     */
    function pause() external onlyDAO {
        paused = true;
        emit Paused();
    }

    /**
     * @notice Unpause the contract to resume event ingestion
     * @dev Only callable by DAO
     */
    function unpause() external onlyDAO {
        paused = false;
        emit Unpaused();
    }

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
     * @notice Check if the contract is currently paused
     * @return True if paused, false otherwise
     */
    function isPaused() external view returns (bool) {
        return paused;
    }

    /**
     * @notice Get the current DAO address
     * @return The current DAO address
     */
    function getDAO() external view returns (address) {
        return dao;
    }
}
