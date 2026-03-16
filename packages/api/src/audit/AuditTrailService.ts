/**
 * AuditTrailService — immutable on-chain audit trail for all platform events.
 *
 * Requirements: 6.1, 6.2, 6.3, 6.4, 6.5
 */
import { createHash, randomBytes } from 'crypto';
import { AuditTrailEntry, AuditEventType, ComputationMethod } from '@health-data/sdk';

// ---------------------------------------------------------------------------
// Input type for writing a new entry
// ---------------------------------------------------------------------------

export interface AuditEntryInput {
  patientDID: string;
  eventType: AuditEventType;
  contractId?: string;
  dataRef?: string;
  computationMethod?: ComputationMethod;
  amount?: bigint;
  /** Override timestamp (defaults to Date.now()) — useful for testing */
  timestamp?: number;
}

// ---------------------------------------------------------------------------
// AuditTrailService
// ---------------------------------------------------------------------------

export class AuditTrailService {
  /**
   * Append-only log — entries are never modified or deleted after insertion.
   * Requirement 6.3 — immutability.
   */
  private readonly log: AuditTrailEntry[] = [];

  /**
   * Write an immutable audit entry.
   * Returns the written entry.
   * Requirements: 6.1, 6.3
   */
  writeEntry(input: AuditEntryInput): AuditTrailEntry {
    const entryId = randomBytes(16).toString('hex');
    const timestamp = input.timestamp ?? Date.now();

    // Simulate on-chain tx hash: SHA-256 of entry content
    const onChainTxHash =
      '0x' +
      createHash('sha256')
        .update(JSON.stringify({ entryId, ...input, timestamp }, (_, v) => (typeof v === 'bigint' ? v.toString() : v)))
        .digest('hex');

    const entry: AuditTrailEntry = {
      entryId,
      patientDID: input.patientDID,
      eventType: input.eventType,
      contractId: input.contractId,
      dataRef: input.dataRef,
      computationMethod: input.computationMethod,
      amount: input.amount,
      timestamp,
      onChainTxHash,
    };

    // Freeze the entry so it cannot be mutated after insertion (Req 6.3)
    Object.freeze(entry);
    this.log.push(entry);

    return entry;
  }

  /**
   * Return all audit entries for a patient in ascending timestamp order.
   * Requirements: 6.1, 6.2
   */
  getAuditTrail(patientDID: string): AuditTrailEntry[] {
    return this.log
      .filter(e => e.patientDID === patientDID)
      .sort((a, b) => a.timestamp - b.timestamp);
  }

  /**
   * Export the patient's audit trail as a JSON string.
   * Requirement 6.5
   */
  exportAuditTrail(patientDID: string): string {
    const entries = this.getAuditTrail(patientDID);
    // bigint is not JSON-serialisable by default — convert to string
    return JSON.stringify(
      entries,
      (_, v) => (typeof v === 'bigint' ? v.toString() : v),
      2,
    );
  }
}
