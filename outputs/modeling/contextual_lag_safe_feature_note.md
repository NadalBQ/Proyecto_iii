# Contextual Leak-Safe Feature Note

## Scope
This phase adds leak-safe contextual features on top of `training_table_with_lag_safe_features.parquet`.
It does not change:
- target: `accident_count`
- split: train 2016-2022 / validation 2023 / test 2024
- routing logic
- final edge weighting

## Rebuild strategy
Contextual signals were rebuilt from matched accidents plus accident-level context using only information from years strictly earlier than each row `analysis_year`.

Fallback hierarchy:
1. `edge_id + temporal_bin_4h + is_weekend`
2. `edge_id + temporal_bin_4h`
3. `road_class + temporal_bin_4h + is_weekend`
4. `global + temporal_bin_4h + is_weekend`

## M11 / M12 audit
- M12 `intensidad_context`, `ocupacion_context`, `dynamic_context_signal_prelim` and `context_observation_n` are reconstructable as leak-safe lagged features and were rebuilt here.
- M11 `historical_exposure_adjusted_score_prelim` and `exposure_proxy_value` were not rebuilt here because that would require cutoff-specific recomputation of the accident-backed exposure crosswalk/proxy.

## Diagnostics
- matched accidents available: 134565
- matched accidents with valid panel context: 134565
- matched accidents dropped for invalid panel fields: 0
- matched accidents with intensity: 109820
- matched accidents with occupacion: 109746
- matched accidents with joint context: 109746

## Usability
- usable now: prior_context_observation_n, prior_context_observation_n_recent_3y, prior_mean_intensity_context, prior_mean_occupacion_context, prior_mean_intensity_context_recent_3y, prior_mean_occupacion_context_recent_3y, prior_dynamic_context_signal, prior_dynamic_context_signal_recent_3y
- usable with caution: none
- limited for now: none

## Interpretation
This new block is leak-safe and technically suitable for an A3/B3 iteration.
However, it is still accident-backed context, not exogenous real-time context. A3/B3 is now methodologically worth testing, but it will not remove the need for future exogenous contextual feeds if ROAD-SAFETY wants a truly operational dynamic layer.
