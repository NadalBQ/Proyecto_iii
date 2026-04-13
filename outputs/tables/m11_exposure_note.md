# M11 - Crosswalk trafico/exposicion -> edge

## Logica de M11
- M11 separa tres piezas metodologicas:
  - `crosswalk geometrico`: intento de enlazar la capa lineal de trafico `Id. Tram` con la red canonica mediante geometria real.
  - `exposure baseline`: proxy por edge construida a partir del puente `edge <-> sensor` respaldado por accidentes ya matcheados en M9.
  - `historical_exposure_adjusted_score_prelim`: ajuste preliminar de la densidad historica ponderada de M10 contra una proxy de exposicion, todavia fuera del routing final.

## Fuente base de exposicion
- La proxy baseline se construye con sensores asociados a accidentes matcheados (`id_sensor_cercano`) y sus variables `intensidad` / `ocupacion`.
- No se usa `id_sensor_cercano` como join directo a `edge_id`; el enlace se construye solo a traves de evidencia `accidente matcheado -> edge` ya validada en M9.
- `exposure_proxy_value` es un indice `0-1` trazable, derivado de rankings robustos de `intensidad` y `ocupacion` a nivel sensor.

## Estado del crosswalk geometrico de trafico
- Tramos de trafico totales: 378
- Geometrias de tramo validas: 378
- BBox de tramos con solape usable frente a la red actual: FALSE
- Pairs tramo-edge linked: 0
- Si la cobertura geometrica de tramos es nula o residual, M11 no la fuerza y deja constancia del bloqueo en las tablas de salida.

## Exposure baseline y score ajustado
- `historical_count_raw` y `historical_count_weighted` se mantienen separados del ajuste por exposicion.
- `historical_exposure_adjusted_score_prelim` se obtiene reescalando la densidad historica ajustada y capando en el p95 no nulo (`252.284`).
- El ajuste usa `accidents_per_km / (0.25 + exposure_proxy_value)` para evitar explosiones en edges con proxy baja.

## Limitaciones abiertas
- La exposicion sigue siendo una proxy y no una medicion real independiente de flujo.
- Todavia no hay modelo dinamico/contextual sobre la red.
- Todavia no hay severidad ni suavizado espacial.
- Todavia no existe coste final de routing.
- `historical_exposure_adjusted_score_prelim` no es peso final de arista.

## Cobertura resultante
- Edges con exposure proxy disponible: 53691
- Edges con exposure proxy fiable (high/medium): 53565
- Edges sin proxy: 310009

- Schema de salida: `m11_schema_v1_sensor_proxy_plus_traffic_crosswalk_diagnostics`.

