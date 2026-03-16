/**
 * ComputationEngine — privacy-preserving computation dispatcher.
 *
 * Verifies active on-chain consent before starting any job, dispatches to
 * the correct handler (Federated Learning or ZKP), records completion, and
 * triggers dividend payment via PaymentRouter.
 *
 * Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 5.1
 */
import { randomBytes, createHash } from 'crypto';
import {
  ComputationMethod,
  ComputationResult,
  JobStatus,
  ModelGradients,
  ZKProof,
} from '@health-data/sdk';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface ComputationJob {
  jobId: string;
  contractId: string;
  method: ComputationMethod;
  status: JobStatus;
  startedAt: number;
  completedAt?: number;
  result?: ComputationResult;
}

/**
 * Minimal interface the engine needs from the on-chain consent layer.
 * In production this would be an ethers.js contract wrapper; here it is
 * an interface so tests can inject a simple in-memory stub.
 */
export interface IConsentRegistry {
  isConsentActive(contractId: string): Promise<boolean>;
  getComputationMethod(contractId: string): Promise<number>; // 0=FL, 1=ZKP
}

/**
 * Minimal interface for triggering dividend payment on milestone.
 */
export interface IPaymentRouter {
  releaseDividend(contractId: string): Promise<string>; // returns tx hash
}

// ---------------------------------------------------------------------------
// ComputationEngine
// ---------------------------------------------------------------------------

export class ComputationEngine {
  private readonly jobs = new Map<string, ComputationJob>();

  constructor(
    private readonly registry: IConsentRegistry,
    private readonly paymentRouter: IPaymentRouter,
  ) {}

  /**
   * Initiate a privacy-preserving computation.
   *
   * 1. Verify active Consent Record on-chain — reject if none found (Req 4.4).
   * 2. Dispatch to FL or ZKP handler based on contract method (Req 4.5).
   * 3. Record completion on-chain and trigger dividend payment (Req 4.6, 5.1).
   */
  async initiateComputation(contractId: string): Promise<ComputationJob> {
    // Step 1 — consent check (Requirement 4.4)
    const active = await this.registry.isConsentActive(contractId);
    if (!active) {
      throw new Error(
        `Computation rejected: no valid active Consent Record found for contract ${contractId}`,
      );
    }

    const method = await this.registry.getComputationMethod(contractId);
    const computationMethod: ComputationMethod =
      method === 1 ? 'ZKP' : 'FEDERATED_LEARNING';

    const jobId = randomBytes(16).toString('hex');
    const job: ComputationJob = {
      jobId,
      contractId,
      method: computationMethod,
      status: 'RUNNING',
      startedAt: Date.now(),
    };
    this.jobs.set(jobId, job);

    // Step 2 — dispatch (Requirement 4.5)
    let result: ComputationResult;
    if (computationMethod === 'FEDERATED_LEARNING') {
      result = await this._runFederatedLearning(jobId, contractId);
    } else {
      result = await this._runZKP(jobId, contractId);
    }

    // Step 3 — record completion and trigger payment (Requirements 4.6, 5.1)
    const txHash = await this.paymentRouter.releaseDividend(contractId);
    result = { ...result, onChainTxHash: txHash };

    job.status = 'COMPLETED';
    job.completedAt = Date.now();
    job.result = result;
    this.jobs.set(jobId, job);

    return job;
  }

  getJob(jobId: string): ComputationJob | undefined {
    return this.jobs.get(jobId);
  }

  getJobStatus(jobId: string): JobStatus {
    return this.jobs.get(jobId)?.status ?? 'REJECTED';
  }

  // ---------------------------------------------------------------------------
  // Federated Learning handler
  // Requirement 4.2 — only model gradients are returned; raw data stays in vault
  // ---------------------------------------------------------------------------

  private async _runFederatedLearning(
    jobId: string,
    contractId: string,
  ): Promise<ComputationResult> {
    // Simulate local model training — raw data is accessed inside the vault
    // and never serialised into the result object.
    const gradients: ModelGradients = {
      layerGradients: {
        'layer_0': this._simulateGradients(64),
        'layer_1': this._simulateGradients(32),
        'output':  this._simulateGradients(1),
      },
      sampleCount: 128,   // count only — no raw records
      roundId: `round-${createHash('sha256').update(jobId).digest('hex').slice(0, 8)}`,
    };

    return {
      jobId,
      contractId,
      gradients,
      // proof is intentionally absent — FL result contains ONLY gradients
      completedAt: Date.now(),
      onChainTxHash: '', // filled in by caller after payment
    };
  }

  // ---------------------------------------------------------------------------
  // ZKP handler
  // Requirement 4.3 — proof is verifiable; no raw data values in proof object
  // ---------------------------------------------------------------------------

  private async _runZKP(
    jobId: string,
    contractId: string,
  ): Promise<ComputationResult> {
    // Simulate circom/snarkjs proof generation.
    // The proof bytes are a commitment — they contain no raw patient data.
    const proofBytes = randomBytes(128).toString('hex');
    const publicSignals = [
      // Public signals are aggregate statistics, never raw values
      createHash('sha256').update(`aggregate:${contractId}`).digest('hex'),
    ];

    const proof: ZKProof = {
      proof: proofBytes,
      publicSignals,
      verificationKeyRef: `vk:${contractId}`,
    };

    return {
      jobId,
      contractId,
      proof,
      // gradients is intentionally absent — ZKP result contains ONLY the proof
      completedAt: Date.now(),
      onChainTxHash: '',
    };
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  private _simulateGradients(size: number): number[] {
    // Simulated gradient values — small floats, no patient data
    return Array.from({ length: size }, () => (Math.random() - 0.5) * 0.01);
  }
}
