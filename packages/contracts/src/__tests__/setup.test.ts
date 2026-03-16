/**
 * Smoke tests verifying fast-check is configured in the contracts package.
 * Feature: health-data-monetization
 */
import * as fc from 'fast-check';
import type { ContractState, ConsentRecord, ContractStatus } from '@health-data/sdk';

describe('fast-check setup in contracts package', () => {
  it('runs a basic property with fast-check', () => {
    fc.assert(
      fc.property(fc.string(), (s) => {
        return typeof s === 'string';
      }),
    );
  });

  it('generates arbitrary ContractStatus values', () => {
    const statuses: ContractStatus[] = [
      'PENDING_SIGNATURE',
      'ACTIVE',
      'EXPIRED',
      'REVOKED',
      'COMPLETED',
    ];
    fc.assert(
      fc.property(fc.constantFrom(...statuses), (status) => {
        return statuses.includes(status);
      }),
    );
  });
});

describe('ContractState type is importable', () => {
  it('ContractState shape is correct', () => {
    const consentRecord: ConsentRecord = {
      contractId: '0xabc123',
      patientWallet: '0xpatient',
      researcherWallet: '0xresearcher',
      dataCategory: 'genomics',
      permittedScope: 'aggregate-only',
      accessDuration: 86400,
      dataDividend: BigInt(1000),
      computationMethod: 'FEDERATED_LEARNING',
      createdAt: 1_000_000,
      expiresAt: 1_086_400,
      active: true,
    };

    const state: ContractState = {
      contractId: '0xabc123',
      patientDID: 'did:ethr:0xpatient',
      researcherDID: 'did:ethr:0xresearcher',
      status: 'ACTIVE',
      consentRecord,
      escrowedAmount: BigInt(1000),
      createdAt: 1_000_000,
      expiresAt: 1_086_400,
    };

    expect(state.status).toBe('ACTIVE');
    expect(state.consentRecord.active).toBe(true);
  });
});
