from __future__ import annotations

import argparse
from pathlib import Path
import sys

import numpy as np
import pandas as pd

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from src.internal_pipeline.builders.config import build_paths


ROAD_CLASS_HIERARCHY = {
    "motorway": 8,
    "motorway_link": 7,
    "trunk": 7,
    "trunk_link": 6,
    "primary": 6,
    "primary_link": 5,
    "secondary": 5,
    "secondary_link": 4,
    "tertiary": 4,
    "tertiary_link": 3,
    "residential": 3,
    "unclassified": 3,
    "service": 2,
    "living_street": 1,
}

USABLE_NOW_SOURCES = [
    {
        "item_name": "m8_road_network_edges.csv",
        "source": "outputs/data/m8_road_network_edges.csv",
        "definition": "Canonical edge-level OSM attributes already exported to CSV.",
        "granularity": "edge",
        "temporal_scope": "static",
        "source_category": "usable_now_exogenous",
        "status_note": "Usable now as the main static exogenous source.",
    },
    {
        "item_name": "m8_road_network_nodes.csv",
        "source": "outputs/data/m8_road_network_nodes.csv",
        "definition": "Canonical node-level topology exported to CSV.",
        "granularity": "node",
        "temporal_scope": "static",
        "source_category": "usable_now_exogenous",
        "status_note": "Usable now to derive edge endpoint topology.",
    },
    {
        "item_name": "training_table_calendar_panel",
        "source": "outputs/modeling/training_table_with_contextual_lag_safe_features.parquet",
        "definition": "Deterministic panel calendar fields already present in the modeling table.",
        "granularity": "edge_id + analysis_year + temporal_bin_4h + is_weekend",
        "temporal_scope": "temporal",
        "source_category": "usable_now_exogenous",
        "status_note": "Usable now because these fields are deterministic and leak-safe.",
    },
]

USABLE_WITH_PROCESSING_SOURCES = [
    {
        "item_name": "geofabrik_osm_traffic_layers",
        "source": "bases de datos/network/madrid-latest-free-shp/gis_osm_traffic*.shp",
        "definition": "Static OSM traffic-control layers such as crossings, tunnel mouths or related road objects.",
        "granularity": "line / polygon / point depending on layer",
        "temporal_scope": "static",
        "source_category": "usable_with_processing",
        "status_note": "Promising, but current Python environment lacks geospatial stack for spatial joins.",
    },
    {
        "item_name": "geofabrik_osm_landuse_buildings_pois_transport",
        "source": "bases de datos/network/madrid-latest-free-shp/gis_osm_{landuse,buildings,pois,transport,pofw,places}*.shp",
        "definition": "Static built-environment and activity layers from the same OSM extract.",
        "granularity": "point / polygon",
        "temporal_scope": "static",
        "source_category": "usable_with_processing",
        "status_note": "Promising for POI density, land-use mix or transit proximity once spatial preprocessing is available.",
    },
]

NOT_USABLE_NOW_SOURCES = [
    {
        "item_name": "municipal_traffic_tramos_csv",
        "source": "bases de datos/estat-transit-temps-real-estado-trafico-tiempo-real.csv",
        "definition": "Municipal line layer of traffic tramos.",
        "granularity": "traffic tramo",
        "temporal_scope": "dynamic",
        "source_category": "not_usable_now",
        "status_note": "M11 already showed bbox mismatch with the canonical network and zero linked pairs.",
    },
    {
        "item_name": "communications_cartography_csv",
        "source": "bases de datos/cartografia-base-comunicacions-comunicaciones.csv",
        "definition": "Communications cartography, not clearly aligned with road-risk modeling.",
        "granularity": "mixed cartographic elements",
        "temporal_scope": "static",
        "source_category": "not_usable_now",
        "status_note": "Not road-risk-specific and not cleanly parseable in the current workflow.",
    },
    {
        "item_name": "dgt_road_type_catalog_metadata",
        "source": "bases de datos/a05003423-clasificacion-del-tipos-de-vias-de-la-direccion-general-de-trafico-dgt-de-espana-istac-cl_dgt_tipos_vias.csv",
        "definition": "Dataset catalog metadata, not direct edge-level data.",
        "granularity": "catalog metadata",
        "temporal_scope": "static",
        "source_category": "not_usable_now",
        "status_note": "Not directly usable as modeling context features.",
    },
    {
        "item_name": "standalone_weather_feed",
        "source": "not present in repo",
        "definition": "Operational weather feed aligned to the modeling unit.",
        "granularity": "edge + time",
        "temporal_scope": "dynamic",
        "source_category": "not_usable_now",
        "status_note": "No standalone leak-safe weather source is currently available in the repository.",
    },
]

