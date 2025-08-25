# Escrow Contract Specification (Codeless)

## Overview
Provides a P2P escrow for crypto against off-chain fiat settlement, with:
- Dual EIP-712 signatures to create and fund escrows atomically.
- Reputation-aware dynamic fees via the Reputation Oracle.
- Reputation event emission (ingestion via ReputationEvents).
- Dispute resolution via an external ArbitrationProxy.
- DAO-configurable parameters and emergency pause.

## State Machine (Intent)
- States: INITIAL (pseudo), FUNDED, FIAT_TRANSFERRED, COMPLETE, CLOSED, SELLER_DISPUTED, BUYER_DISPUTED.
- Decision Points: VALID (signature validation), TIMEOUT_PASSED (timeout condition check).
- Transitions:
  - INITIAL → FUNDED: happens immediately after dual-signature validation and exact funds received.
  - FUNDED → FIAT_TRANSFERRED: buyer submits proof of fiat payment.
  - FIAT_TRANSFERRED → COMPLETE: seller releases crypto; fee deducted and funds disbursed.
  - FUNDED/FIAT_TRANSFERRED → SELLER_DISPUTED/BUYER_DISPUTED: party opens dispute; state reflects initiator.
  - FUNDED/FIAT_TRANSFERRED → TIMEOUT_PASSED condition check: routes based on timeout status and context.
  - Any active → CLOSED: terminal after completion, cancellation, or dispute ruling execution.

## Complete State Machine Paths

Based on the state machine diagram, here are all possible paths through the escrow lifecycle:

### Happy Path - Normal Completion
1. **INITIAL** → `createEscrow(buyer, seller, signature, funds, timeouts)` → *VALID check* → **FUNDED** 
2. **FUNDED** → `buyer_proof(escrow_id, proof)` → **FIAT_TRANSFERRED**
3. **FIAT_TRANSFERRED** → `seller_complete(escrow_id)` → **COMPLETE**
4. **COMPLETE** → `automatic closure` → **CLOSED** ✓

### Early Cancellation Paths
1. **INITIAL** → `createEscrow()` → *VALID check* → `invalid signature` → **CLOSED** ✓
2. **INITIAL** → `createEscrow()` → *VALID check* → `buyer_cancelled(escrow_id)` → **CLOSED** ✓
3. **INITIAL** → `createEscrow()` → *VALID check* → `mutual_cancel(escrow_id, signature)` → **CLOSED** ✓

### Timeout Resolution Paths
1. **FUNDED** → `seller_cancel(escrow_id)` → *TIMEOUT_PASSED check* → `buyer_lost(escrow_id)` → **CLOSED** ✓
2. **FIAT_TRANSFERRED** → `timeout exceeded` → *TIMEOUT_PASSED check* → `buyer_lost(escrow_id)` → **CLOSED** ✓
3. **FUNDED** → `seller_cancel(escrow_id)` → *TIMEOUT_PASSED check* → `dispute available: yes` → **BUYER_DISPUTED** → `buyer_won(escrow_id)` → **COMPLETE** → **CLOSED** ✓

### Seller Dispute Paths
1. **FIAT_TRANSFERRED** → `seller_dispute(escrow_id, fee)` → **SELLER_DISPUTED** → `seller_won(escrow_id)` → **CLOSED** ✓

### Buyer Dispute Paths  
1. **FUNDED** → `buyer_dispute(escrow_id, fee)` → **BUYER_DISPUTED** → `buyer_won(escrow_id)` → **COMPLETE** → **CLOSED** ✓

### Failed Completion Paths
1. **COMPLETE** → `seller_lost(escrow_id)` → **CLOSED** ✓

### State Transition Summary
- **Terminal States**: CLOSED, COMPLETE (which leads to CLOSED)
- **Dispute States**: SELLER_DISPUTED, BUYER_DISPUTED (both can resolve to either CLOSED or COMPLETE)
- **Active States**: FUNDED, FIAT_TRANSFERRED
- **Decision Points**: VALID (signature validation), TIMEOUT_PASSED (conditional routing based on timeout status)
- **Entry Point**: INITIAL (pseudo-state for creation initiation)

