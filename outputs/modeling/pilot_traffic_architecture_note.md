# Pilot Traffic Architecture Note

## Scope
- This is an architectural consolidation only.
- It does not retrain models.
- It does not promote the pilot 2024 traffic branch to the global default pipeline.

## Surviving pilot traffic block
- Feature block name: `pilot_traffic_d_transformed`.
- Active block columns:
  - `traffic_covered_flag`
  - `traffic_missing_due_to_no_time_flag`
  - `traffic_intensidad_wins_log`
  - `traffic_ocupacion_wins`
  - `log1p_traffic_support_n`
  - `log1p_traffic_n_observations`
- Explicitly excluded from the main pilot block:
  - `traffic_vmed_mean`

## Global vs pilot separation
- `global_default_model` stays default and keeps the pilot traffic block disabled.
- `pilot_traffic_model` is an explicit opt-in branch for the pilot scope only.
- Pilot scope restriction: `analysis_year = 2024` and `month in (1, 4, 7, 10)`.

## Gating behavior
- The pilot traffic block is never auto-enabled inside the global branch.
- If the pilot branch is requested and pilot-only preconditions fail, the pipeline must abort with a clear message.
- Silent fallback from requested pilot traffic to global no-traffic is not allowed.

## Current validation status
- Raw pilot training table rules passed: `4/4`.
- Transformed pilot input rules passed: `5/5`.
- Current architecture audit: all gating rules pass on the existing pilot artifacts.

## Where the block lives
- Contract and gating constants live in `modeling/pilot_traffic_block.py`.
- Pilot input builder lives in `modeling/build_pilot_traffic_input.py`.
- Pilot training script lives in `modeling/train_pilot_traffic_baselines.py`.
- Architecture audit lives in `modeling/build_pilot_traffic_architecture.py`.

## Future integration boundary
- This prepares coexistence between the global branch and the pilot traffic branch.
- It does not make traffic globally available across 2016-2024.
- A deeper integration would require broader traffic coverage and a new leakage audit before promoting any traffic block beyond the pilot branch.