UNSAFE_SOURCES = [
    {
        "item_name": "m11_edge_sensor_crosswalk",
        "source": "outputs/data/m11_edge_sensor_crosswalk.csv",
        "definition": "Edge-sensor crosswalk supported by matched accidents.",
        "granularity": "edge + sensor",
        "temporal_scope": "historical",
        "source_category": "unsafe_due_to_leakage",
        "status_note": "Accident-backed and therefore not usable as a direct predictor block.",
    },
    {
        "item_name": "m11_edge_exposure_baseline",
        "source": "outputs/data/m11_edge_exposure_baseline.csv",
        "definition": "Exposure proxy baseline built from accident-supported evidence.",
        "granularity": "edge",
        "temporal_scope": "historical",
        "source_category": "unsafe_due_to_leakage",
        "status_note": "Useful as analytical reference, not as a direct exogenous predictor.",
    },
    {
        "item_name": "m11_historical_exposure_adjusted",
        "source": "outputs/data/m11_historical_exposure_adjusted.csv",
        "definition": "Exposure-adjusted historical score built from historical accidents.",
        "granularity": "edge",
        "temporal_scope": "historical",
        "source_category": "unsafe_due_to_leakage",
        "status_note": "A score derived from historical outcomes; not a direct exogenous predictor.",
    },
    {
        "item_name": "m12_edge_context_dynamic_base",
        "source": "outputs/data/m12_edge_context_dynamic_base.csv",
        "definition": "Accident-backed dynamic/contextual base.",
        "granularity": "edge + temporal_bin_4h + is_weekend",
        "temporal_scope": "historical",
        "source_category": "unsafe_due_to_leakage",
        "status_note": "Useful only after leak-safe reconstruction, never as a direct full-period predictor block.",
    },
    {
        "item_name": "accident_backed_meteorology_in_m12",
        "source": "outputs/data/m12_edge_context_dynamic_base.csv",
        "definition": "Meteorology observations attached through accident-backed context support.",
        "granularity": "edge + temporal_bin_4h + is_weekend",
        "temporal_scope": "historical",
        "source_category": "unsafe_due_to_leakage",
        "status_note": "Not a standalone exogenous weather feed.",
    },
]


