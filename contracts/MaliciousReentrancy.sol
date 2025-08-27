// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./EscrowContract.sol";

/**
 * @title MaliciousReentrancy
 * @notice A malicious contract designed to test reentrancy protection
 * @dev This contract attempts to exploit reentrancy vulnerabilities in EscrowContract
 */
contract MaliciousReentrancy {
    EscrowContract public escrowContract;
    uint256 public attackCount;
    bool public attackInProgress;
    
    event AttackAttempt(uint256 count);
    event AttackFailed(string reason);
    
    constructor(address _escrowContract) {
        escrowContract = EscrowContract(payable(_escrowContract));
    }
    
    /**
     * @notice Attempt a reentrancy attack during escrow operations
     * @param escrowId The escrow ID to attack
     */
    function attemptReentrancyAttack(uint256 escrowId) external payable {
        require(!attackInProgress, "Attack already in progress");
        attackInProgress = true;
        attackCount = 0;
        
        try escrowContract.holderCancel(escrowId) {
            // Attack attempt - if successful, receive() will be called during _safeTransfer
        } catch Error(string memory reason) {
            emit AttackFailed(reason);
            attackInProgress = false;
            return;
        } catch (bytes memory) {
            emit AttackFailed("Low-level revert");
            attackInProgress = false;
            return;
        }
        
        attackInProgress = false;
    }
    
    /**
     * @notice This function is called when ETH is sent to this contract
     * @dev This is where we attempt the reentrancy attack
     */
    receive() external payable {
        if (attackInProgress && attackCount < 3) {
            attackCount++;
            emit AttackAttempt(attackCount);
            
            // Attempt to reenter the escrow contract
            // Try multiple reentrancy vectors
            if (attackCount == 1) {
                // Try to create another escrow during the callback
                _attemptEscrowCreation();
            } else if (attackCount == 2) {
                // Try to cancel another escrow
                _attemptEscrowCancellation();
            } else {
                // Try to dispute an escrow
                _attemptDisputeCreation();
            }
        }
    }
    
    function _attemptEscrowCreation() internal {
        // This would require valid signatures, so it's mainly testing
        // that the nonReentrant modifier blocks the call
        bytes memory dummyAgreement = "0x";
        bytes memory dummySig1 = "0x";
        bytes memory dummySig2 = "0x";
        
        try escrowContract.createEscrow{value: 0.1 ether}(
            dummyAgreement,
            dummySig1,
            dummySig2
        ) {
            // Reentrancy succeeded (bad!)
        } catch {
            // Expected to fail due to reentrancy protection
        }
    }
    
    function _attemptEscrowCancellation() internal {
        try escrowContract.holderCancel(0) {
            // Reentrancy succeeded (bad!)
        } catch {
            // Expected to fail due to reentrancy protection
        }
    }
    
    function _attemptDisputeCreation() internal {
        try escrowContract.createDispute{value: 0.01 ether}(0, "Reentrancy attack evidence") {
            // Reentrancy succeeded (bad!)
        } catch {
            // Expected to fail due to reentrancy protection
        }
    }
    
    /**
     * @notice Allow withdrawing any ETH sent to this contract
     */
    function withdraw() external {
        payable(msg.sender).transfer(address(this).balance);
    }
}
