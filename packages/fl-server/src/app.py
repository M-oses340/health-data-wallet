"""
app.py — Flask HTTP bridge between the TypeScript ComputationEngine and
the Flower federated learning simulation.

Endpoints:
  POST /fl/run      { contractId, numClients?, numRounds? }
                  → { jobId, contractId, layerGradients, sampleCount, roundId, roundMetrics }

  POST /anonymize   { text, patient_did, data_type, threshold? }
                  → { success, qualityScore, anonymizedCid, rejectionReason? }

  GET  /health    → { status: "ok" }
"""
import hashlib
import logging
import sys
import uuid
from flask import Flask, jsonify, request

# Anonymizer lives in packages/anonymizer/src — add to path when running standalone
import os
_anon_src = os.path.join(os.path.dirname(__file__), '..', '..', 'anonymizer', 'src')
if os.path.isdir(_anon_src):
    sys.path.insert(0, os.path.abspath(_anon_src))

try:
    from anonymizer_service import AnonymizerService
    from anonymizer_types import ContentReference, DataType
    _anonymizer = AnonymizerService()
    _anon_available = True
except ImportError:
    _anon_available = False

from fl_server import run_federated_learning

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)


@app.post("/fl/run")
def fl_run():
    body = request.get_json(force=True, silent=True) or {}
    contract_id = body.get("contractId")
    if not contract_id:
        return jsonify({"error": "contractId is required"}), 400

    num_clients = int(body.get("numClients", 3))
    num_rounds = int(body.get("numRounds", 3))

    # Clamp to sane limits
    num_clients = max(1, min(num_clients, 10))
    num_rounds = max(1, min(num_rounds, 10))

    # Optional real patient data: list of per-client record lists
    # Each element is a list of dicts with numeric health fields
    patient_data = body.get("patientData")  # None → synthetic fallback

    logger.info("Starting FL job — contract=%s clients=%d rounds=%d real_data=%s",
                contract_id, num_clients, num_rounds, patient_data is not None)

    try:
        result = run_federated_learning(
            contract_id=contract_id,
            num_clients=num_clients,
            num_rounds=num_rounds,
            patient_data=patient_data,
        )
        job_id = str(uuid.uuid4())
        return jsonify({
            "jobId": job_id,
            "contractId": result["contract_id"],
            "layerGradients": result["layer_gradients"],
            "sampleCount": result["sample_count"],
            "roundId": result["round_id"],
            "roundMetrics": result["round_metrics"],
        })
    except Exception as exc:
        logger.exception("FL job failed")
        return jsonify({"error": str(exc)}), 500


@app.get("/health")
def health():
    return jsonify({"status": "ok"})


@app.post("/anonymize")
def anonymize():
    """
    De-identify health text via the AnonymizerService.
    Body: { text, patient_did, data_type, threshold? }
    """
    if not _anon_available:
        return jsonify({"error": "Anonymizer not available"}), 503

    body = request.get_json(force=True, silent=True) or {}
    text = body.get("text", "")
    patient_did = body.get("patient_did", "unknown")
    data_type_str = body.get("data_type", "GENERAL")
    threshold = float(body.get("threshold", 60.0))

    try:
        data_type = DataType(data_type_str)
    except (ValueError, KeyError):
        data_type = DataType.GENERAL

    ref = ContentReference(
        cid="raw-" + hashlib.sha256(text.encode()).hexdigest()[:16],
        data_type=data_type,
        uploaded_at=0,
        encryption_key_ref="",
    )

    result = _anonymizer.deidentify(
        text=text,
        data_ref=ref,
        patient_did=patient_did,
        minimum_quality_threshold=threshold,
    )

    return jsonify({
        "success": result.success,
        "qualityScore": result.quality_score,
        "anonymizedCid": result.anonymized_data_ref.cid,
        "rejectionReason": result.rejection_reason,
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001, debug=False)
