/**
 * Unit tests for PlatformOrchestrator.
 * Requirements: 1.4, 2.1, 3.1, 3.5, 3.6, 4.1, 5.1, 5.6, 6.1
 */
import { PlatformOrchestrator, IOnChainConsentManager, IOnChainPaymentRouter, IAnonymizerAdapter } from './PlatformOrchestrator';
import { WalletService } from '../wallet/WalletService';
import { PatientProfileRepository } from '../patient/PatientProfileRepository';
import { DataVaultService } from '../vault/DataVaultService';
import { MarketplaceService } from '../marketplace/MarketplaceService';
import { ComputationEngine, IConsentRegistry, IPaymentRouter } from '../computation/ComputationEngine';
import { AuditTrailService } from '../audit/AuditTrailService';
import { ComputationRequest } from '@health-data/sdk';
import { db } from '../db';

// ---------------------------------------------------------------------------
// Stubs
// ---------------------------------------------------------------------------

function makeConsentManager(activeIds: string[] = [], expiresAt = 9999999999): IOnChainConsentManager {
  return {
    createContract: async () => {},
    signContract:   async () => {},
    revokeConsent:  async () => {},
    expireContract: async () => {},
    getExpiresAt:   async () => expiresAt,
    getActiveContractIds: async () => activeIds,
  };
}

function makePaymentRouter(): IOnChainPaymentRouter & { refunds: string[] } {
  const refunds: string[] = [];
  return {
    refunds,
    processRevocationRefund: async (id) => { refunds.push(id); return '0xrefund'; },
  };
}

function makeAnonymizer(success = true, score = 85): IAnonymizerAdapter {
  return {
    deidentify: async (data, did, type, threshold) => ({
      success,
      qualityScore: score,
      anonymizedCid: 'anon-cid-123',
      rejectionReason: success ? undefined : 'Score too low',
    }),
  };
}

function makeComputationRegistry(active = true, method = 0): IConsentRegistry {
  return {
    isConsentActive: async () => active,
    getComputationMethod: async () => method,
  };
}

function makeComputationPaymentRouter(): IPaymentRouter {
  return { releaseDividend: async () => '0xpayment' };
}

function makeOrchestrator(overrides: Partial<{
  anonymizer: IAnonymizerAdapter;
  consentManager: IOnChainConsentManager;
  paymentRouter: IOnChainPaymentRouter;
  computationActive: boolean;
}> = {}) {
  const audit    = new AuditTrailService();
  const repo     = new PatientProfileRepository();
  const vault    = new DataVaultService();
  const market   = new MarketplaceService();
  const engine   = new ComputationEngine(
    makeComputationRegistry(overrides.computationActive ?? true),
    makeComputationPaymentRouter(),
  );
  const orch = new PlatformOrchestrator(
    new WalletService(),
    repo,
    vault,
    overrides.anonymizer ?? makeAnonymizer(),
    market,
    engine,
    audit,
    overrides.consentManager ?? makeConsentManager(),
    overrides.paymentRouter  ?? makePaymentRouter(),
  );
  return { orch, audit, repo, vault, market };
}

const validRequest: ComputationRequest = {
  researcherDID: 'did:ethr:0xResearcher',
  dataCategory: 'cardiology',
  computationMethod: 'FEDERATED_LEARNING',
  permittedScope: 'cardiology-research',
  accessDurationSeconds: 86400,
  dataDividendWei: BigInt('100000000000000000'),
};

beforeEach(() => {
  db.prepare('DELETE FROM audit_trail').run();
  db.prepare('DELETE FROM patient_profiles').run();
  db.prepare('DELETE FROM marketplace_listings').run();
  db.prepare('DELETE FROM vault_records').run();
});

// ---------------------------------------------------------------------------
// Flow A: Registration
// ---------------------------------------------------------------------------

describe('PlatformOrchestrator — registration', () => {

  it('registerPatient returns a valid DID', () => {
    const { orch } = makeOrchestrator();
    const result = orch.registerPatient();
    expect(result.did).toMatch(/^did:ethr:0x/);
  });

  it('registerPatient stores the profile in the repository', () => {
    const { orch, repo } = makeOrchestrator();
    const result = orch.registerPatient();
    expect(repo.exists(result.did)).toBe(true);
  });

  it('two registrations produce unique DIDs', () => {
    const { orch } = makeOrchestrator();
    const r1 = orch.registerPatient();
    const r2 = orch.registerPatient();
    expect(r1.did).not.toBe(r2.did);
  });

  it('registration writes an audit entry', () => {
    const { orch, audit } = makeOrchestrator();
    const result = orch.registerPatient();
    expect(audit.getAuditTrail(result.did)).toHaveLength(1);
  });
});

// ---------------------------------------------------------------------------
// Flow A: Upload and list
// ---------------------------------------------------------------------------

