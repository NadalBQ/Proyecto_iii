# Traffic 2024 4-Month Pilot Integration Note

## Scope
- This is a pilot partial integration from traffic to accidents.
- It keeps the raw row structure of `accidentes_con_trafico_final.csv` and does not deduplicate accidents.
- It does not use `edge_id`, does not enter modeling, and is not a routing-ready layer.

## Join design
- LEFT JOIN from accidents to traffic aggregated table.
- Join key: `id_sensor_cercano -> sensor_id`, `analysis_year`, `month`, `temporal_bin_4h`, `is_weekend`.
- Traffic aggregate uniqueness on that key was validated before join.

## Coverage interpretation
- Global matched rows: 24247 (7.79% of all accident rows).
- Rows inside pilot period: 25382 (8.16% of all accident rows).
- Matched rows within pilot period: 24247 (95.53% of pilot-period rows).
- Rows outside pilot period: 285817 (91.84% of all accident rows).
- Non-match outside the pilot period is expected coverage absence, not a join failure.

## Main non-match reasons inside pilot period
- sensor_not_in_traffic_pilot: 868 rows; sensor_and_time_match_not_found: 265 rows; missing_sensor_id: 2 rows

## Interpretation
- This output is suitable as a pilot partial integration layer for future traffic-aware phases.
- It must not be interpreted as full historical traffic coverage for 2016-2024.
