# PluriSwap Integration Testing Specification (Codeless)

## Overview
Defines end-to-end integration tests across DAO, Reputation Oracle, ReputationEvents, ArbitrationProxy, and Escrow. Validates user journeys, cross-contract state coherence, economics, and emergency operations.

## Environment Setup (Intent)
- Deploy DAO (5 signers, configured delays/limits).
- Deploy Oracle with DAO; add a trusted data provider.
- Deploy ReputationEvents in allowlist mode; authorize Escrow and ArbitrationProxy.
- Deploy ArbitrationProxy with DAO and initial fee config; add initial support agent(s); authorize Escrow.
- Deploy Escrow with DAO, Oracle, Events, and initial fee/timeout config; set ArbitrationProxy.

## E2E User Journeys
- Happy-path escrow:
  - High-reputation buyer and seller; create escrow via dual signatures; buyer provides fiat proof; seller completes; fees charged at snapshot; DAO receives fee; reputation events emitted; oracle updated off-chain and reloaded.
- First-time users:
  - No reputation → maximum fees; complete; initial score creation; subsequent transactions reflect improved fees.
- Dispute flow:
  - Open dispute from FUNDED/FIAT_TRANSFERRED; submit bilateral evidence; support agent resolves; escrow callback executes ruling; fee refund to winner using exact paid value; events emitted; oracle updated accordingly.

## Cross-Contract Scenarios
- Dynamic fees:
  - Preload varied reputation; confirm fee bands and bounds; snapshot behavior validated against manipulation.
- Oracle unavailability:
  - Pause oracle; escrow creation falls back (policy-dependent) or blocks; unpause and resume normal operation.
- Events lifecycle:
  - Ensure consistent ingestion by ReputationEvents; off-chain correlation across contracts.

## Governance Operations
- Coordinated updates:
  - DAO proposes and executes fee changes across Escrow and ArbitrationProxy; verify contracts reflect new parameters.
- Emergency shutdown:
  - Pause all components; verify new operations blocked and critical closures still possible; recover with controlled unpausing.
- DAO migration:
  - Update DAO references across all contracts, transfer treasury, and verify control fully transitions.

## Advanced Scenarios
- Multi-escrow concurrency:
  - Multiple escrows in various states; concurrent transitions; isolation guarantees.
- Bulk operations:
  - Batch oracle loads; many simultaneous events; gas and latency characterization.

## Security and Resilience
- Reentrancy across boundaries (Escrow payouts, Arbitration callbacks).
- Economic attacks (fee avoidance, dispute spam); ensure reputation-based fees and bounds deter abuse.
- Data consistency and event ordering under contention; recovery after network congestion.

## Performance & Longevity
- Load tests at target throughputs (escrows/disputes/events).
- Long-run simulation (months) to observe parameter stability, fee revenue, and dispute latencies.

## Success Criteria
- Functional: All defined flows complete with expected state and funds distribution.
- Performance: Gas within targets, throughput sustained.
- Security: No successful reentrancy or governance bypasses.
- Reliability: Deterministic state consistency across contracts; event auditability.

## TypeScript/Hardhat Test Use Cases

### Basic Escrow Operations
**UC-001: Happy Path Same-Chain Escrow**
- Deploy all contracts with proper configuration
- Create escrow with dual signatures (buyer/seller)
- Buyer provides fiat proof
- Seller completes escrow
- Verify platform fee deducted from deposit, remainder sent to buyer
- Confirm reputation events emitted
- Validate escrow state transitions (FUNDED → FIAT_TRANSFERRED → COMPLETE → CLOSED)

**UC-002: Happy Path Cross-Chain Escrow**  
- Create escrow with destination chain different from source
- Mock Stargate router for cross-chain bridging
- Seller completes escrow with cross-chain delivery
- Verify platform fee + bridge fee deducted from deposit
- Confirm cross-chain bridge call made with correct parameters
- Validate net amount calculation and event emission

**UC-003: Cost Calculator Accuracy**
- Test `calculateEscrowCosts()` with various reputation scenarios
- Compare calculated vs actual fees for same-chain escrows
- Compare calculated vs actual fees for cross-chain escrows
- Verify bridge fee estimation matches Stargate quotes
- Test edge cases (min/max fees, zero reputation, high reputation)

