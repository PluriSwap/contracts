# Escrow Contract Specification (Codeless)

## Overview
Provides a P2P escrow for crypto against off-chain fiat settlement, with:
- Dual EIP-712 signatures to create and fund escrows atomically.
- Cross-chain fund delivery via Stargate integration for multi-network support.
- Comprehensive cost calculator for accurate fee estimation across networks.
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

## Cross-Chain Functionality

### Stargate Integration
The escrow contract supports cross-chain fund delivery using Stargate, enabling buyers to receive funds on different networks than where the escrow was created. This provides flexibility for global P2P transactions.

**Supported Networks**: All Stargate-supported chains (Ethereum, Polygon, Arbitrum, Optimism, BSC, Avalanche, Fantom, etc.)

**Cross-Chain Flow**:
1. Escrow created on seller's network (e.g., Ethereum) with buyer's contract address (same network) and destination address (any network)
2. Contract automatically detects if destination differs from source network
3. On completion, funds are either:
   - Sent directly to buyer (same network)
   - Bridged via Stargate to destination network (cross-chain)

### Escrow Agreement Structure
```solidity
struct EscrowAgreement {
    address buyer;              // Buyer's address on contract network (for signatures/interactions)
    address seller;             // Seller's address on contract network
    uint256 amount;             // Escrow amount in native token
    uint256 timeout;            // Timeout timestamp
    uint256 nonce;              // Scoped nonce for replay protection
    uint256 deadline;           // Signature validity deadline
    // Destination Configuration
    uint16 dstChainId;          // Destination chain ID (0 = same chain as contract)
    address dstRecipient;       // Final recipient address (can be different from buyer)
    bytes dstAdapterParams;     // Stargate parameters (gas for destination, etc.)
}
```

### Automatic Cross-Chain Detection
- **Same Network**: If `dstChainId == 0` or equals current chain ID, funds sent directly to `dstRecipient`
- **Cross-Chain**: If `dstChainId` differs from current chain, funds bridged via Stargate to `dstRecipient` on target network
- **Cost Calculation**: Automatically includes bridge fees when cross-chain delivery detected

### Cost Calculator
The contract provides comprehensive cost estimation for both same-chain and cross-chain escrows, helping users understand all fees upfront.

**Cost Components**:
- **Base Escrow Fee**: Reputation-aware percentage fee (deducted from deposit)
- **Cross-Chain Bridge Fee**: Stargate protocol fees (deducted from deposit)
- **Destination Gas**: Gas costs on destination network (deducted from deposit)
- **Dispute Costs**: Arbitration fees (paid separately by disputer to prevent abuse)

