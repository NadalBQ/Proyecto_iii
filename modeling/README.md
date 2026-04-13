# ROAD-SAFETY Modeling Environment

## Scope

This folder contains the active Python-side global modeling pipeline used after the upstream R preparation stages.

The active line does four things:
- build the training table
- add controls and safe feature blocks
- train the global baseline comparison chain
- build the preliminary global scoring output

## Environment

- Recommended Python: `3.12`
- Working directory: project root

## Setup from VS Code / terminal

```powershell
py -3 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r modeling\requirements.txt
```

## Active files

Configuration:
- `config.py`

Builders:
- `build_training_table.py`
- `build_training_table_with_controls.py`
- `build_lag_safe_features.py`
- `build_contextual_lag_safe_features.py`
- `build_exogenous_context_features.py`

Training:
- `train_baseline.py`
- `train_negative_binomial.py`
- `train_lag_safe_baselines.py`
- `train_contextual_baselines.py`
- `train_exogenous_baselines.py`

Scoring:
- `global_scoring_block.py`
- `score_global_model.py`

Convenience runner:
- `run_global_model_pipeline.py`

## Recommended execution

Run the full active global modeling chain:

```powershell
python modeling\run_global_model_pipeline.py --force
```

Equivalent explicit sequence:

```powershell
python modeling\build_training_table.py --force
python modeling\build_training_table_with_controls.py --force
python modeling\build_lag_safe_features.py --force
python modeling\build_contextual_lag_safe_features.py --force
python modeling\build_exogenous_context_features.py --force
python modeling\train_baseline.py --force
python modeling\train_negative_binomial.py --force
python modeling\train_lag_safe_baselines.py --force
python modeling\train_contextual_baselines.py --force
python modeling\train_exogenous_baselines.py --force
python modeling\score_global_model.py --force
```

## Current active minable view

The final active modeling table is:

- `outputs/modeling/training_table_with_exogenous_context_features.parquet`

This is the active minable view for the global line.

## Current active baseline

The selected active global baseline is:

- `negative_binomial_b4`

Selection traceability lives in:

- `outputs/modeling/global_model_branch_summary.csv`

Supporting lightweight artifacts kept in the shared repo:
- `outputs/modeling/negative_binomial_b4_metrics.csv`
- `outputs/modeling/negative_binomial_b4_coefficients.csv`
- `outputs/modeling/exogenous_feature_registry.csv`
- `outputs/modeling/exogenous_feature_summary.csv`
- `outputs/modeling/exogenous_feature_note.md`
- `outputs/modeling/tables/training_table_summary.csv`
- `outputs/modeling/tables/training_feature_registry.csv`

## Global scoring

The scoring unit is:

- `edge_id + analysis_year + temporal_bin_4h + is_weekend`

The main scoring output is:

- `outputs/modeling/global_scoring_output_prelim.csv`

Important:
- `predicted_risk_score_prelim` is a preliminary model-derived score
- it is **not** a final routing edge weight or routing cost

Supporting lightweight scoring artifacts kept in the shared repo:
- `outputs/modeling/global_scoring_architecture_note.md`
- `outputs/modeling/global_scoring_contract.csv`
- `outputs/modeling/global_scoring_validation_summary.csv`

## Guardrails

- Do not treat full-period accident-backed outputs as direct exogenous predictors.
- Do not change target or temporal split silently.
- Do not interpret the preliminary score as the final routing layer.
- Keep routing logic outside this package until the scoring-to-weighting phase is explicitly opened.
