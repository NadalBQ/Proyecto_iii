from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd

from src.model import (
    evaluate_model,
    get_default_model_path,
    load_model,
    predict,
    rebuild_parquet_from_raw,
    train_model,
    update_model,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="ROAD-SAFETY main orchestrator for the active final model."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    train_parser = subparsers.add_parser(
        "train",
        help="Train or refresh the active final model from the local final minable view.",
    )
    train_parser.add_argument("--force", action="store_true", help="Force a full retraining refresh.")
    train_parser.add_argument("--model-path", default=None, help="Optional custom destination for the serialized artifact.")

    update_parser = subparsers.add_parser(
        "update",
        help="Force retraining of the active final model from the local final minable view.",
    )
    update_parser.add_argument("--model-path", default=None, help="Optional custom destination for the serialized artifact.")

    rebuild_parser = subparsers.add_parser(
        "rebuild-parquet-from-raw",
        help="Rebuild the final minable parquet from local raw data and external inputs.",
    )
    rebuild_parser.add_argument("--force", action="store_true", help="Force a full raw rebuild refresh.")
    rebuild_parser.add_argument(
        "--parquet-path",
        default=None,
        help="Optional custom destination for the rebuilt parquet artifact.",
    )

    predict_parser = subparsers.add_parser("predict", help="Load a trained model and generate predictions.")
    predict_parser.add_argument("--input", required=True, help="Input dataframe path (.csv or .parquet).")
    predict_parser.add_argument("--output", default=None, help="Optional output path (.csv or .parquet).")
    predict_parser.add_argument("--model-path", default=None, help="Optional serialized artifact path.")

    evaluate_parser = subparsers.add_parser("evaluate", help="Evaluate a trained model on labelled data.")
    evaluate_parser.add_argument("--input", required=True, help="Input dataframe path (.csv or .parquet).")
    evaluate_parser.add_argument("--target-column", default="accident_count", help="Observed target column.")
    evaluate_parser.add_argument("--model-path", default=None, help="Optional serialized artifact path.")

    return parser.parse_args()


def load_frame(path: str | Path) -> pd.DataFrame:
    path = Path(path)
    suffix = path.suffix.lower()
    if suffix == ".csv":
        return pd.read_csv(path)
    if suffix == ".parquet":
        return pd.read_parquet(path)
    raise ValueError(f"Unsupported input format: {path}")


def write_frame(df: pd.DataFrame, path: str | Path) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    suffix = path.suffix.lower()
    if suffix == ".csv":
        df.to_csv(path, index=False)
        return
    if suffix == ".parquet":
        df.to_parquet(path, index=False)
        return
    raise ValueError(f"Unsupported output format: {path}")


def main() -> None:
    args = parse_args()

    try:
        if args.command == "train":
            model = train_model(path=args.model_path, force=args.force)
            print(f"[INFO] trained model_name = {getattr(model, 'model_name', 'unknown')}")
            print(f"[INFO] artifact_path = {Path(args.model_path) if args.model_path else get_default_model_path()}")
            return

        if args.command == "update":
            model = update_model(path=args.model_path)
            print(f"[INFO] updated model_name = {getattr(model, 'model_name', 'unknown')}")
            print(f"[INFO] artifact_path = {Path(args.model_path) if args.model_path else get_default_model_path()}")
            return

        if args.command == "rebuild-parquet-from-raw":
            parquet_path = rebuild_parquet_from_raw(path=args.parquet_path, force=args.force)
            print(f"[INFO] rebuilt final minable view = {parquet_path}")
            return

        model = load_model(args.model_path)
        df = load_frame(args.input)

        if args.command == "predict":
            y_pred = predict(model, df)
            output = df.copy()
            output["predicted_accident_count"] = y_pred
            if args.output:
                write_frame(output, args.output)
                print(f"[INFO] predictions written to {args.output}")
            else:
                print(output.head().to_string(index=False))
            return

        if args.command == "evaluate":
            if args.target_column not in df.columns:
                raise ValueError(f"Target column '{args.target_column}' not found in input frame.")
            X = df.drop(columns=[args.target_column])
            metrics = evaluate_model(model, X, df[args.target_column])
            for key, value in metrics.items():
                print(f"{key}={value}")
            return
    except Exception as exc:
        raise SystemExit(f"[ERROR] {exc}") from exc


if __name__ == "__main__":
    main()
