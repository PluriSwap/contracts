# ArbitrationProxy Contract Specification (Codeless)

## Overview
The ArbitrationProxy is a bridge between the `Escrow` contract and an operational support team. It allows authorized human agents to resolve disputes after off-chain review and executes final rulings on-chain via callbacks into the relevant `Escrow` instance. It prioritizes operational simplicity, transparent auditability, and safety. Pricing for arbitration is reputation-aware to discourage frivolous disputes.

## Behavioral Requirements

- Dispute intake
  - Only authorized escrow contracts can open disputes.
  - The dispute records escrow context (ids, buyer, seller, amount) and the disputer address.
  - The proxy assigns a unique dispute id and tracks status until resolution.

- Evidence collection
  - Evidence will be collected off-chain. Only the resolution with a description will be sent as a result

- Resolution
  - Only active support agents/arbitrators may resolve an active dispute.
  - Valid rulings: 0 (tie/refuse), 1 (buyer wins), 2 (seller wins).
  - Upon resolution: mark dispute resolved, store ruling and human-readable resolution text, then callback the originating `Escrow` to execute the ruling atomically.

- Access control
  - DAO manages support agents and authorized escrow contracts.
  - Only authorized escrow contracts can create disputes.
  - Only active support agents/arbitrators can resolve disputes.

- Pausing
  - DAO can pause/unpause the proxy. When paused, new disputes are blocked; resolution of existing disputes remain enabled.

- Querying
  - Basic getters expose individual disputes and agent metadata.
  - On-chain iteration must be bounded; any “listing” APIs should be offset/limit based and expected to be complemented by off-chain indexing.

## Data Model (Conceptual)
- Dispute: id, escrowId, escrowContract, buyer, seller, amount, disputer, createdAt, resolvedAt, status, ruling, resolution.
- SupportAgent: address, name, isActive, addedAt, disputesResolved.
- Configuration (ArbitrationConfig): paused flag.

## Security and Invariants
- Do not rely on tx.origin; the `Escrow` passes the disputer explicitly.
- Apply checks-effects-interactions and reentrancy guards and external callbacks.
- Enforce strict authorization gates (DAO, authorized escrows, active agents).

## Administration (DAO-controlled)
- Add/remove/update support agents.
- Add/remove authorized escrow contracts.
- Update arbitration configuration (including fee recipient if configurable).
- Pause/unpause operations.
- Update DAO address reference.

## Events (Intent)
- DisputeCreated: dispute opened with escrow context and disputer.
- DisputeResolved: final ruling stored and emitted with resolver address.
- Agent and config management events for audit trail.
- Pause/Unpause and DAOUpdated events.

## External Interface (Exposed Methods Only)
```solidity
function createDispute(
    uint256 escrowId,
    address buyer,
    address seller,
    uint256 amount,
    address disputer
) external payable returns (uint256 disputeId);

function resolveDispute(
    uint256 disputeId,
    uint256 ruling,
    string calldata resolution
) external;

function addSupportAgent(address agent, string calldata name) external;
function removeSupportAgent(address agent) external;
function updateSupportAgent(address agent, string calldata name) external;

function updateConfig(bytes calldata newConfigEncoded) external;

function addAuthorizedContract(address escrowContract) external;
function removeAuthorizedContract(address escrowContract) external;

function pause() external;
function unpause() external;

function updateDAO(address newDAO) external;

function getDispute(uint256 disputeId) external view returns (bytes memory disputeEncoded);
function getDisputeEvidence(uint256 disputeId) external view returns (bytes[] memory evidenceListEncoded);
function getActiveDisputes(uint256 offset, uint256 limit) external view returns (bytes[] memory activeDisputesEncoded);
function getSupportAgent(address agent) external view returns (bytes memory agentInfoEncoded);
```

## Deployment & Configuration
- Constructor receives: DAO address, Reputation Oracle address, initial config, optional initial support agents.
- Initial config makes contract starts unpaused.

## Future Enhancements
- Appeals process, automated triage and SLAs, specialization per dispute type, optional migration to third-party arbitration behind the same interface.

## Testing Scope (Intent)
- Initialization, access control, dispute lifecycle (create/evidence/resolve/callbacks), pause behavior, DAO management, gas bounds, and reentrancy protections.

Version: 1.0 · Status: Draft


