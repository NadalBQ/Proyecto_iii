from __future__ import annotations

import argparse
from pathlib import Path
import sys

import pandas as pd

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from modeling.config import build_paths


SOURCE_AUDIT_ROWS = [
    {
        "item_name": "deterministic_panel_calendar",
        "item_kind": "source",
        "source_type": "calendar",
        "source_path": "already embedded in modeling tables",
        "category": "usable_now_dynamic_exogenous",
        "source_present_in_repo": True,
        "true_dynamic_exogenous": False,
        "already_integrated": True,
        "spatial_granularity": "edge_id + temporal_bin_4h + is_weekend",
        "temporal_granularity": "deterministic calendar",
        "spatial_alignment_ready": True,
        "temporal_history_ready": True,
        "leak_safe_now": True,
        "can_build_new_a5_features_now": False,
        "primary_blocker": "already integrated; does not solve the richer dynamic-exogenous gap",
        "notes": "Useful baseline temporal context, but not the new true dynamic source needed after A4/B4.",
    },
    {
        "item_name": "municipal_traffic_tramos_csv",
        "item_kind": "source",
        "source_type": "traffic",
        "source_path": "bases de datos/estat-transit-temps-real-estado-trafico-tiempo-real.csv",
        "category": "not_usable_now",
        "source_present_in_repo": True,
        "true_dynamic_exogenous": True,
        "already_integrated": False,
        "spatial_granularity": "traffic tramo",
        "temporal_granularity": "snapshot-like / no historical series in repo",
        "spatial_alignment_ready": False,
        "temporal_history_ready": False,
        "leak_safe_now": False,
        "can_build_new_a5_features_now": False,
        "primary_blocker": "wrong geography plus no usable historical time series plus no edge alignment",
        "notes": "Header and coordinates point to Valencia-area geometry; M11 confirmed bbox overlap FALSE and 0 linked tramo-edge pairs.",
    },
    {
        "item_name": "geofabrik_osm_traffic_layers",
        "item_kind": "source",
        "source_type": "traffic",
        "source_path": "bases de datos/network/madrid-latest-free-shp/gis_osm_traffic*.shp",
        "category": "usable_with_processing",
        "source_present_in_repo": True,
        "true_dynamic_exogenous": False,
        "already_integrated": False,
        "spatial_granularity": "static traffic-control geometries",
        "temporal_granularity": "static",
        "spatial_alignment_ready": False,
        "temporal_history_ready": False,
        "leak_safe_now": False,
        "can_build_new_a5_features_now": False,
        "primary_blocker": "not dynamic by nature; would only support richer static context after geospatial joins",
        "notes": "Promising for static enrichment, not for true dynamic exogenous context.",
    },
    {
        "item_name": "standalone_weather_feed",
        "item_kind": "source",
        "source_type": "weather",
        "source_path": "not present in repo",
        "category": "not_usable_now",
        "source_present_in_repo": False,
        "true_dynamic_exogenous": True,
        "already_integrated": False,
        "spatial_granularity": "station/grid + timestamp",
        "temporal_granularity": "dynamic",
        "spatial_alignment_ready": False,
        "temporal_history_ready": False,
        "leak_safe_now": False,
        "can_build_new_a5_features_now": False,
        "primary_blocker": "missing source",
        "notes": "No standalone historical or operational weather feed exists in the repository.",
    },
    {
        "item_name": "event_calendar_feed",
        "item_kind": "source",
        "source_type": "calendar",
        "source_path": "not present in repo",
        "category": "not_usable_now",
        "source_present_in_repo": False,
        "true_dynamic_exogenous": True,
        "already_integrated": False,
        "spatial_granularity": "event + place + timestamp",
        "temporal_granularity": "dynamic/scheduled",
        "spatial_alignment_ready": False,
        "temporal_history_ready": False,
        "leak_safe_now": False,
        "can_build_new_a5_features_now": False,
        "primary_blocker": "missing source",
        "notes": "No event calendar with stable location and time coverage is available in the repository.",
    },
    {
        "item_name": "m11_edge_sensor_crosswalk",
        "item_kind": "source",
        "source_type": "traffic",
        "source_path": "outputs/data/m11_edge_sensor_crosswalk.csv",
        "category": "unsafe_due_to_leakage",
        "source_present_in_repo": True,
        "true_dynamic_exogenous": False,
        "already_integrated": False,
        "spatial_granularity": "edge + sensor",
        "temporal_granularity": "historical accident-backed",
        "spatial_alignment_ready": True,
        "temporal_history_ready": False,
        "leak_safe_now": False,
        "can_build_new_a5_features_now": False,
        "primary_blocker": "accident-backed construction",
        "notes": "Useful as methodological reference only; not a direct dynamic exogenous source.",
    },
    {
        "item_name": "m11_historical_exposure_adjusted",
        "item_kind": "source",
        "source_type": "traffic",
        "source_path": "outputs/data/m11_historical_exposure_adjusted.csv",
        "category": "unsafe_due_to_leakage",
        "source_present_in_repo": True,
        "true_dynamic_exogenous": False,
        "already_integrated": False,
        "spatial_granularity": "edge",
        "temporal_granularity": "historical score",
        "spatial_alignment_ready": True,
        "temporal_history_ready": False,
        "leak_safe_now": False,
        "can_build_new_a5_features_now": False,
        "primary_blocker": "target-derived historical score",
        "notes": "Not a true exogenous feed and cannot be used as a new dynamic predictor source.",
    },
    {
        "item_name": "m12_edge_context_dynamic_base",
        "item_kind": "source",
        "source_type": "traffic",
        "source_path": "outputs/data/m12_edge_context_dynamic_base.csv",
        "category": "unsafe_due_to_leakage",
        "source_present_in_repo": True,
        "true_dynamic_exogenous": False,
        "already_integrated": False,
        "spatial_granularity": "edge + temporal_bin_4h + is_weekend",
        "temporal_granularity": "historical accident-backed aggregation",
        "spatial_alignment_ready": True,
        "temporal_history_ready": False,
        "leak_safe_now": False,
        "can_build_new_a5_features_now": False,
        "primary_blocker": "full-period accident-backed aggregation",
        "notes": "Useful only as a blueprint of desired schema, never as a direct source for true dynamic exogenous context.",
    },
]


