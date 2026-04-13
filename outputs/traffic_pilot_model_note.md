# Traffic Pilot Model Comparison Note

## Scope
- Pilot-only comparison restricted to analysis year 2024 and months 1, 4, 7 and 10.
- Unit: `edge_id + analysis_year + month + temporal_bin_4h + is_weekend`.
- Target: `pilot_accident_count`.

## Split
- Train: months 1 and 4.
- Validation: month 7.
- Test: month 10.
- This keeps the comparison temporal and avoids a random split.

## Feature blocks
- Baseline without traffic: static/base features only.
- Baseline with traffic: same base block plus aggregated traffic features, simple train-median imputation and explicit traffic coverage flags.
- `traffic_vmed_mean` used as predictor: yes.

## Dispersion decision
- Train target mean: 0.023015.
- Train target variance: 0.022794.
- Poisson train Pearson dispersion without traffic: 1.024229.
- Poisson train Pearson dispersion with traffic: 1.024595.
- Negative Binomial justified: no.

## Interpretation boundary
- This comparison is pilot-only and must not be interpreted as a result for the full 2016-2024 system.
- Traffic missingness inside the pilot was kept explicit and documented; it is not interpreted as missing outside the pilot period.
- These outputs are for next-step pilot model integration decisions, not for routing or final edge weighting.

## Split distribution
- train: n=149208, positives=3411, zero_pct=97.71, mean=0.023015, var=0.022794.
- validation: n= 74604, positives=1591, zero_pct=97.87, mean=0.021607, var=0.021811.
- test: n= 74604, positives=1933, zero_pct=97.41, mean=0.026151, var=0.026004.

## Best family by validation/test deviance delta
- Validation best family: poisson.
- Test best family: poisson.
