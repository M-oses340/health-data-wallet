/**
 * WalletService — secp256k1 key pair generation, W3C DID provisioning, and transaction signing.
 * Requirements: 1.1, 1.3
 */
import * as secp from '@noble/secp256k1';
import { ethers } from 'ethers';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** secp256k1 key pair with hex-encoded keys */
export interface KeyPair {
  /** 32-byte private key (hex, no 0x prefix) */
  privateKey: string;
  /** 65-byte uncompressed public key (hex, no 0x prefix) */
  publicKey: string;
  /** Checksummed EVM address derived from the public key */
  address: string;
}

/** A transaction payload to be signed */
export interface Transaction {
  /** Unique contract or operation identifier */
  contractId: string;
  /** Arbitrary transaction data */
  data: unknown;
  /** Unix timestamp (ms) */
  timestamp: number;
}

/** A transaction with an attached EIP-191 personal_sign signature */
export interface SignedTransaction {
  transaction: Transaction;
  /** EIP-191 signature (hex, 0x-prefixed, 65 bytes) */
  signature: string;
  /** Checksummed EVM address of the signer */
  signerAddress: string;
}

// ---------------------------------------------------------------------------
// WalletService
// ---------------------------------------------------------------------------

export class WalletService {
  /**
   * Generate a fresh secp256k1 key pair.
   * Requirement 1.1 — each patient wallet gets a unique cryptographic key pair.
   */
  generateKeyPair(): KeyPair {
    const privateKeyBytes = secp.utils.randomPrivateKey();
    const publicKeyBytes = secp.getPublicKey(privateKeyBytes, false); // uncompressed

    const privateKey = Buffer.from(privateKeyBytes).toString('hex');
    const publicKey = Buffer.from(publicKeyBytes).toString('hex');
    const address = ethers.computeAddress('0x' + publicKey);

    return { privateKey, publicKey, address };
  }

  /**
   * Derive a W3C-compliant DID from a secp256k1 public key.
   * Format: `did:ethr:<checksummed-EVM-address>`
   * Requirement 1.3 — wallet is provisioned with a unique DID on registration.
   *
   * @param publicKey  65-byte uncompressed public key, hex (with or without 0x prefix)
   */
  provisionDID(publicKey: string): string {
    const normalized = publicKey.startsWith('0x') ? publicKey : '0x' + publicKey;
    const address = ethers.computeAddress(normalized);
    return `did:ethr:${address}`;
  }

  /**
   * Sign a transaction using EIP-191 personal_sign (Ethereum message signing).
   * The signature can be verified with `ethers.verifyMessage`.
   * Requirement 1.3 — wallet signs Smart Contract transactions on behalf of the patient.
   *
   * @param transaction  The transaction payload to sign
   * @param privateKey   32-byte private key, hex (with or without 0x prefix)
   */
  sign(transaction: Transaction, privateKey: string): SignedTransaction {
    const normalized = privateKey.startsWith('0x') ? privateKey : '0x' + privateKey;
    const wallet = new ethers.Wallet(normalized);
    const message = JSON.stringify(transaction);
    const signature = wallet.signMessageSync(message);

    return {
      transaction,
      signature,
      signerAddress: wallet.address,
    };
  }
}
