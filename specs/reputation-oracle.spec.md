# Reputation Oracle Specification (Codeless)

## Overview
The Reputation Oracle provides read-only reputation data for wallets and controlled write access for DAO-approved trusted parties. Its data informs fee schedules and risk checks in `Escrow` and `ArbitrationProxy`.

## Behavioral Requirements

- Data model (intent)
  - For each wallet, store counters and volumes across started/completed/cancelled/disputed transactions, disputes won/lost, a composite score (0–1000), lastUpdated timestamp, and an isActive bit.

- Reads
  - `score_of` returns the complete WalletScore. It is constant-time and available to any caller.

- Writes
  - Only DAO-approved trusted parties (or DAO) may load or batch load scores.
  - Calls replace the entire score payload for a wallet and update lastUpdated; score values are validated (bounds and logical consistency).
  - A wallet can be deactivated (isActive=false) without deleting history (if policy dictates).

- Governance
  - DAO manages trusted parties and can pause/unpause operations and update the DAO address.

- Freshness
  - Consumers should enforce freshness policies (e.g., reject scores older than a threshold) based on `lastUpdated`.

- Security
  - All state-changing functions revert when paused.
  - Strict validation of array sizes and numerical bounds to prevent corrupt state.

## External Interface (Exposed Methods Only)
```solidity
// Reads
function score_of(address wallet) external view returns (bytes memory walletScoreEncoded);

// Writes (authorized: DAO or trusted party)
function load(address wallet, uint256[11] calldata data) external;
function batchLoad(address[] calldata wallets, uint256[11][] calldata data) external;

// Governance (DAO-only)
function addTrustedParty(address party) external;
function removeTrustedParty(address party) external;
function pause() external;
function unpause() external;
function updateDAO(address newDAO) external;
```

## Validation Rules (Intent)
- Score in [0, 1000].
- Completed ≤ Started; Disputed ≤ Started; Cancelled ≤ Started.
- VolumeCompleted ≤ VolumeStarted; sums within uint bounds.
- DisputesWon + DisputesLost ≤ Disputed.
- Non-zero wallet addresses for writes.


## Scoring Formula

The reputation score is calculated using a weighted combination of multiple factors, normalized to a 0-1000 scale:
Final Score = min(1000, Base Score × Activity Multiplier × Freshness Factor)
### Base Score Components
1. Success Rate (40% weight)
Success Rate = (Completed Transactions / Started Transactions) × 100
Success Score = Success Rate × 4.0
2. Dispute Performance (25% weight)
If Disputed > 0:
    Dispute Win Rate = (Disputes Won / Disputed) × 100
    Dispute Score = Dispute Win Rate × 2.5
Else:
    Dispute Score = 250 (neutral bonus for no disputes)
3. Volume Reliability (20% weight)
Volume Completion Rate = (Volume Completed / Volume Started) × 100
Volume Score = Volume Completion Rate × 2.0
4. Transaction Consistency (15% weight)
If Started > 0:
    Cancellation Rate = (Cancelled / Started) × 100
    Consistency Score = max(0, (100 - Cancellation Rate) × 1.5)
Else:
    Consistency Score = 0

### Activity Multiplier
If Started >= 50: Multiplier = 1.0
If Started >= 20: Multiplier = 0.95
If Started >= 10: Multiplier = 0.90
If Started >= 5:  Multiplier = 0.85
If Started >= 1:  Multiplier = 0.75
Else:             Multiplier = 0.5 (new user)

### Freshness Factor
Days Since Last Update = (current timestamp - lastUpdated) / 86400

If Days <= 30:   Factor = 1.0
If Days <= 60:   Factor = 0.95
If Days <= 90:   Factor = 0.90
If Days <= 180:  Factor = 0.80
Else:            Factor = 0.70

### Reputation Bands
🟢 DIAMOND (900-1000)

Description: Elite traders with exceptional track record
Benefits: Lowest fees, highest trust level

🔵 PLATINUM (800-899)

Description: Highly reliable traders with strong history
Benefits: Reduced fees, high trust level

🟡 GOLD (650-799)

Description: Established traders with good performance
Benefits: Standard fees, moderate trust level

🟠 SILVER (500-649)

Description: Developing traders with mixed performance
Benefits: Slightly higher fees, basic trust level

🔴 BRONZE (300-499)

Description: New or inconsistent traders requiring caution
Benefits: Higher fees, requires careful evaluation

⚫ UNRATED (0-299)

Description: New users or those with poor track record
Benefits: Highest fees, maximum caution required

## Testing Scope (Intent)
- Deployment, access controls, writes by trusted parties, data validation, batch operations, pause/unpause, DAO updates, performance bounds.

Version: 1.0 · Status: Draft


