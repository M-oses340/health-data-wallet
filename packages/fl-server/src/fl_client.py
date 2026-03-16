"""
fl_client.py — Flower federated learning client.

Each client represents a patient data silo. It trains a local logistic
regression model on anonymized health data and shares ONLY the model
parameters (gradients) with the server — raw data never leaves the silo.

Requirements: 4.2 — only model gradients returned, raw data stays in vault.
"""
import numpy as np
import flwr as fl
from sklearn.linear_model import LogisticRegression
from sklearn.datasets import make_classification
from sklearn.model_selection import train_test_split
from typing import Dict, List, Tuple


def _make_local_dataset(n_samples: int = 200, n_features: int = 10, seed: int = 42):
    """
    Simulate a patient's anonymized health dataset.
    In production this would be decrypted from the DataVault using the
    patient's consent token, then passed through the AnonymizerService.
    """
    X, y = make_classification(
        n_samples=n_samples,
        n_features=n_features,
        n_informative=5,
        random_state=seed,
    )
    return train_test_split(X, y, test_size=0.2, random_state=seed)


def _get_model_params(model: LogisticRegression) -> List[np.ndarray]:
    """Extract coef_ and intercept_ as a flat parameter list."""
    if model.fit_intercept:
        return [model.coef_, model.intercept_]
    return [model.coef_]


def _set_model_params(model: LogisticRegression, params: List[np.ndarray]) -> LogisticRegression:
    """Apply aggregated parameters from the server back to the local model."""
    model.coef_ = params[0]
    if model.fit_intercept:
        model.intercept_ = params[1]
    return model


def _init_model(n_features: int) -> LogisticRegression:
    model = LogisticRegression(
        max_iter=1,          # one local epoch per round
        warm_start=True,     # continue from previous round's weights
        solver="saga",
        C=1.0,
    )
    # sklearn requires a fit before coef_ exists — use a tiny dummy fit
    X_dummy = np.zeros((2, n_features))
    y_dummy = np.array([0, 1])
    model.fit(X_dummy, y_dummy)
    return model


class HealthDataClient(fl.client.NumPyClient):
    """
    Flower NumPyClient for a single patient data silo.

    - get_parameters: returns current local model weights
    - fit: trains one round on local data, returns updated weights + metrics
    - evaluate: evaluates global model on local held-out data
    """

    def __init__(self, patient_id: str, n_features: int = 10, seed: int = 42):
        self.patient_id = patient_id
        self.n_features = n_features
        self.X_train, self.X_test, self.y_train, self.y_test = _make_local_dataset(
            seed=seed
        )
        self.model = _init_model(n_features)

    def get_parameters(self, config: Dict) -> List[np.ndarray]:
        return _get_model_params(self.model)

    def fit(
        self, parameters: List[np.ndarray], config: Dict
    ) -> Tuple[List[np.ndarray], int, Dict]:
        _set_model_params(self.model, parameters)
        self.model.fit(self.X_train, self.y_train)
        updated_params = _get_model_params(self.model)
        return updated_params, len(self.X_train), {"patient_id": self.patient_id}

    def evaluate(
        self, parameters: List[np.ndarray], config: Dict
    ) -> Tuple[float, int, Dict]:
        _set_model_params(self.model, parameters)
        accuracy = float(self.model.score(self.X_test, self.y_test))
        loss = 1.0 - accuracy  # simple proxy loss
        return loss, len(self.X_test), {"accuracy": accuracy}
