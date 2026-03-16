/**
 * ComplianceService — scope enforcement middleware and GDPR handlers.
 *
 * Requirements: 3.7, 8.2, 8.3, 8.4, 8.5
 */
import { AuditTrailService } from '../audit/AuditTrailService';
import { AuditTrailEntry } from '@health-data/sdk';
import { PatientProfile, PatientProfileRepository } from '../patient/PatientProfileRepository';
import { ContentReference, DataDividendRecord } from '@health-data/sdk';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface ScopeCheckResult {
  allowed: boolean;
  /** Present when allowed is false */
  violationReason?: string;
  /** On-chain violation log tx hash (present when allowed is false) */
  violationLogTxHash?: string;
}

export interface GdprErasureResult {
  deletedVaultRecords: number;
  invalidatedContracts: number;
  auditEntryHash: string;
}

export interface GdprAccessExport {
  patientDID: string;
  exportedAt: number;
  vaultReferences: ContentReference[];
  auditTrail: AuditTrailEntry[];
  paymentHistory: DataDividendRecord[];
}

/**
 * Minimal interface for a consent record store the compliance layer needs.
 */
export interface IConsentStore {
  getPermittedScope(contractId: string): Promise<string | null>;
  invalidateContract(contractId: string): Promise<void>;
  getActiveContractIds(patientDID: string): Promise<string[]>;
}

/**
 * Minimal interface for the vault the compliance layer needs.
 */
export interface IVaultStore {
  deleteByPatient(patientDID: string): Promise<number>;
}

/**
 * Minimal interface for payment history.
 */
export interface IPaymentStore {
  getByPatient(patientDID: string): Promise<DataDividendRecord[]>;
}

// ---------------------------------------------------------------------------
// ComplianceService
// ---------------------------------------------------------------------------

export class ComplianceService {
  constructor(
    private readonly auditTrail: AuditTrailService,
    private readonly profileRepo: PatientProfileRepository,
    private readonly consentStore: IConsentStore,
    private readonly vaultStore: IVaultStore,
    private readonly paymentStore: IPaymentStore,
  ) {}

  // ---------------------------------------------------------------------------
  // Scope enforcement middleware
  // Requirements: 3.7, 8.4, 8.5
  // ---------------------------------------------------------------------------

  /**
   * Check whether the stated purpose of a computation request matches the
   * consented scope in the active Smart Contract.
   * Rejects mismatches and writes a violation log entry on-chain.
   */
  async checkScope(
    contractId: string,
    statedPurpose: string,
    patientDID: string,
  ): Promise<ScopeCheckResult> {
    const permittedScope = await this.consentStore.getPermittedScope(contractId);

    if (permittedScope === null) {
      const entry = this.auditTrail.writeEntry({
        patientDID,
        eventType: 'CONSENT_REVOKED', // closest event type for a missing contract
        contractId,
      });
      return {
        allowed: false,
        violationReason: `No active consent record found for contract ${contractId}`,
        violationLogTxHash: entry.onChainTxHash,
      };
    }

    const scopeMatches = permittedScope.toLowerCase().trim() === statedPurpose.toLowerCase().trim();

    if (!scopeMatches) {
      // Write violation log on-chain (Requirement 8.5)
      const entry = this.auditTrail.writeEntry({
        patientDID,
        eventType: 'CONSENT_REVOKED', // violation event — closest available type
        contractId,
        dataRef: `scope-violation:stated=${statedPurpose}:permitted=${permittedScope}`,
      });
      return {
        allowed: false,
        violationReason:
          `Scope mismatch: stated purpose "${statedPurpose}" does not match ` +
          `consented scope "${permittedScope}"`,
        violationLogTxHash: entry.onChainTxHash,
      };
    }

    return { allowed: true };
  }

  // ---------------------------------------------------------------------------
  // GDPR Right to Erasure
  // Requirement 8.2
  // ---------------------------------------------------------------------------

  /**
   * Delete all raw vault data for a patient, invalidate all active Smart Contracts
   * referencing that patient, and record the erasure event on-chain.
   */
  async handleErasureRequest(patientDID: string): Promise<GdprErasureResult> {
    // 1. Delete vault records
    const deletedVaultRecords = await this.vaultStore.deleteByPatient(patientDID);

    // 2. Invalidate active contracts
    const activeContractIds = await this.consentStore.getActiveContractIds(patientDID);
    for (const contractId of activeContractIds) {
      await this.consentStore.invalidateContract(contractId);
    }

    // 3. Write erasure audit entry on-chain
    const entry = this.auditTrail.writeEntry({
      patientDID,
      eventType: 'CONSENT_REVOKED', // erasure is a form of consent termination
      dataRef: `gdpr-erasure:deleted=${deletedVaultRecords}:contracts=${activeContractIds.length}`,
    });

    return {
      deletedVaultRecords,
      invalidatedContracts: activeContractIds.length,
      auditEntryHash: entry.onChainTxHash,
    };
  }

  // ---------------------------------------------------------------------------
  // GDPR Right of Access
  // Requirement 8.3
  // ---------------------------------------------------------------------------

  /**
   * Compile a complete data export for the patient:
   * vault references, audit trail, and payment history.
   */
  async handleAccessRequest(patientDID: string): Promise<GdprAccessExport> {
    const profile: PatientProfile | undefined = this.profileRepo.findByDID(patientDID);
    const vaultReferences = profile?.dataReferences ?? [];
    const auditTrail = this.auditTrail.getAuditTrail(patientDID);
    const paymentHistory = await this.paymentStore.getByPatient(patientDID);

    return {
      patientDID,
      exportedAt: Date.now(),
      vaultReferences,
      auditTrail,
      paymentHistory,
    };
  }
}
