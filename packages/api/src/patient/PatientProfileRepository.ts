/**
 * PatientProfileRepository — in-memory store for patient profiles.
 * Requirements: 1.1, 1.3, 1.4
 */
import { ContentReference } from '@health-data/sdk';

// ---------------------------------------------------------------------------
// PatientProfile
// ---------------------------------------------------------------------------

export interface PatientProfile {
  /** W3C DID — primary key */
  did: string;
  /** EVM wallet address */
  walletAddress: string;
  /** secp256k1 public key (hex) */
  publicKey: string;
  /** Unix timestamp of registration */
  registeredAt: number;
  /** Content-addressed references to encrypted vault records */
  dataReferences: ContentReference[];
  /** Patient-configured minimum quality threshold (default 60) */
  minimumQualityThreshold: number;
}

// ---------------------------------------------------------------------------
// PatientProfileRepository
// ---------------------------------------------------------------------------

export class PatientProfileRepository {
  private readonly store = new Map<string, PatientProfile>();

  /**
   * Store a new patient profile.
   * Throws if a profile with the same DID already exists.
   * Requirement 1.3 — each patient is provisioned with a unique DID.
   */
  create(profile: PatientProfile): void {
    if (this.store.has(profile.did)) {
      throw new Error(`Profile already exists for DID: ${profile.did}`);
    }
    // Store a defensive copy so external mutations don't affect the store
    this.store.set(profile.did, {
      ...profile,
      dataReferences: [...profile.dataReferences],
    });
  }

  /**
   * Retrieve a patient profile by DID.
   * Returns undefined if no profile exists for the given DID.
   */
  findByDID(did: string): PatientProfile | undefined {
    const profile = this.store.get(did);
    if (!profile) return undefined;
    // Return a defensive copy
    return { ...profile, dataReferences: [...profile.dataReferences] };
  }

  /**
   * Update mutable fields of an existing profile.
   * Throws if no profile exists for the given DID.
   * Requirement 1.4 — data references can be updated after upload.
   */
  update(
    did: string,
    updates: Partial<Omit<PatientProfile, 'did'>>,
  ): PatientProfile {
    const existing = this.store.get(did);
    if (!existing) {
      throw new Error(`Profile not found for DID: ${did}`);
    }
    const updated: PatientProfile = {
      ...existing,
      ...updates,
      did: existing.did, // did is immutable
      dataReferences: updates.dataReferences
        ? [...updates.dataReferences]
        : [...existing.dataReferences],
    };
    this.store.set(did, updated);
    return { ...updated, dataReferences: [...updated.dataReferences] };
  }

  /**
   * Append a ContentReference to the patient's data references list.
   * Throws if no profile exists for the given DID.
   * Requirement 1.4 — Data_Vault returns a CID that is stored in the wallet.
   */
  addDataReference(did: string, ref: ContentReference): PatientProfile {
    const existing = this.store.get(did);
    if (!existing) {
      throw new Error(`Profile not found for DID: ${did}`);
    }
    existing.dataReferences.push({ ...ref });
    return { ...existing, dataReferences: [...existing.dataReferences] };
  }

  /**
   * Check whether a profile exists for the given DID.
   */
  exists(did: string): boolean {
    return this.store.has(did);
  }
}
