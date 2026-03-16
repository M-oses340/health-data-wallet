/**
 * interact.ts — Full on-chain demo for the Health Data Monetization platform.
 *
 * Runs the complete consent lifecycle against a locally deployed Hardhat node:
 *   1. Connect to deployed contracts (reads deployed-addresses.json)
 *   2. Create a consent contract (researcher → patient)
 *   3. Patient signs the contract
 *   4. Researcher escrows funds
 *   5. Check escrow balance
 *   6. Release dividend to patient (PaymentRouter)
 *   7. Verify patient wallet balance increased
 *   8. Revoke consent and process refund
 *
 * Prerequisites:
 *   Terminal 1: npx hardhat node
 *   Terminal 2: npx hardhat run scripts/deploy.ts --network localhost
 *   Terminal 3: npx hardhat run scripts/interact.ts --network localhost
 */
import { ethers } from 'hardhat';
import * as fs from 'fs';
import * as path from 'path';

async function main() {
  // -------------------------------------------------------------------------
  // 1. Load deployed addresses
  // -------------------------------------------------------------------------
  const addressFile = path.join(__dirname, '..', 'deployed-addresses.json');
  if (!fs.existsSync(addressFile)) {
    throw new Error('deployed-addresses.json not found — run deploy.ts first');
  }
  const addresses = JSON.parse(fs.readFileSync(addressFile, 'utf8'));
  console.log('\n=== Deployed Addresses ===');
  console.log(`ConsentRegistry : ${addresses.ConsentRegistry}`);
  console.log(`DataEscrow      : ${addresses.DataEscrow}`);
  console.log(`PaymentRouter   : ${addresses.PaymentRouter}`);

  // -------------------------------------------------------------------------
  // 2. Connect signers and contracts
  // -------------------------------------------------------------------------
  const [deployer, patient, researcher] = await ethers.getSigners();
  console.log('\n=== Signers ===');
  console.log(`Deployer   : ${deployer.address}`);
  console.log(`Patient    : ${patient.address}`);
  console.log(`Researcher : ${researcher.address}`);

  const registry = await ethers.getContractAt('ConsentRegistry', addresses.ConsentRegistry);
  const escrow   = await ethers.getContractAt('DataEscrow',       addresses.DataEscrow);
  const router   = await ethers.getContractAt('PaymentRouter',    addresses.PaymentRouter);

  // -------------------------------------------------------------------------
  // 3. Create consent contract
  // -------------------------------------------------------------------------
  const contractId      = ethers.id('demo-contract-001');
  const dividendWei     = ethers.parseEther('0.1');
  const accessDuration  = 60 * 60 * 24; // 24 h in seconds
  const dataCategory    = 'cardiology';
  const permittedScope  = 'cardiology-research';
  const computationMethod = 0; // 0 = FEDERATED_LEARNING, 1 = ZKP

  console.log('\n=== Step 1: createContract ===');
  const createTx = await registry.connect(researcher).createContract(
    contractId,
    patient.address,
    dataCategory,
    permittedScope,
    accessDuration,
    dividendWei,
    computationMethod,
  );
  const createReceipt = await createTx.wait();
  console.log(`Tx hash : ${createReceipt!.hash}`);
  console.log(`Gas used: ${createReceipt!.gasUsed.toString()}`);

  // -------------------------------------------------------------------------
  // 4. Patient signs the contract
  // -------------------------------------------------------------------------
  console.log('\n=== Step 2: signContract ===');
  const signTx = await registry.connect(patient).signContract(contractId);
  const signReceipt = await signTx.wait();
  console.log(`Tx hash : ${signReceipt!.hash}`);

  const isActive = await registry.isConsentActive(contractId);
  console.log(`isConsentActive: ${isActive}`);   // expected: true

  // -------------------------------------------------------------------------
  // 5. Researcher escrows funds
  // -------------------------------------------------------------------------
  console.log('\n=== Step 3: escrowFunds ===');
  const patientBalanceBefore = await ethers.provider.getBalance(patient.address);
  console.log(`Patient balance before: ${ethers.formatEther(patientBalanceBefore)} ETH`);

  const escrowTx = await escrow.connect(researcher).escrowFunds(contractId, patient.address, dividendWei, {
    value: dividendWei,
  });
  const escrowReceipt = await escrowTx.wait();
  console.log(`Tx hash : ${escrowReceipt!.hash}`);

  const escrowBalance = await ethers.provider.getBalance(addresses.DataEscrow);
  console.log(`DataEscrow balance: ${ethers.formatEther(escrowBalance)} ETH`);  // expected: 0.1

  // -------------------------------------------------------------------------
  // 6. Release dividend via PaymentRouter
  // -------------------------------------------------------------------------
  console.log('\n=== Step 4: releaseDividend ===');
  const releaseTx = await router.connect(deployer).releaseDividend(contractId);
  const releaseReceipt = await releaseTx.wait();
  console.log(`Tx hash : ${releaseReceipt!.hash}`);

  // Parse DividendPaid event
  const iface = router.interface;
  for (const log of releaseReceipt!.logs) {
    try {
      const parsed = iface.parseLog(log);
      if (parsed?.name === 'DividendPaid') {
        console.log(`DividendPaid event:`);
        console.log(`  contractId : ${parsed.args.contractId}`);
        console.log(`  patient    : ${parsed.args.patientWallet}`);
        console.log(`  amount     : ${ethers.formatEther(parsed.args.amount)} ETH`);
        console.log(`  timestamp  : ${new Date(Number(parsed.args.timestamp) * 1000).toISOString()}`);
      }
    } catch {
      // not a router event
    }
  }

  // -------------------------------------------------------------------------
  // 7. Verify patient balance increased
  // -------------------------------------------------------------------------
  const patientBalanceAfter = await ethers.provider.getBalance(patient.address);
  const delta = patientBalanceAfter - patientBalanceBefore;
  console.log(`\nPatient balance after : ${ethers.formatEther(patientBalanceAfter)} ETH`);
  console.log(`Delta (net of gas)    : ${ethers.formatEther(delta)} ETH`);
  console.log(`Dividend received     : ${delta > 0n ? 'YES ✓' : 'NO ✗'}`);

  // -------------------------------------------------------------------------
  // 8. Revoke consent and process refund (second contract)
  // -------------------------------------------------------------------------
  console.log('\n=== Step 5: revokeConsent + processRevocationRefund ===');
  const contractId2     = ethers.id('demo-contract-002');

  await (await registry.connect(researcher).createContract(
    contractId2, patient.address, dataCategory, permittedScope, accessDuration, dividendWei, computationMethod,
  )).wait();
  await (await registry.connect(patient).signContract(contractId2)).wait();
  await (await escrow.connect(researcher).escrowFunds(contractId2, patient.address, dividendWei, {
    value: dividendWei,
  })).wait();

  const researcherBalanceBefore = await ethers.provider.getBalance(researcher.address);

  const revokeTx = await registry.connect(patient).revokeConsent(contractId2);
  await revokeTx.wait();
  console.log(`Consent revoked for contract: ${contractId2}`);

  const refundTx = await router.connect(deployer).processRevocationRefund(contractId2);
  const refundReceipt = await refundTx.wait();
  console.log(`Refund tx hash: ${refundReceipt!.hash}`);

  const researcherBalanceAfter = await ethers.provider.getBalance(researcher.address);
  const refundDelta = researcherBalanceAfter - researcherBalanceBefore;
  console.log(`Researcher refund delta: ${ethers.formatEther(refundDelta)} ETH`);
  console.log(`Refund received: ${refundDelta > 0n ? 'YES ✓' : 'NO ✗'}`);

  console.log('\n=== Demo complete ===\n');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
