from __future__ import annotations

import argparse
from pathlib import Path

from pipeline.runners.common import (
    ensure_command_available,
    get_repo_root,
    get_workspace_root,
    run_command,
    stage_local_inputs,
)


def get_upstream_runner_path() -> Path:
    return get_repo_root() / "pipeline" / "upstream_r" / "run_global_upstream_min.R"


def validate_upstream_outputs(workspace_root: Path) -> None:
    required_outputs = [
        workspace_root / "outputs" / "data" / "accidentes_tabla_accidente_master.csv",
        workspace_root / "outputs" / "data" / "m8_road_network_edges.csv",
        workspace_root / "outputs" / "data" / "m9_accident_edge_matches.csv",
        workspace_root / "outputs" / "data" / "m10_edge_historical_aggregation.csv",
        workspace_root / "outputs" / "data" / "m11_historical_exposure_adjusted.csv",
        workspace_root / "outputs" / "data" / "m12_edge_context_dynamic_base.csv",
    ]
    missing = [str(path) for path in required_outputs if not path.exists()]
    if missing:
        raise RuntimeError(
            "The upstream R stage did not generate all required intermediate artifacts: "
            f"{missing}"
        )


def run_upstream_r(*, force: bool = False, workspace_root: Path | None = None) -> Path:
    root = stage_local_inputs(workspace_root=workspace_root)
    rscript_path = ensure_command_available("Rscript")
    runner_path = get_upstream_runner_path()

    if not runner_path.exists():
        raise RuntimeError(f"Missing upstream R runner: '{runner_path}'.")

    command = [rscript_path, str(runner_path), "--project-dir", str(root)]
    if force:
        command.append("--force")

    run_command(command, cwd=get_repo_root())
    validate_upstream_outputs(root)
    return root


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run the internal R upstream pipeline against the compatibility workspace."
    )
    parser.add_argument("--force", action="store_true", help="Force refresh on the cached R stages.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    workspace_root = run_upstream_r(force=args.force)
    print(f"workspace_root={workspace_root}")


if __name__ == "__main__":
    main()
