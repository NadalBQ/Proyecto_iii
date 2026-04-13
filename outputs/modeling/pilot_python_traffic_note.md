# Pilot Python Traffic Consolidation Note

## Scope
- Pilot-only consolidation restricted to analysis year 2024 and months 1, 4, 7 and 10.
- Unit kept fixed: `edge_id + analysis_year + month + temporal_bin_4h + is_weekend`.
- Target kept fixed: `pilot_accident_count`.
- Split reproduced exactly from R: train months 1 and 4, validation month 7, test month 10.

## Traffic contract carried into Python
- `traffic_covered_flag`
- `traffic_missing_due_to_no_time_flag`
- `traffic_intensidad_wins_log`
- `traffic_ocupacion_wins`
- `log1p_traffic_support_n`
- `log1p_traffic_n_observations`
- `traffic_vmed_mean` excluded from the main Python spec.

## Translation R -> Python
- Train-covered medians reused as the imputation rule for traffic columns.
- Winsorization thresholds computed on Python train covered rows using the type-8 equivalent (`median_unbiased`).
- Same Poisson family, same split and same baseline/base block.

## Dispersion check
- Train mean: 0.023015.
- Train variance: 0.022794.
- Train Pearson dispersion without traffic: 1.024229.
- Train Pearson dispersion with traffic: 1.024825.
- Negative Binomial not reopened in this phase.

## Alignment against R
- Validation overall Python delta deviance: -0.001031.
- Validation overall R delta deviance: -0.001031.
- Test overall Python delta deviance: -0.001990.
- Test overall R delta deviance: -0.001990.

## Interpretation boundary
- This result is pilot-only and does not validate the full 2016-2024 model.
- It does not imply readiness for routing or final edge weighting.
- It only promotes `traffic_D_transformed` as a live candidate for deeper integration in the Python modeling pipeline.