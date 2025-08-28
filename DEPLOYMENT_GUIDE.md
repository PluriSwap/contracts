# 🚀 PluriSwap Multi-Network Deployment Guide

This guide covers deploying PluriSwap contracts across multiple blockchain networks with network-specific optimizations.

## 📋 Supported Networks & Tokens

### 🌐 **Supported Blockchains**
- **Ethereum** (Mainnet & Sepolia)
- **Polygon** (Mainnet & Amoy)
- **BNB Chain** (Mainnet & Testnet)
- **Arbitrum** (Mainnet & Sepolia)
- **Base** (Mainnet & Sepolia)
- **Celo** (Mainnet & Alfajores)

### 🪙 **Supported Tokens**
- **USDT** (Tether USD)
- **USDC** (USD Coin)
- **WBTC** (Wrapped Bitcoin)
- **DAI** (Dai Stablecoin)
- **ETH** (Native Ethereum)

## ⚙️ Configuration Setup

### 1. Environment Variables

Copy the deployment environment template and configure your settings:

```bash
cp deployment-env.example .env
```

Edit `.env` with your actual values:

```bash
# RPC URLs (required for each network you want to deploy to)
MAINNET_RPC_URL=https://mainnet.infura.io/v3/YOUR_INFURA_PROJECT_ID
POLYGON_RPC_URL=https://polygon-rpc.com
BSC_RPC_URL=https://bsc-dataseed.binance.org
# ... etc for each network

# Private Keys (required - use different keys for different networks)
MAINNET_PRIVATE_KEY=0xYOUR_PRIVATE_KEY_HERE
POLYGON_PRIVATE_KEY=0xYOUR_PRIVATE_KEY_HERE
# ... etc

# Block Explorer API Keys (required for contract verification)
ETHERSCAN_API_KEY=YOUR_ETHERSCAN_API_KEY
POLYGONSCAN_API_KEY=YOUR_POLYGONSCAN_API_KEY
# ... etc
```

### 2. Network-Specific Configurations

Each network has optimized parameters:

**Note:** Polygon has migrated from Mumbai to Amoy testnet. All configurations have been updated to use Amoy (Chain ID: 80002).

| Network | Gas Fee | Dispute Fee | Min Fee | Max Fee | Block Time |
|---------|---------|-------------|---------|---------|------------|
| Ethereum | 2.5% | 1.0% | 0.001 ETH | 1 ETH | 12s |
| Polygon | 2.0% | 0.8% | 0.01 MATIC | 10 MATIC | 2s |
| BSC | 2.0% | 0.8% | 0.001 BNB | 5 BNB | 3s |
| Arbitrum | 2.0% | 0.8% | 0.0001 ETH | 0.5 ETH | 0.25s |
| Base | 2.0% | 0.8% | 0.0001 ETH | 0.5 ETH | 2s |
| Celo | 3.0% | 1.5% | 0.01 CELO | 5 CELO | 5s |

## 🚀 Deployment Commands

### Single Network Deployment

```bash
# Deploy to specific networks
npm run deploy:sepolia
npm run deploy:mainnet
npm run deploy:polygon
npm run deploy:bsc
npm run deploy:arbitrum
npm run deploy:base
npm run deploy:celo

# Deploy to testnets
npm run deploy:polygon-amoy
npm run deploy:bsc-testnet
npm run deploy:arbitrum-sepolia
npm run deploy:base-sepolia
npm run deploy:celo-alfajores
```

### Multi-Network Deployment

```bash
# Deploy to all testnets
npm run deploy:testnets

# Deploy to all mainnets (use with caution!)
npm run deploy:mainnets
```

### Advanced Deployment Options

```bash
# Deploy using the flexible deployment script
npm run deploy:network sepolia
npm run deploy:network polygon mainnet
```

## 🔍 Verification & Validation

### Contract Verification

```bash
# Verify contracts on block explorers
npm run verify:sepolia
npm run verify:mainnet
npm run verify:polygon
npm run verify:bsc
npm run verify:arbitrum
npm run verify:base
npm run verify:celo
```

### Deployment Validation

```bash
# Validate deployment on specific networks
npm run validate:sepolia
npm run validate:mainnet
```

## 📊 Network-Specific Features

### Cross-Chain Support

Each network deployment includes:
- **Stargate Router Integration**: For cross-chain fund transfers
- **Network-Specific Fee Structures**: Optimized for each blockchain's economics
- **Gas Optimization**: Network-specific gas limits and pricing
- **Block Time Adaptation**: Timeout periods adjusted for block times

### Security Configurations

- **Mainnets**: 7-day timelock for DAO operations
- **Testnets**: 2-day timelock for faster testing
- **Multi-sig Requirements**: 3-of-5 signatures required
- **Emergency Controls**: Pause functionality for security incidents

## 🧪 Testing Deployment

