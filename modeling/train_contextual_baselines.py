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
from modeling.train_lag_safe_baselines import (
    NB_FALLBACK_SAMPLE_N,
    NB_MAX_ITER,
    NB_RANDOM_SEED,
    best_row,
    build_family_comparison,
    choose_winner,
    improvement_label,
)


A3B3_FEATURE_SOURCES = {
    "log_edge_length_m": "edge_length_m",
    "analysis_year_offset": "analysis_year",
    "hour_sin": "hour_sin",
    "hour_cos": "hour_cos",
    "is_weekend_int": "is_weekend",
    "log1p_edge_accident_count_prior_total": "edge_accident_count_prior_total",
    "log1p_edge_bin_accident_count_prior": "edge_bin_accident_count_prior",
    "log1p_edge_accident_count_prior_recent_3y": "edge_accident_count_prior_recent_3y",
    "log1p_edge_bin_accident_count_prior_recent_3y": "edge_bin_accident_count_prior_recent_3y",
    "prior_dynamic_context_signal_recent_3y_imputed": "prior_dynamic_context_signal_recent_3y",
    "log1p_prior_context_observation_n_recent_3y": "prior_context_observation_n_recent_3y",
    "prior_dynamic_context_recent_missing_flag": "prior_dynamic_context_signal_recent_3y_missing_flag",
    "ctx_recent_fallback_edge_bin_weekend": "prior_dynamic_context_signal_recent_3y_fallback_level",
    "ctx_recent_fallback_edge_bin": "prior_dynamic_context_signal_recent_3y_fallback_level",
    "ctx_recent_fallback_global_bin_weekend": "prior_dynamic_context_signal_recent_3y_fallback_level",
}

EXCLUDED_CONTEXTUAL_CANDIDATES = {
    "prior_dynamic_context_signal": "excluded_due_to_high_redundancy_with_recent_3y_dynamic_signal",
    "prior_context_observation_n": "excluded_due_to_high_redundancy_with_recent_3y_context_support",
    "prior_mean_intensity_context": "excluded_because_dynamic_context_signal_already_summarizes_intensity_and_occupacion",
    "prior_mean_occupacion_context": "excluded_because_dynamic_context_signal_already_summarizes_intensity_and_occupacion",
    "prior_mean_intensity_context_recent_3y": "excluded_because_recent_dynamic_signal_already_summarizes_intensity_and_occupacion",
    "prior_mean_occupacion_context_recent_3y": "excluded_because_recent_dynamic_signal_already_summarizes_intensity_and_occupacion",
    "prior_dynamic_context_signal_recent_3y_fallback_level": "encoded_as_dummies_with_road_class_bin_weekend_as_omitted_baseline",
    "prior_context_observation_n_recent_3y_missing_flag": "excluded_because_support_zero_is_already_encoded_by_log1p_support_and_missing_flag_on_dynamic_signal",
}

RECENT_FALLBACK_BASELINE = "road_class_bin_weekend"
RECENT_DYNAMIC_NEUTRAL_VALUE = 50.0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train ROAD-SAFETY A3/B3 contextual leak-safe baselines and compare them.")
    parser.add_argument("--force", action="store_true", help="Retrain even if A3/B3 artifacts already exist.")
    return parser.parse_args()


def validate_required_artifacts(paths) -> None:
    required = [
        paths.training_with_contextual_lag_safe_features_parquet,
        paths.contextual_lag_safe_feature_registry_csv,
        paths.poisson_a2_metrics_csv,
        paths.poisson_a2_predictions_csv,
        paths.negative_binomial_b2_metrics_csv,
        paths.negative_binomial_b2_predictions_csv,
    ]
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        raise FileNotFoundError(f"Missing required artifacts for A3/B3 phase: {missing}")


