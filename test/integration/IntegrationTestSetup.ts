import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import assert from "node:assert";
import { network } from "hardhat";
import { getAddress, parseEther, Hex, encodePacked, keccak256 } from "viem";

// Contract artifacts and types
export interface TestContracts {
  dao: any;
  reputationOracle: any;
  reputationEvents: any;
  arbitrationProxy: any;
  escrowContract: any;
  mockStargateRouter: any;
}

export interface TestAccounts {
  deployer: any;
  daoSigner1: any;
  daoSigner2: any;
  daoSigner3: any;
  daoSigner4: any;
  daoSigner5: any;
  buyer: any;
  seller: any;
  supportAgent: any;
  user1: any;
  user2: any;
  unauthorized: any;
}

export interface EscrowAgreement {
  holder: `0x${string}`;
  provider: `0x${string}`;
  amount: bigint;
  fundedTimeout: bigint;
  proofTimeout: bigint;
  nonce: bigint;
  deadline: bigint;
  dstChainId: number;
  dstRecipient: `0x${string}`;
  dstAdapterParams: Hex;
}

export interface TestConfiguration {
  escrowConfig: {
    baseFee: bigint;
    reputationThreshold: number;
    feeReduction: number;
    maxFeeReduction: number;
    disputeWindow: bigint;
    platformFeeRecipient: `0x${string}`;
  };
  arbitrationConfig: {
    baseFee: bigint;
    feePerByte: bigint;
    maxEvidence: number;
    resolutionWindow: bigint;
  };
}

export async function deployIntegrationFixture(): Promise<{
  contracts: TestContracts;
  accounts: TestAccounts;
  config: TestConfiguration;
}> {
  const { viem } = await network.connect();
  const publicClient = await viem.getPublicClient();
  const walletClient = await viem.getWalletClient();

  // Get test accounts
  const [
    deployer,
    daoSigner1,
    daoSigner2,
    daoSigner3,
    daoSigner4,
    daoSigner5,
    buyer,
    seller,
    supportAgent,
    user1,
    user2,
    unauthorized,
  ] = await viem.getWalletClients();

  const accounts: TestAccounts = {
    deployer,
    daoSigner1,
    daoSigner2,
    daoSigner3,
    daoSigner4,
    daoSigner5,
    buyer,
    seller,
    supportAgent,
    user1,
    user2,
    unauthorized,
  };

  // 1. Deploy DAO with 5 signers
  const daoSigners = [
    daoSigner1.account.address,
    daoSigner2.account.address,
    daoSigner3.account.address,
    daoSigner4.account.address,
    daoSigner5.account.address,
  ];

  const dao = await viem.deployContract("PluriSwapDAO", [daoSigners]);

  // 2. Deploy ReputationOracle with DAO
  const reputationOracle = await viem.deployContract("ReputationOracle", [dao.address]);

  // 3. Deploy ReputationIngestion (Events) with DAO
  const reputationEvents = await viem.deployContract("ReputationIngestion", [dao.address]);

  // 4. Deploy MockStargateRouter
  const mockStargateRouter = await viem.deployContract("MockStargateRouter", []);

  // 5. Deploy ArbitrationProxy with DAO
  const arbitrationConfig = {
    baseFee: parseEther("0.01"),
    feePerByte: parseEther("0.000001"),
    maxEvidence: 10,
    resolutionWindow: BigInt(7 * 24 * 3600), // 7 days
  };

  const arbitrationProxy = await viem.deployContract("ArbitrationProxy", [
    dao.address,
    arbitrationConfig.baseFee,
    arbitrationConfig.feePerByte,
    arbitrationConfig.maxEvidence,
    arbitrationConfig.resolutionWindow,
  ]);

  // 6. Deploy EscrowContract with all dependencies
  const escrowConfig = {
    baseFee: parseEther("0.005"), // 0.5%
    reputationThreshold: 500,
    feeReduction: 10, // 10%
    maxFeeReduction: 50, // 50% max reduction
    disputeWindow: BigInt(3 * 24 * 3600), // 3 days
    platformFeeRecipient: dao.address,
  };

  const escrowContract = await viem.deployContract("EscrowContract", [
    dao.address,
    reputationOracle.address,
    reputationEvents.address,
    mockStargateRouter.address,
    escrowConfig.baseFee,
    escrowConfig.reputationThreshold,
    escrowConfig.feeReduction,
    escrowConfig.maxFeeReduction,
    escrowConfig.disputeWindow,
    escrowConfig.platformFeeRecipient,
  ]);

  // 7. Configure contracts
  // Add support agent to arbitration proxy (via DAO)
  await dao.write.submitTransaction([
    6, // ARBITRATION_ADD_SUPPORT_AGENT
    arbitrationProxy.address,
    0n,
    encodePacked(["address", "string"], [supportAgent.account.address, "Test Support Agent"]),
  ], { account: daoSigner1.account });

  // Confirm the transaction with other signers
  await dao.write.confirmTransaction([1n], { account: daoSigner2.account });
  await dao.write.confirmTransaction([1n], { account: daoSigner3.account });

  // Execute the transaction
  await dao.write.executeTransaction([1n], { account: daoSigner1.account });

  // Authorize escrow contract in arbitration proxy
  await dao.write.submitTransaction([
    9, // ARBITRATION_ADD_AUTHORIZED_ESCROW
    arbitrationProxy.address,
    0n,
    encodePacked(["address"], [escrowContract.address]),
  ], { account: daoSigner1.account });

  await dao.write.confirmTransaction([2n], { account: daoSigner2.account });
  await dao.write.confirmTransaction([2n], { account: daoSigner3.account });
  await dao.write.executeTransaction([2n], { account: daoSigner1.account });

  // Set arbitration proxy in escrow contract
  await dao.write.submitTransaction([
    7, // ESCROW_SET_ARBITRATION_PROXY
    escrowContract.address,
    0n,
    encodePacked(["address"], [arbitrationProxy.address]),
  ], { account: daoSigner1.account });

  await dao.write.confirmTransaction([3n], { account: daoSigner2.account });
  await dao.write.confirmTransaction([3n], { account: daoSigner3.account });
  await dao.write.executeTransaction([3n], { account: daoSigner1.account });

  // Add trusted party to reputation oracle
  await dao.write.submitTransaction([
    1, // ORACLE_ADD_TRUSTED_PARTY
    reputationOracle.address,
    0n,
    encodePacked(["address"], [deployer.account.address]),
  ], { account: daoSigner1.account });

  await dao.write.confirmTransaction([4n], { account: daoSigner2.account });
  await dao.write.confirmTransaction([4n], { account: daoSigner3.account });
  await dao.write.executeTransaction([4n], { account: daoSigner1.account });

  const contracts: TestContracts = {
    dao,
    reputationOracle,
    reputationEvents,
    arbitrationProxy,
    escrowContract,
    mockStargateRouter,
  };

  const config: TestConfiguration = {
    escrowConfig,
    arbitrationConfig,
  };

  return { contracts, accounts, config };
}

