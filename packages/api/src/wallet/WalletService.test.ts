/**
 * Unit tests for WalletService.
 * Requirements: 1.1, 1.3
 */
import { ethers } from 'ethers';
import { WalletService, Transaction } from './WalletService';

const service = new WalletService();

// ---------------------------------------------------------------------------
// generateKeyPair
// ---------------------------------------------------------------------------

describe('WalletService.generateKeyPair', () => {
  it('returns a private key of 64 hex chars (32 bytes)', () => {
    const { privateKey } = service.generateKeyPair();
    expect(privateKey).toMatch(/^[0-9a-f]{64}$/);
  });

  it('returns an uncompressed public key of 130 hex chars (65 bytes)', () => {
    const { publicKey } = service.generateKeyPair();
    expect(publicKey).toMatch(/^04[0-9a-f]{128}$/);
  });

  it('returns a checksummed EVM address', () => {
    const { address } = service.generateKeyPair();
    expect(address).toMatch(/^0x[0-9a-fA-F]{40}$/);
    // ethers.getAddress throws if not checksummed
    expect(() => ethers.getAddress(address)).not.toThrow();
    expect(ethers.getAddress(address)).toBe(address);
  });

  it('produces unique key pairs on each call', () => {
    const kp1 = service.generateKeyPair();
    const kp2 = service.generateKeyPair();
    const kp3 = service.generateKeyPair();
    expect(kp1.privateKey).not.toBe(kp2.privateKey);
    expect(kp1.privateKey).not.toBe(kp3.privateKey);
    expect(kp2.privateKey).not.toBe(kp3.privateKey);
    expect(kp1.publicKey).not.toBe(kp2.publicKey);
  });
});

// ---------------------------------------------------------------------------
// provisionDID
// ---------------------------------------------------------------------------

describe('WalletService.provisionDID', () => {
  it('returns a DID starting with did:ethr:0x', () => {
    const { publicKey } = service.generateKeyPair();
    const did = service.provisionDID(publicKey);
    expect(did).toMatch(/^did:ethr:0x[0-9a-fA-F]{40}$/);
  });

  it('embeds a checksummed EVM address', () => {
    const { publicKey } = service.generateKeyPair();
    const did = service.provisionDID(publicKey);
    const address = did.replace('did:ethr:', '');
    expect(ethers.getAddress(address)).toBe(address);
  });

  it('accepts public key with or without 0x prefix', () => {
    const { publicKey } = service.generateKeyPair();
    const didWithout = service.provisionDID(publicKey);
    const didWith = service.provisionDID('0x' + publicKey);
    expect(didWithout).toBe(didWith);
  });

  it('is deterministic — same public key always yields same DID', () => {
    const { publicKey } = service.generateKeyPair();
    expect(service.provisionDID(publicKey)).toBe(service.provisionDID(publicKey));
  });

  it('DID address matches the address in the key pair', () => {
    const kp = service.generateKeyPair();
    const did = service.provisionDID(kp.publicKey);
    const addressFromDID = did.replace('did:ethr:', '');
    expect(addressFromDID).toBe(kp.address);
  });
});

// ---------------------------------------------------------------------------
// sign
// ---------------------------------------------------------------------------

describe('WalletService.sign', () => {
  const tx: Transaction = {
    contractId: '0xdeadbeef',
    data: { action: 'grant-consent' },
    timestamp: 1700000000000,
  };

  it('returns a 65-byte EIP-191 signature (132 hex chars + 0x)', () => {
    const { privateKey } = service.generateKeyPair();
    const { signature } = service.sign(tx, privateKey);
    expect(signature).toMatch(/^0x[0-9a-f]{130}$/i);
  });

  it('signerAddress is a checksummed EVM address', () => {
    const { privateKey } = service.generateKeyPair();
    const { signerAddress } = service.sign(tx, privateKey);
    expect(ethers.getAddress(signerAddress)).toBe(signerAddress);
  });

  it('recovered address from signature matches signerAddress', () => {
    const { privateKey } = service.generateKeyPair();
    const { transaction, signature, signerAddress } = service.sign(tx, privateKey);
    const recovered = ethers.verifyMessage(JSON.stringify(transaction), signature);
    expect(recovered).toBe(signerAddress);
  });

  it('signerAddress matches the address derived from the private key', () => {
    const kp = service.generateKeyPair();
    const { signerAddress } = service.sign(tx, kp.privateKey);
    expect(signerAddress).toBe(kp.address);
  });

  it('accepts private key with or without 0x prefix', () => {
    const { privateKey } = service.generateKeyPair();
    const s1 = service.sign(tx, privateKey);
    const s2 = service.sign(tx, '0x' + privateKey);
    expect(s1.signerAddress).toBe(s2.signerAddress);
    expect(s1.signature).toBe(s2.signature);
  });

  it('different transactions produce different signatures', () => {
    const { privateKey } = service.generateKeyPair();
    const tx2: Transaction = { ...tx, contractId: '0xcafebabe' };
    const s1 = service.sign(tx, privateKey);
    const s2 = service.sign(tx2, privateKey);
    expect(s1.signature).not.toBe(s2.signature);
  });
});