def _lookup_source_safety(registry: pd.DataFrame, source_column: str) -> tuple[bool, str]:
    direct = registry.loc[registry["column_name"] == source_column]
    if not direct.empty:
        bucket = str(direct["audit_bucket"].iloc[0])
        return bucket == "safe_now", bucket

    from_missing = registry.loc[registry["missing_flag_column"] == source_column]
    if not from_missing.empty:
        bucket = str(from_missing["audit_bucket"].iloc[0])
        return bucket == "safe_now", bucket

    from_fallback = registry.loc[registry["fallback_level_column"] == source_column]
    if not from_fallback.empty:
        bucket = str(from_fallback["audit_bucket"].iloc[0])
        return bucket == "safe_now", bucket

    return False, "missing"


def validate_feature_block(paths) -> None:
    registry = pd.read_csv(paths.contextual_lag_safe_feature_registry_csv)
    missing = []
    unsafe = []
    for source_column in set(A3B3_FEATURE_SOURCES.values()):
        is_safe, bucket = _lookup_source_safety(registry, source_column)
        if bucket == "missing":
            missing.append(source_column)
        elif not is_safe:
            unsafe.append(f"{source_column}:{bucket}")

    if missing:
        raise ValueError(f"A3/B3 feature block references missing source columns: {missing}")
    if unsafe:
        raise ValueError(f"A3/B3 feature block includes non-safe columns: {unsafe}")


def load_table(paths) -> pd.DataFrame:
    return pd.read_parquet(paths.training_with_contextual_lag_safe_features_parquet)


def add_a3b3_features(df: pd.DataFrame) -> pd.DataFrame:
    result = df.copy()
    result["log_edge_length_m"] = np.log(result["edge_length_m"])
    result["analysis_year_offset"] = result["analysis_year"] - min(TRAIN_YEARS)
    result["is_weekend_int"] = result["is_weekend"].astype(int)
    result["log1p_edge_accident_count_prior_total"] = np.log1p(result["edge_accident_count_prior_total"])
    result["log1p_edge_bin_accident_count_prior"] = np.log1p(result["edge_bin_accident_count_prior"])
    result["log1p_edge_accident_count_prior_recent_3y"] = np.log1p(result["edge_accident_count_prior_recent_3y"])
    result["log1p_edge_bin_accident_count_prior_recent_3y"] = np.log1p(result["edge_bin_accident_count_prior_recent_3y"])

    result["prior_dynamic_context_signal_recent_3y_imputed"] = pd.to_numeric(
        result["prior_dynamic_context_signal_recent_3y"], errors="coerce"
    ).fillna(RECENT_DYNAMIC_NEUTRAL_VALUE)
    result["log1p_prior_context_observation_n_recent_3y"] = np.log1p(
        pd.to_numeric(result["prior_context_observation_n_recent_3y"], errors="coerce").fillna(0)
    )
    result["prior_dynamic_context_recent_missing_flag"] = (
        result["prior_dynamic_context_signal_recent_3y_missing_flag"].astype(int)
    )

    fallback = result["prior_dynamic_context_signal_recent_3y_fallback_level"].fillna("unresolved").astype(str)
    result["ctx_recent_fallback_edge_bin_weekend"] = (fallback == "edge_bin_weekend").astype(int)
    result["ctx_recent_fallback_edge_bin"] = (fallback == "edge_bin").astype(int)
    result["ctx_recent_fallback_global_bin_weekend"] = (fallback == "global_bin_weekend").astype(int)
    return result


def split_frames(df: pd.DataFrame) -> dict[str, pd.DataFrame]:
    return {
        "train": df.loc[df["analysis_year"].isin(TRAIN_YEARS)].copy(),
        "validation": df.loc[df["analysis_year"].isin(VALIDATION_YEARS)].copy(),
        "test": df.loc[df["analysis_year"].isin(TEST_YEARS)].copy(),
    }


def get_feature_matrix(df: pd.DataFrame) -> pd.DataFrame:
    matrix = df[list(A3B3_FEATURE_SOURCES.keys())].copy()
    matrix = matrix.apply(pd.to_numeric, errors="coerce").astype(float)
    if matrix.isna().any().any():
        na_columns = matrix.columns[matrix.isna().any()].tolist()
        raise ValueError(f"Missing values found in A3/B3 feature matrix: {na_columns}")
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
    n_params = len(A3B3_FEATURE_SOURCES) + (2 if alpha is not None else 1)

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


