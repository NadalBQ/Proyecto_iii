from __future__ import annotations

import argparse
from pathlib import Path
import sys

import numpy as np
import pandas as pd
import statsmodels.api as sm
import statsmodels.discrete.discrete_model as smd
from sklearn.linear_model import PoissonRegressor
from sklearn.metrics import mean_absolute_error, mean_poisson_deviance, mean_squared_error

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from modeling.config import build_paths
from modeling.train_baseline import (
    OVERDISPERSION_THRESHOLD,
    POISSON_ALPHA,
    POISSON_MAX_ITER,
    TEST_YEARS,
    TRAIN_YEARS,
    VALIDATION_YEARS,
    assign_prediction_bins,
    ensure_nonempty_splits,
)


A2B2_FEATURE_SOURCES = {
    "log_edge_length_m": "edge_length_m",
    "analysis_year_offset": "analysis_year",
    "hour_sin": "hour_sin",
    "hour_cos": "hour_cos",
    "is_weekend_int": "is_weekend",
    "log1p_edge_accident_count_prior_total": "edge_accident_count_prior_total",
    "log1p_edge_bin_accident_count_prior": "edge_bin_accident_count_prior",
    "log1p_edge_accident_count_prior_1y": "edge_accident_count_prior_1y",
    "log1p_edge_bin_accident_count_prior_1y": "edge_bin_accident_count_prior_1y",
    "log1p_edge_accident_count_prior_recent_3y": "edge_accident_count_prior_recent_3y",
    "log1p_edge_bin_accident_count_prior_recent_3y": "edge_bin_accident_count_prior_recent_3y",
}

EXCLUDED_CANDIDATE_COLUMNS = {
    "edge_years_since_last_accident": "excluded_due_to_high_structural_missingness_without_imputation",
    "edge_bin_years_since_last_accident": "excluded_due_to_high_structural_missingness_without_imputation",
    "edge_accident_count_prior_2y": "excluded_for_prudence_because_recent_3y_window_already_captures_this_signal",
    "edge_bin_accident_count_prior_2y": "excluded_for_prudence_because_recent_3y_window_already_captures_this_signal",
    "recent_activity_flag": "excluded_as_near_binary_reexpression_of_recent_3y_count",
    "edge_bin_recent_activity_flag": "excluded_as_near_binary_reexpression_of_recent_3y_bin_count",
    "edge_active_years_prior_recent_3y": "excluded_for_prudence_to_limit_redundancy_in_first_A2B2_iteration",
    "edge_bin_active_years_prior_recent_3y": "excluded_for_prudence_to_limit_redundancy_in_first_A2B2_iteration",
    "edge_accident_count_prior_change_1y": "excluded_for_prudence_to_avoid_adding_signed_instability_in_first_A2B2_iteration",
    "edge_bin_accident_count_prior_change_1y": "excluded_for_prudence_to_avoid_adding_sparse_signed_instability",
    "edge_bin_share_of_edge_prior_recent_3y": "excluded_for_prudence_because_it_is_a_derived_share_of_the_same_recent_count_block",
}

NB_MAX_ITER = 100
NB_FALLBACK_SAMPLE_N = 250_000
NB_RANDOM_SEED = 20260411


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train ROAD-SAFETY A2/B2 lag-safe baselines and compare them.")
    parser.add_argument("--force", action="store_true", help="Retrain even if A2/B2 artifacts already exist.")
    return parser.parse_args()


def validate_required_artifacts(paths) -> None:
    required = [
        paths.training_with_lag_safe_features_parquet,
        paths.lag_safe_feature_registry_csv,
        paths.poisson_metrics_csv,
        paths.negative_binomial_metrics_csv,
        paths.poisson_predictions_csv,
        paths.negative_binomial_predictions_csv,
    ]
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        raise FileNotFoundError(f"Missing required artifacts for A2/B2 phase: {missing}")


def validate_feature_block(paths) -> None:
    registry = pd.read_csv(paths.lag_safe_feature_registry_csv)
    lookup = registry.set_index("column_name").to_dict("index")
    missing = []
    unsafe = []

    for source_column in A2B2_FEATURE_SOURCES.values():
        if source_column not in lookup:
            missing.append(source_column)
            continue
        if lookup[source_column]["temporal_safety_bucket"] != "safe_now":
            unsafe.append(source_column)

    if missing:
        raise ValueError(f"A2/B2 feature block references missing source columns: {missing}")
    if unsafe:
        raise ValueError(f"A2/B2 feature block includes non-safe columns: {unsafe}")


