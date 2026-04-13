from __future__ import annotations

import argparse
from pathlib import Path
import sys

import numpy as np
import pandas as pd
import statsmodels.api as sm
import statsmodels.discrete.discrete_model as smd
from sklearn.metrics import mean_absolute_error, mean_poisson_deviance, mean_squared_error

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from modeling.config import build_paths
from modeling.train_baseline import (
    MODEL_SAFE_DERIVED_FEATURES,
    OVERDISPERSION_THRESHOLD,
    add_features,
    assign_prediction_bins,
    ensure_nonempty_splits,
    get_feature_matrix,
    split_frames,
    validate_model_safe_sources,
)


NB_MAX_ITER = 100
NB_FALLBACK_SAMPLE_N = 250_000
NB_RANDOM_SEED = 20260411


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train and compare the ROAD-SAFETY Negative Binomial baseline.")
    parser.add_argument("--force", action="store_true", help="Retrain even if NB outputs already exist.")
    return parser.parse_args()


def validate_required_artifacts(paths) -> None:
    required = [
        paths.training_with_controls_parquet,
        paths.feature_registry_csv,
        paths.poisson_metrics_csv,
        paths.poisson_predictions_csv,
    ]
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        raise FileNotFoundError(f"Missing required artifacts for Negative Binomial baseline: {missing}")


def add_constant(X: pd.DataFrame) -> pd.DataFrame:
    return sm.add_constant(X, has_constant="add")


def estimate_alpha_on_sample(train_df: pd.DataFrame) -> float:
    rng = np.random.default_rng(NB_RANDOM_SEED)
    sample_n = min(NB_FALLBACK_SAMPLE_N, len(train_df))
    sample_index = rng.choice(train_df.index.to_numpy(), size=sample_n, replace=False)
    sample = train_df.loc[sample_index].copy()
    X_sample = add_constant(get_feature_matrix(sample))
    y_sample = sample["accident_count"].to_numpy()
    sample_model = smd.NegativeBinomial(y_sample, X_sample)
    sample_result = sample_model.fit(disp=False, maxiter=NB_MAX_ITER)
    return max(float(sample_result.params["alpha"]), 1e-9)


def fit_negative_binomial(train_df: pd.DataFrame) -> tuple[object, str, float, bool]:
    X_train = add_constant(get_feature_matrix(train_df))
    y_train = train_df["accident_count"].to_numpy()

    try:
        nb_model = smd.NegativeBinomial(y_train, X_train)
        nb_result = nb_model.fit(disp=False, maxiter=NB_MAX_ITER)
        converged = bool(nb_result.mle_retvals.get("converged", False))
        alpha = max(float(nb_result.params["alpha"]), 1e-9)
        if not converged:
            raise RuntimeError("NegativeBinomial MLE did not converge cleanly on full train.")
        return nb_result, "statsmodels.discrete.NegativeBinomial_mle", alpha, converged
    except Exception:
        alpha = estimate_alpha_on_sample(train_df)
        glm_model = sm.GLM(y_train, X_train, family=sm.families.NegativeBinomial(alpha=alpha))
        glm_result = glm_model.fit(maxiter=NB_MAX_ITER, disp=False)
        converged = bool(getattr(glm_result, "converged", True))
        return glm_result, "statsmodels.GLM_NegativeBinomial_fixed_alpha", alpha, converged


def predict_mean(model_result, frame: pd.DataFrame, fit_method: str) -> np.ndarray:
    X = add_constant(get_feature_matrix(frame))
    if fit_method == "statsmodels.discrete.NegativeBinomial_mle":
        return np.asarray(model_result.predict(X), dtype=float)
    return np.asarray(model_result.predict(X), dtype=float)


def compute_model_based_pearson_dispersion(y_true: np.ndarray, mu: np.ndarray, alpha: float, n_params: int) -> float:
    variance = mu + alpha * np.square(mu)
    numerator = np.sum(np.square(y_true - mu) / np.clip(variance, 1e-9, None))
    denominator = max(len(y_true) - n_params, 1)
    return float(numerator / denominator)


