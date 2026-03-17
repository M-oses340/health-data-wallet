/**
 * MarketplaceService — SQLite-backed anonymized dataset discovery.
 * Requirements: 7.1, 7.2, 7.3, 7.4, 7.5
 */
import { randomBytes } from 'crypto';
import { ComputationMethod, ComputationRequest, DataType } from '@health-data/sdk';
import { db } from '../db';

export interface DatasetListing {
  listingId: string;
  category: string;
  dataType: DataType;
  minQualityScore: number;
  recordCount: number;
  availableMethods: ComputationMethod[];
}

export interface DatasetQuery {
  category?: string;
  dataType?: DataType;
  minQualityScore?: number;
}

export interface RequestSubmission {
  requestId: string;
  status: 'ACCEPTED' | 'REJECTED';
  fieldErrors?: Record<string, string>;
  contractId?: string;
}

export class MarketplaceService {
  registerDataset(listing: Omit<DatasetListing, 'listingId'>): DatasetListing {
    const listingId = randomBytes(8).toString('hex');
    db.prepare(`
      INSERT INTO marketplace_listings
        (listing_id, category, data_type, min_quality_score, record_count, available_methods)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run(
      listingId, listing.category, listing.dataType,
      listing.minQualityScore, listing.recordCount,
      JSON.stringify(listing.availableMethods),
    );
    return { listingId, ...listing };
  }

  searchDatasets(query: DatasetQuery): DatasetListing[] {
    let sql = 'SELECT * FROM marketplace_listings WHERE 1=1';
    const params: any[] = [];
    if (query.category) { sql += ' AND LOWER(category) = LOWER(?)'; params.push(query.category); }
    if (query.dataType) { sql += ' AND data_type = ?'; params.push(query.dataType); }
    if (query.minQualityScore !== undefined) { sql += ' AND min_quality_score >= ?'; params.push(query.minQualityScore); }
    const rows = db.prepare(sql).all(...params) as any[];
    return rows.map(r => ({
      listingId: r.listing_id,
      category: r.category,
      dataType: r.data_type as DataType,
      minQualityScore: r.min_quality_score,
      recordCount: r.record_count,
      availableMethods: JSON.parse(r.available_methods),
    }));
  }

  submitComputationRequest(request: Partial<ComputationRequest>): RequestSubmission {
    const fieldErrors = this._validateRequest(request);
    if (Object.keys(fieldErrors).length > 0) {
      return { requestId: randomBytes(8).toString('hex'), status: 'REJECTED', fieldErrors };
    }
    const contractId = '0x' + randomBytes(32).toString('hex');
    return { requestId: randomBytes(8).toString('hex'), status: 'ACCEPTED', contractId };
  }

  private _validateRequest(req: Partial<ComputationRequest>): Record<string, string> {
    const errors: Record<string, string> = {};
    if (!req.researcherDID?.trim()) errors['researcherDID'] = 'researcherDID is required';
    if (!req.dataCategory?.trim()) errors['dataCategory'] = 'dataCategory is required';
    if (!req.computationMethod) errors['computationMethod'] = 'computationMethod is required';
    else if (!['FEDERATED_LEARNING', 'ZKP'].includes(req.computationMethod))
      errors['computationMethod'] = 'computationMethod must be FEDERATED_LEARNING or ZKP';
    if (!req.permittedScope?.trim()) errors['permittedScope'] = 'permittedScope is required';
    if (req.accessDurationSeconds == null) errors['accessDurationSeconds'] = 'accessDurationSeconds is required';
    else if (req.accessDurationSeconds <= 0) errors['accessDurationSeconds'] = 'must be > 0';
    if (req.dataDividendWei == null) errors['dataDividendWei'] = 'dataDividendWei is required';
    else if (req.dataDividendWei <= 0n) errors['dataDividendWei'] = 'must be > 0';
    return errors;
  }
}