FEATURE_SPECS = [
    ("exog_road_class_hierarchy_score", "road_network_edges", "edge", "static", "Hierarchical score derived from OSM road_class."),
    ("exog_road_class_is_link_flag", "road_network_edges", "edge", "static", "Flag for *_link road classes."),
    ("exog_road_class_is_major_flag", "road_network_edges", "edge", "static", "Flag for motorway/trunk/primary classes and links."),
    ("exog_road_class_is_local_flag", "road_network_edges", "edge", "static", "Flag for residential/service/living_street/unclassified classes."),
    ("exog_has_road_ref_flag", "road_network_edges", "edge", "static", "Flag for edges with a populated road reference."),
    ("exog_has_street_name_flag", "road_network_edges", "edge", "static", "Flag for edges with a populated street name."),
    ("exog_maxspeed_kph", "road_network_edges", "edge", "static", "Parsed maxspeed in km/h; zero treated as missing."),
    ("exog_maxspeed_missing_flag", "road_network_edges", "edge", "static", "Flag for missing/zero maxspeed."),
    ("exog_maxspeed_kph_imputed_by_road_class", "road_network_edges", "edge", "static", "Maxspeed imputed by road_class median and then global median."),
    ("exog_maxspeed_ge70_flag", "road_network_edges", "edge", "static", "Flag for fast roads with maxspeed >= 70 km/h."),
    ("exog_maxspeed_le30_flag", "road_network_edges", "edge", "static", "Flag for low-speed roads with maxspeed <= 30 km/h."),
    ("exog_oneway_code_t_flag", "road_network_edges", "edge", "static", "Flag for raw oneway code T."),
    ("exog_oneway_code_b_flag", "road_network_edges", "edge", "static", "Flag for raw oneway code B."),
    ("exog_bridge_flag", "road_network_edges", "edge", "static", "Flag for bridge edges."),
    ("exog_tunnel_flag", "road_network_edges", "edge", "static", "Flag for tunnel edges."),
    ("exog_layer_abs", "road_network_edges", "edge", "static", "Absolute vertical layer offset from OSM."),
    ("exog_nonzero_layer_flag", "road_network_edges", "edge", "static", "Flag for non-zero vertical layer."),
    ("exog_from_node_degree", "road_network_nodes", "edge", "static", "Degree of the from-node."),
    ("exog_to_node_degree", "road_network_nodes", "edge", "static", "Degree of the to-node."),
    ("exog_node_degree_mean", "road_network_nodes", "edge", "static", "Mean endpoint degree."),
    ("exog_node_degree_max", "road_network_nodes", "edge", "static", "Max endpoint degree."),
    ("exog_node_degree_min", "road_network_nodes", "edge", "static", "Min endpoint degree."),
    ("exog_edge_touches_dead_end_flag", "road_network_nodes", "edge", "static", "Flag for edges touching a degree-1 node."),
    ("exog_edge_touches_intersection_flag", "road_network_nodes", "edge", "static", "Flag for edges touching a node with degree >= 3."),
    ("exog_edge_between_intersections_flag", "road_network_nodes", "edge", "static", "Flag for edges whose both endpoints have degree >= 3."),
    ("exog_orientation_sin", "road_network_geometry", "edge", "static", "Sine of the edge orientation angle derived from endpoints."),
    ("exog_orientation_cos", "road_network_geometry", "edge", "static", "Cosine of the edge orientation angle derived from endpoints."),
    ("exog_distance_from_network_centroid_km", "road_network_geometry", "edge", "static", "Distance from edge midpoint to canonical network centroid."),
    ("exog_source_way_segment_count", "road_network_edges", "edge", "static", "Number of canonical edge segments derived from the same source_osm_id."),
    ("exog_source_way_total_length_m", "road_network_edges", "edge", "static", "Total canonical edge length derived from the same source_osm_id."),
    ("exog_source_way_mean_segment_length_m", "road_network_edges", "edge", "static", "Mean canonical segment length for the same source_osm_id."),
    ("exog_temporal_is_night_flag", "panel_calendar", "edge + temporal_bin_4h + is_weekend", "temporal", "Flag for night bins 00_03 or 20_23."),
    ("exog_temporal_is_peak_commute_flag", "panel_calendar", "edge + temporal_bin_4h + is_weekend", "temporal", "Flag for bins 08_11 or 16_19."),
    ("exog_temporal_is_weekday_peak_flag", "panel_calendar", "edge + temporal_bin_4h + is_weekend", "temporal", "Flag for commute bins on weekdays."),
    ("exog_temporal_is_weekend_night_flag", "panel_calendar", "edge + temporal_bin_4h + is_weekend", "temporal", "Flag for night bins on weekends."),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build ROAD-SAFETY richer exogenous context features without training a new model."
    )
    parser.add_argument("--force", action="store_true", help="Rebuild outputs even if they already exist.")
    return parser.parse_args()


