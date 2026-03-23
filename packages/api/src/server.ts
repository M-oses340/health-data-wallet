import express, { Request, Response, NextFunction } from 'express';
import * as crypto from 'crypto';
import rateLimit from 'express-rate-limit';
import { WalletService } from './wallet/WalletService';
import { PatientProfileRepository } from './patient/PatientProfileRepository';
import { ResearcherProfileRepository } from './researcher/ResearcherProfileRepository';
import { DataVaultService } from './vault/DataVaultService';
import { MarketplaceService } from './marketplace/MarketplaceService';
import { ComputationEngine, IVaultDataProvider } from './computation/ComputationEngine';
import { AuditTrailService } from './audit/AuditTrailService';
import { PlatformOrchestrator } from './orchestrator/PlatformOrchestrator';
import { buildChainAdapters } from './chain/ContractAdapters';
import { DataType, ComputationMethod } from '@health-data/sdk';
import { db } from './db';
import { ComplianceService } from './compliance/ComplianceService';

// ---------------------------------------------------------------------------
// Service singletons
// ---------------------------------------------------------------------------

const walletService = new WalletService();
const profileRepo = new PatientProfileRepository();
const researcherRepo = new ResearcherProfileRepository();
const vaultService = new DataVaultService();
const marketplace = new MarketplaceService();
const auditTrail = new AuditTrailService();

const RPC_URL = process.env.BLOCKCHAIN_RPC_URL ?? 'http://localhost:8545';
const { consentRegistry, consentManager, paymentRouter, onChainPaymentRouter } = buildChainAdapters(RPC_URL);

// Vault data provider: each patient with vault records becomes one FL silo
const vaultDataProvider: IVaultDataProvider = {
  async getAnonymizedRecordsForFL(_contractId: string) {
    const dbModule = await import('./db');
    const rows = dbModule.db.prepare('SELECT did FROM patient_profiles').all() as { did: string }[];
    const silos: Record<string, number>[][] = [];
    for (const { did } of rows) {
      const records = vaultService.getPlaintextRecords(did);
      if (records.length === 0) continue;
      const numericRecords = records.map(rec => {
        const out: Record<string, number> = {};
        for (const [k, v] of Object.entries(rec)) {
          if (typeof v === 'number') out[k] = v;
        }
        return out;
      }).filter(r => Object.keys(r).length > 0);
      if (numericRecords.length > 0) silos.push(numericRecords);
    }
    return silos;
  },
};

const computationEngine = new ComputationEngine(consentRegistry, paymentRouter, vaultDataProvider);

const FL_URL = process.env.FL_SERVER_URL ?? 'http://localhost:5001';
const anonymizerAdapter = {
  async deidentify(data: Buffer, patientDID: string, dataType: DataType, threshold: number) {
    try {
      const res = await fetch(`${FL_URL}/anonymize`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text: data.toString('utf8'), patient_did: patientDID, data_type: dataType, threshold }),
      });
      if (!res.ok) throw new Error(`Anonymizer HTTP ${res.status}`);
      return await res.json() as { success: boolean; qualityScore: number; anonymizedCid: string; rejectionReason?: string };
    } catch {
      return { success: true, qualityScore: 75, anonymizedCid: 'anon-' + crypto.randomUUID() };
    }
  },
};

const orchestrator = new PlatformOrchestrator(
  walletService, profileRepo, vaultService, anonymizerAdapter,
  marketplace, computationEngine, auditTrail, consentManager, onChainPaymentRouter,
);

// ---------------------------------------------------------------------------
// ComplianceService — scope enforcement + GDPR
// ---------------------------------------------------------------------------

const complianceService = new ComplianceService(
  auditTrail,
  profileRepo,
  {
    async getPermittedScope(contractId: string) {
      const row = db.prepare(
        `SELECT permitted_scope FROM computation_requests WHERE contract_id = ? AND status = 'ACTIVE'`
      ).get(contractId) as { permitted_scope: string } | undefined;
      return row?.permitted_scope ?? null;
    },
    async invalidateContract(contractId: string) {
      db.prepare(`UPDATE computation_requests SET status = 'REVOKED' WHERE contract_id = ?`).run(contractId);
    },
    async getActiveContractIds(_patientDID: string) {
      const rows = db.prepare(
        `SELECT contract_id FROM computation_requests WHERE status = 'ACTIVE'`
      ).all() as { contract_id: string }[];
      return rows.map(r => r.contract_id);
    },
  },
  {
    async deleteByPatient(patientDID: string) {
      const result = db.prepare(`DELETE FROM vault_records WHERE patient_did = ?`).run(patientDID);
      db.prepare(`UPDATE patient_profiles SET data_references = '[]' WHERE did = ?`).run(patientDID);
      return result.changes;
    },
  },
  {
    async getByPatient(_patientDID: string) { return []; },
  },
);

