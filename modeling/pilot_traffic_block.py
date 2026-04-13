from __future__ import annotations

from dataclasses import dataclass

import pandas as pd


GLOBAL_DEFAULT_PIPELINE_NAME = "global_default_model"
PILOT_TRAFFIC_PIPELINE_NAME = "pilot_traffic_model"
PILOT_TRAFFIC_FEATURE_BLOCK_NAME = "pilot_traffic_d_transformed"

PILOT_TRAFFIC_ALLOWED_YEAR = 2024
PILOT_TRAFFIC_ALLOWED_MONTHS = (1, 4, 7, 10)
PILOT_TRAFFIC_SPLIT_BY_MONTH = {1: "train", 4: "train", 7: "validation", 10: "test"}

PILOT_TRAFFIC_KEY_COLUMNS = ["edge_id", "analysis_year", "month", "temporal_bin_4h", "is_weekend"]
PILOT_TRAFFIC_TARGET_COLUMN = "pilot_accident_count"

PILOT_TRAFFIC_BASE_FEATURE_COLUMNS = [
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
]
PILOT_TRAFFIC_CATEGORICAL_BASE_FEATURE_COLUMNS = ["road_class_group"]

PILOT_TRAFFIC_BLOCK_COLUMNS = [
    "traffic_covered_flag",
    "traffic_missing_due_to_no_time_flag",
    "traffic_intensidad_wins_log",
    "traffic_ocupacion_wins",
    "log1p_traffic_support_n",
    "log1p_traffic_n_observations",
]

PILOT_TRAFFIC_EXCLUDED_COLUMNS = ["traffic_vmed_mean"]

PILOT_TRAFFIC_REQUIRED_RAW_COLUMNS = [
    *PILOT_TRAFFIC_KEY_COLUMNS,
    PILOT_TRAFFIC_TARGET_COLUMN,
    "traffic_coverage_flag",
    "traffic_missing_reason",
    "traffic_intensidad_mean",
    "traffic_ocupacion_mean",
    "traffic_n_observations",
    "traffic_support_n",
    "edge_length_m",
    "road_class",
    "oneway_raw",
    "maxspeed_raw",
    "bridge_raw",
    "tunnel_raw",
    "hour_sin",
    "hour_cos",
]

PILOT_TRAFFIC_REQUIRED_INPUT_COLUMNS = [
    *PILOT_TRAFFIC_KEY_COLUMNS,
    "split",
    PILOT_TRAFFIC_TARGET_COLUMN,
    "target",
    "pilot_row_type",
    "traffic_coverage_flag",
    "traffic_missing_reason",
    *PILOT_TRAFFIC_BASE_FEATURE_COLUMNS,
    *PILOT_TRAFFIC_BLOCK_COLUMNS,
]


@dataclass(frozen=True)
class ValidationRow:
    gating_stage: str
    rule_name: str
    severity: str
    passed: bool
    evidence: str
    on_fail_behavior: str

    def as_dict(self) -> dict[str, object]:
        return {
            "gating_stage": self.gating_stage,
            "rule_name": self.rule_name,
            "severity": self.severity,
            "passed": self.passed,
            "evidence": self.evidence,
            "on_fail_behavior": self.on_fail_behavior,
        }


def assign_pilot_split(month_series: pd.Series) -> pd.Series:
    split = month_series.map(PILOT_TRAFFIC_SPLIT_BY_MONTH)
    return split.astype("string")


def _missing_columns(df: pd.DataFrame, required_columns: list[str]) -> list[str]:
    return [column for column in required_columns if column not in df.columns]


def _year_values(df: pd.DataFrame) -> str:
    values = sorted(pd.Series(df["analysis_year"]).dropna().unique().tolist()) if "analysis_year" in df.columns else []
    return "|".join(str(int(value)) for value in values) if values else "missing"


def _month_values(df: pd.DataFrame) -> str:
    values = sorted(pd.Series(df["month"]).dropna().unique().tolist()) if "month" in df.columns else []
    return "|".join(str(int(value)) for value in values) if values else "missing"