def fit_and_score_poisson_a3(split_frames_dict: dict[str, pd.DataFrame]) -> tuple[PoissonRegressor, pd.DataFrame, pd.DataFrame]:
    model = fit_poisson(split_frames_dict["train"])
    metrics_rows = []
    scored_frames = []
    for split_name, frame in split_frames_dict.items():
        predicted = model.predict(get_feature_matrix(frame))
        scored, metrics = score_frame(frame, predicted, model_name="poisson_a3", fit_method="sklearn.PoissonRegressor", alpha=None)
        scored["split"] = split_name
        metrics["split"] = split_name
        scored_frames.append(scored)
        metrics_rows.append(metrics)
    return model, pd.concat(scored_frames, ignore_index=True), pd.DataFrame(metrics_rows)


def fit_and_score_nb_b3(split_frames_dict: dict[str, pd.DataFrame]) -> tuple[object, pd.DataFrame, pd.DataFrame, str, float, bool]:
    result, fit_method, alpha, converged = fit_negative_binomial(split_frames_dict["train"])
    metrics_rows = []
    scored_frames = []
    for split_name, frame in split_frames_dict.items():
        predicted = predict_mean(result, frame, fit_method=fit_method)
        scored, metrics = score_frame(frame, predicted, model_name="negative_binomial_b3", fit_method=fit_method, alpha=alpha)
        scored["split"] = split_name
        metrics["split"] = split_name
        metrics["converged"] = converged
        scored_frames.append(scored)
        metrics_rows.append(metrics)
    return result, pd.concat(scored_frames, ignore_index=True), pd.DataFrame(metrics_rows), fit_method, alpha, converged


