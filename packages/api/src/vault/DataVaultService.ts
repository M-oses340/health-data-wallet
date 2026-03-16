/**
 * DataVaultService — encrypted in-memory vault with content-addressed storage.
 *
 * Design decisions:
 *  - Encryption: AES-256-GCM with a random per-record symmetric key.
 *    The symmetric key is ECIES-encrypted to the patient's secp256k1 public key
 *    so only the holder of the matching private key can decrypt.
 *  - CID: SHA-256 of the raw ciphertext bytes (content-addressed, like IPFS).
 *  - Access control: every retrieve/delete call must present a SignedToken whose
 *    message is the CID and whose signer address matches the patient's registered
 *    address.  Any other token is rejected with a 401-style error.
 *
 * Requirements: 1.2, 1.4, 1.5, 1.6
 */
import * as crypto from 'crypto';
import * as secp from '@noble/secp256k1';
import { ethers } from 'ethers';
import { ContentReference, DataType } from '@health-data/sdk';

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/**
 * A signed access token authorising vault operations on a specific CID.
 * The token message MUST be the CID string; the signature MUST be an
 * EIP-191 personal_sign produced by the patient's private key.
 */
export interface SignedToken {
  /** The CID this token authorises access to */
  cid: string;
  /** EIP-191 signature (hex, 0x-prefixed) */
  signature: string;
}

// ---------------------------------------------------------------------------
// Internal record stored in the vault
// ---------------------------------------------------------------------------

interface VaultRecord {
  /** AES-256-GCM ciphertext */
  ciphertext: Buffer;
  /** 12-byte AES-GCM IV */
  iv: Buffer;
  /** 16-byte AES-GCM auth tag */
  authTag: Buffer;
  /**
   * Symmetric key encrypted to the patient's public key via ECDH + AES-256-GCM.
   * Layout: ephemeralPubKey(65) | iv(12) | authTag(16) | encryptedKey(32)
   */
  encryptedKey: Buffer;
  /** Patient DID that owns this record */
  patientDID: string;
  /** Checksummed EVM address of the patient (derived from their public key) */
  patientAddress: string;
  /** Data type tag */
  dataType: DataType;
  /** Unix timestamp of upload */
  uploadedAt: number;
}

// ---------------------------------------------------------------------------
// DataVaultService
// ---------------------------------------------------------------------------

export class DataVaultService {
  /** In-memory store: CID → VaultRecord */
  private readonly store = new Map<string, VaultRecord>();

  /**
   * Encrypt and store health data.
   * Returns a ContentReference containing the CID and metadata.
   *
   * @param encryptedData  Raw (plaintext) health data buffer supplied by the patient.
   *                       The vault re-encrypts it with a fresh AES key.
   * @param patientDID     W3C DID of the owning patient.
   * @param patientPublicKey  65-byte uncompressed secp256k1 public key (hex, no 0x).
   * @param dataType       EHR | WEARABLE | GENETIC
   *
   * Requirements: 1.2, 1.4, 1.6
   */
  async upload(
    data: Buffer,
    patientDID: string,
    patientPublicKey: string,
    dataType: DataType,
  ): Promise<ContentReference> {
    // 1. Generate a fresh 256-bit symmetric key and encrypt the data
    const symKey = crypto.randomBytes(32);
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv('aes-256-gcm', symKey, iv);
    const ciphertext = Buffer.concat([cipher.update(data), cipher.final()]);
    const authTag = cipher.getAuthTag();

    // 2. Derive CID = SHA-256(ciphertext) — content-addressed like IPFS
    const cid = crypto.createHash('sha256').update(ciphertext).digest('hex');

    // 3. ECIES: encrypt the symmetric key to the patient's public key
    const encryptedKey = this._encryptKeyToPublicKey(symKey, patientPublicKey);

    // 4. Derive the patient's EVM address for access-control checks
    const patientAddress = ethers.computeAddress('0x' + patientPublicKey);

    // 5. Store the record
    this.store.set(cid, {
      ciphertext,
      iv,
      authTag,
      encryptedKey,
      patientDID,
      patientAddress,
      dataType,
      uploadedAt: Date.now(),
    });

    return {
      cid,
      dataType,
      uploadedAt: Date.now(),
      encryptionKeyRef: `vault:${cid}:key`,
    };
  }