def load_table(paths) -> pd.DataFrame:
    return pd.read_parquet(paths.training_with_lag_safe_features_parquet)


def add_a2b2_features(df: pd.DataFrame) -> pd.DataFrame:
    result = df.copy()
    result["log_edge_length_m"] = np.log(result["edge_length_m"])
    result["analysis_year_offset"] = result["analysis_year"] - min(TRAIN_YEARS)
    result["is_weekend_int"] = result["is_weekend"].astype(int)
    result["log1p_edge_accident_count_prior_total"] = np.log1p(result["edge_accident_count_prior_total"])
    result["log1p_edge_bin_accident_count_prior"] = np.log1p(result["edge_bin_accident_count_prior"])
    result["log1p_edge_accident_count_prior_1y"] = np.log1p(result["edge_accident_count_prior_1y"])
    result["log1p_edge_bin_accident_count_prior_1y"] = np.log1p(result["edge_bin_accident_count_prior_1y"])
    result["log1p_edge_accident_count_prior_recent_3y"] = np.log1p(result["edge_accident_count_prior_recent_3y"])
    result["log1p_edge_bin_accident_count_prior_recent_3y"] = np.log1p(result["edge_bin_accident_count_prior_recent_3y"])
    return result


def split_frames(df: pd.DataFrame) -> dict[str, pd.DataFrame]:
    return {
        "train": df.loc[df["analysis_year"].isin(TRAIN_YEARS)].copy(),
        "validation": df.loc[df["analysis_year"].isin(VALIDATION_YEARS)].copy(),
        "test": df.loc[df["analysis_year"].isin(TEST_YEARS)].copy(),
    }


def get_feature_matrix(df: pd.DataFrame) -> pd.DataFrame:
    matrix = df[list(A2B2_FEATURE_SOURCES.keys())].copy()
    if matrix.isna().any().any():
        na_columns = matrix.columns[matrix.isna().any()].tolist()
        raise ValueError(f"Missing values found in A2/B2 feature matrix: {na_columns}")
    return matrix


def fit_poisson(train_df: pd.DataFrame) -> PoissonRegressor:
    X = get_feature_matrix(train_df)
    y = train_df["accident_count"].to_numpy()
    model = PoissonRegressor(alpha=POISSON_ALPHA, max_iter=POISSON_MAX_ITER)
    model.fit(X, y)
    return model


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
    X = add_constant(get_feature_matrix(frame)) if fit_method.startswith("statsmodels") else get_feature_matrix(frame)
    return np.asarray(model_result.predict(X), dtype=float)


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


def compute_model_based_pearson_dispersion(y_true: np.ndarray, mu: np.ndarray, alpha: float, n_params: int) -> float:
    variance = mu + alpha * np.square(mu)
    numerator = np.sum(np.square(y_true - mu) / np.clip(variance, 1e-9, None))
    denominator = max(len(y_true) - n_params, 1)
    return float(numerator / denominator)


def compute_poisson_style_pearson_dispersion(y_true: np.ndarray, mu: np.ndarray, n_params: int) -> float:
    numerator = np.sum(np.square(y_true - mu) / np.clip(mu, 1e-9, None))
    denominator = max(len(y_true) - n_params, 1)
    return float(numerator / denominator)


