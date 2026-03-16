"""
Shared Python types for the Anonymizer service.
Mirrors the TypeScript types in packages/sdk/src/types.ts.
"""
from dataclasses import dataclass, field
from typing import List, Optional
from enum import Enum


class DataType(str, Enum):
    EHR = "EHR"
    WEARABLE = "WEARABLE"
    GENETIC = "GENETIC"


class ComputationMethod(str, Enum):
    FEDERATED_LEARNING = "FEDERATED_LEARNING"
    ZKP = "ZKP"


@dataclass
class ContentReference:
    cid: str
    data_type: DataType
    uploaded_at: int  # Unix timestamp
    encryption_key_ref: str


@dataclass
class AnonymizationResult:
    anonymized_data_ref: ContentReference
    quality_score: float          # 0–100
    identifiers_removed: List[str]
    audit_entry_hash: str
    success: bool
    rejection_reason: Optional[str] = None


@dataclass
class AuditLogEntry:
    operation_id: str
    data_ref: str
    timestamp: int
    quality_score: float
    operator_did: str
    on_chain_tx_hash: str
