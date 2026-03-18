/**
 * End-to-end integration tests for the Health Data Wallet API.
 * Covers the full user journey:
 *   1. Patient registers
 *   2. Patient logs in (gets JWT)
 *   3. Patient refreshes token
 *   4. Patient uploads health data
 *   5. Patient views profile, vault records, audit trail
 *   6. Researcher registers & logs in
 *   7. Researcher browses marketplace datasets
 *   8. Researcher submits computation request
 *   9. Patient checks payments & audit trail
 *  10. Patient revokes consent
 *  11. Auth guards — expired/invalid token rejection
 */
import request from 'supertest';
import { app } from '../server';
import { db } from '../db';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function authHeader(token: string) {
  return { Authorization: `Bearer ${token}` };
}

// ---------------------------------------------------------------------------
// DB cleanup between tests
// ---------------------------------------------------------------------------

beforeEach(() => {
  db.prepare('DELETE FROM audit_trail').run();
  db.prepare('DELETE FROM patient_profiles').run();
  db.prepare('DELETE FROM marketplace_listings').run();
  db.prepare('DELETE FROM vault_records').run();
  db.prepare('DELETE FROM researcher_profiles').run();
});

// ---------------------------------------------------------------------------
// 1. Health check
// ---------------------------------------------------------------------------

describe('GET /health', () => {
  it('returns ok', async () => {
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('ok');
  });
});

// ---------------------------------------------------------------------------
// 2. Patient registration & login
// ---------------------------------------------------------------------------

describe('Patient auth flow', () => {
  it('registers a new patient and returns a JWT', async () => {
    const res = await request(app).post('/auth/register');
    expect(res.status).toBe(201);
    expect(res.body.did).toMatch(/^did:ethr:0x/);
    expect(res.body.token).toBeTruthy();
    expect(res.body.token.split('.')).toHaveLength(3);
  });

  it('logs in with a registered DID and returns a fresh JWT', async () => {
    const reg = await request(app).post('/auth/register');
    const { did } = reg.body;

    // Small delay to ensure different iat second
    await new Promise(r => setTimeout(r, 1100));
    const login = await request(app).post('/auth/login').send({ did, role: 'patient' });
    expect(login.status).toBe(200);
    expect(login.body.token).toBeTruthy();
    expect(login.body.token).not.toBe(reg.body.token);
  });

  it('login returns 404 for unknown DID', async () => {
    const res = await request(app).post('/auth/login').send({ did: 'did:ethr:0xUnknown', role: 'patient' });
    expect(res.status).toBe(404);
  });

  it('login returns 400 when did or role is missing', async () => {
    const res = await request(app).post('/auth/login').send({ did: 'did:ethr:0xSomething' });
    expect(res.status).toBe(400);
  });
});

// ---------------------------------------------------------------------------
// 3. Token refresh
// ---------------------------------------------------------------------------

describe('Token refresh', () => {
  it('POST /auth/refresh returns a new valid token', async () => {
    const reg = await request(app).post('/auth/register');
    const token = reg.body.token;

    const refresh = await request(app)
      .post('/auth/refresh')
      .set(authHeader(token));
    expect(refresh.status).toBe(200);
    expect(refresh.body.token).toBeTruthy();
    expect(refresh.body.token.split('.')).toHaveLength(3);
  });

  it('POST /auth/refresh returns 401 without a token', async () => {
    const res = await request(app).post('/auth/refresh');
    expect(res.status).toBe(401);
  });
});

// ---------------------------------------------------------------------------
// 4. Patient profile
// ---------------------------------------------------------------------------

