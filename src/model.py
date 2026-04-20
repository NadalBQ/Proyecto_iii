import pickle
import shutil
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.metrics import mean_absolute_error, mean_poisson_deviance, mean_squared_error
import statsmodels.api as sm


def _resolve_path(path_like):
    return Path(path_like).expanduser().resolve()


def _get_r_entrypoint():
    return Path(__file__).with_name("build_final_parquet.R").resolve()


def _find_rscript():
    rscript_path = shutil.which("Rscript")
    if rscript_path is not None:
        return rscript_path

    common_roots = [Path(r"C:\Program Files\R"), Path(r"C:\Program Files (x86)\R")]
    for root in common_roots:
        if not root.exists():
            continue
        candidates = sorted(root.glob("R-*/bin/x64/Rscript.exe"), reverse=True)
        candidates.extend(sorted(root.glob("R-*/bin/Rscript.exe"), reverse=True))
        if candidates:
            return str(candidates[0])

    return None


def _prepare_numeric_frame(X):
    X = pd.DataFrame(X).copy().astype(float)
    X = X.replace([np.inf, -np.inf], np.nan).fillna(0.0)
    constant_columns = [column for column in X.columns if X[column].nunique(dropna=False) <= 1]
    if constant_columns:
        X = X.drop(columns=constant_columns)
    return X


def build_final_parquet(
    accidents_csv_path,
    output_parquet_path,
    network_zip_path=None,
    force=False,
):
    """Materialize the final training parquet through the single R entrypoint."""
    accidents_path = _resolve_path(accidents_csv_path)
    output_path = _resolve_path(output_parquet_path)

    missing_inputs = []
    if not accidents_path.exists():
        missing_inputs.append(str(accidents_path))

    network_path = None
    if network_zip_path is not None:
        network_path = _resolve_path(network_zip_path)
        if not network_path.exists():
            missing_inputs.append(str(network_path))

    if missing_inputs:
        raise FileNotFoundError(f"Missing required inputs for parquet build: {missing_inputs}")

    if output_path.exists() and not force:
        return output_path

    rscript_path = _find_rscript()
    if rscript_path is None:
        raise RuntimeError("Rscript is not available in PATH and no local R installation was found.")

    r_entrypoint = _get_r_entrypoint()
    if not r_entrypoint.exists():
        raise RuntimeError(f"Missing R build entrypoint: '{r_entrypoint}'.")

    output_path.parent.mkdir(parents=True, exist_ok=True)

    command = [
        rscript_path,
        str(r_entrypoint),
        "--accidents-csv",
        str(accidents_path),
        "--output-parquet",
        str(output_path),
    ]
    if network_path is not None:
        command.extend(["--network-zip", str(network_path)])
    if force:
        command.append("--force")

    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        details = "\n".join(part for part in [result.stdout.strip(), result.stderr.strip()] if part)
        raise RuntimeError(f"R parquet build failed.\n{details}".strip())

    if not output_path.exists():
        raise RuntimeError(f"R build finished without creating '{output_path}'.")

    return output_path


def train_model(X, y):
    """Train the final negative binomial model from feature matrix X and target y."""
    X = _prepare_numeric_frame(X)
    y = pd.Series(y).copy().astype(float)
    X = sm.add_constant(X, has_constant="add")
    model = sm.GLM(y, X, family=sm.families.NegativeBinomial())
    return model.fit()


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
    X = pd.DataFrame(X).copy().astype(float)
    X = X.replace([np.inf, -np.inf], np.nan).fillna(0.0)
    X = sm.add_constant(X, has_constant="add")

    expected_columns = [column for column in model.model.exog_names if column != "alpha"]
    missing_columns = [column for column in expected_columns if column != "const" and column not in X.columns]
    if missing_columns:
        raise ValueError(f"Missing columns for prediction: {missing_columns}")

    X = X.copy()
    if "const" in expected_columns and "const" not in X.columns:
        X["const"] = 1.0

    X = X[expected_columns]
    y_pred = np.asarray(model.predict(X), dtype=float)
    return np.nan_to_num(y_pred, nan=1e-9, posinf=1e9, neginf=1e-9)


def test_model(model, X, y):
    """Return simple evaluation metrics for a fitted model on test data."""
    y = np.asarray(y, dtype=float)
    y_pred = predict(model, X)
    y_pred = np.clip(y_pred, 1e-9, None)

    return {
        "mean_poisson_deviance": float(mean_poisson_deviance(y, y_pred)),
        "mae": float(mean_absolute_error(y, y_pred)),
        "rmse": float(np.sqrt(mean_squared_error(y, y_pred))),
    }
