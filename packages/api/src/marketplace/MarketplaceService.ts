/**
 * MarketplaceService — anonymized dataset discovery and computation request submission.
 *
 * Requirements: 7.1, 7.2, 7.3, 7.4, 7.5
 */
import { randomBytes } from 'crypto';
import { ComputationMethod, ComputationRequest, DataType } from '@health-data/sdk';

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/**
 * A dataset listing returned by the marketplace.
 * Contains ONLY anonymized category metadata — no raw or identifiable patient data.
 * Requirement 7.1
 */
export interface DatasetListing {
  listingId: string;
  category: string;
  dataType: DataType;
  /** Minimum quality score across all records in this dataset */
  minQualityScore: number;
  /** Number of anonymized records available */
  recordCount: number;
  /** Available computation methods for this dataset */
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
  /** Set when status is REJECTED — maps field name → error message */
  fieldErrors?: Record<string, string>;
  /** Set when status is ACCEPTED */
  contractId?: string;
}

// ---------------------------------------------------------------------------
// Internal listing registry (populated via registerDataset)
// ---------------------------------------------------------------------------

interface InternalListing extends DatasetListing {
  // No raw patient data fields — only metadata
}

// ---------------------------------------------------------------------------
// MarketplaceService
// ---------------------------------------------------------------------------

export class MarketplaceService {
  private readonly listings = new Map<string, InternalListing>();

  /**
   * Register an anonymized dataset listing.
   * Called by the platform after anonymization completes.
   * Only metadata fields are accepted — raw data is rejected at the type level.
   */
  registerDataset(listing: Omit<DatasetListing, 'listingId'>): DatasetListing {
    const listingId = randomBytes(8).toString('hex');
    const stored: InternalListing = { listingId, ...listing };
    this.listings.set(listingId, stored);
    return { ...stored };
  }

  /**
   * Search for anonymized dataset listings by category and/or data type.
   * Returns only metadata — no raw or identifiable patient data.
   * Requirements: 7.1, 7.2
   */
  searchDatasets(query: DatasetQuery): DatasetListing[] {
    return Array.from(this.listings.values())
      .filter(l => {
        if (query.category && l.category.toLowerCase() !== query.category.toLowerCase()) {
          return false;
        }
        if (query.dataType && l.dataType !== query.dataType) {
          return false;
        }
        if (query.minQualityScore !== undefined && l.minQualityScore < query.minQualityScore) {
          return false;
        }
        return true;
      })
      .map(l => ({ ...l })); // return copies — no internal references
  }

  /**
   * Validate and submit a computation request.
   * Rejects with field-level errors if any required fields are missing.
   * On valid request, generates a contractId for Smart Contract creation.
   * Requirements: 7.3, 7.4, 7.5
   */
  submitComputationRequest(request: Partial<ComputationRequest>): RequestSubmission {
    const fieldErrors = this._validateRequest(request);

    if (Object.keys(fieldErrors).length > 0) {
      return { requestId: randomBytes(8).toString('hex'), status: 'REJECTED', fieldErrors };
    }

    const contractId = '0x' + randomBytes(32).toString('hex');
    return {
      requestId: randomBytes(8).toString('hex'),
      status: 'ACCEPTED',
      contractId,
    };
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  private _validateRequest(req: Partial<ComputationRequest>): Record<string, string> {
    const errors: Record<string, string> = {};

    if (!req.researcherDID || req.researcherDID.trim() === '') {
      errors['researcherDID'] = 'researcherDID is required';
    }
    if (!req.dataCategory || req.dataCategory.trim() === '') {
      errors['dataCategory'] = 'dataCategory is required';
    }
    if (!req.computationMethod) {
      errors['computationMethod'] = 'computationMethod is required';
    } else if (!['FEDERATED_LEARNING', 'ZKP'].includes(req.computationMethod)) {
      errors['computationMethod'] = 'computationMethod must be FEDERATED_LEARNING or ZKP';
    }
    if (!req.permittedScope || req.permittedScope.trim() === '') {
      errors['permittedScope'] = 'permittedScope is required';
    }
    if (req.accessDurationSeconds === undefined || req.accessDurationSeconds === null) {
      errors['accessDurationSeconds'] = 'accessDurationSeconds is required';
    } else if (req.accessDurationSeconds <= 0) {
      errors['accessDurationSeconds'] = 'accessDurationSeconds must be greater than 0';
    }
    if (req.dataDividendWei === undefined || req.dataDividendWei === null) {
      errors['dataDividendWei'] = 'dataDividendWei is required';
    } else if (req.dataDividendWei <= 0n) {
      errors['dataDividendWei'] = 'dataDividendWei must be greater than 0';
    }

    return errors;
  }
}