FUTURE_FEATURE_BLUEPRINT_ROWS = [
    {
        "item_name": "prior_mean_real_traffic_state_edge_bin_1y",
        "item_kind": "candidate_feature",
        "source_type": "traffic",
        "source_path": "requires historical dynamic traffic feed aligned to Madrid network",
        "category": "usable_with_processing",
        "source_present_in_repo": False,
        "true_dynamic_exogenous": True,
        "already_integrated": False,
        "spatial_granularity": "edge_id + temporal_bin_4h + is_weekend",
        "temporal_granularity": "lagged 1y summary",
        "spatial_alignment_ready": False,
        "temporal_history_ready": False,
        "leak_safe_now": False,
        "can_build_new_a5_features_now": False,
        "primary_blocker": "missing historical traffic feed and edge crosswalk",
        "notes": "Would aggregate only timestamps < analysis_year and keep support_n + fallback level.",
    },
    {
        "item_name": "prior_mean_real_traffic_state_edge_bin_recent_90d",
        "item_kind": "candidate_feature",
        "source_type": "traffic",
        "source_path": "requires timestamped traffic history",
        "category": "usable_with_processing",
        "source_present_in_repo": False,
        "true_dynamic_exogenous": True,
        "already_integrated": False,
        "spatial_granularity": "edge_id + temporal_bin_4h + is_weekend",
        "temporal_granularity": "lagged recent window",
        "spatial_alignment_ready": False,
        "temporal_history_ready": False,
        "leak_safe_now": False,
        "can_build_new_a5_features_now": False,
        "primary_blocker": "missing timestamped traffic history",
        "notes": "Better candidate for A5/B5 than further history-only accident lags once feed exists.",
    },
    {
        "item_name": "prior_weather_precipitation_edge_bin_1y",
        "item_kind": "candidate_feature",
        "source_type": "weather",
        "source_path": "requires historical weather feed",
        "category": "usable_with_processing",
        "source_present_in_repo": False,
        "true_dynamic_exogenous": True,
        "already_integrated": False,
        "spatial_granularity": "edge_id + temporal_bin_4h + is_weekend",
        "temporal_granularity": "lagged 1y summary",
        "spatial_alignment_ready": False,
        "temporal_history_ready": False,
        "leak_safe_now": False,
        "can_build_new_a5_features_now": False,
        "primary_blocker": "missing weather feed and spatial interpolation layer",
        "notes": "Would need station/grid -> edge assignment and timestamp history before A5/B5.",
    },
    {
        "item_name": "prior_event_intensity_edge_bin_1y",
        "item_kind": "candidate_feature",
        "source_type": "calendar",
        "source_path": "requires event calendar with locations",
        "category": "usable_with_processing",
        "source_present_in_repo": False,
        "true_dynamic_exogenous": True,
        "already_integrated": False,
        "spatial_granularity": "edge_id + temporal_bin_4h + is_weekend",
        "temporal_granularity": "lagged scheduled-event summary",
        "spatial_alignment_ready": False,
        "temporal_history_ready": False,
        "leak_safe_now": False,
        "can_build_new_a5_features_now": False,
        "primary_blocker": "missing event source",
        "notes": "Could complement traffic/weather once a spatially referenced event feed exists.",
    },
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Audit true dynamic exogenous context readiness for ROAD-SAFETY.")
    parser.add_argument("--force", action="store_true", help="Rebuild audit outputs even if they already exist.")
    return parser.parse_args()


def validate_required_inputs(paths) -> None:
    required = [
        paths.exogenous_feature_note_md,
        paths.a4_b4_note_md,
        paths.m11_historical_adjusted_csv,
        paths.m12_dynamic_base_csv,
    ]
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        raise FileNotFoundError(f"Missing required inputs for dynamic exogenous audit: {missing}")


def build_registry() -> pd.DataFrame:
    return pd.DataFrame(SOURCE_AUDIT_ROWS + FUTURE_FEATURE_BLUEPRINT_ROWS)


def build_summary(registry: pd.DataFrame) -> pd.DataFrame:
    source_rows = registry.loc[registry["item_kind"] == "source"].copy()
    summary_rows: list[dict] = []

    for category in [
        "usable_now_dynamic_exogenous",
        "usable_with_processing",
        "not_usable_now",
        "unsafe_due_to_leakage",
    ]:
        frame = source_rows.loc[source_rows["category"] == category]
        summary_rows.append(
            {
                "summary_scope": "category",
                "summary_key": category,
                "value": int(len(frame)),
                "notes": "Source count in this readiness bucket.",
            }
        )

    summary_rows.extend(
        [
            {
                "summary_scope": "overall",
                "summary_key": "new_true_dynamic_source_usable_now",
                "value": False,
                "notes": "No new true dynamic exogenous feed in the repo is currently edge-ready and leak-safe.",
            },
            {
                "summary_scope": "overall",
                "summary_key": "calendar_already_integrated_only",
                "value": True,
                "notes": "Deterministic calendar exists and is already in the model; it is not the missing richer dynamic source.",
            },
            {
                "summary_scope": "overall",
                "summary_key": "best_candidate_source_type",
                "value": "traffic",
                "notes": "Traffic remains the best next source type if a real Madrid historical feed becomes available.",
            },
            {
                "summary_scope": "overall",
                "summary_key": "leak_safe_dynamic_integration_feasible_now",
                "value": False,
                "notes": "Feasible blueprint exists, but not with the current repo-only sources.",
            },
            {
                "summary_scope": "overall",
                "summary_key": "future_a5_b5_justified_now",
                "value": False,
                "notes": "A5/B5 should wait for actual dynamic exogenous ingestion beyond the already integrated calendar.",
            },
            {
                "summary_scope": "overall",
                "summary_key": "training_table_with_true_dynamic_exogenous_features_created",
                "value": False,
                "notes": "No parquet created because no true dynamic exogenous source is operational now.",
            },
        ]
    )

    for row in source_rows.itertuples(index=False):
        summary_rows.append(
            {
                "summary_scope": "source",
                "summary_key": row.item_name,
                "value": row.category,
                "notes": row.primary_blocker,
            }
        )

    return pd.DataFrame(summary_rows)


def build_note(registry: pd.DataFrame) -> str:
    sources = registry.loc[registry["item_kind"] == "source"].copy()
    candidates = registry.loc[registry["item_kind"] == "candidate_feature"].copy()

    usable_now = sources.loc[sources["category"] == "usable_now_dynamic_exogenous", "item_name"].tolist()
    usable_processing = sources.loc[sources["category"] == "usable_with_processing", "item_name"].tolist()
    not_usable = sources.loc[sources["category"] == "not_usable_now", "item_name"].tolist()
    unsafe = sources.loc[sources["category"] == "unsafe_due_to_leakage", "item_name"].tolist()

    note_lines = [
        "# Dynamic Exogenous Feature Note",
        "",
        "## Scope",
        "- This phase hardens the Python environment and audits true dynamic exogenous context readiness.",
        "- It does not train A5/B5.",
        "- It does not change target, split or the current B4 baseline.",
        "",
        "## Environment status",
        "- Modeling dependencies are now pinned in `modeling/requirements.txt`.",
        "- Minimal execution instructions are documented in `modeling/README.md`.",
        "",
        "## Source classification",
        f"- usable_now_dynamic_exogenous: {', '.join(usable_now) if usable_now else 'none'}",
        f"- usable_with_processing: {', '.join(usable_processing) if usable_processing else 'none'}",
        f"- not_usable_now: {', '.join(not_usable) if not_usable else 'none'}",
        f"- unsafe_due_to_leakage: {', '.join(unsafe) if unsafe else 'none'}",
        "",
        "## Practical reading",
        "- The only temporal context currently usable now is the deterministic calendar already integrated in the modeling tables.",
        "- There is no new richer true dynamic exogenous source in the repo that is both edge-ready and leak-safe.",
        "- The municipal `temps-real` CSV is not usable now: its coordinates point to Valencia-area geometry, it has no usable historical series in-repo, and M11 already showed zero tramo-edge links against the canonical Madrid network.",
        "- OSM `gis_osm_traffic*.shp` layers are useful only as static auxiliary traffic-control context, not as true dynamic feeds.",
        "- Weather and event feeds are simply absent from the repository.",
        "",
        "## Leak-safe integration design for future A5/B5",
        "- Modeling unit should stay `edge_id + analysis_year + temporal_bin_4h + is_weekend` for comparability with A/B through A4/B4.",
        "- Raw ingestion unit for true dynamic context should be `source_observation_id + observation_timestamp + source_location/source_geometry`.",
        "- Any future dynamic source must first be aligned to the canonical network or to a documented intermediate unit with a versioned crosswalk.",
        "- For a row with `analysis_year = Y`, every dynamic feature must aggregate only observations with timestamps `< Y-01-01`.",
        "- Recommended windows: prior 1y, recent 90d/180d, and support counts, always with explicit missing/support flags and fallback levels.",
        "- Recommended fallback hierarchy once a real feed exists: `edge_id + temporal_bin_4h + is_weekend` -> `edge_id + temporal_bin_4h` -> `road_class + temporal_bin_4h + is_weekend` -> `global + temporal_bin_4h + is_weekend`.",
        "",
        "## Why no new parquet was created",
        "- A new `training_table_with_true_dynamic_exogenous_features.parquet` was intentionally not created.",
        "- There is no source in the repo today that would let us build true dynamic exogenous features without inventing data or reusing accident-backed outputs.",
        "",
        "## Best next step",
        "- Prepare external ingestion of a real Madrid traffic feed with timestamp history and stable geometry or sensor metadata.",
        "- If traffic ingestion is not immediately available, the next-best exogenous stream is weather, but it is also absent today.",
        "",
        "## Candidate future feature families",
    ]

    for row in candidates.itertuples(index=False):
        note_lines.append(f"- `{row.item_name}` from `{row.source_type}`: {row.primary_blocker}.")

    note_lines.extend(
        [
            "",
            "## Guardrails",
            "- `m11_*` and `m12_*` outputs remain references or blueprints, not direct exogenous predictors.",
            "- This phase closes environment + dynamic-exogenous readiness, not model training and not routing.",
        ]
    )
    return "\n".join(note_lines) + "\n"


def main() -> None:
    args = parse_args()
    paths = build_paths()
    validate_required_inputs(paths)

    outputs_exist = all(
        path.exists()
        for path in [
            paths.dynamic_exogenous_feature_registry_csv,
            paths.dynamic_exogenous_feature_summary_csv,
            paths.dynamic_exogenous_feature_note_md,
        ]
    )
    if outputs_exist and not args.force:
        print("Dynamic exogenous audit artifacts already exist. Use --force to rebuild.")
        return

    registry = build_registry()
    summary = build_summary(registry)
    note = build_note(registry)

    registry.to_csv(paths.dynamic_exogenous_feature_registry_csv, index=False)
    summary.to_csv(paths.dynamic_exogenous_feature_summary_csv, index=False)
    paths.dynamic_exogenous_feature_note_md.write_text(note, encoding="utf-8")

    print(f"registry_rows_n={len(registry)}")
    print(f"summary_rows_n={len(summary)}")
    print("training_table_with_true_dynamic_exogenous_features_created=False")


if __name__ == "__main__":
    main()
