from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import sys

import numpy as np
import pandas as pd

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from pipeline.builders.build_training_table import (
    TEMPORAL_BIN_HOURS,
    TEMPORAL_BIN_LABELS,
    build_training_table,
    load_inputs,
    validate_inputs,
)
from pipeline.builders.config import build_paths


RANDOM_SEED = 20260411
LENGTH_BIN_EDGES = [0, 50, 100, 200, 500, np.inf]
LENGTH_BIN_LABELS = ["lt50", "50_100", "100_200", "200_500", "ge500"]
CONTROL_SUPPORT_RULE = "sampled_positive_edge_year_span_within_same_road_class_length_bin_stratum"
CONTROL_SAMPLING_RULE = "stratified_1_to_1_cap_by_road_class_and_edge_length_bin"


@dataclass(frozen=True)
class ControlsSummary:
    current_rows_n: int
    current_positive_rows_n: int
    current_zero_rows_n: int
    current_unique_edges_n: int
    current_positive_history_edges_n: int
    current_zero_only_control_edges_n: int
    current_positive_history_edges_pct: float
    current_zero_only_control_edges_pct: float
    controls_rows_n: int
    controls_zero_rows_n: int
    controls_unique_edges_n: int
    controls_sampled_edges_pct_of_never_accident_pool: float
    with_controls_rows_n: int
    with_controls_positive_rows_n: int
    with_controls_zero_rows_n: int
    with_controls_unique_edges_n: int
    with_controls_positive_history_edges_n: int
    with_controls_zero_only_control_edges_n: int
    with_controls_positive_history_edges_pct: float
    with_controls_zero_only_control_edges_pct: float
    network_edges_n: int
    never_accident_edges_n: int
    sampled_zero_only_edges_n: int
    sampled_strata_n: int
    strata_with_deficit_n: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build training table with zero-only control edges.")
    parser.add_argument("--force", action="store_true", help="Rebuild even if the output already exists.")
    return parser.parse_args()


def load_or_build_current_training(paths) -> pd.DataFrame:
    if paths.training_table_parquet.exists():
        return pd.read_parquet(paths.training_table_parquet)

    validate_inputs(paths)
    inputs = load_inputs(paths)
    current_training, _ = build_training_table(inputs)
    current_training.to_parquet(paths.training_table_parquet, index=False)
    return current_training


def load_reference_frames(paths) -> dict[str, pd.DataFrame]:
    return {
        "edges": pd.read_csv(paths.m8_edges_csv, usecols=["edge_id", "road_class", "edge_length_m"]),
        "m10": pd.read_csv(
            paths.m10_historical_csv,
            usecols=[
                "edge_id",
                "accident_count_raw",
                "accident_count_weighted_by_quality",
                "accidents_per_km_raw",
                "accidents_per_km",
                "historical_score_prelim",
            ],
        ),
        "m11": pd.read_csv(
            paths.m11_historical_adjusted_csv,
            usecols=[
                "edge_id",
                "historical_exposure_adjusted_score_prelim",
                "exposure_proxy_value",
                "exposure_quality_flag",
            ],
        ),
        "m12": pd.read_csv(
            paths.m12_dynamic_base_csv,
            usecols=[
                "edge_id",
                "temporal_bin_4h",
                "is_weekend",
                "intensidad_context",
                "ocupacion_context",
                "hour_sin",
                "hour_cos",
                "dynamic_context_signal_prelim",
                "context_data_quality_flag",
                "context_observation_n",
            ],
        ),
    }


def assign_sampling_strata(edges: pd.DataFrame) -> pd.DataFrame:
    result = edges.copy()
    result["road_class"] = result["road_class"].fillna("unknown").astype(str)
    result["edge_length_m"] = pd.to_numeric(result["edge_length_m"], errors="coerce")

    length_bin = pd.cut(
        result["edge_length_m"],
        bins=LENGTH_BIN_EDGES,
        labels=LENGTH_BIN_LABELS,
        right=False,
        include_lowest=True,
    )
    result["edge_length_bin"] = length_bin.astype(object)
    result.loc[result["edge_length_bin"].isna(), "edge_length_bin"] = "unknown_len"
    result["sampling_stratum"] = result["road_class"] + "|" + result["edge_length_bin"].astype(str)
    return result


