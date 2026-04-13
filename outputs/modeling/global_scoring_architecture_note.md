# Global Scoring Architecture Note

## Scope
- This phase retakes the main global branch only.
- It does not retrain models.
- It does not activate the pilot traffic branch.
- It stops at a preliminary score and does not produce final edge weights or routing costs.

## Current global baseline
- Selected baseline: `negative_binomial_b4`.
- Family: `negative_binomial`.
- Feature block: `history_plus_contextual_lag_safe_plus_exogenous`.
- Validation overall deviance / RMSE: `0.225583` / `0.202981`.
- Test overall deviance / RMSE: `0.286072` / `0.235519`.
- Explicit runner-up after the same ranking rule: `poisson_a4`.

## Scoring architecture
- Training table stays upstream of scoring.
- Model fitting stays upstream of scoring.
- This scoring phase reuses the selected model's existing prediction artifact.
- Score transformation is a separate step from prediction.
- Future edge weighting will be a later mapping from preliminary score to graph cost.
- Future routing will consume weighted edges, not this preliminary score directly.

## Scoring unit
- `edge_id + analysis_year + temporal_bin_4h + is_weekend`.
- `month` is not part of the global scoring unit because the global branch was modeled at year/bin/weekend resolution, not the pilot monthly branch.

## Score transform rule
- Raw quantity kept: `predicted_accident_count`.
- Preliminary score rule: `linear_cap_at_global_p99_then_scale_0_100`.
- Cap reference: p99 of current scoring universe = `0.227667121163`.
- Rationale: monotonic, interpretable, capped against the heavy tail, and reversible below the cap.
- Alternatives such as percentile rank or log-score remain only documented, not activated here.

## Global vs pilot separation
- `global_default_model` is the only branch used in this phase.
- `pilot_traffic_model` remains an optional 2024-only capability and is not consulted for this output.

## What still needs to happen after this phase
- Decide how to collapse or select temporal slices for edge weighting policy.
- Map preliminary score to an actual edge-weighting rule.
- Validate graph-cost behavior before opening routing.
- Keep pilot traffic integration separate until broader traffic coverage exists.
