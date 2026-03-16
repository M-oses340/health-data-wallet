/**
 * Smart contract tests — ConsentRegistry, DataEscrow, PaymentRouter.

 * Requirements: 3.1, 3.3, 3.5, 3.6, 5.1, 5.2, 5.3, 5.4, 5.6
 */
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { time } from '@nomicfoundation/hardhat-network-helpers';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function randomId(): string {
  return ethers.encodeBytes32String(Math.random().toString(36).slice(2, 12));
}

async function deployAll() {
  const [deployer, patient, researcher, other] = await ethers.getSigners();

  const Registry = await ethers.getContractFactory('ConsentRegistry');
  const registry = await Registry.deploy();

  // Deploy escrow with deployer as temporary router, then update after router is known
  const Escrow = await ethers.getContractFactory('DataEscrow');
  const escrow = await Escrow.deploy(deployer.address);

  const Router = await ethers.getContractFactory('PaymentRouter');
  const router = await Router.deploy(await registry.getAddress(), await escrow.getAddress());

  // Point escrow at the real router
  await escrow.setRouter(await router.getAddress());

  return { registry, escrow, router, deployer, patient, researcher, other };
}

const ONE_DAY = 86400n;
const DIVIDEND = ethers.parseEther('0.1');

// ---------------------------------------------------------------------------
// ConsentRegistry
// ---------------------------------------------------------------------------

describe('ConsentRegistry', () => {
  it('createContract stores a PENDING_SIGNATURE record', async () => {
    const { registry, patient, researcher } = await deployAll();
    const id = randomId();
    await registry.connect(researcher).createContract(
      id, patient.address, 'cardiology', 'research-only', ONE_DAY, DIVIDEND, 0,
    );
    const rec = await registry.getRecord(id);
    expect(rec.status).to.equal(0); // PENDING_SIGNATURE
    expect(rec.patientWallet).to.equal(patient.address);
  });

  it('createContract emits ContractCreated', async () => {
    const { registry, patient, researcher } = await deployAll();
    const id = randomId();
    await expect(
      registry.connect(researcher).createContract(
        id, patient.address, 'cardiology', 'research-only', ONE_DAY, DIVIDEND, 0,
      ),
    ).to.emit(registry, 'ContractCreated').withArgs(id, patient.address, researcher.address, DIVIDEND);
  });

  it('createContract reverts on duplicate contractId', async () => {
    const { registry, patient, researcher } = await deployAll();
    const id = randomId();
    await registry.connect(researcher).createContract(
      id, patient.address, 'cardiology', 'research-only', ONE_DAY, DIVIDEND, 0,
    );
    await expect(
      registry.connect(researcher).createContract(
        id, patient.address, 'cardiology', 'research-only', ONE_DAY, DIVIDEND, 0,
      ),
    ).to.be.revertedWithCustomError(registry, 'ContractAlreadyExists');
  });

  it('signContract activates the record and emits ContractSigned', async () => {
    const { registry, patient, researcher } = await deployAll();
    const id = randomId();
    await registry.connect(researcher).createContract(
      id, patient.address, 'cardiology', 'research-only', ONE_DAY, DIVIDEND, 0,
    );
    await expect(registry.connect(patient).signContract(id))
      .to.emit(registry, 'ContractSigned');
    const rec = await registry.getRecord(id);
    expect(rec.status).to.equal(1); // ACTIVE
  });

  it('signContract reverts if caller is not the patient', async () => {
    const { registry, patient, researcher, other } = await deployAll();
    const id = randomId();
    await registry.connect(researcher).createContract(
      id, patient.address, 'cardiology', 'research-only', ONE_DAY, DIVIDEND, 0,
    );
    await expect(registry.connect(other).signContract(id))
      .to.be.revertedWithCustomError(registry, 'NotPatient');
  });

  it('revokeConsent transitions to REVOKED and emits ConsentRevoked', async () => {
    const { registry, patient, researcher } = await deployAll();
    const id = randomId();
    await registry.connect(researcher).createContract(
      id, patient.address, 'cardiology', 'research-only', ONE_DAY, DIVIDEND, 0,
    );
    await registry.connect(patient).signContract(id);
    await expect(registry.connect(patient).revokeConsent(id))
      .to.emit(registry, 'ConsentRevoked');
    const rec = await registry.getRecord(id);
    expect(rec.status).to.equal(3); // REVOKED
  });

  it('revokeConsent reverts if caller is not the patient', async () => {
    const { registry, patient, researcher, other } = await deployAll();
    const id = randomId();
    await registry.connect(researcher).createContract(
      id, patient.address, 'cardiology', 'research-only', ONE_DAY, DIVIDEND, 0,
    );
    await registry.connect(patient).signContract(id);
    await expect(registry.connect(other).revokeConsent(id))
      .to.be.revertedWithCustomError(registry, 'NotPatient');
  });

  it('isConsentActive returns true for active non-expired contract', async () => {
    const { registry, patient, researcher } = await deployAll();
    const id = randomId();
    await registry.connect(researcher).createContract(
      id, patient.address, 'cardiology', 'research-only', ONE_DAY, DIVIDEND, 0,
    );
    await registry.connect(patient).signContract(id);
    expect(await registry.isConsentActive(id)).to.be.true;
  });

  it('isConsentActive returns false after expiry time passes', async () => {
    const { registry, patient, researcher } = await deployAll();
    const id = randomId();
    await registry.connect(researcher).createContract(
      id, patient.address, 'cardiology', 'research-only', ONE_DAY, DIVIDEND, 0,
    );
    await registry.connect(patient).signContract(id);
    await time.increase(Number(ONE_DAY) + 1);
    expect(await registry.isConsentActive(id)).to.be.false;
  });

  it('isConsentActive returns false for unknown contractId', async () => {
    const { registry } = await deployAll();
    expect(await registry.isConsentActive(randomId())).to.be.false;
  });
});