def calibration_metrics(frame: pd.DataFrame) -> tuple[int, float, float]:
    calibration = (
        frame.groupby("prediction_bin", as_index=False)
        .agg(
            rows_n=("accident_count", "size"),
            actual_mean=("accident_count", "mean"),
            predicted_mean=("predicted_accident_count", "mean"),
        )
    )
    calibration["abs_gap"] = (calibration["actual_mean"] - calibration["predicted_mean"]).abs()
    return int(len(calibration)), float(calibration["abs_gap"].mean()), float(calibration["abs_gap"].max())


def compute_core_metrics(frame: pd.DataFrame, alpha: float, n_params: int) -> dict[str, float]:
    y_true = frame["accident_count"].to_numpy()
    y_pred = frame["predicted_accident_count"].to_numpy()
    bins_n, mean_gap, max_gap = calibration_metrics(frame)
    return {
        "rows_n": int(len(frame)),
        "positive_rows_n": int((frame["accident_count"] > 0).sum()),
        "zero_rows_n": int((frame["accident_count"] == 0).sum()),
        "zero_rows_pct": float(100 * (frame["accident_count"] == 0).mean()),
        "target_mean": float(frame["accident_count"].mean()),
        "target_variance": float(frame["accident_count"].var(ddof=0)),
        "predicted_mean": float(frame["predicted_accident_count"].mean()),
        "predicted_p50": float(frame["predicted_accident_count"].quantile(0.50)),
        "predicted_p95": float(frame["predicted_accident_count"].quantile(0.95)),
        "predicted_p99": float(frame["predicted_accident_count"].quantile(0.99)),
        "mean_poisson_deviance": float(mean_poisson_deviance(y_true, y_pred)),
        "mae": float(mean_absolute_error(y_true, y_pred)),
        "rmse": float(np.sqrt(mean_squared_error(y_true, y_pred))),
        "pearson_dispersion": compute_model_based_pearson_dispersion(y_true, y_pred, alpha=alpha, n_params=n_params),
        "calibration_bins_n": bins_n,
        "calibration_mean_abs_gap": mean_gap,
        "calibration_max_abs_gap": max_gap,
    }


def subgroup_metrics(frame: pd.DataFrame, subgroup_name: str) -> dict[str, float | str]:
    if frame.empty:
        return {
            "segment": subgroup_name,
            "rows_n": 0,
            "target_mean": np.nan,
            "predicted_mean": np.nan,
            "predicted_p50": np.nan,
            "predicted_p95": np.nan,
            "predicted_p99": np.nan,
            "mean_poisson_deviance": np.nan,
            "mae": np.nan,
            "rmse": np.nan,
        }

    y_true = frame["accident_count"].to_numpy()
    y_pred = frame["predicted_accident_count"].to_numpy()
    return {
        "segment": subgroup_name,
        "rows_n": int(len(frame)),
        "target_mean": float(frame["accident_count"].mean()),
        "predicted_mean": float(frame["predicted_accident_count"].mean()),
        "predicted_p50": float(frame["predicted_accident_count"].quantile(0.50)),
        "predicted_p95": float(frame["predicted_accident_count"].quantile(0.95)),
        "predicted_p99": float(frame["predicted_accident_count"].quantile(0.99)),
        "mean_poisson_deviance": float(mean_poisson_deviance(y_true, y_pred)),
        "mae": float(mean_absolute_error(y_true, y_pred)),
        "rmse": float(np.sqrt(mean_squared_error(y_true, y_pred))),
    }


