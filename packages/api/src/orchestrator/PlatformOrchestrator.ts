/**
 * PlatformOrchestrator — wires all platform services into end-to-end flows.
 *
 * Flows:
 *  A. Patient registration → wallet provisioning → data upload → anonymization → marketplace listing
 *  B. Researcher search → computation request → contract generation → patient signing
 *     → computation → dividend payment
 *  C. Consent revocation → terminate computation → escrow refund → audit entry
 *  D. Contract expiry watcher → auto-revoke on expiry → audit entry
 *
 * Requirements: 1.4, 2.1, 3.1, 3.5, 3.6, 4.1, 5.1, 5.6, 6.1
 */
import { WalletService } from '../wallet/WalletService';
import { PatientProfileRepository, PatientProfile } from '../patient/PatientProfileRepository';
import { DataVaultService } from '../vault/DataVaultService';
import { MarketplaceService } from '../marketplace/MarketplaceService';
import { ComputationEngine } from '../computation/ComputationEngine';
import { AuditTrailService } from '../audit/AuditTrailService';
import { DataType, ComputationRequest, DataDividendRecord } from '@health-data/sdk';
import { db } from '../db';

// ---------------------------------------------------------------------------
// Supporting interfaces (thin adapters over on-chain contracts)
// ---------------------------------------------------------------------------

export interface IOnChainConsentManager {
  createContract(contractId: string, patientAddress: string, request: ComputationRequest): Promise<void>;
  signContract(contractId: string, patientDID: string): Promise<void>;
  revokeConsent(contractId: string, patientDID: string): Promise<void>;
  expireContract(contractId: string): Promise<void>;
  getExpiresAt(contractId: string): Promise<number>;
  getActiveContractIds(patientDID: string): Promise<string[]>;
}

export interface IOnChainPaymentRouter {
  processRevocationRefund(contractId: string): Promise<string>;
}

export interface IAnonymizerAdapter {
  deidentify(data: Buffer, patientDID: string, dataType: DataType, threshold: number): Promise<{
    success: boolean;
    qualityScore: number;
    anonymizedCid: string;
    rejectionReason?: string;
  }>;
}

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

export interface RegistrationResult {
  did: string;
  walletAddress: string;
  publicKey: string;
}

export interface UploadAndListResult {
  cid: string;
  qualityScore: number;
  listingId: string;
}

export interface ComputationFlowResult {
  jobId: string;
  contractId: string;
  onChainTxHash: string;
}

export interface RevocationResult {
  contractId: string;
  refundTxHash: string;
  auditEntryHash: string;
}

export interface ExpiryCheckResult {
  expired: string[];
}

// ---------------------------------------------------------------------------
// PlatformOrchestrator
// ---------------------------------------------------------------------------

export class PlatformOrchestrator {
  constructor(
    private readonly walletService: WalletService,
    private readonly profileRepo: PatientProfileRepository,
    private readonly vaultService: DataVaultService,
    private readonly anonymizer: IAnonymizerAdapter,
    private readonly marketplace: MarketplaceService,
    private readonly computationEngine: ComputationEngine,
    private readonly auditTrail: AuditTrailService,
    private readonly consentManager: IOnChainConsentManager,
    private readonly paymentRouter: IOnChainPaymentRouter,
  ) {}

  // ---------------------------------------------------------------------------
  // Flow A: Patient registration → wallet → upload → anonymize → list
  // Requirements: 1.1, 1.3, 1.4, 2.1
  // ---------------------------------------------------------------------------

  /**
   * Register a new patient: generate key pair, provision DID, store profile.
   */
  registerPatient(): RegistrationResult {
    const keyPair = this.walletService.generateKeyPair();
    const did = this.walletService.provisionDID(keyPair.publicKey);

    const profile: PatientProfile = {
      did,
      walletAddress: keyPair.address,
      publicKey: keyPair.publicKey,
      registeredAt: Date.now(),
      dataReferences: [],
      minimumQualityThreshold: 60,
    };
    this.profileRepo.create(profile);

    this.auditTrail.writeEntry({ patientDID: did, eventType: 'CONSENT_GRANTED' });

    return { did, walletAddress: keyPair.address, publicKey: keyPair.publicKey };
  }

