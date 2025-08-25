// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title ReputationOracle
 * @notice Provides read-only reputation data with controlled write access for DAO-approved trusted parties
 * @dev Data informs fee schedules and risk checks in Escrow and ArbitrationProxy contracts
 */
contract ReputationOracle {
    // Constants for data array indices
    uint256 private constant IDX_STARTED = 0;
    uint256 private constant IDX_COMPLETED = 1;
    uint256 private constant IDX_CANCELLED = 2;
    uint256 private constant IDX_DISPUTED = 3;
    uint256 private constant IDX_DISPUTES_WON = 4;
    uint256 private constant IDX_DISPUTES_LOST = 5;
    uint256 private constant IDX_VOLUME_STARTED = 6;
    uint256 private constant IDX_VOLUME_COMPLETED = 7;
    uint256 private constant IDX_SCORE = 8;
    uint256 private constant IDX_LAST_UPDATED = 9;
    uint256 private constant IDX_IS_ACTIVE = 10;

    // Score bounds
    uint256 private constant MIN_SCORE = 0;
    uint256 private constant MAX_SCORE = 1000;

    // State variables
    address public dao;
    bool public paused;
    mapping(address => bool) public trustedParties;
    mapping(address => uint256[11]) private walletData;

    // Events
    event TrustedPartyAdded(address indexed party);
    event TrustedPartyRemoved(address indexed party);
    event WalletScoreLoaded(address indexed wallet, uint256 score, bool isActive);
    event BatchWalletScoresLoaded(uint256 count);
    event DAOUpdated(address indexed oldDAO, address indexed newDAO);
    event Paused();
    event Unpaused();

    // Custom errors
    error OnlyDAO();
    error OnlyDAOOrTrustedParty();
    error ContractIsPaused();
    error InvalidAddress();
    error TrustedPartyAlreadyExists();
    error TrustedPartyNotFound();
    error InvalidScore(uint256 score);
    error InvalidTransactionData(string reason);
    error ArrayLengthMismatch();

    modifier onlyDAO() {
        if (msg.sender != dao) revert OnlyDAO();
        _;
    }

    modifier onlyDAOOrTrustedParty() {
        if (msg.sender != dao && !trustedParties[msg.sender]) revert OnlyDAOOrTrustedParty();
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

    // ==================== READS ====================

    /**
     * @notice Get the complete wallet score data
     * @param wallet The wallet address to query
     * @return walletScoreEncoded ABI-encoded wallet score data
     * @dev Returns all 11 data points: [started, completed, cancelled, disputed, disputesWon, 
     *      disputesLost, volumeStarted, volumeCompleted, score, lastUpdated, isActive]
     */
    function score_of(address wallet) external view returns (bytes memory walletScoreEncoded) {
        return abi.encode(walletData[wallet]);
    }

    // ==================== WRITES ====================

    /**
     * @notice Load reputation data for a single wallet
     * @param wallet The wallet address to update
     * @param data Array of 11 uint256 values representing the wallet's reputation data
     * @dev Only callable by DAO or trusted parties when not paused
     */
    function load(address wallet, uint256[11] calldata data) external onlyDAOOrTrustedParty whenNotPaused {
        if (wallet == address(0)) revert InvalidAddress();
        
        _validateData(data);
        
        walletData[wallet] = data;
        
        emit WalletScoreLoaded(wallet, data[IDX_SCORE], data[IDX_IS_ACTIVE] == 1);
    }

    /**
     * @notice Batch load reputation data for multiple wallets
     * @param wallets Array of wallet addresses to update
     * @param data Array of reputation data arrays, one for each wallet
     * @dev Only callable by DAO or trusted parties when not paused
     */
    function batchLoad(
        address[] calldata wallets, 
        uint256[11][] calldata data
    ) external onlyDAOOrTrustedParty whenNotPaused {
        if (wallets.length != data.length) revert ArrayLengthMismatch();
        
        for (uint256 i = 0; i < wallets.length; i++) {
            if (wallets[i] == address(0)) revert InvalidAddress();
            _validateData(data[i]);
            walletData[wallets[i]] = data[i];
        }
        
        emit BatchWalletScoresLoaded(wallets.length);
    }

    // ==================== GOVERNANCE ====================

    /**
     * @notice Add a trusted party authorized to update reputation scores
     * @param party The address to add as a trusted party
     * @dev Only callable by DAO
     */
    function addTrustedParty(address party) external onlyDAO {
        if (party == address(0)) revert InvalidAddress();
        if (trustedParties[party]) revert TrustedPartyAlreadyExists();
        
        trustedParties[party] = true;
        emit TrustedPartyAdded(party);
    }

    /**
     * @notice Remove a trusted party's authorization to update reputation scores
     * @param party The address to remove from trusted parties
     * @dev Only callable by DAO
     */
    function removeTrustedParty(address party) external onlyDAO {
        if (!trustedParties[party]) revert TrustedPartyNotFound();
        
        trustedParties[party] = false;
        emit TrustedPartyRemoved(party);
    }

    /**
     * @notice Pause the contract to halt all write operations
     * @dev Only callable by DAO
     */
    function pause() external onlyDAO {
        paused = true;
        emit Paused();
    }

    /**
     * @notice Unpause the contract to resume write operations
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

    // ==================== INTERNAL FUNCTIONS ====================

    /**
     * @notice Validate reputation data according to business rules
     * @param data The reputation data array to validate
     */
    function _validateData(uint256[11] calldata data) internal pure {
        uint256 started = data[IDX_STARTED];
        uint256 completed = data[IDX_COMPLETED];
        uint256 cancelled = data[IDX_CANCELLED];
        uint256 disputed = data[IDX_DISPUTED];
        uint256 disputesWon = data[IDX_DISPUTES_WON];
        uint256 disputesLost = data[IDX_DISPUTES_LOST];
        uint256 volumeStarted = data[IDX_VOLUME_STARTED];
        uint256 volumeCompleted = data[IDX_VOLUME_COMPLETED];
        uint256 score = data[IDX_SCORE];
        uint256 isActive = data[IDX_IS_ACTIVE];

        // Score bounds check
        if (score > MAX_SCORE) revert InvalidScore(score);

        // Transaction count validations
        if (completed > started) revert InvalidTransactionData("Completed > Started");
        if (cancelled > started) revert InvalidTransactionData("Cancelled > Started");
        if (disputed > started) revert InvalidTransactionData("Disputed > Started");

        // Volume validations
        if (volumeCompleted > volumeStarted) revert InvalidTransactionData("VolumeCompleted > VolumeStarted");

        // Dispute validations
        if (disputesWon + disputesLost > disputed) revert InvalidTransactionData("DisputesWon + DisputesLost > Disputed");

        // isActive should be 0 or 1
        if (isActive > 1) revert InvalidTransactionData("isActive must be 0 or 1");
    }

    // ==================== VIEW FUNCTIONS ====================

    /**
     * @notice Check if an address is a trusted party
     * @param party The address to check
     * @return True if the address is a trusted party
     */
    function isTrustedParty(address party) external view returns (bool) {
        return trustedParties[party];
    }

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

    /**
     * @notice Get raw wallet data (for testing/debugging)
     * @param wallet The wallet address to query
     * @return The raw uint256[11] array of wallet data
     */
    function getWalletData(address wallet) external view returns (uint256[11] memory) {
        return walletData[wallet];
    }
}