def score_splits(model_result, split_frames_dict: dict[str, pd.DataFrame], fit_method: str, alpha: float) -> tuple[pd.DataFrame, pd.DataFrame]:
    prediction_frames = []
    metrics_rows = []
    n_params = len(MODEL_SAFE_DERIVED_FEATURES) + 2

    for split_name, frame in split_frames_dict.items():
        scored = frame[
            [
                "edge_id",
                "analysis_year",
                "temporal_bin_4h",
                "is_weekend",
                "is_zero_only_control",
                "accident_count",
            ]
        ].copy()
        scored["split"] = split_name
        scored["predicted_accident_count"] = predict_mean(model_result, frame, fit_method)
        scored["prediction_bin"] = assign_prediction_bins(scored["predicted_accident_count"])
        prediction_frames.append(scored)

        row = compute_core_metrics(scored, alpha=alpha, n_params=n_params)
        row["split"] = split_name
        row["fit_method"] = fit_method
        row["alpha_estimate"] = alpha
        row["overdispersion_flag"] = bool(row["pearson_dispersion"] > OVERDISPERSION_THRESHOLD)
        metrics_rows.append(row)

    predictions = pd.concat(prediction_frames, ignore_index=True)
    metrics = pd.DataFrame(metrics_rows)
    return predictions, metrics


def build_coefficients_frame(model_result, fit_method: str, alpha: float) -> pd.DataFrame:
    if fit_method == "statsmodels.discrete.NegativeBinomial_mle":
        params = pd.Series(model_result.params)
    else:
        params = pd.Series(model_result.params, index=["const"] + list(MODEL_SAFE_DERIVED_FEATURES.keys()))

    rows = []
    for name, value in params.items():
        if name == "alpha":
            rows.append(
                {
                    "parameter": "alpha",
                    "parameter_type": "dispersion",
                    "coefficient": float(value),
                    "exp_coefficient": np.nan,
                    "absolute_coefficient": abs(float(value)),
                }
            )
            continue

        param_type = "intercept" if name == "const" else "feature"
        rows.append(
            {
                "parameter": "intercept" if name == "const" else name,
                "parameter_type": param_type,
                "coefficient": float(value),
                "exp_coefficient": float(np.exp(value)),
                "absolute_coefficient": abs(float(value)),
            }
        )

    if not any(row["parameter"] == "alpha" for row in rows):
        rows.append(
            {
                "parameter": "alpha",
                "parameter_type": "dispersion",
                "coefficient": alpha,
                "exp_coefficient": np.nan,
                "absolute_coefficient": abs(alpha),
            }
        )

    frame = pd.DataFrame(rows)
    frame["rank_by_absolute_value"] = frame["absolute_coefficient"].rank(ascending=False, method="dense").astype(int)
    return frame.sort_values(["parameter_type", "rank_by_absolute_value", "parameter"]).reset_index(drop=True)


def load_poisson_artifacts(paths) -> tuple[pd.DataFrame, pd.DataFrame]:
    return (
        pd.read_csv(paths.poisson_metrics_csv),
        pd.read_csv(paths.poisson_predictions_csv),
    )