```solidity
struct EscrowCosts {
    uint256 escrowFee;          // Platform fee (deducted from deposit, goes to DAO)
    uint256 bridgeFee;          // Stargate bridge fee (deducted from deposit)
    uint256 destinationGas;     // Gas for destination chain (deducted from deposit)
    uint256 totalDeductions;    // Sum of deductions from deposit (excludes dispute costs)
    uint256 netRecipientAmount; // Amount recipient receives after platform/bridge fees
    uint256 maxDisputeCost;     // Max potential dispute cost (paid separately by disputer)
}
```

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
   ) payable
   ```
   - Called by: **Seller** 🔥 (pays gas only)
   - ETH sent: `0` (all fees deducted from deposited crypto)
   - Result: All fees (platform + bridge) deducted from deposit, net amount sent to `dstRecipient`, escrow closed

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
   - Fee handling: Arbitration cost paid by disputer to prevent frivolous disputes

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
   - Fee handling: Arbitration cost paid by disputer to prevent frivolous disputes

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
   - ETH sent: `getArbitrationCost(escrowId, msg.sender)` 
   - Fee handling: Arbitration cost paid by disputer to prevent frivolous disputes
   - Condition: Dispute window still open post-timeout

3. **BUYER_DISPUTED** → **COMPLETE** → **CLOSED** (via executeRuling as Path 5A.3)

### Path 6: Cost Estimation (Pre-Creation)
1. **Cost Calculation** (View Functions - No State Changes)
   ```solidity
   calculateEscrowCosts(
     agreementEncoded: bytes  // EIP-712 encoded agreement with all parameters
   ) view returns (EscrowCosts)
   ```
   - Called by: **Anyone** (view function, no gas cost for external calls)
   - Returns: Complete cost breakdown including:
     - Same-chain costs if `dstChainId == 0` or equals current chain
     - Cross-chain costs with bridge fees if destination differs
   - Automatically detects delivery method from agreement parameters

   ```solidity
   getStargateFee(
     dstChainId: uint16,      // Destination chain ID
     amount: uint256,         // Amount to bridge
     dstToken: address,       // Destination token address
     adapterParams: bytes     // Gas and other parameters
   ) view returns (uint256, uint256)
   ```
   - Called by: **Anyone** (view function, no gas cost for external calls)
   - Returns: (nativeFee, zroFee) - fees required for Stargate bridge

### Path 7: Network Discovery (Helper Functions)
```solidity
getSupportedChains() view returns (uint16[])
```
- Called by: **Anyone** (view function, no gas cost)
- Returns: Array of supported Stargate chain IDs

```solidity
getChainTokens(chainId: uint16) view returns (address[])
```
- Called by: **Anyone** (view function, no gas cost)
- Returns: Supported tokens on specified chain

### Additional Dispute Methods (Available During Active Disputes)
```solidity
submitEvidence(
  escrowId: uint256,            // ID of the escrow
  evidence: string             // Additional evidence
)
```
- Called by: **Either Disputing Party** 🔥 (caller pays gas only)

```solidity
getArbitrationCost(
  escrowId: uint256,            // ID of the escrow
  disputer: address            // Address of potential disputer
) view returns (uint256)
```
- Called by: **Anyone** (view function, no gas for external calls)
- Returns: Required arbitration fee based on disputer's reputation

### Gas Payment Summary
**Important: Platform and bridge fees deducted from deposit, dispute fees paid separately**

- **Escrow Creation**: Seller pays gas + deposits escrow amount in crypto
- **State Progression**: Party triggering transition pays gas only
- **Escrow Completion**: Seller pays gas only
  - Same-chain: Platform fee deducted from deposit, remainder to recipient
  - Cross-chain: Platform fee + bridge fees deducted from deposit, remainder bridged
- **Disputes**: Disputer pays gas + arbitration fee (paid separately to prevent abuse)
  - Arbitration fee refunded to winner, forfeited to DAO if loser
  - **No appeals**: Arbitration rulings are final
- **Timeouts**: Anyone can trigger (pays gas, may receive incentive from DAO)
- **Dispute Resolution**: Arbitration system handles final execution gas
- **Evidence Submission**: Each party pays their own gas costs
- **Cost Estimation**: View functions (no gas cost for external calls)
- **Network Discovery**: View functions (no gas cost for external calls)

**Fee Handling**:
- **From Deposit**: Platform escrow fee, bridge fees (cross-chain)
- **Paid Separately**: Arbitration fees (to prevent frivolous disputes)
- **Refund Mechanism**: Winning disputers get arbitration fees back, losers forfeit to DAO
- **Final Rulings**: No appeals - arbitration decisions are final and binding

## Functional Behavior

- Creation (dual signatures)
  - Both buyer and seller sign identical `EscrowAgreement` off-chain (EIP-712).
  - Seller relays `createEscrow` with both signatures and exact ETH equal to the amount.
  - Agreement includes buyer, seller, amount, timeout, nonce, deadline, plus destination details (dstChainId, dstToken, dstRecipient, dstAdapterParams).
  - Buyer address must be on same network as contract (for signatures/interactions).
  - Destination recipient can be any address on any Stargate-supported network.
  - Nonce must be scoped (e.g., per-buyer) to avoid cross-tenant collisions.

- Fiat payment proof
  - Only the buyer can register proof; proof is a short reference (e.g., IPFS CID) recorded for audit.

- Completion
  - Only the seller can complete after buyer's proof; all fees deducted from deposited crypto; DAO receives platform fee; net remainder is paid out.
  - Contract automatically detects delivery method based on agreement's `dstChainId`:
    - Same-chain: Platform fee deducted, remainder transferred to `dstRecipient`
    - Cross-chain: Platform fee + bridge fees deducted, remainder bridged to `dstRecipient` on destination network
  - All fees (platform + bridge) deducted from the original crypto deposit, seller only pays gas.
  - Fee calculation is reputation-aware (buyer/seller), bounded by min/max, and SHOULD be snapshotted at creation to prevent mid-escrow reputation manipulation.

- Cancellation
  - Mutual cancel via counterparty authorization; unilateral cancellations as per policy (e.g., before fiat proof or pre-agreed windows).

- Disputes
  - Either party may open a dispute via the ArbitrationProxy; arbitration fee is paid separately by the disputer to prevent frivolous disputes.
  - Disputer pays gas + arbitration fee directly (not from escrow deposit) to ensure skin in the game.
  - Evidence submission is possible while dispute active.
  - **Final rulings**: No appeals mechanism - arbitration decisions are binding and final.
  - Ruling is enforced via `executeRuling` callback; funds distributed according to ruling, arbitration fee refunded to winner.
  - If disputer loses, arbitration fee is forfeited to DAO; if disputer wins, fee is refunded to them.

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
**Fee Structure**: Platform/bridge fees deducted from deposit, dispute fees paid separately
- Base fee percentage, with min/max, applied to escrow amount and influenced by combined reputation (weighted average, seller heavier weight). Deducted from deposit.
- Cross-chain bridge fees (Stargate) deducted from deposit when cross-chain delivery occurs.
- Dispute fee bands determined by disputer's reputation. **Paid separately by disputer** to prevent frivolous disputes and ensure proper economic incentives.
- Platform and bridge fees bounded and sent to DAO (treasury) or configured recipient from the deposited funds.
- Arbitration fees held by contract and refunded to winners, forfeited to DAO by losers.
- **Final arbitration**: No appeals mechanism - rulings are binding and final.
- Fee and/or scores SHOULD be snapshotted at creation.
- Recipients receive net amount after platform/bridge fees are deducted from the original deposit.

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
function completeEscrow(uint256 escrowId) external payable;

// Cancellation
function mutualCancel(uint256 escrowId, bytes calldata counterpartySignature) external;
function buyerCancel(uint256 escrowId) external;
function sellerCancel(uint256 escrowId) external;

// Disputes via proxy
function createDispute(uint256 escrowId, string calldata evidence) external payable returns (uint256 disputeId);
function submitEvidence(uint256 escrowId, string calldata evidence) external;
function getArbitrationCost(uint256 escrowId, address disputer) external view returns (uint256);
function executeRuling(uint256 disputeId, uint256 ruling, string calldata resolution) external;

// Timeout handling
function hasTimedOut(uint256 escrowId) external view returns (bool);
function handleTimeout(uint256 escrowId) external;
function resolveTimeout(uint256 escrowId) external;

// Cost Calculation
function calculateEscrowCosts(
    bytes calldata agreementEncoded
) external view returns (EscrowCosts memory costs);

function getStargateFee(
    uint16 dstChainId,
    uint256 amount,
    address dstToken,
    bytes calldata adapterParams
) external view returns (uint256 nativeFee, uint256 zroFee);

function getSupportedChains() external view returns (uint16[] memory chainIds);
function getChainTokens(uint16 chainId) external view returns (address[] memory tokens);

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
- Constructor receives DAO, ReputationOracle, ReputationEvents, StargateRouter, and initial `EscrowConfig`.
- Config must satisfy min/base/max relationships and timeout bounds.
- Stargate integration requires router address and supported chain/token mappings.
- Cross-chain configurations must be validated against Stargate pool availability.

## Testing Scope (Intent)
- EIP-712 correctness, creation, state transitions, fee calculations and bounds, dispute lifecycle (final rulings, no appeals), timeout behavior (refund buyer), events integration, pause behavior, access control, and reentrancy.
- Cross-chain functionality: Stargate integration, bridge fee calculations, cross-chain completion flows, destination chain validation.
- Cost calculator accuracy: fee estimation across networks, reputation impact on costs, bridge fee queries.
- Dispute finality: Testing that arbitration rulings are final and binding with proper fee handling.

Version: 1.0 · Status: Draft


