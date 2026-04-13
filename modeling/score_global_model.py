from __future__ import annotations

import argparse
from pathlib import Path
import sys

import pandas as pd

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from modeling.config import build_paths
from modeling.global_scoring_block import (
    CANDIDATE_BASELINES,
    GLOBAL_DEFAULT_BRANCH_NAME,
    GLOBAL_SCORING_ARTIFACT_SOURCE,
    GLOBAL_SCORING_FEATURE_BLOCK,
    GLOBAL_SCORING_MODEL_FAMILY,
    GLOBAL_SCORING_MODEL_NAME,
    GLOBAL_SCORING_NOTE_CODE,
    GLOBAL_SCORING_STATUS_OK,
    GLOBAL_SCORING_TARGET_COLUMN,
    GLOBAL_SCORING_TRANSFORM_CAP_QUANTILE,
    GLOBAL_SCORING_TRANSFORM_RULE,
    GLOBAL_SCORING_UNIT_COLUMNS,
    PILOT_BRANCH_NAME,
    build_score,
    build_validation_rows,
    rank_candidates,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build the global preliminary scoring output from the selected baseline.")
    parser.add_argument("--force", action="store_true", help="Rebuild scoring artifacts even if they already exist.")
    return parser.parse_args()


def _read_overall_metrics(path: Path, model_name: str, family: str, generation: str, feature_block: str) -> dict[str, object]:
    df = pd.read_csv(path)
    if "segment" in df.columns:
        df = df.loc[df["segment"] == "all"].copy()
    validation = df.loc[df["split"] == "validation"].iloc[0]
    test = df.loc[df["split"] == "test"].iloc[0]
    train = df.loc[df["split"] == "train"].iloc[0]
    return {
        "model_name": model_name,
        "family": family,
        "generation": generation,
        "feature_block": feature_block,
        "metrics_artifact": str(path.relative_to(path.parents[2])).replace("\\", "/"),
        "validation_mean_poisson_deviance": float(validation["mean_poisson_deviance"]),
        "validation_mae": float(validation["mae"]),
        "validation_rmse": float(validation["rmse"]),
        "validation_pearson_dispersion": float(validation["pearson_dispersion"]) if pd.notna(validation.get("pearson_dispersion")) else float("nan"),
        "test_mean_poisson_deviance": float(test["mean_poisson_deviance"]),
        "test_mae": float(test["mae"]),
        "test_rmse": float(test["rmse"]),
        "test_pearson_dispersion": float(test["pearson_dispersion"]) if pd.notna(test.get("pearson_dispersion")) else float("nan"),
        "train_mean_poisson_deviance": float(train["mean_poisson_deviance"]),
        "train_mae": float(train["mae"]),
        "train_rmse": float(train["rmse"]),
        "train_pearson_dispersion": float(train["pearson_dispersion"]) if pd.notna(train.get("pearson_dispersion")) else float("nan"),
    }


def build_branch_summary(paths) -> tuple[pd.DataFrame, dict[str, object]]:
    rows = []
    for candidate in CANDIDATE_BASELINES:
        metrics_path = getattr(paths, candidate["metrics_path_attr"])
        predictions_path = getattr(paths, candidate["predictions_path_attr"])
        if not metrics_path.exists() or not predictions_path.exists():
            raise FileNotFoundError(f"Missing candidate artifact: {metrics_path} or {predictions_path}")
        row = _read_overall_metrics(
            metrics_path,
            model_name=candidate["model_name"],
            family=candidate["family"],
            generation=candidate["generation"],
            feature_block=candidate["feature_block"],
        )
        row["predictions_artifact"] = str(predictions_path.relative_to(paths.project_root)).replace("\\", "/")
        rows.append(row)

    summary = rank_candidates(pd.DataFrame(rows))
    selected = summary.loc[summary["selected_global_baseline"]].iloc[0].to_dict()
    summary["selection_rule"] = (
        "rank_by_validation_deviance_then_test_deviance_then_validation_rmse_then_test_rmse_then_validation_mae_then_test_mae"
    )
    summary["selection_rationale"] = summary["selected_global_baseline"].map(
        {
            True: "chosen_as_current_global_baseline_from_existing_artifacts",
            False: "not_selected_after_explicit_artifact_comparison",
        }
    )
    return summary, selected


def build_scoring_contract(cap_value: float) -> pd.DataFrame:
    return pd.DataFrame(
        [
            {
                "output_column": "edge_id",
                "role": "scoring_unit",
                "source": "selected_prediction_artifact",
                "derivation": "copied",
                "notes": "global scoring unit key",
            },
            {
                "output_column": "analysis_year",
                "role": "scoring_unit",
                "source": "selected_prediction_artifact",
                "derivation": "copied",
                "notes": "global scoring unit key",
            },
            {
                "output_column": "temporal_bin_4h",
                "role": "scoring_unit",
                "source": "selected_prediction_artifact",
                "derivation": "copied",
                "notes": "global scoring unit key",
            },
            {
                "output_column": "is_weekend",
                "role": "scoring_unit",
                "source": "selected_prediction_artifact",
                "derivation": "copied",
                "notes": "global scoring unit key",
            },
            {
                "output_column": "predicted_accident_count",
                "role": "raw_model_prediction",
                "source": GLOBAL_SCORING_ARTIFACT_SOURCE,
                "derivation": "copied_from_selected_baseline_predictions",
                "notes": "expected count on the modeling unit",
            },
            {
                "output_column": "predicted_risk_score_prelim",
                "role": "preliminary_score",
                "source": "predicted_accident_count",
                "derivation": f"min(predicted_accident_count,p99_cap={cap_value:.12f})/p99_cap*100",
                "notes": "monotonic capped linear index on 0-100 scale; not a routing weight",
            },
            {
                "output_column": "score_transform_rule",
                "role": "traceability",
                "source": "global_scoring_block",
                "derivation": GLOBAL_SCORING_TRANSFORM_RULE,
                "notes": "transformation code for the preliminary score",
            },
            {
                "output_column": "model_branch_used",
                "role": "traceability",
                "source": "global_scoring_block",
                "derivation": GLOBAL_DEFAULT_BRANCH_NAME,
                "notes": "pilot branch is not used in this phase",
            },
            {
                "output_column": "model_name_used",
                "role": "traceability",
                "source": "global_scoring_block",
                "derivation": GLOBAL_SCORING_MODEL_NAME,
                "notes": "selected current global baseline",
            },
            {
                "output_column": "model_family_used",
                "role": "traceability",
                "source": "global_scoring_block",
                "derivation": GLOBAL_SCORING_MODEL_FAMILY,
                "notes": "selected current global baseline family",
            },
            {
                "output_column": "scoring_status",
                "role": "traceability",
                "source": "global_scoring_block",
                "derivation": GLOBAL_SCORING_STATUS_OK,
                "notes": "row-level scoring status",
            },
            {
                "output_column": "scoring_note",
                "role": "traceability",
                "source": "global_scoring_block",
                "derivation": GLOBAL_SCORING_NOTE_CODE,
                "notes": "explicitly not a final routing weight",
            },
            {
                "output_column": "prediction_split",
                "role": "traceability",
                "source": "selected_prediction_artifact",
                "derivation": "copied",
                "notes": "train/validation/test split from the baseline artifact",
            },
            {
                "output_column": "prediction_bin",
                "role": "traceability",
                "source": "selected_prediction_artifact",
                "derivation": "copied",
                "notes": "bin assigned during baseline evaluation",
            },
        ]
    )


def build_global_vs_pilot_summary(selected_baseline: dict[str, object], paths) -> pd.DataFrame:
    pilot_summary_path = paths.pilot_vs_global_pipeline_summary_csv
    pilot_note = "pilot branch artifacts not required for global scoring execution"
    if pilot_summary_path.exists():
        pilot_df = pd.read_csv(pilot_summary_path)
        pilot_row = pilot_df.loc[pilot_df["pipeline_name"] == PILOT_BRANCH_NAME].iloc[0].to_dict()
    else:
        pilot_row = {
            "pipeline_name": PILOT_BRANCH_NAME,
            "default_active": False,
            "traffic_block_name": "pilot_traffic_d_transformed",
            "traffic_block_active": True,
            "representative_scope": "pilot_2024_months_1_4_7_10_only",
            "target_column": "pilot_accident_count",
            "modeling_unit": "edge_id + analysis_year + month + temporal_bin_4h + is_weekend",
            "time_restriction": "analysis_year=2024 and month in (1,4,7,10)",
            "activation_mode": "explicit_opt_in_only",
            "gating_failure_behavior": "abort_with_clear_message",
            "notes": pilot_note,
        }

    return pd.DataFrame(
        [
            {
                "pipeline_name": GLOBAL_DEFAULT_BRANCH_NAME,
                "default_active": True,
                "selected_baseline_model": selected_baseline["model_name"],
                "selected_baseline_family": selected_baseline["family"],
                "selected_feature_block": selected_baseline["feature_block"],
                "target_column": GLOBAL_SCORING_TARGET_COLUMN,
                "modeling_unit": "edge_id + analysis_year + temporal_bin_4h + is_weekend",
                "scope_restriction": "global_2016_2024_branch",
                "traffic_block_active": False,
                "activation_mode": "default",
                "notes": "global scoring uses the selected baseline only; pilot traffic remains disabled",
            },
            {
                "pipeline_name": PILOT_BRANCH_NAME,
                "default_active": False,
                "selected_baseline_model": "pilot_with_traffic_d",
                "selected_baseline_family": "poisson",
                "selected_feature_block": "pilot_traffic_d_transformed",
                "target_column": pilot_row["target_column"],
                "modeling_unit": pilot_row["modeling_unit"],
                "scope_restriction": pilot_row["time_restriction"],
                "traffic_block_active": True,
                "activation_mode": pilot_row["activation_mode"],
                "notes": "pilot branch remains documented but inactive in this global scoring phase",
            },
        ]
    )


def build_note(selected_baseline: dict[str, object], summary: pd.DataFrame, cap_value: float) -> str:
    selected_row = summary.loc[summary["selected_global_baseline"]].iloc[0]
    runner_up = summary.loc[summary["selection_rank"] == 2].iloc[0]
    lines = [
        "# Global Scoring Architecture Note",
        "",
        "## Scope",
        "- This phase retakes the main global branch only.",
        "- It does not retrain models.",
        "- It does not activate the pilot traffic branch.",
        "- It stops at a preliminary score and does not produce final edge weights or routing costs.",
        "",
        "## Current global baseline",
        f"- Selected baseline: `{selected_baseline['model_name']}`.",
        f"- Family: `{selected_baseline['family']}`.",
        f"- Feature block: `{selected_baseline['feature_block']}`.",
        f"- Validation overall deviance / RMSE: `{selected_baseline['validation_mean_poisson_deviance']:.6f}` / `{selected_baseline['validation_rmse']:.6f}`.",
        f"- Test overall deviance / RMSE: `{selected_baseline['test_mean_poisson_deviance']:.6f}` / `{selected_baseline['test_rmse']:.6f}`.",
        f"- Explicit runner-up after the same ranking rule: `{runner_up['model_name']}`.",
        "",
        "## Scoring architecture",
        "- Training table stays upstream of scoring.",
        "- Model fitting stays upstream of scoring.",
        "- This scoring phase reuses the selected model's existing prediction artifact.",
        "- Score transformation is a separate step from prediction.",
        "- Future edge weighting will be a later mapping from preliminary score to graph cost.",
        "- Future routing will consume weighted edges, not this preliminary score directly.",
        "",
        "## Scoring unit",
        "- `edge_id + analysis_year + temporal_bin_4h + is_weekend`.",
        "- `month` is not part of the global scoring unit because the global branch was modeled at year/bin/weekend resolution, not the pilot monthly branch.",
        "",
        "## Score transform rule",
        f"- Raw quantity kept: `predicted_accident_count`.",
        f"- Preliminary score rule: `{GLOBAL_SCORING_TRANSFORM_RULE}`.",
        f"- Cap reference: p99 of current scoring universe = `{cap_value:.12f}`.",
        "- Rationale: monotonic, interpretable, capped against the heavy tail, and reversible below the cap.",
        "- Alternatives such as percentile rank or log-score remain only documented, not activated here.",
        "",
        "## Global vs pilot separation",
        "- `global_default_model` is the only branch used in this phase.",
        "- `pilot_traffic_model` remains an optional 2024-only capability and is not consulted for this output.",
        "",
        "## What still needs to happen after this phase",
        "- Decide how to collapse or select temporal slices for edge weighting policy.",
        "- Map preliminary score to an actual edge-weighting rule.",
        "- Validate graph-cost behavior before opening routing.",
        "- Keep pilot traffic integration separate until broader traffic coverage exists.",
    ]
    return "\n".join(lines) + "\n"


def main() -> None:
    args = parse_args()
    paths = build_paths()
    outputs = [
        paths.global_scoring_architecture_note_md,
        paths.global_model_branch_summary_csv,
        paths.global_scoring_contract_csv,
        paths.global_scoring_output_prelim_csv,
        paths.global_scoring_validation_summary_csv,
        paths.global_vs_pilot_branch_summary_csv,
    ]
    if all(path.exists() for path in outputs) and not args.force:
        print("Global scoring artifacts already exist. Use --force to rebuild.")
        return

    branch_summary, selected_baseline = build_branch_summary(paths)
    selected_prediction_path = getattr(
        paths,
        next(candidate["predictions_path_attr"] for candidate in CANDIDATE_BASELINES if candidate["model_name"] == selected_baseline["model_name"]),
    )

    predictions = pd.read_csv(
        selected_prediction_path,
        usecols=[
            "edge_id",
            "analysis_year",
            "temporal_bin_4h",
            "is_weekend",
            "predicted_accident_count",
            "prediction_bin",
            "split",
            "model_name",
        ],
    )
    if predictions.duplicated(subset=GLOBAL_SCORING_UNIT_COLUMNS).any():
        raise ValueError("Selected global prediction artifact is not unique on the scoring unit.")
    if predictions["predicted_accident_count"].isna().any():
        raise ValueError("Selected global prediction artifact contains NA predicted_accident_count.")

    cap_value = float(predictions["predicted_accident_count"].quantile(GLOBAL_SCORING_TRANSFORM_CAP_QUANTILE))
    scoring_df = predictions.rename(columns={"split": "prediction_split", "model_name": "model_name_used"}).copy()
    scoring_df["predicted_risk_score_prelim"] = build_score(scoring_df["predicted_accident_count"], cap_value=cap_value)
    scoring_df["score_transform_rule"] = GLOBAL_SCORING_TRANSFORM_RULE
    scoring_df["model_branch_used"] = GLOBAL_DEFAULT_BRANCH_NAME
    scoring_df["model_family_used"] = selected_baseline["family"]
    scoring_df["scoring_status"] = GLOBAL_SCORING_STATUS_OK
    scoring_df["scoring_note"] = GLOBAL_SCORING_NOTE_CODE
    scoring_df = scoring_df[
        [
            "edge_id",
            "analysis_year",
            "temporal_bin_4h",
            "is_weekend",
            "predicted_accident_count",
            "predicted_risk_score_prelim",
            "score_transform_rule",
            "model_branch_used",
            "model_name_used",
            "model_family_used",
            "scoring_status",
            "scoring_note",
            "prediction_split",
            "prediction_bin",
        ]
    ]

    contract_df = build_scoring_contract(cap_value)
    validation_df = build_validation_rows(predictions, scoring_df, selected_model_name=selected_baseline["model_name"], cap_value=cap_value)
    branch_compare_df = build_global_vs_pilot_summary(selected_baseline, paths)
    note = build_note(selected_baseline, branch_summary, cap_value)

    branch_summary.to_csv(paths.global_model_branch_summary_csv, index=False)
    contract_df.to_csv(paths.global_scoring_contract_csv, index=False)
    scoring_df.to_csv(paths.global_scoring_output_prelim_csv, index=False)
    validation_df.to_csv(paths.global_scoring_validation_summary_csv, index=False)
    branch_compare_df.to_csv(paths.global_vs_pilot_branch_summary_csv, index=False)
    paths.global_scoring_architecture_note_md.write_text(note, encoding="utf-8")

    print(f"Created global model branch summary: {paths.global_model_branch_summary_csv}")
    print(f"Created global scoring contract: {paths.global_scoring_contract_csv}")
    print(f"Created global scoring output prelim: {paths.global_scoring_output_prelim_csv}")
    print(f"Created global scoring validation summary: {paths.global_scoring_validation_summary_csv}")
    print(f"Created global vs pilot branch summary: {paths.global_vs_pilot_branch_summary_csv}")
    print(f"Created global scoring architecture note: {paths.global_scoring_architecture_note_md}")


if __name__ == "__main__":
    main()