  /**
   * Upload health data, anonymize it, and register a marketplace listing.
   * Requirement 1.4 — vault returns CID stored in wallet.
   * Requirement 2.1 — anonymizer processes data before marketplace listing.
   */
  async uploadAndList(
    patientDID: string,
    data: Buffer,
    dataType: DataType,
    category: string,
  ): Promise<UploadAndListResult> {
    const profile = this.profileRepo.findByDID(patientDID);
    if (!profile) throw new Error(`Patient not found: ${patientDID}`);

    // Upload to vault
    const ref = await this.vaultService.upload(data, patientDID, profile.publicKey, dataType);

    // Anonymize
    const anonResult = await this.anonymizer.deidentify(
      data, patientDID, dataType, profile.minimumQualityThreshold,
    );
    if (!anonResult.success) {
      throw new Error(`Anonymization rejected: ${anonResult.rejectionReason}`);
    }

    // Store CID in patient profile
    this.profileRepo.addDataReference(patientDID, ref);

    // Register a new marketplace listing for this upload
    const listing = this.marketplace.registerDataset({
      category,
      dataType,
      minQualityScore: anonResult.qualityScore,
      recordCount: 1,
      availableMethods: ['FEDERATED_LEARNING', 'ZKP'],
    });

    this.auditTrail.writeEntry({ patientDID, eventType: 'DATA_ANONYMIZED', dataRef: ref.cid });

    return { cid: ref.cid, qualityScore: anonResult.qualityScore, listingId: listing.listingId };
  }

  // ---------------------------------------------------------------------------
  // Flow B: Researcher request → contract → sign → compute → pay
  // Requirements: 3.1, 4.1, 5.1
  // ---------------------------------------------------------------------------

  async submitAndSignContract(
    patientDID: string,
    contractId: string,
    request: ComputationRequest,
  ): Promise<void> {
    const profile = this.profileRepo.findByDID(patientDID);
    if (!profile) throw new Error(`Patient not found: ${patientDID}`);

    await this.consentManager.createContract(contractId, profile.walletAddress, request);
    await this.consentManager.signContract(contractId, patientDID);

    db.prepare(`UPDATE computation_requests SET status = 'ACTIVE' WHERE contract_id = ?`).run(contractId);

    this.auditTrail.writeEntry({ patientDID, eventType: 'CONSENT_GRANTED', contractId });
  }

  async runComputation(contractId: string, patientDID: string): Promise<ComputationFlowResult> {
    const job = await this.computationEngine.initiateComputation(contractId);

    this.auditTrail.writeEntry({
      patientDID,
      eventType: 'COMPUTATION_COMPLETED',
      contractId,
      computationMethod: job.method,
    });

    // Look up the dividend amount from the computation request
    const row = db.prepare(
      `SELECT data_dividend_wei FROM computation_requests WHERE contract_id = ?`
    ).get(contractId) as { data_dividend_wei: string | null } | undefined;
    const dividendWei = row?.data_dividend_wei ? BigInt(row.data_dividend_wei) : undefined;

    this.auditTrail.writeEntry({
      patientDID,
      eventType: 'DIVIDEND_PAID',
      contractId,
      computationMethod: job.method,
      amount: dividendWei,
    });

    return {
      jobId: job.jobId,
      contractId,
      onChainTxHash: job.result!.onChainTxHash,
    };
  }

  // ---------------------------------------------------------------------------
  // Flow C: Consent revocation
  // Requirements: 3.6, 5.6
  // ---------------------------------------------------------------------------

  async revokeConsent(contractId: string, patientDID: string): Promise<RevocationResult> {
    await this.consentManager.revokeConsent(contractId, patientDID);
    const refundTxHash = await this.paymentRouter.processRevocationRefund(contractId);

    const entry = this.auditTrail.writeEntry({
      patientDID,
      eventType: 'CONSENT_REVOKED',
      contractId,
    });

    return { contractId, refundTxHash, auditEntryHash: entry.onChainTxHash };
  }

  // ---------------------------------------------------------------------------
  // Flow D: Contract expiry watcher
  // Requirement 3.5
  // ---------------------------------------------------------------------------

  async checkAndExpireContracts(
    patientDID: string,
    nowMs: number = Date.now(),
  ): Promise<ExpiryCheckResult> {
    const activeIds = await this.consentManager.getActiveContractIds(patientDID);
    const expired: string[] = [];

    for (const contractId of activeIds) {
      const expiresAt = await this.consentManager.getExpiresAt(contractId);
      if (nowMs >= expiresAt * 1000) {
        await this.consentManager.expireContract(contractId);
        this.auditTrail.writeEntry({
          patientDID,
          eventType: 'CONTRACT_EXPIRED',
          contractId,
        });
        expired.push(contractId);
      }
    }

    return { expired };
  }
}
