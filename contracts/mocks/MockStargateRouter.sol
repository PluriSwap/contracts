// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title MockStargateRouter
 * @notice Mock contract for testing Stargate cross-chain functionality
 * @dev Simulates Stargate router behavior for integration testing
 */
contract MockStargateRouter {
    
    struct BridgeCall {
        uint16 dstChainId;
        address token;
        uint256 amount;
        address recipient;
        bytes adapterParams;
        uint256 nativeFee;
        uint256 zroFee;
        uint256 timestamp;
    }
    
    BridgeCall[] public bridgeCalls;
    mapping(uint16 => bool) public supportedChains;
    mapping(uint16 => mapping(address => bool)) public supportedTokens;
    
    event CrossChainTransfer(
        uint16 indexed dstChainId,
        address indexed token,
        uint256 amount,
        address indexed recipient
    );
    
    constructor() {
        // Set up some mock supported chains
        supportedChains[1] = true;      // Ethereum
        supportedChains[137] = true;    // Polygon
        supportedChains[42161] = true;  // Arbitrum
        supportedChains[10] = true;     // Optimism
        supportedChains[56] = true;     // BSC
        
        // Mock supported tokens (using zero address for native tokens)
        supportedTokens[1][address(0)] = true;
        supportedTokens[137][address(0)] = true;
        supportedTokens[42161][address(0)] = true;
        supportedTokens[10][address(0)] = true;
        supportedTokens[56][address(0)] = true;
    }
    
    /**
     * @notice Simulate Stargate quote fee function
     */
    function quoteLayerZeroFee(
        uint16 _dstChainId,
        uint8 /* _functionType */,
        bytes calldata /* _toAddress */,
        bytes calldata _transferAndCallPayload,
        bytes calldata /* _adapterParams */
    ) external view returns (uint256 nativeFee, uint256 zroFee) {
        require(supportedChains[_dstChainId], "Unsupported chain");
        
        // Mock fee calculation (simplified)
        nativeFee = 0.001 ether + (_transferAndCallPayload.length * 100); // Base fee + payload cost
        zroFee = 0; // Usually 0 for most chains
        
        return (nativeFee, zroFee);
    }
    
    /**
     * @notice Simulate cross-chain swap
     */
    function swap(
        uint16 _dstChainId,
        uint256 /* _srcPoolId */,
        uint256 /* _dstPoolId */,
        address payable /* _refundAddress */,
        uint256 _amountLD,
        uint256 /* _minAmountLD */,
        IStargateRouter.lzTxObj memory _lzTxParams,
        bytes calldata /* _to */,
        bytes calldata /* _payload */
    ) external payable {
        require(supportedChains[_dstChainId], "Unsupported destination chain");
        require(msg.value >= 0.001 ether, "Insufficient gas for cross-chain");
        
        // Record the bridge call
        BridgeCall memory bridgeCall = BridgeCall({
            dstChainId: _dstChainId,
            token: address(0), // Native token
            amount: _amountLD,
            recipient: address(0), // Would decode from _to in real implementation
            adapterParams: abi.encode(_lzTxParams),
            nativeFee: msg.value,
            zroFee: 0,
            timestamp: block.timestamp
        });
        
        bridgeCalls.push(bridgeCall);
        
        emit CrossChainTransfer(_dstChainId, address(0), _amountLD, address(0));
        
        // In a real implementation, this would trigger the cross-chain message
        // For testing, we just record the call
    }
    
    /**
     * @notice Simple bridge function (alternative interface)
     */
    function bridge(
        uint16 dstChainId,
        address token,
        uint256 amount,
        address recipient,
        bytes calldata adapterParams
    ) external payable {
        require(supportedChains[dstChainId], "Unsupported chain");
        require(supportedTokens[dstChainId][token], "Unsupported token");
        
        BridgeCall memory bridgeCall = BridgeCall({
            dstChainId: dstChainId,
            token: token,
            amount: amount,
            recipient: recipient,
            adapterParams: adapterParams,
            nativeFee: msg.value,
            zroFee: 0,
            timestamp: block.timestamp
        });
        
        bridgeCalls.push(bridgeCall);
        
        emit CrossChainTransfer(dstChainId, token, amount, recipient);
    }
    
    /**
     * @notice Get all bridge calls made
     */
    function getBridgeCalls() external view returns (BridgeCall[] memory) {
        return bridgeCalls;
    }
    
    /**
     * @notice Get bridge call count
     */
    function getBridgeCallCount() external view returns (uint256) {
        return bridgeCalls.length;
    }
    
    /**
     * @notice Check if chain is supported
     */
    function isChainSupported(uint16 chainId) external view returns (bool) {
        return supportedChains[chainId];
    }
    
    /**
     * @notice Add supported chain (for testing)
     */
    function addSupportedChain(uint16 chainId) external {
        supportedChains[chainId] = true;
    }
    
    /**
     * @notice Add supported token (for testing)
     */
    function addSupportedToken(uint16 chainId, address token) external {
        supportedTokens[chainId][token] = true;
    }
    
    /**
     * @notice Reset bridge calls (for testing)
     */
    function resetBridgeCalls() external {
        delete bridgeCalls;
    }
    
    /**
     * @notice Simulate bridge fee calculation
     */
    function calculateBridgeFee(
        uint16 /* dstChainId */,
        uint256 amount,
        bytes calldata adapterParams
    ) external pure returns (uint256 fee) {
        // Simple mock fee calculation
        fee = amount / 1000; // 0.1% bridge fee
        
        // Add gas fee based on adapter params
        if (adapterParams.length > 0) {
            fee += 0.001 ether; // Base gas fee
        }
        
        return fee;
    }
    
    // Receive function to accept ETH
    receive() external payable {}
}

/**
 * @notice Interface for Stargate Router compatibility
 */
interface IStargateRouter {
    struct lzTxObj {
        uint256 dstGasForCall;
        uint256 dstNativeAmount;
        bytes dstNativeAddr;
    }
}
