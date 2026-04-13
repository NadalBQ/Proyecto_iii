# Missing Accident Sensor Coverage Audit

## Scope
- This audit uses the already-built 4-month 2024 traffic layer.
- It does not reprocess traffic, does not add months, and does not enter modeling or routing.

## Join key
- `id_sensor_cercano` in accidents was normalized to `sensor_id` and compared against `sensor_id` in `traffic_2024_4months_aggregated.csv`.

## Core impact
- Total accident rows: 311199.
- Accident rows with covered sensors: 294989.
- Accident rows with missing sensors: 16210.
- Affected accident row percentage: 5.21%.
- Missing sensors count: 360.
- Top 10 missing sensors concentrate 17.63% of the missing-sensor accident rows.

## Operational reading
- The gap is not zero, but its row-level impact stays below a 10% threshold and is operationally manageable for a pilot integration.

## Recommendation
- Coverage gap looks operationally acceptable for a pilot traffic integration. Keep the current 4-month layer and document the uncovered sensors as a bounded limitation.
