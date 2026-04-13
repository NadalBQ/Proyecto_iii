from __future__ import annotations

import argparse
from pathlib import Path
import sys

import numpy as np
import pandas as pd

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from modeling.config import TEMPORAL_BIN_HOURS, TEMPORAL_BIN_LABELS, build_paths


FALLBACK_LEVELS = [
    ("edge_bin_weekend", ["edge_id", "temporal_bin_4h", "is_weekend"]),
    ("edge_bin", ["edge_id", "temporal_bin_4h"]),
    ("road_class_bin_weekend", ["road_class", "temporal_bin_4h", "is_weekend"]),
    ("global_bin_weekend", ["temporal_bin_4h", "is_weekend"]),
]

CURRENT_TABLE_UNSAFE_DUE_TO_LEAKAGE = {
    "context_reference_available": "Administrative flag tied to full-period contextual references.",
    "reference_feature_warning": "Administrative warning about reference-only full-period columns.",
}

CURRENT_TABLE_POTENTIALLY_REBUILDABLE = {
    "edge_years_observed_prior": "Not reused directly because zero-only controls inherit sampled support windows.",
    "historical_count_raw_full_period_reference": "Full-period accident-backed reference; only usable if rebuilt by cutoff.",
    "historical_count_weighted_full_period_reference": "Full-period accident-backed reference; only usable if rebuilt by cutoff.",
    "accidents_per_km_raw_full_period_reference": "Full-period density; not leak-safe as predictor.",
    "accidents_per_km_full_period_reference": "Full-period weighted density; not leak-safe as predictor.",
    "historical_score_prelim_full_period_reference": "Heuristic full-period score; not leak-safe as predictor.",
    "historical_exposure_adjusted_score_prelim_full_period_reference": "M11 full-period adjusted score; would require cutoff-specific rebuild.",
    "exposure_proxy_value_full_period_reference": "M11 full-period exposure proxy; would require cutoff-specific rebuild.",
    "exposure_quality_flag_full_period_reference": "M11 full-period quality flag; would require cutoff-specific rebuild.",
    "intensidad_context_full_period_reference": "M12 full-period contextual mean; rebuilt safely in this phase instead.",
    "ocupacion_context_full_period_reference": "M12 full-period contextual mean; rebuilt safely in this phase instead.",
    "dynamic_context_signal_prelim_full_period_reference": "M12 full-period contextual signal; rebuilt safely in this phase instead.",
    "context_observation_n_full_period_reference": "M12 full-period contextual support; rebuilt safely in this phase instead.",
    "context_data_quality_flag_full_period_reference": "M12 full-period contextual quality; would need cutoff-specific rebuild.",
}

SOURCE_PHASE_AUDIT = [
    {
        "source_phase": "M11",
        "source_column": "historical_exposure_adjusted_score_prelim",
        "audit_bucket": "potentially_rebuildable_as_lagged",
        "rebuild_status": "not_rebuilt_in_this_phase",
        "reason": "Requires cutoff-specific recomputation of the accident-backed exposure proxy and its edge crosswalk.",
    },
    {
        "source_phase": "M11",
        "source_column": "exposure_proxy_value",
        "audit_bucket": "potentially_rebuildable_as_lagged",
        "rebuild_status": "not_rebuilt_in_this_phase",
        "reason": "Would need cutoff-specific recomputation of sensor-edge evidence before each analysis year.",
    },
    {
        "source_phase": "M11",
        "source_column": "exposure_quality_flag",
        "audit_bucket": "potentially_rebuildable_as_lagged",
        "rebuild_status": "not_rebuilt_in_this_phase",
        "reason": "Depends on a cutoff-specific exposure proxy rebuild.",
    },
    {
        "source_phase": "M12",
        "source_column": "intensidad_context",
        "audit_bucket": "potentially_rebuildable_as_lagged",
        "rebuild_status": "rebuilt_in_this_phase",
        "reason": "Rebuilt safely as prior mean intensity using only years strictly before the row analysis_year.",
    },
    {
        "source_phase": "M12",
        "source_column": "ocupacion_context",
        "audit_bucket": "potentially_rebuildable_as_lagged",
        "rebuild_status": "rebuilt_in_this_phase",
        "reason": "Rebuilt safely as prior mean occupancy using only years strictly before the row analysis_year.",
    },
    {
        "source_phase": "M12",
        "source_column": "dynamic_context_signal_prelim",
        "audit_bucket": "potentially_rebuildable_as_lagged",
        "rebuild_status": "rebuilt_in_this_phase",
        "reason": "Rebuilt safely from prior contextual intensity/occupancy means after fallback resolution.",
    },
    {
        "source_phase": "M12",
        "source_column": "context_observation_n",
        "audit_bucket": "potentially_rebuildable_as_lagged",
        "rebuild_status": "rebuilt_in_this_phase",
        "reason": "Rebuilt safely as prior joint support count with explicit fallback.",
    },
]

