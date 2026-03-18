/**
 * db.ts — SQLite persistence layer (better-sqlite3).
 * Single shared database instance for the API process.
 * DB file path: process.env.DB_PATH ?? './data/platform.db'
 */
import Database from 'better-sqlite3';
import * as fs from 'fs';
import * as path from 'path';

const dbPath = process.env.DB_PATH ?? path.join(process.cwd(), 'data', 'platform.db');
fs.mkdirSync(path.dirname(dbPath), { recursive: true });

export const db: Database.Database = new Database(dbPath);
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

// ---------------------------------------------------------------------------
// Schema
// ---------------------------------------------------------------------------

db.exec(`
  CREATE TABLE IF NOT EXISTS patient_profiles (
    did                       TEXT PRIMARY KEY,
    wallet_address            TEXT NOT NULL,
    public_key                TEXT NOT NULL,
    registered_at             INTEGER NOT NULL,
    minimum_quality_threshold INTEGER NOT NULL DEFAULT 60,
    data_references           TEXT NOT NULL DEFAULT '[]'
  );

  CREATE TABLE IF NOT EXISTS researcher_profiles (
    did            TEXT PRIMARY KEY,
    wallet_address TEXT NOT NULL,
    public_key     TEXT NOT NULL,
    registered_at  INTEGER NOT NULL,
    organisation   TEXT NOT NULL DEFAULT ''
  );

  CREATE TABLE IF NOT EXISTS marketplace_listings (
    listing_id        TEXT PRIMARY KEY,
    category          TEXT NOT NULL,
    data_type         TEXT NOT NULL,
    min_quality_score INTEGER NOT NULL,
    record_count      INTEGER NOT NULL,
    available_methods TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS computation_requests (
    request_id        TEXT PRIMARY KEY,
    contract_id       TEXT NOT NULL UNIQUE,
    researcher_did    TEXT NOT NULL,
    data_category     TEXT NOT NULL,
    computation_method TEXT NOT NULL,
    permitted_scope   TEXT NOT NULL,
    access_duration   INTEGER NOT NULL,
    data_dividend_wei TEXT NOT NULL,
    status            TEXT NOT NULL DEFAULT 'ACCEPTED',
    created_at        INTEGER NOT NULL
  );

  CREATE TABLE IF NOT EXISTS audit_trail (
    entry_id           TEXT PRIMARY KEY,
    patient_did        TEXT NOT NULL,
    event_type         TEXT NOT NULL,
    contract_id        TEXT,
    data_ref           TEXT,
    computation_method TEXT,
    amount             TEXT,
    timestamp          INTEGER NOT NULL,
    on_chain_tx_hash   TEXT NOT NULL
  );

  CREATE INDEX IF NOT EXISTS idx_audit_patient ON audit_trail(patient_did);

  CREATE TABLE IF NOT EXISTS vault_records (
    cid             TEXT PRIMARY KEY,
    patient_did     TEXT NOT NULL,
    patient_address TEXT NOT NULL,
    data_type       TEXT NOT NULL,
    uploaded_at     INTEGER NOT NULL,
    iv              BLOB NOT NULL,
    auth_tag        BLOB NOT NULL,
    encrypted_key   BLOB NOT NULL,
    ciphertext      BLOB NOT NULL,
    plaintext       BLOB
  );

  CREATE INDEX IF NOT EXISTS idx_vault_patient ON vault_records(patient_did);
`);
