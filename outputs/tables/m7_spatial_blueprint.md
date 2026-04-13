# M7 - Blueprint historico-espacial ROAD-SAFETY

## 1. Que falta para pasar del indice conceptual al routing real
- Hace falta una red viaria routable canonica a nivel edge/node.
- Hace falta armonizar CRS entre accidentes y capas lineales antes de cualquier matching real.
- Hace falta asignar accidente -> edge con trazabilidad de calidad, no con joins debiles por sensor o tramo.
- Hace falta agregar evidencia historica por edge y ventana temporal.
- Hace falta un denominador o proxy de exposicion antes de tratar el recuento historico como riesgo operativo.
- Hace falta mantener separado el bloque historico_espacial del baseline/contextual y del futuro coste final de routing.

## 2. Unidad espacial baseline recomendada
- Unidad recomendada: `routable_graph_edge`.
- Justificacion: This is the correct baseline spatial unit for ROAD-SAFETY because routing operates over graph edges, not over raw accident points or sensor proxies.
- Limite de las alternativas intermedias: Requires a canonical drivable road network plus accident-to-edge assignment before any historical score can be computed.

## 3. Inputs existentes y faltantes
- Accidentes listos para preparacion espacial: Accident master keeps 146,747 coordinate-ready accidents and 146,872 sensor-linked accidents. Confirm CRS before matching.
- Capa lineal disponible ahora: Source has 378 rows, 378 unique tramo ids and 378 non-missing LineString geometries. Useful as overlay/bridge, not as final routable edge layer.
- Inputs futuros obligatorios para map-matching y score por edge:
- `road_network_edges` -> `bases de datos/network/road_network_edges.geojson`
- `road_network_nodes` -> `bases de datos/network/road_network_nodes.geojson`
- `tramo_sensor_to_edge_crosswalk` -> `bases de datos/crosswalks/tramo_sensor_to_edge_crosswalk.csv`
- `edge_exposure_baseline` -> `bases de datos/exposure/edge_exposure_baseline.csv`

## 4. Pipeline espacial propuesto
- 1. `prepare_accidents_geolocalized` -> ready_now. Build the spatially ready accident point layer from accident_master and keep unmatched or zero-coordinate cases explicit.
- 2. `prepare_road_network` -> blocked_missing_network. Create the canonical drivable edge/node layers that will become the routing graph backbone.
- 3. `assign_accident_to_edge` -> blocked_missing_network. Snap or match each accident point to the canonical graph edge, keeping distance/error diagnostics.
- 4. `aggregate_historical_by_edge` -> blocked_upstream. Aggregate matched accidents by edge and time window to build historical counts and severity summaries.
- 5. `adjust_by_exposure` -> blocked_missing_exposure. Join denominator or exposure proxies to avoid treating raw counts as final risk.
- 6. `build_preliminary_historical_edge_score` -> blueprint_only. Combine historical frequency, severity and optional smoothing into a preliminary edge-level historical block.

## 5. Salidas intermedias a guardar
- `m7_existing_spatial_sources_summary.csv` -> `outputs/data/m7_existing_spatial_sources_summary.csv`
- `m7_accidents_spatial_ready.csv` -> `outputs/data/m7_accidents_spatial_ready.csv`
- `m7_network_edges_clean.geojson` -> `outputs/data/m7_network_edges_clean.geojson`
- `m7_network_nodes_clean.geojson` -> `outputs/data/m7_network_nodes_clean.geojson`
- `m7_accident_edge_matches.csv` -> `outputs/data/m7_accident_edge_matches.csv`
- `m7_edge_history_annual.csv` -> `outputs/data/m7_edge_history_annual.csv`
- `m7_edge_history_exposure_adjusted.csv` -> `outputs/data/m7_edge_history_exposure_adjusted.csv`
- `m7_edge_historical_score.csv` -> `outputs/data/m7_edge_historical_score.csv`

## 6. Separacion de capas
- `score_baseline` y moduladores contextuales siguen fuera de este bloque.
- `bloque_historico_espacial` debe nacer despues del matching y la agregacion por edge.
- `peso_operativo_final_de_routing` sigue fuera de M7 y no debe inferirse todavia.

