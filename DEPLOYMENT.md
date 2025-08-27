# PluriSwap Sepolia Testnet Deployment Guide

This guide will walk you through deploying the PluriSwap smart contract system to Ethereum Sepolia testnet.

## 🛠️ Prerequisites

1. **Node.js** v18+ installed
2. **Testnet ETH** on Sepolia (get from faucets)
3. **RPC Provider** account (Alchemy, Infura, or Ankr)
4. **Etherscan API Key** (optional, for verification)

## 📋 Setup Steps

### 1. Get Testnet ETH

You'll need ~0.5 ETH on Sepolia for deployment. Get it from faucets:
- [Alchemy Sepolia Faucet](https://sepoliafaucet.com/)
- [Infura Sepolia Faucet](https://www.infura.io/faucet/sepolia)
- [Chainlink Sepolia Faucet](https://faucets.chain.link/sepolia)

### 2. Get an RPC Provider

Choose one and get your URL:

**Alchemy (Recommended):**
1. Go to [alchemy.com](https://alchemy.com)
2. Create account and app
3. Get URL: `https://eth-sepolia.g.alchemy.com/v2/YOUR-API-KEY`

**Infura:**
1. Go to [infura.io](https://infura.io)
2. Create project
3. Get URL: `https://sepolia.infura.io/v3/YOUR-PROJECT-ID`

**Ankr (Free):**
- Use: `https://rpc.ankr.com/eth_sepolia`

### 3. Set Environment Variables

Create your environment setup based on `sepolia-config.example`:

```bash
# Option A: Export directly in terminal
export SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR-API-KEY
export SEPOLIA_PRIVATE_KEY=0xYOUR_PRIVATE_KEY_HERE
export ETHERSCAN_API_KEY=YOUR_ETHERSCAN_KEY  # Optional

# Option B: Source the config file (after updating it)
source sepolia-config.example
```

⚠️ **SECURITY WARNING:**
- Never commit your private key to git
- Use a dedicated testnet wallet
- Keep your private key secure

### 4. Get Etherscan API Key (Optional)

For contract verification:
1. Go to [etherscan.io/apis](https://etherscan.io/apis)
2. Register and get API key
3. Add to environment: `export ETHERSCAN_API_KEY=your_key`

## 🚀 Deployment Commands

### Compile Contracts
```bash
npm run compile
```

### Deploy to Sepolia
```bash
npm run deploy:sepolia
```

This will deploy all PluriSwap contracts in the correct order:
1. **ReputationOracle** - User reputation system
2. **ReputationIngestion** - Reputation event processing  
3. **MockStargateRouter** - Cross-chain bridge mock
4. **ArbitrationProxy** - Dispute resolution system
5. **EscrowContract** - Main P2P escrow functionality
6. **PluriSwapDAO** - Governance multisig
7. **AbiEncodingTest** - Testing helper

### Verify Contracts on Etherscan
```bash
npm run verify:sepolia
```

## 📊 Expected Deployment Output

```
🚀 Starting PluriSwap System Deployment...
📋 Deployer account: 0xYourAddress...

📊 Deploying ReputationOracle...
✅ ReputationOracle deployed to: 0x1234...

📥 Deploying ReputationIngestion...
✅ ReputationIngestion deployed to: 0x5678...

⚖️ Deploying ArbitrationProxy...
✅ ArbitrationProxy deployed to: 0x9abc...

💰 Deploying EscrowContract...
✅ EscrowContract deployed to: 0xdef0...

🏛️ Deploying PluriSwapDAO...
✅ PluriSwapDAO deployed to: 0x2468...

🔗 Setting up contract connections...
✅ EscrowContract ↔ ArbitrationProxy connected
✅ ArbitrationProxy authorized EscrowContract  
✅ Initial support agent added

✅ PluriSwap deployment complete!
```

## 🎛️ Configuration Details

### EscrowContract Configuration
- **Base Fee:** 2.5% (250 basis points)
- **Min Fee:** 0.001 ETH
- **Max Fee:** 1.0 ETH  
- **Dispute Fee:** 1% (100 basis points)
- **Min Timeout:** 1 hour
- **Max Timeout:** 30 days

### ArbitrationProxy Configuration  
- **Base Fee:** 0.01 ETH
- **Fee Recipient:** Deployer address
- **Initially:** Not paused

### DAO Configuration (Testnet)
- **Signers:** 5 (all deployer for testnet)
- **Required Signatures:** 3 out of 5
- **Timelock:** 2 days

## 🧪 Testing Deployment

### Connect to Sepolia Console
```bash
npm run console:sepolia
```

### Run Tests Against Deployed Contracts
```bash
# Update test files with deployed addresses if needed
npm run test:all
```

## 🔍 Contract Addresses

After deployment, save these addresses:

```typescript
const SEPOLIA_ADDRESSES = {
  EscrowContract: "0x...",
  ArbitrationProxy: "0x...", 
  ReputationOracle: "0x...",
  ReputationIngestion: "0x...",
  PluriSwapDAO: "0x...",
  MockStargateRouter: "0x...",
  AbiEncodingTest: "0x...",
}
```

## 🐛 Troubleshooting

### Common Issues:

**"Insufficient funds"**
- Ensure you have enough Sepolia ETH
- Gas costs ~0.3-0.5 ETH for full deployment

**"Invalid API key"**  
- Check your RPC URL is correct
- Verify environment variables are set

**"Nonce too high/low"**
- Wait a few minutes and retry
- Check if transactions are stuck

**"Deployment failed"**
- Check gas limits in hardhat.config.ts
- Verify contract dependencies

### Getting Help:
1. Check transaction hashes on [Sepolia Etherscan](https://sepolia.etherscan.io)
2. Review contract addresses and configurations
3. Verify environment variables are correctly set

## 🎉 Success!

Once deployed, your PluriSwap system will be live on Sepolia testnet with:
- ✅ Full escrow functionality
- ✅ Dispute resolution system  
- ✅ Reputation tracking
- ✅ DAO governance
- ✅ Security features

You can now build frontends, integrate APIs, or test the full P2P escrow workflow!

## 🚨 Security Checklist

Before mainnet deployment:
- [ ] Use real multisig signers for DAO
- [ ] Review all configuration parameters
- [ ] Audit smart contracts
- [ ] Test extensively on testnet
- [ ] Prepare incident response plan
- [ ] Set up monitoring and alerts
