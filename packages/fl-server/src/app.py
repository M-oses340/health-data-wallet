"""
app.py — Flask HTTP bridge between the TypeScript ComputationEngine and
the Flower federated learning simulation.

Endpoints:
  POST /fl/run   { contractId, numClients?, numRounds? }
               → { jobId, contractId, layerGradients, sampleCount, roundId, roundMetrics }

  GET  /health  → { status: "ok" }
"""
import logging
import uuid
from flask import Flask, jsonify, request

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

    logger.info("Starting FL job — contract=%s clients=%d rounds=%d",
                contract_id, num_clients, num_rounds)

    try:
        result = run_federated_learning(
            contract_id=contract_id,
            num_clients=num_clients,
            num_rounds=num_rounds,
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


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001, debug=False)
