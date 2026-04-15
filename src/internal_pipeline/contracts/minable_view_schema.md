# Minable View Schema

The final published parquet is:

- `artifacts/training_table_with_exogenous_context_features.parquet`

The internal builders produce it first at:

- `src/internal_pipeline/.workspace/outputs/modeling/training_table_with_exogenous_context_features.parquet`

At minimum, the final parquet must satisfy the schema required by the final
model artifact:

- panel identifiers: `edge_id`, `analysis_year`, `temporal_bin_4h`, `is_weekend`
- target: `accident_count`
- base geometry/context: `edge_length_m`, `hour_sin`, `hour_cos`
- lag-safe history block:
  - `edge_accident_count_prior_total`
  - `edge_bin_accident_count_prior`
  - `edge_accident_count_prior_recent_3y`
  - `edge_bin_accident_count_prior_recent_3y`
- contextual lag-safe block:
  - `prior_dynamic_context_signal_recent_3y`
  - `prior_context_observation_n_recent_3y`
  - `prior_dynamic_context_signal_recent_3y_missing_flag`
  - `prior_dynamic_context_signal_recent_3y_fallback_level`
- exogenous block:
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
