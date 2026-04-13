# Traffic 2024 4-Month Pilot Training Table Note

## Scope
- This table is restricted to analysis year 2024 and months 1, 4, 7 and 10.
- It is a pilot partial training table, not a full historical training table for 2016-2024.

## Unit
- `edge_id + analysis_year + month + temporal_bin_4h + is_weekend`.

## Zero generation rule
- Edge universe: only edges already observed in the positive pilot model integration table.
- Time grid: only `(analysis_year, month, temporal_bin_4h, is_weekend)` combinations actually present in the pilot traffic aggregate.
- Zero rows were generated as `pilot_edge_universe x pilot_time_grid` minus observed positive units.
- This avoids expanding the entire road network while still creating defensible zeros inside the pilot temporal frame.

## Traffic integration
- Traffic for both positives and zeros was propagated from a pilot edge-to-sensor support map derived from matched pilot accidents.
- Rows with no traffic support are separated from rows with traffic support.
- Missing traffic inside the pilot is therefore interpreted as pilot-period support limitation, not as absence outside the pilot temporal coverage.

## Status
- This table is ready for a next pilot re-training phase with and without traffic.
- It must not be interpreted as a final system-wide table or as routing-ready coverage.