  /**
   * Retrieve and decrypt a vault record.
   * Throws if the token is invalid or the CID does not exist.
   *
   * @param cid        Content identifier returned by upload().
   * @param authToken  Token signed by the patient's private key over the CID.
   * @param patientPrivateKey  32-byte private key (hex, no 0x) — used to decrypt the sym key.
   *
   * Requirements: 1.5
   */
  async retrieve(
    cid: string,
    authToken: SignedToken,
    patientPrivateKey: string,
  ): Promise<Buffer> {
    const record = this._authorise(cid, authToken);

    // Decrypt the symmetric key using the patient's private key
    const symKey = this._decryptKeyWithPrivateKey(record.encryptedKey, patientPrivateKey);

    // Decrypt the ciphertext
    const decipher = crypto.createDecipheriv('aes-256-gcm', symKey, record.iv);
    decipher.setAuthTag(record.authTag);
    return Buffer.concat([decipher.update(record.ciphertext), decipher.final()]);
  }

  /**
   * Delete a vault record.
   * Throws if the token is invalid or the CID does not exist.
   *
   * Requirements: 1.6
   */
  async delete(cid: string, authToken: SignedToken): Promise<void> {
    this._authorise(cid, authToken);
    this.store.delete(cid);
  }

  /**
   * Check whether a CID exists in the vault (no auth required — metadata only).
   */
  exists(cid: string): boolean {
    return this.store.has(cid);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /**
   * Verify the signed token and return the vault record.
   * Throws with a descriptive message on any auth failure.
   * Requirement 1.5 — reject all access without valid patient-signed token.
   */
  private _authorise(cid: string, token: SignedToken): VaultRecord {
    const record = this.store.get(cid);
    if (!record) {
      throw new Error(`Vault record not found: ${cid}`);
    }
    if (token.cid !== cid) {
      throw new Error('401 Unauthorized: token CID does not match requested CID');
    }
    let signerAddress: string;
    try {
      signerAddress = ethers.verifyMessage(cid, token.signature);
    } catch {
      throw new Error('401 Unauthorized: invalid signature');
    }
    if (signerAddress.toLowerCase() !== record.patientAddress.toLowerCase()) {
      throw new Error('401 Unauthorized: signer is not the record owner');
    }
    return record;
  }

  /**
   * ECIES key encapsulation: encrypt a 32-byte symmetric key to a secp256k1 public key.
   * Layout of output buffer: ephemeralPubKey(65) | iv(12) | authTag(16) | encryptedKey(32)
   */
  private _encryptKeyToPublicKey(symKey: Buffer, recipientPublicKeyHex: string): Buffer {
    // Generate ephemeral key pair
    const ephemeralPriv = secp.utils.randomPrivateKey();
    const ephemeralPub = secp.getPublicKey(ephemeralPriv, false); // uncompressed 65 bytes

    // ECDH shared secret
    const recipientPubBytes = Buffer.from(recipientPublicKeyHex, 'hex');
    const sharedPoint = secp.getSharedSecret(ephemeralPriv, recipientPubBytes, false);
    // Use SHA-256 of the x-coordinate as the wrapping key
    const wrappingKey = crypto
      .createHash('sha256')
      .update(Buffer.from(sharedPoint).subarray(1, 33)) // x-coordinate only
      .digest();

    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv('aes-256-gcm', wrappingKey, iv);
    const encryptedKey = Buffer.concat([cipher.update(symKey), cipher.final()]);
    const authTag = cipher.getAuthTag();

    return Buffer.concat([Buffer.from(ephemeralPub), iv, authTag, encryptedKey]);
  }

  /**
   * ECIES key decapsulation: decrypt the symmetric key using the patient's private key.
   */
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
