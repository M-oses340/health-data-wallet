# Health Data Monetization Platform

A full-stack, privacy-preserving platform that lets patients own, control, and earn from their health data — while giving researchers compliant, consent-gated access to anonymized datasets.

---

## Architecture Overview

```
health-data-wallet/
├── packages/
│   ├── api/          # TypeScript/Node.js backend (Express)
│   ├── app/          # Flutter mobile app (iOS + Android)
│   ├── contracts/    # Solidity smart contracts (Hardhat)
│   ├── anonymizer/   # Python PII anonymization service (Presidio)
│   └── sdk/          # Shared TypeScript types
├── package.json      # npm workspaces root
└── README.md
```

### How the pieces connect

```
Flutter App
    │
    ▼
Express API  ──────────────────────────────────────────────────────────────┐
    │                                                                       │
    ├── PatientProfileRepository   (patient identity + consent state)      │
    ├── DataVaultService           (AES-256-GCM + ECIES → IPFS via Helia)  │
    ├── ComputationEngine          (Federated Learning / ZKP dispatch)     │
    ├── MarketplaceService         (dataset discovery + contract creation) │
    ├── WalletService              (ETH balance + dividend tracking)       │
    ├── AuditTrailService          (immutable event log)                   │
    ├── ComplianceService          (HIPAA / GDPR rule engine)              │
    └── PlatformOrchestrator       (end-to-end workflow coordinator)       │
                                                                            │
Python Anonymizer ◄─────────────────────────────────────────────────────── ┘
    │  (Presidio NLP — strips PII before data leaves the vault)
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
| Backend | Node.js, TypeScript, Express 5 |
| Storage | IPFS (Helia + UnixFS), local blockstore/datastore |
| Encryption | AES-256-GCM (data), ECIES (key wrapping) |
| Smart Contracts | Solidity ^0.8.24, Hardhat, Ethers.js |
| Anonymization | Python 3, Microsoft Presidio, spaCy |
| Testing | Jest + fast-check (PBT), Pytest + Hypothesis, Hardhat tests |

---

## Prerequisites

- Node.js >= 18
- npm >= 9
- Flutter >= 3.0
- Python >= 3.10
- pip / virtualenv

---

## Getting Started

### 1. Install dependencies

```bash
# Root (API + contracts + SDK)
npm install

# Python anonymizer
cd packages/anonymizer
pip install -r requirements.txt
python -m spacy download en_core_web_lg
```

### 2. Run the API

```bash
cd packages/api
npm run build
node dist/index.js
# Listens on http://localhost:3000
```

### 3. Start the local blockchain

Open a dedicated terminal:

```bash
cd packages/contracts
npx hardhat node
```

### 4. Deploy contracts

In a second terminal:

```bash
cd packages/contracts
npx hardhat run scripts/deploy.ts --network localhost
```

Deployed addresses are saved to `packages/contracts/deployed-addresses.json`.

### 5. Run the Flutter app

```bash
cd packages/app
flutter pub get
flutter run
```

---

## Smart Contracts

### ConsentRegistry

Manages the full consent lifecycle between patients and researchers.

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

---

## On-chain Demo

With the Hardhat node running and contracts deployed:

```bash
cd packages/contracts
npx hardhat run scripts/interact.ts --network localhost
```

This runs the full lifecycle:

1. Researcher calls `createContract`
2. Patient calls `signContract`
3. Researcher escrows `0.1 ETH` via `DataEscrow`
4. `releaseDividend` — patient receives `0.1 ETH`, `DividendPaid` event emitted
5. Patient calls `revokeConsent` on a second contract
6. `processRevocationRefund` — researcher refunded `0.1 ETH`

---

## Data Vault

Health records are encrypted before leaving the device:

1. Data encrypted with AES-256-GCM (random key per record)
2. Encryption key wrapped with patient's ECIES public key
3. Ciphertext stored on IPFS via Helia — real CID returned
4. Metadata (IV, wrapped key, CID) stored in local sidecar map
5. Access requires a signed JWT token validated against the consent registry

---

## Anonymization Service

Before any data is shared with researchers, it passes through the Python anonymizer:

```bash
cd packages/anonymizer
python -m pytest tests/
```

Uses Microsoft Presidio with spaCy `en_core_web_lg` to detect and redact:
- Names, dates of birth, addresses
- Phone numbers, email addresses, SSNs
- Medical record numbers and other PHI

---

## Flutter App

### User flow

```
BiometricAuthPage
    │  (fingerprint / face ID)
    ▼
RoleSelectPage
    │
    ├── Patient → PatientShell
    │               ├── Payments tab  (earnings summary + history)
    │               └── Audit Trail   (timeline of all data events)
    │
    └── Researcher → ResearcherShell
                        ├── Datasets tab   (search + filter marketplace)
                        └── New Request    (submit computation contract)
```

### Features

- Biometric auth with animated pulse rings, elastic success, shake on failure
- Gradient headers with truncated DID / wallet address (tap to copy)
- Dark mode — follows system theme automatically
- Skeleton shimmer loaders while data fetches
- Pull-to-refresh on payments and audit trail
- Payment badge on tab icon showing unread count
- Color-coded timeline audit trail with event chips
- Live dividend preview card on the request form

---

## Running Tests

### API (TypeScript + property-based tests)

```bash
cd packages/api
npm test
# 142 tests passing
```

### Smart contracts

```bash
cd packages/contracts
npx hardhat test
# 18 contract tests passing
```

### Anonymizer (Python + Hypothesis PBT)

```bash
cd packages/anonymizer
python -m pytest tests/ -v
# 23 tests passing
```

---

## Environment Variables

Create `packages/api/.env`:

```env
PORT=3000
IPFS_BLOCKSTORE_PATH=./data/blocks
IPFS_DATASTORE_PATH=./data/datastore
```

Create `packages/contracts/.env`:

```env
PRIVATE_KEY=<deployer-private-key>
RPC_URL=http://127.0.0.1:8545
```

---

## Deployed Contract Addresses (local testnet)

| Contract | Address |
|---|---|
| ConsentRegistry | `0x5FbDB2315678afecb367f032d93F642f64180aa3` |
| DataEscrow | `0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512` |
| PaymentRouter | `0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0` |

---

## Repository

[https://github.com/M-oses340/health-data-wallet](https://github.com/M-oses340/health-data-wallet)

---

## License

MIT
