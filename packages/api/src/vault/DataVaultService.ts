/**
 * DataVaultService — AES-256-GCM encrypted vault backed by a real IPFS node (Helia).
 *
 * Storage model:
 *  - Ciphertext bytes are stored on IPFS via Helia UnixFS; the real content-addressed
 *    CID is returned by Helia and used as the record identifier.
 *  - Encryption metadata (iv, authTag, encryptedKey, patient info) is kept in a local
 *    sidecar Map keyed by CID string.  This metadata never leaves the node.
 *  - "Delete" unpins the block from the local Helia blockstore and drops the sidecar.
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
import { createHelia } from 'helia';
import { unixfs } from '@helia/unixfs';
import { CID } from 'multiformats/cid';
import { ContentReference, DataType } from '@health-data/sdk';
import type { Helia } from '@helia/interface';
import type { UnixFS } from '@helia/unixfs';

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

export interface SignedToken {
  cid: string;
  signature: string; // EIP-191 personal_sign over the CID string
}

// ---------------------------------------------------------------------------
// Internal sidecar metadata (never stored on IPFS)
// ---------------------------------------------------------------------------

interface VaultMeta {
  iv: Buffer;
  authTag: Buffer;
  encryptedKey: Buffer;
  patientDID: string;
  patientAddress: string;
  dataType: DataType;
  uploadedAt: number;
  ipfsCID: CID; // the real Helia CID object for unpin on delete
}

// ---------------------------------------------------------------------------
// DataVaultService
// ---------------------------------------------------------------------------

export class DataVaultService {
  private _helia: Helia | null = null;
  private _fs: UnixFS | null = null;

  /** Sidecar: CID string → encryption metadata */
  private readonly _meta = new Map<string, VaultMeta>();

  // ---------------------------------------------------------------------------
  // Lazy Helia initialisation
  // ---------------------------------------------------------------------------

  private async _node(): Promise<{ helia: Helia; fs: UnixFS }> {
    if (!this._helia) {
      this._helia = await createHelia();
      this._fs = unixfs(this._helia);
    }
    return { helia: this._helia, fs: this._fs! };
  }

  /** Gracefully stop the Helia node (call on process exit). */
  async stop(): Promise<void> {
    if (this._helia) {
      await this._helia.stop();
      this._helia = null;
      this._fs = null;
    }
  }

  // ---------------------------------------------------------------------------
  // upload — encrypt then pin to IPFS
  // Requirements: 1.2, 1.4, 1.6
  // ---------------------------------------------------------------------------

  async upload(
    data: Buffer,
    patientDID: string,
    patientPublicKey: string,
    dataType: DataType,
  ): Promise<ContentReference> {
    // 1. AES-256-GCM encrypt
    const symKey = crypto.randomBytes(32);
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv('aes-256-gcm', symKey, iv);
    const ciphertext = Buffer.concat([cipher.update(data), cipher.final()]);
    const authTag = cipher.getAuthTag();

    // 2. ECIES-encrypt the symmetric key to the patient's public key
    const encryptedKey = this._encryptKeyToPublicKey(symKey, patientPublicKey);

    // 3. Derive patient EVM address for access-control
    const patientAddress = ethers.computeAddress('0x' + patientPublicKey);

    // 4. Add ciphertext to IPFS — Helia returns a real content-addressed CID
    const { fs } = await this._node();
    const ipfsCID = await fs.addBytes(ciphertext);
    const cidStr = ipfsCID.toString();

    // 5. Store sidecar metadata locally
    this._meta.set(cidStr, {
      iv,
      authTag,
      encryptedKey,
      patientDID,
      patientAddress,
      dataType,
      uploadedAt: Date.now(),
      ipfsCID,
    });

    return {
      cid: cidStr,
      dataType,
      uploadedAt: Date.now(),
      encryptionKeyRef: `vault:${cidStr}:key`,
    };
  }

  // ---------------------------------------------------------------------------
  // retrieve — fetch from IPFS then decrypt
  // Requirement: 1.5
  // ---------------------------------------------------------------------------

  async retrieve(
    cid: string,
    authToken: SignedToken,
    patientPrivateKey: string,
  ): Promise<Buffer> {
    const meta = this._authorise(cid, authToken);
    const { fs } = await this._node();

    // Collect all chunks from IPFS
    const chunks: Uint8Array[] = [];
    for await (const chunk of fs.cat(meta.ipfsCID)) {
      chunks.push(chunk);
    }
    const ciphertext = Buffer.concat(chunks);

    // Decrypt symmetric key then data
    const symKey = this._decryptKeyWithPrivateKey(meta.encryptedKey, patientPrivateKey);
    const decipher = crypto.createDecipheriv('aes-256-gcm', symKey, meta.iv);
    decipher.setAuthTag(meta.authTag);
    return Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  }

  // ---------------------------------------------------------------------------
  // delete — unpin from local blockstore + drop sidecar
  // Requirement: 1.6
  // ---------------------------------------------------------------------------

  async delete(cid: string, authToken: SignedToken): Promise<void> {
    const meta = this._authorise(cid, authToken);
    const { helia } = await this._node();

    // Unpin so the block can be garbage-collected
    await helia.pins.rm(meta.ipfsCID);
    this._meta.delete(cid);
  }

  /** Check whether a CID is tracked in the sidecar (no auth required). */
  exists(cid: string): boolean {
    return this._meta.has(cid);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  private _authorise(cid: string, token: SignedToken): VaultMeta {
    const meta = this._meta.get(cid);
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
