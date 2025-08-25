# PluriSwap DAO Contract Specification (Codeless)

## Overview
A 5-signer, 3-of-5 multisig governance managing system parameters, authorization, and emergency controls across the ecosystem (Oracle, Escrow, ArbitrationProxy, ReputationEvents). Certain signer-management actions require 4-of-5. Transactions follow propose → approve → execute.

## Governance Model (Intent)
- Signers: 5 active addresses; 3-of-5 for standard ops; 4-of-5 for signer changes.
- Lifecycle:
  - Proposal: created by a valid signer; proposer implicitly approves.
  - Approval: additional signers add approvals; immutable once given; double-approval prevented.
  - Execution: Immediately after the approvals have been reached.
  - Cancellation: proposer can cancel prior to execution.
- Limits:
  - No limits, transactions will be assumed to have the needed funds to be run or will just fail.

## Managed Domains (Intent)
- Treasury: ETH/ERC-20 transfers to recipients within limits.
- Reputation Oracle: trusted parties, pause/unpause, DAO reference updates.
- Escrow: fee bands/timeout configs, arbitration proxy reference, pause/unpause, DAO reference.
- ArbitrationProxy: support agents, config, authorized escrow contracts, pause/unpause, DAO reference.
- ReputationEvents: pause/unpause, ownership/DAO updates.
- Cross-contract: update DAO addresses across system components.
- DAO signers: add/remove signers (4-of-5).

## Security & Invariants
- Enforce thresholds per transaction type.
- Prevent duplicate or stale transaction executions.
- Timelocks for non-emergency actions; emergency actions limited but traceable.
- Daily spending caps; per-token accounting; auto reset after day boundary.
- All administrative effects produce audit events.

## External Interface (Exposed Methods Only)
```solidity
// Treasury
function proposeTreasuryTransfer(address recipient, uint256 amount, address token, string calldata description) external returns (uint256 transactionId);
function approveTreasuryTransfer(uint256 transactionId) external;
function executeTreasuryTransfer(uint256 transactionId) external;

// Oracle management
function proposeAddOracleTrustedParty(address party, string calldata description) external returns (uint256 transactionId);
function proposeRemoveOracleTrustedParty(address party, string calldata description) external returns (uint256 transactionId);
function proposePauseOracle(string calldata reason) external returns (uint256 transactionId);
function proposeUnpauseOracle(string calldata reason) external returns (uint256 transactionId);
function proposeUpdateOracleDAO(address newDAO, string calldata justification) external returns (uint256 transactionId);
function approveOracleUpdate(uint256 transactionId) external;
function executeOracleUpdate(uint256 transactionId) external;

// Escrow management
function proposeUpdateEscrowConfig(address escrowContract, bytes calldata configEncoded, string calldata description) external returns (uint256 transactionId);
function proposeUpdateEscrowBaseFee(address escrowContract, uint256 newBaseFee, string calldata description) external returns (uint256 transactionId);
function proposeSetEscrowArbitrationProxy(address escrowContract, address arbitrationProxy, string calldata description) external returns (uint256 transactionId);
function proposePauseEscrow(address escrowContract, string calldata reason) external returns (uint256 transactionId);
function proposeUnpauseEscrow(address escrowContract, string calldata reason) external returns (uint256 transactionId);

// ArbitrationProxy management
function proposeAddSupportAgent(address arbitrationProxy, address agent, string calldata agentName, string calldata description) external returns (uint256 transactionId);
function proposeRemoveSupportAgent(address arbitrationProxy, address agent, string calldata description) external returns (uint256 transactionId);
function proposeUpdateArbitrationConfig(address arbitrationProxy, bytes calldata configEncoded, string calldata description) external returns (uint256 transactionId);
function proposeAddAuthorizedEscrowContract(address arbitrationProxy, address escrowContract, string calldata description) external returns (uint256 transactionId);
function proposeRemoveAuthorizedEscrowContract(address arbitrationProxy, address escrowContract, string calldata description) external returns (uint256 transactionId);
function proposePauseArbitrationProxy(address arbitrationProxy, string calldata reason) external returns (uint256 transactionId);
function proposeUnpauseArbitrationProxy(address arbitrationProxy, string calldata reason) external returns (uint256 transactionId);

// ReputationEvents management
function proposePauseReputationEvents(address reputationEvents, string calldata reason) external returns (uint256 transactionId);
function proposeUnpauseReputationEvents(address reputationEvents, string calldata reason) external returns (uint256 transactionId);
function proposeTransferEventsOwnership(address reputationEvents, address newOwner, string calldata description) external returns (uint256 transactionId);

// DAO address updates in managed contracts
function proposeAddDAO(address daoAddress, string calldata description) external returns (uint256 transactionId);
function proposeRemoveDAO(address daoAddress, string calldata description) external returns (uint256 transactionId);

// Emergency actions
function proposeEmergencyPause(string calldata reason) external returns (uint256 transactionId);
function proposeEmergencyUnpause(string calldata reason) external returns (uint256 transactionId);
function approveEmergencyAction(uint256 transactionId) external;
function executeEmergencyAction(uint256 transactionId) external;

// Signer management (4-of-5)
function proposeAddSigner(address newSigner, string calldata name, string calldata justification) external returns (uint256 transactionId);
function proposeRemoveSigner(address signerToRemove, string calldata reason) external returns (uint256 transactionId);
function approveTransaction(uint256 transactionId) external;
function executeTransaction(uint256 transactionId) external;
function cancelTransaction(uint256 transactionId) external;
```

## Deployment & Parameters
- Initial signers (5), initial delays, daily limits, and contract references configured at deployment.
- Monitorable via events (transaction proposed/approved/executed/cancelled, domain-specific outcomes).

## Testing Scope (Intent)
- Thresholds, delays, expirations, daily limits; all domain operations; signer management; reentrancy/MEV resistance where relevant.

Version: 1.0 · Status: Draft


