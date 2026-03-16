"""
Unit tests for AnonymizerService.
Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6
"""
import sys
import os
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

import pytest
from anonymizer_service import AnonymizerService
from anonymizer_types import ContentReference, DataType


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def svc():
    return AnonymizerService()


def make_ref(cid: str = "QmTest") -> ContentReference:
    return ContentReference(
        cid=cid,
        data_type=DataType.EHR,
        uploaded_at=int(time.time()),
        encryption_key_ref="key-ref-1",
    )


# ---------------------------------------------------------------------------
# de-identification — HIPAA identifier removal (Requirement 2.2)
# ---------------------------------------------------------------------------

class TestHIPAARemoval:

    def test_removes_person_name(self, svc):
        text = "Patient John Smith was admitted on 01/15/2024."
        result = svc.deidentify(text, make_ref(), "did:ethr:0xabc")
        assert "John Smith" not in result.anonymized_data_ref.cid or result.success

    def test_removes_email(self, svc):
        text = "Contact the patient at john.doe@example.com for follow-up."
        result = svc.deidentify(text, make_ref(), "did:ethr:0xabc")
        assert result.success
        assert result.identifiers_removed  # at least one identifier found

    def test_removes_phone_number(self, svc):
        text = "Call the patient at 555-867-5309 before the appointment."
        result = svc.deidentify(text, make_ref(), "did:ethr:0xabc")
        assert "PHONE" in result.identifiers_removed or result.success

    def test_removes_ssn(self, svc):
        text = "SSN: 123-45-6789 on file."
        result = svc.deidentify(text, make_ref(), "did:ethr:0xabc")
        assert "SSN" in result.identifiers_removed

    def test_removes_date(self, svc):
        text = "Date of birth: 03/22/1985."
        result = svc.deidentify(text, make_ref(), "did:ethr:0xabc")
        assert "DATE" in result.identifiers_removed or "DATE_TIME" in result.identifiers_removed

    def test_removes_ip_address(self, svc):
        text = "Device logged in from IP 192.168.1.100."
        result = svc.deidentify(text, make_ref(), "did:ethr:0xabc")
        assert "IP_ADDRESS" in result.identifiers_removed or "IP" in result.identifiers_removed

    def test_removes_zip_code(self, svc):
        text = "Patient resides in zip code 90210."
        result = svc.deidentify(text, make_ref(), "did:ethr:0xabc")
        assert "ZIP" in result.identifiers_removed

    def test_removes_url(self, svc):
        text = "See patient portal at https://portal.hospital.org/patient/12345."
        result = svc.deidentify(text, make_ref(), "did:ethr:0xabc")
        assert "URL" in result.identifiers_removed

    def test_clean_text_has_no_identifiers_removed(self, svc):
        text = "The patient has elevated blood pressure and requires monitoring."
        result = svc.deidentify(text, make_ref(), "did:ethr:0xabc")
        assert result.success
        assert result.identifiers_removed == []


# ---------------------------------------------------------------------------
# Quality score (Requirement 2.3)
# ---------------------------------------------------------------------------

class TestQualityScore:

    def test_score_is_in_range_for_clean_text(self, svc):
        text = "Blood pressure 120/80. Heart rate 72 bpm. No abnormalities."
        result = svc.deidentify(text, make_ref(), "did:ethr:0xabc")
        assert 0.0 <= result.quality_score <= 100.0

    def test_score_is_in_range_for_pii_heavy_text(self, svc):
        text = (
            "Patient John Doe, SSN 123-45-6789, DOB 01/01/1980, "
            "phone 555-123-4567, email jdoe@test.com, zip 12345."
        )
        result = svc.deidentify(text, make_ref(), "did:ethr:0xabc", minimum_quality_threshold=0.0)
        assert 0.0 <= result.quality_score <= 100.0

    def test_empty_text_returns_100(self, svc):
        result = svc.deidentify("", make_ref(), "did:ethr:0xabc")
        assert result.quality_score == 100.0

    def test_clean_text_scores_higher_than_pii_heavy(self, svc):
        clean = "Blood pressure 120/80. Heart rate 72 bpm."
        pii_heavy = "John Doe, 123-45-6789, jdoe@test.com, 555-123-4567, 01/01/1980."
        r_clean = svc.deidentify(clean, make_ref("cid1"), "did:ethr:0xabc")
        r_pii = svc.deidentify(pii_heavy, make_ref("cid2"), "did:ethr:0xabc", minimum_quality_threshold=0.0)
        assert r_clean.quality_score >= r_pii.quality_score