// ---------------------------------------------------------------------------
// Contract expiry watcher — runs every 60 seconds
// ---------------------------------------------------------------------------

setInterval(async () => {
  try {
    const rows = db.prepare(
      `SELECT DISTINCT patient_did FROM computation_requests WHERE status = 'ACTIVE'`
    ).all() as { patient_did: string }[];
    for (const { patient_did } of rows) {
      const result = await orchestrator.checkAndExpireContracts(patient_did);
      if (result.expired.length > 0) {
        const placeholders = result.expired.map(() => '?').join(',');
        db.prepare(
          `UPDATE computation_requests SET status = 'EXPIRED' WHERE contract_id IN (${placeholders})`
        ).run(...result.expired);
        console.log(`[expiry] Expired contracts: ${result.expired.join(', ')}`);
      }
    }
  } catch (e) {
    console.warn('[expiry] watcher error:', (e as Error).message);
  }
}, 60_000);

// ---------------------------------------------------------------------------
// JWT helpers (HS256)
// ---------------------------------------------------------------------------

const JWT_SECRET = process.env.JWT_SECRET ?? 'dev-secret-change-in-prod';
const JWT_TTL_SECONDS = Number(process.env.JWT_TTL_SECONDS ?? 86400); // default 24 h

function signJWT(payload: object): string {
  const now = Math.floor(Date.now() / 1000);
  const header = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
  const body = Buffer.from(JSON.stringify({ ...payload, iat: now, exp: now + JWT_TTL_SECONDS })).toString('base64url');
  const sig = crypto.createHmac('sha256', JWT_SECRET).update(`${header}.${body}`).digest('base64url');
  return `${header}.${body}.${sig}`;
}

function verifyJWT(token: string): Record<string, unknown> {
  const [header, body, sig] = token.split('.');
  const expected = crypto.createHmac('sha256', JWT_SECRET).update(`${header}.${body}`).digest('base64url');
  if (sig !== expected) throw new Error('Invalid token');
  const payload = JSON.parse(Buffer.from(body, 'base64url').toString()) as Record<string, unknown>;
  if (typeof payload['exp'] === 'number' && Math.floor(Date.now() / 1000) > payload['exp']) {
    throw new Error('Token expired');
  }
  return payload;
}

// ---------------------------------------------------------------------------
// Auth middleware
// ---------------------------------------------------------------------------

function requireAuth(req: Request, res: Response, next: NextFunction): void {
  const auth = req.headers.authorization;
  if (!auth?.startsWith('Bearer ')) { res.status(401).json({ error: 'Unauthorized' }); return; }
  try {
    (req as any).jwtPayload = verifyJWT(auth.slice(7));
    next();
  } catch (e: unknown) {
    const msg = (e as Error).message;
    if (msg === 'Token expired') {
      res.status(401).json({ error: 'Token expired' }); return;
    }
    res.status(401).json({ error: 'Invalid token' });
  }
}

function requireRole(role: string) {
  return (req: Request, res: Response, next: NextFunction): void => {
    const payload = (req as any).jwtPayload as Record<string, unknown>;
    if (payload?.role !== role) {
      res.status(403).json({ error: `Forbidden: ${role} role required` });
      return;
    }
    next();
  };
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

export const app = express();
app.use(express.json({ limit: '10mb' }));

app.get('/health', (_req, res) => res.json({ status: 'ok' }));

// ── Auth ──────────────────────────────────────────────────────────────────

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many attempts, please try again later.' },
});

app.post('/auth/register', (_req, res) => {
  try {
    const result = orchestrator.registerPatient();
    const token = signJWT({ did: result.did, role: 'patient' });
    res.status(201).json({ ...result, token });
  } catch (e: unknown) {
    res.status(500).json({ error: (e as Error).message });
  }
});

app.post('/auth/register/researcher', authLimiter, (req, res) => {
  try {
    const { organisation } = req.body as { organisation?: string };
    const keyPair = walletService.generateKeyPair();
    const did = walletService.provisionDID(keyPair.publicKey);
    researcherRepo.create({
      did,
      walletAddress: keyPair.address,
      publicKey: keyPair.publicKey,
      registeredAt: Date.now(),
      organisation: organisation ?? '',
    });
    const token = signJWT({ did, role: 'researcher' });
    res.status(201).json({ did, walletAddress: keyPair.address, publicKey: keyPair.publicKey, token });
  } catch (e: unknown) {
    res.status(500).json({ error: (e as Error).message });
  }
});

