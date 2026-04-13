# Negative Binomial baseline note

## Scope
- Target: `accident_count`.
- Split: train `2016-2022`, validation `2023`, test `2024`.
- Features: exactly the same `model_safe` transformed predictors as Poisson baseline A.
- This baseline is not a routing weight and not a final graph cost.

## Fitting method
- Method used: `statsmodels.discrete.NegativeBinomial_mle`.
- Estimated alpha: `1.104821`.

## Validation/Test performance
- Validation mean Poisson deviance / MAE / RMSE: `0.231987` / `0.063322` / `0.204185`.
- Validation Pearson dispersion: `1.422053`.
- Test mean Poisson deviance / MAE / RMSE: `0.293858` / `0.073355` / `0.236867`.
- Test Pearson dispersion: `2.042995`.

## Coefficient readout
- Strongest positive coefficients:
  - `log1p_edge_accident_count_prior_total`: coef `0.615672`, exp(coef) `1.850900`.
  - `log1p_edge_bin_accident_count_prior`: coef `0.321823`, exp(coef) `1.379641`.
  - `log_edge_length_m`: coef `0.063464`, exp(coef) `1.065521`.
- Strongest negative coefficients:
  - `is_weekend_int`: coef `-1.150271`, exp(coef) `0.316551`.
  - `hour_sin`: coef `-0.532375`, exp(coef) `0.587209`.
  - `hour_cos`: coef `-0.372536`, exp(coef) `0.688985`.

## Interpretation guardrails
- The comparison against Poisson A is clean because target, table, split and features are unchanged.
- Negative Binomial is still only a count-model baseline; it does not produce a routing weight and does not change the project strategy by itself.
