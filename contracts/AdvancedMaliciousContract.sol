// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IEscrowContract {
    function createEscrow(bytes calldata agreementEncoded, bytes calldata holderSignature, bytes calldata providerSignature) external payable;
    function provideOffchainProof(uint256 escrowId, string calldata proof) external;
    function completeEscrow(uint256 escrowId) external payable;
    function cancel(uint256 escrowId) external;
}

contract AdvancedMaliciousContract {
    IEscrowContract public escrowContract;
    uint256 public reentryCount;
    bool public shouldReenter;
    uint256 public maxReentries;

    constructor(address _escrowContract) {
        escrowContract = IEscrowContract(_escrowContract);
        reentryCount = 0;
        shouldReenter = false;
        maxReentries = 3;
    }

    function setReentryConfig(bool _shouldReenter, uint256 _maxReentries) external {
        shouldReenter = _shouldReenter;
        maxReentries = _maxReentries;
    }

    // Malicious fallback that attempts reentrancy
    receive() external payable {
        if (shouldReenter && reentryCount < maxReentries) {
            reentryCount++;

            // Try to reenter escrow completion
            if (reentryCount == 1) {
                try escrowContract.completeEscrow(0) {
                    // Success - this should be blocked
                } catch {
                    // Expected to fail due to reentrancy guard
                }
            }

            // Try to create new escrow during completion
            if (reentryCount == 2) {
                // This would require valid signatures, so just increment counter
            }
        }
    }

    function attackCreateEscrow(bytes calldata agreementEncoded, bytes calldata holderSignature, bytes calldata providerSignature) external payable {
        escrowContract.createEscrow{value: msg.value}(agreementEncoded, holderSignature, providerSignature);
    }

    function attackCompleteEscrow(uint256 escrowId) external {
        escrowContract.completeEscrow(escrowId);
    }
}