def validate_pilot_raw_training_table(df: pd.DataFrame) -> pd.DataFrame:
    missing_required = _missing_columns(df, PILOT_TRAFFIC_REQUIRED_RAW_COLUMNS)
    has_key_columns = all(column in df.columns for column in PILOT_TRAFFIC_KEY_COLUMNS)
    has_year = "analysis_year" in df.columns
    has_month = "month" in df.columns
    rows = [
        ValidationRow(
            gating_stage="raw_training_table",
            rule_name="required_columns_present",
            severity="error",
            passed=not missing_required,
            evidence=(
                "missing_columns=" + "|".join(missing_required)
                if missing_required
                else "all_required_columns_present"
            ),
            on_fail_behavior="abort_pilot_traffic_block_activation",
        ),
        ValidationRow(
            gating_stage="raw_training_table",
            rule_name="pilot_year_scope_only",
            severity="error",
            passed=has_year and set(pd.Series(df["analysis_year"]).dropna().astype(int).unique().tolist()) == {PILOT_TRAFFIC_ALLOWED_YEAR},
            evidence=f"analysis_year_values={_year_values(df)}",
            on_fail_behavior="abort_pilot_traffic_block_activation",
        ),
        ValidationRow(
            gating_stage="raw_training_table",
            rule_name="pilot_month_scope_only",
            severity="error",
            passed=has_month and set(pd.Series(df["month"]).dropna().astype(int).unique().tolist()) == set(PILOT_TRAFFIC_ALLOWED_MONTHS),
            evidence=f"month_values={_month_values(df)}",
            on_fail_behavior="abort_pilot_traffic_block_activation",
        ),
        ValidationRow(
            gating_stage="raw_training_table",
            rule_name="pilot_key_unique",
            severity="error",
            passed=has_key_columns and not df.duplicated(subset=PILOT_TRAFFIC_KEY_COLUMNS).any(),
            evidence=(
                f"duplicate_surplus={int(df.duplicated(subset=PILOT_TRAFFIC_KEY_COLUMNS).sum())}"
                if has_key_columns
                else "duplicate_surplus=not_evaluated_missing_key_columns"
            ),
            on_fail_behavior="abort_pilot_traffic_block_activation",
        ),
    ]
    return pd.DataFrame([row.as_dict() for row in rows])


def validate_pilot_transformed_input(df: pd.DataFrame) -> pd.DataFrame:
    missing_required = _missing_columns(df, PILOT_TRAFFIC_REQUIRED_INPUT_COLUMNS)
    has_key_columns = all(column in df.columns for column in PILOT_TRAFFIC_KEY_COLUMNS)
    has_year = "analysis_year" in df.columns
    has_month = "month" in df.columns
    has_split = "split" in df.columns and has_month
    split_series = df["split"] if "split" in df.columns else pd.Series(dtype="string")
    if has_split:
        observed_split_map = (
            df.loc[:, ["month", "split"]]
            .dropna()
            .drop_duplicates()
            .sort_values(["month", "split"])
            .astype({"month": int, "split": str})
        )
        observed_split_pairs = "|".join(f"{row.month}:{row.split}" for row in observed_split_map.itertuples(index=False))
    else:
        observed_split_pairs = ""
    expected_split_pairs = "|".join(f"{month}:{split}" for month, split in sorted(PILOT_TRAFFIC_SPLIT_BY_MONTH.items()))
    rows = [
        ValidationRow(
            gating_stage="transformed_model_input",
            rule_name="required_columns_present",
            severity="error",
            passed=not missing_required,
            evidence=(
                "missing_columns=" + "|".join(missing_required)
                if missing_required
                else "all_required_columns_present"
            ),
            on_fail_behavior="abort_pilot_traffic_block_activation",
        ),
        ValidationRow(
            gating_stage="transformed_model_input",
            rule_name="pilot_year_scope_only",
            severity="error",
            passed=has_year and set(pd.Series(df["analysis_year"]).dropna().astype(int).unique().tolist()) == {PILOT_TRAFFIC_ALLOWED_YEAR},
            evidence=f"analysis_year_values={_year_values(df)}",
            on_fail_behavior="abort_pilot_traffic_block_activation",
        ),
        ValidationRow(
            gating_stage="transformed_model_input",
            rule_name="pilot_month_scope_only",
            severity="error",
            passed=has_month and set(pd.Series(df["month"]).dropna().astype(int).unique().tolist()) == set(PILOT_TRAFFIC_ALLOWED_MONTHS),
            evidence=f"month_values={_month_values(df)}",
            on_fail_behavior="abort_pilot_traffic_block_activation",
        ),
        ValidationRow(
            gating_stage="transformed_model_input",
            rule_name="pilot_key_unique",
            severity="error",
            passed=has_key_columns and not df.duplicated(subset=PILOT_TRAFFIC_KEY_COLUMNS).any(),
            evidence=(
                f"duplicate_surplus={int(df.duplicated(subset=PILOT_TRAFFIC_KEY_COLUMNS).sum())}"
                if has_key_columns
                else "duplicate_surplus=not_evaluated_missing_key_columns"
            ),
            on_fail_behavior="abort_pilot_traffic_block_activation",
        ),
        ValidationRow(
            gating_stage="transformed_model_input",
            rule_name="pilot_split_exact",
            severity="error",
            passed=has_split and observed_split_pairs == expected_split_pairs and not split_series.isna().any(),
            evidence=f"observed={observed_split_pairs or 'missing'};expected={expected_split_pairs}",
            on_fail_behavior="abort_pilot_traffic_block_activation",
        ),
    ]
    return pd.DataFrame([row.as_dict() for row in rows])


