# Health Data Monetization Platform

A full-stack, privacy-preserving platform that lets patients own, control, and earn from their health data — while giving researchers compliant, consent-gated access to anonymized datasets.

---

## Architecture Overview

```
health-data-wallet/
├── packages/
│   ├── api/          # TypeScript/Node.js backend (Express + SQLite)
│   ├── app/          # Flutter mobile app (iOS + Android)
│   ├── contracts/    # Solidity smart contracts (Hardhat)
│   ├── anonymizer/   # Python PII anonymization service (Presidio)
│   ├── fl-server/    # Python Flower federated learning server
│   └── sdk/          # Shared TypeScript types
├── docker-compose.yml
└── README.md
```

### How the pieces connect

```
Flutter App
    │
    ▼
Express API  ──────────────────────────────────────────────────────────────┐
    │                                                                       │
    ├── PatientProfileRepository   (SQLite — patient identity + consent)   │
    ├── DataVaultService           (AES-256-GCM + ECIES content store)     │
    ├── ComputationEngine          (FL / ZKP dispatch + vault data feed)   │
    ├── MarketplaceService         (SQLite — dataset discovery)            │
    ├── WalletService              (ETH balance + dividend tracking)       │
    ├── AuditTrailService          (SQLite — immutable event log)          │
    ├── ComplianceService          (HIPAA / GDPR rule engine)              │
    ├── ContractAdapters           (ethers.js wrappers — real or stub)     │
    └── PlatformOrchestrator       (end-to-end workflow coordinator)       │
                                                                            │
Python FL Server ◄──────────────────────────────────────────────────────── ┘
    │  POST /fl/run  { contractId, numClients, numRounds, patientData? }
    │  POST /anonymize  (Presidio NLP — strips PII before data leaves vault)
    ▼
Ethereum Smart Contracts (Hardhat / local testnet)
    ├── ConsentRegistry   — on-chain consent lifecycle
    ├── DataEscrow        — holds researcher funds until computation completes
    └── PaymentRouter     — releases dividends to patients, refunds on revocation
```

---

## Tech Stack

| Layer | Technology |
|---|---|
| Mobile | Flutter 3, BLoC, Dio, local_auth |
| Backend | Node.js 20, TypeScript, Express 5 |
| Persistence | SQLite via better-sqlite3 (WAL mode) |
| Encryption | AES-256-GCM (data), ECIES (key wrapping) |
| Smart Contracts | Solidity ^0.8.24, Hardhat, Ethers.js v6 |
| Anonymization | Python 3, Microsoft Presidio, spaCy en_core_web_lg |
| Federated Learning | Flower (flwr), scikit-learn, NumPy |
| Testing | Jest + fast-check (PBT), Pytest + Hypothesis, Hardhat tests |
| Containerisation | Docker, Docker Compose |

---

## Quick Start (Docker)

```bash
# Copy env template (optional — defaults work out of the box)
cp packages/api/.env.example packages/api/.env

# Build and start all services
docker compose up --build
```

Services start in dependency order: `hardhat` → `contracts-deploy` → `fl-server` → `api`.

| Service | URL | Notes |
|---|---|---|
| API | http://localhost:3000 | Express REST API |
| FL server + anonymizer | http://localhost:5001 | Flask + Flower + Presidio |
| Hardhat node | http://localhost:8545 | Local Ethereum testnet |

```bash
# Verify everything is healthy
curl http://localhost:3000/health      # {"status":"ok"}
curl http://localhost:5001/health      # {"status":"ok"}
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Stop everything (data persists in the api_data Docker volume)
docker compose down
```

> Note: the first build takes ~20 minutes — the FL server downloads the spaCy `en_core_web_lg` model (588 MB). Subsequent builds use Docker layer cache and complete in under 2 minutes.

### Persistent storage

The SQLite database is stored in the `api_data` Docker volume at `/app/data/platform.db`. Data survives container restarts. To wipe it:

```bash
docker compose down -v
```

### Smart contract auto-deploy

The `contracts-deploy` service runs `deploy.ts` against the local Hardhat node on every `docker compose up` and writes `deployed-addresses.json` into the API container. The API's `ContractAdapters` picks this up automatically — no manual deploy step needed.

---

## Manual Setup

### Prerequisites

- Node.js >= 18, npm >= 9
- Flutter >= 3.0
- Python >= 3.10

### 1. Install dependencies

```bash
npm install

cd packages/anonymizer
pip install -r requirements.txt
python -m spacy download en_core_web_lg
```

### 2. Run the API

```bash
npm run build --workspace=packages/api
node packages/api/dist/server.js
# Listens on http://localhost:3000
```

### 3. Start the local blockchain + deploy contracts

```bash
# Terminal 1
cd packages/contracts && npx hardhat node

# Terminal 2
cd packages/contracts && npx hardhat run scripts/deploy.ts --network localhost
# Writes deployed-addresses.json — API picks it up automatically
```

### 4. Start the FL server

```bash
cd packages/fl-server
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python3 src/app.py
# Listening on http://localhost:5001
```

### 5. Run the Flutter app

```bash
cd packages/app
flutter pub get
flutter run
```

---

## Environment Variables

`packages/api/.env`:

```env
PORT=3000
JWT_SECRET=dev-secret-change-in-prod
FL_SERVER_URL=http://localhost:5001
BLOCKCHAIN_RPC_URL=http://localhost:8545
DB_PATH=./data/platform.db
```

`packages/contracts/.env`:

```env
PRIVATE_KEY=<deployer-private-key>
RPC_URL=http://127.0.0.1:8545
```

---

