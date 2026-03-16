import { PatientProfileRepository, PatientProfile } from './PatientProfileRepository';
import { DataType } from '@health-data/sdk';

const makeProfile = (did: string): PatientProfile => ({
  did,
  walletAddress: '0x' + did.slice(-40).padStart(40, '0'),
  publicKey: '04' + 'ab'.repeat(32),
  registeredAt: Date.now(),
  dataReferences: [],
  minimumQualityThreshold: 60,
});

describe('PatientProfileRepository', () => {
  let repo: PatientProfileRepository;

  beforeEach(() => {
    repo = new PatientProfileRepository();
  });

  // --- create ---

  it('stores a new profile and retrieves it by DID', () => {
    const profile = makeProfile('did:ethr:0xabc123');
    repo.create(profile);
    const found = repo.findByDID(profile.did);
    expect(found).toBeDefined();
    expect(found!.did).toBe(profile.did);
  });

  it('throws when creating a duplicate DID', () => {
    const profile = makeProfile('did:ethr:0xdupe');
    repo.create(profile);
    expect(() => repo.create(profile)).toThrow(/already exists/i);
  });

  it('stores a defensive copy — external mutation does not affect store', () => {
    const profile = makeProfile('did:ethr:0xmut');
    repo.create(profile);
    profile.minimumQualityThreshold = 99;
    const found = repo.findByDID(profile.did);
    expect(found!.minimumQualityThreshold).toBe(60);
  });

  // --- findByDID ---

  it('returns undefined for unknown DID', () => {
    expect(repo.findByDID('did:ethr:0xunknown')).toBeUndefined();
  });

  it('returns a defensive copy — mutation of result does not affect store', () => {
    const profile = makeProfile('did:ethr:0xcopy');
    repo.create(profile);
    const found = repo.findByDID(profile.did)!;
    found.minimumQualityThreshold = 1;
    expect(repo.findByDID(profile.did)!.minimumQualityThreshold).toBe(60);
  });

  // --- update ---

  it('updates mutable fields', () => {
    const profile = makeProfile('did:ethr:0xupd');
    repo.create(profile);
    const updated = repo.update(profile.did, { minimumQualityThreshold: 80 });
    expect(updated.minimumQualityThreshold).toBe(80);
    expect(repo.findByDID(profile.did)!.minimumQualityThreshold).toBe(80);
  });

  it('does not allow changing the DID via update', () => {
    const profile = makeProfile('did:ethr:0ximmut');
    repo.create(profile);
    const updated = repo.update(profile.did, { did: 'did:ethr:0xhacked' } as any);
    expect(updated.did).toBe('did:ethr:0ximmut');
  });

  it('throws when updating a non-existent DID', () => {
    expect(() => repo.update('did:ethr:0xghost', { minimumQualityThreshold: 70 })).toThrow(/not found/i);
  });

  // --- addDataReference ---

  it('appends a data reference to the profile', () => {
    const profile = makeProfile('did:ethr:0xref');
    repo.create(profile);
    repo.addDataReference(profile.did, {
      cid: 'Qm123',
      dataType: 'EHR' as DataType,
      uploadedAt: Date.now(),
      encryptionKeyRef: 'key-ref-1',
    });
    const found = repo.findByDID(profile.did)!;
    expect(found.dataReferences).toHaveLength(1);
    expect(found.dataReferences[0].cid).toBe('Qm123');
  });

  it('throws when adding a reference to a non-existent DID', () => {
    expect(() =>
      repo.addDataReference('did:ethr:0xnope', {
        cid: 'Qm999',
        dataType: 'WEARABLE' as DataType,
        uploadedAt: Date.now(),
        encryptionKeyRef: 'key-ref-2',
      }),
    ).toThrow(/not found/i);
  });

  // --- exists ---

  it('returns true for a registered DID', () => {
    const profile = makeProfile('did:ethr:0xexists');
    repo.create(profile);
    expect(repo.exists(profile.did)).toBe(true);
  });

  it('returns false for an unregistered DID', () => {
    expect(repo.exists('did:ethr:0xnope')).toBe(false);
  });
});
