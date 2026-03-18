import * as crypto from 'crypto';
import { ethers } from 'ethers';

// Mock for @noble/secp256k1 (ESM-only — not parseable by Jest without transform)
// Uses ethers internally to produce real valid secp256k1 key material.

export const utils = {
  randomPrivateKey: (): Uint8Array => {
    return new Uint8Array(crypto.randomBytes(32));
  },
};

export function getPublicKey(privateKey: Uint8Array, compressed = true): Uint8Array {
  const privHex = '0x' + Buffer.from(privateKey).toString('hex');
  const signingKey = new ethers.SigningKey(privHex);
  const pubHex = compressed
    ? signingKey.compressedPublicKey   // 33 bytes, 0x02/0x03 prefix
    : signingKey.publicKey;            // 65 bytes, 0x04 prefix
  return new Uint8Array(Buffer.from(pubHex.slice(2), 'hex'));
}

export function getSharedSecret(
  privateKey: Uint8Array | Buffer,
  publicKey: Uint8Array | Buffer,
  _compressed = true,
): Uint8Array {
  // Use Node's built-in ECDH to compute the shared secret
  const ecdh = crypto.createECDH('secp256k1');
  ecdh.setPrivateKey(Buffer.from(privateKey));
  // publicKey is 65-byte uncompressed (0x04 prefix)
  const shared = ecdh.computeSecret(Buffer.from(publicKey));
  // Return as 65-byte uncompressed point: 0x04 + x(32) + y(32)
  // Node's computeSecret returns just the x coordinate (32 bytes), pad to match secp256k1 output
  return new Uint8Array(Buffer.concat([Buffer.from([0x04]), shared, Buffer.alloc(32)]));
}
