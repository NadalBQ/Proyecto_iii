from __future__ import annotations

import argparse
from pathlib import Path
import sys

import numpy as np
import pandas as pd

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from modeling.config import build_paths
from modeling.pilot_traffic_block import (
    PILOT_TRAFFIC_ALLOWED_MONTHS,
    PILOT_TRAFFIC_ALLOWED_YEAR,
    PILOT_TRAFFIC_KEY_COLUMNS,
    assert_validated,
    assign_pilot_split,
    validate_pilot_raw_training_table,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build the pilot 2024 traffic D-transformed modeling input.")
    parser.add_argument("--force", action="store_true", help="Rebuild artifacts even if they already exist.")
    return parser.parse_args()


def parse_bool_flag(series: pd.Series) -> pd.Series:
    values = series.fillna("").astype(str).str.strip().str.lower()
    return values.isin({"t", "true", "1", "y", "yes"}).astype(int)


def parse_maxspeed(series: pd.Series) -> pd.Series:
    extracted = series.astype("string").str.extract(r"([0-9]+(?:\.[0-9]+)?)", expand=False)
    numeric = pd.to_numeric(extracted, errors="coerce")
    numeric[numeric <= 0] = np.nan
    return numeric.astype(float)


def road_class_group(series: pd.Series) -> pd.Series:
    values = series.fillna("").astype(str).str.strip().str.lower()
    major = {"motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link"}
    collector = {"secondary", "secondary_link", "tertiary", "tertiary_link", "unclassified"}
    local = {"residential", "living_street", "service"}

    grouped = np.select(
        [
            values.isin(major),
            values.isin(collector),
            values.isin(local),
            values.eq(""),
        ],
        [
            "major",
            "collector",
            "local",
            "missing",
        ],
        default="other",
    )
    return pd.Categorical(grouped, categories=["major", "collector", "local", "other", "missing"])


def median_unbiased_quantile(series: pd.Series, q: float) -> float:
    clean = series.dropna().to_numpy(dtype=float)
    if clean.size == 0:
        return float("nan")
    return float(np.quantile(clean, q, method="median_unbiased"))


def build_contract_rows(params: dict[str, float]) -> list[dict[str, object]]:
    return [
        {
            "feature_name": "pilot_accident_count",
            "role": "target",
            "source_columns": "pilot_accident_count",
            "transformation": "none",
            "imputation_rule": "none",
            "training_scope_for_params": "not_applicable",
            "include_in_no_traffic_baseline": True,
            "include_in_with_traffic_baseline": True,
            "leak_safe": True,
            "pilot_scope_only": True,
            "exclusion_reason": "",
            "parameter_details": "",
        },
        {
            "feature_name": "log_edge_length_m",
            "role": "base",
            "source_columns": "edge_length_m",
            "transformation": "log1p(max(edge_length_m,0))",
            "imputation_rule": "none",
            "training_scope_for_params": "not_applicable",
            "include_in_no_traffic_baseline": True,
            "include_in_with_traffic_baseline": True,
            "leak_safe": True,
            "pilot_scope_only": True,
            "exclusion_reason": "",
            "parameter_details": "",
        },
        {
            "feature_name": "road_class_group",
            "role": "base",
            "source_columns": "road_class",
            "transformation": "grouped_categorical_major_collector_local_other_missing",
            "imputation_rule": "missing_to_missing_bucket",
            "training_scope_for_params": "not_applicable",
            "include_in_no_traffic_baseline": True,
            "include_in_with_traffic_baseline": True,
            "leak_safe": True,
            "pilot_scope_only": True,
            "exclusion_reason": "",
            "parameter_details": "",
        },
        {
            "feature_name": "oneway_flag",
            "role": "base",
            "source_columns": "oneway_raw",
            "transformation": "boolean_parse_to_int",
            "imputation_rule": "non_true_to_0",
            "training_scope_for_params": "not_applicable",
            "include_in_no_traffic_baseline": True,
            "include_in_with_traffic_baseline": True,
            "leak_safe": True,
            "pilot_scope_only": True,
            "exclusion_reason": "",
            "parameter_details": "",
        },
        {
            "feature_name": "maxspeed_kph_imputed",
            "role": "base",
            "source_columns": "maxspeed_raw",
            "transformation": "regex_numeric_parse_then_train_road_class_median_imputation",
            "imputation_rule": "train_road_class_median_else_train_global_median",
            "training_scope_for_params": "train_months_1_4_all_rows",
            "include_in_no_traffic_baseline": True,
            "include_in_with_traffic_baseline": True,
            "leak_safe": True,
            "pilot_scope_only": True,
            "exclusion_reason": "",
            "parameter_details": f"global_median={params['global_maxspeed_median']:.6f}",
        },
        {
            "feature_name": "maxspeed_missing_flag",
            "role": "base",
            "source_columns": "maxspeed_raw",
            "transformation": "is_na_after_numeric_parse_to_int",
            "imputation_rule": "none",
            "training_scope_for_params": "not_applicable",
            "include_in_no_traffic_baseline": True,
            "include_in_with_traffic_baseline": True,
            "leak_safe": True,
            "pilot_scope_only": True,
            "exclusion_reason": "",
            "parameter_details": "",
        },
        {
            "feature_name": "bridge_flag",
            "role": "base",
            "source_columns": "bridge_raw",
            "transformation": "boolean_parse_to_int",
            "imputation_rule": "non_true_to_0",
            "training_scope_for_params": "not_applicable",
            "include_in_no_traffic_baseline": True,
            "include_in_with_traffic_baseline": True,
            "leak_safe": True,
            "pilot_scope_only": True,
            "exclusion_reason": "",
            "parameter_details": "",
        },
        {
            "feature_name": "tunnel_flag",
            "role": "base",
            "source_columns": "tunnel_raw",
            "transformation": "boolean_parse_to_int",
            "imputation_rule": "non_true_to_0",
            "training_scope_for_params": "not_applicable",
            "include_in_no_traffic_baseline": True,
            "include_in_with_traffic_baseline": True,
            "leak_safe": True,
            "pilot_scope_only": True,
            "exclusion_reason": "",
            "parameter_details": "",
        },
        {
            "feature_name": "hour_sin",
            "role": "base",
            "source_columns": "hour_sin",
            "transformation": "precomputed_from_temporal_bin_center",
            "imputation_rule": "none",
            "training_scope_for_params": "not_applicable",
            "include_in_no_traffic_baseline": True,
            "include_in_with_traffic_baseline": True,
            "leak_safe": True,
            "pilot_scope_only": True,
            "exclusion_reason": "",
            "parameter_details": "",
        },
        {
            "feature_name": "hour_cos",
            "role": "base",
            "source_columns": "hour_cos",
            "transformation": "precomputed_from_temporal_bin_center",
            "imputation_rule": "none",
            "training_scope_for_params": "not_applicable",
            "include_in_no_traffic_baseline": True,
            "include_in_with_traffic_baseline": True,
            "leak_safe": True,
            "pilot_scope_only": True,
            "exclusion_reason": "",
            "parameter_details": "",
        },
        {
            "feature_name": "month_sin",
            "role": "base",
            "source_columns": "month",
            "transformation": "sin(2*pi*month/12)",
            "imputation_rule": "none",
            "training_scope_for_params": "not_applicable",
            "include_in_no_traffic_baseline": True,
            "include_in_with_traffic_baseline": True,
            "leak_safe": True,
            "pilot_scope_only": True,
            "exclusion_reason": "",
            "parameter_details": "",
        },
        {
            "feature_name": "is_weekend_int",
            "role": "base",
            "source_columns": "is_weekend",
            "transformation": "cast_bool_to_int",
            "imputation_rule": "none",
            "training_scope_for_params": "not_applicable",
            "include_in_no_traffic_baseline": True,
            "include_in_with_traffic_baseline": True,
            "leak_safe": True,
            "pilot_scope_only": True,
            "exclusion_reason": "",
            "parameter_details": "",
        },
        {
            "feature_name": "traffic_covered_flag",
            "role": "traffic",
            "source_columns": "traffic_coverage_flag",
            "transformation": "covered_to_1_else_0",
            "imputation_rule": "none",
            "training_scope_for_params": "not_applicable",
            "include_in_no_traffic_baseline": False,
            "include_in_with_traffic_baseline": True,
            "leak_safe": True,
            "pilot_scope_only": True,
            "exclusion_reason": "",
            "parameter_details": "",
        },
        {
            "feature_name": "traffic_missing_due_to_no_time_flag",
            "role": "traffic",
            "source_columns": "traffic_missing_reason",
            "transformation": "pilot_sensor_support_but_no_traffic_for_time_to_1_else_0",
            "imputation_rule": "none",
            "training_scope_for_params": "not_applicable",
            "include_in_no_traffic_baseline": False,
            "include_in_with_traffic_baseline": True,
            "leak_safe": True,
            "pilot_scope_only": True,
            "exclusion_reason": "",
            "parameter_details": "",
        },
        {
            "feature_name": "traffic_intensidad_wins_log",
            "role": "traffic",
            "source_columns": "traffic_intensidad_mean",
            "transformation": "train_covered_median_impute_then_winsorize_q01_q99_then_log1p",
            "imputation_rule": "train_covered_median",
            "training_scope_for_params": "train_months_1_4_covered_rows",
            "include_in_no_traffic_baseline": False,
            "include_in_with_traffic_baseline": True,
            "leak_safe": True,
            "pilot_scope_only": True,
            "exclusion_reason": "",
            "parameter_details": (
                f"median={params['median_intensidad']:.6f};"
                f"q01={params['int_q01']:.6f};q99={params['int_q99']:.6f}"
            ),
        },
        {
            "feature_name": "traffic_ocupacion_wins",
            "role": "traffic",
            "source_columns": "traffic_ocupacion_mean",
            "transformation": "train_covered_median_impute_then_winsorize_q01_q99",
            "imputation_rule": "train_covered_median",
            "training_scope_for_params": "train_months_1_4_covered_rows",
            "include_in_no_traffic_baseline": False,
            "include_in_with_traffic_baseline": True,
            "leak_safe": True,
            "pilot_scope_only": True,
            "exclusion_reason": "",
            "parameter_details": (
                f"median={params['median_ocupacion']:.6f};"
                f"q01={params['occ_q01']:.6f};q99={params['occ_q99']:.6f}"
            ),
        },
        {
            "feature_name": "log1p_traffic_support_n",
            "role": "traffic_support",
            "source_columns": "traffic_support_n",
            "transformation": "train_covered_median_impute_then_log1p",
            "imputation_rule": "train_covered_median",
            "training_scope_for_params": "train_months_1_4_covered_rows",
            "include_in_no_traffic_baseline": False,
            "include_in_with_traffic_baseline": True,
            "leak_safe": True,
            "pilot_scope_only": True,
            "exclusion_reason": "",
            "parameter_details": f"median={params['median_support_n']:.6f}",
        },
        {
            "feature_name": "log1p_traffic_n_observations",
            "role": "traffic_support",
            "source_columns": "traffic_n_observations",
            "transformation": "train_covered_median_impute_then_log1p",
            "imputation_rule": "train_covered_median",
            "training_scope_for_params": "train_months_1_4_covered_rows",
            "include_in_no_traffic_baseline": False,
            "include_in_with_traffic_baseline": True,
            "leak_safe": True,
            "pilot_scope_only": True,
            "exclusion_reason": "",
            "parameter_details": f"median={params['median_n_obs']:.6f}",
        },
        {
            "feature_name": "traffic_vmed_mean",
            "role": "excluded",
            "source_columns": "traffic_vmed_mean",
            "transformation": "excluded_from_main_python_pilot_spec",
            "imputation_rule": "not_applicable",
            "training_scope_for_params": "not_applicable",
            "include_in_no_traffic_baseline": False,
            "include_in_with_traffic_baseline": False,
            "leak_safe": True,
            "pilot_scope_only": True,
            "exclusion_reason": "excluded_from_main_spec_because_r_refinement_showed_only_marginal_gain_vs_support_block",
            "parameter_details": "",
        },
    ]


def main() -> None:
    args = parse_args()
    paths = build_paths()

    if (
        paths.pilot_traffic_feature_contract_csv.exists()
        and paths.pilot_traffic_d_input_parquet.exists()
        and not args.force
    ):
        print("Pilot traffic input artifacts already exist. Use --force to rebuild.")
        return

    if not paths.pilot_traffic_training_table_csv.exists():
        raise FileNotFoundError(f"Missing pilot traffic training table: {paths.pilot_traffic_training_table_csv}")

    df = pd.read_csv(paths.pilot_traffic_training_table_csv)

    df = df.loc[
        (df["analysis_year"] == PILOT_TRAFFIC_ALLOWED_YEAR) & (df["month"].isin(PILOT_TRAFFIC_ALLOWED_MONTHS))
    ].copy()
    if df.empty:
        raise ValueError("Pilot traffic training table is empty after restricting to 2024 months 1,4,7,10.")

    validation_df = validate_pilot_raw_training_table(df)
    assert_validated(validation_df, "Pilot traffic raw training table")

    df["split"] = assign_pilot_split(df["month"])
    if df["split"].isna().any():
        raise ValueError("Failed to assign split to all pilot rows.")

    df["target"] = df["pilot_accident_count"].astype(int)
    df["is_weekend_int"] = df["is_weekend"].astype(int)
    df["log_edge_length_m"] = np.log1p(np.clip(df["edge_length_m"].fillna(0.0), a_min=0.0, a_max=None))
    df["road_class_group"] = road_class_group(df["road_class"])
    df["oneway_flag"] = parse_bool_flag(df["oneway_raw"])
    df["bridge_flag"] = parse_bool_flag(df["bridge_raw"])
    df["tunnel_flag"] = parse_bool_flag(df["tunnel_raw"])
    df["maxspeed_kph_raw"] = parse_maxspeed(df["maxspeed_raw"])
    df["maxspeed_missing_flag"] = df["maxspeed_kph_raw"].isna().astype(int)
    df["month_sin"] = np.sin(2 * np.pi * df["month"] / 12.0)

    train_df = df.loc[df["split"] == "train"].copy()
    covered_train = train_df.loc[train_df["traffic_coverage_flag"] == "covered"].copy()
    if covered_train.empty:
        raise ValueError("Covered train subset is empty; cannot build pilot traffic transforms.")

    road_class_medians = (
        train_df.loc[train_df["maxspeed_kph_raw"].notna()]
        .groupby("road_class_group", observed=False)["maxspeed_kph_raw"]
        .median()
    )
    global_maxspeed_median = float(train_df["maxspeed_kph_raw"].median(skipna=True))
    if np.isnan(global_maxspeed_median):
        global_maxspeed_median = 50.0
    df["road_class_median_maxspeed"] = df["road_class_group"].map(road_class_medians)
    df["maxspeed_kph_imputed"] = df["maxspeed_kph_raw"]
    df.loc[df["maxspeed_kph_imputed"].isna(), "maxspeed_kph_imputed"] = df.loc[
        df["maxspeed_kph_imputed"].isna(), "road_class_median_maxspeed"
    ]
    df["maxspeed_kph_imputed"] = df["maxspeed_kph_imputed"].fillna(global_maxspeed_median)

    df["traffic_covered_flag"] = (df["traffic_coverage_flag"] == "covered").astype(int)
    df["traffic_missing_due_to_no_time_flag"] = (
        df["traffic_missing_reason"] == "pilot_sensor_support_but_no_traffic_for_time"
    ).astype(int)

    median_intensidad = float(covered_train["traffic_intensidad_mean"].median(skipna=True))
    median_ocupacion = float(covered_train["traffic_ocupacion_mean"].median(skipna=True))
    median_n_obs = float(covered_train["traffic_n_observations"].median(skipna=True))
    median_support_n = float(covered_train["traffic_support_n"].median(skipna=True))

    df["traffic_intensidad_imputed"] = df["traffic_intensidad_mean"].fillna(median_intensidad)
    df["traffic_ocupacion_imputed"] = df["traffic_ocupacion_mean"].fillna(median_ocupacion)
    df["traffic_n_observations_imputed"] = df["traffic_n_observations"].fillna(median_n_obs)
    df["traffic_support_n_imputed"] = df["traffic_support_n"].fillna(median_support_n)

    int_q01 = median_unbiased_quantile(covered_train["traffic_intensidad_mean"], 0.01)
    int_q99 = median_unbiased_quantile(covered_train["traffic_intensidad_mean"], 0.99)
    occ_q01 = median_unbiased_quantile(covered_train["traffic_ocupacion_mean"], 0.01)
    occ_q99 = median_unbiased_quantile(covered_train["traffic_ocupacion_mean"], 0.99)

    df["traffic_intensidad_wins"] = df["traffic_intensidad_imputed"].clip(lower=int_q01, upper=int_q99)
    df["traffic_ocupacion_wins"] = df["traffic_ocupacion_imputed"].clip(lower=occ_q01, upper=occ_q99)
    df["traffic_intensidad_wins_log"] = np.log1p(np.clip(df["traffic_intensidad_wins"], a_min=0.0, a_max=None))
    df["log1p_traffic_n_observations"] = np.log1p(np.clip(df["traffic_n_observations_imputed"], a_min=0.0, a_max=None))
    df["log1p_traffic_support_n"] = np.log1p(np.clip(df["traffic_support_n_imputed"], a_min=0.0, a_max=None))

    output_columns = [
        *PILOT_TRAFFIC_KEY_COLUMNS,
        "split",
        "pilot_accident_count",
        "pilot_row_type",
        "traffic_coverage_flag",
        "traffic_missing_reason",
        "target",
        "log_edge_length_m",
        "road_class_group",
        "oneway_flag",
        "maxspeed_kph_imputed",
        "maxspeed_missing_flag",
        "bridge_flag",
        "tunnel_flag",
        "hour_sin",
        "hour_cos",
        "month_sin",
        "is_weekend_int",
        "traffic_covered_flag",
        "traffic_missing_due_to_no_time_flag",
        "traffic_intensidad_wins_log",
        "traffic_ocupacion_wins",
        "log1p_traffic_support_n",
        "log1p_traffic_n_observations",
        "traffic_intensidad_mean",
        "traffic_ocupacion_mean",
        "traffic_vmed_mean",
        "traffic_n_observations",
        "traffic_support_n",
    ]
    output_df = df.loc[:, output_columns].copy()
    output_df["road_class_group"] = output_df["road_class_group"].cat.remove_unused_categories()
    output_df.to_parquet(paths.pilot_traffic_d_input_parquet, index=False)

    params = {
        "global_maxspeed_median": global_maxspeed_median,
        "median_intensidad": median_intensidad,
        "median_ocupacion": median_ocupacion,
        "median_n_obs": median_n_obs,
        "median_support_n": median_support_n,
        "int_q01": int_q01,
        "int_q99": int_q99,
        "occ_q01": occ_q01,
        "occ_q99": occ_q99,
    }
    contract_df = pd.DataFrame(build_contract_rows(params))
    contract_df.to_csv(paths.pilot_traffic_feature_contract_csv, index=False)

    print(f"Created pilot traffic feature contract: {paths.pilot_traffic_feature_contract_csv}")
    print(f"Created pilot traffic D-transformed input: {paths.pilot_traffic_d_input_parquet}")


if __name__ == "__main__":
    main()
