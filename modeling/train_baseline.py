from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import sys

import numpy as np
import pandas as pd
from sklearn.linear_model import PoissonRegressor
from sklearn.metrics import mean_poisson_deviance, mean_absolute_error, mean_squared_error

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from modeling.config import build_paths


MODEL_SAFE_DERIVED_FEATURES = {
    "log_edge_length_m": ["edge_length_m"],
    "analysis_year_offset": ["analysis_year"],
    "hour_sin": ["hour_sin"],
    "hour_cos": ["hour_cos"],
    "is_weekend_int": ["is_weekend"],
    "log1p_edge_accident_count_prior_total": ["edge_accident_count_prior_total"],
    "log1p_edge_bin_accident_count_prior": ["edge_bin_accident_count_prior"],
}
EXCLUDED_MODEL_SAFE_COLUMNS = {
    "edge_years_observed_prior": "excluded_from_first_poisson_because_zero_only_controls_use_sampled_support_windows",
}
TRAIN_YEARS = list(range(2016, 2023))
VALIDATION_YEARS = [2023]
TEST_YEARS = [2024]
POISSON_ALPHA = 1e-6
POISSON_MAX_ITER = 1000
OVERDISPERSION_THRESHOLD = 1.5


@dataclass(frozen=True)
class SplitMetrics:
    split: str
    rows_n: int
    positive_rows_n: int
    zero_rows_n: int
    zero_rows_pct: float
    target_mean: float
    target_variance: float
    predicted_mean: float
    mean_poisson_deviance: float
    mae: float
    rmse: float
    pearson_dispersion: float
    calibration_bins_n: int
    calibration_mean_abs_gap: float
    calibration_max_abs_gap: float


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train the first ROAD-SAFETY Poisson baseline.")
    parser.add_argument("--force", action="store_true", help="Retrain even if output artifacts already exist.")
    return parser.parse_args()


def validate_required_artifacts(paths) -> None:
    required = [paths.training_with_controls_parquet, paths.feature_registry_csv]
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        raise FileNotFoundError(f"Missing required artifacts for Poisson baseline: {missing}")


def load_training_table(paths) -> pd.DataFrame:
    return pd.read_parquet(paths.training_with_controls_parquet)


def validate_model_safe_sources(paths) -> None:
    registry = pd.read_csv(paths.feature_registry_csv)
    status_lookup = registry.set_index("column_name")["status"].to_dict()

    missing = []
    non_model_safe = []
    for source_columns in MODEL_SAFE_DERIVED_FEATURES.values():
        for column in source_columns:
            if column not in status_lookup:
                missing.append(column)
            elif status_lookup[column] != "model_safe":
                non_model_safe.append(column)

    if missing:
        raise ValueError(f"Feature registry is missing required source columns: {missing}")
    if non_model_safe:
        raise ValueError(f"Non-model-safe columns slipped into baseline feature set: {non_model_safe}")


def add_features(df: pd.DataFrame) -> pd.DataFrame:
    result = df.copy()
    result["log_edge_length_m"] = np.log(result["edge_length_m"])
    result["analysis_year_offset"] = result["analysis_year"] - min(TRAIN_YEARS)
    result["is_weekend_int"] = result["is_weekend"].astype(int)
    result["log1p_edge_accident_count_prior_total"] = np.log1p(result["edge_accident_count_prior_total"])
    result["log1p_edge_bin_accident_count_prior"] = np.log1p(result["edge_bin_accident_count_prior"])
    return result


def split_frames(df: pd.DataFrame) -> dict[str, pd.DataFrame]:
    return {
        "train": df.loc[df["analysis_year"].isin(TRAIN_YEARS)].copy(),
        "validation": df.loc[df["analysis_year"].isin(VALIDATION_YEARS)].copy(),
        "test": df.loc[df["analysis_year"].isin(TEST_YEARS)].copy(),
    }


def ensure_nonempty_splits(split_frames_dict: dict[str, pd.DataFrame]) -> None:
    empty = [name for name, frame in split_frames_dict.items() if frame.empty]
    if empty:
        raise ValueError(f"Temporal split produced empty partitions: {empty}")


def get_feature_matrix(df: pd.DataFrame) -> pd.DataFrame:
    feature_names = list(MODEL_SAFE_DERIVED_FEATURES.keys())
    matrix = df[feature_names].copy()
    if matrix.isna().any().any():
        na_columns = matrix.columns[matrix.isna().any()].tolist()
        raise ValueError(f"Missing values found in baseline feature matrix: {na_columns}")
    return matrix


