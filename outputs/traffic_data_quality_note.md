# Traffic Data Quality Note

## Scope
- This pilot uses only January, April, July and October 2024 traffic history files.
- It does not extend the period, does not enter modeling, and does not map to edge_id.

## Input structure
- Traffic monthly files were read with separator `;`.
- Sensor locations were read with separator `;`.
- Accident file was read with separator `,` and UTF-8 encoding.
- The project sensor field detected in accidents is `id_sensor_cercano`.
- October keeps the same logical traffic schema but its header formatting drops quotes around `id` and `periodo_integracion`.

## Parsing assumptions
- Traffic timestamp was parsed from `fecha` using `%Y-%m-%d %H:%M:%S` and timezone `Europe/Madrid`.
- `sensor_id` was standardized from traffic `id`, sensor location `id`, and accident `id_sensor_cercano` with explicit numeric coercion.
- Temporal variables built in this phase are `analysis_year`, `month`, `hour`, `temporal_bin_4h`, and `is_weekend`.

## Quality observations
- Panel missingness: intensidad `0%`, ocupacion `0.12%`, vmed `0.07%`.
- Non-`N` traffic error flags account for `0.14%` of cleaned panel rows.
- Sensor join key used for official locations: `sensor_id`.
- Unique sensors in accidents: 4763.
- Overlap with official sensor locations: 95.86%.
- Overlap with 4-month traffic history: 92.44%.

## Interpretation
- This phase only establishes whether a small historical traffic slice can be summarized and linked to the sensor universe already used in accidents.
- Any weak or partial overlap must be treated as a data availability constraint, not as something to fix with ad-hoc joins.
