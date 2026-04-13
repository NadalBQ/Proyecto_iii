from __future__ import annotations

import argparse
from pathlib import Path
import sys

import pandas as pd

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from modeling.config import build_paths
from modeling.pilot_traffic_block import (
    GLOBAL_DEFAULT_PIPELINE_NAME,
    PILOT_TRAFFIC_ALLOWED_MONTHS,
    PILOT_TRAFFIC_ALLOWED_YEAR,
    PILOT_TRAFFIC_BLOCK_COLUMNS,
    PILOT_TRAFFIC_EXCLUDED_COLUMNS,
    PILOT_TRAFFIC_FEATURE_BLOCK_NAME,
    PILOT_TRAFFIC_PIPELINE_NAME,
    assert_validated,
    build_gating_rules,
    build_pipeline_summary,
    validate_pilot_raw_training_table,
    validate_pilot_transformed_input,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build pilot traffic architecture and gating artifacts.")
    parser.add_argument("--force", action="store_true", help="Rebuild architecture artifacts even if they already exist.")
    return parser.parse_args()


def build_feature_block_contract(feature_contract: pd.DataFrame) -> pd.DataFrame:
    filtered = feature_contract.loc[
        feature_contract["feature_name"].isin(PILOT_TRAFFIC_BLOCK_COLUMNS + PILOT_TRAFFIC_EXCLUDED_COLUMNS)
    ].copy()
    filtered.insert(0, "pipeline_name", PILOT_TRAFFIC_PIPELINE_NAME)
    filtered.insert(1, "feature_block_name", PILOT_TRAFFIC_FEATURE_BLOCK_NAME)
    filtered.insert(
        2,
        "block_membership",
        filtered["feature_name"].where(
            filtered["feature_name"].isin(PILOT_TRAFFIC_EXCLUDED_COLUMNS),
            other="active_block_member",
        ),
    )
    filtered["block_membership"] = filtered["block_membership"].replace(
        {feature: "explicitly_excluded" for feature in PILOT_TRAFFIC_EXCLUDED_COLUMNS}
    )
    filtered["required_for_block_activation"] = filtered["feature_name"].isin(PILOT_TRAFFIC_BLOCK_COLUMNS)
    filtered["activation_mode"] = "explicit_opt_in_only"
    filtered["scope_restriction"] = "analysis_year=2024 and month in (1,4,7,10)"
    filtered["fallback_if_requested_and_ineligible"] = "abort_with_clear_message"
    return filtered[
        [
            "pipeline_name",
            "feature_block_name",
            "block_membership",
            "feature_name",
            "role",
            "source_columns",
            "transformation",
            "imputation_rule",
            "training_scope_for_params",
            "required_for_block_activation",
            "include_in_with_traffic_baseline",
            "leak_safe",
            "pilot_scope_only",
            "activation_mode",
            "scope_restriction",
            "fallback_if_requested_and_ineligible",
            "exclusion_reason",
            "parameter_details",
        ]
    ]


def build_note(
    validation_raw: pd.DataFrame,
    validation_input: pd.DataFrame,
    gating_rules: pd.DataFrame,
    pipeline_summary: pd.DataFrame,
) -> str:
    raw_pass = int(validation_raw["passed"].sum())
    raw_total = int(validation_raw.shape[0])
    input_pass = int(validation_input["passed"].sum())
    input_total = int(validation_input.shape[0])
    pilot_row = pipeline_summary.loc[pipeline_summary["pipeline_name"] == PILOT_TRAFFIC_PIPELINE_NAME].iloc[0]
    global_row = pipeline_summary.loc[pipeline_summary["pipeline_name"] == GLOBAL_DEFAULT_PIPELINE_NAME].iloc[0]

    lines = [
        "# Pilot Traffic Architecture Note",
        "",
        "## Scope",
        "- This is an architectural consolidation only.",
        "- It does not retrain models.",
        "- It does not promote the pilot 2024 traffic branch to the global default pipeline.",
        "",
        "## Surviving pilot traffic block",
        f"- Feature block name: `{PILOT_TRAFFIC_FEATURE_BLOCK_NAME}`.",
        "- Active block columns:",
    ]
    for column in PILOT_TRAFFIC_BLOCK_COLUMNS:
        lines.append(f"  - `{column}`")
    lines.append("- Explicitly excluded from the main pilot block:")
    for column in PILOT_TRAFFIC_EXCLUDED_COLUMNS:
        lines.append(f"  - `{column}`")

    lines.extend(
        [
            "",
            "## Global vs pilot separation",
            f"- `{global_row['pipeline_name']}` stays default and keeps the pilot traffic block disabled.",
            f"- `{pilot_row['pipeline_name']}` is an explicit opt-in branch for the pilot scope only.",
            f"- Pilot scope restriction: `analysis_year = {PILOT_TRAFFIC_ALLOWED_YEAR}` and `month in {PILOT_TRAFFIC_ALLOWED_MONTHS}`.",
            "",
            "## Gating behavior",
            "- The pilot traffic block is never auto-enabled inside the global branch.",
            "- If the pilot branch is requested and pilot-only preconditions fail, the pipeline must abort with a clear message.",
            "- Silent fallback from requested pilot traffic to global no-traffic is not allowed.",
            "",
            "## Current validation status",
            f"- Raw pilot training table rules passed: `{raw_pass}/{raw_total}`.",
            f"- Transformed pilot input rules passed: `{input_pass}/{input_total}`.",
        ]
    )
    failed_rules = gating_rules.loc[~gating_rules["passed"]]
    if failed_rules.empty:
        lines.append("- Current architecture audit: all gating rules pass on the existing pilot artifacts.")
    else:
        lines.append("- Current architecture audit failed rules:")
        for row in failed_rules.itertuples(index=False):
            lines.append(f"  - `{row.gating_stage}.{row.rule_name}` -> {row.evidence}")

    lines.extend(
        [
            "",
            "## Where the block lives",
            "- Contract and gating constants live in `modeling/pilot_traffic_block.py`.",
            "- Pilot input builder lives in `modeling/build_pilot_traffic_input.py`.",
            "- Pilot training script lives in `modeling/train_pilot_traffic_baselines.py`.",
            "- Architecture audit lives in `modeling/build_pilot_traffic_architecture.py`.",
            "",
            "## Future integration boundary",
            "- This prepares coexistence between the global branch and the pilot traffic branch.",
            "- It does not make traffic globally available across 2016-2024.",
            "- A deeper integration would require broader traffic coverage and a new leakage audit before promoting any traffic block beyond the pilot branch.",
        ]
    )
    return "\n".join(lines) + "\n"


def main() -> None:
    args = parse_args()
    paths = build_paths()

    outputs = [
        paths.pilot_traffic_architecture_note_md,
        paths.pilot_traffic_feature_block_contract_csv,
        paths.pilot_traffic_pipeline_gating_rules_csv,
        paths.pilot_vs_global_pipeline_summary_csv,
    ]
    if all(path.exists() for path in outputs) and not args.force:
        print("Pilot traffic architecture artifacts already exist. Use --force to rebuild.")
        return

    required = [
        paths.pilot_traffic_training_table_csv,
        paths.pilot_traffic_feature_contract_csv,
        paths.pilot_traffic_d_input_parquet,
        paths.pilot_python_traffic_note_md,
    ]
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        raise FileNotFoundError(f"Missing required pilot traffic artifacts: {missing}")

    raw_df = pd.read_csv(paths.pilot_traffic_training_table_csv)
    transformed_df = pd.read_parquet(paths.pilot_traffic_d_input_parquet)
    feature_contract = pd.read_csv(paths.pilot_traffic_feature_contract_csv)

    validation_raw = validate_pilot_raw_training_table(raw_df)
    validation_input = validate_pilot_transformed_input(transformed_df)
    gating_rules = build_gating_rules(validation_raw, validation_input)
    pipeline_summary = build_pipeline_summary()
    feature_block_contract = build_feature_block_contract(feature_contract)

    assert_validated(validation_raw, "Pilot traffic raw training table")
    assert_validated(validation_input, "Pilot traffic transformed input")

    paths.pilot_traffic_feature_block_contract_csv.write_text(
        feature_block_contract.to_csv(index=False),
        encoding="utf-8",
    )
    paths.pilot_traffic_pipeline_gating_rules_csv.write_text(
        gating_rules.to_csv(index=False),
        encoding="utf-8",
    )
    paths.pilot_vs_global_pipeline_summary_csv.write_text(
        pipeline_summary.to_csv(index=False),
        encoding="utf-8",
    )
    note = build_note(validation_raw, validation_input, gating_rules, pipeline_summary)
    paths.pilot_traffic_architecture_note_md.write_text(note, encoding="utf-8")

    print(f"Created pilot traffic feature block contract: {paths.pilot_traffic_feature_block_contract_csv}")
    print(f"Created pilot traffic gating rules: {paths.pilot_traffic_pipeline_gating_rules_csv}")
    print(f"Created pilot vs global pipeline summary: {paths.pilot_vs_global_pipeline_summary_csv}")
    print(f"Created pilot traffic architecture note: {paths.pilot_traffic_architecture_note_md}")


if __name__ == "__main__":
    main()
