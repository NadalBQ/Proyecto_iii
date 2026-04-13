from __future__ import annotations

import argparse
from pathlib import Path
import sys

import numpy as np
import pandas as pd
from patsy import dmatrices
import statsmodels.formula.api as smf
import statsmodels.api as sm
from sklearn.metrics import mean_absolute_error, mean_poisson_deviance, mean_squared_error

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from modeling.config import build_paths
from modeling.pilot_traffic_block import (
    PILOT_TRAFFIC_BASE_FEATURE_COLUMNS,
    PILOT_TRAFFIC_BLOCK_COLUMNS,
    PILOT_TRAFFIC_CATEGORICAL_BASE_FEATURE_COLUMNS,
    PILOT_TRAFFIC_KEY_COLUMNS,
    PILOT_TRAFFIC_ALLOWED_MONTHS,
    PILOT_TRAFFIC_ALLOWED_YEAR,
    assert_validated,
    validate_pilot_transformed_input,
)

PILOT_SPLITS = ("train", "validation", "test")


def build_formula(feature_columns: list[str]) -> str:
    terms = [
        f"C({column})" if column in PILOT_TRAFFIC_CATEGORICAL_BASE_FEATURE_COLUMNS else column
        for column in feature_columns
    ]
    return "target ~ " + " + ".join(terms)


BASE_FEATURE_FORMULA = build_formula(PILOT_TRAFFIC_BASE_FEATURE_COLUMNS)
TRAFFIC_D_FEATURE_FORMULA = build_formula(PILOT_TRAFFIC_BASE_FEATURE_COLUMNS + PILOT_TRAFFIC_BLOCK_COLUMNS)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train pilot 2024 Python baselines with and without traffic_D_transformed.")
    parser.add_argument("--force", action="store_true", help="Retrain even if output artifacts already exist.")
    return parser.parse_args()


def safe_pct(num: int, den: int) -> float:
    if den == 0:
        return float("nan")
    return round(num / den * 100.0, 4)


def poisson_deviance_mean(y_true: np.ndarray, y_pred: np.ndarray) -> float:
    if y_true.size == 0:
        return float("nan")
    return float(mean_poisson_deviance(y_true, np.clip(y_pred, 1e-12, None)))


def pearson_dispersion(y_true: np.ndarray, y_pred: np.ndarray, df_resid: float | None = None) -> float:
    if y_true.size == 0:
        return float("nan")
    mu = np.clip(y_pred, 1e-12, None)
    pearson_resid = (y_true - mu) / np.sqrt(mu)
    denom = df_resid if df_resid is not None and df_resid > 0 else y_true.size
    return float(np.sum(np.square(pearson_resid)) / denom)


def calibration_gap_decile(y_true: np.ndarray, y_pred: np.ndarray) -> float:
    if y_true.size == 0:
        return float("nan")
    pred = np.clip(y_pred, 1e-12, None)
    frame = pd.DataFrame({"actual": y_true, "pred": pred})
    try:
        frame["bin"] = pd.qcut(frame["pred"], q=10, duplicates="drop")
    except ValueError:
        return float(abs(frame["actual"].mean() - frame["pred"].mean()))
    grouped = frame.groupby("bin", observed=True).agg(actual_mean=("actual", "mean"), pred_mean=("pred", "mean"))
    return float(np.mean(np.abs(grouped["actual_mean"] - grouped["pred_mean"])))


def check_full_rank(formula: str, train_df: pd.DataFrame, label: str) -> None:
    _, x_matrix = dmatrices(formula, data=train_df, return_type="dataframe")
    rank = np.linalg.matrix_rank(x_matrix.to_numpy())
    if rank < x_matrix.shape[1]:
        raise ValueError(
            f"Rank-deficient design matrix for {label}: rank={rank}, columns={x_matrix.shape[1]}"
        )


