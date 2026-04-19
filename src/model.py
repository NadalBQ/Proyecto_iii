from __future__ import annotations

import pickle
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Union

import numpy as np
import pandas as pd
from sklearn.metrics import mean_absolute_error, mean_poisson_deviance, mean_squared_error
import statsmodels.api as sm
import statsmodels.discrete.discrete_model as smd


TRAIN_YEARS = list(range(2016, 2023))
VALIDATION_YEARS = [2023]
TEST_YEARS = [2024]

NEGATIVE_BINOMIAL_B4_MODEL_NAME = "negative_binomial_b4"
NEGATIVE_BINOMIAL_B4_MODEL_FAMILY = "negative_binomial"
NEGATIVE_BINOMIAL_B4_TARGET_COLUMN = "accident_count"
NEGATIVE_BINOMIAL_B4_UNIT_COLUMNS = ["edge_id", "analysis_year", "temporal_bin_4h", "is_weekend"]
NEGATIVE_BINOMIAL_B4_ARTIFACT_RELATIVE_PATH = Path("artifacts") / "negative_binomial_b4.pkl"
FINAL_MINABLE_VIEW_RELATIVE_PATH = (
    Path("outputs") / "modeling" / "training_table_with_exogenous_context_features.parquet"
)

RECENT_DYNAMIC_NEUTRAL_VALUE = 50.0
NB_MAX_ITER = 100
NB_FALLBACK_SAMPLE_N = 250_000
NB_RANDOM_SEED = 20260411

A4B4_FEATURE_SOURCES = {
    "log_edge_length_m": "edge_length_m",
    "analysis_year_offset": "analysis_year",
    "hour_sin": "hour_sin",
    "hour_cos": "hour_cos",
    "is_weekend_int": "is_weekend",
    "log1p_edge_accident_count_prior_total": "edge_accident_count_prior_total",
    "log1p_edge_bin_accident_count_prior": "edge_bin_accident_count_prior",
    "log1p_edge_accident_count_prior_recent_3y": "edge_accident_count_prior_recent_3y",
    "log1p_edge_bin_accident_count_prior_recent_3y": "edge_bin_accident_count_prior_recent_3y",
    "prior_dynamic_context_signal_recent_3y_imputed": "prior_dynamic_context_signal_recent_3y",
    "log1p_prior_context_observation_n_recent_3y": "prior_context_observation_n_recent_3y",
    "prior_dynamic_context_recent_missing_flag": "prior_dynamic_context_signal_recent_3y_missing_flag",
    "ctx_recent_fallback_edge_bin_weekend": "prior_dynamic_context_signal_recent_3y_fallback_level",
    "ctx_recent_fallback_edge_bin": "prior_dynamic_context_signal_recent_3y_fallback_level",
    "ctx_recent_fallback_global_bin_weekend": "prior_dynamic_context_signal_recent_3y_fallback_level",
    "exog_road_class_is_major_flag": "exog_road_class_is_major_flag",
    "exog_maxspeed_kph_imputed_by_road_class": "exog_maxspeed_kph_imputed_by_road_class",
    "exog_maxspeed_missing_flag": "exog_maxspeed_missing_flag",
    "exog_oneway_code_b_flag": "exog_oneway_code_b_flag",
    "exog_tunnel_flag": "exog_tunnel_flag",
    "exog_node_degree_mean": "exog_node_degree_mean",
    "exog_edge_touches_dead_end_flag": "exog_edge_touches_dead_end_flag",
    "exog_distance_from_network_centroid_km": "exog_distance_from_network_centroid_km",
    "exog_temporal_is_night_flag": "exog_temporal_is_night_flag",
    "exog_temporal_is_weekday_peak_flag": "exog_temporal_is_weekday_peak_flag",
}

NEGATIVE_BINOMIAL_B4_REQUIRED_INPUT_COLUMNS = sorted(
    set(A4B4_FEATURE_SOURCES.values()) | set(NEGATIVE_BINOMIAL_B4_UNIT_COLUMNS)
)

DEFAULT_MODEL_ARTIFACT_PATH = Path(__file__).resolve().parents[1] / NEGATIVE_BINOMIAL_B4_ARTIFACT_RELATIVE_PATH
DEFAULT_TRAINING_TABLE_PATH = Path(__file__).resolve().parents[1] / FINAL_MINABLE_VIEW_RELATIVE_PATH
LEGACY_ARTIFACT_MODULE = "src.internal_model.final_model_artifact"

__all__ = [
    "load_model",
    "save_model",
    "train_model",
    "update_model",
    "predict",
    "test_model",
    "evaluate_model",
    "get_default_model_path",
    "NegativeBinomialB4Artifact",
    "validate_negative_binomial_b4_input",
    "add_a4b4_features",
    "get_a4b4_feature_matrix",
    "add_a4b4_constant",
    "build_negative_binomial_b4_artifact",
]


