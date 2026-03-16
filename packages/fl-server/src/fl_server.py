"""
fl_server.py — Flower federated learning server with FedAvg aggregation.

Runs a simulation using Flower's virtual client engine — no real network
sockets needed. The server aggregates model gradients from all patient
clients and returns the final global model parameters.

Requirements: 4.2 — raw data never leaves patient silos.
"""
import json
import logging
from typing import Dict, List, Optional, Tuple, Union

import numpy as np
import flwr as fl
from flwr.common import (
    FitRes,
    Parameters,
    Scalar,
    ndarrays_to_parameters,
    parameters_to_ndarrays,
)
from flwr.server.client_proxy import ClientProxy
from flwr.server.strategy import FedAvg

from fl_client import HealthDataClient, _init_model, _get_model_params

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Custom FedAvg strategy that captures the final aggregated result
# ---------------------------------------------------------------------------

class CapturingFedAvg(FedAvg):
    """
    Extends FedAvg to capture the final aggregated parameters and
    per-round metrics so the HTTP layer can return them to the caller.
    """

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.final_parameters: Optional[List[np.ndarray]] = None
        self.round_metrics: List[Dict] = []

    def aggregate_fit(
        self,
        server_round: int,
        results: List[Tuple[ClientProxy, FitRes]],
        failures: List[Union[Tuple[ClientProxy, FitRes], BaseException]],
    ) -> Tuple[Optional[Parameters], Dict[str, Scalar]]:
        aggregated_params, metrics = super().aggregate_fit(
            server_round, results, failures
        )
        if aggregated_params is not None:
            self.final_parameters = parameters_to_ndarrays(aggregated_params)

        round_info = {
            "round": server_round,
            "num_clients": len(results),
            "failures": len(failures),
        }
        self.round_metrics.append(round_info)
        logger.info("Round %d complete — %d clients, %d failures",
                    server_round, len(results), len(failures))
        return aggregated_params, metrics


# ---------------------------------------------------------------------------
# Simulation entry point
# ---------------------------------------------------------------------------

def run_federated_learning(
    contract_id: str,
    num_clients: int = 3,
    num_rounds: int = 3,
    n_features: int = 10,
) -> Dict:
    """
    Run a full federated learning simulation for a given contract.

    Each client represents a patient data silo. Flower's virtual client
    engine runs all clients in-process — no network required.

    Returns a dict with:
      - contract_id
      - num_rounds
      - num_clients
      - round_metrics: per-round aggregation stats
      - layer_gradients: final aggregated model weights (coef_ + intercept_)
      - sample_count: total training samples across all clients
      - round_id: deterministic identifier for this FL run
    """
    import hashlib

    # Seed per contract so results are reproducible for the same contract
    seed_base = int(hashlib.sha256(contract_id.encode()).hexdigest()[:8], 16)

    strategy = CapturingFedAvg(
        fraction_fit=1.0,          # use all available clients each round
        fraction_evaluate=1.0,
        min_fit_clients=num_clients,
        min_evaluate_clients=num_clients,
        min_available_clients=num_clients,
    )

    def client_fn(cid: str) -> fl.client.Client:
        seed = seed_base + int(cid)
        return HealthDataClient(
            patient_id=f"patient-{cid}",
            n_features=n_features,
            seed=seed % (2**31),
        ).to_client()

    # Run simulation
    fl.simulation.start_simulation(
        client_fn=client_fn,
        num_clients=num_clients,
        config=fl.server.ServerConfig(num_rounds=num_rounds),
        strategy=strategy,
    )

    # Extract final aggregated gradients
    final_params = strategy.final_parameters or []
    layer_gradients: Dict[str, List[float]] = {}
    if len(final_params) >= 1:
        layer_gradients["coef"] = final_params[0].flatten().tolist()
    if len(final_params) >= 2:
        layer_gradients["intercept"] = final_params[1].flatten().tolist()

    round_id = "fl-" + hashlib.sha256(
        f"{contract_id}:{num_rounds}".encode()
    ).hexdigest()[:12]

    return {
        "contract_id": contract_id,
        "num_rounds": num_rounds,
        "num_clients": num_clients,
        "round_metrics": strategy.round_metrics,
        "layer_gradients": layer_gradients,
        "sample_count": num_clients * 160,  # 200 samples × 0.8 train split
        "round_id": round_id,
    }
