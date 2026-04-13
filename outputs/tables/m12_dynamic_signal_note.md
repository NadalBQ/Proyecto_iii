# M12 - Capa dinamica/contextual preliminar por edge

## Unidad observacional
- M12 fija explicitamente la unidad `edge_id + temporal_bin_4h + is_weekend`.
- La eleccion de bins de 4 horas evita una malla horaria demasiado dispersa con el soporte accident-backed actual y deja una base reutilizable para observaciones futuras.

## Que entra ya de forma usable
- `intensidad` y `ocupacion` entran como bloque contextual principal y son la unica base del `dynamic_context_signal_prelim`.
- `hour_sin`, `hour_cos` e `is_weekend` se conservan como descriptores ya utilizables, pero todavia no se convierten por si solos en una senal numerica de riesgo.

## Que queda fuera por ahora
- `vmed` queda bajo revision y no entra en el signal preliminar.
- `es_festivo` no entra en el baseline dinamico porque es una binaria muy desbalanceada para estructurar esta primera capa; puede seguir siendo modulador futuro.
- `estado_meteorologico` queda fuera hasta que exista integracion operativa comparable por edge/observacion.

## Logica del signal preliminar
- M12 no fuerza un modelo contextual serio que todavia no existe.
- El `dynamic_context_signal_prelim` se construye como promedio de ranks robustos `0-1` de `intensidad_context` y `ocupacion_context`, reescalado a `0-100`.
- Esta regla refleja la evidencia de M4-M5: `intensidad` y `ocupacion` forman un mismo bloque y no conviene sobreponderarlas sumandolas a peso pleno.

## Separacion metodologica
- `historical_exposure_adjusted_score_prelim` se mantiene separado y solo se arrastra como referencia historica por edge.
- `dynamic_context_signal_prelim` es una capa distinta, contextual y auditada por bin temporal.
- `future_combined_edge_risk` queda solo como placeholder conceptual y no se calcula en M12.

## Cobertura resultante
- Filas en la base dinamica/contextual: 103556
- Edges cubiertos por la base dinamica/contextual: 55867
- Rows con signal preliminar disponible: 85779
- Rows sin contexto numerico usable: 17777

## Limitaciones abiertas
- Todavia no hay peso final de routing.
- Todavia no hay integracion completa de meteorologia.
- Todavia no hay severidad.
- Todavia no hay calibracion final.
- Todavia no hay combinacion definitiva entre historico, exposicion y contexto dinamico.

- Schema de salida: `m12_schema_v1_edge_temporal_bin_4h_weekend_dynamic_context_baseline`.

