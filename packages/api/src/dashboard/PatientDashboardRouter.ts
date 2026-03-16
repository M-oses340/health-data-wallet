/**
 * PatientDashboardRouter — REST endpoints for the patient dashboard.
 *
 * GET /patient/:did/payments    — payment history  (Requirement 5.5)
 * GET /patient/:did/audit-trail — audit trail      (Requirements 6.1, 6.2, 6.5)
 */
import { Router, Request, Response } from 'express';
import { AuditTrailService } from '../audit/AuditTrailService';
import { DataDividendRecord } from '@health-data/sdk';

// ---------------------------------------------------------------------------
// Payment store interface (injected — backed by on-chain events in production)
// ---------------------------------------------------------------------------

export interface IPaymentStore {
  getByPatient(patientDID: string): Promise<DataDividendRecord[]>;
}

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

export function createPatientDashboardRouter(
  auditTrail: AuditTrailService,
  paymentStore: IPaymentStore,
): Router {
  const router = Router();

  /**
   * GET /patient/:did/payments
   * Returns all DataDividendRecord entries for the patient.
   * Requirement 5.5
   */
  router.get('/:did/payments', async (req: Request, res: Response) => {
    const { did } = req.params;
    const patientDID = Array.isArray(did) ? did[0] : did;
    try {
      const records = await paymentStore.getByPatient(patientDID);
      // bigint is not JSON-serialisable — convert to string
      res.json(
        JSON.parse(
          JSON.stringify(records, (_, v) => (typeof v === 'bigint' ? v.toString() : v)),
        ),
      );
    } catch (err) {
      res.status(500).json({ error: 'Failed to retrieve payment history' });
    }
  });

  /**
   * GET /patient/:did/audit-trail
   * Returns the chronological audit trail.
   * When Accept: application/json is set, returns a JSON export.
   * Requirements: 6.1, 6.2, 6.5
   */
  router.get('/:did/audit-trail', (req: Request, res: Response) => {
    const { did } = req.params;
    const patientDID = Array.isArray(did) ? did[0] : did;
    try {
      const acceptsJson =
        req.headers['accept']?.includes('application/json') ?? true;

      if (acceptsJson) {
        const json = auditTrail.exportAuditTrail(patientDID);
        res.setHeader('Content-Type', 'application/json');
        res.send(json);
      } else {
        const entries = auditTrail.getAuditTrail(patientDID);
        res.json(entries);
      }
    } catch (err) {
      res.status(500).json({ error: 'Failed to retrieve audit trail' });
    }
  });

  return router;
}