### Local Testing

```bash
# Test deployment on local Hardhat network
npm run compile
npx hardhat ignition deploy ignition/modules/PluriSwapNetworkDeployment.ts#PluriSwapSepoliaDeployment --network hardhat
```

### Testnet Deployment Flow

1. **Deploy to Testnet**:
   ```bash
   npm run deploy:sepolia
   ```

2. **Verify Contracts**:
   ```bash
   npm run verify:sepolia
   ```

3. **Validate Deployment**:
   ```bash
   npm run validate:sepolia
   ```

4. **Run Integration Tests**:
   ```bash
   npm run test:all
   ```

## 💰 Cost Estimation

### Estimated Deployment Costs

| Network | Estimated Cost | Currency |
|---------|----------------|----------|
| Ethereum Mainnet | ~0.5 ETH | ETH |
| Polygon Mainnet | ~50 MATIC | MATIC |
| BSC Mainnet | ~0.1 BNB | BNB |
| Arbitrum Mainnet | ~0.01 ETH | ETH |
| Base Mainnet | ~0.01 ETH | ETH |
| Celo Mainnet | ~5 CELO | CELO |

*Costs are estimates and may vary based on network congestion and gas prices.*

## 🔧 Advanced Configuration

### Custom Network Configuration

You can modify network-specific parameters in `config/deployment-config.ts`:

```typescript
// Example: Custom configuration for a specific network
polygon: {
  name: "polygon",
  displayName: "Polygon Mainnet",
  chainId: 137,
  isTestnet: false,
  // ... customize other parameters
  deploymentConfig: {
    escrowFeePercent: 150, // 1.5% custom fee
    disputeFeePercent: 75, // 0.75% custom dispute fee
    // ... other custom parameters
  }
}
```

### Multi-Account Deployment

For production deployments, use different accounts for different networks:

```bash
# Use network-specific private keys
export MAINNET_PRIVATE_KEY=0xPRODUCTION_KEY_1
export POLYGON_PRIVATE_KEY=0xPRODUCTION_KEY_2
export BSC_PRIVATE_KEY=0xPRODUCTION_KEY_3
```

## 🚨 Production Deployment Checklist

### Pre-Deployment
- [ ] Configure all required environment variables
- [ ] Fund deployment accounts with sufficient native tokens
- [ ] Test deployment on testnets first
- [ ] Verify all contract addresses and configurations
- [ ] Set up multi-sig wallet addresses
- [ ] Configure block explorer API keys

### During Deployment
- [ ] Monitor gas prices and network congestion
- [ ] Verify each contract deployment
- [ ] Test basic functionality on testnets
- [ ] Document all deployed contract addresses
- [ ] Set up monitoring and alerting

### Post-Deployment
- [ ] Verify contracts on block explorers
- [ ] Set up monitoring dashboards
- [ ] Configure emergency procedures
- [ ] Update frontend with new addresses
- [ ] Notify stakeholders of successful deployment

## 🆘 Troubleshooting

### Common Issues

1. **"Network not supported" error**
   - Check if the network is configured in `hardhat.config.ts`
   - Verify environment variables are set correctly

2. **"Insufficient funds" error**
   - Ensure deployment account has enough native tokens
   - Check gas price settings

3. **"Contract verification failed"**
   - Verify API keys are correct
   - Check if contracts are already verified
   - Wait a few minutes and retry

4. **"Timelock not met" error**
   - This is expected for DAO operations
   - Wait for the timelock period or use testnet for faster testing

### Getting Help

- Check the deployment logs for detailed error messages
- Verify network connectivity and RPC endpoints
- Ensure all required dependencies are installed
- Review the test suite for expected behavior

## 📈 Monitoring & Maintenance

### Post-Deployment Monitoring

1. **Contract Health**: Monitor contract balances and activity
2. **Gas Usage**: Track gas consumption patterns
3. **Error Rates**: Monitor failed transactions
4. **Network Performance**: Track block times and congestion

### Regular Maintenance

1. **Update Token Addresses**: Keep token configurations current
2. **Monitor Gas Prices**: Adjust fees based on network economics
3. **Security Updates**: Stay informed about security vulnerabilities
4. **Performance Optimization**: Monitor and optimize contract usage

## 🎯 Next Steps

After successful deployment:

1. **Frontend Integration**: Update frontend with deployed contract addresses
2. **User Documentation**: Create user guides for each supported network
3. **Community Communication**: Announce deployment to users and partners
4. **Bug Bounty Program**: Launch bug bounty for security testing
5. **Performance Monitoring**: Set up comprehensive monitoring systems

---

## 📞 Support

For deployment assistance or questions:
- Check the troubleshooting section above
- Review the comprehensive test suite
- Verify network configurations
- Ensure all prerequisites are met

**Happy deploying! 🚀**
