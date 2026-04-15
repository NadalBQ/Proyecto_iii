from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
import statsmodels.api as sm


TRAIN_YEARS = list(range(2016, 2023))
VALIDATION_YEARS = [2023]
TEST_YEARS = [2024]

NEGATIVE_BINOMIAL_B4_MODEL_NAME = "negative_binomial_b4"
NEGATIVE_BINOMIAL_B4_MODEL_FAMILY = "negative_binomial"
NEGATIVE_BINOMIAL_B4_TARGET_COLUMN = "accident_count"
NEGATIVE_BINOMIAL_B4_UNIT_COLUMNS = ["edge_id", "analysis_year", "temporal_bin_4h", "is_weekend"]
NEGATIVE_BINOMIAL_B4_ARTIFACT_RELATIVE_PATH = Path("artifacts") / "negative_binomial_b4.pkl"

RECENT_DYNAMIC_NEUTRAL_VALUE = 50.0

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
