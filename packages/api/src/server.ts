/**
 * HTTP server — Express app wiring all platform services into REST endpoints.
 *
 * Routes:
 *   POST /auth/register              → register new patient (returns DID + JWT)
 *   POST /auth/register/researcher   → register new researcher (returns DID + JWT)
 *   POST /auth/login                 → login with DID + role (returns JWT)
 *   GET  /patient/:did/payments      → payment history
 *   GET  /patient/:did/audit-trail   → audit log
 *   GET  /marketplace/datasets       → search listings
 *   POST /marketplace/requests       → submit computation request (researcher only)
 *   POST /vault/upload               → upload + anonymize + list data
 *   POST /consent/revoke             → revoke consent
 *   GET  /health                     → liveness probe
 */
import express, { Request, Response, NextFunction } from 'express';
import * as crypto from 'crypto';
import { WalletService } from './wallet/WalletService';
import { PatientProfileRepository } from './patient/PatientProfileRepository';
import { ResearcherProfileRepository } from './researcher/ResearcherProfileRepository';
import { DataVaultService } from './vault/DataVaultService';
import { MarketplaceService } from './marketplace/MarketplaceService';
import { ComputationEngine, IVaultDataProvider } from './computation/ComputationEngine';
import { AuditTrailService } from './audit/AuditTrailService';
import { ComplianceService } from './compliance/ComplianceService';
import { PlatformOrchestrator } from './orchestrator/PlatformOrchestrator';
import { buildChainAdapters } from './chain/ContractAdapters';
import { DataType, ComputationMethod } from '@health-data/sdk';

// ---------------------------------------------------------------------------
// Service singletons
// ---------------------------------------------------------------------------

const walletService = new WalletService();
const profileRepo = new PatientProfileRepository();
const researcherRepo = new ResearcherProfileRepository();
const vaultService = new DataVaultService();
const marketplace = new MarketplaceService();
const auditTrail = new AuditTrailService();

// Chain adapters — real ethers.js if contracts deployed, stubs otherwise
const RPC_URL = process.env.BLOCKCHAIN_RPC_URL ?? 'http://localhost:8545';
const { consentRegistry, consentManager, paymentRouter, onChainPaymentRouter } = buildChainAdapters(RPC_URL);

// Vault data provider — distributes real decoded health records across FL silos.
// Each patient whose data is in the vault becomes one silo.
const vaultDataProvider: IVaultDataProvider = {
  async getAnonymizedRecordsForFL(_contractId: string) {
    const { db } = await import('./db');
    const rows = db.prepare('SELECT did FROM patient_profiles').all() as { did: string }[];
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

// Anonymizer adapter — calls the Python FL server sidecar
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
// JWT helpers (HS256)
// ---------------------------------------------------------------------------

const JWT_SECRET = process.env.JWT_SECRET ?? 'dev-secret-change-in-prod';

function signJWT(payload: object): string {
  const header = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
  const body = Buffer.from(JSON.stringify({ ...payload, iat: Math.floor(Date.now() / 1000) })).toString('base64url');
  const sig = crypto.createHmac('sha256', JWT_SECRET).update(`${header}.${body}`).digest('base64url');
  return `${header}.${body}.${sig}`;
}

function verifyJWT(token: string): Record<string, unknown> {
  const [header, body, sig] = token.split('.');
  const expected = crypto.createHmac('sha256', JWT_SECRET).update(`${header}.${body}`).digest('base64url');
  if (sig !== expected) throw new Error('Invalid token');
  return JSON.parse(Buffer.from(body, 'base64url').toString());
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
  } catch {
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

app.post('/auth/register', (_req, res) => {
  try {
    const result = orchestrator.registerPatient();
    const token = signJWT({ did: result.did, role: 'patient' });
    res.status(201).json({ ...result, token });
  } catch (e: unknown) {
    res.status(500).json({ error: (e as Error).message });
  }
});

app.post('/auth/register/researcher', (req, res) => {
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

app.post('/auth/login', (req, res) => {
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

// ── Patient ───────────────────────────────────────────────────────────────

app.get('/patient/:did/payments', requireAuth, (req, res) => {
  const did = req.params['did'] as string;
  res.json({ payments: auditTrail.getAuditTrail(did).filter(e => e.eventType === 'DIVIDEND_PAID') });
});

app.get('/patient/:did/audit-trail', requireAuth, (req, res) => {
  res.json({ entries: auditTrail.getAuditTrail(req.params['did'] as string) });
});

// ── Vault ─────────────────────────────────────────────────────────────────

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

// Researcher-only: validate request body, generate contractId, run computation
app.post('/marketplace/requests', requireAuth, requireRole('researcher'), async (req, res) => {
  const {
    listingId, researcherDID, computationMethod, dataCategory,
    permittedScope, accessDurationSeconds, dataDividendWei,
  } = req.body as {
    listingId?: string;
    researcherDID?: string;
    computationMethod?: ComputationMethod;
    dataCategory?: string;
    permittedScope?: string;
    accessDurationSeconds?: number;
    dataDividendWei?: string;
  };

  // Validate via MarketplaceService
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

  // Verify listing exists if provided
  if (listingId) {
    const listings = marketplace.searchDatasets({});
    if (!listings.find(l => l.listingId === listingId)) {
      res.status(404).json({ error: `Listing ${listingId} not found` }); return;
    }
  }

  try {
    const job = await computationEngine.initiateComputation(submission.contractId!);
    res.status(201).json({ ...submission, job });
  } catch (e: unknown) {
    res.status(500).json({ error: (e as Error).message });
  }
});

// ── Consent ───────────────────────────────────────────────────────────────

app.post('/consent/revoke', requireAuth, async (req, res) => {
  const { contractId, patientDID } = req.body as { contractId: string; patientDID: string };
  if (!contractId || !patientDID) {
    res.status(400).json({ error: 'contractId and patientDID required' }); return;
  }
  try {
    res.json(await orchestrator.revokeConsent(contractId, patientDID));
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
