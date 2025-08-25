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
// General Management
function proposePauseAll(string calldata reason) external returns (uint256 transactionId);
function proposeUnpauseAll(string calldata reason) external returns (uint256 transactionId);
function proposeUpdateDAO(address newDAO, string calldata justification) external returns (uint256 transactionId);

// Treasury
function proposeTreasuryTransfer(address recipient, uint256 amount, address token, string calldata description) external returns (uint256 transactionId);

// Oracle management
function proposeAddOracleTrustedParty(address party, string calldata description) external returns (uint256 transactionId);
function proposeRemoveOracleTrustedParty(address party, string calldata description) external returns (uint256 transactionId);

// Escrow management including:
// fee structure, 
// arbitration address, 
// reputation event sending
// reputation oracle 
function proposeUpdateEscrowConfig(address escrowContract, bytes calldata configEncoded, string calldata description) external returns (uint256 transactionId);


// DAO address updates in managed contracts
function proposeAddDAO(address daoAddress, string calldata description) external returns (uint256 transactionId);
function proposeRemoveDAO(address daoAddress, string calldata description) external returns (uint256 transactionId);

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

## Acceptance Criteria

### Core Governance Requirements
- [ ] Multisig functionality with exactly 5 signers at initialization
- [ ] 3-of-5 approval threshold for standard operations (treasury, config changes, pause/unpause)
- [ ] 4-of-5 approval threshold for signer management operations (add/remove signers)
- [ ] Proposer automatically counts as first approver when creating proposal
- [ ] Immutable approvals (signers cannot revoke once given)
- [ ] Prevention of double-approval by same signer
- [ ] Only proposer can cancel transactions before execution
- [ ] Immediate execution once approval threshold is reached

### Transaction Lifecycle Management
- [ ] All propose* methods return unique transaction ID
- [ ] Transaction states properly tracked (pending, approved, executed, cancelled)
- [ ] Executed transactions cannot be re-executed
- [ ] Cancelled transactions cannot be executed
- [ ] Proper state transitions enforced

### Domain-Specific Operations
- [ ] Treasury transfers with recipient, amount, token, and description tracking
- [ ] Oracle trusted party management (add/remove)
- [ ] Escrow configuration updates with encoded config data
- [ ] ArbitrationProxy management capabilities
- [ ] ReputationEvents contract administration
- [ ] Cross-contract DAO address updates (add/remove DAO references)
- [ ] System-wide pause/unpause functionality with reason tracking

### Security & Access Control
- [ ] Only registered signers can propose transactions
- [ ] Only registered signers can approve transactions
- [ ] Transaction execution accessible to any address (after approval threshold met)
- [ ] Signer management requires 4-of-5 threshold enforcement
- [ ] Prevention of removing signers below minimum count
- [ ] Reentrancy protection on critical functions

### Events & Auditability
- [ ] Transaction proposed events with all relevant details
- [ ] Transaction approved events with signer identification
- [ ] Transaction executed events with outcome tracking
- [ ] Transaction cancelled events
- [ ] Signer management events (added/removed)
- [ ] All administrative actions produce audit trails

### Integration Requirements
- [ ] Compatible with ReputationOracle contract interfaces
- [ ] Compatible with EscrowContract configuration methods
- [ ] Compatible with ArbitrationProxy management functions
- [ ] Compatible with ReputationEvents ownership transfers
- [ ] Proper handling of contract address updates across ecosystem

### Error Handling & Edge Cases
- [ ] Graceful handling of failed external contract calls
- [ ] Proper revert messages for unauthorized access attempts
- [ ] Invalid transaction ID handling
- [ ] Duplicate proposal prevention where applicable
- [ ] Gas estimation compatibility for complex operations

### Deployment & Initialization
- [ ] Constructor accepts initial 5 signer addresses
- [ ] Initial signer validation (no duplicates, no zero addresses)
- [ ] Contract references properly set at deployment
- [ ] Initial configuration parameters correctly applied
- [ ] Emergency controls functional from deployment

Version: 1.0 · Status: Draft