def validate_required_inputs(paths) -> None:
    required = [
        paths.training_with_contextual_lag_safe_features_parquet,
        paths.m8_edges_csv,
        paths.m8_nodes_csv,
    ]
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        raise FileNotFoundError(f"Missing required inputs for exogenous feature phase: {missing}")


def load_base_table(paths) -> pd.DataFrame:
    base = pd.read_parquet(paths.training_with_contextual_lag_safe_features_parquet)
    duplicate_n = int(base.duplicated(["edge_id", "analysis_year", "temporal_bin_4h", "is_weekend"]).sum())
    if duplicate_n > 0:
        raise ValueError(f"Base contextual table is not unique at panel level; duplicates found: {duplicate_n}")
    return base


def load_network_frames(paths) -> tuple[pd.DataFrame, pd.DataFrame]:
    edges = pd.read_csv(paths.m8_edges_csv)
    nodes = pd.read_csv(paths.m8_nodes_csv, usecols=["node_id", "degree_total"])
    return edges, nodes


def road_class_group_flags(series: pd.Series) -> tuple[pd.Series, pd.Series, pd.Series]:
    text = series.fillna("unknown").astype(str)
    is_link = text.str.endswith("_link")
    is_major = text.isin(["motorway", "trunk", "primary", "motorway_link", "trunk_link", "primary_link"])
    is_local = text.isin(["residential", "service", "living_street", "unclassified", "tertiary", "tertiary_link"])
    return is_link.astype(int), is_major.astype(int), is_local.astype(int)


