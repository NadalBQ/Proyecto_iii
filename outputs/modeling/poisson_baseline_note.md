# Poisson baseline note

## Scope
- Target: `accident_count`.
- Split: train `2016-2022`, validation `2023`, test `2024`.
- Features: only `model_safe` transformed predictors.
- Explicitly excluded from this first baseline: `reference_only` columns and `edge_years_observed_prior`.
- This baseline is not a routing weight and not a final graph cost.

## Zero-only controls
- The corrected training table adds stratified zero-only control edges sampled by `road_class x edge_length_bin`.
- Control support windows are inherited from positive-history edges in the same stratum to avoid fabricating a full-network all-years panel.

## Train diagnostics
- Train rows: `2385168`.
- Train zero pct: `96.40%`.
- Train target mean/variance: `0.0392` / `0.0532`.
- Train Pearson dispersion: `1.1058`.
- Over-dispersion threshold `1.5` exceeded: `False`.

## Validation/Test performance
- Validation mean Poisson deviance / MAE / RMSE: `0.232470` / `0.062769` / `0.204262`.
- Test mean Poisson deviance / MAE / RMSE: `0.295414` / `0.072730` / `0.236862`.

## Coefficient readout
- Strongest positive coefficients:
  - `log1p_edge_accident_count_prior_total`: coef `0.623529`, exp(coef) `1.865500`.
  - `log1p_edge_bin_accident_count_prior`: coef `0.370810`, exp(coef) `1.448908`.
  - `log_edge_length_m`: coef `0.056340`, exp(coef) `1.057957`.
- Strongest negative coefficients:
  - `is_weekend_int`: coef `-1.147099`, exp(coef) `0.317557`.
  - `hour_sin`: coef `-0.524745`, exp(coef) `0.591706`.
  - `hour_cos`: coef `-0.371081`, exp(coef) `0.689988`.

## Interpretation guardrails
- Signs and magnitudes are baseline associations under a log-link count model, not causal claims.
- `historical_exposure_adjusted_score_prelim` and `dynamic_context_signal_prelim` stay out of this first model as predictors because they are not `model_safe` for temporal validation.