def build_metrics(pred_df: pd.DataFrame, pred_col: str, model_label: str, df_resid: float) -> pd.DataFrame:
    scope_frames = {
        "overall": pred_df,
        "covered_only": pred_df.loc[pred_df["traffic_coverage_flag"] == "covered"].copy(),
        "positive_only": pred_df.loc[pred_df["pilot_accident_count"] > 0].copy(),
        "zero_only": pred_df.loc[pred_df["pilot_accident_count"] == 0].copy(),
    }
    rows: list[dict[str, object]] = []
    for split_name in PILOT_SPLITS:
        split_df = pred_df.loc[pred_df["split"] == split_name].copy()
        split_scope_frames = {
            "overall": split_df,
            "covered_only": split_df.loc[split_df["traffic_coverage_flag"] == "covered"].copy(),
            "positive_only": split_df.loc[split_df["pilot_accident_count"] > 0].copy(),
            "zero_only": split_df.loc[split_df["pilot_accident_count"] == 0].copy(),
        }
        for scope_name, scope_df in split_scope_frames.items():
            y_true = scope_df["pilot_accident_count"].to_numpy(dtype=float)
            y_pred = scope_df[pred_col].to_numpy(dtype=float)
            rows.append(
                {
                    "model_label": model_label,
                    "family": "poisson",
                    "split": split_name,
                    "scope": scope_name,
                    "n_rows": int(scope_df.shape[0]),
                    "target_mean": float(scope_df["pilot_accident_count"].mean()) if not scope_df.empty else float("nan"),
                    "target_variance": float(scope_df["pilot_accident_count"].var(ddof=1)) if scope_df.shape[0] > 1 else float("nan"),
                    "zero_pct": safe_pct(int((scope_df["pilot_accident_count"] == 0).sum()), int(scope_df.shape[0])),
                    "mean_poisson_deviance": poisson_deviance_mean(y_true, y_pred),
                    "mae": float(mean_absolute_error(y_true, y_pred)) if scope_df.shape[0] > 0 else float("nan"),
                    "rmse": float(np.sqrt(mean_squared_error(y_true, y_pred))) if scope_df.shape[0] > 0 else float("nan"),
                    "pearson_dispersion": pearson_dispersion(y_true, y_pred, df_resid if scope_name == "overall" else None),
                    "calibration_mean_abs_gap_decile": calibration_gap_decile(y_true, y_pred),
                }
            )
    return pd.DataFrame(rows)


