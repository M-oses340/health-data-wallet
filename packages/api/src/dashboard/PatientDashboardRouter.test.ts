/**
 * Unit tests for PatientDashboardRouter.
 * Requirements: 5.5, 6.1, 6.2, 6.5
 */
import express from 'express';
import request from 'supertest';
import { createPatientDashboardRouter, IPaymentStore } from './PatientDashboardRouter';
import { AuditTrailService } from '../audit/AuditTrailService';
import { DataDividendRecord } from '@health-data/sdk';
import { db } from '../db';

// supertest may not be installed — use a lightweight alternative via http
// We'll test the router logic directly using express + supertest pattern
// but fall back to direct function calls if supertest is unavailable.

function makeApp(auditTrail: AuditTrailService, paymentStore: IPaymentStore) {
  const app = express();
  app.use('/patient', createPatientDashboardRouter(auditTrail, paymentStore));
  return app;
}

function makePaymentStore(records: DataDividendRecord[] = []): IPaymentStore {
  return { getByPatient: async () => records };
}

const DID = 'did:ethr:0xPatient';
const ENCODED_DID = encodeURIComponent(DID);

const samplePayments: DataDividendRecord[] = [
  {
    transactionHash: '0xabc',
    contractId: 'c1',
    patientWallet: '0xwallet',
    amount: BigInt('100000000000000000'),
    paidAt: 1000,
    computationMethod: 'FEDERATED_LEARNING',
  },
  {
    transactionHash: '0xdef',
    contractId: 'c2',
    patientWallet: '0xwallet',
    amount: BigInt('200000000000000000'),
    paidAt: 2000,
    computationMethod: 'ZKP',
  },
];

describe('GET /patient/:did/payments', () => {
  beforeEach(() => { db.prepare('DELETE FROM audit_trail').run(); });

  it('returns 200 with payment records', async () => {
    const audit = new AuditTrailService();
    const app = makeApp(audit, makePaymentStore(samplePayments));
    const res = await request(app).get(`/patient/${ENCODED_DID}/payments`);
    expect(res.status).toBe(200);
    expect(res.body).toHaveLength(2);
  });

  it('returns all payment fields', async () => {
    const audit = new AuditTrailService();
    const app = makeApp(audit, makePaymentStore(samplePayments));
    const res = await request(app).get(`/patient/${ENCODED_DID}/payments`);
    expect(res.body[0].transactionHash).toBe('0xabc');
    expect(res.body[0].contractId).toBe('c1');
    expect(res.body[0].computationMethod).toBe('FEDERATED_LEARNING');
  });

  it('serialises bigint amount as string', async () => {
    const audit = new AuditTrailService();
    const app = makeApp(audit, makePaymentStore(samplePayments));
    const res = await request(app).get(`/patient/${ENCODED_DID}/payments`);
    expect(typeof res.body[0].amount).toBe('string');
    expect(res.body[0].amount).toBe('100000000000000000');
  });

  it('returns empty array when patient has no payments', async () => {
    const audit = new AuditTrailService();
    const app = makeApp(audit, makePaymentStore([]));
    const res = await request(app).get(`/patient/${ENCODED_DID}/payments`);
    expect(res.status).toBe(200);
    expect(res.body).toEqual([]);
  });
});

describe('GET /patient/:did/audit-trail', () => {
  beforeEach(() => { db.prepare('DELETE FROM audit_trail').run(); });

  it('returns 200 with audit entries', async () => {
    const audit = new AuditTrailService();
    audit.writeEntry({ patientDID: DID, eventType: 'CONSENT_GRANTED', timestamp: 1000 });
    audit.writeEntry({ patientDID: DID, eventType: 'DIVIDEND_PAID',   timestamp: 2000 });
    const app = makeApp(audit, makePaymentStore());
    const res = await request(app)
      .get(`/patient/${ENCODED_DID}/audit-trail`)
      .set('Accept', 'application/json');
    expect(res.status).toBe(200);
    const body = JSON.parse(res.text);
    expect(body).toHaveLength(2);
  });

  it('returns entries in chronological order', async () => {
    const audit = new AuditTrailService();
    audit.writeEntry({ patientDID: DID, eventType: 'DIVIDEND_PAID',   timestamp: 3000 });
    audit.writeEntry({ patientDID: DID, eventType: 'CONSENT_GRANTED', timestamp: 1000 });
    audit.writeEntry({ patientDID: DID, eventType: 'COMPUTATION_STARTED', timestamp: 2000 });
    const app = makeApp(audit, makePaymentStore());
    const res = await request(app)
      .get(`/patient/${ENCODED_DID}/audit-trail`)
      .set('Accept', 'application/json');
    const body = JSON.parse(res.text);
    expect(body[0].timestamp).toBe(1000);
    expect(body[1].timestamp).toBe(2000);
    expect(body[2].timestamp).toBe(3000);
  });

  it('returns valid JSON when Accept: application/json is set', async () => {
    const audit = new AuditTrailService();
    audit.writeEntry({ patientDID: DID, eventType: 'CONSENT_GRANTED' });
    const app = makeApp(audit, makePaymentStore());
    const res = await request(app)
      .get(`/patient/${ENCODED_DID}/audit-trail`)
      .set('Accept', 'application/json');
    expect(() => JSON.parse(res.text)).not.toThrow();
  });

  it('returns empty array for patient with no audit entries', async () => {
    const audit = new AuditTrailService();
    const app = makeApp(audit, makePaymentStore());
    const res = await request(app)
      .get(`/patient/${ENCODED_DID}/audit-trail`)
      .set('Accept', 'application/json');
    expect(JSON.parse(res.text)).toEqual([]);
  });

  it('only returns entries for the requested patient', async () => {
    const audit = new AuditTrailService();
    audit.writeEntry({ patientDID: DID,                    eventType: 'CONSENT_GRANTED' });
    audit.writeEntry({ patientDID: 'did:ethr:0xOther',     eventType: 'DIVIDEND_PAID' });
    const app = makeApp(audit, makePaymentStore());
    const res = await request(app)
      .get(`/patient/${ENCODED_DID}/audit-trail`)
      .set('Accept', 'application/json');
    const body = JSON.parse(res.text);
    expect(body).toHaveLength(1);
    expect(body[0].patientDID).toBe(DID);
  });
});
