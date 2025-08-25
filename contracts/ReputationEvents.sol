// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title ReputationEvents
 * @dev A minimal ingestion point for reputation-relevant events emitted by upstream contracts.
 * Emits a single canonical event that includes the originating caller, wallet of interest,
 * metadata blob, and timestamp. The contract does not interpret semantics on-chain.
 */
contract ReputationEvents {
    /// @dev Address that can pause/unpause the contract and update DAO
    address public dao;
    
    /// @dev Flag to control event ingestion
    bool public paused;

    /// @dev Maximum allowed metadata size (64KB)
    uint256 public constant MAX_METADATA_SIZE = 65536;

    /// @notice Emitted when a reputation event is ingested
    /// @param eventName The name of the event
    /// @param wallet The wallet address of interest
    /// @param caller The address that called the event_of function
    /// @param metadata Opaque metadata bytes
    /// @param timestamp Block timestamp when the event was emitted
    event ReputationEvent(
        string indexed eventName,
        address indexed wallet,
        address indexed caller,
        bytes metadata,
        uint256 timestamp
    );

    /// @notice Emitted when the contract is paused
    event Paused(address indexed by);

    /// @notice Emitted when the contract is unpaused
    event Unpaused(address indexed by);

    /// @notice Emitted when the DAO address is updated
    /// @param previousDAO The previous DAO address
    /// @param newDAO The new DAO address
    event DAOUpdated(address indexed previousDAO, address indexed newDAO);

    /// @dev Error thrown when the contract is paused
    error ContractPaused();

    /// @dev Error thrown when caller is not authorized
    error Unauthorized();

    /// @dev Error thrown when metadata exceeds maximum size
    error MetadataTooLarge();

    /// @dev Error thrown when trying to set DAO to zero address
    error InvalidDAOAddress();

    /// @dev Modifier to check if caller is the DAO
    modifier onlyDAO() {
        if (msg.sender != dao) revert Unauthorized();
        _;
    }

    /// @dev Modifier to check if contract is not paused
    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    /// @param _dao Initial DAO address
    constructor(address _dao) {
        if (_dao == address(0)) revert InvalidDAOAddress();
        dao = _dao;
        paused = false;
    }

    /// @notice Ingest a reputation event
    /// @param eventName The name of the event being reported
    /// @param wallet The wallet address this event relates to
    /// @param metadata Opaque metadata bytes (consider using IPFS CID for large data)
    /// @dev Anyone can call this function; the caller address is tracked in the event
    function event_of(
        string calldata eventName,
        address wallet,
        bytes calldata metadata
    ) external whenNotPaused {
        // Gas optimization: check metadata size to prevent excessive gas costs
        if (metadata.length > MAX_METADATA_SIZE) {
            revert MetadataTooLarge();
        }

        emit ReputationEvent(
            eventName,
            wallet,
            msg.sender,
            metadata,
            block.timestamp
        );
    }

    /// @notice Pause the contract to halt event ingestion
    /// @dev Only DAO can call this function
    function pause() external onlyDAO {
        paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Unpause the contract to resume event ingestion
    /// @dev Only DAO can call this function
    function unpause() external onlyDAO {
        paused = false;
        emit Unpaused(msg.sender);
    }

    /// @notice Update the DAO address
    /// @param newDAO The new DAO address
    /// @dev Only current DAO can call this function
    function updateDAO(address newDAO) external onlyDAO {
        if (newDAO == address(0)) revert InvalidDAOAddress();
        
        address previousDAO = dao;
        dao = newDAO;
        
        emit DAOUpdated(previousDAO, newDAO);
    }
}
