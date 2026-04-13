# ROAD-SAFETY Modeling Environment

## Scope
This folder contains the Python-side modeling pipeline used after the R preparation phases.

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

## Typical commands
Build the latest modeling tables:
```powershell
python modeling\build_training_table.py --force
python modeling\build_training_table_with_controls.py --force
python modeling\build_lag_safe_features.py --force
python modeling\build_contextual_lag_safe_features.py --force
python modeling\build_exogenous_context_features.py --force
```

Train the current baseline family comparisons:
```powershell
python modeling\train_baseline.py --force
python modeling\train_negative_binomial.py --force
python modeling\train_lag_safe_baselines.py --force
python modeling\train_contextual_baselines.py --force
python modeling\train_exogenous_baselines.py --force
```

Build the current global preliminary scoring output:
```powershell
python modeling\score_global_model.py --force
```

Audit the next dynamic-exogenous phase:
```powershell
python modeling\build_dynamic_exogenous_context_audit.py --force
```

Build and audit the pilot 2024 traffic branch:
```powershell
python modeling\build_pilot_traffic_input.py --force
python modeling\build_pilot_traffic_architecture.py --force
```

Train the already-defined pilot 2024 traffic comparison:
```powershell
python modeling\train_pilot_traffic_baselines.py --force
```

## Global vs pilot traffic branch
- `global_default_model` remains the default branch and does not auto-enable pilot traffic.
- `pilot_traffic_model` is a separate opt-in branch restricted to `analysis_year = 2024` and months `1,4,7,10`.
- The live pilot traffic block is `traffic_D_transformed`.
- Main pilot traffic contract:
  - `traffic_covered_flag`
  - `traffic_missing_due_to_no_time_flag`
  - `traffic_intensidad_wins_log`
  - `traffic_ocupacion_wins`
  - `log1p_traffic_support_n`
  - `log1p_traffic_n_observations`
- `traffic_vmed_mean` stays outside the main pilot traffic contract.
- If the pilot traffic branch is requested and its scope/column preconditions fail, the pipeline should abort with a clear message instead of silently falling back.

## Global scoring branch
- The current global scoring branch reuses the selected global baseline instead of retraining inside scoring.
- The scoring unit is `edge_id + analysis_year + temporal_bin_4h + is_weekend`.
- The current selected global baseline should be checked in `outputs/modeling/global_model_branch_summary.csv`.
- `predicted_risk_score_prelim` is a capped preliminary score for system integration, not a final edge-weight or routing cost.

## Guardrails
- Do not treat full-period accident-backed outputs as direct exogenous predictors.
- Do not change target or split silently.
- Keep routing logic out of this package until the risk-modeling phase is explicitly closed.
- Do not treat the pilot 2024 traffic branch as global traffic coverage for 2016-2024.