def build_poisson_coefficients(model: PoissonRegressor) -> pd.DataFrame:
    frame = pd.DataFrame(
        {
            "parameter": list(A3B3_FEATURE_SOURCES.keys()),
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
        params = pd.Series(result.params, index=["const"] + list(A3B3_FEATURE_SOURCES.keys()))

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


def build_a3b3_comparison(poisson_metrics: pd.DataFrame, poisson_predictions: pd.DataFrame, nb_metrics: pd.DataFrame, nb_predictions: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for model_name, metrics_df, predictions_df in (
        ("poisson_a3", poisson_metrics, poisson_predictions),
        ("negative_binomial_b3", nb_metrics, nb_predictions),
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
                y_true = segment_frame["accident_count"].to_numpy()
                y_pred = segment_frame["predicted_accident_count"].to_numpy()
                metric_row = {
                    "segment": segment_name,
                    "rows_n": int(len(segment_frame)),
                    "positive_rows_n": int((segment_frame["accident_count"] > 0).sum()),
                    "zero_rows_n": int((segment_frame["accident_count"] == 0).sum()),
                    "zero_rows_pct": float(100 * (segment_frame["accident_count"] == 0).mean()) if len(segment_frame) else np.nan,
                    "target_mean": float(segment_frame["accident_count"].mean()) if len(segment_frame) else np.nan,
                    "target_variance": float(segment_frame["accident_count"].var(ddof=0)) if len(segment_frame) else np.nan,
                    "predicted_mean": float(segment_frame["predicted_accident_count"].mean()) if len(segment_frame) else np.nan,
                    "predicted_p50": float(segment_frame["predicted_accident_count"].quantile(0.50)) if len(segment_frame) else np.nan,
                    "predicted_p95": float(segment_frame["predicted_accident_count"].quantile(0.95)) if len(segment_frame) else np.nan,
                    "predicted_p99": float(segment_frame["predicted_accident_count"].quantile(0.99)) if len(segment_frame) else np.nan,
                    "mean_poisson_deviance": float(mean_poisson_deviance(y_true, y_pred)) if len(segment_frame) else np.nan,
                    "mae": float(mean_absolute_error(y_true, y_pred)) if len(segment_frame) else np.nan,
                    "rmse": float(np.sqrt(mean_squared_error(y_true, y_pred))) if len(segment_frame) else np.nan,
                    "pearson_dispersion": np.nan,
                    "calibration_bins_n": np.nan,
                    "calibration_mean_abs_gap": np.nan,
                    "calibration_max_abs_gap": np.nan,
                    "fit_method": metrics_df.loc[metrics_df["split"] == split_name, "fit_method"].iloc[0],
                    "alpha_estimate": float(metrics_df.loc[metrics_df["split"] == split_name, "alpha_estimate"].iloc[0]),
                    "overdispersion_flag": pd.NA,
                    "split": split_name,
                    "model_name": model_name,
                }
                rows.append(pd.DataFrame([metric_row]))
    return pd.concat(rows, ignore_index=True, sort=False)


def build_note(
    a3b3_comparison: pd.DataFrame,
    family_comparison: pd.DataFrame,
    poisson_coefficients: pd.DataFrame,
    nb_coefficients: pd.DataFrame,
    old_poisson_metrics: pd.DataFrame,
    old_nb_metrics: pd.DataFrame,
    train_df: pd.DataFrame,
) -> str:
    overall = a3b3_comparison.loc[a3b3_comparison["segment"] == "all"].copy()
    val_p = overall.loc[(overall["model_name"] == "poisson_a3") & (overall["split"] == "validation")].iloc[0]
    val_nb = overall.loc[(overall["model_name"] == "negative_binomial_b3") & (overall["split"] == "validation")].iloc[0]
    test_p = overall.loc[(overall["model_name"] == "poisson_a3") & (overall["split"] == "test")].iloc[0]
    test_nb = overall.loc[(overall["model_name"] == "negative_binomial_b3") & (overall["split"] == "test")].iloc[0]

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

    contextual_feature_names = {
        "prior_dynamic_context_signal_recent_3y_imputed",
        "log1p_prior_context_observation_n_recent_3y",
        "prior_dynamic_context_recent_missing_flag",
        "ctx_recent_fallback_edge_bin_weekend",
        "ctx_recent_fallback_edge_bin",
        "ctx_recent_fallback_global_bin_weekend",
    }
    top_poisson_context = (
        poisson_coefficients.loc[poisson_coefficients["parameter"].isin(contextual_feature_names)]
        .sort_values("absolute_coefficient", ascending=False)
        .head(4)
    )
    top_nb_context = (
        nb_coefficients.loc[nb_coefficients["parameter"].isin(contextual_feature_names)]
        .sort_values("absolute_coefficient", ascending=False)
        .head(4)
    )

    train_fallback = (
        train_df["prior_dynamic_context_signal_recent_3y_fallback_level"]
        .fillna("unresolved")
        .astype(str)
        .value_counts(normalize=True)
        .mul(100)
        .round(2)
    )
    road_class_share = float(train_fallback.get("road_class_bin_weekend", 0.0))
    unresolved_share = float(train_fallback.get("unresolved", 0.0))

    comparison_positive = family_comparison.loc[
        (family_comparison["segment"] == "positive_obs") & (family_comparison["metric"] == "mean_poisson_deviance")
    ].copy()
    comparison_zero = family_comparison.loc[
        (family_comparison["segment"] == "zero_obs") & (family_comparison["metric"] == "mean_poisson_deviance")
    ].copy()

    lines = [
        "# A3/B3 note",
        "",
        "## Feature block",
        "- Historical base kept from A2/B2:",
    ]
    for feature in [
        "log_edge_length_m",
        "analysis_year_offset",
        "hour_sin",
        "hour_cos",
        "is_weekend_int",
        "log1p_edge_accident_count_prior_total",
        "log1p_edge_bin_accident_count_prior",
        "log1p_edge_accident_count_prior_recent_3y",
        "log1p_edge_bin_accident_count_prior_recent_3y",
    ]:
        lines.append(f"  - `{feature}`")
    lines.append("- Contextual block added in A3/B3:")
    for feature in [
        "prior_dynamic_context_signal_recent_3y_imputed",
        "log1p_prior_context_observation_n_recent_3y",
        "prior_dynamic_context_recent_missing_flag",
        "ctx_recent_fallback_edge_bin_weekend",
        "ctx_recent_fallback_edge_bin",
        "ctx_recent_fallback_global_bin_weekend",
    ]:
        lines.append(f"  - `{feature}`")
    lines.append("- Left out on purpose:")
    for feature, reason in EXCLUDED_CONTEXTUAL_CANDIDATES.items():
        lines.append(f"  - `{feature}`: {reason}.")

    lines.extend(
        [
            "",
            "## A3 vs B3",
            f"- Validation winner: `{validation_winner}`.",
            f"- Test winner: `{test_winner}`.",
            f"- A3 validation deviance / MAE / RMSE: `{val_p['mean_poisson_deviance']:.6f}` / `{val_p['mae']:.6f}` / `{val_p['rmse']:.6f}`.",
            f"- B3 validation deviance / MAE / RMSE: `{val_nb['mean_poisson_deviance']:.6f}` / `{val_nb['mae']:.6f}` / `{val_nb['rmse']:.6f}`.",
            f"- A3 test deviance / MAE / RMSE: `{test_p['mean_poisson_deviance']:.6f}` / `{test_p['mae']:.6f}` / `{test_p['rmse']:.6f}`.",
            f"- B3 test deviance / MAE / RMSE: `{test_nb['mean_poisson_deviance']:.6f}` / `{test_nb['mae']:.6f}` / `{test_nb['rmse']:.6f}`.",
            "",
            "## Improvement vs A2/B2",
            f"- Validation improvement vs previous A2/B2: `{validation_gain_label}`.",
            f"- Test improvement vs previous A2/B2: `{test_gain_label}`.",
            f"- Best old validation deviance / MAE / RMSE: `{old_best_val['mean_poisson_deviance']:.6f}` / `{old_best_val['mae']:.6f}` / `{old_best_val['rmse']:.6f}`.",
            f"- Best new validation deviance / MAE / RMSE: `{new_best_val['mean_poisson_deviance']:.6f}` / `{new_best_val['mae']:.6f}` / `{new_best_val['rmse']:.6f}`.",
            f"- Best old test deviance / MAE / RMSE: `{old_best_test['mean_poisson_deviance']:.6f}` / `{old_best_test['mae']:.6f}` / `{old_best_test['rmse']:.6f}`.",
            f"- Best new test deviance / MAE / RMSE: `{new_best_test['mean_poisson_deviance']:.6f}` / `{new_best_test['mae']:.6f}` / `{new_best_test['rmse']:.6f}`.",
            "",
            "## Positive vs zero observations",
        ]
    )
    if not comparison_positive.empty:
        lines.append(
            "- Positive observations deviance improvement labels: "
            + ", ".join(
                f"{row.old_model}->{row.new_model} {row.split}={row.improvement_label}"
                for row in comparison_positive.itertuples(index=False)
            )
            + "."
        )
    if not comparison_zero.empty:
        lines.append(
            "- Zero observations deviance improvement labels: "
            + ", ".join(
                f"{row.old_model}->{row.new_model} {row.split}={row.improvement_label}"
                for row in comparison_zero.itertuples(index=False)
            )
            + "."
        )

    lines.extend(
        [
            "",
            "## Contextual signal reading",
            f"- Train fallback share at omitted baseline `{RECENT_FALLBACK_BASELINE}`: `{road_class_share:.2f}%`.",
            f"- Train unresolved contextual share: `{unresolved_share:.2f}%`.",
            "- This means most of the contextual block is still inherited from road-class/bin/weekend support rather than fine edge-specific support.",
            "",
            "## Strongest contextual coefficient signals",
            "- Poisson A3:",
        ]
    )
    for row in top_poisson_context.itertuples(index=False):
        lines.append(f"  - `{row.parameter}`: coef `{row.coefficient:.6f}`, exp(coef) `{row.exp_coefficient:.6f}`.")
    lines.append("- Negative Binomial B3:")
    for row in top_nb_context.itertuples(index=False):
        lines.append(f"  - `{row.parameter}`: coef `{row.coefficient:.6f}`, exp(coef) `{row.exp_coefficient:.6f}`.")
    lines.extend(
        [
            "",
            "## Guardrails",
            "- A3/B3 do not change target, split or general project strategy.",
            "- These are still count-model baselines, not routing weights.",
            "- Full-period accident-backed references remain out of the predictor set.",
        ]
    )
    return "\n".join(lines) + "\n"


def main() -> None:
    args = parse_args()
    paths = build_paths()
    validate_required_artifacts(paths)
    validate_feature_block(paths)

    if paths.a3_b3_comparison_csv.exists() and not args.force:
        print(f"A3/B3 comparison already exists: {paths.a3_b3_comparison_csv}")
        print("Use --force to retrain.")
        return

    df = load_table(paths)
    df = add_a3b3_features(df)
    split_frames_dict = split_frames(df)
    ensure_nonempty_splits(split_frames_dict)

    poisson_model, poisson_predictions, poisson_metrics = fit_and_score_poisson_a3(split_frames_dict)
    nb_result, nb_predictions, nb_metrics, nb_fit_method, nb_alpha, _ = fit_and_score_nb_b3(split_frames_dict)

    poisson_coefficients = build_poisson_coefficients(poisson_model)
    nb_coefficients = build_nb_coefficients(nb_result, fit_method=nb_fit_method, alpha=nb_alpha)

    a3b3_comparison = build_a3b3_comparison(poisson_metrics, poisson_predictions, nb_metrics, nb_predictions)

    old_poisson_metrics = pd.read_csv(paths.poisson_a2_metrics_csv)
    old_poisson_predictions = pd.read_csv(paths.poisson_a2_predictions_csv)
    old_nb_metrics = pd.read_csv(paths.negative_binomial_b2_metrics_csv)
    old_nb_predictions = pd.read_csv(paths.negative_binomial_b2_predictions_csv)

    family_comparison = pd.concat(
        [
            build_family_comparison(old_poisson_metrics, old_poisson_predictions, poisson_metrics, poisson_predictions, "poisson", "poisson_a2", "poisson_a3"),
            build_family_comparison(old_nb_metrics, old_nb_predictions, nb_metrics, nb_predictions, "negative_binomial", "negative_binomial_b2", "negative_binomial_b3"),
        ],
        ignore_index=True,
    )

    note = build_note(
        a3b3_comparison,
        family_comparison,
        poisson_coefficients,
        nb_coefficients,
        old_poisson_metrics,
        old_nb_metrics,
        split_frames_dict["train"],
    )

    poisson_metrics.to_csv(paths.poisson_a3_metrics_csv, index=False)
    poisson_coefficients.to_csv(paths.poisson_a3_coefficients_csv, index=False)
    poisson_predictions.to_csv(paths.poisson_a3_predictions_csv, index=False)
    nb_metrics.to_csv(paths.negative_binomial_b3_metrics_csv, index=False)
    nb_coefficients.to_csv(paths.negative_binomial_b3_coefficients_csv, index=False)
    nb_predictions.to_csv(paths.negative_binomial_b3_predictions_csv, index=False)
    a3b3_comparison.to_csv(paths.a3_b3_comparison_csv, index=False)
    paths.a3_b3_note_md.write_text(note, encoding="utf-8")
    family_comparison.to_csv(paths.baseline_a2b2_vs_a3b3_comparison_csv, index=False)

    print(f"Poisson A3 metrics written to: {paths.poisson_a3_metrics_csv}")
    print(poisson_metrics.to_string(index=False))
    print(f"Negative Binomial B3 metrics written to: {paths.negative_binomial_b3_metrics_csv}")
    print(nb_metrics.to_string(index=False))
    print(f"A3/B3 comparison written to: {paths.a3_b3_comparison_csv}")


if __name__ == "__main__":
    main()