NEW_CONTEXTUAL_FEATURES = [
    {
        "column_name": "prior_mean_intensity_context",
        "feature_family": "contextual_mean",
        "temporal_window": "all_prior_years",
        "definition": "Prior mean traffic intensity for the row context after hierarchical fallback.",
        "support_column": "prior_mean_intensity_context_support_n",
    },
    {
        "column_name": "prior_mean_occupacion_context",
        "feature_family": "contextual_mean",
        "temporal_window": "all_prior_years",
        "definition": "Prior mean traffic occupancy for the row context after hierarchical fallback.",
        "support_column": "prior_mean_occupacion_context_support_n",
    },
    {
        "column_name": "prior_mean_intensity_context_recent_3y",
        "feature_family": "contextual_mean",
        "temporal_window": "recent_3y",
        "definition": "Trailing three-year prior mean traffic intensity for the row context after hierarchical fallback.",
        "support_column": "prior_mean_intensity_context_recent_3y_support_n",
    },
    {
        "column_name": "prior_mean_occupacion_context_recent_3y",
        "feature_family": "contextual_mean",
        "temporal_window": "recent_3y",
        "definition": "Trailing three-year prior mean traffic occupancy for the row context after hierarchical fallback.",
        "support_column": "prior_mean_occupacion_context_recent_3y_support_n",
    },
    {
        "column_name": "prior_dynamic_context_signal",
        "feature_family": "contextual_signal",
        "temporal_window": "all_prior_years",
        "definition": "Leak-safe contextual signal derived from prior joint intensity/occupancy means after fallback resolution.",
        "support_column": "prior_dynamic_context_signal_support_n",
    },
    {
        "column_name": "prior_dynamic_context_signal_recent_3y",
        "feature_family": "contextual_signal",
        "temporal_window": "recent_3y",
        "definition": "Leak-safe recent contextual signal derived from trailing three-year joint intensity/occupancy means after fallback resolution.",
        "support_column": "prior_dynamic_context_signal_recent_3y_support_n",
    },
    {
        "column_name": "prior_context_observation_n",
        "feature_family": "context_support",
        "temporal_window": "all_prior_years",
        "definition": "Joint prior contextual support count used to build the leak-safe dynamic signal.",
        "support_column": "prior_context_observation_n",
    },
    {
        "column_name": "prior_context_observation_n_recent_3y",
        "feature_family": "context_support",
        "temporal_window": "recent_3y",
        "definition": "Joint trailing three-year contextual support count used to build the leak-safe dynamic signal.",
        "support_column": "prior_context_observation_n_recent_3y",
    },
]

LEVEL_OUTPUT_COLUMNS = [
    "analysis_year",
    "prior_mean_intensity_context",
    "prior_mean_intensity_context_support_n",
    "prior_mean_intensity_context_recent_3y",
    "prior_mean_intensity_context_recent_3y_support_n",
    "prior_mean_occupacion_context",
    "prior_mean_occupacion_context_support_n",
    "prior_mean_occupacion_context_recent_3y",
    "prior_mean_occupacion_context_recent_3y_support_n",
    "prior_joint_mean_intensity_context",
    "prior_joint_mean_intensity_context_recent_3y",
    "prior_joint_mean_occupacion_context",
    "prior_joint_mean_occupacion_context_recent_3y",
    "prior_context_observation_n",
    "prior_context_observation_n_recent_3y",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build ROAD-SAFETY leak-safe contextual features for future A3/B3 baselines."
    )
    parser.add_argument("--force", action="store_true", help="Rebuild outputs even if they already exist.")
    return parser.parse_args()


def validate_required_inputs(paths) -> None:
    required = [
        paths.training_with_lag_safe_features_parquet,
        paths.m9_matches_csv,
        paths.accident_master_csv,
        paths.m11_historical_adjusted_csv,
        paths.m12_dynamic_base_csv,
    ]
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        raise FileNotFoundError(f"Missing required inputs for contextual lag-safe feature phase: {missing}")


def load_base_table(paths) -> pd.DataFrame:
    base = pd.read_parquet(paths.training_with_lag_safe_features_parquet)
    duplicate_n = int(base.duplicated(["edge_id", "analysis_year", "temporal_bin_4h", "is_weekend"]).sum())
    if duplicate_n > 0:
        raise ValueError(f"Base training table is not unique at panel level; duplicates found: {duplicate_n}")
    return base


def extract_hour_of_day(series: pd.Series) -> pd.Series:
    return pd.to_numeric(series.astype(str).str.extract(r"^\s*(\d{1,2})")[0], errors="coerce")


