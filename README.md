# ROAD-SAFETY

This branch exposes the **final validated model layer** of the project in a
group-repo-friendly structure.

## Public surface

The intended public integration path is:

- [`main.py`](./main.py)
- [`src/model.py`](./src/model.py)

This is the surface another developer should use.

## Active final model

- **model**: `negative_binomial_b4`
- **target**: `accident_count`
- **final parquet**: `artifacts/training_table_with_exogenous_context_features.parquet`
- **final model artifact**: `artifacts/negative_binomial_b4.pkl`

This branch does not change the validated model choice or the methodological
definition of the target.

## Public commands

```powershell
python main.py rebuild-parquet-from-raw
python main.py train
python main.py update
python main.py predict --input <csv-or-parquet>
python main.py evaluate --input <csv-or-parquet> --target-column accident_count
```

## Public model API

`src/model.py` exposes:

- `load_model(path=None)`
- `save_model(model, path=None)`
- `rebuild_parquet_from_raw(path=None, force=False)`
- `train_model(path=None, force=False)`
- `update_model(path=None)`
- `predict(model, X)`
- `evaluate_model(model, X, y_true)`

## Internal implementation

The repo keeps two internal layers behind the public API:

- `src/internal_model/`
- `pipeline/`

`src/internal_model/` owns the final model artifact and the final
`parquet -> pkl` training bridge.

`pipeline/` owns the recovered raw-data rebuild flow:

- `pipeline/upstream_r/`: raw -> upstream CSV intermediates
- `pipeline/builders/`: upstream CSV intermediates -> final parquet
- `pipeline/runners/`: internal orchestration and compatibility workspace

## Three distinct flows

### 1. Raw -> final parquet

This is the new explicit command:

```powershell
python main.py rebuild-parquet-from-raw
```

It requires local raw and external inputs:

- `data/raw/accidentes_con_trafico_final.csv`
- `data/external/traffic/estat-transit-temps-real-estado-trafico-tiempo-real.csv`

Optional local cache:

- `data/external/network/madrid-latest-free.shp.zip`

These paths are **local-only conventions**. The repo does not commit a `data/`
directory by default; each developer creates it locally only when they want to
run the raw rebuild flow.

If the local network zip is not present, the upstream R stage may download it.

The rebuild uses an internal disposable workspace at:

- `pipeline/.workspace/`

The final published output remains:

- `artifacts/training_table_with_exogenous_context_features.parquet`

### 2. Final parquet -> final model artifact

These commands do **not** rebuild from raw data:

```powershell
python main.py train
python main.py update
```

They require:

- `artifacts/training_table_with_exogenous_context_features.parquet`

Behavior:

- `train` loads the existing serialized artifact when it already exists
- otherwise it retrains `negative_binomial_b4` from the local final minable view
- `update` forces retraining from that same parquet

### 3. Final model artifact -> predictions / metrics

These commands require:

- `artifacts/negative_binomial_b4.pkl`

Commands:

```powershell
python main.py predict --input <csv-or-parquet>
python main.py evaluate --input <csv-or-parquet> --target-column accident_count
```

## Local heavy artifacts not bundled by default

This repo keeps only the folders and contracts for the heavy runtime artifacts.
The files themselves are expected to be added or downloaded locally when
needed:

- `artifacts/negative_binomial_b4.pkl`
- `artifacts/training_table_with_exogenous_context_features.parquet`

Public command preconditions:

- `rebuild-parquet-from-raw` requires local raw data, local external traffic data, and `Rscript`
- `train` and `update` require the local final parquet
- `predict` and `evaluate` require the local `.pkl`

## Current limitation of this branch

This branch now supports rebuilding the final parquet from raw data, but that
flow still depends on local external files and an R environment. The repo does
not bundle:

- raw accident CSV
- external traffic CSV
- optional local network zip cache
- the final parquet
- the final `.pkl`

The architectural goal remains clear separation:

- public API: `main.py` and `src/model.py`
- internal model layer: `src/internal_model/`
- internal data pipeline: `pipeline/`