def add_current_audit_columns(current: pd.DataFrame, edges_meta: pd.DataFrame) -> pd.DataFrame:
    result = current.copy()
    if "road_class" not in result.columns:
        result = result.merge(edges_meta[["edge_id", "road_class"]], on="edge_id", how="left")
    if "edge_length_m" not in result.columns:
        result = result.merge(edges_meta[["edge_id", "edge_length_m"]], on="edge_id", how="left")

    support = (
        result[["edge_id", "analysis_year"]]
        .drop_duplicates()
        .groupby("edge_id", as_index=False)
        .agg(
            panel_support_first_year=("analysis_year", "min"),
            panel_support_last_year=("analysis_year", "max"),
        )
    )
    result = result.merge(support, on="edge_id", how="left")
    result = result.merge(edges_meta[["edge_id", "edge_length_bin", "sampling_stratum"]], on="edge_id", how="left")
    result["is_zero_only_control"] = False
    result["control_template_source_edge_id"] = pd.NA
    result["control_support_rule"] = pd.NA
    result["control_sampling_rule"] = pd.NA
    return result


def build_zero_control_edges(current: pd.DataFrame, edges_meta: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    positive_edge_ids = set(current["edge_id"].unique())

    support = (
        current[["edge_id", "analysis_year"]]
        .drop_duplicates()
        .groupby("edge_id", as_index=False)
        .agg(
            panel_support_first_year=("analysis_year", "min"),
            panel_support_last_year=("analysis_year", "max"),
            support_years_n=("analysis_year", "nunique"),
        )
    )

    positive_edges = (
        edges_meta.loc[edges_meta["edge_id"].isin(positive_edge_ids)]
        .merge(support, on="edge_id", how="inner")
        .reset_index(drop=True)
    )
    zero_pool = edges_meta.loc[~edges_meta["edge_id"].isin(positive_edge_ids)].reset_index(drop=True)

    rng = np.random.default_rng(RANDOM_SEED)
    sampled_controls = []
    stratum_records = []

    positive_counts = positive_edges.groupby("sampling_stratum").size().rename("positive_history_edges_n")
    zero_counts = zero_pool.groupby("sampling_stratum").size().rename("never_accident_edges_n")
    all_strata = positive_counts.index.union(zero_counts.index)

    for sampling_stratum in all_strata:
        positive_n = int(positive_counts.get(sampling_stratum, 0))
        zero_n = int(zero_counts.get(sampling_stratum, 0))
        sample_n = min(positive_n, zero_n)
        deficit_n = max(positive_n - zero_n, 0)
        stratum_records.append(
            {
                "sampling_stratum": sampling_stratum,
                "positive_history_edges_n": positive_n,
                "never_accident_edges_n": zero_n,
                "sampled_zero_only_edges_n": sample_n,
                "stratum_deficit_n": deficit_n,
            }
        )
        if sample_n == 0:
            continue

        stratum_zero_pool = zero_pool.loc[zero_pool["sampling_stratum"] == sampling_stratum].copy()
        chosen_zero_idx = rng.choice(stratum_zero_pool.index.to_numpy(), size=sample_n, replace=False)
        chosen_zero_edges = stratum_zero_pool.loc[chosen_zero_idx].reset_index(drop=True)

        stratum_templates = positive_edges.loc[
            positive_edges["sampling_stratum"] == sampling_stratum,
            ["edge_id", "panel_support_first_year", "panel_support_last_year", "support_years_n"],
        ].reset_index(drop=True)
        template_idx = rng.integers(0, len(stratum_templates), size=sample_n)
        template_sample = stratum_templates.iloc[template_idx].reset_index(drop=True)

        chosen_zero_edges["control_template_source_edge_id"] = template_sample["edge_id"]
        chosen_zero_edges["panel_support_first_year"] = template_sample["panel_support_first_year"].astype(int)
        chosen_zero_edges["panel_support_last_year"] = template_sample["panel_support_last_year"].astype(int)
        chosen_zero_edges["support_years_n"] = template_sample["support_years_n"].astype(int)
        chosen_zero_edges["is_zero_only_control"] = True
        chosen_zero_edges["control_support_rule"] = CONTROL_SUPPORT_RULE
        chosen_zero_edges["control_sampling_rule"] = CONTROL_SAMPLING_RULE
        sampled_controls.append(chosen_zero_edges)

    zero_controls = pd.concat(sampled_controls, ignore_index=True) if sampled_controls else pd.DataFrame()
    strata_summary = pd.DataFrame(stratum_records)
    return zero_controls, strata_summary


def build_zero_control_panel(zero_controls: pd.DataFrame) -> pd.DataFrame:
    if zero_controls.empty:
        return pd.DataFrame()

    edge_year_rows = []
    for row in zero_controls.itertuples(index=False):
        for year in range(int(row.panel_support_first_year), int(row.panel_support_last_year) + 1):
            edge_year_rows.append(
                {
                    "edge_id": row.edge_id,
                    "analysis_year": year,
                    "panel_support_first_year": int(row.panel_support_first_year),
                    "panel_support_last_year": int(row.panel_support_last_year),
                    "edge_first_year": pd.NA,
                    "edge_last_year": pd.NA,
                    "road_class": row.road_class,
                    "edge_length_m": row.edge_length_m,
                    "edge_length_bin": row.edge_length_bin,
                    "sampling_stratum": row.sampling_stratum,
                    "is_zero_only_control": True,
                    "control_template_source_edge_id": row.control_template_source_edge_id,
                    "control_support_rule": row.control_support_rule,
                    "control_sampling_rule": row.control_sampling_rule,
                }
            )

    edge_year = pd.DataFrame(edge_year_rows)
    time_grid = pd.DataFrame(
        [
            {
                "temporal_bin_4h": label,
                "temporal_bin_start_hour": start_hour,
                "temporal_bin_end_hour": start_hour + (TEMPORAL_BIN_HOURS - 1),
                "temporal_bin_center_hour": start_hour + ((TEMPORAL_BIN_HOURS - 1) / 2),
                "is_weekend": is_weekend,
            }
            for start_hour, label in zip(range(0, 24, TEMPORAL_BIN_HOURS), TEMPORAL_BIN_LABELS)
            for is_weekend in (False, True)
        ]
    )

    edge_year["__join_key"] = 1
    time_grid["__join_key"] = 1
    panel = edge_year.merge(time_grid, on="__join_key", how="inner").drop(columns="__join_key")
    panel["hour_sin"] = np.sin(2 * np.pi * panel["temporal_bin_center_hour"] / 24)
    panel["hour_cos"] = np.cos(2 * np.pi * panel["temporal_bin_center_hour"] / 24)
    panel["edge_years_observed_prior"] = pd.NA
    panel["edge_accident_count_prior_total"] = 0
    panel["edge_bin_accident_count_prior"] = 0
    panel["accident_count"] = 0
    panel["high_confidence_accident_count"] = 0
    panel["medium_confidence_accident_count"] = 0
    panel["low_confidence_accident_count"] = 0
    return panel


def attach_reference_columns(control_panel: pd.DataFrame, reference_frames: dict[str, pd.DataFrame]) -> pd.DataFrame:
    if control_panel.empty:
        return control_panel

    result = control_panel.merge(
        reference_frames["m10"].rename(
            columns={
                "accident_count_raw": "historical_count_raw_full_period_reference",
                "accident_count_weighted_by_quality": "historical_count_weighted_full_period_reference",
                "accidents_per_km_raw": "accidents_per_km_raw_full_period_reference",
                "accidents_per_km": "accidents_per_km_full_period_reference",
                "historical_score_prelim": "historical_score_prelim_full_period_reference",
            }
        ),
        on="edge_id",
        how="left",
    )
    result = result.merge(
        reference_frames["m11"].rename(
            columns={
                "historical_exposure_adjusted_score_prelim": "historical_exposure_adjusted_score_prelim_full_period_reference",
                "exposure_proxy_value": "exposure_proxy_value_full_period_reference",
                "exposure_quality_flag": "exposure_quality_flag_full_period_reference",
            }
        ),
        on="edge_id",
        how="left",
    )
    result = result.merge(
        reference_frames["m12"].rename(
            columns={
                "intensidad_context": "intensidad_context_full_period_reference",
                "ocupacion_context": "ocupacion_context_full_period_reference",
                "hour_sin": "hour_sin_full_period_reference",
                "hour_cos": "hour_cos_full_period_reference",
                "dynamic_context_signal_prelim": "dynamic_context_signal_prelim_full_period_reference",
                "context_data_quality_flag": "context_data_quality_flag_full_period_reference",
                "context_observation_n": "context_observation_n_full_period_reference",
            }
        ),
        on=["edge_id", "temporal_bin_4h", "is_weekend"],
        how="left",
    )
    result["context_reference_available"] = result["dynamic_context_signal_prelim_full_period_reference"].notna()
    result["reference_feature_warning"] = np.where(
        result["context_reference_available"],
        "full_period_context_reference_is_not_safe_for_temporal_cv",
        "no_full_period_context_reference",
    )
    result["target_definition"] = "accident_count"
    result["panel_definition"] = "edge_id + analysis_year + temporal_bin_4h + is_weekend"
    result["zero_generation_rule"] = (
        "positive_edges_use_edge_specific_year_span; zero_only_controls_use_stratified_sampled_support_template"
    )
    return result


def harmonise_columns(current: pd.DataFrame, controls: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    current_cols = set(current.columns)
    control_cols = set(controls.columns)
    all_cols = sorted(current_cols | control_cols)

    current_h = current.copy()
    control_h = controls.copy()

    for column in all_cols:
        if column not in current_h.columns:
            current_h[column] = pd.NA
        if column not in control_h.columns:
            control_h[column] = pd.NA

    return current_h[all_cols], control_h[all_cols]


def build_summary(current: pd.DataFrame, with_controls: pd.DataFrame, zero_controls: pd.DataFrame, edges_meta: pd.DataFrame, strata_summary: pd.DataFrame) -> pd.DataFrame:
    network_edges_n = int(edges_meta["edge_id"].nunique())
    current_positive_history_edges_n = int((~current["is_zero_only_control"]).sum() > 0 and current.loc[~current["is_zero_only_control"], "edge_id"].nunique())
    current_zero_only_control_edges_n = int(current.loc[current["is_zero_only_control"], "edge_id"].nunique())
    with_controls_positive_history_edges_n = int(with_controls.loc[~with_controls["is_zero_only_control"], "edge_id"].nunique())
    with_controls_zero_only_control_edges_n = int(with_controls.loc[with_controls["is_zero_only_control"], "edge_id"].nunique())
    never_accident_edges_n = network_edges_n - current_positive_history_edges_n

    summary = ControlsSummary(
        current_rows_n=int(len(current)),
        current_positive_rows_n=int((current["accident_count"] > 0).sum()),
        current_zero_rows_n=int((current["accident_count"] == 0).sum()),
        current_unique_edges_n=int(current["edge_id"].nunique()),
        current_positive_history_edges_n=current_positive_history_edges_n,
        current_zero_only_control_edges_n=current_zero_only_control_edges_n,
        current_positive_history_edges_pct=100 * current_positive_history_edges_n / network_edges_n,
        current_zero_only_control_edges_pct=100 * current_zero_only_control_edges_n / network_edges_n,
        controls_rows_n=int(len(zero_controls)),
        controls_zero_rows_n=int((zero_controls["accident_count"] == 0).sum()),
        controls_unique_edges_n=int(zero_controls["edge_id"].nunique()),
        controls_sampled_edges_pct_of_never_accident_pool=(
            100 * zero_controls["edge_id"].nunique() / never_accident_edges_n if never_accident_edges_n > 0 else 0.0
        ),
        with_controls_rows_n=int(len(with_controls)),
        with_controls_positive_rows_n=int((with_controls["accident_count"] > 0).sum()),
        with_controls_zero_rows_n=int((with_controls["accident_count"] == 0).sum()),
        with_controls_unique_edges_n=int(with_controls["edge_id"].nunique()),
        with_controls_positive_history_edges_n=with_controls_positive_history_edges_n,
        with_controls_zero_only_control_edges_n=with_controls_zero_only_control_edges_n,
        with_controls_positive_history_edges_pct=100 * with_controls_positive_history_edges_n / network_edges_n,
        with_controls_zero_only_control_edges_pct=100 * with_controls_zero_only_control_edges_n / network_edges_n,
        network_edges_n=network_edges_n,
        never_accident_edges_n=never_accident_edges_n,
        sampled_zero_only_edges_n=int(zero_controls["edge_id"].nunique()),
        sampled_strata_n=int((strata_summary["sampled_zero_only_edges_n"] > 0).sum()),
        strata_with_deficit_n=int((strata_summary["stratum_deficit_n"] > 0).sum()),
    )

    rows = []
    for metric, value in summary.__dict__.items():
        rows.append({"dataset_name": "training_table_comparison", "metric": metric, "value": value})

    stratum_rows = strata_summary.copy()
    stratum_rows["dataset_name"] = "zero_control_sampling_stratum"
    return pd.concat([pd.DataFrame(rows), stratum_rows], ignore_index=True, sort=False)


def main() -> None:
    args = parse_args()
    paths = build_paths()

    if paths.training_with_controls_parquet.exists() and not args.force:
        print(f"Training table with controls already exists: {paths.training_with_controls_parquet}")
        print("Use --force to rebuild.")
        return

    current = load_or_build_current_training(paths)
    reference_frames = load_reference_frames(paths)
    edges_meta = assign_sampling_strata(reference_frames["edges"])

    current = add_current_audit_columns(current, edges_meta)
    zero_control_edges, strata_summary = build_zero_control_edges(current, edges_meta)
    zero_control_panel = build_zero_control_panel(zero_control_edges)
    zero_control_panel = attach_reference_columns(zero_control_panel, reference_frames)

    current_h, controls_h = harmonise_columns(current, zero_control_panel)
    with_controls = pd.concat([current_h, controls_h], ignore_index=True)
    with_controls = with_controls.sort_values(
        ["edge_id", "analysis_year", "temporal_bin_start_hour", "is_weekend", "is_zero_only_control"]
    ).reset_index(drop=True)

    summary_frame = build_summary(current_h, with_controls, controls_h, edges_meta, strata_summary)

    with_controls.to_parquet(paths.training_with_controls_parquet, index=False)
    summary_frame.to_csv(paths.training_with_controls_summary_csv, index=False)

    print(f"Training table with controls written to: {paths.training_with_controls_parquet}")
    print(f"Rows: {len(with_controls)}")
    print(f"Zero-only control edges: {controls_h['edge_id'].nunique()}")
    print(f"Zero rows: {(with_controls['accident_count'] == 0).sum()}")
    print(f"Positive rows: {(with_controls['accident_count'] > 0).sum()}")


if __name__ == "__main__":
    main()
