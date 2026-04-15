from __future__ import annotations

import argparse
from pathlib import Path

from src.internal_pipeline.runners.common import (
    get_workspace_final_parquet_path,
    get_workspace_root,
    run_python_module,
)


BUILDER_MODULES = [
    "src.internal_pipeline.builders.build_training_table",
    "src.internal_pipeline.builders.build_training_table_with_controls",
    "src.internal_pipeline.builders.build_lag_safe_features",
    "src.internal_pipeline.builders.build_contextual_lag_safe_features",
    "src.internal_pipeline.builders.build_exogenous_context_features",
]


def validate_upstream_workspace(workspace_root: Path) -> None:
    required_inputs = [
        workspace_root / "outputs" / "data" / "accidentes_tabla_accidente_master.csv",
        workspace_root / "outputs" / "data" / "m8_road_network_edges.csv",
        workspace_root / "outputs" / "data" / "m9_accident_edge_matches.csv",
        workspace_root / "outputs" / "data" / "m10_edge_historical_aggregation.csv",
        workspace_root / "outputs" / "data" / "m11_historical_exposure_adjusted.csv",
        workspace_root / "outputs" / "data" / "m12_edge_context_dynamic_base.csv",
    ]
    missing = [str(path) for path in required_inputs if not path.exists()]
    if missing:
        raise RuntimeError(
            "The workspace does not contain the required upstream R artifacts for building the "
            f"final minable view: {missing}"
        )


def build_minable_view(*, force: bool = False, workspace_root: Path | None = None) -> Path:
    root = workspace_root or get_workspace_root()
    validate_upstream_workspace(root)

    for module_name in BUILDER_MODULES:
        run_python_module(module_name, force=force, workspace_root=root)

    final_parquet_path = get_workspace_final_parquet_path(root)
    if not final_parquet_path.exists():
        raise RuntimeError(
            "The builder pipeline finished without producing the expected final minable view at "
            f"'{final_parquet_path}'."
        )
    return final_parquet_path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run the internal Python builders that materialize the final minable view."
    )
    parser.add_argument("--force", action="store_true", help="Force rebuild on all builder stages.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    final_parquet_path = build_minable_view(force=args.force)
    print(f"final_parquet_path={final_parquet_path}")


if __name__ == "__main__":
    main()