def build_comparison_frame(poisson_metrics: pd.DataFrame, poisson_predictions: pd.DataFrame, nb_metrics: pd.DataFrame, nb_predictions: pd.DataFrame) -> pd.DataFrame:
    comparison_rows = []

    for model_name, metrics_df, predictions_df, alpha in (
        ("poisson_baseline_a", poisson_metrics, poisson_predictions, 0.0),
        ("negative_binomial_baseline_b", nb_metrics, nb_predictions, float(nb_metrics["alpha_estimate"].iloc[0])),
    ):
        overall = metrics_df.copy()
        overall["model_name"] = model_name
        overall["segment"] = "all"
        for quantile_column, quantile_value in (
            ("predicted_p50", 0.50),
            ("predicted_p95", 0.95),
            ("predicted_p99", 0.99),
        ):
            if quantile_column not in overall.columns:
                quantiles = (
                    predictions_df.groupby("split")["predicted_accident_count"]
                    .quantile(quantile_value)
                    .rename(quantile_column)
                    .reset_index()
                )
                overall = overall.merge(quantiles, on="split", how="left")
        comparison_rows.append(overall)

        for split_name, split_frame in predictions_df.groupby("split"):
            positive_only = split_frame.loc[split_frame["accident_count"] > 0].copy()
            zero_only = split_frame.loc[split_frame["accident_count"] == 0].copy()
            for subgroup_frame, subgroup_name in ((positive_only, "positive_obs"), (zero_only, "zero_obs")):
                subgroup_row = subgroup_metrics(subgroup_frame, subgroup_name)
                subgroup_row.update(
                    {
                        "model_name": model_name,
                        "split": split_name,
                        "fit_method": metrics_df.loc[metrics_df["split"] == split_name, "fit_method"].iloc[0] if "fit_method" in metrics_df.columns else "sklearn.PoissonRegressor",
                        "alpha_estimate": alpha,
                        "overdispersion_flag": pd.NA,
                        "pearson_dispersion": np.nan,
                        "calibration_bins_n": np.nan,
                        "calibration_mean_abs_gap": np.nan,
                        "calibration_max_abs_gap": np.nan,
                        "positive_rows_n": int((subgroup_frame["accident_count"] > 0).sum()),
                        "zero_rows_n": int((subgroup_frame["accident_count"] == 0).sum()),
                        "zero_rows_pct": float(100 * (subgroup_frame["accident_count"] == 0).mean()) if len(subgroup_frame) else np.nan,
                        "target_variance": float(subgroup_frame["accident_count"].var(ddof=0)) if len(subgroup_frame) else np.nan,
                    }
                )
                comparison_rows.append(pd.DataFrame([subgroup_row]))

    comparison = pd.concat(comparison_rows, ignore_index=True, sort=False)
    return comparison[
        [
            "model_name",
            "split",
            "segment",
            "rows_n",
            "positive_rows_n",
            "zero_rows_n",
            "zero_rows_pct",
            "target_mean",
            "target_variance",
            "predicted_mean",
            "predicted_p50",
            "predicted_p95",
            "predicted_p99",
            "mean_poisson_deviance",
            "mae",
            "rmse",
            "pearson_dispersion",
            "calibration_bins_n",
            "calibration_mean_abs_gap",
            "calibration_max_abs_gap",
            "fit_method",
            "alpha_estimate",
            "overdispersion_flag",
        ]
    ]


def choose_winner(poisson_row: pd.Series, nb_row: pd.Series) -> str:
    relative_diffs = []
    nb_votes = 0
    poisson_votes = 0
    for metric in ("mean_poisson_deviance", "mae", "rmse"):
        p_val = float(poisson_row[metric])
        nb_val = float(nb_row[metric])
        if p_val == 0:
            relative_diffs.append(0.0)
        else:
            relative_diffs.append(abs(p_val - nb_val) / p_val)
        if nb_val < p_val:
            nb_votes += 1
        elif p_val < nb_val:
            poisson_votes += 1

    if max(relative_diffs) < 0.005:
        return "tie"
    if nb_votes >= 2:
        return "Negative Binomial"
    if poisson_votes >= 2:
        return "Poisson"
    return "tie"


def improvement_label(poisson_row: pd.Series, nb_row: pd.Series) -> str:
    deviance_gain = (float(poisson_row["mean_poisson_deviance"]) - float(nb_row["mean_poisson_deviance"])) / float(poisson_row["mean_poisson_deviance"])
    mae_gain = (float(poisson_row["mae"]) - float(nb_row["mae"])) / float(poisson_row["mae"])
    if deviance_gain >= 0.05 and mae_gain >= 0.03:
        return "material"
    if deviance_gain > 0:
        return "marginal"
    if deviance_gain < -0.01:
        return "negative"
    return "tie_or_negligible"