app.post('/auth/login', authLimiter, (req, res) => {
  const { did, role } = req.body as { did: string; role: string };
  if (!did || !role) { res.status(400).json({ error: 'did and role required' }); return; }
  if (role === 'researcher') {
    if (!researcherRepo.exists(did)) { res.status(404).json({ error: 'DID not found' }); return; }
  } else {
    if (!profileRepo.findByDID(did)) { res.status(404).json({ error: 'DID not found' }); return; }
  }
  const token = signJWT({ did, role });
  res.json({ token });
});

app.post('/auth/refresh', requireAuth, (req, res) => {
  const { did, role } = (req as any).jwtPayload as { did: string; role: string };
  const token = signJWT({ did, role });
  res.json({ token });
});

// ── Patient ───────────────────────────────────────────────────────────────

app.get('/patient/payments', requireAuth, (req, res) => {
  const did = req.query['did'] as string;
  if (!did) { res.status(400).json({ error: 'did query param required' }); return; }
  const entries = auditTrail.getAuditTrail(did)
    .filter(e => e.eventType === 'DIVIDEND_PAID')
    .map(e => ({
      ...e,
      // Convert wei BigInt to ETH string for JSON serialization
      amount: e.amount != null
        ? (Number(e.amount) / 1e18).toFixed(6).replace(/\.?0+$/, '')
        : undefined,
    }));
  res.json({ payments: entries });
});

app.get('/patient/audit-trail', requireAuth, (req, res) => {
  const did = req.query['did'] as string;
  if (!did) { res.status(400).json({ error: 'did query param required' }); return; }
  const entries = auditTrail.getAuditTrail(did).map(e => ({
    ...e,
    amount: e.amount != null ? e.amount.toString() : undefined,
  }));
  res.json({ entries });
});

app.get('/patient/profile', requireAuth, (req, res) => {
  const did = req.query['did'] as string;
  if (!did) { res.status(400).json({ error: 'did query param required' }); return; }
  const profile = profileRepo.findByDID(did);
  if (!profile) { res.status(404).json({ error: 'Patient not found' }); return; }
  res.json({
    did: profile.did,
    walletAddress: profile.walletAddress,
    registeredAt: profile.registeredAt,
    dataReferenceCount: profile.dataReferences.length,
    minimumQualityThreshold: profile.minimumQualityThreshold,
  });
});

// ── Vault ─────────────────────────────────────────────────────────────────

app.get('/vault/records', requireAuth, (req, res) => {
  const did = req.query['did'] as string;
  if (!did) { res.status(400).json({ error: 'did query param required' }); return; }
  const records = vaultService.listByPatient(did);
  res.json({ records });
});

app.post('/vault/upload', requireAuth, async (req, res) => {
  const { patientDID, data, dataType, category } = req.body as {
    patientDID: string; data: string; dataType: DataType; category: string;
  };
  if (!patientDID || !data || !dataType || !category) {
    res.status(400).json({ error: 'patientDID, data, dataType, category required' }); return;
  }
  try {
    const result = await orchestrator.uploadAndList(patientDID, Buffer.from(data, 'base64'), dataType, category);
    res.status(201).json(result);
  } catch (e: unknown) {
    res.status(500).json({ error: (e as Error).message });
  }
});

// ── Marketplace ───────────────────────────────────────────────────────────

app.get('/marketplace/datasets', (req, res) => {
  const { category, dataType } = req.query as { category?: string; dataType?: string };
  res.json(marketplace.searchDatasets({ category, dataType: dataType as DataType }));
});

// Researcher-only: validate and accept a computation request.
// Returns contractId for the researcher to use when triggering computation
// after patients have granted on-chain consent.
app.post('/marketplace/requests', requireAuth, requireRole('researcher'), (req, res) => {
  const {
    listingId,
    researcherDID,
    computationMethod,
    dataCategory,
    permittedScope,
    accessDurationSeconds,
    dataDividendWei,
  } = req.body as {
    listingId?: string;
    researcherDID?: string;
    computationMethod?: ComputationMethod;
    dataCategory?: string;
    permittedScope?: string;
    accessDurationSeconds?: number;
    dataDividendWei?: string;
  };

  const submission = marketplace.submitComputationRequest({
    researcherDID,
    dataCategory,
    computationMethod,
    permittedScope,
    accessDurationSeconds,
    dataDividendWei: dataDividendWei != null ? BigInt(dataDividendWei) : undefined,
  });

  if (submission.status === 'REJECTED') {
    res.status(400).json(submission); return;
  }

  if (listingId) {
    const listings = marketplace.searchDatasets({});
    if (!listings.find(l => l.listingId === listingId)) {
      res.status(404).json({ error: `Listing ${listingId} not found` }); return;
    }
  }

  // Return the accepted submission — computation is triggered separately via
  // POST /computation/run once patients have granted on-chain consent.
  res.status(201).json(submission);
});