describe('PlatformOrchestrator — uploadAndList', () => {

  it('returns a CID and listingId on success', async () => {
    const { orch } = makeOrchestrator();
    const { did } = orch.registerPatient();
    const result = await orch.uploadAndList(did, Buffer.from('data'), 'EHR', 'cardiology');
    expect(result.cid).toBeTruthy();
    expect(result.listingId).toBeTruthy();
  });

  it('stores the data reference in the patient profile', async () => {
    const { orch, repo } = makeOrchestrator();
    const { did } = orch.registerPatient();
    const result = await orch.uploadAndList(did, Buffer.from('data'), 'EHR', 'cardiology');
    const profile = repo.findByDID(did)!;
    expect(profile.dataReferences.some(r => r.cid === result.cid)).toBe(true);
  });

  it('registers a marketplace listing', async () => {
    const { orch, market } = makeOrchestrator();
    const { did } = orch.registerPatient();
    await orch.uploadAndList(did, Buffer.from('data'), 'EHR', 'cardiology');
    expect(market.searchDatasets({ category: 'cardiology' })).toHaveLength(1);
  });

  it('throws when anonymization is rejected', async () => {
    const { orch } = makeOrchestrator({ anonymizer: makeAnonymizer(false) });
    const { did } = orch.registerPatient();
    await expect(orch.uploadAndList(did, Buffer.from('data'), 'EHR', 'cardiology'))
      .rejects.toThrow(/anonymization rejected/i);
  });

  it('writes a DATA_ANONYMIZED audit entry', async () => {
    const { orch, audit } = makeOrchestrator();
    const { did } = orch.registerPatient();
    await orch.uploadAndList(did, Buffer.from('data'), 'EHR', 'cardiology');
    const trail = audit.getAuditTrail(did);
    expect(trail.some(e => e.eventType === 'DATA_ANONYMIZED')).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Flow B: Contract + computation
// ---------------------------------------------------------------------------

describe('PlatformOrchestrator — computation flow', () => {

  it('runComputation returns a jobId and onChainTxHash', async () => {
    const { orch } = makeOrchestrator();
    const { did } = orch.registerPatient();
    await orch.submitAndSignContract(did, 'contract-1', validRequest);
    const result = await orch.runComputation('contract-1', did);
    expect(result.jobId).toBeTruthy();
    expect(result.onChainTxHash).toBeTruthy();
  });

  it('runComputation writes COMPUTATION_COMPLETED and DIVIDEND_PAID audit entries', async () => {
    const { orch, audit } = makeOrchestrator();
    const { did } = orch.registerPatient();
    await orch.submitAndSignContract(did, 'contract-2', validRequest);
    await orch.runComputation('contract-2', did);
    const trail = audit.getAuditTrail(did);
    expect(trail.some(e => e.eventType === 'COMPUTATION_COMPLETED')).toBe(true);
    expect(trail.some(e => e.eventType === 'DIVIDEND_PAID')).toBe(true);
  });

  it('runComputation throws when consent is not active', async () => {
    const { orch } = makeOrchestrator({ computationActive: false });
    const { did } = orch.registerPatient();
    await expect(orch.runComputation('contract-no-consent', did))
      .rejects.toThrow(/no valid active Consent Record/i);
  });
});

// ---------------------------------------------------------------------------
// Flow C: Revocation
// ---------------------------------------------------------------------------

describe('PlatformOrchestrator — revocation', () => {

  it('revokeConsent returns a refundTxHash', async () => {
    const { orch } = makeOrchestrator();
    const { did } = orch.registerPatient();
    const result = await orch.revokeConsent('contract-rev', did);
    expect(result.refundTxHash).toBe('0xrefund');
  });

  it('revokeConsent writes a CONSENT_REVOKED audit entry', async () => {
    const { orch, audit } = makeOrchestrator();
    const { did } = orch.registerPatient();
    await orch.revokeConsent('contract-rev', did);
    const trail = audit.getAuditTrail(did);
    expect(trail.some(e => e.eventType === 'CONSENT_REVOKED')).toBe(true);
  });

  it('revokeConsent calls processRevocationRefund', async () => {
    const router = makePaymentRouter();
    const { orch } = makeOrchestrator({ paymentRouter: router });
    const { did } = orch.registerPatient();
    await orch.revokeConsent('contract-refund', did);
    expect(router.refunds).toContain('contract-refund');
  });
});

// ---------------------------------------------------------------------------
// Flow D: Expiry watcher
// ---------------------------------------------------------------------------

describe('PlatformOrchestrator — expiry watcher', () => {

  it('expires contracts whose expiresAt has passed', async () => {
    const pastExpiry = Math.floor(Date.now() / 1000) - 100; // 100s ago
    const cm = makeConsentManager(['contract-exp'], pastExpiry);
    const { orch, audit } = makeOrchestrator({ consentManager: cm });
    const { did } = orch.registerPatient();
    const result = await orch.checkAndExpireContracts(did);
    expect(result.expired).toContain('contract-exp');
  });

  it('does not expire contracts that have not yet elapsed', async () => {
    const futureExpiry = Math.floor(Date.now() / 1000) + 9999;
    const cm = makeConsentManager(['contract-active'], futureExpiry);
    const { orch } = makeOrchestrator({ consentManager: cm });
    const { did } = orch.registerPatient();
    const result = await orch.checkAndExpireContracts(did);
    expect(result.expired).toHaveLength(0);
  });

  it('writes CONTRACT_EXPIRED audit entry for each expired contract', async () => {
    const pastExpiry = Math.floor(Date.now() / 1000) - 100;
    const cm = makeConsentManager(['c1', 'c2'], pastExpiry);
    const { orch, audit } = makeOrchestrator({ consentManager: cm });
    const { did } = orch.registerPatient();
    await orch.checkAndExpireContracts(did);
    const trail = audit.getAuditTrail(did);
    const expiredEntries = trail.filter(e => e.eventType === 'CONTRACT_EXPIRED');
    expect(expiredEntries).toHaveLength(2);
  });
});
