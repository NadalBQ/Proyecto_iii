from __future__ import annotations

import argparse
from pathlib import Path
import sys

import numpy as np
import pandas as pd

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from modeling.config import build_paths


TRAIN_YEARS = list(range(2016, 2023))
VALIDATION_YEARS = [2023]
TEST_YEARS = [2024]


NEW_FEATURE_SPECS = [
    {
        "column_name": "edge_accident_count_prior_1y",
        "feature_block": "new_lag_safe_contextual_features",
        "temporal_safety_bucket": "safe_now",
        "source": "lag_from_edge_year_totals",
        "definition": "Accident count on the same edge in the immediately previous analysis year.",
        "leak_safe_reason": "Uses only year y-1 information for the same edge.",
    },
    {
        "column_name": "edge_bin_accident_count_prior_1y",
        "feature_block": "new_lag_safe_contextual_features",
        "temporal_safety_bucket": "safe_now",
        "source": "lag_from_edge_bin_year_totals",
        "definition": "Accident count on the same edge/bin/weekend in the immediately previous analysis year.",
        "leak_safe_reason": "Uses only year y-1 information for the same edge/bin/weekend cell.",
    },
    {
        "column_name": "edge_accident_count_prior_2y",
        "feature_block": "new_lag_safe_contextual_features",
        "temporal_safety_bucket": "safe_now",
        "source": "lag_from_edge_year_totals",
        "definition": "Accident count on the same edge two analysis years before the current observation.",
        "leak_safe_reason": "Uses only year y-2 information.",
    },
    {
        "column_name": "edge_bin_accident_count_prior_2y",
        "feature_block": "new_lag_safe_contextual_features",
        "temporal_safety_bucket": "safe_now",
        "source": "lag_from_edge_bin_year_totals",
        "definition": "Accident count on the same edge/bin/weekend two analysis years before the current observation.",
        "leak_safe_reason": "Uses only year y-2 information.",
    },
    {
        "column_name": "edge_accident_count_prior_recent_3y",
        "feature_block": "new_lag_safe_contextual_features",
        "temporal_safety_bucket": "safe_now",
        "source": "lag_from_edge_year_totals",
        "definition": "Trailing three-year accident count on the same edge, excluding the current year.",
        "leak_safe_reason": "Uses only years y-1, y-2 and y-3.",
    },
    {
        "column_name": "edge_bin_accident_count_prior_recent_3y",
        "feature_block": "new_lag_safe_contextual_features",
        "temporal_safety_bucket": "safe_now",
        "source": "lag_from_edge_bin_year_totals",
        "definition": "Trailing three-year accident count on the same edge/bin/weekend, excluding the current year.",
        "leak_safe_reason": "Uses only years y-1, y-2 and y-3 for the same edge/bin/weekend.",
    },
    {
        "column_name": "recent_activity_flag",
        "feature_block": "new_lag_safe_contextual_features",
        "temporal_safety_bucket": "safe_now",
        "source": "derived_from_edge_accident_count_prior_recent_3y",
        "definition": "Flag equal to 1 when the edge had at least one accident in the previous three years.",
        "leak_safe_reason": "Derived only from prior-year edge history.",
    },
    {
        "column_name": "edge_bin_recent_activity_flag",
        "feature_block": "new_lag_safe_contextual_features",
        "temporal_safety_bucket": "safe_now",
        "source": "derived_from_edge_bin_accident_count_prior_recent_3y",
        "definition": "Flag equal to 1 when the edge/bin/weekend cell had at least one accident in the previous three years.",
        "leak_safe_reason": "Derived only from prior-year edge/bin history.",
    },
    {
        "column_name": "edge_active_years_prior_recent_3y",
        "feature_block": "new_lag_safe_contextual_features",
        "temporal_safety_bucket": "safe_now",
        "source": "lag_from_edge_year_totals",
        "definition": "Number of active accident years in the previous three years on the same edge.",
        "leak_safe_reason": "Counts only prior years with positive accident totals.",
    },
    {
        "column_name": "edge_bin_active_years_prior_recent_3y",
        "feature_block": "new_lag_safe_contextual_features",
        "temporal_safety_bucket": "safe_now",
        "source": "lag_from_edge_bin_year_totals",
        "definition": "Number of active accident years in the previous three years on the same edge/bin/weekend.",
        "leak_safe_reason": "Counts only prior years with positive accident totals in the same edge/bin/weekend.",
    },
    {
        "column_name": "edge_accident_count_prior_change_1y",
        "feature_block": "new_lag_safe_contextual_features",
        "temporal_safety_bucket": "safe_now",
        "source": "derived_from_edge_year_lags",
        "definition": "Difference between prior-1y and prior-2y edge totals.",
        "leak_safe_reason": "Uses only y-1 and y-2 edge history.",
    },
    {
        "column_name": "edge_bin_accident_count_prior_change_1y",
        "feature_block": "new_lag_safe_contextual_features",
        "temporal_safety_bucket": "safe_now",
        "source": "derived_from_edge_bin_year_lags",
        "definition": "Difference between prior-1y and prior-2y edge/bin/weekend totals.",
        "leak_safe_reason": "Uses only y-1 and y-2 edge/bin/weekend history.",
    },
    {
        "column_name": "edge_years_since_last_accident",
        "feature_block": "new_lag_safe_contextual_features",
        "temporal_safety_bucket": "safe_now",
        "source": "lag_from_edge_year_totals",
        "definition": "Years elapsed since the last previous positive accident year on the edge.",
        "leak_safe_reason": "Looks only backward; stays missing when there is no prior positive year.",
    },
    {
        "column_name": "edge_bin_years_since_last_accident",
        "feature_block": "new_lag_safe_contextual_features",
        "temporal_safety_bucket": "safe_now",
        "source": "lag_from_edge_bin_year_totals",
        "definition": "Years elapsed since the last previous positive accident year on the same edge/bin/weekend.",
        "leak_safe_reason": "Looks only backward within the same edge/bin/weekend cell.",
    },
    {
        "column_name": "edge_bin_share_of_edge_prior_recent_3y",
        "feature_block": "new_lag_safe_contextual_features",
        "temporal_safety_bucket": "safe_now",
        "source": "derived_from_edge_and_edge_bin_recent_3y",
        "definition": "Share of the edge recent three-year history concentrated in the same edge/bin/weekend cell.",
        "leak_safe_reason": "Uses only prior three-year lagged counts.",
    },
]


