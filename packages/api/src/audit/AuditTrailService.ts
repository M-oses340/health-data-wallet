/**
 * AuditTrailService — SQLite-backed immutable audit trail.
 * Requirements: 6.1, 6.2, 6.3, 6.4, 6.5
 */
import { createHash, randomBytes } from 'crypto';
import { AuditTrailEntry, AuditEventType, ComputationMethod } from '@health-data/sdk';
import { db } from '../db';

export interface AuditEntryInput {
  patientDID: string;
  eventType: AuditEventType;
  contractId?: string;
  dataRef?: string;
  computationMethod?: ComputationMethod;
  amount?: bigint;
  timestamp?: number;
}

export class AuditTrailService {
  writeEntry(input: AuditEntryInput): AuditTrailEntry {
    const entryId = randomBytes(16).toString('hex');
    const timestamp = input.timestamp ?? Date.now();
    const onChainTxHash = '0x' + createHash('sha256')
      .update(JSON.stringify({ entryId, ...input, timestamp }, (_, v) => typeof v === 'bigint' ? v.toString() : v))
      .digest('hex');

    db.prepare(`
      INSERT INTO audit_trail
        (entry_id, patient_did, event_type, contract_id, data_ref, computation_method, amount, timestamp, on_chain_tx_hash)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      entryId, input.patientDID, input.eventType,
      input.contractId ?? null, input.dataRef ?? null,
      input.computationMethod ?? null,
      input.amount != null ? input.amount.toString() : null,
      timestamp, onChainTxHash,
    );

    return Object.freeze({
      entryId, patientDID: input.patientDID, eventType: input.eventType,
      contractId: input.contractId, dataRef: input.dataRef,
      computationMethod: input.computationMethod, amount: input.amount,
      timestamp, onChainTxHash,
    });
  }

  getAuditTrail(patientDID: string): AuditTrailEntry[] {
    const rows = db.prepare(
      'SELECT * FROM audit_trail WHERE patient_did = ? ORDER BY timestamp ASC'
    ).all(patientDID) as any[];
    return rows.map(r => ({
      entryId: r.entry_id,
      patientDID: r.patient_did,
      eventType: r.event_type as AuditEventType,
      contractId: r.contract_id ?? undefined,
      dataRef: r.data_ref ?? undefined,
      computationMethod: r.computation_method as ComputationMethod ?? undefined,
      amount: r.amount != null ? BigInt(r.amount) : undefined,
      timestamp: r.timestamp,
      onChainTxHash: r.on_chain_tx_hash,
    }));
  }

  exportAuditTrail(patientDID: string): string {
    return JSON.stringify(
      this.getAuditTrail(patientDID),
      (_, v) => typeof v === 'bigint' ? v.toString() : v,
      2,
    );
  }
}
