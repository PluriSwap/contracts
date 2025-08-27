// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./EscrowContract.sol";

/**
 * @title AbiEncodingTest
 * @notice Simple contract to test ABI encoding differences between Solidity and TypeScript
 */
contract AbiEncodingTest {
    
    /**
     * @notice Encode an EscrowAgreement exactly like Solidity tests do
     * @dev This will help us compare with TypeScript encodeAbiParameters
     */
    function encodeEscrowAgreement(
        address holder,
        address provider,
        uint256 amount,
        uint256 fundedTimeout,
        uint256 proofTimeout,
        uint256 nonce,
        uint256 deadline,
        uint16 dstChainId,
        address dstRecipient,
        bytes calldata dstAdapterParams
    ) external pure returns (bytes memory) {
        EscrowContract.EscrowAgreement memory agreement = EscrowContract.EscrowAgreement({
            holder: holder,
            provider: provider,
            amount: amount,
            fundedTimeout: fundedTimeout,
            proofTimeout: proofTimeout,
            nonce: nonce,
            deadline: deadline,
            dstChainId: dstChainId,
            dstRecipient: dstRecipient,
            dstAdapterParams: dstAdapterParams
        });
        
        return abi.encode(agreement);
    }
    
    /**
     * @notice Decode bytes back to EscrowAgreement to test compatibility
     */
    function decodeEscrowAgreement(bytes calldata agreementEncoded) 
        external 
        pure 
        returns (
            address holder,
            address provider,
            uint256 amount,
            uint256 fundedTimeout,
            uint256 proofTimeout,
            uint256 nonce,
            uint256 deadline,
            uint16 dstChainId,
            address dstRecipient,
            bytes memory dstAdapterParams
        ) 
    {
        EscrowContract.EscrowAgreement memory agreement = abi.decode(agreementEncoded, (EscrowContract.EscrowAgreement));
        
        return (
            agreement.holder,
            agreement.provider,
            agreement.amount,
            agreement.fundedTimeout,
            agreement.proofTimeout,
            agreement.nonce,
            agreement.deadline,
            agreement.dstChainId,
            agreement.dstRecipient,
            agreement.dstAdapterParams
        );
    }
    
    /**
     * @notice Test if our agreement bytes can be decoded successfully
     */
    function testDecoding(bytes calldata agreementEncoded) external view returns (bool success, string memory error) {
        try this.decodeEscrowAgreement(agreementEncoded) {
            return (true, "");
        } catch Error(string memory reason) {
            return (false, reason);
        } catch (bytes memory) {
            return (false, "Low-level revert");
        }
    }
}
