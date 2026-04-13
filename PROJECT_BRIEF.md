# ROAD-SAFETY — Project Brief

## Overview

ROAD-SAFETY is a university project focused on building a risk-aware urban routing system.

The idea is not to return only the shortest or fastest route, but a route that also accounts for road safety risk.

The most realistic technical output is an API with structured outputs, likely JSON-based. A web frontend is not the current priority.

## System goal

The system is intended to:
1. integrate accident data with contextual variables,
2. analyze which factors are associated with higher road risk,
3. build a street / segment risk variable or risk index,
4. model the street network as a graph,
5. assign risk-based weights to graph edges,
6. and compute routes that optimize not only time/distance but also safety.

## Main technical components

- data integration
- data cleaning and normalization
- exploratory analysis
- risk variable / score design
- geospatial graph modeling
- edge weighting
- routing logic
- API-oriented output design

## Technologies currently relevant

- Python for the main system
- OSMnx and NetworkX for road graph and routing
- scikit-learn if needed for modeling
- R for exploratory statistical analysis and visualization
- Visual Studio Code as current working environment

## User role in the project

Main responsibilities currently include:
- descriptive analysis,
- visual / communication design,
- geospatial technical framing,
- and risk-variable design.

Therefore, outputs should connect analytical findings to the future routing system.

## Current dataset situation

The main CSV contains accident data with traffic/context variables.

Important issues already identified:
- the data is not cleanly one-row-per-accident,
- a single accident identifier / expediente may appear multiple times,
- exact duplicate rows exist,
- especially in recent data,
- so raw row counts are not valid accident counts,
- the correct counting unit is the accident / expediente,
- `vmed` is quite noisy,
- `intensidad` and `ocupacion` look more usable,
- some categorical labels need normalization,
- and comparability across years may be affected by coding changes around 2019.

## Current analytical focus

Current focus:
- exploratory study of redundancy and overlap among contextual/numeric variables,
- especially to avoid blind weighting in the future risk index.

PCA is being used as:
- an exploratory tool,
- a redundancy detector,
- a way to discover latent dimensions,
- and a support for more defensible grouping / weighting decisions.

PCA is NOT being used as:
- a causal model,
- a final definition of road risk,
- or a direct source of “correct” risk weights.

## Variables currently considered for exploratory PCA-style work

Reasonable candidates:
- intensidad
- ocupacion
- vmed only if sufficiently cleaned
- cyclical hour encoding (sin/cos)
- es_festivo
- is_weekend
- other numeric/contextual variables with clear meaning

Variables that should NOT be pushed into PCA blindly:
- IDs
- accident identifiers
- raw coordinates without a clear methodological purpose
- categorical accident type encoded as fake numeric values
- arbitrary category codings

## Near-term objective

Build a sound exploratory pipeline in R that:
1. checks duplicates,
2. checks accident-level aggregation,
3. evaluates candidate variables,
4. prepares a clean analysis table,
5. runs interpretable exploratory PCA-style analysis,
6. and extracts conclusions useful for future risk-score design.

## Long-term project direction

Use exploratory findings to inform:
- grouping of variables into interpretable blocks,
- avoidance of double-counting,
- possible synthetic factors,
- and later translation of risk logic into graph edge weights for routing.