### Key Path Characteristics
- All paths eventually lead to **CLOSED** (the final terminal state)
- **COMPLETE** is a penultimate state that always transitions to **CLOSED**  
- Disputes can be initiated from **FUNDED** (buyer) or **FIAT_TRANSFERRED** (seller)
- **TIMEOUT_PASSED** is a conditional decision point that routes based on current state and timeout status
- Timeouts provide buyer protection by defaulting to buyer refund, but may allow dispute escalation
- Multiple cancellation mechanisms exist at different stages for flexibility

## Detailed Method Call Paths

This section details all possible execution paths with specific method calls, parameters, and gas payment responsibilities.

**Legend**: 🔥 = Gas paid, 💰 = ETH/arbitration fee paid, ⚖️ = Arbitration system call

### Path 1: Happy Path - Normal Completion
1. **INITIAL** → **FUNDED**
   ```solidity
   createEscrow(
     agreementEncoded: bytes,     // EIP-712 encoded agreement
     buyerSignature: bytes,       // Buyer's signature on agreement  
     sellerSignature: bytes       // Seller's signature on agreement
   ) payable returns (uint256)
   ```
   - Called by: **Seller** 🔥💰 (pays gas + exact escrow amount in ETH)
   - ETH sent: `msg.value == agreement.amount`

2. **FUNDED** → **FIAT_TRANSFERRED**
   ```solidity
   provideFiatProof(
     escrowId: uint256,           // ID of the escrow
     proof: string               // IPFS CID or payment reference
   )
   ```
   - Called by: **Buyer** 🔥 (pays gas only)

3. **FIAT_TRANSFERRED** → **COMPLETE** → **CLOSED**
   ```solidity
   completeEscrow(
     escrowId: uint256           // ID of the escrow
   )
   ```
   - Called by: **Seller** 🔥 (pays gas only)
   - Result: Fee deducted, remainder sent to buyer, escrow closed

### Path 2A: Early Cancellation - Invalid Signature
1. **INITIAL** → **CLOSED**
   ```solidity
   createEscrow(
     agreementEncoded: bytes,     // EIP-712 encoded agreement
     buyerSignature: bytes,       // Invalid/mismatched signature
     sellerSignature: bytes       // Seller's signature on agreement
   ) payable returns (uint256)
   ```
   - Called by: **Seller** 🔥💰 (pays gas, ETH refunded due to failure)
   - Result: Transaction reverts or escrow immediately closed

### Path 2B: Early Cancellation - Buyer Unilateral
1. **INITIAL** → **FUNDED** (via createEscrow as Path 1.1)
2. **FUNDED** → **CLOSED**
   ```solidity
   buyerCancel(
     escrowId: uint256           // ID of the escrow
   )
   ```
   - Called by: **Buyer** 🔥 (pays gas only)
   - Result: Full refund to buyer (no fees), escrow closed

### Path 2C: Early Cancellation - Mutual
1. **INITIAL** → **FUNDED** (via createEscrow as Path 1.1)
2. **FUNDED** → **CLOSED**
   ```solidity
   mutualCancel(
     escrowId: uint256,           // ID of the escrow
     counterpartySignature: bytes // Other party's cancellation signature
   )
   ```
   - Called by: **Either Party** 🔥 (caller pays gas only)
   - Result: Full refund to buyer (no fees), escrow closed

### Path 3A: Timeout Resolution - Direct Close
1. **INITIAL** → **FUNDED** (via createEscrow as Path 1.1)
2. **FUNDED** → **CLOSED** (via timeout)
   ```solidity
   handleTimeout(
     escrowId: uint256           // ID of the escrow
   )
   ```
   - Called by: **Anyone** 🔥 (caller pays gas, may receive small incentive)
   - Condition: `block.timestamp > escrow.timeout`
   - Result: Full refund to buyer, escrow closed

### Path 3B: Timeout Resolution - From Fiat Transfer State
1. **INITIAL** → **FUNDED** → **FIAT_TRANSFERRED** (via Paths 1.1, 1.2)
2. **FIAT_TRANSFERRED** → **CLOSED** (via timeout)
   ```solidity
   resolveTimeout(
     escrowId: uint256           // ID of the escrow
   )
   ```
   - Called by: **Anyone** 🔥 (caller pays gas, may receive small incentive)
   - Condition: `block.timestamp > escrow.timeout`
   - Result: Full refund to buyer, escrow closed

