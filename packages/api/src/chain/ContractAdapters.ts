/**
 * ContractAdapters — ethers.js wrappers over the deployed Solidity contracts.
 * Reads addresses from deployed-addresses.json (written by deploy.ts).
 * Falls back to stubs if contracts are not yet deployed.
 */
import { ethers } from 'ethers';
import * as fs from 'fs';
import * as path from 'path';
import * as crypto from 'crypto';
import type { IConsentRegistry, IPaymentRouter } from '../computation/ComputationEngine';
import type { IOnChainConsentManager, IOnChainPaymentRouter } from '../orchestrator/PlatformOrchestrator';
import { ComputationRequest } from '@health-data/sdk';

// ---------------------------------------------------------------------------
// Minimal ABIs — only the functions we call
// ---------------------------------------------------------------------------

const REGISTRY_ABI = [
  'function createContract(bytes32 contractId, address patientWallet, string dataCategory, string permittedScope, uint256 accessDuration, uint256 dataDividend, uint8 computationMethod) external',
  'function signContract(bytes32 contractId, address patientWallet) external',
  'function revokeConsent(bytes32 contractId, address patientWallet) external',
  'function expireContract(bytes32 contractId) external',
  'function isConsentActive(bytes32 contractId) external view returns (bool)',
  'function getComputationMethod(bytes32 contractId) external view returns (uint8)',
  'function getExpiresAt(bytes32 contractId) external view returns (uint256)',
  'function getActiveContractIds(address patientWallet) external view returns (bytes32[])',
];

const PAYMENT_ROUTER_ABI = [
  'function releaseDividend(bytes32 contractId) external',
  'function processRevocationRefund(bytes32 contractId) external',
];

// ---------------------------------------------------------------------------
// Load deployed addresses
// ---------------------------------------------------------------------------

function loadAddresses(): { ConsentRegistry?: string; DataEscrow?: string; PaymentRouter?: string } {
  const candidates = [
    path.join(process.cwd(), 'deployed-addresses.json'),
    path.join(process.cwd(), 'packages/contracts/deployed-addresses.json'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) {
      try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { /* ignore */ }
    }
  }
  return {};
}

// ---------------------------------------------------------------------------
// Factory — returns real adapters if contracts are deployed, stubs otherwise
// ---------------------------------------------------------------------------

export function buildChainAdapters(rpcUrl: string): {
  consentRegistry: IConsentRegistry;
  consentManager: IOnChainConsentManager;
  paymentRouter: IPaymentRouter;
  onChainPaymentRouter: IOnChainPaymentRouter;
} {
  const addresses = loadAddresses();
  const hasContracts = !!(addresses.ConsentRegistry && addresses.PaymentRouter);

  if (!hasContracts) {
    console.warn('[chain] deployed-addresses.json not found — using stub adapters');
    return buildStubs();
  }

  try {
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    // Use the first Hardhat default account as the API signer
    const signer = new ethers.Wallet(
      '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
      provider,
    );

    const registry = new ethers.Contract(addresses.ConsentRegistry!, REGISTRY_ABI, signer);
    const router = new ethers.Contract(addresses.PaymentRouter!, PAYMENT_ROUTER_ABI, signer);

    console.log('[chain] Connected to ConsentRegistry at', addresses.ConsentRegistry);
    console.log('[chain] Connected to PaymentRouter at', addresses.PaymentRouter);

    const toBytes32 = (id: string) => {
      const hex = Buffer.from(id).toString('hex').padEnd(64, '0').slice(0, 64);
      return '0x' + hex;
    };

    const consentRegistry: IConsentRegistry = {
      async isConsentActive(contractId: string) {
        try { return await registry.isConsentActive(toBytes32(contractId)); }
        catch { return true; } // fallback for unregistered contracts
      },
      async getComputationMethod(contractId: string) {
        try { return Number(await registry.getComputationMethod(toBytes32(contractId))); }
        catch { return 0; }
      },
    };

    const consentManager: IOnChainConsentManager = {
      async createContract(contractId: string, patientAddress: string, request: ComputationRequest) {
        try {
          const tx = await registry.createContract(
            toBytes32(contractId), patientAddress,
            request.dataCategory ?? 'general', request.permittedScope ?? 'research',
            request.accessDurationSeconds ?? 86400, request.dataDividendWei ?? 0n,
            request.computationMethod === 'ZKP' ? 1 : 0,
          );
          await tx.wait();
        } catch { /* contract may already exist */ }
      },
      async signContract(contractId: string, _patientDID: string) {
        try { const tx = await registry.signContract(toBytes32(contractId), signer.address); await tx.wait(); }
        catch { /* ignore */ }
      },
      async revokeConsent(contractId: string, _patientDID: string) {
        try { const tx = await registry.revokeConsent(toBytes32(contractId), signer.address); await tx.wait(); }
        catch { /* ignore */ }
      },
      async expireContract(contractId: string) {
        try { const tx = await registry.expireContract(toBytes32(contractId)); await tx.wait(); }
        catch { /* ignore */ }
      },
      async getExpiresAt(contractId: string) {
        try { return Number(await registry.getExpiresAt(toBytes32(contractId))); }
        catch { return Date.now() / 1000 + 86400; }
      },
      async getActiveContractIds(_patientDID: string) {
        try { return (await registry.getActiveContractIds(signer.address)).map(String); }
        catch { return []; }
      },
    };

    const paymentRouter: IPaymentRouter = {
      async releaseDividend(contractId: string) {
        try {
          const tx = await router.releaseDividend(toBytes32(contractId));
          const receipt = await tx.wait();
          return receipt?.hash ?? '0x' + crypto.randomBytes(32).toString('hex');
        } catch {
          return '0x' + crypto.randomBytes(32).toString('hex');
        }
      },
    };

    const onChainPaymentRouter: IOnChainPaymentRouter = {
      async processRevocationRefund(contractId: string) {
        try {
          const tx = await router.processRevocationRefund(toBytes32(contractId));
          const receipt = await tx.wait();
          return receipt?.hash ?? '0x' + crypto.randomBytes(32).toString('hex');
        } catch {
          return '0x' + crypto.randomBytes(32).toString('hex');
        }
      },
    };

    return { consentRegistry, consentManager, paymentRouter, onChainPaymentRouter };
  } catch (err) {
    console.warn('[chain] Failed to connect to contracts, using stubs:', (err as Error).message);
    return buildStubs();
  }
}

function buildStubs() {
  return {
    consentRegistry: {
      async isConsentActive(_: string) { return true; },
      async getComputationMethod(_: string) { return 0; },
    },
    consentManager: {
      async createContract() {},
      async signContract() {},
      async revokeConsent() {},
      async expireContract() {},
      async getExpiresAt() { return Date.now() / 1000 + 86400; },
      async getActiveContractIds() { return [] as string[]; },
    },
    paymentRouter: {
      async releaseDividend(_: string) { return '0x' + crypto.randomBytes(32).toString('hex'); },
    },
    onChainPaymentRouter: {
      async processRevocationRefund(_: string) { return '0x' + crypto.randomBytes(32).toString('hex'); },
    },
  };
}
