/**
 * Unit tests for AuditTrailService.
 * Requirements: 6.1, 6.2, 6.3, 6.4, 6.5
 */
import { AuditTrailService } from './AuditTrailService';
import { AuditEventType } from '@health-data/sdk';
import { db } from '../db';

const DID_A = 'did:ethr:0xPatientA';
const DID_B = 'did:ethr:0xPatientB';

describe('AuditTrailService', () => {
  beforeEach(() => {
    db.prepare('DELETE FROM audit_trail').run();
  });

  // --- writeEntry ---

  it('writeEntry returns an entry with a non-empty entryId and onChainTxHash', () => {
    const svc = new AuditTrailService();
    const entry = svc.writeEntry({ patientDID: DID_A, eventType: 'CONSENT_GRANTED' });
    expect(entry.entryId).toBeTruthy();
    expect(entry.onChainTxHash).toMatch(/^0x[a-f0-9]{64}$/);
  });

  it('writeEntry stores the correct eventType and patientDID', () => {
    const svc = new AuditTrailService();
    const entry = svc.writeEntry({ patientDID: DID_A, eventType: 'DIVIDEND_PAID', amount: 100n });
    expect(entry.patientDID).toBe(DID_A);
    expect(entry.eventType).toBe('DIVIDEND_PAID');
    expect(entry.amount).toBe(100n);
  });

  it('written entry is frozen — mutation throws in strict mode', () => {
    const svc = new AuditTrailService();
    const entry = svc.writeEntry({ patientDID: DID_A, eventType: 'CONSENT_GRANTED' });
    expect(Object.isFrozen(entry)).toBe(true);
  });

  // --- getAuditTrail (Requirements 6.1, 6.2) ---

  it('getAuditTrail returns only entries for the requested patient', () => {
    const svc = new AuditTrailService();
    svc.writeEntry({ patientDID: DID_A, eventType: 'CONSENT_GRANTED' });
    svc.writeEntry({ patientDID: DID_B, eventType: 'CONSENT_GRANTED' });
    svc.writeEntry({ patientDID: DID_A, eventType: 'DIVIDEND_PAID' });
    const trail = svc.getAuditTrail(DID_A);
    expect(trail).toHaveLength(2);
    trail.forEach(e => expect(e.patientDID).toBe(DID_A));
  });

  it('getAuditTrail returns entries in ascending timestamp order', () => {
    const svc = new AuditTrailService();
    svc.writeEntry({ patientDID: DID_A, eventType: 'COMPUTATION_STARTED', timestamp: 3000 });
    svc.writeEntry({ patientDID: DID_A, eventType: 'CONSENT_GRANTED',     timestamp: 1000 });
    svc.writeEntry({ patientDID: DID_A, eventType: 'DIVIDEND_PAID',       timestamp: 2000 });
    const trail = svc.getAuditTrail(DID_A);
    expect(trail[0].timestamp).toBe(1000);
    expect(trail[1].timestamp).toBe(2000);
    expect(trail[2].timestamp).toBe(3000);
  });

  it('getAuditTrail returns empty array for unknown patient', () => {
    const svc = new AuditTrailService();
    expect(svc.getAuditTrail('did:ethr:0xUnknown')).toEqual([]);
  });

  it('all event types can be written and retrieved', () => {
    const svc = new AuditTrailService();
    const types: AuditEventType[] = [
      'CONSENT_GRANTED', 'CONSENT_REVOKED', 'COMPUTATION_STARTED',
      'COMPUTATION_COMPLETED', 'DIVIDEND_PAID', 'DATA_ANONYMIZED', 'CONTRACT_EXPIRED',
    ];
    types.forEach(eventType => svc.writeEntry({ patientDID: DID_A, eventType }));
    const trail = svc.getAuditTrail(DID_A);
    expect(trail).toHaveLength(types.length);
    const writtenTypes = trail.map(e => e.eventType);
    types.forEach(t => expect(writtenTypes).toContain(t));
  });

  // --- immutability (Requirement 6.3) ---

  it('re-reading an entry returns identical content', () => {
    const svc = new AuditTrailService();
    svc.writeEntry({ patientDID: DID_A, eventType: 'CONSENT_GRANTED', contractId: 'c1' });
    const first  = svc.getAuditTrail(DID_A)[0];
    const second = svc.getAuditTrail(DID_A)[0];
    expect(first.entryId).toBe(second.entryId);
    expect(first.onChainTxHash).toBe(second.onChainTxHash);
    expect(first.timestamp).toBe(second.timestamp);
  });

  it('N operations produce exactly N audit entries', () => {
    const svc = new AuditTrailService();
    const N = 5;
    for (let i = 0; i < N; i++) {
      svc.writeEntry({ patientDID: DID_A, eventType: 'COMPUTATION_COMPLETED' });
    }
    expect(svc.getAuditTrail(DID_A)).toHaveLength(N);
  });

  // --- exportAuditTrail (Requirement 6.5) ---

  it('exportAuditTrail returns valid JSON', () => {
    const svc = new AuditTrailService();
    svc.writeEntry({ patientDID: DID_A, eventType: 'CONSENT_GRANTED' });
    const json = svc.exportAuditTrail(DID_A);
    expect(() => JSON.parse(json)).not.toThrow();
  });

  it('exportAuditTrail round-trip produces equivalent entries', () => {
    const svc = new AuditTrailService();
    svc.writeEntry({ patientDID: DID_A, eventType: 'CONSENT_GRANTED',  contractId: 'c1', timestamp: 1000 });
    svc.writeEntry({ patientDID: DID_A, eventType: 'DIVIDEND_PAID',    amount: 500n,      timestamp: 2000 });
    const parsed = JSON.parse(svc.exportAuditTrail(DID_A));
    expect(parsed).toHaveLength(2);
    expect(parsed[0].eventType).toBe('CONSENT_GRANTED');
    expect(parsed[1].eventType).toBe('DIVIDEND_PAID');
    // bigint serialised as string
    expect(parsed[1].amount).toBe('500');
  });

  it('exportAuditTrail returns empty array JSON for unknown patient', () => {
    const svc = new AuditTrailService();
    const parsed = JSON.parse(svc.exportAuditTrail('did:ethr:0xNobody'));
    expect(parsed).toEqual([]);
  });
});
