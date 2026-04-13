# ROAD-SAFETY

ROAD-SAFETY is a university project focused on risk-aware urban routing. The active code in this repository now keeps only the global modeling line needed to go from raw accident data to a final global baseline and a preliminary scoring output.

This is a lightweight, reproducible project skeleton. Heavy raw data and large regenerable outputs are not bundled, but the active pipeline is documented so another person can rerun it locally if they place the required inputs in the expected paths.

## Active pipeline goal

The active minimum pipeline covers three blocks:

1. **Data preparation**
   - clean and audit the accident CSV
   - deduplicate exact duplicate rows
   - build an accident-level master table
   - prepare the canonical Madrid road network
   - match accidents to edges
   - build historical, exposure-adjusted, and dynamic edge context layers

2. **Materialising the minable view**
   - build a single final modeling table:
     - `outputs/modeling/training_table_with_exogenous_context_features.parquet`

3. **Model building and scoring**
   - train the global baseline comparison chain
   - keep the selected final global baseline:
     - `negative_binomial_b4`
   - generate a preliminary global scoring output for later edge-weighting work

## External inputs required

To rerun the active global pipeline from zero, these inputs must be available locally:

1. `accidentes_con_trafico_final.csv`
   - expected location: **project root**

2. `bases de datos/estat-transit-temps-real-estado-trafico-tiempo-real.csv`
   - expected location: **`bases de datos/`**

3. Madrid OSM road network source for M8
   - preferred automatic path: M8 downloads Geofabrik if internet is available
   - expected local fallback zip if there is no internet:
     - `bases de datos/network/madrid-latest-free.shp.zip`

## Repository structure

### `R/`
Active upstream R modules for the global line:
- ingestion and profiling
- exact deduplication / expediente audit
- accident-level master table
- canonical network preparation
- accident-to-edge matching
- edge historical aggregation
- edge exposure crosswalk
- edge dynamic context

### `modeling/`
Active Python global modeling pipeline:
- training-table builders
- lag-safe/contextual/exogenous feature builders
- baseline training scripts
- global scoring logic
- environment and execution notes

See [modeling/README.md](modeling/README.md) for the Python-side commands.

### `outputs/`
Lightweight audit artifacts kept for traceability. Heavy parquet/prediction artifacts are intended to be regenerated locally.

### `data/`
Local raw/processed data staging area. It is not treated as a shareable lightweight artifact set.

### `bases de datos/`
Local external data staging area used by the active global line.

## Minimal execution order

### 1. Install minimal R packages

If `Rscript` is in `PATH`:

```powershell
Rscript R\install_packages_min.R
```

If `Rscript` is not in `PATH`, call it from the local R installation, for example:

```powershell
& "C:\Program Files\R\R-4.4.2\bin\Rscript.exe" R\install_packages_min.R
```

### 2. Run the active global upstream in R

```powershell
Rscript R\run_global_upstream_min.R
```

Optional full refresh:

```powershell
Rscript R\run_global_upstream_min.R --force
```

This runner executes only the active global line:
- `01_ingesta_y_perfilado.R`
- `02_duplicados_y_expedientes.R`
- `03_tabla_accidente.R`
- `08_preparacion_red_canonica.R`
- `09_accidente_edge_matching.R`
- `10_edge_historical_aggregation.R`
- `11_edge_exposure_crosswalk.R`
- `12_edge_dynamic_context.R`

Operational note about the upstream R line:
- `M9` (`09_accidente_edge_matching.R`) is currently the most expensive upstream phase.
- It performs the real accident-to-edge spatial matching against the canonical network.
- On a full run it can take **several hours**, especially before it writes final `m9_*` outputs.
- Long runtime in `M9` should not be interpreted automatically as a crash; it is the dominant heavy spatial step in the active global line.

### 3. Set up Python

```powershell
py -3 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r modeling\requirements.txt
```

### 4. Run the active global modeling chain

Recommended single runner:

```powershell
python modeling\run_global_model_pipeline.py --force
```

Equivalent explicit sequence:

```powershell
python modeling\build_training_table.py --force
python modeling\build_training_table_with_controls.py --force
python modeling\build_lag_safe_features.py --force
python modeling\build_contextual_lag_safe_features.py --force
python modeling\build_exogenous_context_features.py --force
python modeling\train_baseline.py --force
python modeling\train_negative_binomial.py --force
python modeling\train_lag_safe_baselines.py --force
python modeling\train_contextual_baselines.py --force
python modeling\train_exogenous_baselines.py --force
python modeling\score_global_model.py --force
```

## Final active outputs

Main minable view:
- `outputs/modeling/training_table_with_exogenous_context_features.parquet`

Selected global baseline:
- `negative_binomial_b4`

Main global scoring output:
- `outputs/modeling/global_scoring_output_prelim.csv`

Important note:
- `predicted_risk_score_prelim` is a preliminary model-derived score for later system integration.
- It is **not** the final routing edge weight.

## Lightweight outputs kept in the shared repo

Only a small set of lightweight artifacts is intentionally kept visible in the shared repository. They exist to explain the active line, not to replace a local rerun.

Upstream validation evidence:
- `outputs/tables/m1_ingesta_summary.csv`
- `outputs/tables/m2_expediente_summary.csv`
- `outputs/tables/m3_validation_summary.csv`
- `outputs/tables/m8_network_validation_summary.csv`
- `outputs/tables/m9_matching_validation_summary.csv`
- `outputs/tables/m10_validation_summary.csv`
- `outputs/tables/m11_validation_summary.csv`
- `outputs/tables/m12_validation_summary.csv`

Minable-view and feature-spec traceability:
- `outputs/modeling/tables/training_table_summary.csv`
- `outputs/modeling/tables/training_feature_registry.csv`
- `outputs/modeling/exogenous_feature_registry.csv`
- `outputs/modeling/exogenous_feature_summary.csv`
- `outputs/modeling/exogenous_feature_note.md`

Final model and scoring traceability:
- `outputs/modeling/global_model_branch_summary.csv`
- `outputs/modeling/negative_binomial_b4_metrics.csv`
- `outputs/modeling/negative_binomial_b4_coefficients.csv`
- `outputs/modeling/global_scoring_architecture_note.md`
- `outputs/modeling/global_scoring_contract.csv`
- `outputs/modeling/global_scoring_validation_summary.csv`

Heavy data outputs, row-level predictions, parquet artifacts, local raw data, and archived historical material are intentionally excluded from the shared repo.

## M8 network dependency note

M8 requires a Madrid OSM extract from Geofabrik.

- If internet is available, M8 can download:
  - `https://download.geofabrik.de/europe/spain/madrid-latest-free.shp.zip`
- If internet is not available, place this zip beforehand at:
  - `bases de datos/network/madrid-latest-free.shp.zip`

If neither internet nor the local zip is available, the upstream global line will stop in M8.

## Active project boundary

The active project is intended to run **only** with:
- the files currently present outside `_archive_local/`
- the external inputs listed above
- the R/Python environments documented in this README and in `modeling/README.md`

`_archive_local/` is treated as historical material and is **not** part of the active functional pipeline.

## What is intentionally not included

This repository is not a data-complete release. It intentionally avoids bundling:
- large raw datasets
- large processed CSVs
- row-level prediction dumps
- heavy parquet artifacts
- rendered auxiliary exports

The active project is meant to be rerun locally with the required inputs, not shipped as a full raw-data archive.
