from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import pandas as pd


GLOBAL_DEFAULT_BRANCH_NAME = "global_default_model"
PILOT_BRANCH_NAME = "pilot_traffic_model"
GLOBAL_SCORING_UNIT_COLUMNS = ["edge_id", "analysis_year", "temporal_bin_4h", "is_weekend"]
GLOBAL_SCORING_TARGET_COLUMN = "accident_count"
GLOBAL_SCORING_MODEL_FAMILY = "negative_binomial"
GLOBAL_SCORING_MODEL_NAME = "negative_binomial_b4"
GLOBAL_SCORING_FEATURE_BLOCK = "a4_b4_exogenous_global"
GLOBAL_SCORING_TRANSFORM_RULE = "linear_cap_at_global_p99_then_scale_0_100"
GLOBAL_SCORING_TRANSFORM_CAP_QUANTILE = 0.99
GLOBAL_SCORING_STATUS_OK = "scored"
GLOBAL_SCORING_NOTE_CODE = "prelim_score_not_routing_weight"
GLOBAL_SCORING_ARTIFACT_SOURCE = "outputs/modeling/negative_binomial_b4_predictions.csv"

CANDIDATE_BASELINES = [
    {
        "model_name": "poisson_baseline",
        "family": "poisson",
        "generation": "A",
        "feature_block": "base_history_only",
        "metrics_path_attr": "poisson_metrics_csv",
        "predictions_path_attr": "poisson_predictions_csv",
    },
    {
        "model_name": "negative_binomial_baseline",
        "family": "negative_binomial",
        "generation": "B",
        "feature_block": "base_history_only",
        "metrics_path_attr": "negative_binomial_metrics_csv",
        "predictions_path_attr": "negative_binomial_predictions_csv",
    },
    {
        "model_name": "poisson_a2",
        "family": "poisson",
        "generation": "A2",
        "feature_block": "history_plus_lag_safe",
        "metrics_path_attr": "poisson_a2_metrics_csv",
        "predictions_path_attr": "poisson_a2_predictions_csv",
    },
    {
        "model_name": "negative_binomial_b2",
        "family": "negative_binomial",
        "generation": "B2",
        "feature_block": "history_plus_lag_safe",
        "metrics_path_attr": "negative_binomial_b2_metrics_csv",
        "predictions_path_attr": "negative_binomial_b2_predictions_csv",
    },
    {
        "model_name": "poisson_a3",
        "family": "poisson",
        "generation": "A3",
        "feature_block": "history_plus_contextual_lag_safe",
        "metrics_path_attr": "poisson_a3_metrics_csv",
        "predictions_path_attr": "poisson_a3_predictions_csv",
    },
    {
        "model_name": "negative_binomial_b3",
        "family": "negative_binomial",
        "generation": "B3",
        "feature_block": "history_plus_contextual_lag_safe",
        "metrics_path_attr": "negative_binomial_b3_metrics_csv",
        "predictions_path_attr": "negative_binomial_b3_predictions_csv",
    },
    {
        "model_name": "poisson_a4",
        "family": "poisson",
        "generation": "A4",
        "feature_block": "history_plus_contextual_lag_safe_plus_exogenous",
        "metrics_path_attr": "poisson_a4_metrics_csv",
        "predictions_path_attr": "poisson_a4_predictions_csv",
    },
    {
        "model_name": "negative_binomial_b4",
        "family": "negative_binomial",
        "generation": "B4",
        "feature_block": "history_plus_contextual_lag_safe_plus_exogenous",
        "metrics_path_attr": "negative_binomial_b4_metrics_csv",
        "predictions_path_attr": "negative_binomial_b4_predictions_csv",
    },
]


@dataclass(frozen=True)
class ValidationRow:
    validation_name: str
    passed: bool
    evidence: str

    def as_dict(self) -> dict[str, object]:
        return {
            "validation_name": self.validation_name,
            "passed": self.passed,
            "evidence": self.evidence,
        }


