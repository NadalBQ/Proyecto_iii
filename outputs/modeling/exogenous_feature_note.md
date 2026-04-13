# Exogenous Feature Note

## Scope
This phase enriches `training_table_with_contextual_lag_safe_features.parquet` with richer exogenous features.
It does not change:
- target: `accident_count`
- split: train 2016-2022 / validation 2023 / test 2024
- routing logic
- final edge weighting

## Usable now
- Canonical edge attributes from M8.
- Canonical node topology from M8.
- Deterministic panel calendar features already present in the modeling unit.

## Usable with processing
- Auxiliary OSM layers from the Geofabrik extract: traffic controls, buildings, land use, POIs, transport and related static layers.
- These require a geospatial preprocessing stack and spatial joins not currently available in this Python environment.

## Not usable now
- Municipal traffic tramo CSV remains non-interoperable with the canonical network under current evidence from M11.
- No standalone leak-safe weather feed exists in the repo.
- Communications cartography and DGT catalog metadata are not direct modeling context sources.

## Unsafe due to leakage
- M11 exposure outputs and M12 dynamic/contextual outputs are accident-backed and cannot be used as direct exogenous predictors.

## Built feature block
- Features with >=99% coverage: exog_bridge_flag, exog_distance_from_network_centroid_km, exog_edge_between_intersections_flag, exog_edge_touches_dead_end_flag, exog_edge_touches_intersection_flag, exog_from_node_degree, exog_has_road_ref_flag, exog_has_street_name_flag, exog_layer_abs, exog_maxspeed_ge70_flag, exog_maxspeed_kph_imputed_by_road_class, exog_maxspeed_le30_flag, exog_maxspeed_missing_flag, exog_node_degree_max, exog_node_degree_mean, exog_node_degree_min, exog_nonzero_layer_flag, exog_oneway_code_b_flag, exog_oneway_code_t_flag, exog_orientation_cos, exog_orientation_sin, exog_road_class_hierarchy_score, exog_road_class_is_link_flag, exog_road_class_is_local_flag, exog_road_class_is_major_flag, exog_source_way_mean_segment_length_m, exog_source_way_segment_count, exog_source_way_total_length_m, exog_to_node_degree, exog_tunnel_flag, exog_temporal_is_night_flag, exog_temporal_is_peak_commute_flag, exog_temporal_is_weekday_peak_flag, exog_temporal_is_weekend_night_flag
- Features with partial but still high coverage: none
- Features with low coverage: exog_maxspeed_kph

## Interpretation
This block is genuinely exogenous and materially richer than the previous accident-backed contextual fallback alone.
It is enough to justify a next baseline iteration, especially to test whether static/topological edge context adds value beyond pure history.
However, it still does not solve the absence of operational dynamic exogenous feeds such as aligned traffic or weather data.