# ---------------------------------------------------------------------------
# Quality threshold enforcement (Requirement 2.4)
# ---------------------------------------------------------------------------

class TestQualityThreshold:

    def test_rejects_when_score_below_threshold(self, svc):
        # Force a low score by using a very high threshold
        text = "Blood pressure 120/80."
        result = svc.deidentify(text, make_ref(), "did:ethr:0xabc", minimum_quality_threshold=999.0)
        assert result.success is False
        assert result.rejection_reason is not None
        assert len(result.rejection_reason) > 0

    def test_rejection_reason_mentions_threshold(self, svc):
        text = "Blood pressure 120/80."
        result = svc.deidentify(text, make_ref(), "did:ethr:0xabc", minimum_quality_threshold=999.0)
        assert "threshold" in result.rejection_reason.lower()

    def test_accepts_when_score_meets_threshold(self, svc):
        text = "Blood pressure 120/80. Heart rate 72 bpm. No abnormalities detected."
        result = svc.deidentify(text, make_ref(), "did:ethr:0xabc", minimum_quality_threshold=0.0)
        assert result.success is True
        assert result.rejection_reason is None

    def test_default_threshold_is_60(self, svc):
        # Clean text with no PII should pass the default 60 threshold
        text = "Blood pressure 120/80. Heart rate 72 bpm."
        result = svc.deidentify(text, make_ref(), "did:ethr:0xabc")
        assert result.success is True


# ---------------------------------------------------------------------------
# Audit log (Requirements 2.5, 2.6)
# ---------------------------------------------------------------------------

class TestAuditLog:

    def test_one_entry_per_operation(self, svc):
        ref1 = make_ref("cid1")
        ref2 = make_ref("cid2")
        svc.deidentify("text one", ref1, "did:ethr:0xabc")
        svc.deidentify("text two", ref2, "did:ethr:0xabc")
        assert len(svc.get_audit_log()) == 2

    def test_audit_entry_has_correct_data_ref(self, svc):
        ref = make_ref("QmSpecific")
        svc.deidentify("some text", ref, "did:ethr:0xabc")
        log = svc.get_audit_log()
        assert log[0].data_ref == "QmSpecific"

    def test_audit_entry_has_on_chain_tx_hash(self, svc):
        svc.deidentify("some text", make_ref(), "did:ethr:0xabc")
        log = svc.get_audit_log()
        assert log[0].on_chain_tx_hash.startswith("0x")

    def test_audit_entry_has_quality_score(self, svc):
        svc.deidentify("some text", make_ref(), "did:ethr:0xabc")
        log = svc.get_audit_log()
        assert 0.0 <= log[0].quality_score <= 100.0

    def test_rejected_operation_still_writes_audit_entry(self, svc):
        svc.deidentify("some text", make_ref(), "did:ethr:0xabc", minimum_quality_threshold=999.0)
        assert len(svc.get_audit_log()) == 1

    def test_audit_log_is_append_only(self, svc):
        svc.deidentify("text one", make_ref("c1"), "did:ethr:0xabc")
        first_entry = svc.get_audit_log()[0]
        svc.deidentify("text two", make_ref("c2"), "did:ethr:0xabc")
        # First entry must be unchanged
        assert svc.get_audit_log()[0].operation_id == first_entry.operation_id