def build_nb_note(metrics: pd.DataFrame, coefficients: pd.DataFrame) -> str:
    validation_metrics = metrics.loc[metrics["split"] == "validation"].iloc[0]
    test_metrics = metrics.loc[metrics["split"] == "test"].iloc[0]
    alpha = float(metrics["alpha_estimate"].iloc[0])
    method = metrics["fit_method"].iloc[0]

    feature_coeffs = coefficients.loc[coefficients["parameter_type"] == "feature"].copy()
    strongest_positive = feature_coeffs.sort_values("coefficient", ascending=False).head(3)
    strongest_negative = feature_coeffs.sort_values("coefficient", ascending=True).head(3)

    lines = [
        "# Negative Binomial baseline note",
        "",
        "## Scope",
        "- Target: `accident_count`.",
        "- Split: train `2016-2022`, validation `2023`, test `2024`.",
        "- Features: exactly the same `model_safe` transformed predictors as Poisson baseline A.",
        "- This baseline is not a routing weight and not a final graph cost.",
        "",
        "## Fitting method",
        f"- Method used: `{method}`.",
        f"- Estimated alpha: `{alpha:.6f}`.",
        "",
        "## Validation/Test performance",
        f"- Validation mean Poisson deviance / MAE / RMSE: `{validation_metrics['mean_poisson_deviance']:.6f}` / `{validation_metrics['mae']:.6f}` / `{validation_metrics['rmse']:.6f}`.",
        f"- Validation Pearson dispersion: `{validation_metrics['pearson_dispersion']:.6f}`.",
        f"- Test mean Poisson deviance / MAE / RMSE: `{test_metrics['mean_poisson_deviance']:.6f}` / `{test_metrics['mae']:.6f}` / `{test_metrics['rmse']:.6f}`.",
        f"- Test Pearson dispersion: `{test_metrics['pearson_dispersion']:.6f}`.",
        "",
        "## Coefficient readout",
        "- Strongest positive coefficients:",
    ]

    for row in strongest_positive.itertuples(index=False):
        lines.append(f"  - `{row.parameter}`: coef `{row.coefficient:.6f}`, exp(coef) `{row.exp_coefficient:.6f}`.")
    lines.append("- Strongest negative coefficients:")
    for row in strongest_negative.itertuples(index=False):
        lines.append(f"  - `{row.parameter}`: coef `{row.coefficient:.6f}`, exp(coef) `{row.exp_coefficient:.6f}`.")

    lines.extend(
        [
            "",
            "## Interpretation guardrails",
            "- The comparison against Poisson A is clean because target, table, split and features are unchanged.",
            "- Negative Binomial is still only a count-model baseline; it does not produce a routing weight and does not change the project strategy by itself.",
        ]
    )
    return "\n".join(lines) + "\n"


def build_comparison_note(comparison: pd.DataFrame) -> str:
    overall = comparison.loc[comparison["segment"] == "all"].copy()
    val_p = overall.loc[(overall["model_name"] == "poisson_baseline_a") & (overall["split"] == "validation")].iloc[0]
    val_nb = overall.loc[(overall["model_name"] == "negative_binomial_baseline_b") & (overall["split"] == "validation")].iloc[0]
    test_p = overall.loc[(overall["model_name"] == "poisson_baseline_a") & (overall["split"] == "test")].iloc[0]
    test_nb = overall.loc[(overall["model_name"] == "negative_binomial_baseline_b") & (overall["split"] == "test")].iloc[0]

    validation_winner = choose_winner(val_p, val_nb)
    test_winner = choose_winner(test_p, test_nb)
    validation_gain = improvement_label(val_p, val_nb)
    test_gain = improvement_label(test_p, test_nb)
    overdispersion_material = bool(
        float(val_nb["pearson_dispersion"]) > OVERDISPERSION_THRESHOLD or float(test_nb["pearson_dispersion"]) > OVERDISPERSION_THRESHOLD
    )

    if validation_winner == "Negative Binomial" or test_winner == "Negative Binomial":
        if validation_gain == "material" or test_gain == "material":
            next_step = "move to Negative Binomial"
        else:
            next_step = "prepare leak-safe contextual features"
    else:
        next_step = "keep Poisson"

    if overdispersion_material and next_step == "keep Poisson":
        next_step = "consider hurdle/zero-inflated"

    lines = [
        "# Poisson vs Negative Binomial note",
        "",
        "## Comparison setup",
        "- Same training table: `training_table_with_controls.parquet`.",
        "- Same target: `accident_count`.",
        "- Same split: train `2016-2022`, validation `2023`, test `2024`.",
        "- Same feature block: the seven `model_safe` predictors from Poisson baseline A.",
        "",
        "## Validation",
        f"- Winner: `{validation_winner}`.",
        f"- Poisson deviance / MAE / RMSE: `{val_p['mean_poisson_deviance']:.6f}` / `{val_p['mae']:.6f}` / `{val_p['rmse']:.6f}`.",
        f"- NB deviance / MAE / RMSE: `{val_nb['mean_poisson_deviance']:.6f}` / `{val_nb['mae']:.6f}` / `{val_nb['rmse']:.6f}`.",
        f"- Improvement label: `{validation_gain}`.",
        "",
        "## Test",
        f"- Winner: `{test_winner}`.",
        f"- Poisson deviance / MAE / RMSE: `{test_p['mean_poisson_deviance']:.6f}` / `{test_p['mae']:.6f}` / `{test_p['rmse']:.6f}`.",
        f"- NB deviance / MAE / RMSE: `{test_nb['mean_poisson_deviance']:.6f}` / `{test_nb['mae']:.6f}` / `{test_nb['rmse']:.6f}`.",
        f"- Improvement label: `{test_gain}`.",
        "",
        "## Dispersion",
        f"- NB validation Pearson dispersion: `{val_nb['pearson_dispersion']:.6f}`.",
        f"- NB test Pearson dispersion: `{test_nb['pearson_dispersion']:.6f}`.",
        f"- Over-dispersion still material above threshold `{OVERDISPERSION_THRESHOLD:.1f}`: `{overdispersion_material}`.",
        "",
        "## Recommendation",
        f"- Recommended next step: `{next_step}`.",
        "- No routing implication should be drawn from this comparison by itself.",
    ]
    return "\n".join(lines) + "\n"


