from __future__ import annotations

from dataclasses import dataclass
import os
from pathlib import Path


TEMPORAL_BIN_HOURS = 4
TEMPORAL_BIN_LABELS = ["00_03", "04_07", "08_11", "12_15", "16_19", "20_23"]
MODEL_PHASE_NAMESPACE = "outputs/modeling"
TRAINING_TABLE_FILENAME = "training_table_edge_year_bin_weekend.parquet"
TRAINING_SUMMARY_FILENAME = "training_table_summary.csv"
FEATURE_REGISTRY_FILENAME = "training_feature_registry.csv"
TRAINING_WITH_CONTROLS_FILENAME = "training_table_with_controls.parquet"
TRAINING_WITH_CONTROLS_SUMMARY_FILENAME = "training_table_with_controls_summary.csv"
POISSON_METRICS_FILENAME = "poisson_baseline_metrics.csv"
POISSON_COEFFICIENTS_FILENAME = "poisson_baseline_coefficients.csv"
POISSON_NOTE_FILENAME = "poisson_baseline_note.md"
POISSON_PREDICTIONS_FILENAME = "poisson_baseline_predictions.csv"
NEGATIVE_BINOMIAL_METRICS_FILENAME = "negative_binomial_baseline_metrics.csv"
NEGATIVE_BINOMIAL_COEFFICIENTS_FILENAME = "negative_binomial_baseline_coefficients.csv"
NEGATIVE_BINOMIAL_NOTE_FILENAME = "negative_binomial_baseline_note.md"
NEGATIVE_BINOMIAL_PREDICTIONS_FILENAME = "negative_binomial_baseline_predictions.csv"
POISSON_VS_NB_COMPARISON_FILENAME = "poisson_vs_nb_comparison.csv"
POISSON_VS_NB_NOTE_FILENAME = "poisson_vs_nb_note.md"
TRAINING_WITH_LAG_SAFE_FEATURES_FILENAME = "training_table_with_lag_safe_features.parquet"
LAG_SAFE_FEATURE_REGISTRY_FILENAME = "lag_safe_feature_registry.csv"
LAG_SAFE_FEATURE_SUMMARY_FILENAME = "lag_safe_feature_summary.csv"
LAG_SAFE_FEATURE_NOTE_FILENAME = "lag_safe_feature_note.md"
POISSON_A2_METRICS_FILENAME = "poisson_a2_metrics.csv"
POISSON_A2_COEFFICIENTS_FILENAME = "poisson_a2_coefficients.csv"
POISSON_A2_PREDICTIONS_FILENAME = "poisson_a2_predictions.csv"
NEGATIVE_BINOMIAL_B2_METRICS_FILENAME = "negative_binomial_b2_metrics.csv"
NEGATIVE_BINOMIAL_B2_COEFFICIENTS_FILENAME = "negative_binomial_b2_coefficients.csv"
NEGATIVE_BINOMIAL_B2_PREDICTIONS_FILENAME = "negative_binomial_b2_predictions.csv"
A2_B2_COMPARISON_FILENAME = "a2_b2_comparison.csv"
A2_B2_NOTE_FILENAME = "a2_b2_note.md"
BASELINE_AB_VS_A2B2_COMPARISON_FILENAME = "baseline_ab_vs_a2b2_comparison.csv"
TRAINING_WITH_CONTEXTUAL_LAG_SAFE_FEATURES_FILENAME = "training_table_with_contextual_lag_safe_features.parquet"
CONTEXTUAL_LAG_SAFE_FEATURE_REGISTRY_FILENAME = "contextual_lag_safe_feature_registry.csv"
CONTEXTUAL_LAG_SAFE_FEATURE_SUMMARY_FILENAME = "contextual_lag_safe_feature_summary.csv"
CONTEXTUAL_LAG_SAFE_FEATURE_NOTE_FILENAME = "contextual_lag_safe_feature_note.md"
POISSON_A3_METRICS_FILENAME = "poisson_a3_metrics.csv"
POISSON_A3_COEFFICIENTS_FILENAME = "poisson_a3_coefficients.csv"
POISSON_A3_PREDICTIONS_FILENAME = "poisson_a3_predictions.csv"
NEGATIVE_BINOMIAL_B3_METRICS_FILENAME = "negative_binomial_b3_metrics.csv"
NEGATIVE_BINOMIAL_B3_COEFFICIENTS_FILENAME = "negative_binomial_b3_coefficients.csv"
NEGATIVE_BINOMIAL_B3_PREDICTIONS_FILENAME = "negative_binomial_b3_predictions.csv"
A3_B3_COMPARISON_FILENAME = "a3_b3_comparison.csv"
A3_B3_NOTE_FILENAME = "a3_b3_note.md"
BASELINE_A2B2_VS_A3B3_COMPARISON_FILENAME = "baseline_a2b2_vs_a3b3_comparison.csv"
TRAINING_WITH_EXOGENOUS_CONTEXT_FEATURES_FILENAME = "training_table_with_exogenous_context_features.parquet"
EXOGENOUS_FEATURE_REGISTRY_FILENAME = "exogenous_feature_registry.csv"
EXOGENOUS_FEATURE_SUMMARY_FILENAME = "exogenous_feature_summary.csv"
EXOGENOUS_FEATURE_NOTE_FILENAME = "exogenous_feature_note.md"
POISSON_A4_METRICS_FILENAME = "poisson_a4_metrics.csv"
POISSON_A4_COEFFICIENTS_FILENAME = "poisson_a4_coefficients.csv"
POISSON_A4_PREDICTIONS_FILENAME = "poisson_a4_predictions.csv"
NEGATIVE_BINOMIAL_B4_METRICS_FILENAME = "negative_binomial_b4_metrics.csv"
NEGATIVE_BINOMIAL_B4_COEFFICIENTS_FILENAME = "negative_binomial_b4_coefficients.csv"
NEGATIVE_BINOMIAL_B4_PREDICTIONS_FILENAME = "negative_binomial_b4_predictions.csv"
A4_B4_COMPARISON_FILENAME = "a4_b4_comparison.csv"
A4_B4_NOTE_FILENAME = "a4_b4_note.md"
BASELINE_A3B3_VS_A4B4_COMPARISON_FILENAME = "baseline_a3b3_vs_a4b4_comparison.csv"
EXOGENOUS_FEATURE_EFFECT_SUMMARY_FILENAME = "exogenous_feature_effect_summary.csv"
TRAINING_WITH_TRUE_DYNAMIC_EXOGENOUS_FEATURES_FILENAME = "training_table_with_true_dynamic_exogenous_features.parquet"
DYNAMIC_EXOGENOUS_FEATURE_REGISTRY_FILENAME = "dynamic_exogenous_feature_registry.csv"
DYNAMIC_EXOGENOUS_FEATURE_SUMMARY_FILENAME = "dynamic_exogenous_feature_summary.csv"
DYNAMIC_EXOGENOUS_FEATURE_NOTE_FILENAME = "dynamic_exogenous_feature_note.md"
PILOT_TRAFFIC_TRAINING_TABLE_FILENAME = "traffic_2024_4months_pilot_training_table.csv"
PILOT_TRAFFIC_FEATURE_CONTRACT_FILENAME = "pilot_traffic_feature_contract.csv"
PILOT_TRAFFIC_D_INPUT_FILENAME = "pilot_traffic_d_transformed_input.parquet"
PILOT_PYTHON_BASELINE_NO_TRAFFIC_METRICS_FILENAME = "pilot_python_baseline_no_traffic_metrics.csv"
PILOT_PYTHON_BASELINE_WITH_TRAFFIC_METRICS_FILENAME = "pilot_python_baseline_with_traffic_metrics.csv"
PILOT_PYTHON_TRAFFIC_COMPARISON_FILENAME = "pilot_python_traffic_comparison.csv"
PILOT_PYTHON_TRAFFIC_NOTE_FILENAME = "pilot_python_traffic_note.md"
PILOT_PYTHON_TRAFFIC_PREDICTIONS_FILENAME = "pilot_python_traffic_predictions.csv"
PILOT_TRAFFIC_ARCHITECTURE_NOTE_FILENAME = "pilot_traffic_architecture_note.md"
PILOT_TRAFFIC_FEATURE_BLOCK_CONTRACT_FILENAME = "pilot_traffic_feature_block_contract.csv"
PILOT_TRAFFIC_PIPELINE_GATING_RULES_FILENAME = "pilot_traffic_pipeline_gating_rules.csv"
PILOT_VS_GLOBAL_PIPELINE_SUMMARY_FILENAME = "pilot_vs_global_pipeline_summary.csv"
GLOBAL_SCORING_ARCHITECTURE_NOTE_FILENAME = "global_scoring_architecture_note.md"
GLOBAL_MODEL_BRANCH_SUMMARY_FILENAME = "global_model_branch_summary.csv"
GLOBAL_SCORING_CONTRACT_FILENAME = "global_scoring_contract.csv"
GLOBAL_SCORING_OUTPUT_PRELIM_FILENAME = "global_scoring_output_prelim.csv"
GLOBAL_SCORING_VALIDATION_SUMMARY_FILENAME = "global_scoring_validation_summary.csv"
GLOBAL_VS_PILOT_BRANCH_SUMMARY_FILENAME = "global_vs_pilot_branch_summary.csv"
PIPELINE_ROOT_ENV_VAR = "ROAD_SAFETY_PIPELINE_ROOT"


