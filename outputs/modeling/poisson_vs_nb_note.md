# Poisson vs Negative Binomial note

## Comparison setup
- Same training table: `training_table_with_controls.parquet`.
- Same target: `accident_count`.
- Same split: train `2016-2022`, validation `2023`, test `2024`.
- Same feature block: the seven `model_safe` predictors from Poisson baseline A.

## Validation
- Winner: `Negative Binomial`.
- Poisson deviance / MAE / RMSE: `0.232470` / `0.062769` / `0.204262`.
- NB deviance / MAE / RMSE: `0.231987` / `0.063322` / `0.204185`.
- Improvement label: `marginal`.

## Test
- Winner: `Poisson`.
- Poisson deviance / MAE / RMSE: `0.295414` / `0.072730` / `0.236862`.
- NB deviance / MAE / RMSE: `0.293858` / `0.073355` / `0.236867`.
- Improvement label: `marginal`.

## Dispersion
- NB validation Pearson dispersion: `1.422053`.
- NB test Pearson dispersion: `2.042995`.
- Over-dispersion still material above threshold `1.5`: `True`.

## Recommendation
- Recommended next step: `prepare leak-safe contextual features`.
- No routing implication should be drawn from this comparison by itself.
