from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
from pathlib import Path
import sys

import numpy as np
import pandas as pd

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from pipeline.builders.config import TEMPORAL_BIN_HOURS, TEMPORAL_BIN_LABELS, build_paths


QUALITY_FLAG_LEVELS = ("high_confidence", "medium_confidence", "low_confidence")


@dataclass(frozen=True)
class TrainingTableDiagnostics:
    training_rows_n: int
    zero_rows_n: int
    zero_rows_pct: float
    positive_rows_n: int
    positive_rows_pct: float
    unique_edges_n: int
    unique_years_n: int
    unique_bins_n: int
    edge_year_span_rows_n: int
    m9_match_rows_n: int
    m9_missing_in_master_n: int
    missing_edge_length_n: int
    missing_hist_adjusted_reference_n: int
    missing_dynamic_reference_n: int
    target_mean: float
    target_variance: float
    target_overdispersion_ratio: float


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build ROAD-SAFETY initial training table.")
    parser.add_argument(
        "--force",
        action="store_true",
        help="Rebuild the training table even if the output already exists.",
    )
    return parser.parse_args()


def validate_inputs(paths) -> None:
    required_paths = [
        paths.m8_edges_csv,
        paths.m9_matches_csv,
        paths.accident_master_csv,
        paths.m10_historical_csv,
        paths.m11_historical_adjusted_csv,
        paths.m12_dynamic_base_csv,
    ]
    missing = [str(path) for path in required_paths if not path.exists()]
    if missing:
        raise FileNotFoundError(f"Missing required inputs for modeling phase: {missing}")