def score_frame(frame: pd.DataFrame, predicted: np.ndarray, model_name: str, fit_method: str, alpha: float | None = None) -> tuple[pd.DataFrame, dict]:
    scored = frame[
        ["edge_id", "analysis_year", "temporal_bin_4h", "is_weekend", "is_zero_only_control", "accident_count"]
    ].copy()
    scored["model_name"] = model_name
    scored["predicted_accident_count"] = predicted
    scored["prediction_bin"] = assign_prediction_bins(scored["predicted_accident_count"])

    y_true = scored["accident_count"].to_numpy()
    y_pred = scored["predicted_accident_count"].to_numpy()
    bins_n, mean_gap, max_gap = calibration_metrics(scored)
    n_params = len(A2B2_FEATURE_SOURCES) + (2 if alpha is not None else 1)

    metrics = {
        "rows_n": int(len(scored)),
        "positive_rows_n": int((scored["accident_count"] > 0).sum()),
        "zero_rows_n": int((scored["accident_count"] == 0).sum()),
        "zero_rows_pct": float(100 * (scored["accident_count"] == 0).mean()),
        "target_mean": float(scored["accident_count"].mean()),
        "target_variance": float(scored["accident_count"].var(ddof=0)),
        "predicted_mean": float(scored["predicted_accident_count"].mean()),
        "predicted_p50": float(scored["predicted_accident_count"].quantile(0.50)),
        "predicted_p95": float(scored["predicted_accident_count"].quantile(0.95)),
        "predicted_p99": float(scored["predicted_accident_count"].quantile(0.99)),
        "mean_poisson_deviance": float(mean_poisson_deviance(y_true, y_pred)),
        "mae": float(mean_absolute_error(y_true, y_pred)),
        "rmse": float(np.sqrt(mean_squared_error(y_true, y_pred))),
        "calibration_bins_n": bins_n,
        "calibration_mean_abs_gap": mean_gap,
        "calibration_max_abs_gap": max_gap,
        "fit_method": fit_method,
    }
    if alpha is None:
        metrics["pearson_dispersion"] = compute_poisson_style_pearson_dispersion(y_true, y_pred, n_params=n_params)
        metrics["alpha_estimate"] = 0.0
    else:
        metrics["pearson_dispersion"] = compute_model_based_pearson_dispersion(y_true, y_pred, alpha=alpha, n_params=n_params)
        metrics["alpha_estimate"] = alpha
    metrics["overdispersion_flag"] = bool(metrics["pearson_dispersion"] > OVERDISPERSION_THRESHOLD)
    return scored, metrics


def fit_and_score_poisson_a2(split_frames_dict: dict[str, pd.DataFrame]) -> tuple[PoissonRegressor, pd.DataFrame, pd.DataFrame]:
    model = fit_poisson(split_frames_dict["train"])
    metrics_rows = []
    scored_frames = []
    for split_name, frame in split_frames_dict.items():
        predicted = model.predict(get_feature_matrix(frame))
        scored, metrics = score_frame(frame, predicted, model_name="poisson_a2", fit_method="sklearn.PoissonRegressor", alpha=None)
        scored["split"] = split_name
        metrics["split"] = split_name
        scored_frames.append(scored)
        metrics_rows.append(metrics)
    return model, pd.concat(scored_frames, ignore_index=True), pd.DataFrame(metrics_rows)


def fit_and_score_nb_b2(split_frames_dict: dict[str, pd.DataFrame]) -> tuple[object, pd.DataFrame, pd.DataFrame, str, float, bool]:
    result, fit_method, alpha, converged = fit_negative_binomial(split_frames_dict["train"])
    metrics_rows = []
    scored_frames = []
    for split_name, frame in split_frames_dict.items():
        predicted = predict_mean(result, frame, fit_method=fit_method)
        scored, metrics = score_frame(frame, predicted, model_name="negative_binomial_b2", fit_method=fit_method, alpha=alpha)
        scored["split"] = split_name
        metrics["split"] = split_name
        metrics["converged"] = converged
        scored_frames.append(scored)
        metrics_rows.append(metrics)
    return result, pd.concat(scored_frames, ignore_index=True), pd.DataFrame(metrics_rows), fit_method, alpha, converged


def build_poisson_coefficients(model: PoissonRegressor) -> pd.DataFrame:
    frame = pd.DataFrame(
        {
            "parameter": list(A2B2_FEATURE_SOURCES.keys()),
            "parameter_type": "feature",
            "coefficient": model.coef_,
        }
    )
    frame["exp_coefficient"] = np.exp(frame["coefficient"])
    frame["absolute_coefficient"] = frame["coefficient"].abs()
    frame["rank_by_absolute_value"] = frame["absolute_coefficient"].rank(ascending=False, method="dense").astype(int)
    intercept = pd.DataFrame(
        [
            {
                "parameter": "intercept",
                "parameter_type": "intercept",
                "coefficient": float(model.intercept_),
                "exp_coefficient": float(np.exp(model.intercept_)),
                "absolute_coefficient": abs(float(model.intercept_)),
                "rank_by_absolute_value": 0,
            }
        ]
    )
    return pd.concat([intercept, frame.sort_values("rank_by_absolute_value")], ignore_index=True)


