/**
 * Unit tests for MarketplaceService.
 * Requirements: 7.1, 7.2, 7.3, 7.4, 7.5
 */
import { MarketplaceService } from './MarketplaceService';
import { ComputationRequest } from '@health-data/sdk';
import { db } from '../db';

function makeSvc() {
  const svc = new MarketplaceService();
  svc.registerDataset({ category: 'cardiology',  dataType: 'EHR',      minQualityScore: 80, recordCount: 100, availableMethods: ['FEDERATED_LEARNING'] });
  svc.registerDataset({ category: 'genomics',    dataType: 'GENETIC',  minQualityScore: 90, recordCount: 50,  availableMethods: ['ZKP'] });
  svc.registerDataset({ category: 'cardiology',  dataType: 'WEARABLE', minQualityScore: 70, recordCount: 200, availableMethods: ['FEDERATED_LEARNING', 'ZKP'] });
  return svc;
}

const validRequest: ComputationRequest = {
  researcherDID:       'did:ethr:0xResearcher',
  dataCategory:        'cardiology',
  computationMethod:   'FEDERATED_LEARNING',
  permittedScope:      'cardiovascular-research',
  accessDurationSeconds: 86400,
  dataDividendWei:     BigInt('100000000000000000'), // 0.1 ETH
};

describe('MarketplaceService — searchDatasets', () => {
  beforeEach(() => {
    db.prepare('DELETE FROM marketplace_listings').run();
  });

  it('returns all listings when query is empty', () => {
    const svc = makeSvc();
    expect(svc.searchDatasets({})).toHaveLength(3);
  });

  it('filters by category (case-insensitive)', () => {
    const svc = makeSvc();
    const results = svc.searchDatasets({ category: 'Cardiology' });
    expect(results).toHaveLength(2);
    results.forEach(r => expect(r.category.toLowerCase()).toBe('cardiology'));
  });

  it('filters by dataType', () => {
    const svc = makeSvc();
    const results = svc.searchDatasets({ dataType: 'GENETIC' });
    expect(results).toHaveLength(1);
    expect(results[0].dataType).toBe('GENETIC');
  });

  it('filters by minQualityScore', () => {
    const svc = makeSvc();
    const results = svc.searchDatasets({ minQualityScore: 85 });
    expect(results).toHaveLength(1);
    expect(results[0].minQualityScore).toBeGreaterThanOrEqual(85);
  });

  it('combines category and dataType filters', () => {
    const svc = makeSvc();
    const results = svc.searchDatasets({ category: 'cardiology', dataType: 'WEARABLE' });
    expect(results).toHaveLength(1);
    expect(results[0].dataType).toBe('WEARABLE');
  });

  it('returns empty array when no listings match', () => {
    const svc = makeSvc();
    expect(svc.searchDatasets({ category: 'neurology' })).toHaveLength(0);
  });

  // Requirement 7.1 — listings contain NO raw patient data fields
  it('listings contain only metadata fields — no raw patient data', () => {
    const svc = makeSvc();
    const results = svc.searchDatasets({});
    const FORBIDDEN = ['did', 'patientDID', 'walletAddress', 'publicKey', 'privateKey', 'rawData', 'records'];
    results.forEach(listing => {
      const keys = Object.keys(listing);
      FORBIDDEN.forEach(f => expect(keys).not.toContain(f));
    });
  });

  it('returns defensive copies — mutating result does not affect store', () => {
    const svc = makeSvc();
    const results = svc.searchDatasets({ category: 'genomics' });
    results[0].category = 'hacked';
    expect(svc.searchDatasets({ category: 'genomics' })).toHaveLength(1);
  });
});

describe('MarketplaceService — submitComputationRequest', () => {

  it('accepts a fully valid request', () => {
    const svc = new MarketplaceService();
    const result = svc.submitComputationRequest(validRequest);
    expect(result.status).toBe('ACCEPTED');
    expect(result.contractId).toBeTruthy();
    expect(result.fieldErrors).toBeUndefined();
  });

  it('rejects when researcherDID is missing', () => {
    const svc = new MarketplaceService();
    const { researcherDID, ...rest } = validRequest;
    const result = svc.submitComputationRequest(rest);
    expect(result.status).toBe('REJECTED');
    expect(result.fieldErrors).toHaveProperty('researcherDID');
  });

  it('rejects when dataCategory is missing', () => {
    const svc = new MarketplaceService();
    const { dataCategory, ...rest } = validRequest;
    const result = svc.submitComputationRequest(rest);
    expect(result.status).toBe('REJECTED');
    expect(result.fieldErrors).toHaveProperty('dataCategory');
  });

  it('rejects when computationMethod is missing', () => {
    const svc = new MarketplaceService();
    const { computationMethod, ...rest } = validRequest;
    const result = svc.submitComputationRequest(rest);
    expect(result.status).toBe('REJECTED');
    expect(result.fieldErrors).toHaveProperty('computationMethod');
  });

  it('rejects when permittedScope is missing', () => {
    const svc = new MarketplaceService();
    const { permittedScope, ...rest } = validRequest;
    const result = svc.submitComputationRequest(rest);
    expect(result.status).toBe('REJECTED');
    expect(result.fieldErrors).toHaveProperty('permittedScope');
  });

  it('rejects when accessDurationSeconds is missing', () => {
    const svc = new MarketplaceService();
    const { accessDurationSeconds, ...rest } = validRequest;
    const result = svc.submitComputationRequest(rest);
    expect(result.status).toBe('REJECTED');
    expect(result.fieldErrors).toHaveProperty('accessDurationSeconds');
  });

  it('rejects when dataDividendWei is missing', () => {
    const svc = new MarketplaceService();
    const { dataDividendWei, ...rest } = validRequest;
    const result = svc.submitComputationRequest(rest);
    expect(result.status).toBe('REJECTED');
    expect(result.fieldErrors).toHaveProperty('dataDividendWei');
  });

  it('rejection identifies ALL missing fields simultaneously', () => {
    const svc = new MarketplaceService();
    const result = svc.submitComputationRequest({});
    expect(result.status).toBe('REJECTED');
    const errors = result.fieldErrors!;
    expect(Object.keys(errors)).toEqual(
      expect.arrayContaining([
        'researcherDID', 'dataCategory', 'computationMethod',
        'permittedScope', 'accessDurationSeconds', 'dataDividendWei',
      ]),
    );
  });

  it('rejects when accessDurationSeconds is zero', () => {
    const svc = new MarketplaceService();
    const result = svc.submitComputationRequest({ ...validRequest, accessDurationSeconds: 0 });
    expect(result.status).toBe('REJECTED');
    expect(result.fieldErrors).toHaveProperty('accessDurationSeconds');
  });

  it('rejects when dataDividendWei is zero', () => {
    const svc = new MarketplaceService();
    const result = svc.submitComputationRequest({ ...validRequest, dataDividendWei: 0n });
    expect(result.status).toBe('REJECTED');
    expect(result.fieldErrors).toHaveProperty('dataDividendWei');
  });

  it('accepted request returns a unique contractId each time', () => {
    const svc = new MarketplaceService();
    const r1 = svc.submitComputationRequest(validRequest);
    const r2 = svc.submitComputationRequest(validRequest);
    expect(r1.contractId).not.toBe(r2.contractId);
  });
});
