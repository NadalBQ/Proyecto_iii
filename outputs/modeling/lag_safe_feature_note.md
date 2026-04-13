# Lag-safe feature note

## Scope
- Target unchanged: `accident_count`.
- Split unchanged: train `2016-2022`, validation `2023`, test `2024`.
- Base table unchanged: `training_table_with_controls.parquet` is the source; this phase only adds new lag-safe features in a derived artifact.

## What was added
- New lag-safe contextual/history features built only from information prior to each observation:
  - `edge_accident_count_prior_1y`
  - `edge_accident_count_prior_2y`
  - `edge_accident_count_prior_change_1y`
  - `edge_accident_count_prior_recent_3y`
  - `edge_active_years_prior_recent_3y`
  - `edge_bin_accident_count_prior_1y`
  - `edge_bin_accident_count_prior_2y`
  - `edge_bin_accident_count_prior_change_1y`
  - `edge_bin_accident_count_prior_recent_3y`
  - `edge_bin_active_years_prior_recent_3y`
  - `edge_bin_recent_activity_flag`
  - `edge_bin_share_of_edge_prior_recent_3y`
  - `edge_bin_years_since_last_accident`
  - `edge_years_since_last_accident`
  - `recent_activity_flag`

## Why M11/M12 full-period columns stay out
- Full-period M10/M11/M12 reference columns remain out of direct modeling because they summarize information across years and would leak future information into earlier observations.
- They are preserved only as `reference_only` or `potentially_rebuildable_as_lagged` audit columns.

## Potentially rebuildable later
  - `accidents_per_km_full_period_reference`
  - `accidents_per_km_raw_full_period_reference`
  - `context_data_quality_flag_full_period_reference`
  - `context_observation_n_full_period_reference`
  - `dynamic_context_signal_prelim_full_period_reference`
  - `edge_years_observed_prior`
  - `exposure_proxy_value_full_period_reference`
  - `exposure_quality_flag_full_period_reference`
  - `historical_count_raw_full_period_reference`
  - `historical_count_weighted_full_period_reference`
  - `historical_exposure_adjusted_score_prelim_full_period_reference`
  - `historical_score_prelim_full_period_reference`
  - `intensidad_context_full_period_reference`
  - `ocupacion_context_full_period_reference`

## Unsafe due to leakage now
  - `context_reference_available`
  - `reference_feature_warning`

## Highest missingness among new features
  - `edge_bin_years_since_last_accident`: missing `95.03%`, non-missing `4.97%`.
  - `edge_years_since_last_accident`: missing `70.23%`, non-missing `29.77%`.
  - `edge_accident_count_prior_1y`: missing `0.00%`, non-missing `100.00%`.
  - `edge_bin_accident_count_prior_1y`: missing `0.00%`, non-missing `100.00%`.
  - `edge_accident_count_prior_2y`: missing `0.00%`, non-missing `100.00%`.

## Methodological guardrails
- These new features are still history-derived, not exogenous real-time context feeds.
- No full-period accident-backed contextual aggregate enters as a predictor in this phase.
- This phase does not train a new model and does not change routing logic.
