# A3/B3 note

## Feature block
- Historical base kept from A2/B2:
  - `log_edge_length_m`
  - `analysis_year_offset`
  - `hour_sin`
  - `hour_cos`
  - `is_weekend_int`
  - `log1p_edge_accident_count_prior_total`
  - `log1p_edge_bin_accident_count_prior`
  - `log1p_edge_accident_count_prior_recent_3y`
  - `log1p_edge_bin_accident_count_prior_recent_3y`
- Contextual block added in A3/B3:
  - `prior_dynamic_context_signal_recent_3y_imputed`
  - `log1p_prior_context_observation_n_recent_3y`
  - `prior_dynamic_context_recent_missing_flag`
  - `ctx_recent_fallback_edge_bin_weekend`
  - `ctx_recent_fallback_edge_bin`
  - `ctx_recent_fallback_global_bin_weekend`
- Left out on purpose:
  - `prior_dynamic_context_signal`: excluded_due_to_high_redundancy_with_recent_3y_dynamic_signal.
  - `prior_context_observation_n`: excluded_due_to_high_redundancy_with_recent_3y_context_support.
  - `prior_mean_intensity_context`: excluded_because_dynamic_context_signal_already_summarizes_intensity_and_occupacion.
  - `prior_mean_occupacion_context`: excluded_because_dynamic_context_signal_already_summarizes_intensity_and_occupacion.
  - `prior_mean_intensity_context_recent_3y`: excluded_because_recent_dynamic_signal_already_summarizes_intensity_and_occupacion.
  - `prior_mean_occupacion_context_recent_3y`: excluded_because_recent_dynamic_signal_already_summarizes_intensity_and_occupacion.
  - `prior_dynamic_context_signal_recent_3y_fallback_level`: encoded_as_dummies_with_road_class_bin_weekend_as_omitted_baseline.
  - `prior_context_observation_n_recent_3y_missing_flag`: excluded_because_support_zero_is_already_encoded_by_log1p_support_and_missing_flag_on_dynamic_signal.

## A3 vs B3
- Validation winner: `Poisson`.
- Test winner: `Poisson`.
- A3 validation deviance / MAE / RMSE: `0.232298` / `0.063810` / `0.203509`.
- B3 validation deviance / MAE / RMSE: `0.231782` / `0.064360` / `0.203539`.
- A3 test deviance / MAE / RMSE: `0.294090` / `0.074401` / `0.236288`.
- B3 test deviance / MAE / RMSE: `0.292406` / `0.074995` / `0.236308`.

## Improvement vs A2/B2
- Validation improvement vs previous A2/B2: `marginal`.
- Test improvement vs previous A2/B2: `marginal`.
- Best old validation deviance / MAE / RMSE: `0.233456` / `0.062647` / `0.203982`.
- Best new validation deviance / MAE / RMSE: `0.231782` / `0.064360` / `0.203539`.
- Best old test deviance / MAE / RMSE: `0.298568` / `0.072900` / `0.237465`.
- Best new test deviance / MAE / RMSE: `0.292406` / `0.074995` / `0.236308`.

## Positive vs zero observations
- Positive observations deviance improvement labels: poisson_a2->poisson_a3 validation=marginal, poisson_a2->poisson_a3 test=marginal, negative_binomial_b2->negative_binomial_b3 validation=marginal, negative_binomial_b2->negative_binomial_b3 test=marginal.
- Zero observations deviance improvement labels: poisson_a2->poisson_a3 validation=none, poisson_a2->poisson_a3 test=none, negative_binomial_b2->negative_binomial_b3 validation=none, negative_binomial_b2->negative_binomial_b3 test=none.

## Contextual signal reading
- Train fallback share at omitted baseline `road_class_bin_weekend`: `90.60%`.
- Train unresolved contextual share: `3.63%`.
- This means most of the contextual block is still inherited from road-class/bin/weekend support rather than fine edge-specific support.

## Strongest contextual coefficient signals
- Poisson A3:
  - `prior_dynamic_context_recent_missing_flag`: coef `0.585223`, exp(coef) `1.795391`.
  - `ctx_recent_fallback_edge_bin_weekend`: coef `-0.113588`, exp(coef) `0.892626`.
  - `ctx_recent_fallback_global_bin_weekend`: coef `0.031166`, exp(coef) `1.031656`.
  - `ctx_recent_fallback_edge_bin`: coef `0.029302`, exp(coef) `1.029736`.
- Negative Binomial B3:
  - `prior_dynamic_context_recent_missing_flag`: coef `0.557480`, exp(coef) `1.746266`.
  - `ctx_recent_fallback_global_bin_weekend`: coef `0.290480`, exp(coef) `1.337069`.
  - `ctx_recent_fallback_edge_bin_weekend`: coef `-0.075600`, exp(coef) `0.927187`.
  - `log1p_prior_context_observation_n_recent_3y`: coef `-0.001838`, exp(coef) `0.998164`.

## Guardrails
- A3/B3 do not change target, split or general project strategy.
- These are still count-model baselines, not routing weights.
- Full-period accident-backed references remain out of the predictor set.
