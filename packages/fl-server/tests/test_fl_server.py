"""
Tests for the Flower federated learning server.

Validates:
  - FL simulation runs end-to-end and returns aggregated gradients
  - Raw data never appears in the result (only gradient arrays)
  - Round metrics are recorded per round
  - HTTP bridge returns correct shape
"""
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../src"))

import pytest
import numpy as np
from fl_server import run_federated_learning
from fl_client import HealthDataClient, _init_model, _get_model_params, _set_model_params


# ---------------------------------------------------------------------------
# FL client unit tests
# ---------------------------------------------------------------------------

class TestHealthDataClient:
    def test_get_parameters_returns_arrays(self):
        client = HealthDataClient("p1", n_features=10, seed=0)
        params = client.get_parameters({})
        assert len(params) >= 1
        assert all(isinstance(p, np.ndarray) for p in params)

    def test_fit_returns_updated_params(self):
        client = HealthDataClient("p1", n_features=10, seed=0)
        initial = client.get_parameters({})
        updated, n_samples, metrics = client.fit(initial, {})
        assert n_samples > 0
        assert len(updated) == len(initial)
        assert metrics["patient_id"] == "p1"

    def test_evaluate_returns_accuracy(self):
        client = HealthDataClient("p1", n_features=10, seed=0)
        params = client.get_parameters({})
        client.fit(params, {})
        loss, n_samples, metrics = client.evaluate(params, {})
        assert 0.0 <= metrics["accuracy"] <= 1.0
        assert n_samples > 0

    def test_raw_data_not_in_params(self):
        """Gradients must be float arrays — no patient record strings."""
        client = HealthDataClient("p1", n_features=10, seed=0)
        params, _, _ = client.fit(client.get_parameters({}), {})
        for p in params:
            assert p.dtype in (np.float32, np.float64), \
                "Parameters must be float arrays, not raw data"


# ---------------------------------------------------------------------------
# FL server simulation tests
# ---------------------------------------------------------------------------

class TestFederatedLearningSimulation:
    def test_run_returns_layer_gradients(self):
        result = run_federated_learning(
            contract_id="test-contract-001",
            num_clients=2,
            num_rounds=2,
        )
        assert "layer_gradients" in result
        assert "coef" in result["layer_gradients"]
        coef = result["layer_gradients"]["coef"]
        assert isinstance(coef, list)
        assert len(coef) > 0
        assert all(isinstance(v, float) for v in coef)

    def test_run_returns_correct_round_count(self):
        result = run_federated_learning(
            contract_id="test-contract-002",
            num_clients=2,
            num_rounds=3,
        )
        assert result["num_rounds"] == 3
        assert len(result["round_metrics"]) == 3

    def test_round_metrics_structure(self):
        result = run_federated_learning(
            contract_id="test-contract-003",
            num_clients=2,
            num_rounds=2,
        )
        for m in result["round_metrics"]:
            assert "round" in m
            assert "num_clients" in m
            assert m["num_clients"] == 2

    def test_sample_count_positive(self):
        result = run_federated_learning(
            contract_id="test-contract-004",
            num_clients=2,
            num_rounds=1,
        )
        assert result["sample_count"] > 0

    def test_round_id_deterministic(self):
        """Same contract_id + num_rounds must produce the same round_id."""
        r1 = run_federated_learning("stable-contract", num_clients=2, num_rounds=2)
        r2 = run_federated_learning("stable-contract", num_clients=2, num_rounds=2)
        assert r1["round_id"] == r2["round_id"]

    def test_no_raw_data_in_gradients(self):
        """Gradient values must be small floats — not patient record content."""
        result = run_federated_learning(
            contract_id="privacy-check-001",
            num_clients=2,
            num_rounds=2,
        )
        coef = result["layer_gradients"]["coef"]
        # Model weights from logistic regression are typically in [-10, 10]
        # Raw health data strings would not parse as floats at all
        for v in coef:
            assert isinstance(v, float), "Gradient must be a float"
            assert -1000 < v < 1000, "Suspiciously large gradient value"


# ---------------------------------------------------------------------------
# Flask HTTP bridge tests
# ---------------------------------------------------------------------------

class TestFlaskBridge:
    @pytest.fixture
    def client(self):
        import sys, os
        sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../src"))
        from app import app
        app.config["TESTING"] = True
        with app.test_client() as c:
            yield c

    def test_health_endpoint(self, client):
        resp = client.get("/health")
        assert resp.status_code == 200
        assert resp.get_json()["status"] == "ok"

    def test_fl_run_missing_contract_id(self, client):
        resp = client.post("/fl/run", json={})
        assert resp.status_code == 400
        assert "contractId" in resp.get_json()["error"]

    def test_fl_run_returns_gradients(self, client):
        resp = client.post("/fl/run", json={
            "contractId": "http-test-001",
            "numClients": 2,
            "numRounds": 2,
        })
        assert resp.status_code == 200
        data = resp.get_json()
        assert "layerGradients" in data
        assert "sampleCount" in data
        assert "roundId" in data
        assert "jobId" in data

    def test_fl_run_clamps_clients(self, client):
        """numClients > 10 should be clamped to 10."""
        resp = client.post("/fl/run", json={
            "contractId": "clamp-test",
            "numClients": 999,
            "numRounds": 1,
        })
        # Should not error — just clamped
        assert resp.status_code == 200
