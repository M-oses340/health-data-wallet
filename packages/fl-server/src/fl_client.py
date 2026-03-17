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
from typing import Dict, List, Optional, Tuple


def _make_local_dataset(n_samples: int = 200, n_features: int = 10, seed: int = 42):
    """
    Simulate a patient's anonymized health dataset (fallback when no real data).
    """
    X, y = make_classification(
        n_samples=n_samples,
        n_features=n_features,
        n_informative=5,
        random_state=seed,
    )
    return train_test_split(X, y, test_size=0.2, random_state=seed)


def _dataset_from_real(records: List[Dict], n_features: int, seed: int = 42):
    """
    Build a training dataset from real vault records.

    Each record is a dict with numeric fields extracted from the patient's
    anonymized health data. We pad/truncate to n_features and derive a
    binary label from the first field (e.g. heartRate > median → 1).
    Falls back to synthetic data if records are empty or malformed.
    """
    if not records:
        return _make_local_dataset(n_features=n_features, seed=seed)

    rows = []
    for rec in records:
        # Flatten all numeric values from the record dict
        vals = [float(v) for v in rec.values() if isinstance(v, (int, float))]
        if not vals:
            continue
        # Pad or truncate to n_features
        if len(vals) < n_features:
            vals += [0.0] * (n_features - len(vals))
        rows.append(vals[:n_features])

    if len(rows) < 4:
        # Not enough real samples — fall back to synthetic
        return _make_local_dataset(n_features=n_features, seed=seed)

    X = np.array(rows, dtype=np.float32)
    # Binary label: first feature above its median → 1
    median_val = np.median(X[:, 0])
    y = (X[:, 0] > median_val).astype(int)

    # Ensure both classes present (required by sklearn)
    if len(np.unique(y)) < 2:
        y[0] = 1 - y[0]

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

    When real_records is provided the client trains on actual vault data;
    otherwise it falls back to synthetic data for dev/test.
    """

    def __init__(
        self,
        patient_id: str,
        n_features: int = 10,
        seed: int = 42,
        real_records: Optional[List[Dict]] = None,
    ):
        self.patient_id = patient_id
        self.n_features = n_features
        if real_records is not None:
            self.X_train, self.X_test, self.y_train, self.y_test = _dataset_from_real(
                real_records, n_features=n_features, seed=seed
            )
        else:
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