### Escrow Creation and Validation
**UC-004: Dual Signature Validation**
- Test valid dual signatures with matching agreement parameters
- Test invalid buyer signature (should reject)
- Test invalid seller signature (should reject)
- Test signature replay attacks (nonce validation)
- Test expired signatures (deadline validation)
- Test mismatched agreement parameters between signatures

**UC-005: Deposit Amount Validation**
- Test exact deposit amount matching agreement
- Test insufficient deposit (should reject)
- Test excess deposit (should reject or refund excess)
- Test zero amount escrow (should reject)

**UC-006: Cross-Chain Configuration Validation**
- Test supported destination chains
- Test unsupported destination chains (should reject)
- Test invalid token addresses on destination chain
- Test same chain with dstChainId = 0 or current chain ID

### Cancellation Scenarios
**UC-007: Buyer Unilateral Cancellation**
- Create escrow in FUNDED state
- Buyer cancels before providing fiat proof
- Verify full refund to buyer (no fees)
- Confirm escrow state transitions to CLOSED
- Test unauthorized cancellation by seller (should reject)

**UC-008: Mutual Cancellation**
- Create escrow in FUNDED state
- Generate mutual cancellation signature
- Execute mutual cancellation
- Verify full refund to buyer
- Test invalid counterparty signature (should reject)

**UC-009: Seller Cancellation (if applicable)**
- Test seller cancellation under specific conditions
- Verify proper fund handling and state transitions

### Timeout Handling
**UC-010: Timeout from FUNDED State**
- Create escrow and let timeout expire
- Call `handleTimeout()` or `resolveTimeout()`
- Verify full refund to buyer
- Confirm escrow closes properly
- Test premature timeout call (should reject)

**UC-011: Timeout from FIAT_TRANSFERRED State**
- Progress escrow to FIAT_TRANSFERRED
- Let timeout expire without seller completion
- Trigger timeout resolution
- Verify buyer refund and escrow closure
- Test seller trying to complete after timeout (should reject)

**UC-012: Timeout with Dispute Option**
- Create timeout scenario
- Test buyer initiating dispute within dispute window
- Verify dispute can be created even after timeout
- Test dispute window expiry

### Dispute Lifecycle
**UC-013: Seller Initiates Dispute**
- Progress escrow to FIAT_TRANSFERRED state
- Seller creates dispute with evidence
- Verify arbitration fee paid separately by seller
- Confirm escrow state transition to SELLER_DISPUTED
- Test insufficient arbitration fee payment (should reject)

**UC-014: Buyer Initiates Dispute**
- Create dispute from FUNDED state
- Buyer pays arbitration fee and provides evidence
- Verify state transition to BUYER_DISPUTED
- Test dispute from various escrow states

**UC-015: Evidence Submission**
- Create active dispute
- Both parties submit additional evidence
- Verify evidence stored and events emitted
- Test evidence submission by non-parties (should reject)
- Test evidence submission after dispute closed (should reject)

**UC-016: Dispute Resolution - Seller Wins**
- Create seller dispute scenario
- Mock arbitrator executing ruling in favor of seller
- Verify seller gets funds from escrow
- Confirm seller's arbitration fee is refunded
- Validate escrow state transitions to CLOSED

**UC-017: Dispute Resolution - Buyer Wins**
- Create buyer dispute scenario  
- Execute ruling in favor of buyer
- Verify buyer receives funds
- Confirm buyer's arbitration fee is refunded
- Test loser's fee forfeited to DAO

**UC-018: Invalid Dispute Resolution**
- Test ruling execution by unauthorized caller (should reject)
- Test ruling on non-existent dispute (should reject)
- Test double ruling execution (should reject)

### Fee Handling and Economics
**UC-019: Reputation-Based Fee Calculation**
- Test escrows with various buyer/seller reputation combinations
- Verify fee calculation follows reputation-aware formula
- Test min/max fee boundaries
- Confirm fees are snapshotted at creation time