def assert_validated(validation_df: pd.DataFrame, stage_name: str) -> None:
    failed = validation_df.loc[~validation_df["passed"]].copy()
    if failed.empty:
        return
    details = "; ".join(
        f"{row.rule_name} -> {row.evidence}" for row in failed.itertuples(index=False)
    )
    raise ValueError(f"{stage_name} failed pilot traffic gating: {details}")


def build_pipeline_summary() -> pd.DataFrame:
    return pd.DataFrame(
        [
            {
                "pipeline_name": GLOBAL_DEFAULT_PIPELINE_NAME,
                "default_active": True,
                "traffic_block_name": "",
                "traffic_block_active": False,
                "representative_scope": "global_2016_2024_modeling_branch",
                "target_column": "accident_count",
                "modeling_unit": "edge_id + analysis_year + temporal_bin_4h + is_weekend",
                "time_restriction": "global_2016_2024_split",
                "representative_input_artifact": "outputs/modeling/training_table_with_exogenous_context_features.parquet",
                "entrypoint_build_script": "modeling/build_exogenous_context_features.py",
                "entrypoint_train_script": "modeling/train_exogenous_baselines.py",
                "activation_mode": "default",
                "gating_failure_behavior": "not_applicable",
                "notes": "Pilot traffic block is not part of the default global pipeline.",
            },
            {
                "pipeline_name": PILOT_TRAFFIC_PIPELINE_NAME,
                "default_active": False,
                "traffic_block_name": PILOT_TRAFFIC_FEATURE_BLOCK_NAME,
                "traffic_block_active": True,
                "representative_scope": "pilot_2024_months_1_4_7_10_only",
                "target_column": PILOT_TRAFFIC_TARGET_COLUMN,
                "modeling_unit": "edge_id + analysis_year + month + temporal_bin_4h + is_weekend",
                "time_restriction": "analysis_year=2024 and month in (1,4,7,10)",
                "representative_input_artifact": "outputs/modeling/pilot_traffic_d_transformed_input.parquet",
                "entrypoint_build_script": "modeling/build_pilot_traffic_input.py",
                "entrypoint_train_script": "modeling/train_pilot_traffic_baselines.py",
                "activation_mode": "explicit_opt_in_only",
                "gating_failure_behavior": "abort_with_clear_message",
                "notes": "Pilot traffic branch remains isolated and must not be treated as global coverage.",
            },
        ]
    )


def build_gating_rules(validation_raw: pd.DataFrame, validation_input: pd.DataFrame) -> pd.DataFrame:
    static_rules = pd.DataFrame(
        [
            {
                "gating_stage": "pipeline_selection",
                "rule_name": "global_default_does_not_auto_enable_pilot_traffic",
                "severity": "error",
                "passed": True,
                "evidence": "global_default_model keeps traffic block disabled unless pilot pipeline is requested explicitly",
                "on_fail_behavior": "architecture_regression",
            },
            {
                "gating_stage": "pipeline_selection",
                "rule_name": "pilot_traffic_requires_explicit_opt_in",
                "severity": "error",
                "passed": True,
                "evidence": "pilot_traffic_model is a separate branch and not the default",
                "on_fail_behavior": "architecture_regression",
            },
            {
                "gating_stage": "pipeline_selection",
                "rule_name": "pilot_traffic_gating_failure_aborts_instead_of_fallback",
                "severity": "error",
                "passed": True,
                "evidence": "explicit pilot requests must fail loudly if pilot-only preconditions are not met",
                "on_fail_behavior": "abort_pilot_traffic_block_activation",
            },
        ]
    )
    return pd.concat([static_rules, validation_raw, validation_input], ignore_index=True)