def build_nb_coefficients(result, fit_method: str, alpha: float) -> pd.DataFrame:
    if fit_method == "statsmodels.discrete.NegativeBinomial_mle":
        params = pd.Series(result.params)
    else:
        params = pd.Series(result.params, index=["const"] + list(A2B2_FEATURE_SOURCES.keys()))

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
        rows.append(
            {
                "parameter": "intercept" if name == "const" else name,
                "parameter_type": "intercept" if name == "const" else "feature",
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
                "coefficient": float(alpha),
                "exp_coefficient": np.nan,
                "absolute_coefficient": abs(float(alpha)),
            }
        )
    frame = pd.DataFrame(rows)
    frame["rank_by_absolute_value"] = frame["absolute_coefficient"].rank(ascending=False, method="dense").astype(int)
    return frame.sort_values(["parameter_type", "rank_by_absolute_value", "parameter"]).reset_index(drop=True)


def subgroup_metrics(frame: pd.DataFrame, segment: str) -> dict:
    if frame.empty:
        return {
            "segment": segment,
            "rows_n": 0,
            "positive_rows_n": 0,
            "zero_rows_n": 0,
            "zero_rows_pct": np.nan,
            "target_mean": np.nan,
            "target_variance": np.nan,
            "predicted_mean": np.nan,
            "predicted_p50": np.nan,
            "predicted_p95": np.nan,
            "predicted_p99": np.nan,
            "mean_poisson_deviance": np.nan,
            "mae": np.nan,
            "rmse": np.nan,
            "pearson_dispersion": np.nan,
            "calibration_bins_n": np.nan,
            "calibration_mean_abs_gap": np.nan,
            "calibration_max_abs_gap": np.nan,
        }
    y_true = frame["accident_count"].to_numpy()
    y_pred = frame["predicted_accident_count"].to_numpy()
    return {
        "segment": segment,
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
        "pearson_dispersion": np.nan,
        "calibration_bins_n": np.nan,
        "calibration_mean_abs_gap": np.nan,
        "calibration_max_abs_gap": np.nan,
    }


