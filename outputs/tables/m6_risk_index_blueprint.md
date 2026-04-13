# M6 - Diseno preliminar del indice de riesgo ROAD-SAFETY

## Arquitectura del score baseline
- El baseline se organiza en bloques, no en una suma plana de variables: `trafico_contexto`, `temporal`.
- Bloque `trafico_contexto`: combina `intensidad` y `ocupacion` con regla anti-doble-conteo dentro del bloque.
- Bloque `temporal`: usa `hour_sin` y `hour_cos` como representacion ciclica conjunta del momento temporal.
- La formula conceptual baseline es:
```text
score_baseline = combine_blocks(
  bloque_trafico_contexto = combine_within_block(intensidad, ocupacion),
  bloque_temporal = combine_within_block(hour_sin, hour_cos)
)
```

## Arquitectura con sensibilidades
- Variables en sensibilidad: `is_weekend`.
- `is_weekend` entra como modulador opcional de escenario, no como componente base.
- `vmed` permanece bajo revision y, si se usa, debe entrar como bloque separado de sensibilidad tras limpieza adicional.
- Formula conceptual de sensibilidad:
```text
score_con_sensibilidades = attach_optional_modulators(
  score_baseline,
  weekend_modulator = is_weekend,
  speed_review_block = vmed
)
```

## Que no conviene sobreponderar junto
- `intensidad` + `ocupacion`: el PCA los situa en el mismo bloque de trafico/contexto.
- `hour_sin` + `hour_cos`: son dos coordenadas de una misma estructura ciclica, no dos ejes temporales independientes para sumar a peso pleno.
- `intensidad`/`ocupacion` + `vmed`: no conviene fusionarlas sin control porque `vmed` altera la estructura y puede duplicar senal de contexto de trafico.

## Paso de accidente/contexto a tramo/arista
- Primero hay que construir atributos por segmento y franja temporal, no usar el score accidente a accidente de forma directa en routing.
- El bloque `trafico_contexto` se traduce a atributos segmento-tiempo mediante joins con sensores o variables contextuales agregadas.
- El bloque `temporal` se traduce a perfiles dependientes de la hora o a buckets temporales del edge.
- Hace falta una capa nueva `historico_espacial` con exposicion, frecuencia historica, severidad y suavizado espacial a nivel segmento.
- Solo despues puede definirse un `peso_operativo_arista` que combine score conceptual, historial espacial, calibracion y funcion de coste para routing.
- Formula conceptual futura:
```text
peso_operativo_arista(edge, t) = transform(
  score_baseline(edge, t)
  + bloque_historico_espacial(edge)
  + moduladores_validados(edge, t)
)
```

## Limitaciones
- El PCA ayuda a detectar redundancias, bloques latentes e incompatibilidades de suma ciega.
- El PCA no resuelve pesos finales, causalidad, exposicion, severidad, map-matching ni calibracion para routing.
- Para convertir este blueprint en un peso operativo faltan como minimo: construccion de variables historico-espaciales por segmento, reglas de agregacion temporal, ajuste por exposicion, validacion con red viaria y transformacion final a coste de arista.
- Variables fuera del baseline actual: `vmed -> under_review`, `es_festivo -> excluded`.

## Componentes del blueprint
- Se han documentado 5 bloques y 6 componentes de formula conceptual en los CSV de M6.
