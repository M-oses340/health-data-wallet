/**
 * Unit tests for DataVaultService.
 * Requirements: 1.2, 1.4, 1.5, 1.6
 */
import { ethers } from 'ethers';
import * as secp from '@noble/secp256k1';
import { DataVaultService, SignedToken } from './DataVaultService';
import { DataType } from '@health-data/sdk';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeKeyPair() {
  const privBytes = secp.utils.randomPrivateKey();
  const pubBytes = secp.getPublicKey(privBytes, false);
  return {
    privateKey: Buffer.from(privBytes).toString('hex'),
    publicKey: Buffer.from(pubBytes).toString('hex'),
    address: ethers.computeAddress('0x' + Buffer.from(pubBytes).toString('hex')),
  };
}

async function makeToken(cid: string, privateKeyHex: string): Promise<SignedToken> {
  const wallet = new ethers.Wallet('0x' + privateKeyHex);
  const signature = await wallet.signMessage(cid);
  return { cid, signature };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('DataVaultService', () => {
  let vault: DataVaultService;
  let patient: ReturnType<typeof makeKeyPair>;
  const plaintext = Buffer.from('{"heartRate":72,"bloodPressure":"120/80"}');

  beforeEach(() => {
    vault = new DataVaultService();
    patient = makeKeyPair();
  });

  // --- upload ---

  it('upload returns a ContentReference with a non-empty CID', async () => {
    const ref = await vault.upload(plaintext, 'did:ethr:0xabc', patient.publicKey, 'EHR');
    expect(ref.cid).toBeTruthy();
    expect(ref.dataType).toBe('EHR');
    expect(ref.uploadedAt).toBeGreaterThan(0);
  });

  it('upload stores the record (exists returns true)', async () => {
    const ref = await vault.upload(plaintext, 'did:ethr:0xabc', patient.publicKey, 'EHR');
    expect(vault.exists(ref.cid)).toBe(true);
  });

  it('same plaintext uploaded twice produces different CIDs (random IV)', async () => {
    const ref1 = await vault.upload(plaintext, 'did:ethr:0xabc', patient.publicKey, 'EHR');
    const ref2 = await vault.upload(plaintext, 'did:ethr:0xabc', patient.publicKey, 'EHR');
    expect(ref1.cid).not.toBe(ref2.cid);
  });

  it('supports all three DataType values', async () => {
    const types: DataType[] = ['EHR', 'WEARABLE', 'GENETIC'];
    for (const dt of types) {
      const ref = await vault.upload(plaintext, 'did:ethr:0xabc', patient.publicKey, dt);
      expect(ref.dataType).toBe(dt);
    }
  });

  // --- retrieve (round-trip) ---

  it('retrieve returns the original plaintext after upload', async () => {
    const ref = await vault.upload(plaintext, 'did:ethr:0xabc', patient.publicKey, 'EHR');
    const token = await makeToken(ref.cid, patient.privateKey);
    const result = await vault.retrieve(ref.cid, token, patient.privateKey);
    expect(result).toEqual(plaintext);
  });

  it('retrieve works for WEARABLE data type', async () => {
    const data = Buffer.from('{"steps":10000}');
    const ref = await vault.upload(data, 'did:ethr:0xabc', patient.publicKey, 'WEARABLE');
    const token = await makeToken(ref.cid, patient.privateKey);
    const result = await vault.retrieve(ref.cid, token, patient.privateKey);
    expect(result).toEqual(data);
  });

  it('retrieve works for GENETIC data type', async () => {
    const data = Buffer.from('ATCGATCG');
    const ref = await vault.upload(data, 'did:ethr:0xabc', patient.publicKey, 'GENETIC');
    const token = await makeToken(ref.cid, patient.privateKey);
    const result = await vault.retrieve(ref.cid, token, patient.privateKey);
    expect(result).toEqual(data);
  });

  // --- access control (Requirement 1.5) ---

  it('retrieve throws 401 when token is signed by a different key', async () => {
    const attacker = makeKeyPair();
    const ref = await vault.upload(plaintext, 'did:ethr:0xabc', patient.publicKey, 'EHR');
    const badToken = await makeToken(ref.cid, attacker.privateKey);
    await expect(vault.retrieve(ref.cid, badToken, patient.privateKey)).rejects.toThrow(/401/);
  });

  it('retrieve throws 401 when token CID does not match requested CID', async () => {
    const ref = await vault.upload(plaintext, 'did:ethr:0xabc', patient.publicKey, 'EHR');
    const token: SignedToken = { cid: 'wrong-cid', signature: '0x00' };
    await expect(vault.retrieve(ref.cid, token, patient.privateKey)).rejects.toThrow(/401/);
  });

  it('retrieve throws 401 when signature is malformed', async () => {
    const ref = await vault.upload(plaintext, 'did:ethr:0xabc', patient.publicKey, 'EHR');
    const badToken: SignedToken = { cid: ref.cid, signature: '0xdeadbeef' };
    await expect(vault.retrieve(ref.cid, badToken, patient.privateKey)).rejects.toThrow(/401/);
  });

  it('retrieve throws when CID does not exist', async () => {
    const token = await makeToken('nonexistent', patient.privateKey);
    await expect(vault.retrieve('nonexistent', token, patient.privateKey)).rejects.toThrow(/not found/i);
  });

  // --- delete (Requirement 1.6) ---

  it('delete removes the record from the vault', async () => {
    const ref = await vault.upload(plaintext, 'did:ethr:0xabc', patient.publicKey, 'EHR');
    const token = await makeToken(ref.cid, patient.privateKey);
    await vault.delete(ref.cid, token);
    expect(vault.exists(ref.cid)).toBe(false);
  });

  it('delete throws 401 when token is signed by a different key', async () => {
    const attacker = makeKeyPair();
    const ref = await vault.upload(plaintext, 'did:ethr:0xabc', patient.publicKey, 'EHR');
    const badToken = await makeToken(ref.cid, attacker.privateKey);
    await expect(vault.delete(ref.cid, badToken)).rejects.toThrow(/401/);
  });

  it('retrieve throws after deletion', async () => {
    const ref = await vault.upload(plaintext, 'did:ethr:0xabc', patient.publicKey, 'EHR');
    const token = await makeToken(ref.cid, patient.privateKey);
    await vault.delete(ref.cid, token);
    const token2 = await makeToken(ref.cid, patient.privateKey);
    await expect(vault.retrieve(ref.cid, token2, patient.privateKey)).rejects.toThrow(/not found/i);
  });
});
