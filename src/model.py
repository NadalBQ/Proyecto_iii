import pickle
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.metrics import mean_absolute_error, mean_poisson_deviance, mean_squared_error
import statsmodels.api as sm
import statsmodels.discrete.discrete_model as smd


def train_model(X, y):
    """Train the final negative binomial model from feature matrix X and target y."""
    X = pd.DataFrame(X).copy()
    y = pd.Series(y).copy()
    X = sm.add_constant(X, has_constant="add")
    model = smd.NegativeBinomial(y, X)
    return model.fit(disp=False)


def save_model(model, relative_path):
    """Save a fitted model to a relative .pkl path."""
    path = Path(relative_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as file:
        pickle.dump(model, file, protocol=pickle.HIGHEST_PROTOCOL)


def load_model(relative_path):
    """Load a fitted model from a relative .pkl path."""
    path = Path(relative_path)
    with path.open("rb") as file:
        return pickle.load(file)


def predict(model, X):
    """Generate predictions for X with a fitted model."""
    X = pd.DataFrame(X).copy()
    X = sm.add_constant(X, has_constant="add")

    expected_columns = [column for column in model.model.exog_names if column != "alpha"]
    missing_columns = [column for column in expected_columns if column != "const" and column not in X.columns]
    if missing_columns:
        raise ValueError(f"Missing columns for prediction: {missing_columns}")

    X = X.copy()
    if "const" in expected_columns and "const" not in X.columns:
        X["const"] = 1.0

    X = X[expected_columns]
    return np.asarray(model.predict(X), dtype=float)


def test_model(model, X, y):
    """Return simple evaluation metrics for a fitted model on test data."""
    y = np.asarray(y, dtype=float)
    y_pred = predict(model, X)

    return {
        "mean_poisson_deviance": float(mean_poisson_deviance(y, y_pred)),
        "mae": float(mean_absolute_error(y, y_pred)),
        "rmse": float(np.sqrt(mean_squared_error(y, y_pred))),
    }
