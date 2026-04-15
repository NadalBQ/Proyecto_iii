# Upstream Outputs

The upstream R stage must leave these files in the compatibility workspace:

- `src/internal_pipeline/.workspace/outputs/data/accidentes_tabla_accidente_master.csv`
- `src/internal_pipeline/.workspace/outputs/data/m8_road_network_edges.csv`
- `src/internal_pipeline/.workspace/outputs/data/m9_accident_edge_matches.csv`
- `src/internal_pipeline/.workspace/outputs/data/m10_edge_historical_aggregation.csv`
- `src/internal_pipeline/.workspace/outputs/data/m11_historical_exposure_adjusted.csv`
- `src/internal_pipeline/.workspace/outputs/data/m12_edge_context_dynamic_base.csv`

Those six outputs are the minimal bridge between:

- upstream R preprocessing
- Python builders that materialize the final minable view