def fit_poisson(train_df: pd.DataFrame) -> PoissonRegressor:
    X_train = get_feature_matrix(train_df)
    y_train = train_df["accident_count"].to_numpy()
    model = PoissonRegressor(alpha=POISSON_ALPHA, max_iter=POISSON_MAX_ITER)
    model.fit(X_train, y_train)
    return model


def assign_prediction_bins(predicted: pd.Series) -> pd.Series:
    if predicted.nunique() <= 1:
        return pd.Series(["bin_01"] * len(predicted), index=predicted.index, dtype="object")

    ranked = predicted.rank(method="first")
    quantiles = min(10, ranked.nunique())
    bins = pd.qcut(ranked, q=quantiles, labels=[f"bin_{i:02d}" for i in range(1, quantiles + 1)])
    return bins.astype(str)


def compute_calibration_metrics(frame: pd.DataFrame) -> tuple[int, float, float]:
    calibration = (
        frame.groupby("prediction_bin", as_index=False)
        .agg(
            rows_n=("accident_count", "size"),
            actual_mean=("accident_count", "mean"),
            predicted_mean=("predicted_accident_count", "mean"),
        )
    )
    calibration["abs_gap"] = (calibration["actual_mean"] - calibration["predicted_mean"]).abs()
    return (
        int(len(calibration)),
        float(calibration["abs_gap"].mean()),
        float(calibration["abs_gap"].max()),
    )


def compute_split_metrics(split_name: str, frame: pd.DataFrame) -> SplitMetrics:
    y_true = frame["accident_count"].to_numpy()
    y_pred = frame["predicted_accident_count"].to_numpy()
    p = len(MODEL_SAFE_DERIVED_FEATURES) + 1
    pearson_numerator = np.sum(((y_true - y_pred) ** 2) / np.clip(y_pred, 1e-9, None))
    pearson_dispersion = float(pearson_numerator / max(len(frame) - p, 1))
    calibration_bins_n, calibration_mean_abs_gap, calibration_max_abs_gap = compute_calibration_metrics(frame)

    return SplitMetrics(
        split=split_name,
        rows_n=int(len(frame)),
        positive_rows_n=int((frame["accident_count"] > 0).sum()),
        zero_rows_n=int((frame["accident_count"] == 0).sum()),
        zero_rows_pct=float(100 * (frame["accident_count"] == 0).mean()),
        target_mean=float(frame["accident_count"].mean()),
        target_variance=float(frame["accident_count"].var(ddof=0)),
        predicted_mean=float(frame["predicted_accident_count"].mean()),
        mean_poisson_deviance=float(mean_poisson_deviance(y_true, y_pred)),
        mae=float(mean_absolute_error(y_true, y_pred)),
        rmse=float(np.sqrt(mean_squared_error(y_true, y_pred))),
        pearson_dispersion=pearson_dispersion,
        calibration_bins_n=calibration_bins_n,
        calibration_mean_abs_gap=calibration_mean_abs_gap,
        calibration_max_abs_gap=calibration_max_abs_gap,
    )


def make_predictions(model: PoissonRegressor, split_frames_dict: dict[str, pd.DataFrame]) -> tuple[pd.DataFrame, pd.DataFrame]:
    prediction_frames = []
    metrics_records = []

    for split_name, frame in split_frames_dict.items():
        X = get_feature_matrix(frame)
        split_pred = model.predict(X)
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
        scored["predicted_accident_count"] = split_pred
        scored["prediction_bin"] = assign_prediction_bins(scored["predicted_accident_count"])
        prediction_frames.append(scored)
        metrics_records.append(compute_split_metrics(split_name, scored))

    predictions = pd.concat(prediction_frames, ignore_index=True)
    metrics = pd.DataFrame([record.__dict__ for record in metrics_records])
    metrics["overdispersion_flag"] = metrics["pearson_dispersion"] > OVERDISPERSION_THRESHOLD
    return predictions, metrics


def build_coefficients_frame(model: PoissonRegressor) -> pd.DataFrame:
    frame = pd.DataFrame(
        {
            "feature": list(MODEL_SAFE_DERIVED_FEATURES.keys()),
            "coefficient": model.coef_,
        }
    )
    frame["exp_coefficient"] = np.exp(frame["coefficient"])
    frame["absolute_coefficient"] = frame["coefficient"].abs()
    frame["rank_by_absolute_value"] = frame["absolute_coefficient"].rank(ascending=False, method="dense").astype(int)

    intercept_row = pd.DataFrame(
        [
            {
                "feature": "intercept",
                "coefficient": float(model.intercept_),
                "exp_coefficient": float(np.exp(model.intercept_)),
                "absolute_coefficient": abs(float(model.intercept_)),
                "rank_by_absolute_value": 0,
            }
        ]
    )
    return pd.concat([intercept_row, frame.sort_values("rank_by_absolute_value")], ignore_index=True)


