from __future__ import annotations

import argparse
import shutil
from pathlib import Path
from typing import Union

from src.internal_pipeline.runners.build_minable_view import build_minable_view
from src.internal_pipeline.runners.common import (
    get_default_published_parquet_path,
    get_workspace_root,
    promote_workspace_parquet,
)
from src.internal_pipeline.runners.run_upstream_r import run_upstream_r


def _resolve_destination(path: Union[str, Path, None] = None) -> Path:
    return Path(path) if path is not None else get_default_published_parquet_path()


def rebuild_parquet_from_raw(*, path: Union[str, Path, None] = None, force: bool = False) -> Path:
    destination = _resolve_destination(path)

    if destination.exists() and not force:
        return destination

    workspace_root = get_workspace_root()
    run_upstream_r(force=force, workspace_root=workspace_root)
    workspace_parquet_path = build_minable_view(force=force, workspace_root=workspace_root)

    if destination.resolve() != workspace_parquet_path.resolve():
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(workspace_parquet_path, destination)
        return destination

    return promote_workspace_parquet(destination=destination, workspace_root=workspace_root)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Rebuild the final minable parquet from raw local inputs."
    )
    parser.add_argument(
        "--parquet-path",
        default=None,
        help="Optional custom destination for the rebuilt parquet artifact.",
    )
    parser.add_argument("--force", action="store_true", help="Force a full raw rebuild refresh.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    rebuilt_path = rebuild_parquet_from_raw(path=args.parquet_path, force=args.force)
    print(f"parquet_path={rebuilt_path}")


if __name__ == "__main__":
    main()
