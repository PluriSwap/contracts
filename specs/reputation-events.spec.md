# ReputationEvents Contract Specification (Codeless)

## Overview
A minimal ingestion point for reputation-relevant events emitted by upstream contracts. It emits a single canonical event that includes the originating caller, wallet of interest, metadata blob, and timestamp. The contract does not interpret semantics on-chain; analysis happens off-chain.

## Behavioral Requirements

- Event ingestion
  - Accept an event name string, a wallet address, and opaque metadata bytes.
  - Emit a canonical `ReputationEvent` including `msg.sender`, the supplied wallet, metadata, and `block.timestamp`.

- Access control
  - Emergency pausability to halt ingestion.

- Gas and size considerations
  - Encourage bounded metadata size (policy choice); large payloads increase gas costs.
  - Prefer references (e.g., IPFS CIDs) over large inline datasets.

## External Interface (Exposed Methods Only)
```solidity
// Ingestion
function event_of(string calldata eventName, address wallet, bytes calldata metadata) external;

// Governance (DAO/Owner)
function pause() external;
function unpause() external;
function updateDAO(address newDAO) external;
```

## Events (Intent)
- ReputationEvent(eventName, wallet, caller, metadata, timestamp)
- DAO/owner management events (DAO updated, paused/unpaused)

## Security & Operations
- Everyone is allowed to emit since the sender address will be emitted too.
- Paused state rejects ingestion; reading logs remains unaffected.
- Off-chain infrastructure (subgraphs, listeners) indexes and analyzes events.

## Testing Scope (Intent)
- Calls from different addresses, pause behavior, event emission integrity, large metadata bounds.

Version: 1.0 · Status: Draft


