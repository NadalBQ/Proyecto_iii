from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Iterable


PIPELINE_ROOT_ENV_VAR = "ROAD_SAFETY_PIPELINE_ROOT"

RAW_INPUT_RELATIVE_PATH = Path("data") / "raw" / "accidentes_con_trafico_final.csv"
TRAFFIC_INPUT_RELATIVE_PATH = (
    Path("data") / "external" / "traffic" / "estat-transit-temps-real-estado-trafico-tiempo-real.csv"
)
NETWORK_ZIP_RELATIVE_PATH = (
    Path("data") / "external" / "network" / "madrid-latest-free.shp.zip"
)

WORKSPACE_RELATIVE_PATH = Path("src") / "internal_pipeline" / ".workspace"
WORKSPACE_RAW_INPUT_RELATIVE_PATH = Path("accidentes_con_trafico_final.csv")
WORKSPACE_TRAFFIC_INPUT_RELATIVE_PATH = (
    Path("bases de datos") / "estat-transit-temps-real-estado-trafico-tiempo-real.csv"
)
WORKSPACE_NETWORK_ZIP_RELATIVE_PATH = (
    Path("bases de datos") / "network" / "madrid-latest-free.shp.zip"
)

WORKSPACE_FINAL_PARQUET_RELATIVE_PATH = (
    Path("outputs") / "modeling" / "training_table_with_exogenous_context_features.parquet"
)
PUBLISHED_FINAL_PARQUET_RELATIVE_PATH = (
    Path("artifacts") / "training_table_with_exogenous_context_features.parquet"
)


def get_repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def get_workspace_root() -> Path:
    return get_repo_root() / WORKSPACE_RELATIVE_PATH


def get_default_published_parquet_path() -> Path:
    return get_repo_root() / PUBLISHED_FINAL_PARQUET_RELATIVE_PATH


def get_workspace_final_parquet_path(workspace_root: Path | None = None) -> Path:
    root = workspace_root or get_workspace_root()
    return root / WORKSPACE_FINAL_PARQUET_RELATIVE_PATH


def get_local_raw_input_path() -> Path:
    return get_repo_root() / RAW_INPUT_RELATIVE_PATH


def get_local_traffic_input_path() -> Path:
    return get_repo_root() / TRAFFIC_INPUT_RELATIVE_PATH


def get_local_network_zip_path() -> Path:
    return get_repo_root() / NETWORK_ZIP_RELATIVE_PATH


def ensure_workspace_structure(workspace_root: Path | None = None) -> Path:
    root = workspace_root or get_workspace_root()
    required_dirs = [
        root,
        root / "bases de datos",
        root / "bases de datos" / "network",
        root / "outputs",
        root / "outputs" / "data",
        root / "outputs" / "tables",
        root / "outputs" / "plots",
        root / "outputs" / "modeling",
        root / "outputs" / "modeling" / "data",
        root / "outputs" / "modeling" / "tables",
        root / "data",
        root / "data" / "processed",
    ]
    for directory in required_dirs:
        directory.mkdir(parents=True, exist_ok=True)
    return root


def ensure_required_local_inputs() -> tuple[Path, Path]:
    raw_input_path = get_local_raw_input_path()
    traffic_input_path = get_local_traffic_input_path()

    missing = [str(path) for path in (raw_input_path, traffic_input_path) if not path.exists()]
    if missing:
        raise RuntimeError(
            "Missing required local raw rebuild inputs: "
            f"{missing}. Expected files are staged under data/raw/ and data/external/traffic/."
        )

    return raw_input_path, traffic_input_path


def stage_local_inputs(*, workspace_root: Path | None = None) -> Path:
    root = ensure_workspace_structure(workspace_root)
    raw_input_path, traffic_input_path = ensure_required_local_inputs()
    network_zip_path = get_local_network_zip_path()

    _copy_file(raw_input_path, root / WORKSPACE_RAW_INPUT_RELATIVE_PATH)
    _copy_file(traffic_input_path, root / WORKSPACE_TRAFFIC_INPUT_RELATIVE_PATH)
    if network_zip_path.exists():
        _copy_file(network_zip_path, root / WORKSPACE_NETWORK_ZIP_RELATIVE_PATH)

    return root


def _copy_file(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def promote_workspace_parquet(
    *, destination: Path | None = None, workspace_root: Path | None = None
) -> Path:
    workspace_parquet_path = get_workspace_final_parquet_path(workspace_root)
    if not workspace_parquet_path.exists():
        raise RuntimeError(
            "Raw rebuild finished without producing the expected final parquet at "
            f"'{workspace_parquet_path}'."
        )

    target_path = destination or get_default_published_parquet_path()
    target_path.parent.mkdir(parents=True, exist_ok=True)
    if workspace_parquet_path.resolve() != target_path.resolve():
        shutil.copy2(workspace_parquet_path, target_path)
    return target_path


def build_pipeline_env(*, workspace_root: Path | None = None) -> dict[str, str]:
    env = os.environ.copy()
    env[PIPELINE_ROOT_ENV_VAR] = str((workspace_root or get_workspace_root()).resolve())
    return env


def ensure_command_available(command_name: str) -> str:
    resolved = shutil.which(command_name)
    if not resolved:
        raise RuntimeError(
            f"Required command '{command_name}' is not available in PATH."
        )
    return resolved


def run_command(
    command: Iterable[str], *, cwd: Path | None = None, env: dict[str, str] | None = None
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        list(command),
        cwd=str(cwd) if cwd is not None else None,
        env=env,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            "Command failed.\n"
            f"Command: {' '.join(command)}\n"
            f"Exit code: {result.returncode}\n"
            f"STDOUT:\n{result.stdout}\n"
            f"STDERR:\n{result.stderr}"
        )
    return result


def run_python_module(
    module_name: str, *, force: bool = False, workspace_root: Path | None = None
) -> subprocess.CompletedProcess[str]:
    command = [sys.executable, "-m", module_name]
    if force:
        command.append("--force")
    return run_command(
        command,
        cwd=get_repo_root(),
        env=build_pipeline_env(workspace_root=workspace_root),
    )
