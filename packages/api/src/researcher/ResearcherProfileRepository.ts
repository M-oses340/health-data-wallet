/**
 * ResearcherProfileRepository — SQLite-backed store for researcher profiles.
 */
import { db } from '../db';

export interface ResearcherProfile {
  did: string;
  walletAddress: string;
  publicKey: string;
  registeredAt: number;
  organisation: string;
}

export class ResearcherProfileRepository {
  create(profile: ResearcherProfile): void {
    db.prepare(`
      INSERT INTO researcher_profiles (did, wallet_address, public_key, registered_at, organisation)
      VALUES (?, ?, ?, ?, ?)
    `).run(profile.did, profile.walletAddress, profile.publicKey, profile.registeredAt, profile.organisation);
  }

  findByDID(did: string): ResearcherProfile | undefined {
    const row = db.prepare('SELECT * FROM researcher_profiles WHERE did = ?').get(did) as any;
    if (!row) return undefined;
    return {
      did: row.did,
      walletAddress: row.wallet_address,
      publicKey: row.public_key,
      registeredAt: row.registered_at,
      organisation: row.organisation,
    };
  }

  exists(did: string): boolean {
    return !!db.prepare('SELECT 1 FROM researcher_profiles WHERE did = ?').get(did);
  }
}