@dataclass(frozen=True)
class ProjectPaths:
    project_root: Path
    processed_root: Path
    outputs_root: Path
    outputs_data: Path
    outputs_tables: Path
    modeling_root: Path
    modeling_data: Path
    modeling_tables: Path

    m8_edges_csv: Path
    m8_nodes_csv: Path
    m8_edges_geojson: Path
    m9_matches_csv: Path
    accident_master_csv: Path
    m10_historical_csv: Path
    m11_historical_adjusted_csv: Path
    m12_dynamic_base_csv: Path

    training_table_parquet: Path
    training_summary_csv: Path
    feature_registry_csv: Path
    training_with_controls_parquet: Path
    training_with_controls_summary_csv: Path
    poisson_metrics_csv: Path
    poisson_coefficients_csv: Path
    poisson_note_md: Path
    poisson_predictions_csv: Path
    negative_binomial_metrics_csv: Path
    negative_binomial_coefficients_csv: Path
    negative_binomial_note_md: Path
    negative_binomial_predictions_csv: Path
    poisson_vs_nb_comparison_csv: Path
    poisson_vs_nb_note_md: Path
    training_with_lag_safe_features_parquet: Path
    lag_safe_feature_registry_csv: Path
    lag_safe_feature_summary_csv: Path
    lag_safe_feature_note_md: Path
    poisson_a2_metrics_csv: Path
    poisson_a2_coefficients_csv: Path
    poisson_a2_predictions_csv: Path
    negative_binomial_b2_metrics_csv: Path
    negative_binomial_b2_coefficients_csv: Path
    negative_binomial_b2_predictions_csv: Path
    a2_b2_comparison_csv: Path
    a2_b2_note_md: Path
    baseline_ab_vs_a2b2_comparison_csv: Path
    training_with_contextual_lag_safe_features_parquet: Path
    contextual_lag_safe_feature_registry_csv: Path
    contextual_lag_safe_feature_summary_csv: Path
    contextual_lag_safe_feature_note_md: Path
    poisson_a3_metrics_csv: Path
    poisson_a3_coefficients_csv: Path
    poisson_a3_predictions_csv: Path
    negative_binomial_b3_metrics_csv: Path
    negative_binomial_b3_coefficients_csv: Path
    negative_binomial_b3_predictions_csv: Path
    a3_b3_comparison_csv: Path
    a3_b3_note_md: Path
    baseline_a2b2_vs_a3b3_comparison_csv: Path
    training_with_exogenous_context_features_parquet: Path
    exogenous_feature_registry_csv: Path
    exogenous_feature_summary_csv: Path
    exogenous_feature_note_md: Path
    poisson_a4_metrics_csv: Path
    poisson_a4_coefficients_csv: Path
    poisson_a4_predictions_csv: Path
    negative_binomial_b4_metrics_csv: Path
    negative_binomial_b4_coefficients_csv: Path
    negative_binomial_b4_predictions_csv: Path
    a4_b4_comparison_csv: Path
    a4_b4_note_md: Path
    baseline_a3b3_vs_a4b4_comparison_csv: Path
    exogenous_feature_effect_summary_csv: Path
    training_with_true_dynamic_exogenous_features_parquet: Path
    dynamic_exogenous_feature_registry_csv: Path
    dynamic_exogenous_feature_summary_csv: Path
    dynamic_exogenous_feature_note_md: Path
    pilot_traffic_training_table_csv: Path
    pilot_traffic_feature_contract_csv: Path
    pilot_traffic_d_input_parquet: Path
    pilot_python_baseline_no_traffic_metrics_csv: Path
    pilot_python_baseline_with_traffic_metrics_csv: Path
    pilot_python_traffic_comparison_csv: Path
    pilot_python_traffic_note_md: Path
    pilot_python_traffic_predictions_csv: Path
    pilot_traffic_architecture_note_md: Path
    pilot_traffic_feature_block_contract_csv: Path
    pilot_traffic_pipeline_gating_rules_csv: Path
    pilot_vs_global_pipeline_summary_csv: Path
    global_scoring_architecture_note_md: Path
    global_model_branch_summary_csv: Path
    global_scoring_contract_csv: Path
    global_scoring_output_prelim_csv: Path
    global_scoring_validation_summary_csv: Path
    global_vs_pilot_branch_summary_csv: Path