### Path 4: Seller Dispute Flow
1. **INITIAL** → **FUNDED** → **FIAT_TRANSFERRED** (via Paths 1.1, 1.2)
2. **FIAT_TRANSFERRED** → **SELLER_DISPUTED**
   ```solidity
   createDispute(
     escrowId: uint256,          // ID of the escrow
     evidence: string           // Initial evidence submission
   ) payable returns (uint256)
   ```
   - Called by: **Seller** 🔥💰 (pays gas + arbitration fee)
   - ETH sent: `getArbitrationCost(escrowId, msg.sender)`

3. **SELLER_DISPUTED** → **CLOSED**
   ```solidity
   executeRuling(
     disputeId: uint256,         // ID of the dispute
     ruling: uint256,           // 0=refuse to arbitrate, 1=buyer wins, 2=seller wins
     resolution: string         // Arbitrator's resolution details
   )
   ```
   - Called by: **ArbitrationProxy** ⚖️🔥 (arbitration system pays gas)
   - Result: Funds distributed per ruling, arbitration fee handled per outcome

### Path 5A: Buyer Dispute Flow - From Funded
1. **INITIAL** → **FUNDED** (via createEscrow as Path 1.1)
2. **FUNDED** → **BUYER_DISPUTED**
   ```solidity
   createDispute(
     escrowId: uint256,          // ID of the escrow  
     evidence: string           // Initial evidence submission
   ) payable returns (uint256)
   ```
   - Called by: **Buyer** 🔥💰 (pays gas + arbitration fee)
   - ETH sent: `getArbitrationCost(escrowId, msg.sender)`

3. **BUYER_DISPUTED** → **COMPLETE** → **CLOSED**
   ```solidity
   executeRuling(
     disputeId: uint256,         // ID of the dispute
     ruling: uint256,           // Ruling in favor of buyer
     resolution: string         // Arbitrator's resolution details
   )
   ```
   - Called by: **ArbitrationProxy** ⚖️🔥 (arbitration system pays gas)

### Path 5B: Buyer Dispute Flow - From Timeout
1. Any timeout path leading to timeout condition
2. **Timeout Condition** → **BUYER_DISPUTED** (if dispute option available)
   ```solidity
   createDispute(
     escrowId: uint256,          // ID of the escrow
     evidence: string           // Evidence of legitimate claim
   ) payable returns (uint256)
   ```
   - Called by: **Buyer** 🔥💰 (pays gas + arbitration fee)
   - Condition: Dispute window still open post-timeout

3. **BUYER_DISPUTED** → **COMPLETE** → **CLOSED** (via executeRuling as Path 5A.3)

### Additional Dispute Methods (Available During Active Disputes)
```solidity
submitEvidence(
  escrowId: uint256,            // ID of the escrow
  evidence: string             // Additional evidence
)
```
- Called by: **Either Disputing Party** 🔥 (caller pays gas only)

```solidity
appeal(
  disputeId: uint256            // ID of the dispute
) payable
```
- Called by: **Either Disputing Party** 🔥💰 (pays gas + appeal fee)
- ETH sent: Appeal cost determined by arbitration system

```solidity
getArbitrationCost(
  escrowId: uint256,            // ID of the escrow
  disputer: address            // Address of potential disputer
) view returns (uint256)
```
- Called by: **Anyone** (view function, no gas for external calls)
- Returns: Required arbitration fee based on disputer's reputation

### Gas Payment Summary
- **Escrow Creation**: Seller pays gas + escrow amount
- **State Progression**: Party triggering transition pays gas
- **Disputes**: Disputer pays gas + arbitration fee (may be refunded based on outcome)
- **Timeouts**: Anyone can trigger (pays gas, may receive incentive)
- **Dispute Resolution**: Arbitration system handles final execution gas
- **Evidence Submission**: Each party pays their own gas costs

## Functional Behavior

- Creation (dual signatures)
  - Both buyer and seller sign identical `EscrowAgreement` off-chain (EIP-712).
  - Seller relays `createEscrow` with both signatures and exact ETH equal to the amount.
  - Agreement includes buyer, seller, amount, timeout, nonce, deadline.
  - Nonce must be scoped (e.g., per-buyer) to avoid cross-tenant collisions.

- Fiat payment proof
  - Only the buyer can register proof; proof is a short reference (e.g., IPFS CID) recorded for audit.