def build_note(metrics: pd.DataFrame, coefficients: pd.DataFrame) -> str:
    train_metrics = metrics.loc[metrics["split"] == "train"].iloc[0]
    validation_metrics = metrics.loc[metrics["split"] == "validation"].iloc[0]
    test_metrics = metrics.loc[metrics["split"] == "test"].iloc[0]

    non_intercept = coefficients.loc[coefficients["feature"] != "intercept"].copy()
    strongest_positive = non_intercept.sort_values("coefficient", ascending=False).head(3)
    strongest_negative = non_intercept.sort_values("coefficient", ascending=True).head(3)

    nb_recommended = bool(train_metrics["pearson_dispersion"] > OVERDISPERSION_THRESHOLD)

    lines = [
        "# Poisson baseline note",
        "",
        "## Scope",
        "- Target: `accident_count`.",
        "- Split: train `2016-2022`, validation `2023`, test `2024`.",
        "- Features: only `model_safe` transformed predictors.",
        "- Explicitly excluded from this first baseline: `reference_only` columns and `edge_years_observed_prior`.",
        "- This baseline is not a routing weight and not a final graph cost.",
        "",
        "## Zero-only controls",
        "- The corrected training table adds stratified zero-only control edges sampled by `road_class x edge_length_bin`.",
        "- Control support windows are inherited from positive-history edges in the same stratum to avoid fabricating a full-network all-years panel.",
        "",
        "## Train diagnostics",
        f"- Train rows: `{int(train_metrics['rows_n'])}`.",
        f"- Train zero pct: `{train_metrics['zero_rows_pct']:.2f}%`.",
        f"- Train target mean/variance: `{train_metrics['target_mean']:.4f}` / `{train_metrics['target_variance']:.4f}`.",
        f"- Train Pearson dispersion: `{train_metrics['pearson_dispersion']:.4f}`.",
        f"- Over-dispersion threshold `{OVERDISPERSION_THRESHOLD:.1f}` exceeded: `{nb_recommended}`.",
        "",
        "## Validation/Test performance",
        f"- Validation mean Poisson deviance / MAE / RMSE: `{validation_metrics['mean_poisson_deviance']:.6f}` / `{validation_metrics['mae']:.6f}` / `{validation_metrics['rmse']:.6f}`.",
        f"- Test mean Poisson deviance / MAE / RMSE: `{test_metrics['mean_poisson_deviance']:.6f}` / `{test_metrics['mae']:.6f}` / `{test_metrics['rmse']:.6f}`.",
        "",
        "## Coefficient readout",
        "- Strongest positive coefficients:",
    ]

    for row in strongest_positive.itertuples(index=False):
        lines.append(f"  - `{row.feature}`: coef `{row.coefficient:.6f}`, exp(coef) `{row.exp_coefficient:.6f}`.")

    lines.append("- Strongest negative coefficients:")
    for row in strongest_negative.itertuples(index=False):
        lines.append(f"  - `{row.feature}`: coef `{row.coefficient:.6f}`, exp(coef) `{row.exp_coefficient:.6f}`.")

    lines.extend(
        [
            "",
            "## Interpretation guardrails",
            "- Signs and magnitudes are baseline associations under a log-link count model, not causal claims.",
            "- `historical_exposure_adjusted_score_prelim` and `dynamic_context_signal_prelim` stay out of this first model as predictors because they are not `model_safe` for temporal validation.",
        ]
    )
    return "\n".join(lines) + "\n"


def main() -> None:
    args = parse_args()
    paths = build_paths()
    validate_required_artifacts(paths)
    validate_model_safe_sources(paths)

    if paths.poisson_metrics_csv.exists() and not args.force:
        print(f"Poisson baseline metrics already exist: {paths.poisson_metrics_csv}")
        print("Use --force to retrain.")
        return

    df = load_training_table(paths)
    df = add_features(df)

    split_frames_dict = split_frames(df)
    ensure_nonempty_splits(split_frames_dict)

    model = fit_poisson(split_frames_dict["train"])
    predictions, metrics = make_predictions(model, split_frames_dict)
    coefficients = build_coefficients_frame(model)
    note = build_note(metrics, coefficients)

    predictions.to_csv(paths.poisson_predictions_csv, index=False)
    metrics.to_csv(paths.poisson_metrics_csv, index=False)
    coefficients.to_csv(paths.poisson_coefficients_csv, index=False)
    paths.poisson_note_md.write_text(note, encoding="utf-8")

    print(f"Poisson baseline metrics written to: {paths.poisson_metrics_csv}")
    print(metrics.to_string(index=False))


if __name__ == "__main__":
    main()