def derive_edge_exogenous_features(edges: pd.DataFrame, nodes: pd.DataFrame) -> pd.DataFrame:
    result = edges.copy()
    result["road_class"] = result["road_class"].fillna("unknown").astype(str)
    result["exog_road_class_hierarchy_score"] = result["road_class"].map(ROAD_CLASS_HIERARCHY).fillna(0).astype(float)

    is_link, is_major, is_local = road_class_group_flags(result["road_class"])
    result["exog_road_class_is_link_flag"] = is_link
    result["exog_road_class_is_major_flag"] = is_major
    result["exog_road_class_is_local_flag"] = is_local

    result["exog_has_road_ref_flag"] = result["road_ref"].notna().astype(int)
    result["exog_has_street_name_flag"] = result["street_name"].notna().astype(int)

    maxspeed = pd.to_numeric(result["maxspeed_raw"], errors="coerce")
    maxspeed = maxspeed.mask(maxspeed <= 0, np.nan)
    result["exog_maxspeed_kph"] = maxspeed
    result["exog_maxspeed_missing_flag"] = result["exog_maxspeed_kph"].isna().astype(int)
    road_class_speed_median = result.groupby("road_class")["exog_maxspeed_kph"].transform("median")
    global_speed_median = float(result["exog_maxspeed_kph"].median())
    result["exog_maxspeed_kph_imputed_by_road_class"] = result["exog_maxspeed_kph"].fillna(road_class_speed_median).fillna(global_speed_median)
    result["exog_maxspeed_ge70_flag"] = result["exog_maxspeed_kph_imputed_by_road_class"].ge(70).astype(int)
    result["exog_maxspeed_le30_flag"] = result["exog_maxspeed_kph_imputed_by_road_class"].le(30).astype(int)

    oneway = result["oneway_raw"].fillna("unknown").astype(str)
    result["exog_oneway_code_t_flag"] = oneway.eq("T").astype(int)
    result["exog_oneway_code_b_flag"] = oneway.eq("B").astype(int)

    result["exog_bridge_flag"] = result["bridge_raw"].fillna("F").astype(str).eq("T").astype(int)
    result["exog_tunnel_flag"] = result["tunnel_raw"].fillna("F").astype(str).eq("T").astype(int)

    layer_numeric = pd.to_numeric(result["layer_raw"], errors="coerce").fillna(0)
    result["exog_layer_abs"] = layer_numeric.abs()
    result["exog_nonzero_layer_flag"] = layer_numeric.ne(0).astype(int)

    node_degree_lookup = nodes.rename(columns={"degree_total": "node_degree_total"})
    result = result.merge(
        node_degree_lookup.rename(columns={"node_id": "from_node_id", "node_degree_total": "exog_from_node_degree"}),
        on="from_node_id",
        how="left",
    )
    result = result.merge(
        node_degree_lookup.rename(columns={"node_id": "to_node_id", "node_degree_total": "exog_to_node_degree"}),
        on="to_node_id",
        how="left",
    )
    result["exog_from_node_degree"] = pd.to_numeric(result["exog_from_node_degree"], errors="coerce").fillna(0)
    result["exog_to_node_degree"] = pd.to_numeric(result["exog_to_node_degree"], errors="coerce").fillna(0)
    result["exog_node_degree_mean"] = (result["exog_from_node_degree"] + result["exog_to_node_degree"]) / 2.0
    result["exog_node_degree_max"] = result[["exog_from_node_degree", "exog_to_node_degree"]].max(axis=1)
    result["exog_node_degree_min"] = result[["exog_from_node_degree", "exog_to_node_degree"]].min(axis=1)
    result["exog_edge_touches_dead_end_flag"] = result["exog_node_degree_min"].eq(1).astype(int)
    result["exog_edge_touches_intersection_flag"] = result["exog_node_degree_max"].ge(3).astype(int)
    result["exog_edge_between_intersections_flag"] = result["exog_node_degree_min"].ge(3).astype(int)

    dx = pd.to_numeric(result["to_x"], errors="coerce") - pd.to_numeric(result["from_x"], errors="coerce")
    dy = pd.to_numeric(result["to_y"], errors="coerce") - pd.to_numeric(result["from_y"], errors="coerce")
    norm = np.sqrt(np.square(dx) + np.square(dy))
    result["exog_orientation_sin"] = np.where(norm > 0, dy / norm, 0.0)
    result["exog_orientation_cos"] = np.where(norm > 0, dx / norm, 1.0)

    midpoint_x = (pd.to_numeric(result["from_x"], errors="coerce") + pd.to_numeric(result["to_x"], errors="coerce")) / 2.0
    midpoint_y = (pd.to_numeric(result["from_y"], errors="coerce") + pd.to_numeric(result["to_y"], errors="coerce")) / 2.0
    network_centroid_x = float(midpoint_x.mean())
    network_centroid_y = float(midpoint_y.mean())
    result["exog_distance_from_network_centroid_km"] = (
        np.sqrt(np.square(midpoint_x - network_centroid_x) + np.square(midpoint_y - network_centroid_y)) / 1000.0
    )

    result["exog_source_way_segment_count"] = result.groupby("source_osm_id")["edge_id"].transform("count")
    result["exog_source_way_total_length_m"] = result.groupby("source_osm_id")["edge_length_m"].transform("sum")
    result["exog_source_way_mean_segment_length_m"] = result.groupby("source_osm_id")["edge_length_m"].transform("mean")

    keep_cols = ["edge_id"] + [spec[0] for spec in FEATURE_SPECS if spec[2] == "edge"]
    return result[keep_cols].drop_duplicates("edge_id")


def derive_temporal_exogenous_features(df: pd.DataFrame) -> pd.DataFrame:
    result = df.copy()
    bin_label = result["temporal_bin_4h"].fillna("").astype(str)
    result["exog_temporal_is_night_flag"] = bin_label.isin(["00_03", "20_23"]).astype(int)
    result["exog_temporal_is_peak_commute_flag"] = bin_label.isin(["08_11", "16_19"]).astype(int)
    result["exog_temporal_is_weekday_peak_flag"] = (
        result["exog_temporal_is_peak_commute_flag"].eq(1) & (~result["is_weekend"].astype(bool))
    ).astype(int)
    result["exog_temporal_is_weekend_night_flag"] = (
        result["exog_temporal_is_night_flag"].eq(1) & result["is_weekend"].astype(bool)
    ).astype(int)
    return result