SAFE_NOW_COLUMNS = {
    "edge_length_m": ("original_model_safe", "Static edge descriptor with full coverage."),
    "analysis_year": ("original_model_safe", "Temporal panel index; already safe and used in split."),
    "hour_sin": ("original_model_safe", "Deterministic encoding of the 4h bin center."),
    "hour_cos": ("original_model_safe", "Deterministic encoding of the 4h bin center."),
    "is_weekend": ("original_model_safe", "Calendar descriptor of the observation unit."),
    "edge_accident_count_prior_total": ("original_model_safe", "Lag-safe cumulative edge count already built from prior years."),
    "edge_bin_accident_count_prior": ("original_model_safe", "Lag-safe cumulative edge/bin count already built from prior years."),
    "road_class": ("static_raw_safe_now", "Static categorical road descriptor; safe but not encoded in the first baseline."),
    "temporal_bin_4h": ("static_raw_safe_now", "Observation-unit bin label; safe raw panel descriptor."),
    "temporal_bin_start_hour": ("static_raw_safe_now", "Deterministic raw temporal descriptor."),
    "temporal_bin_end_hour": ("static_raw_safe_now", "Deterministic raw temporal descriptor."),
    "temporal_bin_center_hour": ("static_raw_safe_now", "Deterministic raw temporal descriptor."),
    "hour_sin_full_period_reference": ("safe_now_redundant_copy", "Redundant copy of `hour_sin`; safe but not informative."),
    "hour_cos_full_period_reference": ("safe_now_redundant_copy", "Redundant copy of `hour_cos`; safe but not informative."),
}

