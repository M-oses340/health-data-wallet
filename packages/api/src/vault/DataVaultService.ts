/**
 * DataVaultService — AES-256-GCM encrypted vault with SQLite-backed persistence.
 *
 * Storage model:
 *  - Ciphertext + encryption metadata are stored in the `vault_records` SQLite table.
 *  - An in-process cache (Map) avoids redundant DB reads for hot records.
 *  - Plaintext is stored alongside ciphertext for FL use only (never exposed via API).
 *
 * Encryption:
 *  - AES-256-GCM with a random per-record symmetric key.
 *  - Symmetric key is ECIES-encrypted to the patient's secp256k1 public key.
 *
 * Requirements: 1.2, 1.4, 1.5, 1.6
 */
import * as crypto from 'crypto';
import * as secp from '@noble/secp256k1';
import { ethers } from 'ethers';
import { ContentReference, DataType } from '@health-data/sdk';
import { db } from '../db';

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

export interface SignedToken {
  cid: string;
  signature: string; // EIP-191 personal_sign over the CID string
}

export interface VaultRecord {
  cid: string;
  patientDID: string;
  dataType: DataType;
  uploadedAt: number;
}

// ---------------------------------------------------------------------------
// Internal metadata
// ---------------------------------------------------------------------------

interface VaultMeta {
  iv: Buffer;
  authTag: Buffer;
  encryptedKey: Buffer;
  patientDID: string;
  patientAddress: string;
  dataType: DataType;
  uploadedAt: number;
  ciphertext: Buffer;
  plaintext?: Buffer;
}

// ---------------------------------------------------------------------------
// DataVaultService
// ---------------------------------------------------------------------------

export class DataVaultService {
  /** Hot cache: CID → metadata (populated on first access or upload) */
  private readonly _cache = new Map<string, VaultMeta>();

  // ---------------------------------------------------------------------------
  // upload — encrypt, persist to SQLite, cache
  // Requirements: 1.2, 1.4, 1.6
  // ---------------------------------------------------------------------------