def build_source_registry_rows() -> list[dict]:
    rows = []
    for block in (USABLE_NOW_SOURCES, USABLE_WITH_PROCESSING_SOURCES, NOT_USABLE_NOW_SOURCES, UNSAFE_SOURCES):
        for item in block:
            rows.append(
                {
                    "registry_section": "source_audit",
                    "item_name": item["item_name"],
                    "item_kind": "source",
                    "source_category": item["source_category"],
                    "source": item["source"],
                    "definition": item["definition"],
                    "granularity": item["granularity"],
                    "temporal_scope": item["temporal_scope"],
                    "coverage_pct": np.nan,
                    "missing_pct": np.nan,
                    "leak_safe_reason": "Source-level classification; not a direct feature row.",
                    "status_note": item["status_note"],
                }
            )
    return rows


def build_feature_registry_rows(df: pd.DataFrame) -> list[dict]:
    rows = []
    for feature_name, source_name, granularity, temporal_scope, definition in FEATURE_SPECS:
        missing_pct = float(100.0 * df[feature_name].isna().mean())
        coverage_pct = float(100.0 - missing_pct)
        rows.append(
            {
                "registry_section": "feature",
                "item_name": feature_name,
                "item_kind": "feature",
                "source_category": "usable_now_exogenous",
                "source": source_name,
                "definition": definition,
                "granularity": granularity,
                "temporal_scope": temporal_scope,
                "coverage_pct": coverage_pct,
                "missing_pct": missing_pct,
                "leak_safe_reason": "Derived only from static canonical network attributes, deterministic calendar logic, or node topology available before every observation.",
                "status_note": "Built in this phase.",
            }
        )
    return rows


def build_registry(df: pd.DataFrame) -> pd.DataFrame:
    rows = build_source_registry_rows() + build_feature_registry_rows(df)
    return pd.DataFrame(rows)


def summarize_feature(df: pd.DataFrame, feature_name: str, source_name: str, granularity: str, temporal_scope: str) -> dict:
    series = df[feature_name]
    numeric = pd.to_numeric(series, errors="coerce")
    nonmissing = series.dropna()
    numeric_nonmissing = numeric.dropna()
    return {
        "feature_name": feature_name,
        "source": source_name,
        "granularity": granularity,
        "temporal_scope": temporal_scope,
        "rows_n": int(len(df)),
        "coverage_n": int(series.notna().sum()),
        "coverage_pct": float(100.0 * series.notna().mean()),
        "missing_n": int(series.isna().sum()),
        "missing_pct": float(100.0 * series.isna().mean()),
        "unique_n": int(nonmissing.nunique()),
        "mean_nonmissing": float(numeric_nonmissing.mean()) if not numeric_nonmissing.empty else np.nan,
        "p50_nonmissing": float(numeric_nonmissing.quantile(0.50)) if not numeric_nonmissing.empty else np.nan,
        "p95_nonmissing": float(numeric_nonmissing.quantile(0.95)) if not numeric_nonmissing.empty else np.nan,
        "min_nonmissing": float(numeric_nonmissing.min()) if not numeric_nonmissing.empty else np.nan,
        "max_nonmissing": float(numeric_nonmissing.max()) if not numeric_nonmissing.empty else np.nan,
    }


