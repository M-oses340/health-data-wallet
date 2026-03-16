/**
 * Unit tests for ComputationEngine.
 * Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 5.1
 */
import { ComputationEngine, IConsentRegistry, IPaymentRouter } from './ComputationEngine';

// ---------------------------------------------------------------------------
// Stubs
// ---------------------------------------------------------------------------

function makeRegistry(active: boolean, method: number = 0): IConsentRegistry {
  return {
    isConsentActive: async () => active,
    getComputationMethod: async () => method,
  };
}

function makeRouter(): IPaymentRouter & { calls: string[] } {
  const calls: string[] = [];
  return {
    calls,
    releaseDividend: async (contractId: string) => {
      calls.push(contractId);
      return '0xdeadbeef';
    },
  };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('ComputationEngine', () => {

  // --- consent check (Requirement 4.4) ---

  it('rejects computation when no active consent exists', async () => {
    const engine = new ComputationEngine(makeRegistry(false), makeRouter());
    await expect(engine.initiateComputation('contract-1')).rejects.toThrow(
      /no valid active Consent Record/i,
    );
  });

  it('rejection error message includes the contractId', async () => {
    const engine = new ComputationEngine(makeRegistry(false), makeRouter());
    await expect(engine.initiateComputation('my-contract-id')).rejects.toThrow(
      /my-contract-id/,
    );
  });

  // --- FL dispatch (Requirement 4.5) ---

  it('dispatches to Federated Learning when method is 0', async () => {
    const engine = new ComputationEngine(makeRegistry(true, 0), makeRouter());
    const job = await engine.initiateComputation('contract-fl');
    expect(job.method).toBe('FEDERATED_LEARNING');
  });

  it('FL result contains gradients and no proof', async () => {
    const engine = new ComputationEngine(makeRegistry(true, 0), makeRouter());
    const job = await engine.initiateComputation('contract-fl');
    expect(job.result!.gradients).toBeDefined();
    expect(job.result!.proof).toBeUndefined();
  });

  it('FL gradients contain only numeric arrays — no raw patient data fields', async () => {
    const engine = new ComputationEngine(makeRegistry(true, 0), makeRouter());
    const job = await engine.initiateComputation('contract-fl');
    const gradients = job.result!.gradients!;
    // Only allowed fields: layerGradients, sampleCount, roundId
    const keys = Object.keys(gradients);
    expect(keys).toEqual(expect.arrayContaining(['layerGradients', 'sampleCount', 'roundId']));
    expect(keys).not.toContain('rawData');
    expect(keys).not.toContain('patientRecords');
    // All layer values are number arrays
    for (const vals of Object.values(gradients.layerGradients)) {
      expect(Array.isArray(vals)).toBe(true);
      vals.forEach(v => expect(typeof v).toBe('number'));
    }
  });

  // --- ZKP dispatch (Requirement 4.5) ---

  it('dispatches to ZKP when method is 1', async () => {
    const engine = new ComputationEngine(makeRegistry(true, 1), makeRouter());
    const job = await engine.initiateComputation('contract-zkp');
    expect(job.method).toBe('ZKP');
  });

  it('ZKP result contains proof and no gradients', async () => {
    const engine = new ComputationEngine(makeRegistry(true, 1), makeRouter());
    const job = await engine.initiateComputation('contract-zkp');
    expect(job.result!.proof).toBeDefined();
    expect(job.result!.gradients).toBeUndefined();
  });

  it('ZKP proof contains no raw data fields', async () => {
    const engine = new ComputationEngine(makeRegistry(true, 1), makeRouter());
    const job = await engine.initiateComputation('contract-zkp');
    const proof = job.result!.proof!;
    const keys = Object.keys(proof);
    expect(keys).toEqual(expect.arrayContaining(['proof', 'publicSignals', 'verificationKeyRef']));
    expect(keys).not.toContain('rawData');
    expect(keys).not.toContain('patientRecords');
    expect(typeof proof.proof).toBe('string');
    expect(Array.isArray(proof.publicSignals)).toBe(true);
  });

  // --- completion recording and payment (Requirements 4.6, 5.1) ---

  it('triggers releaseDividend on completion', async () => {
    const router = makeRouter();
    const engine = new ComputationEngine(makeRegistry(true, 0), router);
    await engine.initiateComputation('contract-pay');
    expect(router.calls).toContain('contract-pay');
  });

  it('job status is COMPLETED after successful computation', async () => {
    const engine = new ComputationEngine(makeRegistry(true, 0), makeRouter());
    const job = await engine.initiateComputation('contract-done');
    expect(job.status).toBe('COMPLETED');
    expect(job.completedAt).toBeDefined();
  });

  it('result includes on-chain tx hash from payment router', async () => {
    const engine = new ComputationEngine(makeRegistry(true, 0), makeRouter());
    const job = await engine.initiateComputation('contract-hash');
    expect(job.result!.onChainTxHash).toBe('0xdeadbeef');
  });

  it('getJob returns the stored job by jobId', async () => {
    const engine = new ComputationEngine(makeRegistry(true, 0), makeRouter());
    const job = await engine.initiateComputation('contract-get');
    expect(engine.getJob(job.jobId)).toEqual(job);
  });

  it('getJobStatus returns REJECTED for unknown jobId', async () => {
    const engine = new ComputationEngine(makeRegistry(true, 0), makeRouter());
    expect(engine.getJobStatus('unknown-job')).toBe('REJECTED');
  });
});
