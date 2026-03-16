/**
 * Smoke tests verifying fast-check is configured and shared types are importable.
 * Feature: health-data-monetization
 */
import * as fc from 'fast-check';
import type {
  DataType,
  ComputationMethod,
  ContractStatus,
  JobStatus,
  AuditEventType,
  ContentReference,
  HealthDataWallet,
  ConsentRecord,
  ContractState,
  AuditTrailEntry,
  DataDividendRecord,
  ComputationRequest,
  ComputationResult,
} from '@health-data/sdk';

describe('fast-check setup', () => {
  it('runs a basic property with fast-check', () => {
    fc.assert(
      fc.property(fc.integer(), fc.integer(), (a, b) => {
        return a + b === b + a;
      }),
    );
  });
});

describe('shared types are importable', () => {
  it('DataType values are valid', () => {
    const types: DataType[] = ['EHR', 'WEARABLE', 'GENETIC'];
    expect(types).toHaveLength(3);
  });

  it('ComputationMethod values are valid', () => {
    const methods: ComputationMethod[] = ['FEDERATED_LEARNING', 'ZKP'];
    expect(methods).toHaveLength(2);
  });

  it('ContractStatus values are valid', () => {
    const statuses: ContractStatus[] = [
      'PENDING_SIGNATURE',
      'ACTIVE',
      'EXPIRED',
      'REVOKED',
      'COMPLETED',
    ];
    expect(statuses).toHaveLength(5);
  });

  it('JobStatus values are valid', () => {
    const statuses: JobStatus[] = ['PENDING', 'RUNNING', 'COMPLETED', 'FAILED', 'REJECTED'];
    expect(statuses).toHaveLength(5);
  });

  it('AuditEventType values are valid', () => {
    const events: AuditEventType[] = [
      'CONSENT_GRANTED',
      'CONSENT_REVOKED',
      'COMPUTATION_STARTED',
      'COMPUTATION_COMPLETED',
      'DIVIDEND_PAID',
      'DATA_ANONYMIZED',
      'CONTRACT_EXPIRED',
    ];
    expect(events).toHaveLength(7);
  });

  it('ContentReference shape is correct', () => {
    const ref: ContentReference = {
      cid: 'QmTest',
      dataType: 'EHR',
      uploadedAt: Date.now(),
      encryptionKeyRef: 'key-ref-1',
    };
    expect(ref.cid).toBe('QmTest');
  });

  it('HealthDataWallet shape is correct', () => {
    const wallet: HealthDataWallet = {
      did: 'did:ethr:0x1234',
      publicKey: '0xabcd',
      dataReferences: [],
    };
    expect(wallet.did).toMatch(/^did:/);
  });

  it('AuditTrailEntry shape is correct', () => {
    const entry: AuditTrailEntry = {
      entryId: 'entry-1',
      patientDID: 'did:ethr:0x1234',
      eventType: 'CONSENT_GRANTED',
      timestamp: Date.now(),
      onChainTxHash: '0xdeadbeef',
    };
    expect(entry.eventType).toBe('CONSENT_GRANTED');
  });

  it('DataDividendRecord shape is correct', () => {
    const record: DataDividendRecord = {
      transactionHash: '0xabc',
      contractId: '0x123',
      patientWallet: '0xpatient',
      amount: BigInt(1000),
      paidAt: Date.now(),
      computationMethod: 'FEDERATED_LEARNING',
    };
    expect(record.amount).toBe(BigInt(1000));
  });

  it('ComputationRequest shape is correct', () => {
    const req: ComputationRequest = {
      researcherDID: 'did:ethr:0xresearcher',
      dataCategory: 'cardiovascular',
      computationMethod: 'ZKP',
      permittedScope: 'aggregate-statistics',
      accessDurationSeconds: 86400,
      dataDividendWei: BigInt(500),
    };
    expect(req.dataCategory).toBe('cardiovascular');
  });

  it('ComputationResult shape is correct', () => {
    const result: ComputationResult = {
      jobId: 'job-1',
      contractId: '0x123',
      completedAt: Date.now(),
      onChainTxHash: '0xresult',
    };
    expect(result.jobId).toBe('job-1');
  });
});
