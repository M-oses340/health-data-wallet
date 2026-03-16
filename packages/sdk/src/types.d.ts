/**
 * Shared TypeScript types for the Health Data Monetization Platform.
 * Requirements: 1.1, 1.2, 1.4, 3.1, 4.1, 5.1
 */
/** Supported health data source types (Requirement 1.6) */
export type DataType = 'EHR' | 'WEARABLE' | 'GENETIC';
/** Privacy-preserving computation methods (Requirement 4.1) */
export type ComputationMethod = 'FEDERATED_LEARNING' | 'ZKP';
/** Smart contract lifecycle states (Requirement 3.1) */
export type ContractStatus = 'PENDING_SIGNATURE' | 'ACTIVE' | 'EXPIRED' | 'REVOKED' | 'COMPLETED';
/** Computation job execution states (Requirement 4.1) */
export type JobStatus = 'PENDING' | 'RUNNING' | 'COMPLETED' | 'FAILED' | 'REJECTED';
/** Audit trail event categories (Requirement 6.1) */
export type AuditEventType = 'CONSENT_GRANTED' | 'CONSENT_REVOKED' | 'COMPUTATION_STARTED' | 'COMPUTATION_COMPLETED' | 'DIVIDEND_PAID' | 'DATA_ANONYMIZED' | 'CONTRACT_EXPIRED';
/**
 * Content-addressed reference to an encrypted vault record.
 * Requirement 1.4 — Data_Vault returns a CID to the Health_Data_Wallet.
 */
export interface ContentReference {
    /** IPFS content identifier */
    cid: string;
    /** Health data source type */
    dataType: DataType;
    /** Unix timestamp of upload */
    uploadedAt: number;
    /** Reference to the encryption key used */
    encryptionKeyRef: string;
}
/**
 * Patient-controlled digital wallet.
 * Requirement 1.1 — unique key pair; Requirement 1.3 — DID provisioning.
 */
export interface HealthDataWallet {
    /** W3C Decentralized Identifier */
    did: string;
    /** secp256k1 public key (hex) */
    publicKey: string;
    /** CIDs pointing to encrypted vault records */
    dataReferences: ContentReference[];
}
/**
 * Immutable on-chain consent record.
 * Requirement 3.3 — recorded when patient signs a Smart Contract.
 */
export interface ConsentRecord {
    /** bytes32 hex contract identifier */
    contractId: string;
    /** Patient EVM wallet address */
    patientWallet: string;
    /** Researcher EVM wallet address */
    researcherWallet: string;
    /** Dataset category (e.g. "cardiovascular") */
    dataCategory: string;
    /** Permitted use scope description */
    permittedScope: string;
    /** Access duration in seconds */
    accessDuration: number;
    /** Agreed Data Dividend in wei */
    dataDividend: bigint;
    /** Computation method for this contract */
    computationMethod: ComputationMethod;
    /** Unix timestamp of contract creation */
    createdAt: number;
    /** Unix timestamp when access expires */
    expiresAt: number;
    /** Whether the consent is currently active */
    active: boolean;
}
/**
 * Full smart contract state including lifecycle metadata.
 * Requirement 3.1 — contract specifies scope, duration, dividend, method.
 */
export interface ContractState {
    /** bytes32 hex contract identifier */
    contractId: string;
    /** Patient W3C DID */
    patientDID: string;
    /** Researcher W3C DID */
    researcherDID: string;
    /** Current contract lifecycle status */
    status: ContractStatus;
    /** The on-chain consent record */
    consentRecord: ConsentRecord;
    /** Escrowed amount in wei */
    escrowedAmount: bigint;
    /** Unix timestamp of contract creation */
    createdAt: number;
    /** Unix timestamp when patient signed (undefined until signed) */
    signedAt?: number;
    /** Unix timestamp when access expires */
    expiresAt: number;
    /** Unix timestamp of revocation (undefined unless revoked) */
    revokedAt?: number;
    /** Unix timestamp of completion (undefined unless completed) */
    completedAt?: number;
}
/**
 * Immutable on-chain audit trail entry.
 * Requirement 6.1 — every consent, computation, and payment event is recorded.
 */
export interface AuditTrailEntry {
    /** Unique entry identifier */
    entryId: string;
    /** Patient W3C DID this entry belongs to */
    patientDID: string;
    /** Type of platform event */
    eventType: AuditEventType;
    /** Associated contract ID (if applicable) */
    contractId?: string;
    /** Associated data reference CID (if applicable) */
    dataRef?: string;
    /** Computation method used (if applicable) */
    computationMethod?: ComputationMethod;
    /** Payment amount in wei (if applicable) */
    amount?: bigint;
    /** Unix timestamp of the event */
    timestamp: number;
    /** On-chain transaction hash for this entry */
    onChainTxHash: string;
}
/**
 * Data Dividend payment record.
 * Requirement 5.5 — patients can query their complete payment history.
 */
export interface DataDividendRecord {
    /** On-chain transaction hash */
    transactionHash: string;
    /** Associated contract ID */
    contractId: string;
    /** Patient EVM wallet address that received the payment */
    patientWallet: string;
    /** Amount paid in wei */
    amount: bigint;
    /** Unix timestamp of payment */
    paidAt: number;
    /** Computation method that triggered the payment */
    computationMethod: ComputationMethod;
}
/**
 * Researcher computation request submitted to the marketplace.
 * Requirement 7.3 — must specify all required fields.
 */
export interface ComputationRequest {
    /** Researcher W3C DID */
    researcherDID: string;
    /** Dataset category (e.g. "cardiovascular", "genomics") */
    dataCategory: string;
    /** Computation method requested */
    computationMethod: ComputationMethod;
    /** Permitted use scope description */
    permittedScope: string;
    /** Requested access duration in seconds */
    accessDurationSeconds: number;
    /** Offered Data Dividend in wei */
    dataDividendWei: bigint;
}
/**
 * Result of a completed privacy-preserving computation.
 * Requirement 4.6 — result reference and completion timestamp recorded on-chain.
 */
export interface ComputationResult {
    /** Computation job identifier */
    jobId: string;
    /** Associated contract ID */
    contractId: string;
    /**
     * Federated Learning model gradients only — raw data is never included.
     * Requirement 4.2
     */
    gradients?: ModelGradients;
    /**
     * Zero-Knowledge Proof — no raw data values exposed.
     * Requirement 4.3
     */
    proof?: ZKProof;
    /** Unix timestamp of computation completion */
    completedAt: number;
    /** On-chain transaction hash for the completion record */
    onChainTxHash: string;
}
/**
 * Model gradient payload for Federated Learning.
 * Contains ONLY gradient updates — never raw patient data.
 */
export interface ModelGradients {
    /** Model layer name to gradient tensor mapping */
    layerGradients: Record<string, number[]>;
    /** Number of training samples (no raw data) */
    sampleCount: number;
    /** Training round identifier */
    roundId: string;
}
/**
 * Zero-Knowledge Proof payload.
 * Verifiable by the researcher without exposing underlying data.
 */
export interface ZKProof {
    /** Serialized proof bytes (hex) */
    proof: string;
    /** Public signals used in verification */
    publicSignals: string[];
    /** Verification key reference */
    verificationKeyRef: string;
}
//# sourceMappingURL=types.d.ts.map