**UC-020: Cross-Chain Bridge Fee Deduction**
- Create cross-chain escrow
- Mock Stargate fee calculation
- Complete escrow and verify bridge fees deducted correctly
- Test scenarios where bridge fees exceed deposit (should reject)

**UC-021: DAO Fee Collection**
- Complete various escrow types
- Verify DAO treasury receives platform fees
- Test fee distribution in dispute scenarios
- Confirm forfeited dispute fees go to DAO

**UC-022: Fee Edge Cases**
- Test escrows with minimum viable amounts
- Test fee calculations with extreme reputation scores
- Verify fee deduction order (dispute → platform → bridge → remainder)
- Test scenarios where total fees approach deposit amount

### Cross-Chain Integration
**UC-023: Stargate Integration**
- Mock Stargate router contract
- Test cross-chain completion calls Stargate correctly
- Verify adapter parameters passed correctly
- Test Stargate call failures and error handling

**UC-024: Network Discovery**
- Test `getSupportedChains()` returns correct chain IDs
- Test `getChainTokens()` for various supported chains
- Verify unsupported chain detection

**UC-025: Bridge Fee Estimation**
- Test `getStargateFee()` with various parameters
- Compare estimates with actual Stargate costs
- Test edge cases (large amounts, exotic tokens)

### Security and Error Handling
**UC-026: Reentrancy Protection**
- Test reentrancy attacks during escrow completion
- Test reentrancy during dispute resolution
- Verify all external calls properly protected

**UC-027: Access Control**
- Test unauthorized calls to restricted functions
- Verify only appropriate parties can trigger state changes
- Test admin function access control

**UC-028: Pause Mechanism**
- Pause escrow contract
- Verify new escrow creation blocked
- Test existing escrow operations during pause
- Test emergency operations still work
- Unpause and verify normal operations resume

**UC-029: Invalid Input Handling**
- Test all functions with zero addresses
- Test functions with invalid amounts
- Test malformed signatures and data
- Verify proper error messages and reverts

### Integration with Other Contracts
**UC-030: Reputation Oracle Integration**
- Test escrow creation with various oracle states
- Test oracle unavailability scenarios
- Verify reputation score retrieval and caching
- Test oracle update triggers after escrow completion

**UC-031: Reputation Events Integration**
- Verify events emitted at all escrow lifecycle points
- Test event emission during disputes
- Confirm event data accuracy and completeness
- Test events allowlist and authorization

**UC-032: Arbitration Proxy Integration**
- Test dispute creation through arbitration proxy
- Verify arbitration cost calculation accuracy
- Test arbitration proxy state synchronization
- Test ruling execution callback

### Edge Cases and Stress Testing
**UC-033: Concurrent Escrow Operations**
- Create multiple escrows simultaneously
- Test state isolation between escrows
- Verify no cross-contamination of funds or state
- Test high-volume escrow creation

**UC-034: Gas Optimization Validation**
- Measure gas costs for all major operations
- Verify gas costs within acceptable limits
- Test gas cost impact of different parameter combinations
- Optimize gas usage where possible

**UC-035: Long-Running Escrow Scenarios**
- Create escrows with maximum timeout periods
- Test escrow behavior over extended time periods
- Verify timestamp handling and overflow protection
- Test cleanup of expired escrows

**UC-036: Emergency Recovery Scenarios**
- Test DAO emergency functions
- Verify fund recovery mechanisms
- Test contract upgrade scenarios (if applicable)
- Validate emergency pause and recovery procedures

### Deployment and Configuration
**UC-037: Contract Deployment**
- Test proper deployment sequence of all contracts
- Verify initial configuration parameters
- Test contract address validation and cross-references
- Validate initial permissions and access control

**UC-038: Configuration Updates**
- Test DAO updating various contract parameters
- Verify configuration change validation
- Test parameter update effects on existing escrows
- Confirm proper event emission for config changes

### Performance and Scalability
**UC-039: Throughput Testing**
- Test maximum escrow creation rate
- Measure dispute handling throughput
- Test cross-chain operation performance
- Validate system performance under load

**UC-040: State Management Efficiency**
- Test escrow storage optimization
- Verify efficient state cleanup after completion
- Test memory usage during large-scale operations
- Validate storage cost optimization

Version: 1.0 · Status: Draft


