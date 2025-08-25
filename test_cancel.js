const { network } = require("hardhat");
const { parseEther } = require("viem");

async function main() {
  const { viem } = await network.connect();
  
  // Get signers
  const [deployer, signer1, signer2] = await viem.getWalletClients();
  
  const signerAddresses = [
    signer1.account.address,
    signer2.account.address,
    deployer.account.address,
    "0x1234567890123456789012345678901234567890",
    "0x0987654321098765432109876543210987654321"
  ];
  
  // Deploy DAO
  const dao = await viem.deployContract("PluriSwapDAO", [signerAddresses]);
  
  console.log("DAO deployed at:", dao.address);
  
  // Create a treasury transfer proposal (this should create transaction ID 1)
  await dao.write.proposeTreasuryTransfer([
    signer2.account.address,
    parseEther("1"),
    "0x0000000000000000000000000000000000000000",
    "Test transfer"
  ], { account: signer1.account });
  
  console.log("Transaction proposed");
  
  // Check transaction counter
  const counter = await dao.read.getCurrentTransactionId();
  console.log("Current transaction ID:", counter.toString());
  
  // Try to cancel transaction with ID 1
  try {
    await dao.write.cancelTransaction([1n], { account: signer1.account });
    console.log("✅ Successfully cancelled transaction");
  } catch (error) {
    console.log("❌ Failed to cancel transaction:", error.message);
  }
  
  // Verify transaction was cancelled
  try {
    const [txType, proposer, data, description, proposedAt, executedAt, status, approvalCount, isEmergency] = 
      await dao.read.getTransaction([1n]);
    console.log("Transaction status:", status); // Should be 2 (CANCELLED)
  } catch (error) {
    console.log("❌ Failed to get transaction:", error.message);
  }
}

main().catch(console.error);