def load_inputs(paths) -> dict[str, pd.DataFrame]:
    return {
        "edges": pd.read_csv(paths.m8_edges_csv, usecols=["edge_id", "road_class", "edge_length_m"]),
        "matches": pd.read_csv(
            paths.m9_matches_csv,
            usecols=["num_expediente", "edge_id", "fecha", "hora", "quality_flag", "match_status"],
        ),
        "master": pd.read_csv(paths.accident_master_csv, usecols=["num_expediente"]),
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


def prepare_matches(matches: pd.DataFrame) -> pd.DataFrame:
    matches = matches.loc[matches["match_status"] == "matched"].copy()
    matches["fecha"] = pd.to_datetime(matches["fecha"], errors="coerce")
    matches["analysis_year"] = matches["fecha"].dt.year.astype("Int64")
    matches["hour_of_day"] = pd.to_numeric(matches["hora"].str.slice(0, 2), errors="coerce").astype("Int64")
    matches["temporal_bin_start_hour"] = ((matches["hour_of_day"] // TEMPORAL_BIN_HOURS) * TEMPORAL_BIN_HOURS).astype("Int64")
    matches["temporal_bin_4h"] = matches["temporal_bin_start_hour"].map(
        {
            0: "00_03",
            4: "04_07",
            8: "08_11",
            12: "12_15",
            16: "16_19",
            20: "20_23",
        }
    )
    matches["is_weekend"] = matches["fecha"].dt.dayofweek >= 5
    return matches


def build_edge_year_panel(matches: pd.DataFrame) -> pd.DataFrame:
    edge_span = (
        matches.groupby("edge_id", as_index=False)
        .agg(
            edge_first_year=("analysis_year", "min"),
            edge_last_year=("analysis_year", "max"),
        )
        .astype({"edge_first_year": int, "edge_last_year": int})
    )

    edge_year_rows = []
    for row in edge_span.itertuples(index=False):
        for year in range(int(row.edge_first_year), int(row.edge_last_year) + 1):
            edge_year_rows.append(
                {
                    "edge_id": row.edge_id,
                    "analysis_year": year,
                    "edge_first_year": int(row.edge_first_year),
                    "edge_last_year": int(row.edge_last_year),
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
    panel["edge_years_observed_prior"] = panel["analysis_year"] - panel["edge_first_year"]
    return panel


def aggregate_target(matches: pd.DataFrame) -> pd.DataFrame:
    grouped = (
        matches.groupby(["edge_id", "analysis_year", "temporal_bin_4h", "is_weekend"], as_index=False)
        .agg(
            accident_count=("num_expediente", "size"),
            high_confidence_accident_count=("quality_flag", lambda s: int((s == "high_confidence").sum())),
            medium_confidence_accident_count=("quality_flag", lambda s: int((s == "medium_confidence").sum())),
            low_confidence_accident_count=("quality_flag", lambda s: int((s == "low_confidence").sum())),
        )
    )
    return grouped


def add_lag_features(panel_with_target: pd.DataFrame) -> pd.DataFrame:
    df = panel_with_target.sort_values(["edge_id", "analysis_year", "temporal_bin_start_hour", "is_weekend"]).copy()

    edge_year_totals = (
        df.groupby(["edge_id", "analysis_year"], as_index=False)["accident_count"]
        .sum()
        .sort_values(["edge_id", "analysis_year"])
    )
    edge_year_totals["edge_accident_count_prior_total"] = (
        edge_year_totals.groupby("edge_id")["accident_count"].cumsum() - edge_year_totals["accident_count"]
    )

    df = df.merge(
        edge_year_totals[["edge_id", "analysis_year", "edge_accident_count_prior_total"]],
        on=["edge_id", "analysis_year"],
        how="left",
    )

    df["edge_bin_accident_count_prior"] = (
        df.groupby(["edge_id", "temporal_bin_4h", "is_weekend"])["accident_count"].cumsum() - df["accident_count"]
    )
    return df


def build_training_table(inputs: dict[str, pd.DataFrame]) -> tuple[pd.DataFrame, TrainingTableDiagnostics]:
    matches = prepare_matches(inputs["matches"])

    master_ids = set(inputs["master"]["num_expediente"].astype(str))
    match_ids = matches["num_expediente"].astype(str)
    missing_in_master_n = int((~match_ids.isin(master_ids)).sum())

    panel = build_edge_year_panel(matches)
    target = aggregate_target(matches)

    training = panel.merge(
        target,
        on=["edge_id", "analysis_year", "temporal_bin_4h", "is_weekend"],
        how="left",
    )

    count_columns = [
        "accident_count",
        "high_confidence_accident_count",
        "medium_confidence_accident_count",
        "low_confidence_accident_count",
    ]
    for column in count_columns:
        training[column] = training[column].fillna(0).astype(int)

    training = add_lag_features(training)

    training = training.merge(inputs["edges"], on="edge_id", how="left")
    training = training.merge(
        inputs["m10"].rename(
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
    training = training.merge(
        inputs["m11"].rename(
            columns={
                "historical_exposure_adjusted_score_prelim": "historical_exposure_adjusted_score_prelim_full_period_reference",
                "exposure_proxy_value": "exposure_proxy_value_full_period_reference",
                "exposure_quality_flag": "exposure_quality_flag_full_period_reference",
            }
        ),
        on="edge_id",
        how="left",
    )
    training = training.merge(
        inputs["m12"].rename(
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

    training["context_reference_available"] = training["dynamic_context_signal_prelim_full_period_reference"].notna()
    training["reference_feature_warning"] = np.where(
        training["context_reference_available"],
        "full_period_context_reference_is_not_safe_for_temporal_cv",
        "no_full_period_context_reference",
    )
    training["target_definition"] = "accident_count"
    training["panel_definition"] = "edge_id + analysis_year + temporal_bin_4h + is_weekend"
    training["zero_generation_rule"] = "edge_specific_year_span_crossed_with_all_4h_bins_and_weekend_levels"

    training = training.sort_values(["edge_id", "analysis_year", "temporal_bin_start_hour", "is_weekend"]).reset_index(drop=True)

    zero_rows_n = int((training["accident_count"] == 0).sum())
    positive_rows_n = int((training["accident_count"] > 0).sum())
    target_mean = float(training["accident_count"].mean())
    target_variance = float(training["accident_count"].var(ddof=0))
    diagnostics = TrainingTableDiagnostics(
        training_rows_n=int(len(training)),
        zero_rows_n=zero_rows_n,
        zero_rows_pct=100 * zero_rows_n / len(training),
        positive_rows_n=positive_rows_n,
        positive_rows_pct=100 * positive_rows_n / len(training),
        unique_edges_n=int(training["edge_id"].nunique()),
        unique_years_n=int(training["analysis_year"].nunique()),
        unique_bins_n=int(training["temporal_bin_4h"].nunique() * training["is_weekend"].nunique()),
        edge_year_span_rows_n=int(len(panel)),
        m9_match_rows_n=int(len(matches)),
        m9_missing_in_master_n=missing_in_master_n,
        missing_edge_length_n=int(training["edge_length_m"].isna().sum()),
        missing_hist_adjusted_reference_n=int(training["historical_exposure_adjusted_score_prelim_full_period_reference"].isna().sum()),
        missing_dynamic_reference_n=int(training["dynamic_context_signal_prelim_full_period_reference"].isna().sum()),
        target_mean=target_mean,
        target_variance=target_variance,
        target_overdispersion_ratio=(target_variance / target_mean) if target_mean > 0 else np.nan,
    )
    return training, diagnostics


def build_feature_registry() -> pd.DataFrame:
    records = [
        ("accident_count", "target", "target", "m9_matches", "Real observed target aggregated from matched accidents at panel level."),
        ("high_confidence_accident_count", "target_diagnostic", "diagnostic_only", "m9_matches", "Quality split for target auditability, not primary target."),
        ("medium_confidence_accident_count", "target_diagnostic", "diagnostic_only", "m9_matches", "Quality split for target auditability, not primary target."),
        ("low_confidence_accident_count", "target_diagnostic", "diagnostic_only", "m9_matches", "Quality split for target auditability, not primary target."),
        ("edge_length_m", "historical_base", "model_safe", "m8_edges", "Static edge descriptor with full coverage."),
        ("analysis_year", "temporal_panel", "model_safe", "m9_matches_panel", "Temporal panel index for defendable split."),
        ("hour_sin", "temporal_context", "model_safe", "panel_grid", "Exogenous cyclical encoding of the 4h bin center."),
        ("hour_cos", "temporal_context", "model_safe", "panel_grid", "Exogenous cyclical encoding of the 4h bin center."),
        ("is_weekend", "temporal_context", "model_safe", "panel_grid", "Calendar indicator defined by observation unit."),
        ("edge_accident_count_prior_total", "historical_base", "model_safe", "lag_from_target", "Lag-safe cumulative accident count on the edge before the current analysis year."),
        ("edge_bin_accident_count_prior", "historical_base", "model_safe", "lag_from_target", "Lag-safe cumulative accident count on the same edge/bin/weekend before the current analysis year."),
        ("edge_years_observed_prior", "historical_base", "model_safe", "panel_grid", "Years since the first observed matched accident on the edge."),
        ("historical_score_prelim_full_period_reference", "historical_reference", "reference_only", "m10", "Full-period R artifact kept as comparator; leakage-prone for temporal CV."),
        ("historical_exposure_adjusted_score_prelim_full_period_reference", "historical_reference", "reference_only", "m11", "Full-period R artifact kept as comparator; leakage-prone for temporal CV."),
        ("exposure_proxy_value_full_period_reference", "historical_reference", "reference_only", "m11", "Exposure proxy from M11 retained as baseline reference, not default model-safe predictor."),
        ("intensidad_context_full_period_reference", "dynamic_reference", "reference_only", "m12", "Accident-backed full-period contextual summary; not safe as a direct temporal predictor."),
        ("ocupacion_context_full_period_reference", "dynamic_reference", "reference_only", "m12", "Accident-backed full-period contextual summary; not safe as a direct temporal predictor."),
        ("dynamic_context_signal_prelim_full_period_reference", "dynamic_reference", "reference_only", "m12", "Full-period contextual comparator from M12; not target and not default model-safe feature."),
        ("vmed", "excluded", "excluded_for_now", "not_loaded", "Excluded due to noise already documented in earlier phases."),
        ("es_festivo", "excluded", "excluded_for_now", "not_loaded", "Excluded for now from baseline modeling because the current panel does not support it cleanly as a stable predictor."),
        ("estado_meteorologico", "excluded", "excluded_for_now", "not_loaded", "Excluded until meteorology is integrated operationally and independently."),
    ]
    return pd.DataFrame(records, columns=["column_name", "feature_group", "status", "source_artifact", "rationale"])


def diagnostics_to_frame(diag: TrainingTableDiagnostics) -> pd.DataFrame:
    mapping = asdict(diag)
    return pd.DataFrame({"metric": list(mapping.keys()), "value": list(mapping.values())})


def main() -> None:
    args = parse_args()
    paths = build_paths()
    validate_inputs(paths)

    if paths.training_table_parquet.exists() and not args.force:
        print(f"Training table already exists: {paths.training_table_parquet}")
        print("Use --force to rebuild.")
        return

    inputs = load_inputs(paths)
    training_table, diagnostics = build_training_table(inputs)
    feature_registry = build_feature_registry()

    training_table.to_parquet(paths.training_table_parquet, index=False)
    diagnostics_to_frame(diagnostics).to_csv(paths.training_summary_csv, index=False)
    feature_registry.to_csv(paths.feature_registry_csv, index=False)

    print(f"Training table written to: {paths.training_table_parquet}")
    print(f"Training rows: {diagnostics.training_rows_n}")
    print(f"Zero rows: {diagnostics.zero_rows_n} ({diagnostics.zero_rows_pct:.2f}%)")
    print(f"Positive rows: {diagnostics.positive_rows_n} ({diagnostics.positive_rows_pct:.2f}%)")
    print(f"Target mean: {diagnostics.target_mean:.4f}")
    print(f"Target variance: {diagnostics.target_variance:.4f}")
    print(f"Overdispersion ratio: {diagnostics.target_overdispersion_ratio:.4f}")


if __name__ == "__main__":
    main()