describe('Patient profile', () => {
  it('GET /patient/profile returns profile for registered patient', async () => {
    const reg = await request(app).post('/auth/register');
    const { did, token } = reg.body;

    const res = await request(app)
      .get(`/patient/profile?did=${encodeURIComponent(did)}`)
      .set(authHeader(token));
    expect(res.status).toBe(200);
    expect(res.body.did).toBe(did);
    expect(res.body.dataReferenceCount).toBe(0);
  });

  it('GET /patient/profile returns 401 without token', async () => {
    const res = await request(app).get('/patient/profile?did=did:ethr:0xTest');
    expect(res.status).toBe(401);
  });

  it('GET /patient/profile returns 404 for unknown DID', async () => {
    const reg = await request(app).post('/auth/register');
    const res = await request(app)
      .get('/patient/profile?did=did:ethr:0xUnknown')
      .set(authHeader(reg.body.token));
    expect(res.status).toBe(404);
  });
});

// ---------------------------------------------------------------------------
// 5. Vault upload & records
// ---------------------------------------------------------------------------

describe('Vault upload & records', () => {
  it('POST /vault/upload stores data and returns a CID', async () => {
    const reg = await request(app).post('/auth/register');
    const { did, token } = reg.body;

    const data = Buffer.from(JSON.stringify({ heartRate: 72, steps: 8000 })).toString('base64');
    const res = await request(app)
      .post('/vault/upload')
      .set(authHeader(token))
      .send({ patientDID: did, data, dataType: 'WEARABLE', category: 'cardiology' });

    expect(res.status).toBe(201);
    expect(res.body.cid).toBeTruthy();
    expect(res.body.qualityScore).toBeGreaterThan(0);
  });

  it('GET /vault/records returns uploaded records', async () => {
    const reg = await request(app).post('/auth/register');
    const { did, token } = reg.body;

    const data = Buffer.from('{"bp": 120}').toString('base64');
    await request(app)
      .post('/vault/upload')
      .set(authHeader(token))
      .send({ patientDID: did, data, dataType: 'EHR', category: 'cardiology' });

    const res = await request(app)
      .get(`/vault/records?did=${encodeURIComponent(did)}`)
      .set(authHeader(token));
    expect(res.status).toBe(200);
    expect(res.body.records).toHaveLength(1);
    expect(res.body.records[0].dataType).toBe('EHR');
  });

  it('profile dataReferenceCount increments after upload', async () => {
    const reg = await request(app).post('/auth/register');
    const { did, token } = reg.body;

    const data = Buffer.from('{"glucose": 5.4}').toString('base64');
    await request(app)
      .post('/vault/upload')
      .set(authHeader(token))
      .send({ patientDID: did, data, dataType: 'EHR', category: 'genomics' });

    const profile = await request(app)
      .get(`/patient/profile?did=${encodeURIComponent(did)}`)
      .set(authHeader(token));
    expect(profile.body.dataReferenceCount).toBe(1);
  });
});

// ---------------------------------------------------------------------------
// 6. Marketplace
// ---------------------------------------------------------------------------

