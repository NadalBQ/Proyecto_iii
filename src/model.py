import shutil
import subprocess
from pathlib import Path

DEFAULT_OUTPUT_PARQUET = Path(
    "outputs/modeling/training_table_with_exogenous_context_features.parquet"
)


def _find_rscript():
    rscript_path = shutil.which("Rscript")
    if rscript_path:
        return rscript_path

    common_roots = [Path(r"C:\Program Files\R"), Path(r"C:\Program Files (x86)\R")]
    for root in common_roots:
        if not root.exists():
            continue
        candidates = sorted(root.glob("R-*/bin/x64/Rscript.exe"), reverse=True)
        candidates.extend(sorted(root.glob("R-*/bin/Rscript.exe"), reverse=True))
        if candidates:
            return str(candidates[0])

    raise RuntimeError("Rscript is not available in PATH and no local R installation was found.")


def build_final_parquet(
    accidents_csv_path,
    output_parquet_path=None,
    network_zip_path=None,
    force=False,
):
    accidents_path = Path(accidents_csv_path).expanduser().resolve()
    output_path = Path(output_parquet_path or DEFAULT_OUTPUT_PARQUET).expanduser().resolve()

    if not accidents_path.exists():
        raise FileNotFoundError(f"Missing CSV file: '{accidents_path}'.")

    network_path = None
    if network_zip_path is not None:
        network_path = Path(network_zip_path).expanduser().resolve()
        if not network_path.exists():
            raise FileNotFoundError(f"Missing network zip file: '{network_path}'.")

    if output_path.exists() and not force:
        return output_path

    rscript_path = _find_rscript()
    r_entrypoint = Path(__file__).with_name("build_final_parquet.R").resolve()

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


def build_training_xy(parquet_path, include_analysis_year=True):
    import numpy as np
    import pandas as pd

    parquet_path = Path(parquet_path).expanduser().resolve()
    table = pd.read_parquet(parquet_path)

    if "accident_count" not in table.columns:
        raise ValueError("Missing target column: 'accident_count'.")

    y = table["accident_count"].astype(float)
    X = table.drop(columns=["accident_count", "edge_id"], errors="ignore")

    if not include_analysis_year and "analysis_year" in X.columns:
        X = X.drop(columns=["analysis_year"])

    categorical_columns = X.select_dtypes(include=["object", "string", "category"]).columns.tolist()
    if categorical_columns:
        X = pd.get_dummies(X, columns=categorical_columns, dtype=float)

    X = X.replace([np.inf, -np.inf], np.nan).fillna(0.0).astype(float)
    constant_columns = [column for column in X.columns if X[column].nunique(dropna=False) <= 1]
    if constant_columns:
        X = X.drop(columns=constant_columns)

    return X, y


def build_and_train_model(
    accidents_csv_path,
    output_parquet_path=None,
    network_zip_path=None,
    force=False,
    include_analysis_year=True,
):
    parquet_path = build_final_parquet(
        accidents_csv_path=accidents_csv_path,
        output_parquet_path=output_parquet_path,
        network_zip_path=network_zip_path,
        force=force,
    )
    X, y = build_training_xy(parquet_path, include_analysis_year=include_analysis_year)
    model = train_model(X, y)
    return model, parquet_path


def train_model(X, y):
    import pandas as pd
    import statsmodels.api as sm

    X = pd.DataFrame(X).astype(float)
    y = pd.Series(y).astype(float)
    X = sm.add_constant(X, has_constant="add")
    model = sm.GLM(y, X, family=sm.families.NegativeBinomial())
    return model.fit()
