# A4/B4 note

## Feature block
- A3 base retained:
  - `log_edge_length_m`
  - `analysis_year_offset`
  - `hour_sin`
  - `hour_cos`
  - `is_weekend_int`
  - `log1p_edge_accident_count_prior_total`
  - `log1p_edge_bin_accident_count_prior`
  - `log1p_edge_accident_count_prior_recent_3y`
  - `log1p_edge_bin_accident_count_prior_recent_3y`
  - `prior_dynamic_context_signal_recent_3y_imputed`
  - `log1p_prior_context_observation_n_recent_3y`
  - `prior_dynamic_context_recent_missing_flag`
  - `ctx_recent_fallback_edge_bin_weekend`
  - `ctx_recent_fallback_edge_bin`
  - `ctx_recent_fallback_global_bin_weekend`
- Exogenous block added in A4/B4:
  - `exog_road_class_is_major_flag`
  - `exog_maxspeed_kph_imputed_by_road_class`
  - `exog_maxspeed_missing_flag`
  - `exog_oneway_code_b_flag`
  - `exog_tunnel_flag`
  - `exog_node_degree_mean`
  - `exog_edge_touches_dead_end_flag`
  - `exog_distance_from_network_centroid_km`
  - `exog_temporal_is_night_flag`
  - `exog_temporal_is_weekday_peak_flag`
- Left out on purpose:
  - `exog_road_class_hierarchy_score`: excluded_due_to_high_redundancy_with_maxspeed_imputed_and_major_road_flag.
  - `exog_road_class_is_local_flag`: excluded_due_to_redundancy_with_major_road_flag_and_existing_history_block.
  - `exog_road_class_is_link_flag`: excluded_for_prudence_because_it_is_sparse_relative_to_major_road_flag.
  - `exog_maxspeed_kph`: excluded_because_raw_maxspeed_has_50.9pct_missing_and_imputed_version_is_already_available.
  - `exog_oneway_code_t_flag`: excluded_because_it_is_too_sparse_to_stabilize_a_clean_baseline.
  - `exog_bridge_flag`: excluded_due_to_sparse_overlap_with_tunnel_and_vertical_structure_flags.
  - `exog_layer_abs`: excluded_due_to_overlap_with_tunnel_and_low_nonzero_support.
  - `exog_nonzero_layer_flag`: excluded_due_to_overlap_with_tunnel_and_low_nonzero_support.
  - `exog_from_node_degree`: excluded_due_to_redundancy_with_node_degree_mean.
  - `exog_to_node_degree`: excluded_due_to_redundancy_with_node_degree_mean.
  - `exog_node_degree_max`: excluded_due_to_redundancy_with_node_degree_mean.
  - `exog_node_degree_min`: excluded_due_to_redundancy_with_node_degree_mean_and_dead_end_flag.
  - `exog_edge_touches_intersection_flag`: excluded_due_to_redundancy_with_node_degree_mean.
  - `exog_edge_between_intersections_flag`: excluded_due_to_redundancy_with_node_degree_mean.
  - `exog_orientation_sin`: excluded_for_prudence_because_distance_from_network_centroid_showed stronger standalone signal.
  - `exog_orientation_cos`: excluded_for_prudence_because_distance_from_network_centroid_showed stronger standalone signal.
  - `exog_temporal_is_peak_commute_flag`: excluded_due_to_redundancy_with_weekday_peak_and_existing_hour_sin_hour_cos.
  - `exog_temporal_is_weekend_night_flag`: excluded_due_to_redundancy_with_night_flag_and_existing_is_weekend.
  - `exog_has_road_ref_flag`: excluded_for_prudence_to_keep_the_static_block_short.
  - `exog_has_street_name_flag`: excluded_for_prudence_to_keep_the_static_block_short.
  - `exog_source_way_segment_count`: excluded_for_prudence_to_avoid_expanding_the_geometric_block_without_clear_extra_signal.
  - `exog_source_way_total_length_m`: excluded_due_to_redundancy_with_edge_length_and_way_segment_count.
  - `exog_source_way_mean_segment_length_m`: excluded_for_prudence_to_keep_the_static_block_short.

## A4 vs B4
- Validation winner: `Negative Binomial`.
- Test winner: `Negative Binomial`.
- A4 validation deviance / MAE / RMSE: `0.226588` / `0.062315` / `0.203023`.
- B4 validation deviance / MAE / RMSE: `0.225583` / `0.063233` / `0.202981`.
- A4 test deviance / MAE / RMSE: `0.289239` / `0.072537` / `0.235738`.
- B4 test deviance / MAE / RMSE: `0.286072` / `0.073534` / `0.235519`.

## Improvement vs A3/B3
- Validation improvement vs previous A3/B3: `marginal`.
- Test improvement vs previous A3/B3: `marginal`.
- Best old validation deviance / MAE / RMSE: `0.231782` / `0.064360` / `0.203539`.
- Best new validation deviance / MAE / RMSE: `0.225583` / `0.063233` / `0.202981`.
- Best old test deviance / MAE / RMSE: `0.292406` / `0.074995` / `0.236308`.
- Best new test deviance / MAE / RMSE: `0.286072` / `0.073534` / `0.235519`.

## Positive vs zero observations
- Positive observations deviance improvement labels: poisson_a3->poisson_a4 validation=marginal, poisson_a3->poisson_a4 test=marginal, negative_binomial_b3->negative_binomial_b4 validation=marginal, negative_binomial_b3->negative_binomial_b4 test=marginal.
- Zero observations deviance improvement labels: poisson_a3->poisson_a4 validation=marginal, poisson_a3->poisson_a4 test=material, negative_binomial_b3->negative_binomial_b4 validation=marginal, negative_binomial_b3->negative_binomial_b4 test=material.

## Exogenous block reading
- Contextual fallback omitted baseline `road_class_bin_weekend` still represents `90.60%` of train rows.
- The exogenous block therefore acts as a complement to a contextual block still dominated by road-class/bin/weekend fallback.
- Strongest exogenous group by Poisson standardized-effect sum: `geometry`.
- Strongest exogenous group by NB standardized-effect sum: `geometry`.
- Poisson A4 top exogenous coefficients:
  - `exog_temporal_is_night_flag`: coef `0.843041`, exp(coef) `2.323421`.
  - `exog_temporal_is_weekday_peak_flag`: coef `0.460334`, exp(coef) `1.584603`.
  - `exog_edge_touches_dead_end_flag`: coef `0.332540`, exp(coef) `1.394506`.
  - `exog_tunnel_flag`: coef `0.216347`, exp(coef) `1.241534`.
  - `exog_node_degree_mean`: coef `0.155181`, exp(coef) `1.167870`.
- Negative Binomial B4 top exogenous coefficients:
  - `exog_temporal_is_night_flag`: coef `0.845471`, exp(coef) `2.329074`.
  - `exog_temporal_is_weekday_peak_flag`: coef `0.476783`, exp(coef) `1.610883`.
  - `exog_edge_touches_dead_end_flag`: coef `0.288647`, exp(coef) `1.334621`.
  - `exog_tunnel_flag`: coef `0.210935`, exp(coef) `1.234832`.
  - `exog_node_degree_mean`: coef `0.173461`, exp(coef) `1.189414`.

## Guardrails
- A4/B4 do not change target, split or project strategy.
- These remain count-model baselines, not routing weights.
- Full-period accident-backed references remain outside the predictor block.