def build_a2b2_comparison(poisson_metrics: pd.DataFrame, poisson_predictions: pd.DataFrame, nb_metrics: pd.DataFrame, nb_predictions: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for model_name, metrics_df, predictions_df in (
        ("poisson_a2", poisson_metrics, poisson_predictions),
        ("negative_binomial_b2", nb_metrics, nb_predictions),
    ):
        overall = metrics_df.copy()
        overall["model_name"] = model_name
        overall["segment"] = "all"
        rows.append(overall)

        for split_name, split_frame in predictions_df.groupby("split"):
            for segment_name, segment_frame in (
                ("positive_obs", split_frame.loc[split_frame["accident_count"] > 0].copy()),
                ("zero_obs", split_frame.loc[split_frame["accident_count"] == 0].copy()),
            ):
                metric_row = subgroup_metrics(segment_frame, segment_name)
                metric_row["model_name"] = model_name
                metric_row["split"] = split_name
                metric_row["fit_method"] = metrics_df.loc[metrics_df["split"] == split_name, "fit_method"].iloc[0]
                metric_row["alpha_estimate"] = float(metrics_df.loc[metrics_df["split"] == split_name, "alpha_estimate"].iloc[0])
                metric_row["overdispersion_flag"] = pd.NA
                rows.append(pd.DataFrame([metric_row]))

    comparison = pd.concat(rows, ignore_index=True, sort=False)
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
        relative_diffs.append(abs(p_val - nb_val) / p_val if p_val else 0.0)
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


def improvement_label(old_row: pd.Series, new_row: pd.Series) -> str:
    deviance_gain = (float(old_row["mean_poisson_deviance"]) - float(new_row["mean_poisson_deviance"])) / float(old_row["mean_poisson_deviance"])
    mae_gain = (float(old_row["mae"]) - float(new_row["mae"])) / float(old_row["mae"])
    rmse_gain = (float(old_row["rmse"]) - float(new_row["rmse"])) / float(old_row["rmse"])
    gains = [deviance_gain, mae_gain, rmse_gain]
    improved_n = sum(g > 0 for g in gains)
    if improved_n >= 2 and max(gains) >= 0.05:
        return "material"
    if improved_n >= 2 and max(gains) >= 0.005:
        return "marginal"
    return "none"


def build_family_comparison(old_metrics: pd.DataFrame, old_predictions: pd.DataFrame, new_metrics: pd.DataFrame, new_predictions: pd.DataFrame, family_name: str, old_label: str, new_label: str) -> pd.DataFrame:
    rows = []
    for split_name in ["validation", "test"]:
        old_all = old_metrics.loc[old_metrics["split"] == split_name].iloc[0]
        new_all = new_metrics.loc[new_metrics["split"] == split_name].iloc[0]
        overall_label = improvement_label(old_all, new_all)
        for metric in ["mean_poisson_deviance", "mae", "rmse", "pearson_dispersion", "calibration_mean_abs_gap", "calibration_max_abs_gap"]:
            old_value = float(old_all[metric])
            new_value = float(new_all[metric])
            rows.append(
                {
                    "comparison_family": family_name,
                    "old_model": old_label,
                    "new_model": new_label,
                    "split": split_name,
                    "segment": "all",
                    "metric": metric,
                    "old_value": old_value,
                    "new_value": new_value,
                    "absolute_delta": new_value - old_value,
                    "relative_delta_pct": ((new_value - old_value) / old_value * 100) if old_value else np.nan,
                    "improvement_direction": "lower_is_better",
                    "improvement_label": overall_label,
                }
            )

        old_split = old_predictions.loc[old_predictions["split"] == split_name].copy()
        new_split = new_predictions.loc[new_predictions["split"] == split_name].copy()
        for segment_name, old_segment, new_segment in (
            ("positive_obs", old_split.loc[old_split["accident_count"] > 0].copy(), new_split.loc[new_split["accident_count"] > 0].copy()),
            ("zero_obs", old_split.loc[old_split["accident_count"] == 0].copy(), new_split.loc[new_split["accident_count"] == 0].copy()),
        ):
            old_stats = subgroup_metrics(old_segment, segment_name)
            new_stats = subgroup_metrics(new_segment, segment_name)
            segment_label = improvement_label(pd.Series(old_stats), pd.Series(new_stats))
            for metric in ["mean_poisson_deviance", "mae", "rmse", "predicted_mean", "predicted_p95"]:
                old_value = float(old_stats[metric])
                new_value = float(new_stats[metric])
                rows.append(
                    {
                        "comparison_family": family_name,
                        "old_model": old_label,
                        "new_model": new_label,
                        "split": split_name,
                        "segment": segment_name,
                        "metric": metric,
                        "old_value": old_value,
                        "new_value": new_value,
                        "absolute_delta": new_value - old_value,
                        "relative_delta_pct": ((new_value - old_value) / old_value * 100) if old_value else np.nan,
                        "improvement_direction": "lower_is_better" if metric in {"mean_poisson_deviance", "mae", "rmse"} else "contextual_readout",
                        "improvement_label": segment_label if metric in {"mean_poisson_deviance", "mae", "rmse"} else "descriptive",
                    }
                )
    return pd.DataFrame(rows)


def best_row(rows: list[pd.Series]) -> pd.Series:
    frame = pd.DataFrame(rows)
    return frame.sort_values(["mean_poisson_deviance", "mae", "rmse"]).iloc[0]


def build_note(
    a2b2_comparison: pd.DataFrame,
    family_comparison: pd.DataFrame,
    poisson_coefficients: pd.DataFrame,
    nb_coefficients: pd.DataFrame,
    old_poisson_metrics: pd.DataFrame,
    old_nb_metrics: pd.DataFrame,
) -> str:
    overall = a2b2_comparison.loc[a2b2_comparison["segment"] == "all"].copy()
    val_p = overall.loc[(overall["model_name"] == "poisson_a2") & (overall["split"] == "validation")].iloc[0]
    val_nb = overall.loc[(overall["model_name"] == "negative_binomial_b2") & (overall["split"] == "validation")].iloc[0]
    test_p = overall.loc[(overall["model_name"] == "poisson_a2") & (overall["split"] == "test")].iloc[0]
    test_nb = overall.loc[(overall["model_name"] == "negative_binomial_b2") & (overall["split"] == "test")].iloc[0]

    validation_winner = choose_winner(val_p, val_nb)
    test_winner = choose_winner(test_p, test_nb)

    old_best_val = best_row(
        [
            old_poisson_metrics.loc[old_poisson_metrics["split"] == "validation"].iloc[0],
            old_nb_metrics.loc[old_nb_metrics["split"] == "validation"].iloc[0],
        ]
    )
    old_best_test = best_row(
        [
            old_poisson_metrics.loc[old_poisson_metrics["split"] == "test"].iloc[0],
            old_nb_metrics.loc[old_nb_metrics["split"] == "test"].iloc[0],
        ]
    )
    new_best_val = best_row([val_p, val_nb])
    new_best_test = best_row([test_p, test_nb])
    validation_gain_label = improvement_label(old_best_val, new_best_val)
    test_gain_label = improvement_label(old_best_test, new_best_test)

    new_feature_names = set(list(A2B2_FEATURE_SOURCES.keys())[7:])
    top_poisson_new = (
        poisson_coefficients.loc[poisson_coefficients["parameter"].isin(new_feature_names)]
        .sort_values("absolute_coefficient", ascending=False)
        .head(3)
    )
    top_nb_new = (
        nb_coefficients.loc[nb_coefficients["parameter"].isin(new_feature_names)]
        .sort_values("absolute_coefficient", ascending=False)
        .head(3)
    )

    lines = [
        "# A2/B2 note",
        "",
        "## Feature block",
        "- Original features kept from A/B:",
    ]
    for feature in list(A2B2_FEATURE_SOURCES.keys())[:7]:
        lines.append(f"  - `{feature}`")
    lines.append("- New lag-safe features added in A2/B2:")
    for feature in list(A2B2_FEATURE_SOURCES.keys())[7:]:
        lines.append(f"  - `{feature}`")
    lines.extend(
        [
            "- Left out on purpose: `edge_years_since_last_accident`, `edge_bin_years_since_last_accident`, `*_prior_2y`, activity flags, change features and share features.",
            "",
            "## A2 vs B2",
            f"- Validation winner: `{validation_winner}`.",
            f"- Test winner: `{test_winner}`.",
            f"- A2 validation deviance / MAE / RMSE: `{val_p['mean_poisson_deviance']:.6f}` / `{val_p['mae']:.6f}` / `{val_p['rmse']:.6f}`.",
            f"- B2 validation deviance / MAE / RMSE: `{val_nb['mean_poisson_deviance']:.6f}` / `{val_nb['mae']:.6f}` / `{val_nb['rmse']:.6f}`.",
            f"- A2 test deviance / MAE / RMSE: `{test_p['mean_poisson_deviance']:.6f}` / `{test_p['mae']:.6f}` / `{test_p['rmse']:.6f}`.",
            f"- B2 test deviance / MAE / RMSE: `{test_nb['mean_poisson_deviance']:.6f}` / `{test_nb['mae']:.6f}` / `{test_nb['rmse']:.6f}`.",
            "",
            "## Improvement vs previous A/B",
            f"- Validation improvement vs old A/B: `{validation_gain_label}`.",
            f"- Test improvement vs old A/B: `{test_gain_label}`.",
            f"- Best old validation deviance / MAE / RMSE: `{old_best_val['mean_poisson_deviance']:.6f}` / `{old_best_val['mae']:.6f}` / `{old_best_val['rmse']:.6f}`.",
            f"- Best new validation deviance / MAE / RMSE: `{new_best_val['mean_poisson_deviance']:.6f}` / `{new_best_val['mae']:.6f}` / `{new_best_val['rmse']:.6f}`.",
            f"- Best old test deviance / MAE / RMSE: `{old_best_test['mean_poisson_deviance']:.6f}` / `{old_best_test['mae']:.6f}` / `{old_best_test['rmse']:.6f}`.",
            f"- Best new test deviance / MAE / RMSE: `{new_best_test['mean_poisson_deviance']:.6f}` / `{new_best_test['mae']:.6f}` / `{new_best_test['rmse']:.6f}`.",
            "",
            "## Strongest new-feature signals",
            "- Poisson A2:",
        ]
    )
    for row in top_poisson_new.itertuples(index=False):
        lines.append(f"  - `{row.parameter}`: coef `{row.coefficient:.6f}`, exp(coef) `{row.exp_coefficient:.6f}`.")
    lines.append("- Negative Binomial B2:")
    for row in top_nb_new.itertuples(index=False):
        lines.append(f"  - `{row.parameter}`: coef `{row.coefficient:.6f}`, exp(coef) `{row.exp_coefficient:.6f}`.")
    lines.extend(
        [
            "",
            "## Guardrails",
            "- A2/B2 do not change target, split or general project strategy.",
            "- These are still count-model baselines, not routing weights.",
            "- `reference_only` columns remain out of this phase.",
        ]
    )
    return "\n".join(lines) + "\n"


def main() -> None:
    args = parse_args()
    paths = build_paths()
    validate_required_artifacts(paths)
    validate_feature_block(paths)

    if paths.a2_b2_comparison_csv.exists() and not args.force:
        print(f"A2/B2 comparison already exists: {paths.a2_b2_comparison_csv}")
        print("Use --force to retrain.")
        return

    df = load_table(paths)
    df = add_a2b2_features(df)
    split_frames_dict = split_frames(df)
    ensure_nonempty_splits(split_frames_dict)

    poisson_model, poisson_predictions, poisson_metrics = fit_and_score_poisson_a2(split_frames_dict)
    nb_result, nb_predictions, nb_metrics, nb_fit_method, nb_alpha, nb_converged = fit_and_score_nb_b2(split_frames_dict)

    poisson_coefficients = build_poisson_coefficients(poisson_model)
    nb_coefficients = build_nb_coefficients(nb_result, fit_method=nb_fit_method, alpha=nb_alpha)

    a2b2_comparison = build_a2b2_comparison(poisson_metrics, poisson_predictions, nb_metrics, nb_predictions)

    old_poisson_metrics = pd.read_csv(paths.poisson_metrics_csv)
    old_poisson_predictions = pd.read_csv(paths.poisson_predictions_csv)
    old_nb_metrics = pd.read_csv(paths.negative_binomial_metrics_csv)
    old_nb_predictions = pd.read_csv(paths.negative_binomial_predictions_csv)

    family_comparison = pd.concat(
        [
            build_family_comparison(old_poisson_metrics, old_poisson_predictions, poisson_metrics, poisson_predictions, "poisson", "poisson_a", "poisson_a2"),
            build_family_comparison(old_nb_metrics, old_nb_predictions, nb_metrics, nb_predictions, "negative_binomial", "negative_binomial_b", "negative_binomial_b2"),
        ],
        ignore_index=True,
    )

    note = build_note(a2b2_comparison, family_comparison, poisson_coefficients, nb_coefficients, old_poisson_metrics, old_nb_metrics)

    poisson_metrics.to_csv(paths.poisson_a2_metrics_csv, index=False)
    poisson_coefficients.to_csv(paths.poisson_a2_coefficients_csv, index=False)
    poisson_predictions.to_csv(paths.poisson_a2_predictions_csv, index=False)
    nb_metrics.to_csv(paths.negative_binomial_b2_metrics_csv, index=False)
    nb_coefficients.to_csv(paths.negative_binomial_b2_coefficients_csv, index=False)
    nb_predictions.to_csv(paths.negative_binomial_b2_predictions_csv, index=False)
    a2b2_comparison.to_csv(paths.a2_b2_comparison_csv, index=False)
    paths.a2_b2_note_md.write_text(note, encoding="utf-8")
    family_comparison.to_csv(paths.baseline_ab_vs_a2b2_comparison_csv, index=False)

    print(f"Poisson A2 metrics written to: {paths.poisson_a2_metrics_csv}")
    print(poisson_metrics.to_string(index=False))
    print(f"Negative Binomial B2 metrics written to: {paths.negative_binomial_b2_metrics_csv}")
    print(nb_metrics.to_string(index=False))
    print(f"A2/B2 comparison written to: {paths.a2_b2_comparison_csv}")


if __name__ == "__main__":
    main()