def build_temporal_bin(hour_of_day: pd.Series) -> tuple[pd.Series, pd.Series]:
    start_hour = ((hour_of_day // TEMPORAL_BIN_HOURS) * TEMPORAL_BIN_HOURS).astype("Int64")
    label_map = {start: label for start, label in zip(range(0, 24, TEMPORAL_BIN_HOURS), TEMPORAL_BIN_LABELS)}
    return start_hour, start_hour.map(label_map)


def load_context_events(paths, base: pd.DataFrame) -> tuple[pd.DataFrame, dict[str, int]]:
    matches = pd.read_csv(
        paths.m9_matches_csv,
        usecols=["num_expediente", "edge_id", "match_status"],
        dtype={"num_expediente": str, "edge_id": str, "match_status": str},
    )
    matches = matches.loc[matches["match_status"] == "matched", ["num_expediente", "edge_id"]].copy()

    master = pd.read_csv(
        paths.accident_master_csv,
        usecols=["num_expediente", "fecha", "hora", "intensidad", "ocupacion"],
        dtype={"num_expediente": str},
    )
    master["fecha"] = pd.to_datetime(master["fecha"], errors="coerce", dayfirst=True)
    master["hour_of_day"] = extract_hour_of_day(master["hora"])
    master["intensidad"] = pd.to_numeric(master["intensidad"], errors="coerce")
    master["ocupacion"] = pd.to_numeric(master["ocupacion"], errors="coerce")

    events = matches.merge(master, on="num_expediente", how="left")
    road_class_lookup = base[["edge_id", "road_class"]].drop_duplicates()
    events = events.merge(road_class_lookup, on="edge_id", how="left")

    events["analysis_year"] = events["fecha"].dt.year.astype("Int64")
    events["temporal_bin_start_hour"], events["temporal_bin_4h"] = build_temporal_bin(events["hour_of_day"])
    events["is_weekend"] = (events["fecha"].dt.dayofweek >= 5).astype("boolean")

    diagnostics = {
        "matched_accidents_total_n": int(len(events)),
        "matched_missing_master_fields_n": int(events["fecha"].isna().sum()),
        "matched_missing_road_class_n": int(events["road_class"].isna().sum()),
    }

    valid_mask = (
        events["edge_id"].notna()
        & events["analysis_year"].notna()
        & events["temporal_bin_4h"].notna()
        & events["is_weekend"].notna()
    )
    diagnostics["matched_context_rows_valid_panel_n"] = int(valid_mask.sum())
    diagnostics["matched_context_rows_invalid_panel_n"] = int((~valid_mask).sum())

    events = events.loc[valid_mask].copy()
    events["analysis_year"] = events["analysis_year"].astype(int)
    events["road_class"] = events["road_class"].fillna("unknown").astype(str)
    events["is_weekend"] = events["is_weekend"].astype(bool)

    diagnostics["matched_with_intensity_n"] = int(events["intensidad"].notna().sum())
    diagnostics["matched_with_occupacion_n"] = int(events["ocupacion"].notna().sum())
    diagnostics["matched_with_joint_context_n"] = int(
        (events["intensidad"].notna() & events["ocupacion"].notna()).sum()
    )
    return events, diagnostics


def aggregate_yearly_context(events: pd.DataFrame, key_cols: list[str]) -> pd.DataFrame:
    work = events[key_cols + ["analysis_year", "num_expediente", "intensidad", "ocupacion"]].copy()
    work["has_intensity"] = work["intensidad"].notna().astype(int)
    work["has_occupacion"] = work["ocupacion"].notna().astype(int)
    work["joint_mask"] = (work["has_intensity"].eq(1) & work["has_occupacion"].eq(1)).astype(int)
    work["joint_intensity"] = np.where(work["joint_mask"].eq(1), work["intensidad"], 0.0)
    work["joint_occupacion"] = np.where(work["joint_mask"].eq(1), work["ocupacion"], 0.0)

    grouped = (
        work.groupby(key_cols + ["analysis_year"], as_index=False)
        .agg(
            intensity_sum=("intensidad", "sum"),
            intensity_n=("has_intensity", "sum"),
            occupacion_sum=("ocupacion", "sum"),
            occupacion_n=("has_occupacion", "sum"),
            joint_intensity_sum=("joint_intensity", "sum"),
            joint_occupacion_sum=("joint_occupacion", "sum"),
            joint_n=("joint_mask", "sum"),
        )
        .sort_values(key_cols + ["analysis_year"])
        .reset_index(drop=True)
    )
    return grouped


def build_level_prior_stats(agg: pd.DataFrame, key_cols: list[str], all_years: list[int]) -> pd.DataFrame:
    if agg.empty:
        return pd.DataFrame(columns=key_cols + LEVEL_OUTPUT_COLUMNS)

    keys = agg[key_cols].drop_duplicates().copy()
    years_df = pd.DataFrame({"analysis_year": all_years})
    keys["__join_key"] = 1
    years_df["__join_key"] = 1
    grid = keys.merge(years_df, on="__join_key", how="inner").drop(columns="__join_key")
    grid = grid.merge(agg, on=key_cols + ["analysis_year"], how="left")

    fill_zero_cols = [
        "intensity_sum",
        "intensity_n",
        "occupacion_sum",
        "occupacion_n",
        "joint_intensity_sum",
        "joint_occupacion_sum",
        "joint_n",
    ]
    for column in fill_zero_cols:
        grid[column] = grid[column].fillna(0.0 if "sum" in column else 0)

    grid = grid.sort_values(key_cols + ["analysis_year"]).reset_index(drop=True)
    grouped = grid.groupby(key_cols, sort=False, observed=True)

    def add_prior_mean_features(sum_col: str, count_col: str, mean_name: str, support_name: str) -> None:
        cumulative_sum = grouped[sum_col].cumsum() - grid[sum_col]
        cumulative_n = grouped[count_col].cumsum() - grid[count_col]
        shift1_sum = grouped[sum_col].shift(1).fillna(0)
        shift2_sum = grouped[sum_col].shift(2).fillna(0)
        shift3_sum = grouped[sum_col].shift(3).fillna(0)
        shift1_n = grouped[count_col].shift(1).fillna(0)
        shift2_n = grouped[count_col].shift(2).fillna(0)
        shift3_n = grouped[count_col].shift(3).fillna(0)
        recent_sum = shift1_sum + shift2_sum + shift3_sum
        recent_n = shift1_n + shift2_n + shift3_n

        grid[support_name] = cumulative_n.astype(int)
        grid[mean_name] = np.where(cumulative_n > 0, cumulative_sum / cumulative_n, np.nan)
        grid[f"{mean_name}_recent_3y_support_n"] = recent_n.astype(int)
        grid[f"{mean_name}_recent_3y"] = np.where(recent_n > 0, recent_sum / recent_n, np.nan)

    add_prior_mean_features(
        "intensity_sum",
        "intensity_n",
        "prior_mean_intensity_context",
        "prior_mean_intensity_context_support_n",
    )
    add_prior_mean_features(
        "occupacion_sum",
        "occupacion_n",
        "prior_mean_occupacion_context",
        "prior_mean_occupacion_context_support_n",
    )
    add_prior_mean_features(
        "joint_intensity_sum",
        "joint_n",
        "prior_joint_mean_intensity_context",
        "prior_context_observation_n",
    )
    add_prior_mean_features(
        "joint_occupacion_sum",
        "joint_n",
        "prior_joint_mean_occupacion_context",
        "prior_context_observation_n_duplicate_for_joint",
    )

    grid["prior_context_observation_n_recent_3y"] = grid["prior_joint_mean_occupacion_context_recent_3y_support_n"]
    return grid[key_cols + LEVEL_OUTPUT_COLUMNS]


def initialize_context_columns(base: pd.DataFrame) -> pd.DataFrame:
    result = base.copy()
    result["__row_id"] = np.arange(len(result))

    value_columns = [
        "prior_mean_intensity_context",
        "prior_mean_occupacion_context",
        "prior_mean_intensity_context_recent_3y",
        "prior_mean_occupacion_context_recent_3y",
        "prior_dynamic_context_signal",
        "prior_dynamic_context_signal_recent_3y",
        "__selected_joint_intensity_context",
        "__selected_joint_occupacion_context",
        "__selected_joint_intensity_context_recent_3y",
        "__selected_joint_occupacion_context_recent_3y",
    ]
    for column in value_columns:
        result[column] = np.nan

    support_columns = [
        "prior_mean_intensity_context_support_n",
        "prior_mean_occupacion_context_support_n",
        "prior_mean_intensity_context_recent_3y_support_n",
        "prior_mean_occupacion_context_recent_3y_support_n",
        "prior_dynamic_context_signal_support_n",
        "prior_dynamic_context_signal_recent_3y_support_n",
        "prior_context_observation_n",
        "prior_context_observation_n_recent_3y",
    ]
    for column in support_columns:
        result[column] = 0

    for column in [
        "prior_mean_intensity_context",
        "prior_mean_occupacion_context",
        "prior_mean_intensity_context_recent_3y",
        "prior_mean_occupacion_context_recent_3y",
        "prior_dynamic_context_signal",
        "prior_dynamic_context_signal_recent_3y",
        "prior_context_observation_n",
        "prior_context_observation_n_recent_3y",
    ]:
        result[f"{column}_fallback_level"] = pd.NA

    return result


def apply_fallback_level(base: pd.DataFrame, level_df: pd.DataFrame, level_name: str, join_cols: list[str]) -> pd.DataFrame:
    needed_columns = [
        "analysis_year",
        "prior_mean_intensity_context",
        "prior_mean_intensity_context_support_n",
        "prior_mean_intensity_context_recent_3y",
        "prior_mean_intensity_context_recent_3y_support_n",
        "prior_mean_occupacion_context",
        "prior_mean_occupacion_context_support_n",
        "prior_mean_occupacion_context_recent_3y",
        "prior_mean_occupacion_context_recent_3y_support_n",
        "prior_joint_mean_intensity_context",
        "prior_joint_mean_intensity_context_recent_3y",
        "prior_joint_mean_occupacion_context",
        "prior_joint_mean_occupacion_context_recent_3y",
        "prior_context_observation_n",
        "prior_context_observation_n_recent_3y",
    ]
    temp_columns = {column: f"__{level_name}_{column}" for column in needed_columns if column != "analysis_year"}
    temp = level_df[join_cols + needed_columns].rename(columns=temp_columns)
    result = base.merge(temp, on=join_cols + ["analysis_year"], how="left", sort=False)

    def fill_scalar_feature(feature_name: str, support_name: str) -> None:
        temp_feature = f"__{level_name}_{feature_name}"
        temp_support = f"__{level_name}_{support_name}"
        mask = result[feature_name].isna() & result[temp_support].fillna(0).gt(0)
        if mask.any():
            result.loc[mask, feature_name] = result.loc[mask, temp_feature]
            result.loc[mask, support_name] = result.loc[mask, temp_support]
            result.loc[mask, f"{feature_name}_fallback_level"] = level_name

    fill_scalar_feature("prior_mean_intensity_context", "prior_mean_intensity_context_support_n")
    fill_scalar_feature("prior_mean_occupacion_context", "prior_mean_occupacion_context_support_n")
    fill_scalar_feature("prior_mean_intensity_context_recent_3y", "prior_mean_intensity_context_recent_3y_support_n")
    fill_scalar_feature("prior_mean_occupacion_context_recent_3y", "prior_mean_occupacion_context_recent_3y_support_n")

    joint_mask = result["__selected_joint_intensity_context"].isna() & result[f"__{level_name}_prior_context_observation_n"].fillna(0).gt(0)
    if joint_mask.any():
        result.loc[joint_mask, "__selected_joint_intensity_context"] = result.loc[
            joint_mask, f"__{level_name}_prior_joint_mean_intensity_context"
        ]
        result.loc[joint_mask, "__selected_joint_occupacion_context"] = result.loc[
            joint_mask, f"__{level_name}_prior_joint_mean_occupacion_context"
        ]
        result.loc[joint_mask, "prior_context_observation_n"] = result.loc[
            joint_mask, f"__{level_name}_prior_context_observation_n"
        ]
        result.loc[joint_mask, "prior_dynamic_context_signal_support_n"] = result.loc[
            joint_mask, f"__{level_name}_prior_context_observation_n"
        ]
        result.loc[joint_mask, "prior_dynamic_context_signal_fallback_level"] = level_name
        result.loc[joint_mask, "prior_context_observation_n_fallback_level"] = level_name

    joint_recent_mask = result["__selected_joint_intensity_context_recent_3y"].isna() & result[
        f"__{level_name}_prior_context_observation_n_recent_3y"
    ].fillna(0).gt(0)
    if joint_recent_mask.any():
        result.loc[joint_recent_mask, "__selected_joint_intensity_context_recent_3y"] = result.loc[
            joint_recent_mask, f"__{level_name}_prior_joint_mean_intensity_context_recent_3y"
        ]
        result.loc[joint_recent_mask, "__selected_joint_occupacion_context_recent_3y"] = result.loc[
            joint_recent_mask, f"__{level_name}_prior_joint_mean_occupacion_context_recent_3y"
        ]
        result.loc[joint_recent_mask, "prior_context_observation_n_recent_3y"] = result.loc[
            joint_recent_mask, f"__{level_name}_prior_context_observation_n_recent_3y"
        ]
        result.loc[joint_recent_mask, "prior_dynamic_context_signal_recent_3y_support_n"] = result.loc[
            joint_recent_mask, f"__{level_name}_prior_context_observation_n_recent_3y"
        ]
        result.loc[joint_recent_mask, "prior_dynamic_context_signal_recent_3y_fallback_level"] = level_name
        result.loc[joint_recent_mask, "prior_context_observation_n_recent_3y_fallback_level"] = level_name

    return result.drop(columns=list(temp_columns.values()))


def compute_group_rank_signal(
    df: pd.DataFrame,
    intensity_col: str,
    occupacion_col: str,
    output_col: str,
) -> pd.DataFrame:
    result = df.copy()
    valid_mask = result[intensity_col].notna() & result[occupacion_col].notna()
    result[output_col] = np.nan
    if not valid_mask.any():
        return result

    valid = result.loc[valid_mask, ["analysis_year", "temporal_bin_4h", "is_weekend", intensity_col, occupacion_col]].copy()
    group_cols = ["analysis_year", "temporal_bin_4h", "is_weekend"]
    valid["__intensity_rank01"] = valid.groupby(group_cols)[intensity_col].rank(method="average", pct=True)
    valid["__occupacion_rank01"] = valid.groupby(group_cols)[occupacion_col].rank(method="average", pct=True)
    signal = 100.0 * ((valid["__intensity_rank01"] + valid["__occupacion_rank01"]) / 2.0)
    result.loc[valid_mask, output_col] = signal.to_numpy()
    return result


def finalize_context_features(base: pd.DataFrame) -> pd.DataFrame:
    result = base.copy()
    result = compute_group_rank_signal(
        result,
        intensity_col="__selected_joint_intensity_context",
        occupacion_col="__selected_joint_occupacion_context",
        output_col="prior_dynamic_context_signal",
    )
    result = compute_group_rank_signal(
        result,
        intensity_col="__selected_joint_intensity_context_recent_3y",
        occupacion_col="__selected_joint_occupacion_context_recent_3y",
        output_col="prior_dynamic_context_signal_recent_3y",
    )

    value_columns = [
        "prior_mean_intensity_context",
        "prior_mean_occupacion_context",
        "prior_mean_intensity_context_recent_3y",
        "prior_mean_occupacion_context_recent_3y",
        "prior_dynamic_context_signal",
        "prior_dynamic_context_signal_recent_3y",
    ]
    support_columns = [
        "prior_mean_intensity_context_support_n",
        "prior_mean_occupacion_context_support_n",
        "prior_mean_intensity_context_recent_3y_support_n",
        "prior_mean_occupacion_context_recent_3y_support_n",
        "prior_dynamic_context_signal_support_n",
        "prior_dynamic_context_signal_recent_3y_support_n",
        "prior_context_observation_n",
        "prior_context_observation_n_recent_3y",
    ]
    fallback_columns = [
        "prior_mean_intensity_context_fallback_level",
        "prior_mean_occupacion_context_fallback_level",
        "prior_mean_intensity_context_recent_3y_fallback_level",
        "prior_mean_occupacion_context_recent_3y_fallback_level",
        "prior_dynamic_context_signal_fallback_level",
        "prior_dynamic_context_signal_recent_3y_fallback_level",
        "prior_context_observation_n_fallback_level",
        "prior_context_observation_n_recent_3y_fallback_level",
    ]

    for column in support_columns:
        result[column] = pd.to_numeric(result[column], errors="coerce").fillna(0).astype("Int64")

    for column in fallback_columns:
        result[column] = result[column].fillna("unresolved")

    for column in value_columns:
        result[f"{column}_missing_flag"] = result[column].isna()

    result["prior_context_observation_n_missing_flag"] = result["prior_context_observation_n"].eq(0)
    result["prior_context_observation_n_recent_3y_missing_flag"] = result["prior_context_observation_n_recent_3y"].eq(0)

    drop_columns = [
        "__selected_joint_intensity_context",
        "__selected_joint_occupacion_context",
        "__selected_joint_intensity_context_recent_3y",
        "__selected_joint_occupacion_context_recent_3y",
        "__row_id",
    ]
    return result.drop(columns=drop_columns)


def build_registry(base_columns: list[str]) -> pd.DataFrame:
    records = []
    for column in sorted(base_columns):
        if column in CURRENT_TABLE_UNSAFE_DUE_TO_LEAKAGE:
            records.append(
                {
                    "registry_section": "current_table_audit",
                    "column_name": column,
                    "audit_bucket": "unsafe_due_to_leakage",
                    "source_phase": "training_table_with_lag_safe_features",
                    "rebuild_status": "not_applicable",
                    "definition_or_reason": CURRENT_TABLE_UNSAFE_DUE_TO_LEAKAGE[column],
                    "support_column": pd.NA,
                    "missing_flag_column": pd.NA,
                    "fallback_level_column": pd.NA,
                }
            )
        elif column in CURRENT_TABLE_POTENTIALLY_REBUILDABLE:
            records.append(
                {
                    "registry_section": "current_table_audit",
                    "column_name": column,
                    "audit_bucket": "potentially_rebuildable_as_lagged",
                    "source_phase": "training_table_with_lag_safe_features",
                    "rebuild_status": "not_used_directly_in_this_phase",
                    "definition_or_reason": CURRENT_TABLE_POTENTIALLY_REBUILDABLE[column],
                    "support_column": pd.NA,
                    "missing_flag_column": pd.NA,
                    "fallback_level_column": pd.NA,
                }
            )
        else:
            records.append(
                {
                    "registry_section": "current_table_audit",
                    "column_name": column,
                    "audit_bucket": "safe_now",
                    "source_phase": "training_table_with_lag_safe_features",
                    "rebuild_status": "kept_as_is",
                    "definition_or_reason": "Current panel column considered safe to keep in the table at this stage.",
                    "support_column": pd.NA,
                    "missing_flag_column": pd.NA,
                    "fallback_level_column": pd.NA,
                }
            )

    for row in SOURCE_PHASE_AUDIT:
        records.append(
            {
                "registry_section": "source_phase_audit",
                "column_name": row["source_column"],
                "audit_bucket": row["audit_bucket"],
                "source_phase": row["source_phase"],
                "rebuild_status": row["rebuild_status"],
                "definition_or_reason": row["reason"],
                "support_column": pd.NA,
                "missing_flag_column": pd.NA,
                "fallback_level_column": pd.NA,
            }
        )

    for feature in NEW_CONTEXTUAL_FEATURES:
        records.append(
            {
                "registry_section": "new_contextual_feature",
                "column_name": feature["column_name"],
                "audit_bucket": "safe_now",
                "source_phase": "rebuilt_from_m9_plus_accident_master",
                "rebuild_status": "built_in_this_phase",
                "definition_or_reason": feature["definition"],
                "support_column": feature["support_column"],
                "missing_flag_column": f"{feature['column_name']}_missing_flag",
                "fallback_level_column": f"{feature['column_name']}_fallback_level",
            }
        )

    return pd.DataFrame(records)


def summarize_feature(
    df: pd.DataFrame,
    feature_name: str,
    support_column: str,
    feature_family: str,
    temporal_window: str,
) -> dict:
    support = pd.to_numeric(df[support_column], errors="coerce").fillna(0)
    missing_flag = df[f"{feature_name}_missing_flag"]
    fallback = df[f"{feature_name}_fallback_level"].fillna("unresolved")

    summary = {
        "feature_name": feature_name,
        "feature_family": feature_family,
        "temporal_window": temporal_window,
        "rows_n": int(len(df)),
        "missing_n": int(missing_flag.sum()),
        "missing_pct": float(100.0 * missing_flag.mean()),
        "support_mean": float(support.mean()),
        "support_p50": float(support.quantile(0.50)),
        "support_p95": float(support.quantile(0.95)),
        "support_max": float(support.max()),
        "value_mean_nonmissing": float(pd.to_numeric(df[feature_name], errors="coerce").dropna().mean())
        if df[feature_name].notna().any()
        else np.nan,
        "value_p50_nonmissing": float(pd.to_numeric(df[feature_name], errors="coerce").dropna().quantile(0.50))
        if df[feature_name].notna().any()
        else np.nan,
        "value_p95_nonmissing": float(pd.to_numeric(df[feature_name], errors="coerce").dropna().quantile(0.95))
        if df[feature_name].notna().any()
        else np.nan,
    }
    for level_name, _ in FALLBACK_LEVELS:
        summary[f"fallback_{level_name}_pct"] = float(100.0 * (fallback == level_name).mean())
    summary["fallback_unresolved_pct"] = float(100.0 * (fallback == "unresolved").mean())

    if summary["missing_pct"] <= 15.0 and summary["support_p50"] >= 1.0:
        summary["usability_status"] = "usable_now"
    elif summary["missing_pct"] <= 35.0:
        summary["usability_status"] = "usable_with_caution"
    else:
        summary["usability_status"] = "limited_for_now"
    return summary


def build_summary(df: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for feature in NEW_CONTEXTUAL_FEATURES:
        rows.append(
            summarize_feature(
                df,
                feature_name=feature["column_name"],
                support_column=feature["support_column"],
                feature_family=feature["feature_family"],
                temporal_window=feature["temporal_window"],
            )
        )
    return pd.DataFrame(rows).sort_values(["feature_family", "temporal_window", "feature_name"]).reset_index(drop=True)


def write_note(paths, diagnostics: dict[str, int], summary: pd.DataFrame) -> None:
    usable_now = summary.loc[summary["usability_status"] == "usable_now", "feature_name"].tolist()
    caution = summary.loc[summary["usability_status"] == "usable_with_caution", "feature_name"].tolist()
    limited = summary.loc[summary["usability_status"] == "limited_for_now", "feature_name"].tolist()

    note = f"""# Contextual Leak-Safe Feature Note

## Scope
This phase adds leak-safe contextual features on top of `training_table_with_lag_safe_features.parquet`.
It does not change:
- target: `accident_count`
- split: train 2016-2022 / validation 2023 / test 2024
- routing logic
- final edge weighting

## Rebuild strategy
Contextual signals were rebuilt from matched accidents plus accident-level context using only information from years strictly earlier than each row `analysis_year`.

Fallback hierarchy:
1. `edge_id + temporal_bin_4h + is_weekend`
2. `edge_id + temporal_bin_4h`
3. `road_class + temporal_bin_4h + is_weekend`
4. `global + temporal_bin_4h + is_weekend`

## M11 / M12 audit
- M12 `intensidad_context`, `ocupacion_context`, `dynamic_context_signal_prelim` and `context_observation_n` are reconstructable as leak-safe lagged features and were rebuilt here.
- M11 `historical_exposure_adjusted_score_prelim` and `exposure_proxy_value` were not rebuilt here because that would require cutoff-specific recomputation of the accident-backed exposure crosswalk/proxy.

## Diagnostics
- matched accidents available: {diagnostics['matched_accidents_total_n']}
- matched accidents with valid panel context: {diagnostics['matched_context_rows_valid_panel_n']}
- matched accidents dropped for invalid panel fields: {diagnostics['matched_context_rows_invalid_panel_n']}
- matched accidents with intensity: {diagnostics['matched_with_intensity_n']}
- matched accidents with occupacion: {diagnostics['matched_with_occupacion_n']}
- matched accidents with joint context: {diagnostics['matched_with_joint_context_n']}

## Usability
- usable now: {", ".join(usable_now) if usable_now else "none"}
- usable with caution: {", ".join(caution) if caution else "none"}
- limited for now: {", ".join(limited) if limited else "none"}

## Interpretation
This new block is leak-safe and technically suitable for an A3/B3 iteration.
However, it is still accident-backed context, not exogenous real-time context. A3/B3 is now methodologically worth testing, but it will not remove the need for future exogenous contextual feeds if ROAD-SAFETY wants a truly operational dynamic layer.
"""
    paths.contextual_lag_safe_feature_note_md.write_text(note, encoding="utf-8")


def main() -> None:
    args = parse_args()
    paths = build_paths()

    outputs_exist = all(
        path.exists()
        for path in [
            paths.training_with_contextual_lag_safe_features_parquet,
            paths.contextual_lag_safe_feature_registry_csv,
            paths.contextual_lag_safe_feature_summary_csv,
            paths.contextual_lag_safe_feature_note_md,
        ]
    )
    if outputs_exist and not args.force:
        print("Contextual lag-safe feature artifacts already exist. Use --force to rebuild.")
        return

    validate_required_inputs(paths)
    base = load_base_table(paths)
    all_years = sorted(pd.Series(base["analysis_year"].dropna().unique()).astype(int).tolist())
    events, diagnostics = load_context_events(paths, base)

    context_base = initialize_context_columns(base)

    yearly_level_stats = {}
    for level_name, key_cols in FALLBACK_LEVELS:
        agg = aggregate_yearly_context(events, key_cols=key_cols)
        yearly_level_stats[level_name] = build_level_prior_stats(agg, key_cols=key_cols, all_years=all_years)

    for level_name, join_cols in FALLBACK_LEVELS:
        context_base = apply_fallback_level(
            context_base,
            level_df=yearly_level_stats[level_name],
            level_name=level_name,
            join_cols=join_cols,
        )

    final_table = finalize_context_features(context_base)

    if len(final_table) != len(base):
        raise ValueError("Row count changed while building contextual lag-safe features.")
    if int(final_table["accident_count"].sum()) != int(base["accident_count"].sum()):
        raise ValueError("Target sum changed while building contextual lag-safe features.")

    registry = build_registry(list(base.columns))
    summary = build_summary(final_table)

    final_table.to_parquet(paths.training_with_contextual_lag_safe_features_parquet, index=False)
    registry.to_csv(paths.contextual_lag_safe_feature_registry_csv, index=False)
    summary.to_csv(paths.contextual_lag_safe_feature_summary_csv, index=False)
    write_note(paths, diagnostics=diagnostics, summary=summary)

    print(f"training_rows_n={len(final_table)}")
    print(f"target_sum={int(final_table['accident_count'].sum())}")
    print(f"context_features_built_n={len(NEW_CONTEXTUAL_FEATURES)}")
    print(f"contextual_summary_rows_n={len(summary)}")


if __name__ == "__main__":
    main()
