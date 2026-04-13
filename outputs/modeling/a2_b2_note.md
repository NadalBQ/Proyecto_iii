# A2/B2 note

## Feature block
- Original features kept from A/B:
  - `log_edge_length_m`
  - `analysis_year_offset`
  - `hour_sin`
  - `hour_cos`
  - `is_weekend_int`
  - `log1p_edge_accident_count_prior_total`
  - `log1p_edge_bin_accident_count_prior`
- New lag-safe features added in A2/B2:
  - `log1p_edge_accident_count_prior_1y`
  - `log1p_edge_bin_accident_count_prior_1y`
  - `log1p_edge_accident_count_prior_recent_3y`
  - `log1p_edge_bin_accident_count_prior_recent_3y`
- Left out on purpose: `edge_years_since_last_accident`, `edge_bin_years_since_last_accident`, `*_prior_2y`, activity flags, change features and share features.

## A2 vs B2
- Validation winner: `tie`.
- Test winner: `tie`.
- A2 validation deviance / MAE / RMSE: `0.233752` / `0.062471` / `0.203868`.
- B2 validation deviance / MAE / RMSE: `0.233456` / `0.062647` / `0.203982`.
- A2 test deviance / MAE / RMSE: `0.299426` / `0.072702` / `0.237264`.
- B2 test deviance / MAE / RMSE: `0.298568` / `0.072900` / `0.237465`.

## Improvement vs previous A/B
- Validation improvement vs old A/B: `marginal`.
- Test improvement vs old A/B: `none`.
- Best old validation deviance / MAE / RMSE: `0.231987` / `0.063322` / `0.204185`.
- Best new validation deviance / MAE / RMSE: `0.233456` / `0.062647` / `0.203982`.
- Best old test deviance / MAE / RMSE: `0.293858` / `0.073355` / `0.236867`.
- Best new test deviance / MAE / RMSE: `0.298568` / `0.072900` / `0.237465`.

## Strongest new-feature signals
- Poisson A2:
  - `log1p_edge_accident_count_prior_recent_3y`: coef `0.274573`, exp(coef) `1.315969`.
  - `log1p_edge_accident_count_prior_1y`: coef `0.248745`, exp(coef) `1.282415`.
  - `log1p_edge_bin_accident_count_prior_1y`: coef `0.237668`, exp(coef) `1.268289`.
- Negative Binomial B2:
  - `log1p_edge_accident_count_prior_recent_3y`: coef `0.287702`, exp(coef) `1.333360`.
  - `log1p_edge_bin_accident_count_prior_1y`: coef `0.216877`, exp(coef) `1.242191`.
  - `log1p_edge_bin_accident_count_prior_recent_3y`: coef `0.213358`, exp(coef) `1.237828`.

## Guardrails
- A2/B2 do not change target, split or general project strategy.
- These are still count-model baselines, not routing weights.
- `reference_only` columns remain out of this phase.
