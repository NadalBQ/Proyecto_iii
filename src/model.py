from __future__ import annotations

import pickle
from pathlib import Path
from typing import Any, Union

import numpy as np
from sklearn.metrics import mean_absolute_error, mean_poisson_deviance, mean_squared_error


def load_model(path: Union[str, Path]) -> Any:
    """Load a serialized ROAD-SAFETY model artifact."""
    try:
        with open(path, "rb") as file:
            return pickle.load(file)
    except OSError as e:
        raise RuntimeError(f"Error loading model from '{path}': {e}") from e
    except pickle.PickleError as e:
        raise RuntimeError(f"Invalid pickle artifact at '{path}': {e}") from e


def save_model(model: Any, path: Union[str, Path]) -> bool:
    """Save a serialized ROAD-SAFETY model artifact."""
    try:
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "wb") as file:
            pickle.dump(model, file, protocol=pickle.HIGHEST_PROTOCOL)
        return True
    except (OSError, pickle.PickleError) as e:
        print(f"Error saving model: {e}")
        return False


def train_model(path: Union[str, Path, None] = None, *, force: bool = False) -> Any:
    """
    Train or refresh the active final ROAD-SAFETY model through the single
    internal training entrypoint in `modeling/`.

    If `path` is provided and differs from the default artifact location,
    the trained artifact is also saved there.
    """
    from modeling.train_final_model import train_final_model as _train_final_model

    model, artifact_path = _train_final_model(force=force)

    if path is not None:
        destination = Path(path)
        if destination.resolve() != artifact_path.resolve():
            save_model(model, destination)

    return model


def update_model(path: Union[str, Path, None] = None) -> Any:
    """Force retraining of the active final ROAD-SAFETY model."""
    return train_model(path=path, force=True)


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