def main() -> None:
    args = parse_args()
    paths = build_paths()
    validate_required_artifacts(paths)
    validate_model_safe_sources(paths)

    if paths.negative_binomial_metrics_csv.exists() and not args.force:
        print(f"Negative Binomial baseline metrics already exist: {paths.negative_binomial_metrics_csv}")
        print("Use --force to retrain.")
        return

    df = pd.read_parquet(paths.training_with_controls_parquet)
    df = add_features(df)
    split_frames_dict = split_frames(df)
    ensure_nonempty_splits(split_frames_dict)

    nb_result, fit_method, alpha, converged = fit_negative_binomial(split_frames_dict["train"])
    nb_predictions, nb_metrics = score_splits(nb_result, split_frames_dict, fit_method=fit_method, alpha=alpha)
    nb_metrics["converged"] = converged
    nb_coefficients = build_coefficients_frame(nb_result, fit_method=fit_method, alpha=alpha)

    poisson_metrics, poisson_predictions = load_poisson_artifacts(paths)
    if "fit_method" not in poisson_metrics.columns:
        poisson_metrics["fit_method"] = "sklearn.PoissonRegressor"
    if "alpha_estimate" not in poisson_metrics.columns:
        poisson_metrics["alpha_estimate"] = 0.0

    comparison = build_comparison_frame(poisson_metrics, poisson_predictions, nb_metrics, nb_predictions)
    nb_note = build_nb_note(nb_metrics, nb_coefficients)
    comparison_note = build_comparison_note(comparison)

    nb_metrics.to_csv(paths.negative_binomial_metrics_csv, index=False)
    nb_coefficients.to_csv(paths.negative_binomial_coefficients_csv, index=False)
    nb_predictions.to_csv(paths.negative_binomial_predictions_csv, index=False)
    paths.negative_binomial_note_md.write_text(nb_note, encoding="utf-8")
    comparison.to_csv(paths.poisson_vs_nb_comparison_csv, index=False)
    paths.poisson_vs_nb_note_md.write_text(comparison_note, encoding="utf-8")

    print(f"Negative Binomial metrics written to: {paths.negative_binomial_metrics_csv}")
    print(nb_metrics.to_string(index=False))
    print(f"Comparison written to: {paths.poisson_vs_nb_comparison_csv}")


if __name__ == "__main__":
    main()
