rs_m9_required_master_columns <- c(
  "num_expediente",
  "coordenada_x_utm",
  "coordenada_y_utm",
  "fecha",
  "hora",
  "tipo_accidente"
)

rs_m9_search_radius_m <- 30
rs_m9_high_conf_distance_m <- 10
rs_m9_medium_conf_distance_m <- 20
rs_m9_medium_conf_candidate_max <- 3L
rs_m9_tie_tolerance_m <- 1
rs_m9_batch_size_default <- 1000L
rs_m9_matching_method <- "nearest_edge_projected_within_radius"
rs_m9_output_schema_version <- "m9_schema_v1_edge_id_projected_point_geometry_binary_match_status"

rs_check_m9_packages <- function() {
  required_packages <- c("dplyr", "tibble", "readr", "sf")
  missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]

  if (length(missing_packages) > 0L) {
    stop(
      sprintf(
        "Faltan paquetes requeridos para M9: %s",
        paste(missing_packages, collapse = ", ")
      ),
      call. = FALSE
    )
  }
}

rs_validate_m9_inputs <- function(accident_master, m8_result, paths) {
  if (missing(accident_master) || is.null(accident_master) || !nrow(accident_master)) {
    stop("M9 necesita una tabla accidente no vacia.", call. = FALSE)
  }

  missing_columns <- setdiff(rs_m9_required_master_columns, names(accident_master))
  if (length(missing_columns) > 0L) {
    stop(
      sprintf(
        "Faltan columnas requeridas en accident_master para M9: %s",
        paste(missing_columns, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  if (missing(m8_result) || is.null(m8_result)) {
    stop("M9 necesita los artefactos de M8.", call. = FALSE)
  }

  if (!all(c("edges_path", "nodes_path") %in% names(m8_result))) {
    stop("M9 necesita `edges_path` y `nodes_path` dentro de m8_result.", call. = FALSE)
  }

  if (!file.exists(m8_result$edges_path)) {
    stop(sprintf("No se encontro la red canonica de edges: %s", m8_result$edges_path), call. = FALSE)
  }

  if (!file.exists(m8_result$nodes_path)) {
    stop(sprintf("No se encontro la red canonica de nodes: %s", m8_result$nodes_path), call. = FALSE)
  }

  required_paths <- c("output_data", "output_tables")
  if (!all(required_paths %in% names(paths))) {
    stop("M9 necesita output_data y output_tables dentro de paths.", call. = FALSE)
  }
}

rs_m9_output_paths <- function(paths) {
  list(
    matches_csv = file.path(paths$output_data, "m9_accident_edge_matches.csv"),
    matches_geojson = file.path(paths$output_data, "m9_accident_edge_matches.geojson"),
    unmatched_csv = file.path(paths$output_data, "m9_unmatched_accidents.csv"),
    outside_envelope_csv = file.path(paths$output_data, "m9_outside_operational_envelope_accidents.csv"),
    quality_summary_csv = file.path(paths$output_tables, "m9_matching_quality_summary.csv"),
    thresholds_csv = file.path(paths$output_tables, "m9_matching_thresholds.csv"),
    validation_csv = file.path(paths$output_tables, "m9_matching_validation_summary.csv"),
    note_md = file.path(paths$output_tables, "m9_matching_note.md")
  )
}

rs_m9_artifacts_ready <- function(output_paths) {
  all(file.exists(unlist(output_paths, use.names = FALSE)))
}

rs_m9_expected_thresholds <- function() {
  tibble::tribble(
    ~threshold_name, ~value, ~unit, ~used_for, ~why,
    "search_radius_m", as.character(rs_m9_search_radius_m), "m", "candidate_search", "Initial urban search radius for edge candidates around each accident point.",
    "high_confidence_distance_max_m", as.character(rs_m9_high_conf_distance_m), "m", "quality_flag", "Very short point-edge distance with no ambiguity.",
    "medium_confidence_distance_max_m", as.character(rs_m9_medium_conf_distance_m), "m", "quality_flag", "Reasonable urban offset still compatible with geocoded accident points.",
    "medium_confidence_candidate_max", as.character(rs_m9_medium_conf_candidate_max), "count", "quality_flag", "A small nearby candidate set is still interpretable.",
    "tie_tolerance_m", as.character(rs_m9_tie_tolerance_m), "m", "tie_resolution", "Candidates within this margin from the minimum distance are treated as a near-tie and penalized in quality.",
    "output_schema_version", rs_m9_output_schema_version, "label", "output_schema", "Final M9 schema version for cache invalidation and auditability."
  )
}

rs_m9_cache_is_current <- function(output_paths) {
  if (!rs_m9_artifacts_ready(output_paths)) {
    return(FALSE)
  }

  thresholds <- tryCatch(
    readr::read_csv(output_paths$thresholds_csv, show_col_types = FALSE),
    error = function(...) NULL
  )

  if (is.null(thresholds)) {
    return(FALSE)
  }

  expected <- rs_m9_expected_thresholds()
  merged <- dplyr::left_join(expected, thresholds, by = "threshold_name", suffix = c("_expected", "_found"))
  all(merged$value_expected == merged$value_found)
}

rs_m9_read_cached_outputs <- function(output_paths) {
  list(
    matches = readr::read_csv(output_paths$matches_csv, show_col_types = FALSE),
    unmatched = readr::read_csv(output_paths$unmatched_csv, show_col_types = FALSE),
    outside_operational_envelope = readr::read_csv(output_paths$outside_envelope_csv, show_col_types = FALSE),
    quality_summary = readr::read_csv(output_paths$quality_summary_csv, show_col_types = FALSE),
    thresholds = readr::read_csv(output_paths$thresholds_csv, show_col_types = FALSE),
    validation_summary = readr::read_csv(output_paths$validation_csv, show_col_types = FALSE),
    matching_note = paste(readLines(output_paths$note_md, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  )
}

rs_m9_load_edges <- function(m8_result) {
  edges_sf <- sf::st_read(m8_result$edges_path, quiet = TRUE)

  required_edge_columns <- c(
    "edge_id", "from_node_id", "to_node_id", "edge_length_m",
    "from_x", "from_y", "to_x", "to_y", "source_osm_id", "road_class"
  )
  missing_edge_columns <- setdiff(required_edge_columns, names(edges_sf))

  if (length(missing_edge_columns) > 0L) {
    stop(
      sprintf(
        "Faltan columnas requeridas en la red canonica de edges para M9: %s",
        paste(missing_edge_columns, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  if (!identical(sf::st_crs(edges_sf)$epsg, rs_m8_canonical_crs_epsg)) {
    stop(
      sprintf(
        "La red canonica de edges no esta en EPSG:%s.",
        rs_m8_canonical_crs_epsg
      ),
      call. = FALSE
    )
  }

  edges_sf
}

rs_m9_add_unmatched_audit_columns <- function(df, search_radius_m, unmatched_reason, outside_operational_envelope) {
  df |>
    dplyr::mutate(
      match_status = "unmatched",
      unmatched_reason = unmatched_reason,
      outside_operational_envelope = outside_operational_envelope,
      candidate_edges_n = 0L,
      search_radius_m = search_radius_m,
      edge_id = NA_character_,
      distance_accident_to_edge_m = NA_real_,
      distance_to_from_node_m = NA_real_,
      distance_to_to_node_m = NA_real_,
      projection_fraction_0_1 = NA_real_,
      projected_x_utm = NA_real_,
      projected_y_utm = NA_real_,
      projected_point_geometry = NA_character_,
      nearest_edge_id_any = NA_character_,
      nearest_distance_any_m = NA_real_,
      quality_flag = "unmatched",
      matching_method = rs_m9_matching_method,
      tie_candidate_count = 0L,
      match_decision_rule = unmatched_reason,
      candidate_top3_edge_ids = NA_character_,
      candidate_top3_distances_m = NA_character_
    )
}

rs_m9_prepare_accidents_for_matching <- function(accident_master, edges_sf, search_radius_m) {
  accident_id_order <- seq_len(nrow(accident_master))

  accidents_base <- tibble::tibble(
    accident_row_id = accident_id_order,
    num_expediente = accident_master$num_expediente,
    fecha = accident_master$fecha,
    hora = accident_master$hora,
    tipo_accidente = accident_master$tipo_accidente,
    accident_x_utm = accident_master$coordenada_x_utm,
    accident_y_utm = accident_master$coordenada_y_utm
  )

  valid_coord_mask <- !is.na(accidents_base$accident_x_utm) &
    !is.na(accidents_base$accident_y_utm) &
    accidents_base$accident_x_utm != 0 &
    accidents_base$accident_y_utm != 0

  invalid_unmatched <- accidents_base |>
    dplyr::filter(!valid_coord_mask) |>
    rs_m9_add_unmatched_audit_columns(
      search_radius_m = search_radius_m,
      unmatched_reason = "invalid_coordinates",
      outside_operational_envelope = FALSE
    )

  valid_accidents <- accidents_base |>
    dplyr::filter(valid_coord_mask)

  valid_sf <- sf::st_as_sf(
    valid_accidents,
    coords = c("accident_x_utm", "accident_y_utm"),
    crs = rs_m8_canonical_crs_epsg,
    remove = FALSE
  )

  operational_envelope <- sf::st_as_sfc(sf::st_bbox(edges_sf)) |>
    sf::st_buffer(search_radius_m)
  inside_envelope_mask <- lengths(sf::st_intersects(valid_sf, operational_envelope)) > 0

  outside_unmatched <- valid_sf[!inside_envelope_mask, ] |>
    sf::st_drop_geometry() |>
    rs_m9_add_unmatched_audit_columns(
      search_radius_m = search_radius_m,
      unmatched_reason = "outside_operational_envelope",
      outside_operational_envelope = TRUE
    )

  matching_ready_sf <- valid_sf[inside_envelope_mask, ]

  list(
    matching_ready_sf = matching_ready_sf,
    invalid_unmatched = invalid_unmatched,
    outside_unmatched = outside_unmatched,
    operational_envelope = operational_envelope,
    valid_coordinate_n = sum(valid_coord_mask),
    inside_envelope_n = nrow(matching_ready_sf),
    outside_envelope_n = nrow(outside_unmatched)
  )
}

rs_m9_project_point_to_segment <- function(px, py, candidate_edges) {
  dx <- candidate_edges$to_x - candidate_edges$from_x
  dy <- candidate_edges$to_y - candidate_edges$from_y
  len2 <- dx * dx + dy * dy
  len2[len2 == 0] <- NA_real_
  segment_length_m <- sqrt(len2)

  raw_t <- ((px - candidate_edges$from_x) * dx + (py - candidate_edges$from_y) * dy) / len2
  t <- pmin(1, pmax(0, raw_t))
  projected_x <- candidate_edges$from_x + t * dx
  projected_y <- candidate_edges$from_y + t * dy

  distance_accident_to_edge_m <- sqrt((px - projected_x)^2 + (py - projected_y)^2)
  distance_to_from_node_m <- t * segment_length_m
  distance_to_to_node_m <- (1 - t) * segment_length_m

  tibble::tibble(
    projected_x_utm = projected_x,
    projected_y_utm = projected_y,
    distance_accident_to_edge_m = distance_accident_to_edge_m,
    distance_to_from_node_m = distance_to_from_node_m,
    distance_to_to_node_m = distance_to_to_node_m,
    projection_fraction_0_1 = t
  )
}

rs_m9_assign_quality_flag <- function(distance_m, candidate_edges_n, tie_candidate_count) {
  if (is.na(distance_m)) {
    return("unmatched")
  }

  if (tie_candidate_count > 1L) {
    return("low_confidence")
  }

  if (distance_m <= rs_m9_high_conf_distance_m && candidate_edges_n == 1L) {
    return("high_confidence")
  }

  if (distance_m <= rs_m9_medium_conf_distance_m && candidate_edges_n <= rs_m9_medium_conf_candidate_max) {
    return("medium_confidence")
  }

  "low_confidence"
}

rs_m9_build_unmatched_no_candidate_row <- function(accident_row, search_radius_m) {
  tibble::tibble(
    accident_row_id = accident_row$accident_row_id,
    num_expediente = accident_row$num_expediente,
    fecha = accident_row$fecha,
    hora = accident_row$hora,
    tipo_accidente = accident_row$tipo_accidente,
    accident_x_utm = accident_row$accident_x_utm,
    accident_y_utm = accident_row$accident_y_utm,
    edge_id = NA_character_,
    distance_accident_to_edge_m = NA_real_,
    candidate_edges_n = 0L,
    search_radius_m = search_radius_m,
    distance_to_from_node_m = NA_real_,
    distance_to_to_node_m = NA_real_,
    projection_fraction_0_1 = NA_real_,
    projected_x_utm = NA_real_,
    projected_y_utm = NA_real_,
    projected_point_geometry = NA_character_,
    quality_flag = "unmatched",
    matching_method = rs_m9_matching_method,
    tie_candidate_count = 0L,
    match_decision_rule = "no_candidate_within_search_radius",
    candidate_top3_edge_ids = NA_character_,
    candidate_top3_distances_m = NA_character_,
    match_status = "unmatched",
    unmatched_reason = "no_candidate_within_search_radius",
    outside_operational_envelope = FALSE
  )
}

rs_m9_build_matched_row <- function(accident_row, candidate_edges, projection_df, search_radius_m) {
  ordering <- order(projection_df$distance_accident_to_edge_m, candidate_edges$edge_length_m, candidate_edges$edge_id)
  best_pos <- ordering[1]
  min_dist <- projection_df$distance_accident_to_edge_m[best_pos]
  tie_candidate_count <- sum(projection_df$distance_accident_to_edge_m <= min_dist + rs_m9_tie_tolerance_m)
  top_n <- min(3L, length(ordering))
  top_idx <- ordering[seq_len(top_n)]

  selected_edge <- candidate_edges[best_pos, ]
  selected_projection <- projection_df[best_pos, ]

  quality_flag <- rs_m9_assign_quality_flag(
    distance_m = selected_projection$distance_accident_to_edge_m,
    candidate_edges_n = nrow(candidate_edges),
    tie_candidate_count = tie_candidate_count
  )

  tibble::tibble(
    accident_row_id = accident_row$accident_row_id,
    num_expediente = accident_row$num_expediente,
    fecha = accident_row$fecha,
    hora = accident_row$hora,
    tipo_accidente = accident_row$tipo_accidente,
    accident_x_utm = accident_row$accident_x_utm,
    accident_y_utm = accident_row$accident_y_utm,
    edge_id = selected_edge$edge_id,
    distance_accident_to_edge_m = selected_projection$distance_accident_to_edge_m,
    candidate_edges_n = nrow(candidate_edges),
    search_radius_m = search_radius_m,
    distance_to_from_node_m = selected_projection$distance_to_from_node_m,
    distance_to_to_node_m = selected_projection$distance_to_to_node_m,
    projection_fraction_0_1 = selected_projection$projection_fraction_0_1,
    projected_x_utm = selected_projection$projected_x_utm,
    projected_y_utm = selected_projection$projected_y_utm,
    projected_point_geometry = sprintf(
      "POINT (%.3f %.3f)",
      selected_projection$projected_x_utm,
      selected_projection$projected_y_utm
    ),
    nearest_edge_id_any = NA_character_,
    nearest_distance_any_m = NA_real_,
    quality_flag = quality_flag,
    matching_method = rs_m9_matching_method,
    tie_candidate_count = tie_candidate_count,
    match_decision_rule = if (tie_candidate_count > 1L) "min_distance_then_edge_length_then_edge_id" else "min_distance",
    candidate_top3_edge_ids = paste(candidate_edges$edge_id[top_idx], collapse = " | "),
    candidate_top3_distances_m = paste(sprintf("%.3f", projection_df$distance_accident_to_edge_m[top_idx]), collapse = " | "),
    match_status = "matched",
    unmatched_reason = NA_character_,
    outside_operational_envelope = FALSE
  )
}

rs_m9_match_ready_accidents <- function(matching_ready_sf, edges_sf, search_radius_m = rs_m9_search_radius_m, batch_size = rs_m9_batch_size_default) {
  edge_attrs <- edges_sf |>
    sf::st_drop_geometry()

  results <- vector("list", length = nrow(matching_ready_sf))
  total_rows <- nrow(matching_ready_sf)

  if (!total_rows) {
    return(dplyr::bind_rows(results))
  }

  batch_starts <- seq(1L, total_rows, by = batch_size)

  for (batch_start in batch_starts) {
    batch_end <- min(batch_start + batch_size - 1L, total_rows)
    batch_idx <- batch_start:batch_end
    batch_sf <- matching_ready_sf[batch_idx, ]
    candidate_list <- sf::st_is_within_distance(batch_sf, edges_sf, dist = search_radius_m)

    for (local_i in seq_along(batch_idx)) {
      global_i <- batch_idx[local_i]
      accident_row <- batch_sf[local_i, ] |>
        sf::st_drop_geometry()
      candidate_idx <- candidate_list[[local_i]]

      if (!length(candidate_idx)) {
        results[[global_i]] <- rs_m9_build_unmatched_no_candidate_row(accident_row, search_radius_m)
        next
      }

      candidate_edges <- edge_attrs[candidate_idx, , drop = FALSE]
      projection_df <- rs_m9_project_point_to_segment(
        px = accident_row$accident_x_utm,
        py = accident_row$accident_y_utm,
        candidate_edges = candidate_edges
      )

      results[[global_i]] <- rs_m9_build_matched_row(
        accident_row = accident_row,
        candidate_edges = candidate_edges,
        projection_df = projection_df,
        search_radius_m = search_radius_m
      )
    }
  }

  dplyr::bind_rows(results)
}

rs_m9_attach_nearest_edge_for_unmatched <- function(unmatched_df, edges_sf) {
  if (!nrow(unmatched_df)) {
    return(unmatched_df)
  }

  unmatched_sf <- sf::st_as_sf(
    unmatched_df,
    coords = c("accident_x_utm", "accident_y_utm"),
    crs = rs_m8_canonical_crs_epsg,
    remove = FALSE
  )

  nearest_idx <- sf::st_nearest_feature(unmatched_sf, edges_sf)
  nearest_edges <- edges_sf[nearest_idx, ]

  nearest_projection <- rs_m9_project_point_to_segment(
    px = unmatched_df$accident_x_utm,
    py = unmatched_df$accident_y_utm,
    candidate_edges = nearest_edges |>
      sf::st_drop_geometry()
  )

  unmatched_df |>
    dplyr::mutate(
      nearest_edge_id_any = nearest_edges$edge_id,
      nearest_distance_any_m = nearest_projection$distance_accident_to_edge_m
    )
}

rs_m9_build_quality_summary <- function(matches_df, unmatched_df, valid_coordinate_n) {
  matched_summary <- matches_df |>
    dplyr::group_by(quality_flag) |>
    dplyr::summarise(
      n = dplyr::n(),
      pct_over_valid_coordinates = round(100 * n / valid_coordinate_n, 2),
      distance_min_m = min(distance_accident_to_edge_m, na.rm = TRUE),
      distance_p50_m = stats::median(distance_accident_to_edge_m, na.rm = TRUE),
      distance_p95_m = as.numeric(stats::quantile(distance_accident_to_edge_m, 0.95, na.rm = TRUE)),
      distance_max_m = max(distance_accident_to_edge_m, na.rm = TRUE),
      candidate_edges_p50 = stats::median(candidate_edges_n, na.rm = TRUE),
      candidate_edges_p95 = as.numeric(stats::quantile(candidate_edges_n, 0.95, na.rm = TRUE)),
      .groups = "drop"
    )

  unmatched_summary <- unmatched_df |>
    dplyr::count(unmatched_reason, name = "n") |>
    dplyr::mutate(
      quality_flag = "unmatched",
      pct_over_valid_coordinates = round(100 * n / valid_coordinate_n, 2),
      distance_min_m = NA_real_,
      distance_p50_m = NA_real_,
      distance_p95_m = NA_real_,
      distance_max_m = NA_real_,
      candidate_edges_p50 = NA_real_,
      candidate_edges_p95 = NA_real_
    ) |>
    dplyr::rename(detail = unmatched_reason) |>
    dplyr::select(
      quality_flag,
      detail,
      n,
      pct_over_valid_coordinates,
      distance_min_m,
      distance_p50_m,
      distance_p95_m,
      distance_max_m,
      candidate_edges_p50,
      candidate_edges_p95
    )

  matched_summary |>
    dplyr::mutate(detail = quality_flag, .before = 2) |>
    dplyr::bind_rows(unmatched_summary)
}

rs_m9_build_validation_summary <- function(accident_master, prepared, matches_df, unmatched_df, edges_sf) {
  projected_points_sf <- if (nrow(matches_df)) {
    sf::st_as_sf(
      matches_df,
      coords = c("projected_x_utm", "projected_y_utm"),
      crs = rs_m8_canonical_crs_epsg,
      remove = FALSE
    )
  } else {
    NULL
  }

  distance_values <- if (nrow(matches_df)) matches_df$distance_accident_to_edge_m else numeric(0)

  tibble::tibble(
    metric = c(
      "accidents_total_n",
      "accidents_valid_coordinates_n",
      "accidents_inside_operational_envelope_n",
      "accidents_outside_operational_envelope_n",
      "matched_n",
      "matched_pct_over_valid_coordinates",
      "matched_pct_over_inside_envelope",
      "unmatched_n",
      "unmatched_due_invalid_coordinates_n",
      "unmatched_due_outside_operational_envelope_n",
      "unmatched_due_no_candidate_within_radius_n",
      "high_confidence_n",
      "medium_confidence_n",
      "low_confidence_n",
      "distance_p50_m",
      "distance_p95_m",
      "projected_point_geometry_valid",
      "matched_edge_id_exists_in_network",
      "outside_operational_envelope_report_generated",
      "output_schema_version",
      "working_crs_epsg",
      "search_radius_m"
    ),
    value = c(
      as.character(nrow(accident_master)),
      as.character(prepared$valid_coordinate_n),
      as.character(prepared$inside_envelope_n),
      as.character(prepared$outside_envelope_n),
      as.character(nrow(matches_df)),
      sprintf("%.2f", 100 * nrow(matches_df) / prepared$valid_coordinate_n),
      sprintf("%.2f", 100 * nrow(matches_df) / prepared$inside_envelope_n),
      as.character(nrow(unmatched_df)),
      as.character(sum(unmatched_df$unmatched_reason == "invalid_coordinates")),
      as.character(sum(unmatched_df$unmatched_reason == "outside_operational_envelope")),
      as.character(sum(unmatched_df$unmatched_reason == "no_candidate_within_search_radius")),
      as.character(sum(matches_df$quality_flag == "high_confidence")),
      as.character(sum(matches_df$quality_flag == "medium_confidence")),
      as.character(sum(matches_df$quality_flag == "low_confidence")),
      if (length(distance_values)) sprintf("%.3f", stats::median(distance_values)) else NA_character_,
      if (length(distance_values)) sprintf("%.3f", as.numeric(stats::quantile(distance_values, 0.95))) else NA_character_,
      if (is.null(projected_points_sf)) "TRUE" else as.character(all(sf::st_is_valid(projected_points_sf))),
      as.character(all(matches_df$edge_id %in% edges_sf$edge_id)),
      "TRUE",
      rs_m9_output_schema_version,
      as.character(rs_m8_canonical_crs_epsg),
      as.character(rs_m9_search_radius_m)
    )
  )
}

rs_m9_build_matching_note <- function(validation_summary) {
  get_metric <- function(metric_name) {
    value <- validation_summary |>
      dplyr::filter(metric == metric_name) |>
      dplyr::pull(value)
    if (!length(value)) {
      return(NA_character_)
    }
    value[[1]]
  }

  paste(
    "# M9 - Matching real accidente -> edge",
    "",
    "## Metodo",
    sprintf("- Matching geometrico puro contra la red canonica de M8 en `EPSG:%s`.", rs_m8_canonical_crs_epsg),
    sprintf("- Radio inicial de busqueda: `%sm`.", rs_m9_search_radius_m),
    sprintf("- Regla de seleccion: `%s`.", rs_m9_matching_method),
    sprintf("- Desempate: distancia minima; si hay varios candidatos dentro de `%sm` del minimo, se resuelve de forma determinista por `edge_length_m` y luego `edge_id`, y se degrada la calidad.", rs_m9_tie_tolerance_m),
    sprintf("- Schema final adoptado: `%s`.", rs_m9_output_schema_version),
    "- `edge_id` es la arista canonica seleccionada.",
    "- `projected_point_geometry` se guarda como WKT en CSV; el GeoJSON lleva la geometria proyectada real.",
    "- `match_status` se mantiene binario (`matched` / `unmatched`); la ambiguedad se refleja solo en `quality_flag` y en las columnas de trazabilidad.",
    "",
    "## Umbrales de calidad",
    sprintf("- `high_confidence`: distancia <= %sm y un solo candidato.", rs_m9_high_conf_distance_m),
    sprintf("- `medium_confidence`: distancia <= %sm y hasta %s candidatos.", rs_m9_medium_conf_distance_m, rs_m9_medium_conf_candidate_max),
    "- `low_confidence`: match dentro del radio pero mas ambiguo o mas lejano.",
    "- `unmatched`: coordenadas invalidas, fuera del envelope operativo o sin edge candidato dentro del radio.",
    "",
    "## Cobertura observada",
    sprintf("- Accidentes validos para matching: %s", get_metric("accidents_valid_coordinates_n")),
    sprintf("- Accidentes dentro del envelope operativo: %s", get_metric("accidents_inside_operational_envelope_n")),
    sprintf("- Matched: %s (%s%% sobre coordenadas validas)", get_metric("matched_n"), get_metric("matched_pct_over_valid_coordinates")),
    sprintf("- Unmatched: %s", get_metric("unmatched_n")),
    sprintf("- Accidentes fuera del envelope operativo: %s", get_metric("accidents_outside_operational_envelope_n")),
    sprintf("- Distribucion resumida de distancia: p50=%sm, p95=%sm", get_metric("distance_p50_m"), get_metric("distance_p95_m")),
    "- Los accidentes fuera del envelope operativo se guardan tambien en `m9_outside_operational_envelope_accidents.csv` con el edge canonico mas cercano solo como referencia diagnostica.",
    "",
    "## Que no hace M9",
    "- No calcula todavia score final por edge.",
    "- No implementa routing.",
    "- No usa joins ingenuos por `id_sensor_cercano` ni por `Id. Tram`.",
    "",
    sep = "\n"
  )
}

rs_m9_prepare_matches_for_serialization <- function(matches_df) {
  matches_df |>
    dplyr::mutate(
      projected_point_geometry = as.character(projected_point_geometry),
      hora = if ("hora" %in% names(matches_df)) as.character(hora) else hora
    )
}

rs_m9_write_outputs <- function(matches_df, unmatched_df, quality_summary, thresholds, validation_summary, matching_note, output_paths) {
  matches_csv <- rs_m9_prepare_matches_for_serialization(matches_df)
  outside_envelope_df <- unmatched_df |>
    dplyr::filter(unmatched_reason == "outside_operational_envelope")

  readr::write_csv(matches_csv, output_paths$matches_csv)
  readr::write_csv(unmatched_df, output_paths$unmatched_csv)
  readr::write_csv(outside_envelope_df, output_paths$outside_envelope_csv)
  readr::write_csv(quality_summary, output_paths$quality_summary_csv)
  readr::write_csv(thresholds, output_paths$thresholds_csv)
  readr::write_csv(validation_summary, output_paths$validation_csv)
  writeLines(matching_note, output_paths$note_md, useBytes = TRUE)

  if (file.exists(output_paths$matches_geojson)) {
    file.remove(output_paths$matches_geojson)
  }

  matches_geojson <- if (nrow(matches_df)) {
    sf::st_as_sf(
      matches_csv,
      coords = c("projected_x_utm", "projected_y_utm"),
      crs = rs_m8_canonical_crs_epsg,
      remove = FALSE
    ) |>
      sf::st_transform(rs_m8_source_crs_epsg)
  } else {
    sf::st_sf(matches_df, geometry = sf::st_sfc(crs = rs_m8_source_crs_epsg))
  }

  sf::st_write(matches_geojson, output_paths$matches_geojson, driver = "GeoJSON", quiet = TRUE)
}

rs_run_m9_accidente_edge_matching <- function(accident_master, m8_result, paths, force_refresh = FALSE, batch_size = rs_m9_batch_size_default) {
  rs_check_m9_packages()
  rs_validate_m9_inputs(accident_master, m8_result, paths)

  output_paths <- rs_m9_output_paths(paths)
  if (!force_refresh && rs_m9_cache_is_current(output_paths)) {
    cached <- rs_m9_read_cached_outputs(output_paths)
    cached$used_cache <- TRUE
    return(cached)
  }

  edges_sf <- rs_m9_load_edges(m8_result)
  prepared <- rs_m9_prepare_accidents_for_matching(
    accident_master = accident_master,
    edges_sf = edges_sf,
    search_radius_m = rs_m9_search_radius_m
  )

  matching_results <- rs_m9_match_ready_accidents(
    matching_ready_sf = prepared$matching_ready_sf,
    edges_sf = edges_sf,
    search_radius_m = rs_m9_search_radius_m,
    batch_size = batch_size
  )

  matched_df <- matching_results |>
    dplyr::filter(match_status == "matched")
  unmatched_radius_df <- matching_results |>
    dplyr::filter(match_status == "unmatched")

  unmatched_valid_df <- dplyr::bind_rows(
    prepared$outside_unmatched,
    unmatched_radius_df
  )

  if (nrow(unmatched_valid_df)) {
    unmatched_valid_df <- rs_m9_attach_nearest_edge_for_unmatched(unmatched_valid_df, edges_sf)
  } else {
    unmatched_valid_df <- unmatched_valid_df |>
      dplyr::mutate(
        nearest_edge_id_any = character(),
        nearest_distance_any_m = numeric()
      )
  }

  unmatched_df <- dplyr::bind_rows(
    prepared$invalid_unmatched,
    unmatched_valid_df
  ) |>
    dplyr::arrange(accident_row_id)

  matched_df <- matched_df |>
    dplyr::arrange(accident_row_id)

  quality_summary <- rs_m9_build_quality_summary(
    matches_df = matched_df,
    unmatched_df = unmatched_df,
    valid_coordinate_n = prepared$valid_coordinate_n
  )
  thresholds <- rs_m9_expected_thresholds()
  validation_summary <- rs_m9_build_validation_summary(
    accident_master = accident_master,
    prepared = prepared,
    matches_df = matched_df,
    unmatched_df = unmatched_df,
    edges_sf = edges_sf
  )
  matching_note <- rs_m9_build_matching_note(validation_summary)

  rs_m9_write_outputs(
    matches_df = matched_df,
    unmatched_df = unmatched_df,
    quality_summary = quality_summary,
    thresholds = thresholds,
    validation_summary = validation_summary,
    matching_note = matching_note,
    output_paths = output_paths
  )

  list(
    matches = matched_df,
    unmatched = unmatched_df,
    outside_operational_envelope = unmatched_df |>
      dplyr::filter(unmatched_reason == "outside_operational_envelope"),
    quality_summary = quality_summary,
    thresholds = thresholds,
    validation_summary = validation_summary,
    matching_note = matching_note,
    used_cache = FALSE
  )
}