describe('Marketplace', () => {
  it('GET /marketplace/datasets returns listings after upload', async () => {
    const reg = await request(app).post('/auth/register');
    const { did, token } = reg.body;

    const data = Buffer.from('{"dna": "ATCG"}').toString('base64');
    await request(app)
      .post('/vault/upload')
      .set(authHeader(token))
      .send({ patientDID: did, data, dataType: 'GENETIC', category: 'genomics' });

    const res = await request(app).get('/marketplace/datasets');
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    expect(res.body.length).toBeGreaterThan(0);
  });

  it('GET /marketplace/datasets filters by category', async () => {
    const reg = await request(app).post('/auth/register');
    const { did, token } = reg.body;

    const data = Buffer.from('{"ecg": true}').toString('base64');
    await request(app)
      .post('/vault/upload')
      .set(authHeader(token))
      .send({ patientDID: did, data, dataType: 'EHR', category: 'cardiology' });

    const res = await request(app).get('/marketplace/datasets?category=cardiology');
    expect(res.status).toBe(200);
    expect(res.body.every((l: any) => l.category === 'cardiology')).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// 7. Researcher registration & login
// ---------------------------------------------------------------------------

describe('Researcher auth flow', () => {
  it('registers a researcher and returns a JWT', async () => {
    const res = await request(app)
      .post('/auth/register/researcher')
      .send({ organisation: 'MedResearch Inc.' });
    expect(res.status).toBe(201);
    expect(res.body.did).toMatch(/^did:ethr:0x/);
    expect(res.body.token).toBeTruthy();
  });

  it('researcher can log in after registration', async () => {
    const reg = await request(app)
      .post('/auth/register/researcher')
      .send({ organisation: 'BioLab' });
    const { did } = reg.body;

    const login = await request(app).post('/auth/login').send({ did, role: 'researcher' });
    expect(login.status).toBe(200);
    expect(login.body.token).toBeTruthy();
  });
});

// ---------------------------------------------------------------------------
// 8. Researcher submits computation request
// ---------------------------------------------------------------------------

describe('Computation request', () => {
  it('researcher can submit a valid computation request', async () => {
    // Register researcher
    const resReg = await request(app)
      .post('/auth/register/researcher')
      .send({ organisation: 'DataLab' });
    const { did: researcherDID, token: resToken } = resReg.body;

    // Upload data as patient first (so marketplace has a listing)
    const patReg = await request(app).post('/auth/register');
    const { did: patientDID, token: patToken } = patReg.body;
    const data = Buffer.from('{"heartRate": 80}').toString('base64');
    await request(app)
      .post('/vault/upload')
      .set(authHeader(patToken))
      .send({ patientDID, data, dataType: 'WEARABLE', category: 'cardiology' });

    // Researcher submits computation request
    const res = await request(app)
      .post('/marketplace/requests')
      .set(authHeader(resToken))
      .send({
        researcherDID,
        dataCategory: 'cardiology',
        computationMethod: 'FEDERATED_LEARNING',
        permittedScope: 'cardiovascular-research',
        accessDurationSeconds: 86400,
        dataDividendWei: '100000000000000000',
      });

    expect(res.status).toBe(201);
    expect(res.body.status).toBe('ACCEPTED');
    expect(res.body.contractId).toBeTruthy();

    // Trigger computation on the accepted contract
    const contractId = res.body.contractId;
    const compRes = await request(app)
      .post('/computation/run')
      .set(authHeader(resToken))
      .send({ contractId });

    expect(compRes.status).toBe(201);
    expect(compRes.body.job).toBeTruthy();
    expect(compRes.body.job.jobId).toBeTruthy();
    expect(compRes.body.job.status).toBe('COMPLETED');
  });

  it('returns 403 when a patient tries to submit a computation request', async () => {
    const reg = await request(app).post('/auth/register');
    const { token } = reg.body;

    const res = await request(app)
      .post('/marketplace/requests')
      .set(authHeader(token))
      .send({
        researcherDID: 'did:ethr:0xResearcher',
        dataCategory: 'cardiology',
        computationMethod: 'FEDERATED_LEARNING',
        permittedScope: 'research',
        accessDurationSeconds: 86400,
        dataDividendWei: '100000000000000000',
      });
    expect(res.status).toBe(403);
  });

  it('returns 400 when computation request is missing required fields', async () => {
    const resReg = await request(app)
      .post('/auth/register/researcher')
      .send({ organisation: 'Lab' });
    const { token } = resReg.body;

    const res = await request(app)
      .post('/marketplace/requests')
      .set(authHeader(token))
      .send({ researcherDID: 'did:ethr:0xResearcher' }); // missing most fields
    expect(res.status).toBe(400);
    expect(res.body.status).toBe('REJECTED');
  });
});

// ---------------------------------------------------------------------------
// 9. Patient audit trail & payments
// ---------------------------------------------------------------------------

describe('Patient audit trail & payments', () => {
  it('GET /patient/audit-trail returns entries after registration and upload', async () => {
    const reg = await request(app).post('/auth/register');
    const { did, token } = reg.body;

    const data = Buffer.from('{"temp": 37.2}').toString('base64');
    await request(app)
      .post('/vault/upload')
      .set(authHeader(token))
      .send({ patientDID: did, data, dataType: 'EHR', category: 'cardiology' });

    const res = await request(app)
      .get(`/patient/audit-trail?did=${encodeURIComponent(did)}`)
      .set(authHeader(token));
    expect(res.status).toBe(200);
    expect(res.body.entries.length).toBeGreaterThanOrEqual(2); // CONSENT_GRANTED + DATA_ANONYMIZED
    const types = res.body.entries.map((e: any) => e.eventType);
    expect(types).toContain('CONSENT_GRANTED');
    expect(types).toContain('DATA_ANONYMIZED');
  });

  it('GET /patient/payments returns only DIVIDEND_PAID entries', async () => {
    const reg = await request(app).post('/auth/register');
    const { did, token } = reg.body;

    const res = await request(app)
      .get(`/patient/payments?did=${encodeURIComponent(did)}`)
      .set(authHeader(token));
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body.payments)).toBe(true);
    res.body.payments.forEach((p: any) => expect(p.eventType).toBe('DIVIDEND_PAID'));
  });
});

// ---------------------------------------------------------------------------
// 10. Consent revocation
// ---------------------------------------------------------------------------

describe('Consent revocation', () => {
  it('POST /consent/revoke returns a refundTxHash', async () => {
    const reg = await request(app).post('/auth/register');
    const { did, token } = reg.body;

    const res = await request(app)
      .post('/consent/revoke')
      .set(authHeader(token))
      .send({ contractId: '0xcontract123', patientDID: did });

    expect(res.status).toBe(200);
    expect(res.body.refundTxHash).toBeTruthy();
    expect(res.body.contractId).toBe('0xcontract123');
  });

  it('POST /consent/revoke returns 400 when fields are missing', async () => {
    const reg = await request(app).post('/auth/register');
    const { token } = reg.body;

    const res = await request(app)
      .post('/consent/revoke')
      .set(authHeader(token))
      .send({ contractId: '0xcontract123' }); // missing patientDID
    expect(res.status).toBe(400);
  });
});

// ---------------------------------------------------------------------------
// 11. Auth guards
// ---------------------------------------------------------------------------

describe('Auth guards', () => {
  it('returns 401 with no token on protected routes', async () => {
    const routes = [
      () => request(app).get('/patient/profile?did=x'),
      () => request(app).get('/patient/audit-trail?did=x'),
      () => request(app).get('/patient/payments?did=x'),
      () => request(app).get('/vault/records?did=x'),
      () => request(app).post('/vault/upload').send({}),
      () => request(app).post('/consent/revoke').send({}),
    ];
    for (const route of routes) {
      const res = await route();
      expect(res.status).toBe(401);
    }
  });

  it('returns 401 with a tampered token', async () => {
    const reg = await request(app).post('/auth/register');
    const tampered = reg.body.token.slice(0, -4) + 'XXXX';

    const res = await request(app)
      .get(`/patient/profile?did=${encodeURIComponent(reg.body.did)}`)
      .set(authHeader(tampered));
    expect(res.status).toBe(401);
    expect(res.body.error).toBe('Invalid token');
  });

  it('returns 401 with error "Token expired" for an expired token', async () => {
    // Build an expired token manually using Node crypto directly
    const { createHmac } = require('crypto');
    const secret = 'dev-secret-change-in-prod';
    const now = Math.floor(Date.now() / 1000);
    const header = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
    const body = Buffer.from(JSON.stringify({
      did: 'did:ethr:0xTest', role: 'patient',
      iat: now - 7200,
      exp: now - 3600, // expired 1 hour ago
    })).toString('base64url');
    const sig = createHmac('sha256', secret).update(`${header}.${body}`).digest('base64url');
    const expiredToken = `${header}.${body}.${sig}`;

    const res = await request(app)
      .get('/patient/profile?did=did:ethr:0xTest')
      .set(authHeader(expiredToken));
    expect(res.status).toBe(401);
    expect(res.body.error).toBe('Token expired');
  });
});
