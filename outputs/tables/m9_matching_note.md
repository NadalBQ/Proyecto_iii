# M9 - Matching real accidente -> edge

## Metodo
- Matching geometrico puro contra la red canonica de M8 en `EPSG:25830`.
- Radio inicial de busqueda: `30m`.
- Regla de seleccion: `nearest_edge_projected_within_radius`.
- Desempate: distancia minima; si hay varios candidatos dentro de `1m` del minimo, se resuelve de forma determinista por `edge_length_m` y luego `edge_id`, y se degrada la calidad.
- Schema final adoptado: `m9_schema_v1_edge_id_projected_point_geometry_binary_match_status`.
- `edge_id` es la arista canonica seleccionada.
- `projected_point_geometry` se guarda como WKT en CSV; el GeoJSON lleva la geometria proyectada real.
- `match_status` se mantiene binario (`matched` / `unmatched`); la ambiguedad se refleja solo en `quality_flag` y en las columnas de trazabilidad.

## Umbrales de calidad
- `high_confidence`: distancia <= 10m y un solo candidato.
- `medium_confidence`: distancia <= 20m y hasta 3 candidatos.
- `low_confidence`: match dentro del radio pero mas ambiguo o mas lejano.
- `unmatched`: coordenadas invalidas, fuera del envelope operativo o sin edge candidato dentro del radio.

## Cobertura observada
- Accidentes validos para matching: 146747
- Accidentes dentro del envelope operativo: 138912
- Matched: 134565 (91.70% sobre coordenadas validas)
- Unmatched: 12318
- Accidentes fuera del envelope operativo: 7835
- Distribucion resumida de distancia: p50=2.370m, p95=14.821m
- Los accidentes fuera del envelope operativo se guardan tambien en `m9_outside_operational_envelope_accidents.csv` con el edge canonico mas cercano solo como referencia diagnostica.

## Que no hace M9
- No calcula todavia score final por edge.
- No implementa routing.
- No usa joins ingenuos por `id_sensor_cercano` ni por `Id. Tram`.