def get_project_root() -> Path:
    override = os.environ.get(PIPELINE_ROOT_ENV_VAR)
    if override:
        return Path(override).expanduser().resolve()
    return Path(__file__).resolve().parents[3]


def build_paths(project_root: Path | None = None) -> ProjectPaths:
    root = project_root or get_project_root()
    processed_root = root / "data" / "processed"
    outputs_root = root / "outputs"
    outputs_data = outputs_root / "data"
    outputs_tables = outputs_root / "tables"
    modeling_root = outputs_root / "modeling"
    modeling_data = modeling_root / "data"
    modeling_tables = modeling_root / "tables"

    for path in (outputs_root, outputs_data, outputs_tables, modeling_root, modeling_data, modeling_tables):
      path.mkdir(parents=True, exist_ok=True)

    return ProjectPaths(
        project_root=root,
        processed_root=processed_root,
        outputs_root=outputs_root,
        outputs_data=outputs_data,
        outputs_tables=outputs_tables,
        modeling_root=modeling_root,
        modeling_data=modeling_data,
        modeling_tables=modeling_tables,
        m8_edges_csv=outputs_data / "m8_road_network_edges.csv",
        m8_nodes_csv=outputs_data / "m8_road_network_nodes.csv",
        m8_edges_geojson=outputs_data / "m8_road_network_edges.geojson",
        m9_matches_csv=outputs_data / "m9_accident_edge_matches.csv",
        accident_master_csv=outputs_data / "accidentes_tabla_accidente_master.csv",
        m10_historical_csv=outputs_data / "m10_edge_historical_aggregation.csv",
        m11_historical_adjusted_csv=outputs_data / "m11_historical_exposure_adjusted.csv",
        m12_dynamic_base_csv=outputs_data / "m12_edge_context_dynamic_base.csv",
        training_table_parquet=modeling_data / TRAINING_TABLE_FILENAME,
        training_summary_csv=modeling_tables / TRAINING_SUMMARY_FILENAME,
        feature_registry_csv=modeling_tables / FEATURE_REGISTRY_FILENAME,
        training_with_controls_parquet=modeling_root / TRAINING_WITH_CONTROLS_FILENAME,
        training_with_controls_summary_csv=modeling_root / TRAINING_WITH_CONTROLS_SUMMARY_FILENAME,
        poisson_metrics_csv=modeling_root / POISSON_METRICS_FILENAME,
        poisson_coefficients_csv=modeling_root / POISSON_COEFFICIENTS_FILENAME,
        poisson_note_md=modeling_root / POISSON_NOTE_FILENAME,
        poisson_predictions_csv=modeling_root / POISSON_PREDICTIONS_FILENAME,
        negative_binomial_metrics_csv=modeling_root / NEGATIVE_BINOMIAL_METRICS_FILENAME,
        negative_binomial_coefficients_csv=modeling_root / NEGATIVE_BINOMIAL_COEFFICIENTS_FILENAME,
        negative_binomial_note_md=modeling_root / NEGATIVE_BINOMIAL_NOTE_FILENAME,
        negative_binomial_predictions_csv=modeling_root / NEGATIVE_BINOMIAL_PREDICTIONS_FILENAME,
        poisson_vs_nb_comparison_csv=modeling_root / POISSON_VS_NB_COMPARISON_FILENAME,
        poisson_vs_nb_note_md=modeling_root / POISSON_VS_NB_NOTE_FILENAME,
        training_with_lag_safe_features_parquet=modeling_root / TRAINING_WITH_LAG_SAFE_FEATURES_FILENAME,
        lag_safe_feature_registry_csv=modeling_root / LAG_SAFE_FEATURE_REGISTRY_FILENAME,
        lag_safe_feature_summary_csv=modeling_root / LAG_SAFE_FEATURE_SUMMARY_FILENAME,
        lag_safe_feature_note_md=modeling_root / LAG_SAFE_FEATURE_NOTE_FILENAME,
        poisson_a2_metrics_csv=modeling_root / POISSON_A2_METRICS_FILENAME,
        poisson_a2_coefficients_csv=modeling_root / POISSON_A2_COEFFICIENTS_FILENAME,
        poisson_a2_predictions_csv=modeling_root / POISSON_A2_PREDICTIONS_FILENAME,
        negative_binomial_b2_metrics_csv=modeling_root / NEGATIVE_BINOMIAL_B2_METRICS_FILENAME,
        negative_binomial_b2_coefficients_csv=modeling_root / NEGATIVE_BINOMIAL_B2_COEFFICIENTS_FILENAME,
        negative_binomial_b2_predictions_csv=modeling_root / NEGATIVE_BINOMIAL_B2_PREDICTIONS_FILENAME,
        a2_b2_comparison_csv=modeling_root / A2_B2_COMPARISON_FILENAME,
        a2_b2_note_md=modeling_root / A2_B2_NOTE_FILENAME,
        baseline_ab_vs_a2b2_comparison_csv=modeling_root / BASELINE_AB_VS_A2B2_COMPARISON_FILENAME,
        training_with_contextual_lag_safe_features_parquet=modeling_root / TRAINING_WITH_CONTEXTUAL_LAG_SAFE_FEATURES_FILENAME,
        contextual_lag_safe_feature_registry_csv=modeling_root / CONTEXTUAL_LAG_SAFE_FEATURE_REGISTRY_FILENAME,
        contextual_lag_safe_feature_summary_csv=modeling_root / CONTEXTUAL_LAG_SAFE_FEATURE_SUMMARY_FILENAME,
        contextual_lag_safe_feature_note_md=modeling_root / CONTEXTUAL_LAG_SAFE_FEATURE_NOTE_FILENAME,
        poisson_a3_metrics_csv=modeling_root / POISSON_A3_METRICS_FILENAME,
        poisson_a3_coefficients_csv=modeling_root / POISSON_A3_COEFFICIENTS_FILENAME,
        poisson_a3_predictions_csv=modeling_root / POISSON_A3_PREDICTIONS_FILENAME,
        negative_binomial_b3_metrics_csv=modeling_root / NEGATIVE_BINOMIAL_B3_METRICS_FILENAME,
        negative_binomial_b3_coefficients_csv=modeling_root / NEGATIVE_BINOMIAL_B3_COEFFICIENTS_FILENAME,
        negative_binomial_b3_predictions_csv=modeling_root / NEGATIVE_BINOMIAL_B3_PREDICTIONS_FILENAME,
        a3_b3_comparison_csv=modeling_root / A3_B3_COMPARISON_FILENAME,
        a3_b3_note_md=modeling_root / A3_B3_NOTE_FILENAME,
        baseline_a2b2_vs_a3b3_comparison_csv=modeling_root / BASELINE_A2B2_VS_A3B3_COMPARISON_FILENAME,
        training_with_exogenous_context_features_parquet=modeling_root / TRAINING_WITH_EXOGENOUS_CONTEXT_FEATURES_FILENAME,
        exogenous_feature_registry_csv=modeling_root / EXOGENOUS_FEATURE_REGISTRY_FILENAME,
        exogenous_feature_summary_csv=modeling_root / EXOGENOUS_FEATURE_SUMMARY_FILENAME,
        exogenous_feature_note_md=modeling_root / EXOGENOUS_FEATURE_NOTE_FILENAME,
        poisson_a4_metrics_csv=modeling_root / POISSON_A4_METRICS_FILENAME,
        poisson_a4_coefficients_csv=modeling_root / POISSON_A4_COEFFICIENTS_FILENAME,
        poisson_a4_predictions_csv=modeling_root / POISSON_A4_PREDICTIONS_FILENAME,
        negative_binomial_b4_metrics_csv=modeling_root / NEGATIVE_BINOMIAL_B4_METRICS_FILENAME,
        negative_binomial_b4_coefficients_csv=modeling_root / NEGATIVE_BINOMIAL_B4_COEFFICIENTS_FILENAME,
        negative_binomial_b4_predictions_csv=modeling_root / NEGATIVE_BINOMIAL_B4_PREDICTIONS_FILENAME,
        a4_b4_comparison_csv=modeling_root / A4_B4_COMPARISON_FILENAME,
        a4_b4_note_md=modeling_root / A4_B4_NOTE_FILENAME,
        baseline_a3b3_vs_a4b4_comparison_csv=modeling_root / BASELINE_A3B3_VS_A4B4_COMPARISON_FILENAME,
        exogenous_feature_effect_summary_csv=modeling_root / EXOGENOUS_FEATURE_EFFECT_SUMMARY_FILENAME,
        training_with_true_dynamic_exogenous_features_parquet=modeling_root / TRAINING_WITH_TRUE_DYNAMIC_EXOGENOUS_FEATURES_FILENAME,
        dynamic_exogenous_feature_registry_csv=modeling_root / DYNAMIC_EXOGENOUS_FEATURE_REGISTRY_FILENAME,
        dynamic_exogenous_feature_summary_csv=modeling_root / DYNAMIC_EXOGENOUS_FEATURE_SUMMARY_FILENAME,
        dynamic_exogenous_feature_note_md=modeling_root / DYNAMIC_EXOGENOUS_FEATURE_NOTE_FILENAME,
        pilot_traffic_training_table_csv=processed_root / PILOT_TRAFFIC_TRAINING_TABLE_FILENAME,
        pilot_traffic_feature_contract_csv=modeling_root / PILOT_TRAFFIC_FEATURE_CONTRACT_FILENAME,
        pilot_traffic_d_input_parquet=modeling_root / PILOT_TRAFFIC_D_INPUT_FILENAME,
        pilot_python_baseline_no_traffic_metrics_csv=modeling_root / PILOT_PYTHON_BASELINE_NO_TRAFFIC_METRICS_FILENAME,
        pilot_python_baseline_with_traffic_metrics_csv=modeling_root / PILOT_PYTHON_BASELINE_WITH_TRAFFIC_METRICS_FILENAME,
        pilot_python_traffic_comparison_csv=modeling_root / PILOT_PYTHON_TRAFFIC_COMPARISON_FILENAME,
        pilot_python_traffic_note_md=modeling_root / PILOT_PYTHON_TRAFFIC_NOTE_FILENAME,
        pilot_python_traffic_predictions_csv=modeling_root / PILOT_PYTHON_TRAFFIC_PREDICTIONS_FILENAME,
        pilot_traffic_architecture_note_md=modeling_root / PILOT_TRAFFIC_ARCHITECTURE_NOTE_FILENAME,
        pilot_traffic_feature_block_contract_csv=modeling_root / PILOT_TRAFFIC_FEATURE_BLOCK_CONTRACT_FILENAME,
        pilot_traffic_pipeline_gating_rules_csv=modeling_root / PILOT_TRAFFIC_PIPELINE_GATING_RULES_FILENAME,
        pilot_vs_global_pipeline_summary_csv=modeling_root / PILOT_VS_GLOBAL_PIPELINE_SUMMARY_FILENAME,
        global_scoring_architecture_note_md=modeling_root / GLOBAL_SCORING_ARCHITECTURE_NOTE_FILENAME,
        global_model_branch_summary_csv=modeling_root / GLOBAL_MODEL_BRANCH_SUMMARY_FILENAME,
        global_scoring_contract_csv=modeling_root / GLOBAL_SCORING_CONTRACT_FILENAME,
        global_scoring_output_prelim_csv=modeling_root / GLOBAL_SCORING_OUTPUT_PRELIM_FILENAME,
        global_scoring_validation_summary_csv=modeling_root / GLOBAL_SCORING_VALIDATION_SUMMARY_FILENAME,
        global_vs_pilot_branch_summary_csv=modeling_root / GLOBAL_VS_PILOT_BRANCH_SUMMARY_FILENAME,
    )
