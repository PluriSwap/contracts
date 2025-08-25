// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title ReputationOracle
 * @dev Provides read-only reputation data for wallets and controlled write access for DAO-approved trusted parties.
 * Data informs fee schedules and risk checks in Escrow and ArbitrationProxy contracts.
 */
contract ReputationOracle {
    /// @dev Structure to hold wallet reputation data
    struct WalletScore {
        uint256 started;           // Number of started transactions
        uint256 completed;         // Number of completed transactions  
        uint256 cancelled;         // Number of cancelled transactions
        uint256 disputed;          // Number of disputed transactions
        uint256 disputesWon;       // Number of disputes won
        uint256 disputesLost;      // Number of disputes lost
        uint256 volumeStarted;     // Total volume of started transactions
        uint256 volumeCompleted;   // Total volume of completed transactions
        uint256 score;             // Composite reputation score (0-1000)
        uint256 lastUpdated;       // Timestamp of last update
        bool isActive;             // Whether the wallet is active
    }

    /// @dev DAO address with governance privileges
    address public dao;
    
    /// @dev Contract pause state
    bool public paused;
    
    /// @dev Mapping of trusted parties authorized to write reputation data
    mapping(address => bool) public trustedParties;
    
    /// @dev Mapping of wallet addresses to their reputation scores
    mapping(address => WalletScore) private walletScores;

    /// @notice Emitted when a wallet's reputation score is loaded/updated
    event ScoreLoaded(address indexed wallet, uint256 score, uint256 timestamp);
    
    /// @notice Emitted when multiple scores are batch loaded
    event BatchScoreLoaded(uint256 walletCount, uint256 timestamp);
    
    /// @notice Emitted when a trusted party is added
    event TrustedPartyAdded(address indexed party);
    
    /// @notice Emitted when a trusted party is removed  
    event TrustedPartyRemoved(address indexed party);
    
    /// @notice Emitted when the contract is paused
    event Paused(address indexed by);
    
    /// @notice Emitted when the contract is unpaused
    event Unpaused(address indexed by);
    
    /// @notice Emitted when the DAO address is updated
    event DAOUpdated(address indexed previousDAO, address indexed newDAO);

    /// @dev Custom errors
    error Unauthorized();
    error ContractPaused();
    error InvalidWalletAddress();
    error InvalidDAOAddress();
    error InvalidScore();
    error InvalidCounterRelationship();
    error InvalidVolumeRelationship();
    error InvalidDisputeRelationship();
    error ArrayLengthMismatch();
    error PartyAlreadyTrusted();
    error PartyNotTrusted();

    /// @dev Modifier to check if caller is DAO
    modifier onlyDAO() {
        if (msg.sender != dao) revert Unauthorized();
        _;
    }

    /// @dev Modifier to check if caller is DAO or trusted party
    modifier onlyAuthorized() {
        if (msg.sender != dao && !trustedParties[msg.sender]) revert Unauthorized();
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

    /// @notice Returns the complete encoded wallet score data
    /// @param wallet The wallet address to query
    /// @return walletScoreEncoded ABI-encoded WalletScore struct
    function score_of(address wallet) external view returns (bytes memory walletScoreEncoded) {
        WalletScore memory score = walletScores[wallet];
        return abi.encode(
            score.started,
            score.completed,
            score.cancelled,
            score.disputed,
            score.disputesWon,
            score.disputesLost,
            score.volumeStarted,
            score.volumeCompleted,
            score.score,
            score.lastUpdated,
            score.isActive
        );
    }

    /// @notice Load reputation data for a single wallet
    /// @param wallet The wallet address to update
    /// @param data Array containing reputation data [started, completed, cancelled, disputed, disputesWon, disputesLost, volumeStarted, volumeCompleted, score, lastUpdated, isActive]
    function load(address wallet, uint256[11] calldata data) external onlyAuthorized whenNotPaused {
        _validateWalletAndData(wallet, data);
        
        walletScores[wallet] = WalletScore({
            started: data[0],
            completed: data[1],
            cancelled: data[2],
            disputed: data[3],
            disputesWon: data[4],
            disputesLost: data[5],
            volumeStarted: data[6],
            volumeCompleted: data[7],
            score: data[8],
            lastUpdated: data[9],
            isActive: data[10] > 0
        });

        emit ScoreLoaded(wallet, data[8], block.timestamp);
    }

    /// @notice Batch load reputation data for multiple wallets
    /// @param wallets Array of wallet addresses to update
    /// @param data Array of reputation data arrays, one per wallet
    function batchLoad(address[] calldata wallets, uint256[11][] calldata data) external onlyAuthorized whenNotPaused {
        if (wallets.length != data.length) revert ArrayLengthMismatch();
        if (wallets.length == 0) return;

        for (uint256 i = 0; i < wallets.length; i++) {
            address wallet = wallets[i];
            uint256[11] calldata walletData = data[i];
            
            _validateWalletAndData(wallet, walletData);
            
            walletScores[wallet] = WalletScore({
                started: walletData[0],
                completed: walletData[1],
                cancelled: walletData[2],
                disputed: walletData[3],
                disputesWon: walletData[4],
                disputesLost: walletData[5],
                volumeStarted: walletData[6],
                volumeCompleted: walletData[7],
                score: walletData[8],
                lastUpdated: walletData[9],
                isActive: walletData[10] > 0
            });
        }

        emit BatchScoreLoaded(wallets.length, block.timestamp);
    }

    /// @notice Add a trusted party authorized to write reputation data
    /// @param party Address to add as trusted party
    function addTrustedParty(address party) external onlyDAO {
        if (party == address(0)) revert InvalidWalletAddress();
        if (trustedParties[party]) revert PartyAlreadyTrusted();
        
        trustedParties[party] = true;
        emit TrustedPartyAdded(party);
    }

    /// @notice Remove a trusted party's authorization
    /// @param party Address to remove from trusted parties
    function removeTrustedParty(address party) external onlyDAO {
        if (!trustedParties[party]) revert PartyNotTrusted();
        
        trustedParties[party] = false;
        emit TrustedPartyRemoved(party);
    }

    /// @notice Pause all state-changing operations
    function pause() external onlyDAO {
        paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Unpause all state-changing operations
    function unpause() external onlyDAO {
        paused = false;
        emit Unpaused(msg.sender);
    }

    /// @notice Update the DAO address
    /// @param newDAO The new DAO address
    function updateDAO(address newDAO) external onlyDAO {
        if (newDAO == address(0)) revert InvalidDAOAddress();
        
        address previousDAO = dao;
        dao = newDAO;
        emit DAOUpdated(previousDAO, newDAO);
    }

    /// @dev Validates wallet address and reputation data
    /// @param wallet The wallet address to validate
    /// @param data The reputation data to validate
    function _validateWalletAndData(address wallet, uint256[11] calldata data) private pure {
        // Validate wallet address
        if (wallet == address(0)) revert InvalidWalletAddress();

        uint256 started = data[0];
        uint256 completed = data[1];
        uint256 cancelled = data[2];
        uint256 disputed = data[3];
        uint256 disputesWon = data[4];
        uint256 disputesLost = data[5];
        uint256 volumeStarted = data[6];
        uint256 volumeCompleted = data[7];
        uint256 score = data[8];
        // data[9] is lastUpdated timestamp - no validation needed
        // data[10] is isActive boolean (0/1) - no validation needed

        // Validate score bounds
        if (score > 1000) revert InvalidScore();

        // Validate counter relationships
        if (completed > started) revert InvalidCounterRelationship();
        if (disputed > started) revert InvalidCounterRelationship();
        if (cancelled > started) revert InvalidCounterRelationship();

        // Validate volume relationships
        if (volumeCompleted > volumeStarted) revert InvalidVolumeRelationship();

        // Validate dispute relationships
        if (disputesWon + disputesLost > disputed) revert InvalidDisputeRelationship();
    }

    /// @notice Get basic wallet score information (convenience function)
    /// @param wallet The wallet address to query
    /// @return score The reputation score (0-1000)
    /// @return isActive Whether the wallet is active
    /// @return lastUpdated Timestamp of last update
    function getWalletInfo(address wallet) external view returns (uint256 score, bool isActive, uint256 lastUpdated) {
        WalletScore storage walletScore = walletScores[wallet];
        return (walletScore.score, walletScore.isActive, walletScore.lastUpdated);
    }

    /// @notice Check if an address is a trusted party
    /// @param party Address to check
    /// @return Whether the address is a trusted party
    function isTrustedParty(address party) external view returns (bool) {
        return trustedParties[party];
    }
}
