# Traffic Pilot Refined Model Note

## Scope
- Pilot-only refinement restricted to analysis year 2024 and months 1, 4, 7 and 10.
- Unit: `edge_id + analysis_year + month + temporal_bin_4h + is_weekend`.
- Target: `pilot_accident_count`.
- Split kept from the previous pilot phase: train months 1 and 4, validation month 7, test month 10.

## Traffic audit
- `traffic_intensidad_mean` missing overall: 9.8899%; covered missing: 0.0000%.
- `traffic_ocupacion_mean` missing overall: 9.8909%; covered missing: 0.0011%.
- `traffic_vmed_mean` missing overall: 9.9003%; covered missing: 0.0115%.
- Covered-row medians: intensidad 365.7652, ocupacion 5.4079, vmed 5.1841, n_observations 240.7600, support_n 1.0159.

## Compared traffic specifications
- `traffic_A_core`: covered flag + intensidad + ocupacion.
- `traffic_B_core_support`: A + no-time flag + `n_observations` + `support_n`.
- `traffic_C_core_support_vmed`: B + `vmed`.
- `traffic_D_transformed`: covered flag + no-time flag + winsorized/log intensity + winsorized occupancy + support/quality.

## Missing and transformation rules
- Traffic numeric columns were median-imputed using train covered rows.
- `traffic_covered_flag` and `traffic_missing_due_to_no_time_flag` were kept explicit.
- Robust transformed spec uses train 1st/99th percentile winsorization for intensidad/ocupacion before transformation.

## Recommendation signals
- Best validation spec by overall deviance delta: traffic_D_transformed.
- Best test spec by overall deviance delta: traffic_D_transformed.
- Best validation spec on positives: traffic_D_transformed.
- Best test spec on positives: traffic_D_transformed.
- Validation overall deltas vs no traffic: A -0.000339, B -0.000943, C -0.000960, D -0.001031.
- Test overall deltas vs no traffic: A -0.000754, B -0.001708, C -0.001769, D -0.001990.

## Interpretation boundary
- This note is pilot-only and must not be interpreted as validation of the full 2016-2024 system.
- It supports a next pilot step for traffic integration inside modeling, not routing or final edge weighting.
