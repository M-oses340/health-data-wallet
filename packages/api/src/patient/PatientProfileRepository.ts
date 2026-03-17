/**
 * PatientProfileRepository — SQLite-backed store for patient profiles.
 * Requirements: 1.1, 1.3, 1.4
 */
import { ContentReference } from '@health-data/sdk';
import { db } from '../db';

export interface PatientProfile {
  did: string;
  walletAddress: string;
  publicKey: string;
  registeredAt: number;
  dataReferences: ContentReference[];
  minimumQualityThreshold: number;
}

export class PatientProfileRepository {
  create(profile: PatientProfile): void {
    db.prepare(`
      INSERT INTO patient_profiles
        (did, wallet_address, public_key, registered_at, minimum_quality_threshold, data_references)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run(
      profile.did,
      profile.walletAddress,
      profile.publicKey,
      profile.registeredAt,
      profile.minimumQualityThreshold,
      JSON.stringify(profile.dataReferences),
    );
  }

  findByDID(did: string): PatientProfile | undefined {
    const row = db.prepare('SELECT * FROM patient_profiles WHERE did = ?').get(did) as any;
    if (!row) return undefined;
    return this._toProfile(row);
  }

  update(did: string, updates: Partial<Omit<PatientProfile, 'did'>>): PatientProfile {
    const existing = this.findByDID(did);
    if (!existing) throw new Error(`Profile not found for DID: ${did}`);
    const merged = { ...existing, ...updates, did: existing.did };
    db.prepare(`
      UPDATE patient_profiles SET
        wallet_address = ?, public_key = ?, registered_at = ?,
        minimum_quality_threshold = ?, data_references = ?
      WHERE did = ?
    `).run(
      merged.walletAddress, merged.publicKey, merged.registeredAt,
      merged.minimumQualityThreshold, JSON.stringify(merged.dataReferences),
      did,
    );
    return merged;
  }

  addDataReference(did: string, ref: ContentReference): PatientProfile {
    const existing = this.findByDID(did);
    if (!existing) throw new Error(`Profile not found for DID: ${did}`);
    const refs = [...existing.dataReferences, { ...ref }];
    db.prepare('UPDATE patient_profiles SET data_references = ? WHERE did = ?')
      .run(JSON.stringify(refs), did);
    return { ...existing, dataReferences: refs };
  }

  exists(did: string): boolean {
    return !!db.prepare('SELECT 1 FROM patient_profiles WHERE did = ?').get(did);
  }

  private _toProfile(row: any): PatientProfile {
    return {
      did: row.did,
      walletAddress: row.wallet_address,
      publicKey: row.public_key,
      registeredAt: row.registered_at,
      minimumQualityThreshold: row.minimum_quality_threshold,
      dataReferences: JSON.parse(row.data_references),
    };
  }
}
