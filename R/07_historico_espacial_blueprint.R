rs_m7_required_master_columns <- c(
  "num_expediente",
  "coordenada_x_utm",
  "coordenada_y_utm",
  "fecha",
  "hora",
  "id_sensor_cercano",
  "tipo_accidente",
  "intensidad",
  "ocupacion",
  "vmed"
)

rs_check_m7_packages <- function() {
  required_packages <- c("dplyr", "tibble", "readr")
  missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]

  if (length(missing_packages) > 0L) {
    stop(
      sprintf(
        "Faltan paquetes requeridos para M7: %s",
        paste(missing_packages, collapse = ", ")
      ),
      call. = FALSE
    )
  }
}

rs_validate_m7_inputs <- function(accident_master, paths) {
  if (missing(accident_master) || is.null(accident_master) || !nrow(accident_master)) {
    stop("M7 necesita una tabla accidente no vacia como input.", call. = FALSE)
  }

  missing_columns <- setdiff(rs_m7_required_master_columns, names(accident_master))
  if (length(missing_columns) > 0L) {
    stop(
      sprintf(
        "Faltan columnas requeridas en accident_master para M7: %s",
        paste(missing_columns, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  required_path_fields <- c("project_dir", "output_data", "output_tables")
  missing_path_fields <- setdiff(required_path_fields, names(paths))
  if (length(missing_path_fields) > 0L) {
    stop(
      sprintf(
        "M7 necesita paths con estos campos: %s",
        paste(required_path_fields, collapse = ", ")
      ),
      call. = FALSE
    )
  }
}

rs_m7_define_input_registry <- function(paths) {
  registry <- tibble::tribble(
    ~input_name, ~relative_path, ~input_group, ~role_in_pipeline, ~geometry_or_structure, ~required_for_blueprint, ~required_for_map_matching, ~required_for_edge_score, ~notes,
    "accident_master",
    file.path("outputs", "data", "accidentes_tabla_accidente_master.csv"),
    "existing_core",
    "accident_point_source",
    "table_with_utm_like_point_coordinates",
    TRUE,
    TRUE,
    TRUE,
    "Canonical accident-level table coming from M3; valid source for the historical-spatial bridge.",
    "traffic_tramos_realtime",
    file.path("bases de datos", "estat-transit-temps-real-estado-trafico-tiempo-real.csv"),
    "existing_contextual_segment_source",
    "contextual_segment_overlay",
    "csv_with_linestring_geometry",
    TRUE,
    FALSE,
    FALSE,
    "Useful as contextual or bridging segment source, but not yet a routable graph edge layer.",
    "cartografia_comunicaciones",
    file.path("bases de datos", "cartografia-base-comunicacions-comunicaciones.csv"),
    "existing_optional_auxiliary",
    "non_routable_linear_city_asset",
    "csv_with_linestring_geometry",
    FALSE,
    FALSE,
    FALSE,
    "Available spatial asset, but not a road network substitute for routing.",
    "tipos_vias_reference",
    file.path("bases de datos", "a05003423-clasificacion-del-tipos-de-vias-de-la-direccion-general-de-trafico-dgt-de-espana-istac-cl_dgt_tipos_vias.csv"),
    "existing_optional_reference",
    "metadata_or_reference_lookup",
    "reference_csv",
    FALSE,
    FALSE,
    FALSE,
    "Reference catalog; not a direct routing or matching input.",
    "road_network_edges",
    file.path("bases de datos", "network", "road_network_edges.geojson"),
    "future_required",
    "canonical_routable_edge_layer",
    "edge_geometry_layer",
    FALSE,
    TRUE,
    TRUE,
    "Required future input: drivable graph edges in a canonical CRS.",
    "road_network_nodes",
    file.path("bases de datos", "network", "road_network_nodes.geojson"),
    "future_required",
    "canonical_routable_node_layer",
    "node_geometry_layer",
    FALSE,
    TRUE,
    FALSE,
    "Required future input: graph nodes aligned with the canonical edge layer.",
    "tramo_sensor_to_edge_crosswalk",
    file.path("bases de datos", "crosswalks", "tramo_sensor_to_edge_crosswalk.csv"),
    "future_required",
    "bridge_between_context_layers_and_edges",
    "tabular_crosswalk",
    FALSE,
    TRUE,
    TRUE,
    "Required if traffic tramos or sensors are used to enrich graph edges.",
    "edge_exposure_baseline",
    file.path("bases de datos", "exposure", "edge_exposure_baseline.csv"),
    "future_required",
    "exposure_or_denominator_source",
    "tabular_edge_metrics",
    FALSE,
    FALSE,
    TRUE,
    "Required before any historical edge score is turned into a defensible normalized risk signal."
  )

  registry |>
    dplyr::mutate(
      absolute_path = file.path(paths$project_dir, relative_path),
      exists = file.exists(absolute_path),
      availability_status = dplyr::case_when(
        exists & (required_for_blueprint | required_for_map_matching | required_for_edge_score) ~ "existing_required_or_useful",
        exists ~ "existing_optional",
        !exists & (required_for_map_matching | required_for_edge_score) ~ "missing_future_required",
        TRUE ~ "missing_optional"
      )
    )
}

rs_m7_build_accident_spatial_profile <- function(accident_master) {
  valid_coord_mask <- !is.na(accident_master$coordenada_x_utm) &
    !is.na(accident_master$coordenada_y_utm) &
    accident_master$coordenada_x_utm != 0 &
    accident_master$coordenada_y_utm != 0
  valid_sensor_mask <- !is.na(accident_master$id_sensor_cercano) & accident_master$id_sensor_cercano != 0

  coord_x <- accident_master$coordenada_x_utm[valid_coord_mask]
  coord_y <- accident_master$coordenada_y_utm[valid_coord_mask]

  tibble::tribble(
    ~source_name, ~rows_n, ~usable_for_spatial_assignment_n, ~usable_for_spatial_assignment_pct, ~geometry_type, ~key_candidate, ~current_use_assessment, ~notes,
    "accident_master",
    nrow(accident_master),
    sum(valid_coord_mask),
    round(100 * sum(valid_coord_mask) / nrow(accident_master), 2),
    "point_like_columns_in_utm_space",
    "num_expediente",
    "usable_now_for_point_preparation",
    sprintf(
      "Accident master keeps %s coordinate-ready accidents and %s sensor-linked accidents. Confirm CRS before matching.",
      format(sum(valid_coord_mask), big.mark = ","),
      format(sum(valid_sensor_mask), big.mark = ",")
    ),
    "accident_master_sensor_link",
    nrow(accident_master),
    sum(valid_sensor_mask),
    round(100 * sum(valid_sensor_mask) / nrow(accident_master), 2),
    "tabular_sensor_reference",
    "id_sensor_cercano",
    "useful_as_auxiliary_link_only",
    "Useful auxiliary field, but it must not be assumed equivalent to graph edge ids or traffic tramo ids without a crosswalk."
  ) |>
    dplyr::bind_rows(
      tibble::tibble(
        source_name = "accident_coordinate_bbox",
        rows_n = nrow(accident_master),
        usable_for_spatial_assignment_n = sum(valid_coord_mask),
        usable_for_spatial_assignment_pct = round(100 * sum(valid_coord_mask) / nrow(accident_master), 2),
        geometry_type = "bbox_summary",
        key_candidate = "coordenada_x_utm / coordenada_y_utm",
        current_use_assessment = "diagnostic_only",
        notes = sprintf(
          "Observed coordinate range x=[%.3f, %.3f], y=[%.3f, %.3f]. Values look UTM-like; explicit EPSG confirmation is still pending.",
          min(coord_x),
          max(coord_x),
          min(coord_y),
          max(coord_y)
        )
      )
    )
}

rs_m7_build_tramo_source_profile <- function(paths) {
  tramo_path <- file.path(paths$project_dir, "bases de datos", "estat-transit-temps-real-estado-trafico-tiempo-real.csv")

  if (!file.exists(tramo_path)) {
    return(
      tibble::tibble(
        source_name = "traffic_tramos_realtime",
        rows_n = NA_integer_,
        usable_for_spatial_assignment_n = NA_integer_,
        usable_for_spatial_assignment_pct = NA_real_,
        geometry_type = "csv_with_linestring_geometry",
        key_candidate = "Id. Tram / Id. Tramo",
        current_use_assessment = "missing",
        notes = "Real-time tramo source is not available in the repo."
      )
    )
  }

  tramo_data <- readr::read_delim(
    file = tramo_path,
    delim = ";",
    show_col_types = FALSE,
    progress = FALSE,
    locale = readr::locale(encoding = "UTF-8"),
    name_repair = "minimal"
  )

  tramo_id_column <- "Id. Tram / Id. Tramo"
  tramo_id_n <- if (tramo_id_column %in% names(tramo_data)) {
    dplyr::n_distinct(tramo_data[[tramo_id_column]])
  } else {
    NA_integer_
  }

  linestring_n <- if ("geo_shape" %in% names(tramo_data)) {
    sum(!is.na(tramo_data$geo_shape) & nzchar(tramo_data$geo_shape))
  } else {
    NA_integer_
  }

  tibble::tibble(
    source_name = "traffic_tramos_realtime",
    rows_n = nrow(tramo_data),
    usable_for_spatial_assignment_n = linestring_n,
    usable_for_spatial_assignment_pct = round(100 * linestring_n / nrow(tramo_data), 2),
    geometry_type = "linestring_segments_lonlat",
    key_candidate = "Id. Tram / Id. Tramo",
    current_use_assessment = "usable_as_context_overlay_or_bridge",
    notes = sprintf(
      "Source has %s rows, %s unique tramo ids and %s non-missing LineString geometries. Useful as overlay/bridge, not as final routable edge layer.",
      format(nrow(tramo_data), big.mark = ","),
      format(tramo_id_n, big.mark = ","),
      format(linestring_n, big.mark = ",")
    )
  )
}

rs_build_m7_existing_spatial_sources <- function(accident_master, paths) {
  dplyr::bind_rows(
    rs_m7_build_accident_spatial_profile(accident_master),
    rs_m7_build_tramo_source_profile(paths),
    tibble::tribble(
      ~source_name, ~rows_n, ~usable_for_spatial_assignment_n, ~usable_for_spatial_assignment_pct, ~geometry_type, ~key_candidate, ~current_use_assessment, ~notes,
      "cartografia_comunicaciones",
      NA_integer_,
      NA_integer_,
      NA_real_,
      "linear_city_asset",
      "objectid",
      "auxiliary_only",
      "City linear asset layer available in CSV form. It should not be mistaken for a routable road network.",
      "tipos_vias_reference",
      NA_integer_,
      NA_integer_,
      NA_real_,
      "reference_table",
      "IDENTIFICADOR",
      "reference_only",
      "Reference classification table. Useful for metadata normalization, not for direct accident-to-edge assignment."
    )
  )
}

rs_build_m7_spatial_unit_options <- function(existing_spatial_sources) {
  accident_ready_note <- existing_spatial_sources |>
    dplyr::filter(source_name == "accident_master") |>
    dplyr::slice(1) |>
    dplyr::pull(notes)

  tramo_ready_note <- existing_spatial_sources |>
    dplyr::filter(source_name == "traffic_tramos_realtime") |>
    dplyr::slice(1) |>
    dplyr::pull(notes)

  tibble::tribble(
    ~spatial_unit_option, ~unit_role, ~is_recommended_baseline, ~why_use_it, ~why_not_use_it_as_final_edge_weight_unit, ~implementation_note,
    "routable_graph_edge",
    "final_operational_unit",
    TRUE,
    "This is the correct baseline spatial unit for ROAD-SAFETY because routing operates over graph edges, not over raw accident points or sensor proxies.",
    "Requires a canonical drivable road network plus accident-to-edge assignment before any historical score can be computed.",
    "Use as final target unit. All historical and contextual signals should eventually be translated to this unit.",
    "derived_segment_bridge",
    "intermediate_bridge_unit",
    FALSE,
    "Useful if accidents are first matched to a municipal or analytical segment layer before being collapsed onto graph edges.",
    "If left as the final unit, it risks diverging from the actual graph used for routing.",
    "Acceptable as an intermediate staging layer only if a later segment-to-edge crosswalk is explicit and auditable.",
    "sensor_or_realtime_tramo",
    "contextual_overlay_unit",
    FALSE,
    "Already available in the repo and geometrically useful for contextual overlays or provisional spatial enrichment.",
    "A traffic tramo is not guaranteed to equal a drivable edge. It should not become the final routing unit by default.",
    sprintf(
      "Current evidence: %s %s",
      accident_ready_note,
      tramo_ready_note
    )
  )
}

rs_build_m7_pipeline_stages <- function(input_registry, existing_spatial_sources) {
  network_exists <- input_registry |>
    dplyr::filter(input_name == "road_network_edges") |>
    dplyr::pull(exists)
  crosswalk_exists <- input_registry |>
    dplyr::filter(input_name == "tramo_sensor_to_edge_crosswalk") |>
    dplyr::pull(exists)
  exposure_exists <- input_registry |>
    dplyr::filter(input_name == "edge_exposure_baseline") |>
    dplyr::pull(exists)

  coords_pct <- existing_spatial_sources |>
    dplyr::filter(source_name == "accident_master") |>
    dplyr::slice(1) |>
    dplyr::pull(usable_for_spatial_assignment_pct)

  tibble::tribble(
    ~stage_order, ~stage_name, ~purpose, ~main_inputs, ~future_output, ~current_readiness, ~validation_rule,
    1L,
    "prepare_accidents_geolocalized",
    "Build the spatially ready accident point layer from accident_master and keep unmatched or zero-coordinate cases explicit.",
    "accident_master",
    "m7_accidents_spatial_ready.csv",
    if (coords_pct >= 95) "ready_now" else "partial_readiness",
    "Validate required spatial columns, count non-zero coordinates, confirm CRS metadata and keep a separate unmatched bucket.",
    2L,
    "prepare_road_network",
    "Create the canonical drivable edge/node layers that will become the routing graph backbone.",
    "road_network_edges + road_network_nodes",
    "m7_network_edges_clean.geojson + m7_network_nodes_clean.geojson",
    if (isTRUE(network_exists)) "ready_now" else "blocked_missing_network",
    "Validate topology basics, CRS consistency and graph suitability for edge-based routing.",
    3L,
    "assign_accident_to_edge",
    "Snap or match each accident point to the canonical graph edge, keeping distance/error diagnostics.",
    "spatial_ready_accidents + canonical_edges",
    "m7_accident_edge_matches.csv",
    if (isTRUE(network_exists)) "design_ready_but_not_implemented" else "blocked_missing_network",
    "Validate one best edge per accident, unmatched share, distance thresholds and auditable match quality fields.",
    4L,
    "aggregate_historical_by_edge",
    "Aggregate matched accidents by edge and time window to build historical counts and severity summaries.",
    "accident_edge_matches",
    "m7_edge_history_annual.csv",
    if (isTRUE(network_exists)) "depends_on_matching_stage" else "blocked_upstream",
    "Validate that aggregation keys are edge_id and time window, not raw coordinates or sensor ids.",
    5L,
    "adjust_by_exposure",
    "Join denominator or exposure proxies to avoid treating raw counts as final risk.",
    "edge_history + edge_exposure_baseline",
    "m7_edge_history_exposure_adjusted.csv",
    if (isTRUE(exposure_exists)) "future_ready_once_upstream_exists" else "blocked_missing_exposure",
    "Validate denominator quality, missing exposure coverage and rate stability before scoring.",
    6L,
    "build_preliminary_historical_edge_score",
    "Combine historical frequency, severity and optional smoothing into a preliminary edge-level historical block.",
    "edge_history_exposure_adjusted + optional_crosswalks",
    "m7_edge_historical_score.csv",
    if (isTRUE(network_exists) && isTRUE(exposure_exists)) "future_ready_once_upstream_exists" else "blueprint_only",
    "Validate clear separation from baseline/contextual signals and do not convert the score into final routing cost yet."
  ) |>
    dplyr::mutate(
      dependency_note = dplyr::case_when(
        stage_name == "prepare_accidents_geolocalized" ~ "Consumes the accident-level master built in M3.",
        stage_name == "prepare_road_network" ~ "This is the main blocker right now: no canonical routable network is stored in the repo.",
        stage_name == "assign_accident_to_edge" ~ if (isTRUE(crosswalk_exists)) "Crosswalk exists, but direct point-to-edge matching is still required." else "Direct matching should use geometry first; any tramo/sensor crosswalk is auxiliary, not a substitute.",
        stage_name == "adjust_by_exposure" ~ "Exposure input is still missing and must stay separate from raw historical counts.",
        TRUE ~ "Depends on completion of previous spatial stages."
      )
    )
}

rs_build_m7_missing_inputs <- function(input_registry) {
  input_registry |>
    dplyr::filter(!exists, required_for_map_matching | required_for_edge_score) |>
    dplyr::select(
      input_name,
      relative_path,
      input_group,
      role_in_pipeline,
      geometry_or_structure,
      notes
    )
}

rs_build_m7_output_registry <- function(paths) {
  tibble::tribble(
    ~artifact_name, ~relative_storage_path, ~artifact_scope, ~produced_in_stage, ~purpose,
    "m7_existing_spatial_sources_summary.csv",
    file.path("outputs", "data", "m7_existing_spatial_sources_summary.csv"),
    "current_blueprint",
    "blueprint",
    "Summarize what spatially useful sources already exist in the repo and how ready they are.",
    "m7_accidents_spatial_ready.csv",
    file.path("outputs", "data", "m7_accidents_spatial_ready.csv"),
    "future_pipeline",
    "prepare_accidents_geolocalized",
    "Store the accident point layer after spatial readiness filtering and CRS confirmation.",
    "m7_network_edges_clean.geojson",
    file.path("outputs", "data", "m7_network_edges_clean.geojson"),
    "future_pipeline",
    "prepare_road_network",
    "Canonical drivable edge layer used later by the graph and the historical score.",
    "m7_network_nodes_clean.geojson",
    file.path("outputs", "data", "m7_network_nodes_clean.geojson"),
    "future_pipeline",
    "prepare_road_network",
    "Canonical node layer paired with the edge layer.",
    "m7_accident_edge_matches.csv",
    file.path("outputs", "data", "m7_accident_edge_matches.csv"),
    "future_pipeline",
    "assign_accident_to_edge",
    "One accident to one best edge assignment with distance diagnostics and quality flags.",
    "m7_edge_history_annual.csv",
    file.path("outputs", "data", "m7_edge_history_annual.csv"),
    "future_pipeline",
    "aggregate_historical_by_edge",
    "Historical aggregation by edge and time window before exposure normalization.",
    "m7_edge_history_exposure_adjusted.csv",
    file.path("outputs", "data", "m7_edge_history_exposure_adjusted.csv"),
    "future_pipeline",
    "adjust_by_exposure",
    "Historical edge table after joining exposure or denominator metrics.",
    "m7_edge_historical_score.csv",
    file.path("outputs", "data", "m7_edge_historical_score.csv"),
    "future_pipeline",
    "build_preliminary_historical_edge_score",
    "Preliminary historical-spatial block, still separate from contextual baseline and final graph cost."
  ) |>
    dplyr::mutate(absolute_storage_path = file.path(paths$project_dir, relative_storage_path))
}

rs_build_m7_file_structure_blueprint <- function() {
  tibble::tribble(
    ~path_blueprint, ~path_role, ~status_now, ~notes,
    "R/07_historico_espacial_blueprint.R",
    "current_blueprint_module",
    "implemented_now",
    "Profiles current spatial readiness and writes M7 blueprint outputs.",
    "R/08_preparacion_red_viaria.R",
    "future_network_preparation_module",
    "planned",
    "Will ingest and normalize the canonical routable road network.",
    "R/09_mapmatching_accidente_arista.R",
    "future_matching_module",
    "planned",
    "Will assign each accident point to a graph edge with diagnostics.",
    "R/10_agregacion_historica_aristas.R",
    "future_historical_aggregation_module",
    "planned",
    "Will aggregate matched accidents by edge and time window.",
    "R/11_score_historico_aristas.R",
    "future_historical_score_module",
    "planned",
    "Will build the historical-spatial block before any graph cost transformation.",
    "bases de datos/network/",
    "future_input_directory",
    "missing_now",
    "Recommended location for the canonical road network inputs.",
    "bases de datos/crosswalks/",
    "future_input_directory",
    "missing_now",
    "Recommended location for tramo/sensor to edge bridge tables.",
    "bases de datos/exposure/",
    "future_input_directory",
    "missing_now",
    "Recommended location for edge-level exposure or denominator inputs.",
    "outputs/data/",
    "current_output_directory",
    "already_exists",
    "Recommended location for future spatial intermediate datasets with m7_* prefixes.",
    "outputs/tables/",
    "current_output_directory",
    "already_exists",
    "Recommended location for M7 validation tables and blueprint registries."
  )
}

rs_build_m7_validation_summary <- function(accident_master, input_registry, spatial_unit_options, existing_spatial_sources) {
  coord_ready <- existing_spatial_sources |>
    dplyr::filter(source_name == "accident_master") |>
    dplyr::slice(1)
  sensor_ready <- existing_spatial_sources |>
    dplyr::filter(source_name == "accident_master_sensor_link") |>
    dplyr::slice(1)
  tramo_ready <- existing_spatial_sources |>
    dplyr::filter(source_name == "traffic_tramos_realtime") |>
    dplyr::slice(1)

  road_network_exists <- input_registry |>
    dplyr::filter(input_name == "road_network_edges") |>
    dplyr::pull(exists)
  crosswalk_exists <- input_registry |>
    dplyr::filter(input_name == "tramo_sensor_to_edge_crosswalk") |>
    dplyr::pull(exists)
  exposure_exists <- input_registry |>
    dplyr::filter(input_name == "edge_exposure_baseline") |>
    dplyr::pull(exists)

  tibble::tibble(
    metric = c(
      "accident_master_rows",
      "accidents_with_valid_coordinates_n",
      "accidents_with_valid_coordinates_pct",
      "accidents_with_sensor_link_n",
      "accidents_with_sensor_link_pct",
      "available_tramo_rows",
      "available_tramo_geometry_pct",
      "recommended_spatial_unit",
      "road_network_edges_exists",
      "tramo_sensor_crosswalk_exists",
      "edge_exposure_exists",
      "blueprint_ready_now",
      "ready_for_real_map_matching",
      "ready_for_edge_historical_score",
      "routing_weight_not_implemented"
    ),
    value = c(
      as.character(nrow(accident_master)),
      as.character(coord_ready$usable_for_spatial_assignment_n),
      sprintf("%.2f", coord_ready$usable_for_spatial_assignment_pct),
      as.character(sensor_ready$usable_for_spatial_assignment_n),
      sprintf("%.2f", sensor_ready$usable_for_spatial_assignment_pct),
      as.character(tramo_ready$rows_n),
      sprintf("%.2f", tramo_ready$usable_for_spatial_assignment_pct),
      spatial_unit_options$spatial_unit_option[spatial_unit_options$is_recommended_baseline][1],
      as.character(road_network_exists),
      as.character(crosswalk_exists),
      as.character(exposure_exists),
      "TRUE",
      as.character(isTRUE(road_network_exists)),
      as.character(isTRUE(road_network_exists) && isTRUE(exposure_exists)),
      "TRUE"
    )
  )
}

rs_build_m7_blueprint_markdown <- function(spatial_unit_options, missing_inputs, pipeline_stages, output_registry, existing_spatial_sources) {
  recommended_unit <- spatial_unit_options |>
    dplyr::filter(is_recommended_baseline) |>
    dplyr::slice(1)

  accident_row <- existing_spatial_sources |>
    dplyr::filter(source_name == "accident_master") |>
    dplyr::slice(1)
  tramo_row <- existing_spatial_sources |>
    dplyr::filter(source_name == "traffic_tramos_realtime") |>
    dplyr::slice(1)

  missing_list <- if (nrow(missing_inputs) > 0L) {
    paste0("- `", missing_inputs$input_name, "` -> `", missing_inputs$relative_path, "`", collapse = "\n")
  } else {
    "- No missing future-required inputs detected."
  }

  stage_lines <- paste0(
    "- ",
    pipeline_stages$stage_order,
    ". `",
    pipeline_stages$stage_name,
    "` -> ",
    pipeline_stages$current_readiness,
    ". ",
    pipeline_stages$purpose,
    collapse = "\n"
  )

  output_lines <- paste0(
    "- `",
    output_registry$artifact_name,
    "` -> `",
    output_registry$relative_storage_path,
    "`",
    collapse = "\n"
  )

  paste(
    "# M7 - Blueprint historico-espacial ROAD-SAFETY",
    "",
    "## 1. Que falta para pasar del indice conceptual al routing real",
    "- Hace falta una red viaria routable canonica a nivel edge/node.",
    "- Hace falta armonizar CRS entre accidentes y capas lineales antes de cualquier matching real.",
    "- Hace falta asignar accidente -> edge con trazabilidad de calidad, no con joins debiles por sensor o tramo.",
    "- Hace falta agregar evidencia historica por edge y ventana temporal.",
    "- Hace falta un denominador o proxy de exposicion antes de tratar el recuento historico como riesgo operativo.",
    "- Hace falta mantener separado el bloque historico_espacial del baseline/contextual y del futuro coste final de routing.",
    "",
    "## 2. Unidad espacial baseline recomendada",
    sprintf("- Unidad recomendada: `%s`.", recommended_unit$spatial_unit_option),
    sprintf("- Justificacion: %s", recommended_unit$why_use_it),
    sprintf("- Limite de las alternativas intermedias: %s", recommended_unit$why_not_use_it_as_final_edge_weight_unit),
    "",
    "## 3. Inputs existentes y faltantes",
    sprintf("- Accidentes listos para preparacion espacial: %s", accident_row$notes),
    sprintf("- Capa lineal disponible ahora: %s", tramo_row$notes),
    "- Inputs futuros obligatorios para map-matching y score por edge:",
    missing_list,
    "",
    "## 4. Pipeline espacial propuesto",
    stage_lines,
    "",
    "## 5. Salidas intermedias a guardar",
    output_lines,
    "",
    "## 6. Separacion de capas",
    "- `score_baseline` y moduladores contextuales siguen fuera de este bloque.",
    "- `bloque_historico_espacial` debe nacer despues del matching y la agregacion por edge.",
    "- `peso_operativo_final_de_routing` sigue fuera de M7 y no debe inferirse todavia.",
    "",
    sep = "\n"
  )
}

rs_run_m7_historico_espacial_blueprint <- function(accident_master, paths) {
  rs_check_m7_packages()
  rs_validate_m7_inputs(accident_master, paths)

  input_registry <- rs_m7_define_input_registry(paths)
  existing_spatial_sources <- rs_build_m7_existing_spatial_sources(accident_master, paths)
  spatial_unit_options <- rs_build_m7_spatial_unit_options(existing_spatial_sources)
  pipeline_stages <- rs_build_m7_pipeline_stages(input_registry, existing_spatial_sources)
  missing_inputs <- rs_build_m7_missing_inputs(input_registry)
  output_registry <- rs_build_m7_output_registry(paths)
  file_structure_blueprint <- rs_build_m7_file_structure_blueprint()
  validation_summary <- rs_build_m7_validation_summary(
    accident_master = accident_master,
    input_registry = input_registry,
    spatial_unit_options = spatial_unit_options,
    existing_spatial_sources = existing_spatial_sources
  )
  blueprint_markdown <- rs_build_m7_blueprint_markdown(
    spatial_unit_options = spatial_unit_options,
    missing_inputs = missing_inputs,
    pipeline_stages = pipeline_stages,
    output_registry = output_registry,
    existing_spatial_sources = existing_spatial_sources
  )

  readr::write_csv(input_registry, file.path(paths$output_tables, "m7_spatial_input_registry.csv"))
  readr::write_csv(spatial_unit_options, file.path(paths$output_tables, "m7_spatial_unit_options.csv"))
  readr::write_csv(pipeline_stages, file.path(paths$output_tables, "m7_spatial_pipeline_stages.csv"))
  readr::write_csv(missing_inputs, file.path(paths$output_tables, "m7_spatial_missing_inputs.csv"))
  readr::write_csv(output_registry, file.path(paths$output_tables, "m7_spatial_output_registry.csv"))
  readr::write_csv(file_structure_blueprint, file.path(paths$output_tables, "m7_file_structure_blueprint.csv"))
  readr::write_csv(validation_summary, file.path(paths$output_tables, "m7_spatial_validation_summary.csv"))
  readr::write_csv(existing_spatial_sources, file.path(paths$output_data, "m7_existing_spatial_sources_summary.csv"))
  writeLines(blueprint_markdown, con = file.path(paths$output_tables, "m7_spatial_blueprint.md"), useBytes = TRUE)

  list(
    input_registry = input_registry,
    existing_spatial_sources = existing_spatial_sources,
    spatial_unit_options = spatial_unit_options,
    pipeline_stages = pipeline_stages,
    missing_inputs = missing_inputs,
    output_registry = output_registry,
    file_structure_blueprint = file_structure_blueprint,
    validation_summary = validation_summary,
    blueprint_markdown = blueprint_markdown
  )
}
