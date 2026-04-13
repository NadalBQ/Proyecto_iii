# Dynamic Exogenous Feature Note

## Scope
- This phase hardens the Python environment and audits true dynamic exogenous context readiness.
- It does not train A5/B5.
- It does not change target, split or the current B4 baseline.

## Environment status
- Modeling dependencies are now pinned in `modeling/requirements.txt`.
- Minimal execution instructions are documented in `modeling/README.md`.

## Source classification
- usable_now_dynamic_exogenous: deterministic_panel_calendar
- usable_with_processing: geofabrik_osm_traffic_layers
- not_usable_now: municipal_traffic_tramos_csv, standalone_weather_feed, event_calendar_feed
- unsafe_due_to_leakage: m11_edge_sensor_crosswalk, m11_historical_exposure_adjusted, m12_edge_context_dynamic_base

## Practical reading
- The only temporal context currently usable now is the deterministic calendar already integrated in the modeling tables.
- There is no new richer true dynamic exogenous source in the repo that is both edge-ready and leak-safe.
- The municipal `temps-real` CSV is not usable now: its coordinates point to Valencia-area geometry, it has no usable historical series in-repo, and M11 already showed zero tramo-edge links against the canonical Madrid network.
- OSM `gis_osm_traffic*.shp` layers are useful only as static auxiliary traffic-control context, not as true dynamic feeds.
- Weather and event feeds are simply absent from the repository.

## Leak-safe integration design for future A5/B5
- Modeling unit should stay `edge_id + analysis_year + temporal_bin_4h + is_weekend` for comparability with A/B through A4/B4.
- Raw ingestion unit for true dynamic context should be `source_observation_id + observation_timestamp + source_location/source_geometry`.
- Any future dynamic source must first be aligned to the canonical network or to a documented intermediate unit with a versioned crosswalk.
- For a row with `analysis_year = Y`, every dynamic feature must aggregate only observations with timestamps `< Y-01-01`.
- Recommended windows: prior 1y, recent 90d/180d, and support counts, always with explicit missing/support flags and fallback levels.
- Recommended fallback hierarchy once a real feed exists: `edge_id + temporal_bin_4h + is_weekend` -> `edge_id + temporal_bin_4h` -> `road_class + temporal_bin_4h + is_weekend` -> `global + temporal_bin_4h + is_weekend`.

## Why no new parquet was created
- A new `training_table_with_true_dynamic_exogenous_features.parquet` was intentionally not created.
- There is no source in the repo today that would let us build true dynamic exogenous features without inventing data or reusing accident-backed outputs.

## Best next step
- Prepare external ingestion of a real Madrid traffic feed with timestamp history and stable geometry or sensor metadata.
- If traffic ingestion is not immediately available, the next-best exogenous stream is weather, but it is also absent today.

## Candidate future feature families
- `prior_mean_real_traffic_state_edge_bin_1y` from `traffic`: missing historical traffic feed and edge crosswalk.
- `prior_mean_real_traffic_state_edge_bin_recent_90d` from `traffic`: missing timestamped traffic history.
- `prior_weather_precipitation_edge_bin_1y` from `weather`: missing weather feed and spatial interpolation layer.
- `prior_event_intensity_edge_bin_1y` from `calendar`: missing event source.

## Guardrails
- `m11_*` and `m12_*` outputs remain references or blueprints, not direct exogenous predictors.
- This phase closes environment + dynamic-exogenous readiness, not model training and not routing.