// ---------------------------------------------------------------------------
// DataEscrow
// ---------------------------------------------------------------------------

describe('DataEscrow', () => {
  it('escrowFunds stores the record', async () => {
    const { escrow, router, patient, researcher } = await deployAll();
    const id = randomId();
    await escrow.connect(researcher).escrowFunds(id, patient.address, DIVIDEND, { value: DIVIDEND });
    const rec = await escrow.getEscrow(id);
    expect(rec.amount).to.equal(DIVIDEND);
    expect(rec.researcherWallet).to.equal(researcher.address);
  });

  it('escrowFunds emits FundsEscrowed', async () => {
    const { escrow, patient, researcher } = await deployAll();
    const id = randomId();
    await expect(
      escrow.connect(researcher).escrowFunds(id, patient.address, DIVIDEND, { value: DIVIDEND }),
    ).to.emit(escrow, 'FundsEscrowed').withArgs(id, researcher.address, DIVIDEND);
  });

  it('escrowFunds reverts when sent value is less than dividend', async () => {
    const { escrow, patient, researcher } = await deployAll();
    const id = randomId();
    await expect(
      escrow.connect(researcher).escrowFunds(id, patient.address, DIVIDEND, {
        value: DIVIDEND - 1n,
      }),
    ).to.be.revertedWithCustomError(escrow, 'InsufficientEscrow');
  });

  it('releaseFunds transfers dividend to patient', async () => {
    const { registry, escrow, router, patient, researcher } = await deployAll();
    const id = randomId();

    // Set up active consent
    await registry.connect(researcher).createContract(
      id, patient.address, 'cardiology', 'research-only', ONE_DAY, DIVIDEND, 0,
    );
    await registry.connect(patient).signContract(id);
    await escrow.connect(researcher).escrowFunds(id, patient.address, DIVIDEND, { value: DIVIDEND });

    const before = await ethers.provider.getBalance(patient.address);
    await router.releaseDividend(id);
    const after = await ethers.provider.getBalance(patient.address);
    expect(after - before).to.equal(DIVIDEND);
  });

  it('refundFunds returns escrowed amount to researcher on revocation', async () => {
    const { registry, escrow, router, patient, researcher } = await deployAll();
    const id = randomId();

    await registry.connect(researcher).createContract(
      id, patient.address, 'cardiology', 'research-only', ONE_DAY, DIVIDEND, 0,
    );
    await registry.connect(patient).signContract(id);
    await escrow.connect(researcher).escrowFunds(id, patient.address, DIVIDEND, { value: DIVIDEND });
    await registry.connect(patient).revokeConsent(id);

    const before = await ethers.provider.getBalance(researcher.address);
    await router.processRevocationRefund(id);
    const after = await ethers.provider.getBalance(researcher.address);
    expect(after - before).to.be.closeTo(DIVIDEND, ethers.parseEther('0.001'));
  });
});

// ---------------------------------------------------------------------------
// PaymentRouter
// ---------------------------------------------------------------------------

describe('PaymentRouter', () => {
  it('releaseDividend emits DividendPaid', async () => {
    const { registry, escrow, router, patient, researcher } = await deployAll();
    const id = randomId();

    await registry.connect(researcher).createContract(
      id, patient.address, 'cardiology', 'research-only', ONE_DAY, DIVIDEND, 0,
    );
    await registry.connect(patient).signContract(id);
    await escrow.connect(researcher).escrowFunds(id, patient.address, DIVIDEND, { value: DIVIDEND });

    await expect(router.releaseDividend(id))
      .to.emit(router, 'DividendPaid')
      .withArgs(id, patient.address, DIVIDEND, await time.latest().then(t => t + 1));
  });

  it('releaseDividend reverts when consent is not active', async () => {
    const { registry, escrow, router, patient, researcher } = await deployAll();
    const id = randomId();

    await registry.connect(researcher).createContract(
      id, patient.address, 'cardiology', 'research-only', ONE_DAY, DIVIDEND, 0,
    );
    // Not signed — still PENDING_SIGNATURE
    await expect(router.releaseDividend(id))
      .to.be.revertedWithCustomError(router, 'ConsentNotActive');
  });

  it('releaseDividend reverts after consent is revoked', async () => {
    const { registry, escrow, router, patient, researcher } = await deployAll();
    const id = randomId();

    await registry.connect(researcher).createContract(
      id, patient.address, 'cardiology', 'research-only', ONE_DAY, DIVIDEND, 0,
    );
    await registry.connect(patient).signContract(id);
    await registry.connect(patient).revokeConsent(id);

    await expect(router.releaseDividend(id))
      .to.be.revertedWithCustomError(router, 'ConsentNotActive');
  });
});