def _resolve_model_path(path: Union[str, Path, None] = None) -> Path:
    return Path(path) if path is not None else DEFAULT_MODEL_ARTIFACT_PATH


class _RoadSafetyArtifactUnpickler(pickle.Unpickler):
    """Remap legacy model artifact classes to the current src.model location."""

    def find_class(self, module: str, name: str) -> Any:
        if module == LEGACY_ARTIFACT_MODULE and name in globals():
            return globals()[name]
        return super().find_class(module, name)


def _load_artifact(path: Path) -> Any:
    with open(path, "rb") as file:
        return _RoadSafetyArtifactUnpickler(file).load()


def _save_artifact(model: Any, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "wb") as file:
        pickle.dump(model, file, protocol=pickle.HIGHEST_PROTOCOL)


def get_default_model_path() -> Path:
    """Return the default serialized artifact path for the active final model."""
    return DEFAULT_MODEL_ARTIFACT_PATH


def validate_negative_binomial_b4_input(
    df: pd.DataFrame,
    *,
    require_target: bool = False,
) -> None:
    required = set(NEGATIVE_BINOMIAL_B4_REQUIRED_INPUT_COLUMNS)
    if require_target:
        required.add(NEGATIVE_BINOMIAL_B4_TARGET_COLUMN)

    missing = sorted(required - set(df.columns))
    if missing:
        raise ValueError(f"Missing required columns for {NEGATIVE_BINOMIAL_B4_MODEL_NAME}: {missing}")


def add_a4b4_features(df: pd.DataFrame) -> pd.DataFrame:
    validate_negative_binomial_b4_input(df, require_target=False)

    result = df.copy()
    result["log_edge_length_m"] = np.log(result["edge_length_m"])
    result["analysis_year_offset"] = result["analysis_year"] - min(TRAIN_YEARS)
    result["is_weekend_int"] = result["is_weekend"].astype(int)
    result["log1p_edge_accident_count_prior_total"] = np.log1p(result["edge_accident_count_prior_total"])
    result["log1p_edge_bin_accident_count_prior"] = np.log1p(result["edge_bin_accident_count_prior"])
    result["log1p_edge_accident_count_prior_recent_3y"] = np.log1p(result["edge_accident_count_prior_recent_3y"])
    result["log1p_edge_bin_accident_count_prior_recent_3y"] = np.log1p(result["edge_bin_accident_count_prior_recent_3y"])

    result["prior_dynamic_context_signal_recent_3y_imputed"] = pd.to_numeric(
        result["prior_dynamic_context_signal_recent_3y"], errors="coerce"
    ).fillna(RECENT_DYNAMIC_NEUTRAL_VALUE)

    result["log1p_prior_context_observation_n_recent_3y"] = np.log1p(
        pd.to_numeric(result["prior_context_observation_n_recent_3y"], errors="coerce").fillna(0)
    )

    result["prior_dynamic_context_recent_missing_flag"] = (
        result["prior_dynamic_context_signal_recent_3y_missing_flag"].astype(int)
    )

    fallback = result["prior_dynamic_context_signal_recent_3y_fallback_level"].fillna("unresolved").astype(str)
    result["ctx_recent_fallback_edge_bin_weekend"] = (fallback == "edge_bin_weekend").astype(int)
    result["ctx_recent_fallback_edge_bin"] = (fallback == "edge_bin").astype(int)
    result["ctx_recent_fallback_global_bin_weekend"] = (fallback == "global_bin_weekend").astype(int)

    for feature_name in [name for name in A4B4_FEATURE_SOURCES if name.startswith("exog_")]:
        result[feature_name] = pd.to_numeric(result[feature_name], errors="coerce")

    return result


def get_a4b4_feature_matrix(df: pd.DataFrame) -> pd.DataFrame:
    matrix = df[list(A4B4_FEATURE_SOURCES.keys())].copy()
    matrix = matrix.apply(pd.to_numeric, errors="coerce").astype(float)

    if matrix.isna().any().any():
        na_columns = matrix.columns[matrix.isna().any()].tolist()
        raise ValueError(f"Missing values found in {NEGATIVE_BINOMIAL_B4_MODEL_NAME} feature matrix: {na_columns}")

    return matrix


def add_a4b4_constant(X: pd.DataFrame) -> pd.DataFrame:
    return sm.add_constant(X, has_constant="add")


