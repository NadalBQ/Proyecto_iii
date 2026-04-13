# M10 - Agregacion historica preliminar por edge

## Logica de M10
- M10 agrega solo accidentes `matched` de M9 sobre la red canonica de M8.
- Se mantienen separados tres niveles de informacion:
  - `accident_count_raw`: conteo historico sin ponderar de accidentes asignados al edge.
  - `accident_count_weighted_by_quality`: conteo historico ponderado por calidad de matching.
  - `historical_score_prelim`: transformacion monotona de la densidad historica ponderada, util para ranking preliminar pero no para routing final.

## Regla de ponderacion por quality_flag
- `high_confidence = 1.00`
- `medium_confidence = 0.75`
- `low_confidence = 0.40`
- `unmatched = 0.00`
- Justificacion: M9 mostro que gran parte de los `low_confidence` tienen distancias cortas pero alta ambiguedad local; se conservan como senal historica plausible, pero no con peso completo edge-especifico.

## Definiciones operativas
- `accidents_per_km = accident_count_weighted_by_quality / (edge_length_m / 1000)`.
- `historical_score_prelim` reescala `accidents_per_km` a `0-100`, capando la densidad en el p95 no nulo (`174.142`) para que tramos muy cortos o extremos no dominen el ranking preliminar.

## Cobertura observada
- Edges con al menos un accidente: 55867 (15.36% de la red canonica)
- Accidentes matched usados en la agregacion historica: 134565 (91.61% sobre el total)
- Accidentes excluidos por unmatched: 12318 (8.39% sobre el total)
- Accidentes fuera del envelope operativo: 7835 (5.33% sobre el total)

## Limitaciones abiertas
- Todavia no hay ajuste serio por exposicion real.
- Todavia no hay suavizado espacial entre aristas vecinas.
- Todavia no hay severidad incorporada.
- Todavia no hay combinacion final con el bloque contextual/dinamico.
- `historical_score_prelim` no es todavia peso final de routing.

## Que deja listo M10
- Una capa historica por edge auditable y reusable.
- Conteos raw y ponderados separados.
- Un score preliminar interpretable para la siguiente fase de combinacion, no para routing directo.
- Schema de salida: `m10_schema_v1_full_network_weighted_density_prelim_score`.