LEAKAGE_PRONE_COLUMNS = {
    "context_reference_available": "Derived from full-period contextual support; leakage-prone.",
    "reference_feature_warning": "Administrative warning tied to full-period reference columns; not a predictor.",
}

POTENTIALLY_REBUILDABLE_AS_LAGGED = {
    "edge_years_observed_prior": "Needs redefinition because zero-only controls inherit support windows from sampled templates.",
    "historical_count_raw_full_period_reference": "Could be rebuilt as a rolling prior raw historical count by cutoff year.",
    "historical_count_weighted_full_period_reference": "Could be rebuilt as a rolling prior weighted historical count by cutoff year.",
    "accidents_per_km_raw_full_period_reference": "Could be rebuilt as a rolling prior density by cutoff year.",
    "accidents_per_km_full_period_reference": "Could be rebuilt as a rolling prior weighted density by cutoff year.",
    "historical_score_prelim_full_period_reference": "Could be rebuilt as a rolling prior historical score, not as a full-period column.",
    "historical_exposure_adjusted_score_prelim_full_period_reference": "Could be rebuilt as a rolling prior score only if M11 logic is recomputed by cutoff.",
    "exposure_proxy_value_full_period_reference": "Could be rebuilt as a lagged exposure proxy, but only if sensor/edge evidence is recomputed up to each cutoff.",
    "exposure_quality_flag_full_period_reference": "Could be rebuilt as a lagged exposure-quality flag if the proxy is recomputed by cutoff.",
    "intensidad_context_full_period_reference": "Could be rebuilt as a rolling lagged context proxy, but not used directly now.",
    "ocupacion_context_full_period_reference": "Could be rebuilt as a rolling lagged context proxy, but not used directly now.",
    "dynamic_context_signal_prelim_full_period_reference": "Could be rebuilt as a rolling lagged contextual signal, not from full-period aggregates.",
    "context_observation_n_full_period_reference": "Could be rebuilt as rolling prior support, not from full-period counts.",
    "context_data_quality_flag_full_period_reference": "Could be rebuilt as a rolling prior context-quality flag, not from full-period support.",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build lag-safe contextual features for ROAD-SAFETY modeling.")
    parser.add_argument("--force", action="store_true", help="Rebuild even if outputs already exist.")
    return parser.parse_args()


def validate_required_inputs(paths) -> None:
    required = [paths.training_with_controls_parquet]
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        raise FileNotFoundError(f"Missing required inputs for lag-safe feature phase: {missing}")


def load_training_table(paths) -> pd.DataFrame:
    return pd.read_parquet(paths.training_with_controls_parquet)


def validate_unique_panel(df: pd.DataFrame) -> None:
    duplicate_n = int(df.duplicated(["edge_id", "analysis_year", "temporal_bin_4h", "is_weekend"]).sum())
    if duplicate_n > 0:
        raise ValueError(f"Training table is not unique at panel level; duplicate rows found: {duplicate_n}")


def add_edge_year_lag_features(df: pd.DataFrame) -> pd.DataFrame:
    edge_year = (
        df.groupby(["edge_id", "analysis_year"], as_index=False)
        .agg(edge_year_accident_count=("accident_count", "sum"))
        .sort_values(["edge_id", "analysis_year"])
        .reset_index(drop=True)
    )

    grouped = edge_year.groupby("edge_id")
    edge_year["edge_accident_count_prior_1y"] = grouped["edge_year_accident_count"].shift(1).fillna(0)
    edge_year["edge_accident_count_prior_2y"] = grouped["edge_year_accident_count"].shift(2).fillna(0)
    edge_year["edge_accident_count_prior_3y"] = grouped["edge_year_accident_count"].shift(3).fillna(0)
    edge_year["edge_accident_count_prior_recent_3y"] = (
        edge_year["edge_accident_count_prior_1y"]
        + edge_year["edge_accident_count_prior_2y"]
        + edge_year["edge_accident_count_prior_3y"]
    )
    edge_year["edge_active_years_prior_recent_3y"] = (
        (edge_year["edge_accident_count_prior_1y"] > 0).astype(int)
        + (edge_year["edge_accident_count_prior_2y"] > 0).astype(int)
        + (edge_year["edge_accident_count_prior_3y"] > 0).astype(int)
    )
    edge_year["recent_activity_flag"] = (edge_year["edge_accident_count_prior_recent_3y"] > 0).astype(int)
    edge_year["edge_accident_count_prior_change_1y"] = (
        edge_year["edge_accident_count_prior_1y"] - edge_year["edge_accident_count_prior_2y"]
    )

    positive_year = pd.Series(
        np.where(edge_year["edge_year_accident_count"] > 0, edge_year["analysis_year"], np.nan),
        index=edge_year.index,
    )
    edge_year["edge_prev_positive_year"] = positive_year.groupby(edge_year["edge_id"]).shift(1)
    edge_year["edge_prev_positive_year"] = edge_year.groupby("edge_id")["edge_prev_positive_year"].ffill()
    edge_year["edge_years_since_last_accident"] = edge_year["analysis_year"] - edge_year["edge_prev_positive_year"]

    return df.merge(
        edge_year[
            [
                "edge_id",
                "analysis_year",
                "edge_accident_count_prior_1y",
                "edge_accident_count_prior_2y",
                "edge_accident_count_prior_recent_3y",
                "edge_active_years_prior_recent_3y",
                "recent_activity_flag",
                "edge_accident_count_prior_change_1y",
                "edge_years_since_last_accident",
            ]
        ],
        on=["edge_id", "analysis_year"],
        how="left",
    )


def add_edge_bin_lag_features(df: pd.DataFrame) -> pd.DataFrame:
    result = df.sort_values(["edge_id", "temporal_bin_start_hour", "is_weekend", "analysis_year"]).copy()
    group_cols = ["edge_id", "temporal_bin_4h", "is_weekend"]
    grouped = result.groupby(group_cols)

    result["edge_bin_accident_count_prior_1y"] = grouped["accident_count"].shift(1).fillna(0)
    result["edge_bin_accident_count_prior_2y"] = grouped["accident_count"].shift(2).fillna(0)
    result["edge_bin_accident_count_prior_3y"] = grouped["accident_count"].shift(3).fillna(0)
    result["edge_bin_accident_count_prior_recent_3y"] = (
        result["edge_bin_accident_count_prior_1y"]
        + result["edge_bin_accident_count_prior_2y"]
        + result["edge_bin_accident_count_prior_3y"]
    )
    result["edge_bin_active_years_prior_recent_3y"] = (
        (result["edge_bin_accident_count_prior_1y"] > 0).astype(int)
        + (result["edge_bin_accident_count_prior_2y"] > 0).astype(int)
        + (result["edge_bin_accident_count_prior_3y"] > 0).astype(int)
    )
    result["edge_bin_recent_activity_flag"] = (result["edge_bin_accident_count_prior_recent_3y"] > 0).astype(int)
    result["edge_bin_accident_count_prior_change_1y"] = (
        result["edge_bin_accident_count_prior_1y"] - result["edge_bin_accident_count_prior_2y"]
    )

    positive_year = pd.Series(
        np.where(result["accident_count"] > 0, result["analysis_year"], np.nan),
        index=result.index,
    )
    result["edge_bin_prev_positive_year"] = positive_year.groupby(
        [result["edge_id"], result["temporal_bin_4h"], result["is_weekend"]]
    ).shift(1)
    result["edge_bin_prev_positive_year"] = result.groupby(group_cols)["edge_bin_prev_positive_year"].ffill()
    result["edge_bin_years_since_last_accident"] = result["analysis_year"] - result["edge_bin_prev_positive_year"]

    result["edge_bin_share_of_edge_prior_recent_3y"] = np.where(
        result["edge_accident_count_prior_recent_3y"] > 0,
        result["edge_bin_accident_count_prior_recent_3y"] / result["edge_accident_count_prior_recent_3y"],
        0.0,
    )

    result = result.drop(columns=["edge_bin_prev_positive_year", "edge_bin_accident_count_prior_3y"])
    return result.sort_values(["edge_id", "analysis_year", "temporal_bin_start_hour", "is_weekend"]).reset_index(drop=True)


def build_registry(df: pd.DataFrame) -> pd.DataFrame:
    records = []
    present_columns = set(df.columns)

    for column in sorted(present_columns):
        if column in {spec["column_name"] for spec in NEW_FEATURE_SPECS}:
            continue

        feature_block = "admin_or_target"
        temporal_safety_bucket = "not_applicable"
        source = "training_table_with_controls"
        rationale = "Administrative metadata or target/audit column."
        use_in_next_baseline_candidate = "no"

        if column in SAFE_NOW_COLUMNS:
            feature_block, rationale = SAFE_NOW_COLUMNS[column]
            temporal_safety_bucket = "safe_now"
            use_in_next_baseline_candidate = "yes" if feature_block == "original_model_safe" else "no"
        elif column in LEAKAGE_PRONE_COLUMNS:
            feature_block = "reference_only"
            temporal_safety_bucket = "unsafe_due_to_leakage"
            rationale = LEAKAGE_PRONE_COLUMNS[column]
            use_in_next_baseline_candidate = "no"
        elif column in POTENTIALLY_REBUILDABLE_AS_LAGGED:
            feature_block = "reference_only"
            temporal_safety_bucket = "potentially_rebuildable_as_lagged"
            rationale = POTENTIALLY_REBUILDABLE_AS_LAGGED[column]
            use_in_next_baseline_candidate = "no"
        elif column in {"accident_count", "high_confidence_accident_count", "medium_confidence_accident_count", "low_confidence_accident_count"}:
            feature_block = "target_or_diagnostic"
            temporal_safety_bucket = "not_applicable"
            use_in_next_baseline_candidate = "no"
            source = "observed_target_panel"
            rationale = "Observed target or audit split; not a predictor."
        elif column in {"road_class", "edge_length_bin", "sampling_stratum"}:
            feature_block = "static_raw_safe_now"
            temporal_safety_bucket = "safe_now"
            use_in_next_baseline_candidate = "no"
            rationale = "Static raw descriptor; safe but not encoded in the current numeric baseline."

        records.append(
            {
                "column_name": column,
                "feature_block": feature_block,
                "temporal_safety_bucket": temporal_safety_bucket,
                "source_artifact": source,
                "use_in_next_baseline_candidate": use_in_next_baseline_candidate,
                "rationale": rationale,
                "created_in_this_phase": "no",
            }
        )

    for spec in NEW_FEATURE_SPECS:
        records.append(
            {
                "column_name": spec["column_name"],
                "feature_block": spec["feature_block"],
                "temporal_safety_bucket": spec["temporal_safety_bucket"],
                "source_artifact": spec["source"],
                "use_in_next_baseline_candidate": "yes",
                "rationale": f"{spec['definition']} {spec['leak_safe_reason']}",
                "created_in_this_phase": "yes",
            }
        )

    registry = pd.DataFrame(records).sort_values(
        ["created_in_this_phase", "feature_block", "column_name"], ascending=[False, True, True]
    )
    return registry.reset_index(drop=True)


def build_feature_summary(df: pd.DataFrame) -> pd.DataFrame:
    rows = []
    split_masks = {
        "train": df["analysis_year"].isin(TRAIN_YEARS),
        "validation": df["analysis_year"].isin(VALIDATION_YEARS),
        "test": df["analysis_year"].isin(TEST_YEARS),
    }

    for spec in NEW_FEATURE_SPECS:
        column = spec["column_name"]
        series = pd.to_numeric(df[column], errors="coerce")
        non_missing_mask = series.notna()
        zero_mask = series.eq(0) & non_missing_mask
        rows.append(
            {
                "column_name": column,
                "feature_block": spec["feature_block"],
                "source": spec["source"],
                "missing_n": int(series.isna().sum()),
                "missing_pct": float(100 * series.isna().mean()),
                "non_missing_n": int(non_missing_mask.sum()),
                "non_missing_pct": float(100 * non_missing_mask.mean()),
                "zero_n": int(zero_mask.sum()),
                "zero_pct": float(100 * zero_mask.mean()),
                "nonzero_n": int(((series != 0) & non_missing_mask).sum()),
                "nonzero_pct": float(100 * (((series != 0) & non_missing_mask).mean())),
                "mean": float(series.mean()) if non_missing_mask.any() else np.nan,
                "sd": float(series.std(ddof=0)) if non_missing_mask.any() else np.nan,
                "p50": float(series.quantile(0.50)) if non_missing_mask.any() else np.nan,
                "p95": float(series.quantile(0.95)) if non_missing_mask.any() else np.nan,
                "max": float(series.max()) if non_missing_mask.any() else np.nan,
                "train_non_missing_pct": float(100 * series.loc[split_masks["train"]].notna().mean()),
                "validation_non_missing_pct": float(100 * series.loc[split_masks["validation"]].notna().mean()),
                "test_non_missing_pct": float(100 * series.loc[split_masks["test"]].notna().mean()),
                "train_nonzero_pct": float(100 * ((series.loc[split_masks["train"]] != 0) & series.loc[split_masks["train"]].notna()).mean()),
                "validation_nonzero_pct": float(100 * ((series.loc[split_masks["validation"]] != 0) & series.loc[split_masks["validation"]].notna()).mean()),
                "test_nonzero_pct": float(100 * ((series.loc[split_masks["test"]] != 0) & series.loc[split_masks["test"]].notna()).mean()),
            }
        )

    validation_rows = [
        {
            "column_name": "__table_validation__",
            "feature_block": "table_level",
            "source": "training_table_with_controls",
            "missing_n": np.nan,
            "missing_pct": np.nan,
            "non_missing_n": np.nan,
            "non_missing_pct": np.nan,
            "zero_n": np.nan,
            "zero_pct": np.nan,
            "nonzero_n": np.nan,
            "nonzero_pct": np.nan,
            "mean": np.nan,
            "sd": np.nan,
            "p50": np.nan,
            "p95": np.nan,
            "max": np.nan,
            "train_non_missing_pct": np.nan,
            "validation_non_missing_pct": np.nan,
            "test_non_missing_pct": np.nan,
            "train_nonzero_pct": np.nan,
            "validation_nonzero_pct": np.nan,
            "test_nonzero_pct": np.nan,
            "validation_metric": "row_count_preserved",
            "validation_value": int(len(df)),
        },
        {
            "column_name": "__table_validation__",
            "feature_block": "table_level",
            "source": "training_table_with_controls",
            "missing_n": np.nan,
            "missing_pct": np.nan,
            "non_missing_n": np.nan,
            "non_missing_pct": np.nan,
            "zero_n": np.nan,
            "zero_pct": np.nan,
            "nonzero_n": np.nan,
            "nonzero_pct": np.nan,
            "mean": np.nan,
            "sd": np.nan,
            "p50": np.nan,
            "p95": np.nan,
            "max": np.nan,
            "train_non_missing_pct": np.nan,
            "validation_non_missing_pct": np.nan,
            "test_non_missing_pct": np.nan,
            "train_nonzero_pct": np.nan,
            "validation_nonzero_pct": np.nan,
            "test_nonzero_pct": np.nan,
            "validation_metric": "target_sum_preserved",
            "validation_value": int(df["accident_count"].sum()),
        },
    ]

    summary = pd.DataFrame(rows)
    if validation_rows:
        summary = pd.concat([summary, pd.DataFrame(validation_rows)], ignore_index=True, sort=False)
    return summary


def build_note(registry: pd.DataFrame, summary: pd.DataFrame) -> str:
    new_features = registry.loc[registry["created_in_this_phase"] == "yes", "column_name"].tolist()
    rebuildable = registry.loc[
        registry["temporal_safety_bucket"] == "potentially_rebuildable_as_lagged", "column_name"
    ].tolist()
    unsafe = registry.loc[
        registry["temporal_safety_bucket"] == "unsafe_due_to_leakage", "column_name"
    ].tolist()

    summary_core = summary.loc[~summary["column_name"].eq("__table_validation__")].copy()
    top_missing = summary_core.sort_values("missing_pct", ascending=False).head(5)

    lines = [
        "# Lag-safe feature note",
        "",
        "## Scope",
        "- Target unchanged: `accident_count`.",
        "- Split unchanged: train `2016-2022`, validation `2023`, test `2024`.",
        "- Base table unchanged: `training_table_with_controls.parquet` is the source; this phase only adds new lag-safe features in a derived artifact.",
        "",
        "## What was added",
        "- New lag-safe contextual/history features built only from information prior to each observation:",
    ]
    for feature in new_features:
        lines.append(f"  - `{feature}`")

    lines.extend(
        [
            "",
            "## Why M11/M12 full-period columns stay out",
            "- Full-period M10/M11/M12 reference columns remain out of direct modeling because they summarize information across years and would leak future information into earlier observations.",
            "- They are preserved only as `reference_only` or `potentially_rebuildable_as_lagged` audit columns.",
            "",
            "## Potentially rebuildable later",
        ]
    )
    for feature in rebuildable:
        lines.append(f"  - `{feature}`")

    lines.extend(
        [
            "",
            "## Unsafe due to leakage now",
        ]
    )
    for feature in unsafe:
        lines.append(f"  - `{feature}`")

    lines.extend(
        [
            "",
            "## Highest missingness among new features",
        ]
    )
    for row in top_missing.itertuples(index=False):
        lines.append(f"  - `{row.column_name}`: missing `{row.missing_pct:.2f}%`, non-missing `{row.non_missing_pct:.2f}%`.")

    lines.extend(
        [
            "",
            "## Methodological guardrails",
            "- These new features are still history-derived, not exogenous real-time context feeds.",
            "- No full-period accident-backed contextual aggregate enters as a predictor in this phase.",
            "- This phase does not train a new model and does not change routing logic.",
        ]
    )
    return "\n".join(lines) + "\n"


def main() -> None:
    args = parse_args()
    paths = build_paths()
    validate_required_inputs(paths)

    if paths.training_with_lag_safe_features_parquet.exists() and not args.force:
        print(f"Lag-safe training table already exists: {paths.training_with_lag_safe_features_parquet}")
        print("Use --force to rebuild.")
        return

    df = load_training_table(paths)
    validate_unique_panel(df)
    original_row_count = len(df)
    original_target_sum = int(df["accident_count"].sum())

    df = add_edge_year_lag_features(df)
    df = add_edge_bin_lag_features(df)

    registry = build_registry(df)
    summary = build_feature_summary(df)
    note = build_note(registry, summary)

    if len(df) != original_row_count:
        raise ValueError("Row count changed while building lag-safe features.")
    if int(df["accident_count"].sum()) != original_target_sum:
        raise ValueError("Target sum changed while building lag-safe features.")

    df.to_parquet(paths.training_with_lag_safe_features_parquet, index=False)
    registry.to_csv(paths.lag_safe_feature_registry_csv, index=False)
    summary.to_csv(paths.lag_safe_feature_summary_csv, index=False)
    paths.lag_safe_feature_note_md.write_text(note, encoding="utf-8")

    print(f"Lag-safe feature table written to: {paths.training_with_lag_safe_features_parquet}")
    print(f"Rows preserved: {len(df)}")
    print(f"Target sum preserved: {int(df['accident_count'].sum())}")
    print(f"New features added: {len(NEW_FEATURE_SPECS)}")


if __name__ == "__main__":
    main()
