"""
Smoke tests verifying hypothesis is configured and shared types are importable.
Feature: health-data-monetization
"""
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from hypothesis import given, settings
from hypothesis import strategies as st

from anonymizer_types import DataType, ComputationMethod, ContentReference, AnonymizationResult


class TestHypothesisSetup:
    """Verify hypothesis is wired up correctly."""

    @given(st.integers(), st.integers())
    @settings(max_examples=100)
    def test_addition_is_commutative(self, a: int, b: int) -> None:
        """Basic property: addition is commutative."""
        assert a + b == b + a

    @given(st.text())
    @settings(max_examples=100)
    def test_string_length_non_negative(self, s: str) -> None:
        """Basic property: string length is always non-negative."""
        assert len(s) >= 0


class TestSharedTypesImportable:
    """Verify shared Python types are importable and well-formed."""

    def test_data_type_values(self) -> None:
        assert DataType.EHR == "EHR"
        assert DataType.WEARABLE == "WEARABLE"
        assert DataType.GENETIC == "GENETIC"

    def test_computation_method_values(self) -> None:
        assert ComputationMethod.FEDERATED_LEARNING == "FEDERATED_LEARNING"
        assert ComputationMethod.ZKP == "ZKP"

    def test_content_reference_shape(self) -> None:
        import time
        ref = ContentReference(
            cid="QmTest",
            data_type=DataType.EHR,
            uploaded_at=int(time.time()),
            encryption_key_ref="key-ref-1",
        )
        assert ref.cid == "QmTest"
        assert ref.data_type == DataType.EHR

    def test_anonymization_result_shape(self) -> None:
        import time
        ref = ContentReference(
            cid="QmAnon",
            data_type=DataType.EHR,
            uploaded_at=int(time.time()),
            encryption_key_ref="key-ref-2",
        )
        result = AnonymizationResult(
            anonymized_data_ref=ref,
            quality_score=85.0,
            identifiers_removed=["name", "dob"],
            audit_entry_hash="0xhash",
            success=True,
        )
        assert result.quality_score == 85.0
        assert result.success is True
        assert result.rejection_reason is None