def build_summary(df: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for feature_name, source_name, granularity, temporal_scope, _ in FEATURE_SPECS:
        rows.append(summarize_feature(df, feature_name, source_name, granularity, temporal_scope))
    return pd.DataFrame(rows).sort_values(["temporal_scope", "feature_name"]).reset_index(drop=True)


def write_note(paths, summary: pd.DataFrame) -> None:
    usable_features = summary.loc[summary["coverage_pct"] >= 99.0, "feature_name"].tolist()
    partial_features = summary.loc[(summary["coverage_pct"] < 99.0) & (summary["coverage_pct"] >= 80.0), "feature_name"].tolist()
    low_coverage_features = summary.loc[summary["coverage_pct"] < 80.0, "feature_name"].tolist()

    note = f"""# Exogenous Feature Note

## Scope
This phase enriches `training_table_with_contextual_lag_safe_features.parquet` with richer exogenous features.
It does not change:
- target: `accident_count`
- split: train 2016-2022 / validation 2023 / test 2024
- routing logic
- final edge weighting

## Usable now
- Canonical edge attributes from M8.
- Canonical node topology from M8.
- Deterministic panel calendar features already present in the modeling unit.

## Usable with processing
- Auxiliary OSM layers from the Geofabrik extract: traffic controls, buildings, land use, POIs, transport and related static layers.
- These require a geospatial preprocessing stack and spatial joins not currently available in this Python environment.

## Not usable now
- Municipal traffic tramo CSV remains non-interoperable with the canonical network under current evidence from M11.
- No standalone leak-safe weather feed exists in the repo.
- Communications cartography and DGT catalog metadata are not direct modeling context sources.

## Unsafe due to leakage
- M11 exposure outputs and M12 dynamic/contextual outputs are accident-backed and cannot be used as direct exogenous predictors.

## Built feature block
- Features with >=99% coverage: {", ".join(usable_features) if usable_features else "none"}
- Features with partial but still high coverage: {", ".join(partial_features) if partial_features else "none"}
- Features with low coverage: {", ".join(low_coverage_features) if low_coverage_features else "none"}

## Interpretation
This block is genuinely exogenous and materially richer than the previous accident-backed contextual fallback alone.
It is enough to justify a next baseline iteration, especially to test whether static/topological edge context adds value beyond pure history.
However, it still does not solve the absence of operational dynamic exogenous feeds such as aligned traffic or weather data.
"""
    paths.exogenous_feature_note_md.write_text(note, encoding="utf-8")


def main() -> None:
    args = parse_args()
    paths = build_paths()

    outputs_exist = all(
        path.exists()
        for path in [
            paths.training_with_exogenous_context_features_parquet,
            paths.exogenous_feature_registry_csv,
            paths.exogenous_feature_summary_csv,
            paths.exogenous_feature_note_md,
        ]
    )
    if outputs_exist and not args.force:
        print("Exogenous feature artifacts already exist. Use --force to rebuild.")
        return

    validate_required_inputs(paths)
    base = load_base_table(paths)
    edges, nodes = load_network_frames(paths)
    edge_features = derive_edge_exogenous_features(edges, nodes)

    enriched = base.merge(edge_features, on="edge_id", how="left")
    enriched = derive_temporal_exogenous_features(enriched)

    if len(enriched) != len(base):
        raise ValueError("Row count changed while building exogenous features.")
    if int(enriched["accident_count"].sum()) != int(base["accident_count"].sum()):
        raise ValueError("Target sum changed while building exogenous features.")

    summary = build_summary(enriched)
    registry = build_registry(enriched)

    enriched.to_parquet(paths.training_with_exogenous_context_features_parquet, index=False)
    registry.to_csv(paths.exogenous_feature_registry_csv, index=False)
    summary.to_csv(paths.exogenous_feature_summary_csv, index=False)
    write_note(paths, summary)

    print(f"training_rows_n={len(enriched)}")
    print(f"target_sum={int(enriched['accident_count'].sum())}")
    print(f"exogenous_features_built_n={len(FEATURE_SPECS)}")


if __name__ == "__main__":
    main()