## API Endpoints

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/health` | — | Liveness probe |
| POST | `/auth/register` | — | Register new patient — returns DID + JWT |
| POST | `/auth/login` | — | Login with DID — returns JWT |
| GET | `/patient/:did/payments` | Bearer | Payment history |
| GET | `/patient/:did/audit-trail` | Bearer | Full audit log |
| POST | `/vault/upload` | Bearer | Encrypt + anonymize + list data |
| GET | `/marketplace/datasets` | — | Search dataset listings (`?category=&dataType=`) |
| POST | `/marketplace/requests` | Bearer | Submit computation request (triggers FL or ZKP) |
| POST | `/consent/revoke` | Bearer | Revoke active consent contract |

### Example: full patient flow

```bash
# Register
PATIENT=$(curl -s -X POST http://localhost:3000/auth/register)
DID=$(echo $PATIENT | grep -o '"did":"[^"]*"' | cut -d'"' -f4)
TOKEN=$(echo $PATIENT | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

# Upload health data
DATA=$(echo -n '{"heartRate":72,"bp":"120/80"}' | base64)
curl -s -X POST http://localhost:3000/vault/upload \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "{\"patientDID\":\"$DID\",\"data\":\"$DATA\",\"dataType\":\"HEALTH_METRICS\",\"category\":\"vitals\"}"

# Browse marketplace
curl -s http://localhost:3000/marketplace/datasets

# Submit FL computation
curl -s -X POST http://localhost:3000/marketplace/requests \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"contractId":"contract-001"}'

# Audit trail
curl -s http://localhost:3000/patient/$DID/audit-trail \
  -H "Authorization: Bearer $TOKEN"
```

---

## Federated Learning

The FL server runs a Flower simulation in-process — no real network sockets needed. Raw patient data **never leaves** each client silo; only model parameters (logistic regression coefficients) are shared.

```
ComputationEngine
    │  POST /fl/run  { contractId, numClients, numRounds, patientData? }
    ▼
Flask bridge (port 5001)
    ▼
Flower simulation
    ├── HealthDataClient (patient-0)  ← real vault records or synthetic fallback
    ├── HealthDataClient (patient-1)
    └── HealthDataClient (patient-N)
         │  share only model weights
         ▼
    FedAvg aggregation → global model
         ▼
    { layerGradients, sampleCount, roundId, roundMetrics }
```

When `patientData` is provided (extracted from the vault by `IVaultDataProvider`), each client trains on real anonymized records. If a silo has fewer than 4 records, it falls back to synthetic data automatically.

If the FL server is unreachable, `ComputationEngine` falls back to simulated gradients so the consent-check and payment pipeline still works in dev/test.

---

## Smart Contracts

### ConsentRegistry

```
PENDING_SIGNATURE → ACTIVE → COMPLETED
                           → REVOKED
                           → EXPIRED
```

| Function | Who calls it | Description |
|---|---|---|
| `createContract` | Researcher | Proposes a consent contract |
| `signContract` | Patient | Activates the contract |
| `revokeConsent` | Patient | Revokes active consent |
| `expireContract` | Anyone | Marks expired contracts |
| `isConsentActive` | ComputationEngine | Gate check before computation |

### DataEscrow

Holds researcher funds in escrow until computation completes. Releases dividend to patient on success, refunds researcher on revocation.

### PaymentRouter

Routes ETH dividends from escrow to patient wallets. Emits `DividendPaid` events consumed by the audit trail.

### On-chain demo

```bash
cd packages/contracts
npx hardhat run scripts/interact.ts --network localhost
```

---

## Persistence (SQLite)

All platform state is stored in a single SQLite database (`better-sqlite3`, WAL mode):

| Table | Contents |
|---|---|
| `patient_profiles` | DID, wallet address, public key, data references |
| `marketplace_listings` | Category, data type, quality score, available methods |
| `audit_trail` | Immutable event log — consent, uploads, computations, payments |

The database path is controlled by `DB_PATH` (default: `./data/platform.db`).

---

## Running Tests

```bash
# API (Jest — 142 tests)
npm test --workspace=packages/api

# Smart contracts (Hardhat — 18 tests)
npx hardhat test --project packages/contracts

# Anonymizer (Pytest + Hypothesis — 23 tests)
cd packages/anonymizer && python -m pytest tests/ -v

# FL server (Pytest — 14 tests)
cd packages/fl-server && python -m pytest tests/ -v
```

---

## Flutter App

### User flow

```
BiometricAuthPage → RoleSelectPage
    ├── Patient → PatientShell
    │               ├── Payments tab  (earnings + history)
    │               └── Audit Trail   (timeline of all data events)
    └── Researcher → ResearcherShell
                        ├── Datasets tab   (search + filter marketplace)
                        └── New Request    (submit computation contract)
```

The `ApiClient` (`packages/app/lib/core/api_client.dart`) connects to the live API. Set the base URL at build time:

```bash
flutter run --dart-define=API_URL=http://your-api-host:3000
```

---

## CI/CD

GitHub Actions runs 6 parallel jobs on every push to `main`:

| Job | What it tests |
|---|---|
| API Tests | Jest — 142 TypeScript tests |
| Contract Tests | Hardhat — 18 Solidity tests |
| Anonymizer Tests | Pytest + Hypothesis — 23 Python tests |
| Flutter Tests | `flutter analyze` + `flutter test` |
| Docker Smoke Test | Full `docker compose up` + register → upload → FL → hardhat |
| FL Server Tests | Pytest — 14 FL server tests |

---

## Repository

[https://github.com/M-oses340/health-data-wallet](https://github.com/M-oses340/health-data-wallet)

---

## License

MIT
