/**
 * Unit tests for ComplianceService.
 * Requirements: 3.7, 8.2, 8.3, 8.4, 8.5
 */
import { ComplianceService, IConsentStore, IVaultStore, IPaymentStore } from './ComplianceService';
import { AuditTrailService } from '../audit/AuditTrailService';
import { PatientProfileRepository } from '../patient/PatientProfileRepository';
import { DataDividendRecord } from '@health-data/sdk';

// ---------------------------------------------------------------------------
// Stubs
// ---------------------------------------------------------------------------

function makeConsentStore(scope: string | null = 'cardiology-research', activeIds: string[] = []): IConsentStore {
  const invalidated = new Set<string>();
  return {
    getPermittedScope: async () => scope,
    invalidateContract: async (id) => { invalidated.add(id); },
    getActiveContractIds: async () => activeIds,
  };
}

function makeVaultStore(recordCount = 3): IVaultStore {
  return { deleteByPatient: async () => recordCount };
}

function makePaymentStore(records: DataDividendRecord[] = []): IPaymentStore {
  return { getByPatient: async () => records };
}

function makeSvc(
  consentStore = makeConsentStore(),
  vaultStore = makeVaultStore(),
  paymentStore = makePaymentStore(),
) {
  const audit = new AuditTrailService();
  const repo  = new PatientProfileRepository();
  return { svc: new ComplianceService(audit, repo, consentStore, vaultStore, paymentStore), audit, repo };
}

const DID = 'did:ethr:0xPatient';

// ---------------------------------------------------------------------------
// Scope enforcement (Requirements 3.7, 8.4, 8.5)
// ---------------------------------------------------------------------------

describe('ComplianceService — scope enforcement', () => {

  it('allows when stated purpose matches consented scope', async () => {
    const { svc } = makeSvc(makeConsentStore('cardiology-research'));
    const result = await svc.checkScope('contract-1', 'cardiology-research', DID);
    expect(result.allowed).toBe(true);
    expect(result.violationReason).toBeUndefined();
  });

  it('allows scope match case-insensitively', async () => {
    const { svc } = makeSvc(makeConsentStore('Cardiology-Research'));
    const result = await svc.checkScope('contract-1', 'cardiology-research', DID);
    expect(result.allowed).toBe(true);
  });

  it('rejects when stated purpose does not match consented scope', async () => {
    const { svc } = makeSvc(makeConsentStore('cardiology-research'));
    const result = await svc.checkScope('contract-1', 'oncology-research', DID);
    expect(result.allowed).toBe(false);
    expect(result.violationReason).toMatch(/scope mismatch/i);
  });

  it('rejection includes both stated and permitted scope in reason', async () => {
    const { svc } = makeSvc(makeConsentStore('cardiology-research'));
    const result = await svc.checkScope('contract-1', 'oncology-research', DID);
    expect(result.violationReason).toContain('oncology-research');
    expect(result.violationReason).toContain('cardiology-research');
  });

  it('writes a violation log entry on scope mismatch', async () => {
    const { svc, audit } = makeSvc(makeConsentStore('cardiology-research'));
    await svc.checkScope('contract-1', 'oncology-research', DID);
    expect(audit.getAuditTrail(DID)).toHaveLength(1);
  });

  it('violation log entry has a non-empty on-chain tx hash', async () => {
    const { svc } = makeSvc(makeConsentStore('cardiology-research'));
    const result = await svc.checkScope('contract-1', 'oncology-research', DID);
    expect(result.violationLogTxHash).toMatch(/^0x[a-f0-9]{64}$/);
  });

  it('rejects and logs when no consent record exists', async () => {
    const { svc, audit } = makeSvc(makeConsentStore(null));
    const result = await svc.checkScope('contract-missing', 'any-purpose', DID);
    expect(result.allowed).toBe(false);
    expect(audit.getAuditTrail(DID)).toHaveLength(1);
  });

  it('does not write audit entry when scope matches', async () => {
    const { svc, audit } = makeSvc(makeConsentStore('cardiology-research'));
    await svc.checkScope('contract-1', 'cardiology-research', DID);
    expect(audit.getAuditTrail(DID)).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// GDPR Right to Erasure (Requirement 8.2)
// ---------------------------------------------------------------------------

describe('ComplianceService — GDPR erasure', () => {

  it('returns the number of deleted vault records', async () => {
    const { svc } = makeSvc(makeConsentStore(), makeVaultStore(5));
    const result = await svc.handleErasureRequest(DID);
    expect(result.deletedVaultRecords).toBe(5);
  });

  it('returns the number of invalidated contracts', async () => {
    const { svc } = makeSvc(makeConsentStore('scope', ['c1', 'c2', 'c3']));
    const result = await svc.handleErasureRequest(DID);
    expect(result.invalidatedContracts).toBe(3);
  });

  it('writes an audit entry for the erasure', async () => {
    const { svc, audit } = makeSvc();
    await svc.handleErasureRequest(DID);
    expect(audit.getAuditTrail(DID)).toHaveLength(1);
  });

  it('erasure audit entry has a non-empty on-chain tx hash', async () => {
    const { svc } = makeSvc();
    const result = await svc.handleErasureRequest(DID);
    expect(result.auditEntryHash).toMatch(/^0x[a-f0-9]{64}$/);
  });
});

// ---------------------------------------------------------------------------
// GDPR Right of Access (Requirement 8.3)
// ---------------------------------------------------------------------------

describe('ComplianceService — GDPR access export', () => {

  it('export contains the correct patientDID', async () => {
    const { svc } = makeSvc();
    const result = await svc.handleAccessRequest(DID);
    expect(result.patientDID).toBe(DID);
  });

  it('export contains vault references from the patient profile', async () => {
    const { svc, repo } = makeSvc();
    repo.create({
      did: DID, walletAddress: '0xabc', publicKey: '04ab', registeredAt: 0,
      dataReferences: [{ cid: 'Qm1', dataType: 'EHR', uploadedAt: 0, encryptionKeyRef: 'k1' }],
      minimumQualityThreshold: 60,
    });
    const result = await svc.handleAccessRequest(DID);
    expect(result.vaultReferences).toHaveLength(1);
    expect(result.vaultReferences[0].cid).toBe('Qm1');
  });

  it('export contains audit trail entries', async () => {
    const { svc, audit } = makeSvc();
    audit.writeEntry({ patientDID: DID, eventType: 'CONSENT_GRANTED' });
    const result = await svc.handleAccessRequest(DID);
    expect(result.auditTrail).toHaveLength(1);
  });

  it('export contains payment history', async () => {
    const payments: DataDividendRecord[] = [{
      transactionHash: '0xpay', contractId: 'c1', patientWallet: '0xabc',
      amount: 100n, paidAt: 1000, computationMethod: 'FEDERATED_LEARNING',
    }];
    const { svc } = makeSvc(makeConsentStore(), makeVaultStore(), makePaymentStore(payments));
    const result = await svc.handleAccessRequest(DID);
    expect(result.paymentHistory).toHaveLength(1);
  });

  it('export has an exportedAt timestamp', async () => {
    const { svc } = makeSvc();
    const result = await svc.handleAccessRequest(DID);
    expect(result.exportedAt).toBeGreaterThan(0);
  });

  it('export returns empty arrays for a patient with no data', async () => {
    const { svc } = makeSvc();
    const result = await svc.handleAccessRequest('did:ethr:0xEmpty');
    expect(result.vaultReferences).toEqual([]);
    expect(result.auditTrail).toEqual([]);
    expect(result.paymentHistory).toEqual([]);
  });
});
