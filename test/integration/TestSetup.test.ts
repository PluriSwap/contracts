import { test } from "node:test";
import assert from "node:assert";
import { network } from "hardhat";

test("Test basic hardhat viem setup", async () => {
  const { viem } = await network.connect();
  
  const publicClient = await viem.getPublicClient();
  const blockNumber = await publicClient.getBlockNumber();
  
  assert(typeof blockNumber === 'bigint', 'Block number should be a bigint');
  console.log('Current block number:', blockNumber);
});