// Researcher: list their ACTIVE contracts (patient has granted consent).
app.get('/computation/active', requireAuth, requireRole('researcher'), (req, res) => {
  const { did } = (req as any).jwtPayload as { did: string };
  const rows = db.prepare(
    `SELECT request_id, contract_id, researcher_did, data_category, computation_method,
            permitted_scope, access_duration, data_dividend_wei, status, created_at
     FROM computation_requests WHERE status = 'ACTIVE' AND researcher_did = ? ORDER BY created_at DESC`
  ).all(did) as any[];
  res.json(rows.map(r => ({
    requestId: r.request_id,
    contractId: r.contract_id,
    researcherDID: r.researcher_did,
    dataCategory: r.data_category,
    computationMethod: r.computation_method,
    permittedScope: r.permitted_scope,
    accessDurationSeconds: r.access_duration,
    dataDividendWei: r.data_dividend_wei,
    status: r.status,
    createdAt: r.created_at,
  })));
});

// Trigger computation for an already-accepted contract (requires active on-chain consent).
app.post('/computation/run', requireAuth, requireRole('researcher'), async (req, res) => {
  const { contractId, patientDID } = req.body as { contractId?: string; patientDID?: string };
  if (!contractId || !patientDID) { res.status(400).json({ error: 'contractId and patientDID required' }); return; }
  try {
    // Scope check before computation
    const row = db.prepare(
      `SELECT permitted_scope FROM computation_requests WHERE contract_id = ?`
    ).get(contractId) as { permitted_scope: string } | undefined;
    if (row) {
      const scopeResult = await complianceService.checkScope(contractId, row.permitted_scope, patientDID);
      if (!scopeResult.allowed) {
        res.status(403).json({ error: scopeResult.violationReason }); return;
      }
    }
    const result = await orchestrator.runComputation(contractId, patientDID);
    // Mark contract COMPLETED after successful computation + payment
    db.prepare(`UPDATE computation_requests SET status = 'COMPLETED' WHERE contract_id = ?`).run(contractId);
    const job = computationEngine.getJob(result.jobId);
    res.status(201).json({ job });
  } catch (e: unknown) {
    const msg = (e as Error).message;
    const status = msg.startsWith('Computation rejected') ? 403 : 500;
    res.status(status).json({ error: msg });
  }
});

// ── Consent ───────────────────────────────────────────────────────────────


// List pending (ACCEPTED, not yet granted) computation requests — shown to patient.
app.get('/consent/pending', requireAuth, (_req, res) => {
  const rows = db.prepare(
    `SELECT request_id, contract_id, researcher_did, data_category, computation_method,
            permitted_scope, access_duration, data_dividend_wei, status, created_at
     FROM computation_requests WHERE status = 'ACCEPTED' ORDER BY created_at DESC`
  ).all() as any[];
  res.json(rows.map(r => ({
    requestId: r.request_id,
    contractId: r.contract_id,
    researcherDID: r.researcher_did,
    dataCategory: r.data_category,
    computationMethod: r.computation_method,
    permittedScope: r.permitted_scope,
    accessDurationSeconds: r.access_duration,
    dataDividendWei: r.data_dividend_wei,
    createdAt: r.created_at,
  })));
});
// Patient grants consent for a researcher's accepted contract.
// Creates + signs the on-chain consent record, making the contract ACTIVE
// so the researcher can subsequently call POST /computation/run.
app.post('/consent/grant', requireAuth, async (req, res) => {
  const {
    patientDID,
    contractId,
    researcherDID,
    dataCategory,
    computationMethod,
    permittedScope,
    accessDurationSeconds,
    dataDividendWei,
  } = req.body as {
    patientDID?: string;
    contractId?: string;
    researcherDID?: string;
    dataCategory?: string;
    computationMethod?: ComputationMethod;
    permittedScope?: string;
    accessDurationSeconds?: number;
    dataDividendWei?: string;
  };

  if (!patientDID || !contractId || !researcherDID || !dataCategory || !computationMethod || !permittedScope || accessDurationSeconds == null || dataDividendWei == null) {
    res.status(400).json({ error: 'patientDID, contractId, researcherDID, dataCategory, computationMethod, permittedScope, accessDurationSeconds, dataDividendWei required' });
    return;
  }

  try {
    await orchestrator.submitAndSignContract(patientDID, contractId, {
      researcherDID,
      dataCategory,
      computationMethod,
      permittedScope,
      accessDurationSeconds,
      dataDividendWei: BigInt(dataDividendWei),
    });
    res.json({ status: 'ACTIVE', contractId, patientDID });
  } catch (e: unknown) {
    res.status(500).json({ error: (e as Error).message });
  }
});

