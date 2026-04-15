from __future__ import annotations

import pickle
from pathlib import Path
from typing import Any, Union

import numpy as np
from sklearn.metrics import mean_absolute_error, mean_poisson_deviance, mean_squared_error

DEFAULT_MODEL_ARTIFACT_RELATIVE_PATH = Path("artifacts") / "negative_binomial_b4.pkl"
DEFAULT_MODEL_ARTIFACT_PATH = Path(__file__).resolve().parents[1] / DEFAULT_MODEL_ARTIFACT_RELATIVE_PATH

__all__ = [
    "load_model",
    "save_model",
    "rebuild_parquet_from_raw",
    "train_model",
    "update_model",
    "predict",
    "evaluate_model",
    "get_default_model_path",
]


def _resolve_model_path(path: Union[str, Path, None] = None) -> Path:
    return Path(path) if path is not None else DEFAULT_MODEL_ARTIFACT_PATH


def load_model(path: Union[str, Path, None] = None) -> Any:
    """Load a serialized ROAD-SAFETY model artifact."""
    resolved_path = _resolve_model_path(path)
    try:
        with open(resolved_path, "rb") as file:
            return pickle.load(file)
    except OSError as e:
        raise RuntimeError(f"Error loading model from '{resolved_path}': {e}") from e
    except pickle.PickleError as e:
        raise RuntimeError(f"Invalid pickle artifact at '{resolved_path}': {e}") from e


def save_model(model: Any, path: Union[str, Path, None] = None) -> bool:
    """Save a serialized ROAD-SAFETY model artifact."""
    try:
        resolved_path = _resolve_model_path(path)
        resolved_path.parent.mkdir(parents=True, exist_ok=True)
        with open(resolved_path, "wb") as file:
            pickle.dump(model, file, protocol=pickle.HIGHEST_PROTOCOL)
        return True
    except (OSError, pickle.PickleError) as e:
        print(f"Error saving model: {e}")
        return False


def rebuild_parquet_from_raw(path: Union[str, Path, None] = None, *, force: bool = False) -> Path:
    """
    Rebuild the final minable parquet from local raw inputs through the single
    internal raw-data pipeline entrypoint.
    """
    from src.internal_pipeline.runners.rebuild_from_raw import (
        rebuild_parquet_from_raw as _rebuild_parquet_from_raw,
    )

    return _rebuild_parquet_from_raw(path=path, force=force)


def train_model(path: Union[str, Path, None] = None, *, force: bool = False) -> Any:
    """
    Train or refresh the active final ROAD-SAFETY model through a single
    internal training entrypoint.

    If `path` is provided, the trained artifact is also saved there.
    """
    from src.internal_model.train_final_model import train_final_model as _train_final_model

    model, artifact_path = _train_final_model(force=force)

    destination = _resolve_model_path(path)
    if destination.resolve() != artifact_path.resolve():
        if not save_model(model, destination):
            raise RuntimeError(f"Failed to save trained model artifact to '{destination}'.")

    return model


def update_model(path: Union[str, Path, None] = None) -> Any:
    """Force retraining of the active final ROAD-SAFETY model."""
    return train_model(path=path, force=True)


def get_default_model_path() -> Path:
    """Return the default serialized artifact path for the active final model."""
    return DEFAULT_MODEL_ARTIFACT_PATH


def predict(model: Any, X):
    """
    Predict expected accident counts.

    The loaded artifact must expose a `predict(X)` method and `X` must satisfy
    the input contract expected by the serialized final model artifact.
    """
    if not hasattr(model, "predict"):
        raise TypeError("Loaded model artifact does not expose a predict(X) method.")
    return model.predict(X)


def evaluate_model(model: Any, X, y_true) -> dict[str, float]:
    """Evaluate a count model with regression/count metrics."""
    y_pred = np.asarray(predict(model, X), dtype=float)
    y_true = np.asarray(y_true, dtype=float)

    return {
        "mean_poisson_deviance": float(mean_poisson_deviance(y_true, y_pred)),
        "mae": float(mean_absolute_error(y_true, y_pred)),
        "rmse": float(np.sqrt(mean_squared_error(y_true, y_pred))),
        "target_mean": float(np.mean(y_true)),
        "predicted_mean": float(np.mean(y_pred)),
    }