  async upload(
    data: Buffer,
    patientDID: string,
    patientPublicKey: string,
    dataType: DataType,
  ): Promise<ContentReference> {
    const symKey = crypto.randomBytes(32);
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv('aes-256-gcm', symKey, iv);
    const ciphertext = Buffer.concat([cipher.update(data), cipher.final()]);
    const authTag = cipher.getAuthTag();

    const encryptedKey = this._encryptKeyToPublicKey(symKey, patientPublicKey);
    const patientAddress = ethers.computeAddress('0x' + patientPublicKey);
    const cidStr = 'bafy' + crypto.createHash('sha256').update(ciphertext).digest('hex');
    const uploadedAt = Date.now();

    const meta: VaultMeta = {
      iv, authTag, encryptedKey, patientDID, patientAddress,
      dataType, uploadedAt, ciphertext, plaintext: data,
    };

    // Persist to SQLite (upsert — idempotent on same ciphertext)
    db.prepare(`
      INSERT OR IGNORE INTO vault_records
        (cid, patient_did, patient_address, data_type, uploaded_at,
         iv, auth_tag, encrypted_key, ciphertext, plaintext)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      cidStr, patientDID, patientAddress, dataType, uploadedAt,
      iv, authTag, encryptedKey, ciphertext, data,
    );

    this._cache.set(cidStr, meta);

    return {
      cid: cidStr,
      dataType,
      uploadedAt,
      encryptionKeyRef: `vault:${cidStr}:key`,
    };
  }

  // ---------------------------------------------------------------------------
  // retrieve — decrypt (load from DB if not cached)
  // Requirement: 1.5
  // ---------------------------------------------------------------------------

  async retrieve(
    cid: string,
    authToken: SignedToken,
    patientPrivateKey: string,
  ): Promise<Buffer> {
    const meta = this._authorise(cid, authToken);
    const symKey = this._decryptKeyWithPrivateKey(meta.encryptedKey, patientPrivateKey);
    const decipher = crypto.createDecipheriv('aes-256-gcm', symKey, meta.iv);
    decipher.setAuthTag(meta.authTag);
    return Buffer.concat([decipher.update(meta.ciphertext), decipher.final()]);
  }

  // ---------------------------------------------------------------------------
  // delete — remove from DB + cache
  // Requirement: 1.6
  // ---------------------------------------------------------------------------

  async delete(cid: string, authToken: SignedToken): Promise<void> {
    this._authorise(cid, authToken);
    db.prepare('DELETE FROM vault_records WHERE cid = ?').run(cid);
    this._cache.delete(cid);
  }

  exists(cid: string): boolean {
    if (this._cache.has(cid)) return true;
    return !!db.prepare('SELECT 1 FROM vault_records WHERE cid = ?').get(cid);
  }

  /** List all CIDs for a patient (lightweight — no ciphertext loaded). */
  listByPatient(patientDID: string): VaultRecord[] {
    const rows = db.prepare(
      'SELECT cid, patient_did, data_type, uploaded_at FROM vault_records WHERE patient_did = ? ORDER BY uploaded_at DESC'
    ).all(patientDID) as any[];
    return rows.map(r => ({
      cid: r.cid,
      patientDID: r.patient_did,
      dataType: r.data_type as DataType,
      uploadedAt: r.uploaded_at,
    }));
  }

  /**
   * Return decoded plaintext records for FL training.
   * Loads from DB if not in cache. Only JSON records with numeric fields included.
   */
  getPlaintextRecords(patientDID: string): Record<string, unknown>[] {
    const rows = db.prepare(
      'SELECT cid, plaintext FROM vault_records WHERE patient_did = ?'
    ).all(patientDID) as any[];

    const results: Record<string, unknown>[] = [];
    for (const row of rows) {
      try {
        const plain = row.plaintext as Buffer | null;
        if (!plain) continue;
        const parsed = JSON.parse(plain.toString('utf8'));
        if (parsed && typeof parsed === 'object') results.push(parsed);
      } catch { /* skip non-JSON */ }
    }
    return results;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  private _loadFromDB(cid: string): VaultMeta | undefined {
    const row = db.prepare('SELECT * FROM vault_records WHERE cid = ?').get(cid) as any;
    if (!row) return undefined;
    const meta: VaultMeta = {
      iv: Buffer.from(row.iv),
      authTag: Buffer.from(row.auth_tag),
      encryptedKey: Buffer.from(row.encrypted_key),
      patientDID: row.patient_did,
      patientAddress: row.patient_address,
      dataType: row.data_type as DataType,
      uploadedAt: row.uploaded_at,
      ciphertext: Buffer.from(row.ciphertext),
      plaintext: row.plaintext ? Buffer.from(row.plaintext) : undefined,
    };
    this._cache.set(cid, meta);
    return meta;
  }

  private _authorise(cid: string, token: SignedToken): VaultMeta {
    const meta = this._cache.get(cid) ?? this._loadFromDB(cid);
    if (!meta) throw new Error(`Vault record not found: ${cid}`);
    if (token.cid !== cid) throw new Error('401 Unauthorized: token CID mismatch');
    let signerAddress: string;
    try {
      signerAddress = ethers.verifyMessage(cid, token.signature);
    } catch {
      throw new Error('401 Unauthorized: invalid signature');
    }
    if (signerAddress.toLowerCase() !== meta.patientAddress.toLowerCase()) {
      throw new Error('401 Unauthorized: signer is not the record owner');
    }
    return meta;
  }

  /** ECIES key encapsulation — output: ephemeralPub(65)|iv(12)|authTag(16)|encKey(32) */
  private _encryptKeyToPublicKey(symKey: Buffer, recipientPublicKeyHex: string): Buffer {
    const ephemeralPriv = secp.utils.randomPrivateKey();
    const ephemeralPub = secp.getPublicKey(ephemeralPriv, false);
    const recipientPubBytes = Buffer.from(recipientPublicKeyHex, 'hex');
    const sharedPoint = secp.getSharedSecret(ephemeralPriv, recipientPubBytes, false);
    const wrappingKey = crypto
      .createHash('sha256')
      .update(Buffer.from(sharedPoint).subarray(1, 33))
      .digest();
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv('aes-256-gcm', wrappingKey, iv);
    const encryptedKey = Buffer.concat([cipher.update(symKey), cipher.final()]);
    const authTag = cipher.getAuthTag();
    return Buffer.concat([Buffer.from(ephemeralPub), iv, authTag, encryptedKey]);
  }

  /** ECIES key decapsulation */
  private _decryptKeyWithPrivateKey(encryptedKeyBlob: Buffer, privateKeyHex: string): Buffer {
    const ephemeralPub = encryptedKeyBlob.subarray(0, 65);
    const iv = encryptedKeyBlob.subarray(65, 77);
    const authTag = encryptedKeyBlob.subarray(77, 93);
    const encryptedKey = encryptedKeyBlob.subarray(93);
    const privBytes = Buffer.from(privateKeyHex, 'hex');
    const sharedPoint = secp.getSharedSecret(privBytes, ephemeralPub, false);
    const wrappingKey = crypto
      .createHash('sha256')
      .update(Buffer.from(sharedPoint).subarray(1, 33))
      .digest();
    const decipher = crypto.createDecipheriv('aes-256-gcm', wrappingKey, iv);
    decipher.setAuthTag(authTag);
    return Buffer.concat([decipher.update(encryptedKey), decipher.final()]);
  }
}