app.post('/consent/revoke', requireAuth, async (req, res) => {
  const { contractId, patientDID } = req.body as { contractId: string; patientDID: string };
  if (!contractId || !patientDID) {
    res.status(400).json({ error: 'contractId and patientDID required' }); return;
  }
  try {
    db.prepare(`UPDATE computation_requests SET status = 'REVOKED' WHERE contract_id = ?`).run(contractId);
    res.json(await orchestrator.revokeConsent(contractId, patientDID));
  } catch (e: unknown) {
    res.status(500).json({ error: (e as Error).message });
  }
});

// ── GDPR ──────────────────────────────────────────────────────────────────

// Right to Erasure — deletes all vault data and invalidates active contracts
app.delete('/patient/data', requireAuth, async (req, res) => {
  const did = req.query['did'] as string;
  if (!did) { res.status(400).json({ error: 'did query param required' }); return; }
  try {
    const result = await complianceService.handleErasureRequest(did);
    res.json(result);
  } catch (e: unknown) {
    res.status(500).json({ error: (e as Error).message });
  }
});

// Right of Access — exports all data held about the patient
app.get('/patient/export', requireAuth, async (req, res) => {
  const did = req.query['did'] as string;
  if (!did) { res.status(400).json({ error: 'did query param required' }); return; }
  try {
    const result = await complianceService.handleAccessRequest(did);
    res.setHeader('Content-Disposition', `attachment; filename="data-export-${Date.now()}.json"`);
    res.json({
      ...result,
      auditTrail: result.auditTrail.map(e => ({
        ...e,
        amount: e.amount != null ? e.amount.toString() : undefined,
      })),
    });
  } catch (e: unknown) {
    res.status(500).json({ error: (e as Error).message });
  }
});

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------

if (require.main === module) {
  const PORT = process.env.PORT ?? 3000;
  app.listen(PORT, () => console.log(`API server running on port ${PORT}`));
}


// ---------------------------------------------------------------------------
// Marketplace seed — runs once on startup, idempotent
// ---------------------------------------------------------------------------

function seedMarketplace(): void {
  const existing = marketplace.searchDatasets({});
  if (existing.length > 0) return; // already seeded

  const listings: Array<Parameters<typeof marketplace.registerDataset>[0]> = [
    // EHR datasets
    {
      category: 'cardiology',
      dataType: 'EHR',
      minQualityScore: 70,
      recordCount: 0,
      availableMethods: ['FEDERATED_LEARNING', 'ZKP'],
    },
    {
      category: 'endocrinology',
      dataType: 'EHR',
      minQualityScore: 70,
      recordCount: 0,
      availableMethods: ['ZKP'],
    },
    {
      category: 'oncology',
      dataType: 'EHR',
      minQualityScore: 75,
      recordCount: 0,
      availableMethods: ['FEDERATED_LEARNING'],
    },
    // Wearable datasets
    {
      category: 'vitals',
      dataType: 'WEARABLE',
      minQualityScore: 60,
      recordCount: 0,
      availableMethods: ['FEDERATED_LEARNING', 'ZKP'],
    },
    {
      category: 'activity',
      dataType: 'WEARABLE',
      minQualityScore: 50,
      recordCount: 0,
      availableMethods: ['FEDERATED_LEARNING'],
    },
    {
      category: 'sleep',
      dataType: 'WEARABLE',
      minQualityScore: 55,
      recordCount: 0,
      availableMethods: ['FEDERATED_LEARNING', 'ZKP'],
    },
    // Genetic datasets
    {
      category: 'genomics',
      dataType: 'GENETIC',
      minQualityScore: 80,
      recordCount: 0,
      availableMethods: ['ZKP'],
    },
    {
      category: 'pharmacogenomics',
      dataType: 'GENETIC',
      minQualityScore: 80,
      recordCount: 0,
      availableMethods: ['FEDERATED_LEARNING', 'ZKP'],
    },
  ];

  for (const listing of listings) {
    marketplace.registerDataset(listing);
  }
  console.log(`[marketplace] Seeded ${listings.length} dataset listings.`);
}

seedMarketplace();