export function createEscrowAgreement(
  holder: `0x${string}`,
  provider: `0x${string}`,
  amount: bigint = parseEther("1"),
  dstChainId: number = 0,
  dstRecipient?: `0x${string}`
): EscrowAgreement {
  return {
    holder,
    provider,
    amount,
    fundedTimeout: BigInt(24 * 3600), // 24 hours
    proofTimeout: BigInt(48 * 3600), // 48 hours
    nonce: BigInt(Date.now()),
    deadline: BigInt(Math.floor(Date.now() / 1000) + 3600), // 1 hour from now
    dstChainId,
    dstRecipient: dstRecipient || holder,
    dstAdapterParams: "0x" as Hex,
  };
}

export async function signEscrowAgreement(
  agreement: EscrowAgreement,
  walletClient: any,
  contractAddress: `0x${string}`
): Promise<Hex> {
  const domain = {
    name: "EscrowContract",
    version: "1",
    chainId: await walletClient.getChainId(),
    verifyingContract: contractAddress,
  };

  const types = {
    EscrowAgreement: [
      { name: "holder", type: "address" },
      { name: "provider", type: "address" },
      { name: "amount", type: "uint256" },
      { name: "fundedTimeout", type: "uint256" },
      { name: "proofTimeout", type: "uint256" },
      { name: "nonce", type: "uint256" },
      { name: "deadline", type: "uint256" },
      { name: "dstChainId", type: "uint16" },
      { name: "dstRecipient", type: "address" },
      { name: "dstAdapterParams", type: "bytes" },
    ],
  };

  return await walletClient.signTypedData({
    account: walletClient.account,
    domain,
    types,
    primaryType: "EscrowAgreement",
    message: agreement,
  });
}

export async function signCancellation(
  escrowId: bigint,
  walletClient: any,
  contractAddress: `0x${string}`,
  nonce: bigint = BigInt(Date.now())
): Promise<{ signature: Hex; nonce: bigint; deadline: bigint }> {
  const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);

  const domain = {
    name: "EscrowContract",
    version: "1",
    chainId: await walletClient.getChainId(),
    verifyingContract: contractAddress,
  };

  const types = {
    CancellationAuthorization: [
      { name: "escrowId", type: "uint256" },
      { name: "nonce", type: "uint256" },
      { name: "deadline", type: "uint256" },
    ],
  };

  const signature = await walletClient.signTypedData({
    account: walletClient.account,
    domain,
    types,
    primaryType: "CancellationAuthorization",
    message: { escrowId, nonce, deadline },
  });

  return { signature, nonce, deadline };
}

export async function loadReputation(
  reputationOracle: any,
  walletClient: any,
  walletAddress: `0x${string}`,
  score: number = 500,
  transactionCounts = {
    started: 10,
    completed: 8,
    cancelled: 1,
    disputed: 1,
    disputesWon: 1,
    disputesLost: 0,
  },
  volumes = {
    started: parseEther("10"),
    completed: parseEther("8"),
  }
) {
  await reputationOracle.write.loadWalletScore([
    walletAddress,
    transactionCounts.started,
    transactionCounts.completed,
    transactionCounts.cancelled,
    transactionCounts.disputed,
    transactionCounts.disputesWon,
    transactionCounts.disputesLost,
    volumes.started,
    volumes.completed,
    score,
    true, // isActive
  ], { account: walletClient.account });
}

export function expectEscrowState(actualState: number, expectedState: number) {
  const stateNames = [
    "FUNDED",
    "OFFCHAIN_PROOF_SENT", 
    "COMPLETE",
    "CLOSED",
    "HOLDER_DISPUTED",
    "PROVIDER_DISPUTED"
  ];
  
  assert.strictEqual(
    actualState,
    expectedState,
    `Expected escrow state to be ${stateNames[expectedState]} (${expectedState}) but got ${stateNames[actualState]} (${actualState})`
  );
}

export async function increaseTime(seconds: number) {
  const { time } = await import("@nomicfoundation/hardhat-network-helpers");
  await time.increase(seconds);
}

export async function mineBlock() {
  const { mine } = await import("@nomicfoundation/hardhat-network-helpers");
  await mine();
}
