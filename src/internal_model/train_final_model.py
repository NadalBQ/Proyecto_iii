from __future__ import annotations

import pickle
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
import statsmodels.api as sm
import statsmodels.discrete.discrete_model as smd

from src.internal_model.final_model_artifact import (
    NEGATIVE_BINOMIAL_B4_ARTIFACT_RELATIVE_PATH,
    add_a4b4_constant,
    add_a4b4_features,
    build_negative_binomial_b4_artifact,
    get_a4b4_feature_matrix,
    validate_negative_binomial_b4_input,
    TRAIN_YEARS,
    VALIDATION_YEARS,
    TEST_YEARS,
)


FINAL_MINABLE_VIEW_RELATIVE_PATH = (
    Path("artifacts") / "training_table_with_exogenous_context_features.parquet"
)
NB_MAX_ITER = 100
NB_FALLBACK_SAMPLE_N = 250_000
NB_RANDOM_SEED = 20260411


def get_project_root() -> Path:
    return Path(__file__).resolve().parents[2]


def get_default_artifact_path() -> Path:
    return get_project_root() / NEGATIVE_BINOMIAL_B4_ARTIFACT_RELATIVE_PATH


def get_default_training_table_path() -> Path:
    return get_project_root() / FINAL_MINABLE_VIEW_RELATIVE_PATH


def _load_artifact(path: Path) -> Any:
    with open(path, "rb") as file:
        return pickle.load(file)


def _save_artifact(model: Any, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "wb") as file:
        pickle.dump(model, file, protocol=pickle.HIGHEST_PROTOCOL)


def _split_frames(df: pd.DataFrame) -> dict[str, pd.DataFrame]:
    return {
        "train": df.loc[df["analysis_year"].isin(TRAIN_YEARS)].copy(),
        "validation": df.loc[df["analysis_year"].isin(VALIDATION_YEARS)].copy(),
        "test": df.loc[df["analysis_year"].isin(TEST_YEARS)].copy(),
    }


def _ensure_nonempty_splits(split_frames_dict: dict[str, pd.DataFrame]) -> None:
    empty = [name for name, frame in split_frames_dict.items() if frame.empty]
    if empty:
        raise ValueError(f"Temporal split produced empty partitions: {empty}")


def _estimate_alpha_on_sample(train_df: pd.DataFrame) -> float:
    rng = np.random.default_rng(NB_RANDOM_SEED)
    sample_n = min(NB_FALLBACK_SAMPLE_N, len(train_df))
    sample_index = rng.choice(train_df.index.to_numpy(), size=sample_n, replace=False)
    sample = train_df.loc[sample_index].copy()
    X_sample = add_a4b4_constant(get_a4b4_feature_matrix(sample))
    y_sample = sample["accident_count"].to_numpy()
    sample_model = smd.NegativeBinomial(y_sample, X_sample)
    sample_result = sample_model.fit(disp=False, maxiter=NB_MAX_ITER)
    return max(float(sample_result.params["alpha"]), 1e-9)


def _fit_negative_binomial(train_df: pd.DataFrame) -> tuple[object, str, float, bool]:
    X_train = add_a4b4_constant(get_a4b4_feature_matrix(train_df))
    y_train = train_df["accident_count"].to_numpy()
    try:
        nb_model = smd.NegativeBinomial(y_train, X_train)
        nb_result = nb_model.fit(disp=False, maxiter=NB_MAX_ITER)
        converged = bool(nb_result.mle_retvals.get("converged", False))
        alpha = max(float(nb_result.params["alpha"]), 1e-9)
        if not converged:
            raise RuntimeError("NegativeBinomial MLE did not converge cleanly on full train.")
        return nb_result, "statsmodels.discrete.NegativeBinomial_mle", alpha, converged
    except Exception:
        alpha = _estimate_alpha_on_sample(train_df)
        glm_model = sm.GLM(y_train, X_train, family=sm.families.NegativeBinomial(alpha=alpha))
        glm_result = glm_model.fit(maxiter=NB_MAX_ITER, disp=False)
        converged = bool(getattr(glm_result, "converged", True))
        return glm_result, "statsmodels.GLM_NegativeBinomial_fixed_alpha", alpha, converged


def train_final_model(*, force: bool = False) -> tuple[Any, Path]:
    """
    Single internal training entrypoint for the active final model.

    In this group branch, retraining starts from the already materialized final
    minable view, not from raw inputs or `outputs/data/*`.
    """
    artifact_path = get_default_artifact_path()
    training_table_path = get_default_training_table_path()

    if artifact_path.exists() and not force:
        return _load_artifact(artifact_path), artifact_path

    if not training_table_path.exists():
        raise RuntimeError(
            "Local retraining requires "
            f"'{training_table_path}'. This branch retrains from the final minable "
            "view stored in artifacts/ and does not rebuild it from raw inputs."
        )

    df = pd.read_parquet(training_table_path)
    validate_negative_binomial_b4_input(df, require_target=True)
    df = add_a4b4_features(df)

    split_frames_dict = _split_frames(df)
    _ensure_nonempty_splits(split_frames_dict)

    model_result, fit_method, alpha_estimate, converged = _fit_negative_binomial(
        split_frames_dict["train"]
    )
    artifact = build_negative_binomial_b4_artifact(
        model_result,
        fit_method=fit_method,
        alpha_estimate=alpha_estimate,
        converged=converged,
    )
    _save_artifact(artifact, artifact_path)
    return artifact, artifact_path
