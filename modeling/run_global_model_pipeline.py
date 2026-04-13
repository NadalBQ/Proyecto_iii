from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


ACTIVE_GLOBAL_SCRIPTS = [
    "build_training_table.py",
    "build_training_table_with_controls.py",
    "build_lag_safe_features.py",
    "build_contextual_lag_safe_features.py",
    "build_exogenous_context_features.py",
    "train_baseline.py",
    "train_negative_binomial.py",
    "train_lag_safe_baselines.py",
    "train_contextual_baselines.py",
    "train_exogenous_baselines.py",
    "score_global_model.py",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run the active ROAD-SAFETY global modeling pipeline in the documented order."
    )
    parser.add_argument("--force", action="store_true", help="Pass --force to every stage.")
    return parser.parse_args()


def run_stage(script_path: Path, force: bool) -> None:
    command = [sys.executable, str(script_path)]
    if force:
        command.append("--force")

    print(f"[START] {script_path.name}")
    subprocess.run(command, check=True)
    print(f"[DONE] {script_path.name}")


def main() -> None:
    args = parse_args()
    modeling_dir = Path(__file__).resolve().parent

    for script_name in ACTIVE_GLOBAL_SCRIPTS:
        script_path = modeling_dir / script_name
        if not script_path.exists():
            raise FileNotFoundError(f"Missing active global script: {script_path}")
        run_stage(script_path, force=args.force)

    print("[INFO] Active global modeling pipeline completed.")


if __name__ == "__main__":
    main()