def rank_candidates(summary_df: pd.DataFrame) -> pd.DataFrame:
    ordered = summary_df.sort_values(
        by=[
            "validation_mean_poisson_deviance",
            "test_mean_poisson_deviance",
            "validation_rmse",
            "test_rmse",
            "validation_mae",
            "test_mae",
        ],
        ascending=True,
    ).reset_index(drop=True)
    ordered["selection_rank"] = np.arange(1, len(ordered) + 1)
    ordered["selected_global_baseline"] = ordered["selection_rank"].eq(1)
    return ordered


def build_score(values: pd.Series, cap_value: float) -> pd.Series:
    capped = values.clip(lower=0.0, upper=cap_value)
    if cap_value <= 0:
        raise ValueError("Score cap value must be positive.")
    return capped / cap_value * 100.0


def build_validation_rows(
    predictions_df: pd.DataFrame,
    scoring_df: pd.DataFrame,
    selected_model_name: str,
    cap_value: float,
) -> pd.DataFrame:
    validations = [
        ValidationRow(
            "selected_model_is_expected_global_baseline",
            selected_model_name == GLOBAL_SCORING_MODEL_NAME,
            f"selected_model={selected_model_name};expected={GLOBAL_SCORING_MODEL_NAME}",
        ),
        ValidationRow(
            "predictions_unique_on_scoring_unit",
            not predictions_df.duplicated(subset=GLOBAL_SCORING_UNIT_COLUMNS).any(),
            f"duplicate_surplus={int(predictions_df.duplicated(subset=GLOBAL_SCORING_UNIT_COLUMNS).sum())}",
        ),
        ValidationRow(
            "no_missing_predicted_accident_count",
            not scoring_df["predicted_accident_count"].isna().any(),
            f"missing_predicted_accident_count={int(scoring_df['predicted_accident_count'].isna().sum())}",
        ),
        ValidationRow(
            "no_missing_predicted_risk_score_prelim",
            not scoring_df["predicted_risk_score_prelim"].isna().any(),
            f"missing_predicted_risk_score_prelim={int(scoring_df['predicted_risk_score_prelim'].isna().sum())}",
        ),
        ValidationRow(
            "score_range_is_0_100",
            bool(
                scoring_df["predicted_risk_score_prelim"].ge(0.0).all()
                and scoring_df["predicted_risk_score_prelim"].le(100.0).all()
            ),
            (
                f"min_score={float(scoring_df['predicted_risk_score_prelim'].min()):.6f};"
                f"max_score={float(scoring_df['predicted_risk_score_prelim'].max()):.6f}"
            ),
        ),
        ValidationRow(
            "scoring_output_row_count_matches_predictions",
            scoring_df.shape[0] == predictions_df.shape[0],
            f"scoring_rows={int(scoring_df.shape[0])};prediction_rows={int(predictions_df.shape[0])}",
        ),
        ValidationRow(
            "score_transform_cap_positive",
            cap_value > 0,
            f"p99_cap_value={cap_value:.12f}",
        ),
        ValidationRow(
            "scoring_branch_is_global_only",
            scoring_df["model_branch_used"].eq(GLOBAL_DEFAULT_BRANCH_NAME).all(),
            f"model_branch_used_unique={'|'.join(sorted(scoring_df['model_branch_used'].astype(str).unique().tolist()))}",
        ),
        ValidationRow(
            "pilot_branch_not_used",
            not scoring_df["model_branch_used"].eq(PILOT_BRANCH_NAME).any(),
            "pilot_traffic_model not present in scoring output",
        ),
        ValidationRow(
            "prelim_score_not_routing_weight",
            scoring_df["scoring_note"].eq(GLOBAL_SCORING_NOTE_CODE).all(),
            f"scoring_note_unique={'|'.join(sorted(scoring_df['scoring_note'].astype(str).unique().tolist()))}",
        ),
    ]
    return pd.DataFrame([row.as_dict() for row in validations])