- Completion
  - Only the seller can complete after buyer’s proof; fee is applied; DAO receives fee; remainder is paid out.
  - Fee calculation is reputation-aware (buyer/seller), bounded by min/max, and SHOULD be snapshotted at creation to prevent mid-escrow reputation manipulation.

- Cancellation
  - Mutual cancel via counterparty authorization; unilateral cancellations as per policy (e.g., before fiat proof or pre-agreed windows).

- Disputes
  - Either party may open a dispute via the ArbitrationProxy; requires prepayment of a reputation-based arbitration fee by the disputer.
  - Evidence submission is possible while dispute active.
  - Ruling is enforced via `executeRuling` callback; funds are distributed according to ruling, fee refunded to winner based on the exact fee recorded at dispute creation.
  - The disputer pays a fee that is either reimbursed if they won or sent to the DAO if lost

- Timeouts
  - If timeout passes without completion, anyone may flag TIMEOUT_PASSED.
  - Resolution on timeout refunds the buyer (intended policy; consistent across tests and docs) and closes the escrow.

- Events
  - Emit state-change events for on-chain audit.
  - Emit reputation events for both parties at key milestones (creation, fiat transferred, completion, dispute events).

- Access control & pause
  - DAO-only for configuration updates, arbitration proxy updates, and pause/unpause.
  - Party-specific operations restricted to the concerned party.
  - Paused state blocks new creations and state changes, except DAO-defined emergency pathways (e.g., executing dispute rulings).

## Fees (Intent)
- Base fee percentage, with min/max, applied to escrow amount and influenced by combined reputation (weighted average, seller heavier weight).
- Dispute fee bands determined by disputer’s reputation.
- All fees bounded and sent to DAO (treasury) or configured recipient.
- Fee and/or scores SHOULD be snapshotted at creation.

## External Interface (Exposed Methods Only)
```solidity
// Creation and agreement helpers
function createEscrow(
    bytes calldata agreementEncoded,
    bytes calldata buyerSignature,
    bytes calldata sellerSignature
) external payable returns (uint256 escrowId);

function getAgreementHash(bytes calldata agreementEncoded)
    external view returns (bytes32 hash);

// Progression
function provideFiatProof(uint256 escrowId, string calldata proof) external;
function completeEscrow(uint256 escrowId) external;

// Cancellation
function mutualCancel(uint256 escrowId, bytes calldata counterpartySignature) external;
function buyerCancel(uint256 escrowId) external;
function sellerCancel(uint256 escrowId) external;

// Disputes via proxy
function createDispute(uint256 escrowId, string calldata evidence) external payable returns (uint256 disputeId);
function submitEvidence(uint256 escrowId, string calldata evidence) external;
function getArbitrationCost(uint256 escrowId, address disputer) external view returns (uint256);
function appeal(uint256 disputeId) external payable;
function executeRuling(uint256 disputeId, uint256 ruling, string calldata resolution) external;

// Timeout handling
function hasTimedOut(uint256 escrowId) external view returns (bool);
function handleTimeout(uint256 escrowId) external;
function resolveTimeout(uint256 escrowId) external;

// Administration
function updateConfig(bytes calldata newConfigEncoded) external;
function updateBaseFee(uint256 newBaseFee) external;
function updateDisputeFee(uint256 newDisputeFee) external;
function updateDAO(address newDAO) external;
function setArbitrationProxy(address arbitrationProxy) external;
function pause() external;
function unpause() external;
```

## Security and Invariants
- Dual-signature validation includes domain separation, deadline, and scoped nonces.
- No reliance on tx.origin anywhere (including Arbitration flows).
- All ETH transfers via .call with success checks; use CEI and reentrancy guards.
- Inputs validated (non-zero addresses, positive amounts, timeout bounds, bounded strings).
- Dispute fee refund uses the exact recorded amount at dispute creation.

## Deployment & Configuration
- Constructor receives DAO, ReputationOracle, ReputationEvents, and initial `EscrowConfig`.
- Config must satisfy min/base/max relationships and timeout bounds.

## Testing Scope (Intent)
- EIP-712 correctness, creation, state transitions, fee calculations and bounds, dispute lifecycle, timeout behavior (refund buyer), events integration, pause behavior, access control, and reentrancy.

Version: 1.0 · Status: Draft


