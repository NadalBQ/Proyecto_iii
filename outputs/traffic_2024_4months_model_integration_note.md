# Traffic 2024 4-Month Model Integration Pilot Note

## Chosen unit
- `edge_id + analysis_year + month + temporal_bin_4h + is_weekend`.
- This is a conservative extension of the existing edge-based modeling logic because the traffic pilot is explicitly monthly and only covers months 1, 4, 7 and 10 of 2024.

## Integration logic
- Base traffic source: `traffic_2024_4months_accident_joined.csv` restricted to 2024 and months 1, 4, 7 and 10.
- Edge linkage: `num_expediente -> edge_id` through `m9_accident_edge_matches.csv`.
- Accident rows were first collapsed to one pilot row per `num_expediente` for auditability; then those accident-level rows were aggregated to the chosen unit.
- Traffic support inside each unit was summarized from distinct contributing `sensor_id` values to avoid accident-row repetition inflating the traffic signal.

## Coverage reading
- Pilot-period unique accidents: 7058.
- Pilot-period unique accidents linked to edge_id: 6997 (99.14%).
- Pilot model units total: 6935.
- Pilot model units with usable traffic support: 6321 (91.15%).
- Pilot model units without usable traffic support: 614 (8.85%).

## Missing interpretation
- Outside-pilot temporal absence is not carried into this table as a normal feature missing; the table is already restricted to the pilot period.
- Remaining non-coverage inside the pilot is therefore interpreted as pilot-period support/match limitation, not as historical absence of traffic for 2016-2024.

## Status
- This table is ready for a next pilot re-training phase with traffic, but only as a restricted 2024 pilot subset.
- It is not a routing-ready layer and it must not be treated as full historical traffic coverage.
