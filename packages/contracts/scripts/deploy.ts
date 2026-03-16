/**
 * Deployment script for the Health Data Monetization smart contracts.
 *
 * Deploy order:
 *   1. ConsentRegistry  (no dependencies)
 *   2. DataEscrow       (needs router address — deploy with deployer as placeholder, update after)
 *   3. PaymentRouter    (needs registry + escrow addresses)
 *   4. DataEscrow.setRouter(paymentRouter.address)
 *
 * Run against local Hardhat node:
 *   npx hardhat node                          (terminal 1)
 *   npx hardhat run scripts/deploy.ts --network localhost   (terminal 2)
 */
import { ethers } from 'hardhat';

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log(`\nDeploying contracts with account: ${deployer.address}`);
  console.log(`Account balance: ${ethers.formatEther(await ethers.provider.getBalance(deployer.address))} ETH\n`);

  // 1. ConsentRegistry
  const Registry = await ethers.getContractFactory('ConsentRegistry');
  const registry = await Registry.deploy();
  await registry.waitForDeployment();
  const registryAddr = await registry.getAddress();
  console.log(`ConsentRegistry deployed to: ${registryAddr}`);

  // 2. DataEscrow (placeholder router = deployer, updated in step 4)
  const Escrow = await ethers.getContractFactory('DataEscrow');
  const escrow = await Escrow.deploy(deployer.address);
  await escrow.waitForDeployment();
  const escrowAddr = await escrow.getAddress();
  console.log(`DataEscrow deployed to:      ${escrowAddr}`);

  // 3. PaymentRouter
  const Router = await ethers.getContractFactory('PaymentRouter');
  const router = await Router.deploy(registryAddr, escrowAddr);
  await router.waitForDeployment();
  const routerAddr = await router.getAddress();
  console.log(`PaymentRouter deployed to:   ${routerAddr}`);

  // 4. Wire escrow → router
  const tx = await escrow.setRouter(routerAddr);
  await tx.wait();
  console.log(`DataEscrow router updated to: ${routerAddr}`);

  console.log('\n--- Deployment summary ---');
  console.log(`ConsentRegistry : ${registryAddr}`);
  console.log(`DataEscrow      : ${escrowAddr}`);
  console.log(`PaymentRouter   : ${routerAddr}`);
  console.log('--------------------------\n');

  // Write addresses to a JSON file for the API to consume
  const fs = await import('fs');
  const addresses = { ConsentRegistry: registryAddr, DataEscrow: escrowAddr, PaymentRouter: routerAddr };
  fs.writeFileSync('deployed-addresses.json', JSON.stringify(addresses, null, 2));
  console.log('Addresses written to deployed-addresses.json');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