def main() -> None:
    args = parse_args()
    paths = build_paths()

    output_paths = [
        paths.pilot_python_baseline_no_traffic_metrics_csv,
        paths.pilot_python_baseline_with_traffic_metrics_csv,
        paths.pilot_python_traffic_comparison_csv,
        paths.pilot_python_traffic_note_md,
    ]
    if all(path.exists() for path in output_paths) and not args.force:
        print("Pilot Python traffic artifacts already exist. Use --force to rebuild.")
        return

    required = [
        paths.pilot_traffic_d_input_parquet,
        paths.pilot_traffic_feature_contract_csv,
        paths.project_root / "outputs" / "traffic_pilot_traffic_feature_spec_comparison.csv",
        paths.project_root / "outputs" / "traffic_pilot_refined_model_note.md",
    ]
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        raise FileNotFoundError(f"Missing required pilot artifacts: {missing}")

    df = pd.read_parquet(paths.pilot_traffic_d_input_parquet)
    validation_df = validate_pilot_transformed_input(df)
    assert_validated(validation_df, "Pilot traffic transformed model input")
    if set(df["analysis_year"].unique()) != {PILOT_TRAFFIC_ALLOWED_YEAR}:
        raise ValueError("Pilot traffic D-transformed input is not restricted to 2024.")
    if set(sorted(df["month"].unique().tolist())) != set(PILOT_TRAFFIC_ALLOWED_MONTHS):
        raise ValueError("Pilot traffic D-transformed input is not restricted to months 1,4,7,10.")

    df["road_class_group"] = pd.Categorical(df["road_class_group"]).remove_unused_categories()

    train_df = df.loc[df["split"] == "train"].copy()
    validation_df = df.loc[df["split"] == "validation"].copy()
    test_df = df.loc[df["split"] == "test"].copy()
    if train_df.empty or validation_df.empty or test_df.empty:
        raise ValueError("Pilot split is empty for one of train/validation/test.")

    check_full_rank(BASE_FEATURE_FORMULA, train_df, "pilot_no_traffic")
    check_full_rank(TRAFFIC_D_FEATURE_FORMULA, train_df, "pilot_with_traffic_d")

    no_traffic_model = smf.glm(formula=BASE_FEATURE_FORMULA, data=train_df, family=sm.families.Poisson()).fit()
    with_traffic_model = smf.glm(formula=TRAFFIC_D_FEATURE_FORMULA, data=train_df, family=sm.families.Poisson()).fit()

    pred_base = df.loc[:, [
        *PILOT_TRAFFIC_KEY_COLUMNS,
        "split", "pilot_accident_count", "pilot_row_type", "traffic_coverage_flag", "traffic_missing_reason",
    ]].copy()
    pred_no = pred_base.copy()
    pred_no["model_label"] = "pilot_no_traffic"
    pred_no["pred_poisson"] = no_traffic_model.predict(df)

    pred_with = pred_base.copy()
    pred_with["model_label"] = "pilot_with_traffic_d"
    pred_with["pred_poisson"] = with_traffic_model.predict(df)

    if pred_no["pred_poisson"].isna().any() or pred_with["pred_poisson"].isna().any():
        raise ValueError("NA predictions detected in Python pilot traffic baselines.")

    no_metrics = build_metrics(pred_no, "pred_poisson", "pilot_no_traffic", float(no_traffic_model.df_resid))
    with_metrics = build_metrics(pred_with, "pred_poisson", "pilot_with_traffic_d", float(with_traffic_model.df_resid))

    comparison = with_metrics.merge(
        no_metrics[
            [
                "split",
                "scope",
                "n_rows",
                "target_mean",
                "target_variance",
                "zero_pct",
                "mean_poisson_deviance",
                "mae",
                "rmse",
                "pearson_dispersion",
                "calibration_mean_abs_gap_decile",
            ]
        ].rename(
            columns={
                "mean_poisson_deviance": "mean_poisson_deviance_no_traffic",
                "mae": "mae_no_traffic",
                "rmse": "rmse_no_traffic",
                "pearson_dispersion": "pearson_dispersion_no_traffic",
                "calibration_mean_abs_gap_decile": "calibration_gap_no_traffic",
            }
        ),
        on=["split", "scope", "n_rows", "target_mean", "target_variance", "zero_pct"],
        how="left",
        validate="one_to_one",
    )
    comparison = comparison.rename(
        columns={
            "mean_poisson_deviance": "mean_poisson_deviance_with_traffic",
            "mae": "mae_with_traffic",
            "rmse": "rmse_with_traffic",
            "pearson_dispersion": "pearson_dispersion_with_traffic",
            "calibration_mean_abs_gap_decile": "calibration_gap_with_traffic",
        }
    )
    comparison["delta_mean_poisson_deviance"] = (
        comparison["mean_poisson_deviance_with_traffic"] - comparison["mean_poisson_deviance_no_traffic"]
    )
    comparison["delta_mae"] = comparison["mae_with_traffic"] - comparison["mae_no_traffic"]
    comparison["delta_rmse"] = comparison["rmse_with_traffic"] - comparison["rmse_no_traffic"]
    comparison["delta_pearson_dispersion"] = (
        comparison["pearson_dispersion_with_traffic"] - comparison["pearson_dispersion_no_traffic"]
    )
    comparison["delta_calibration_gap"] = (
        comparison["calibration_gap_with_traffic"] - comparison["calibration_gap_no_traffic"]
    )

    r_comparison = pd.read_csv(paths.project_root / "outputs" / "traffic_pilot_traffic_feature_spec_comparison.csv")
    r_d = r_comparison.loc[r_comparison["model_spec"] == "traffic_D_transformed"].copy()
    r_d = r_d[
        [
            "split",
            "scope",
            "delta_mean_poisson_deviance",
            "delta_mae",
            "delta_rmse",
            "delta_calibration_gap",
        ]
    ].rename(
        columns={
            "delta_mean_poisson_deviance": "r_delta_mean_poisson_deviance",
            "delta_mae": "r_delta_mae",
            "delta_rmse": "r_delta_rmse",
            "delta_calibration_gap": "r_delta_calibration_gap",
        }
    )
    comparison = comparison.merge(r_d, on=["split", "scope"], how="left", validate="many_to_one")
    comparison["r_python_delta_gap_mean_poisson_deviance"] = (
        comparison["delta_mean_poisson_deviance"] - comparison["r_delta_mean_poisson_deviance"]
    )
    comparison["r_python_delta_gap_rmse"] = comparison["delta_rmse"] - comparison["r_delta_rmse"]
    comparison["r_python_delta_gap_calibration"] = (
        comparison["delta_calibration_gap"] - comparison["r_delta_calibration_gap"]
    )
    comparison["aligned_with_r_sign"] = np.where(
        np.sign(comparison["delta_mean_poisson_deviance"]) == np.sign(comparison["r_delta_mean_poisson_deviance"]),
        True,
        False,
    )

    predictions = pd.concat([pred_no, pred_with], ignore_index=True)

    no_metrics.to_csv(paths.pilot_python_baseline_no_traffic_metrics_csv, index=False)
    with_metrics.to_csv(paths.pilot_python_baseline_with_traffic_metrics_csv, index=False)
    comparison.to_csv(paths.pilot_python_traffic_comparison_csv, index=False)

    note_lines = [
        "# Pilot Python Traffic Consolidation Note",
        "",
        "## Scope",
        "- Pilot-only consolidation restricted to analysis year 2024 and months 1, 4, 7 and 10.",
        "- Unit kept fixed: `edge_id + analysis_year + month + temporal_bin_4h + is_weekend`.",
        "- Target kept fixed: `pilot_accident_count`.",
        "- Split reproduced exactly from R: train months 1 and 4, validation month 7, test month 10.",
        "",
        "## Traffic contract carried into Python",
        "- `traffic_covered_flag`",
        "- `traffic_missing_due_to_no_time_flag`",
        "- `traffic_intensidad_wins_log`",
        "- `traffic_ocupacion_wins`",
        "- `log1p_traffic_support_n`",
        "- `log1p_traffic_n_observations`",
        "- `traffic_vmed_mean` excluded from the main Python spec.",
        "",
        "## Translation R -> Python",
        "- Train-covered medians reused as the imputation rule for traffic columns.",
        "- Winsorization thresholds computed on Python train covered rows using the type-8 equivalent (`median_unbiased`).",
        "- Same Poisson family, same split and same baseline/base block.",
        "",
        "## Dispersion check",
        f"- Train mean: {train_df['target'].mean():.6f}.",
        f"- Train variance: {train_df['target'].var(ddof=1):.6f}.",
        f"- Train Pearson dispersion without traffic: {float(no_metrics.loc[(no_metrics['split'] == 'train') & (no_metrics['scope'] == 'overall'), 'pearson_dispersion'].iloc[0]):.6f}.",
        f"- Train Pearson dispersion with traffic: {float(with_metrics.loc[(with_metrics['split'] == 'train') & (with_metrics['scope'] == 'overall'), 'pearson_dispersion'].iloc[0]):.6f}.",
        "- Negative Binomial not reopened in this phase.",
        "",
        "## Alignment against R",
        f"- Validation overall Python delta deviance: {float(comparison.loc[(comparison['split'] == 'validation') & (comparison['scope'] == 'overall'), 'delta_mean_poisson_deviance'].iloc[0]):.6f}.",
        f"- Validation overall R delta deviance: {float(comparison.loc[(comparison['split'] == 'validation') & (comparison['scope'] == 'overall'), 'r_delta_mean_poisson_deviance'].iloc[0]):.6f}.",
        f"- Test overall Python delta deviance: {float(comparison.loc[(comparison['split'] == 'test') & (comparison['scope'] == 'overall'), 'delta_mean_poisson_deviance'].iloc[0]):.6f}.",
        f"- Test overall R delta deviance: {float(comparison.loc[(comparison['split'] == 'test') & (comparison['scope'] == 'overall'), 'r_delta_mean_poisson_deviance'].iloc[0]):.6f}.",
        "",
        "## Interpretation boundary",
        "- This result is pilot-only and does not validate the full 2016-2024 model.",
        "- It does not imply readiness for routing or final edge weighting.",
        "- It only promotes `traffic_D_transformed` as a live candidate for deeper integration in the Python modeling pipeline.",
    ]
    paths.pilot_python_traffic_note_md.write_text("\n".join(note_lines), encoding="utf-8")
    predictions.to_csv(paths.pilot_python_traffic_predictions_csv, index=False)

    print(f"Created pilot Python no-traffic metrics: {paths.pilot_python_baseline_no_traffic_metrics_csv}")
    print(f"Created pilot Python with-traffic metrics: {paths.pilot_python_baseline_with_traffic_metrics_csv}")
    print(f"Created pilot Python comparison: {paths.pilot_python_traffic_comparison_csv}")
    print(f"Created pilot Python note: {paths.pilot_python_traffic_note_md}")


if __name__ == "__main__":
    main()
