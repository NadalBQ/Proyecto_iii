# ROAD-SAFETY

ROAD-SAFETY is a university project focused on risk-aware urban routing. The repository does not stop at descriptive analysis: the end goal is a technical pipeline that can support accident/context integration, road-segment risk logic, graph edge weighting, and later routing/API layers.

This GitHub-oriented version is intentionally lightweight. It keeps the code, documentation, and lightweight validation artifacts needed to understand and reproduce the project structure, while leaving out raw data and heavy regenerable outputs.

## Current state

The repository currently contains two clearly separated modeling lines:

- `global_default_model`: the main Python modeling branch for the global risk pipeline.
- `pilot_traffic_model`: an opt-in pilot branch restricted to Madrid official traffic data for 2024 months `1, 4, 7, 10`.

These are not equivalent branches. The pilot traffic branch is intentionally encapsulated and must not be interpreted as global traffic coverage.

## Repository structure

### `R/`
Core R milestone scripts used for the earlier preparation and risk-logic phases of the project. This includes ingestion, accident-level cleaning, exploratory PCA work, canonical network preparation, accident-to-edge matching, historical aggregation, exposure/context layers, and the preliminary combined-risk work completed before the current scoring architecture.

### `scripts/traffic/`
Separate R scripts for the Madrid traffic 2024 pilot line. This branch is intentionally isolated from the global model. It covers:

- pilot traffic ingestion and aggregation,
- sensor overlap and coverage audits,
- traffic-to-accident integration,
- traffic-to-model-unit integration,
- pilot training table construction,
- and pilot comparative modeling/refinement.

### `modeling/`
Main Python modeling package. This is the current home of the production-oriented modeling architecture, including:

- global training-table builders,
- lag-safe/contextual/exogenous feature builders,
- baseline comparisons,
- global scoring preparation,
- and the encapsulated pilot traffic feature block.

See [modeling/README.md](modeling/README.md) for Python environment setup and the main entry points.

### `outputs/`
Project outputs and audit artifacts. In the shareable repo, the intention is to keep only lightweight files that explain the work:

- `*_summary.csv`
- `*_comparison.csv`
- `*_metrics.csv`
- `*_coefficients.csv`
- `*_contract.csv`
- `*_registry.csv`
- `*_validation_summary.csv`
- `*_note.md`
- `*_branch_summary.csv`
- `*_gating_rules.csv`

Heavy predictions, parquet files, plotting outputs, and other large regenerable artifacts are excluded.

### `data/`
The full project uses raw and processed data locally, but those datasets are intentionally not included in the lightweight GitHub repo when they are heavy or externally sourced.

### `bases de datos/`
Local external data staging area used during development. This folder is treated as a local workspace, not as part of the lightweight shareable repository.

## What is intentionally not uploaded

To keep the repository serious but lightweight, the following are excluded from the GitHub-ready version:

- raw datasets,
- external source dumps and shapefiles,
- heavy processed CSVs,
- large parquet model inputs,
- row-level prediction dumps,
- rendered HTML exports,
- temporary/editor/system files.

This is deliberate. Reproducibility here is based on code plus lightweight validation artifacts, not on bundling gigabytes of data into the repository.

## How to read this repo without the raw data

If you are reviewing the project without the local datasets:

1. Start with [PROJECT_BRIEF.md](PROJECT_BRIEF.md) for the project objective.
2. Read [AGENTS.md](AGENTS.md) for methodological and execution constraints.
3. Review [PLANS.md](PLANS.md) to understand milestone-by-milestone implementation.
4. Inspect `R/` for the preparation phases and `scripts/traffic/` for the traffic pilot line.
5. Inspect `modeling/` for the global modeling pipeline and the separation between global and pilot traffic branches.
6. Use the lightweight files in `outputs/` to verify what was built, validated, and selected.

## Global vs pilot traffic branch

The repository keeps these branches separate on purpose:

- `global_default_model` remains the default modeling/scoring branch.
- `pilot_traffic_model` is restricted to the 2024 pilot traffic scope and must be treated as optional.

The pilot traffic feature block does not silently activate inside the global branch. That separation is part of the repository design and should be preserved.

## Execution notes

- R work is designed for VS Code / terminal execution via `Rscript`.
- Python work is configured from the project root using the instructions in [modeling/README.md](modeling/README.md).
- This repository is prepared for sharing and review, not as a data-complete archive.

## What this repository is ready for

This cleaned version is suitable for:

- project review and evaluation,
- collaboration on code and methodology,
- continuing the global modeling/scoring pipeline,
- and later controlled extension toward edge weighting and routing.

It is not meant to be interpreted as a fully data-complete public release of all raw inputs.