@dataclass
class NegativeBinomialB4Artifact:
    model_result: Any
    fit_method: str
    alpha_estimate: float
    converged: bool
    model_name: str = NEGATIVE_BINOMIAL_B4_MODEL_NAME
    family: str = NEGATIVE_BINOMIAL_B4_MODEL_FAMILY
    target_column: str = NEGATIVE_BINOMIAL_B4_TARGET_COLUMN
    unit_columns: list[str] = field(default_factory=lambda: NEGATIVE_BINOMIAL_B4_UNIT_COLUMNS.copy())
    feature_names: list[str] = field(default_factory=lambda: list(A4B4_FEATURE_SOURCES.keys()))
    required_input_columns: list[str] = field(
        default_factory=lambda: NEGATIVE_BINOMIAL_B4_REQUIRED_INPUT_COLUMNS.copy()
    )
    train_years: list[int] = field(default_factory=lambda: TRAIN_YEARS.copy())
    validation_years: list[int] = field(default_factory=lambda: VALIDATION_YEARS.copy())
    test_years: list[int] = field(default_factory=lambda: TEST_YEARS.copy())

    def predict(self, df: pd.DataFrame) -> np.ndarray:
        if self.model_result is None:
            raise ValueError(f"{self.model_name} artifact has no fitted model_result.")

        validate_negative_binomial_b4_input(df, require_target=False)
        transformed = add_a4b4_features(df)
        X = add_a4b4_constant(get_a4b4_feature_matrix(transformed))
        return np.asarray(self.model_result.predict(X), dtype=float)


def build_negative_binomial_b4_artifact(
    model_result: Any,
    *,
    fit_method: str,
    alpha_estimate: float,
    converged: bool,
) -> NegativeBinomialB4Artifact:
    return NegativeBinomialB4Artifact(
        model_result=model_result,
        fit_method=fit_method,
        alpha_estimate=float(alpha_estimate),
        converged=bool(converged),
    )


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
    y_sample = sample[NEGATIVE_BINOMIAL_B4_TARGET_COLUMN].to_numpy()
    sample_model = smd.NegativeBinomial(y_sample, X_sample)
    sample_result = sample_model.fit(disp=False, maxiter=NB_MAX_ITER)
    return max(float(sample_result.params["alpha"]), 1e-9)


def _fit_negative_binomial(train_df: pd.DataFrame) -> tuple[object, str, float, bool]:
    X_train = add_a4b4_constant(get_a4b4_feature_matrix(train_df))
    y_train = train_df[NEGATIVE_BINOMIAL_B4_TARGET_COLUMN].to_numpy()
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


def _train_active_final_model(*, force: bool = False) -> tuple[Any, Path]:
    artifact_path = DEFAULT_MODEL_ARTIFACT_PATH
    training_table_path = DEFAULT_TRAINING_TABLE_PATH

    if artifact_path.exists() and not force:
        return _load_artifact(artifact_path), artifact_path

    if not training_table_path.exists():
        raise RuntimeError(
            "Local retraining requires "
            f"'{training_table_path}'. This branch retrains from the final minable "
            "view stored in outputs/modeling/ and does not rebuild it from raw inputs."
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


def load_model(path: Union[str, Path, None] = None) -> Any:
    """Load a serialized ROAD-SAFETY model artifact."""
    resolved_path = _resolve_model_path(path)
    try:
        return _load_artifact(resolved_path)
    except OSError as e:
        raise RuntimeError(f"Error loading model from '{resolved_path}': {e}") from e
    except pickle.PickleError as e:
        raise RuntimeError(f"Invalid pickle artifact at '{resolved_path}': {e}") from e


def save_model(model: Any, path: Union[str, Path, None] = None) -> bool:
    """Save a serialized ROAD-SAFETY model artifact."""
    try:
        _save_artifact(model, _resolve_model_path(path))
        return True
    except (OSError, pickle.PickleError) as e:
        print(f"Error saving model: {e}")
        return False


def train_model(path: Union[str, Path, None] = None, *, force: bool = False) -> Any:
    """
    Train or refresh the active final ROAD-SAFETY model from the local final parquet.

    If `path` is provided, the trained artifact is also saved there.
    """
    model, artifact_path = _train_active_final_model(force=force)

    destination = _resolve_model_path(path)
    if destination.resolve() != artifact_path.resolve():
        if not save_model(model, destination):
            raise RuntimeError(f"Failed to save trained model artifact to '{destination}'.")

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


def test_model(model: Any, X, y_true) -> dict[str, float]:
    """Test a count model with regression/count metrics."""
    y_pred = np.asarray(predict(model, X), dtype=float)
    y_true = np.asarray(y_true, dtype=float)

    return {
        "mean_poisson_deviance": float(mean_poisson_deviance(y_true, y_pred)),
        "mae": float(mean_absolute_error(y_true, y_pred)),
        "rmse": float(np.sqrt(mean_squared_error(y_true, y_pred))),
        "target_mean": float(np.mean(y_true)),
        "predicted_mean": float(np.mean(y_pred)),
    }


def evaluate_model(model: Any, X, y_true) -> dict[str, float]:
    """Backward-compatible alias for test_model()."""
    return test_model(model, X, y_true)
