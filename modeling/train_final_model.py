from __future__ import annotations

import argparse
import pickle
from pathlib import Path
import sys
from typing import Any

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from modeling.config import build_paths
from modeling.final_model_artifact import NEGATIVE_BINOMIAL_B4_ARTIFACT_RELATIVE_PATH
from modeling.run_global_model_pipeline import run_active_global_model_pipeline


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Train the active final ROAD-SAFETY model and ensure the final serialized artifact exists."
    )
    parser.add_argument("--force", action="store_true", help="Retrain the full active global pipeline.")
    return parser.parse_args()


def get_final_artifact_path(project_root: Path | None = None) -> Path:
    root = project_root or build_paths().project_root
    return root / NEGATIVE_BINOMIAL_B4_ARTIFACT_RELATIVE_PATH


def load_final_artifact(path: Path) -> Any:
    with open(path, "rb") as file:
        return pickle.load(file)


def train_final_model(*, force: bool = False) -> tuple[Any, Path]:
    artifact_path = get_final_artifact_path()

    if force or not artifact_path.exists():
        run_active_global_model_pipeline(force=force)

    if not artifact_path.exists():
        raise FileNotFoundError(
            f"Final model artifact was not generated as expected: {artifact_path}"
        )

    return load_final_artifact(artifact_path), artifact_path


def main() -> None:
    args = parse_args()
    artifact, artifact_path = train_final_model(force=args.force)
    model_name = getattr(artifact, "model_name", "unknown")
    print(f"[INFO] Final model artifact ready: {artifact_path}")
    print(f"[INFO] Loaded model_name = {model_name}")


if __name__ == "__main__":
    main()
