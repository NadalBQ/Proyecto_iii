rs_m11_output_schema_version <- "m11_schema_v1_sensor_proxy_plus_traffic_crosswalk_diagnostics"
rs_m11_tramo_buffer_m <- 20
rs_m11_sensor_primary_share_high <- 0.75
rs_m11_sensor_primary_share_medium <- 0.50
rs_m11_sensor_weight_high <- 3
rs_m11_sensor_weight_medium <- 2
rs_m11_exposure_floor <- 0.25
rs_m11_adjusted_score_cap_quantile <- 0.95

rs_check_m11_packages <- function() {
  required_packages <- c("dplyr", "tibble", "readr", "sf", "jsonlite")
  missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]

  if (length(missing_packages) > 0L) {
    stop(
      sprintf(
        "Faltan paquetes requeridos para M11: %s",
        paste(missing_packages, collapse = ", ")
      ),
      call. = FALSE
    )
  }
}

rs_validate_m11_inputs <- function(m8_result, paths) {
  if (missing(m8_result) || is.null(m8_result)) {
    stop("M11 necesita los artefactos de M8 para la red canonica.", call. = FALSE)
  }

  if (!"edges_path" %in% names(m8_result) || !file.exists(m8_result$edges_path)) {
    stop("M11 necesita `edges_path` valido dentro de m8_result.", call. = FALSE)
  }

  required_paths <- c("output_data", "output_tables")
  if (!all(required_paths %in% names(paths))) {
    stop("M11 necesita output_data y output_tables dentro de paths.", call. = FALSE)
  }
}

rs_m11_output_paths <- function(paths) {
  list(
    traffic_crosswalk_csv = file.path(paths$output_data, "m11_edge_traffic_crosswalk.csv"),
    sensor_crosswalk_csv = file.path(paths$output_data, "m11_edge_sensor_crosswalk.csv"),
    exposure_baseline_csv = file.path(paths$output_data, "m11_edge_exposure_baseline.csv"),
    historical_adjusted_csv = file.path(paths$output_data, "m11_historical_exposure_adjusted.csv"),
    crosswalk_quality_summary_csv = file.path(paths$output_tables, "m11_crosswalk_quality_summary.csv"),
    exposure_note_md = file.path(paths$output_tables, "m11_exposure_note.md"),
    validation_summary_csv = file.path(paths$output_tables, "m11_validation_summary.csv")
  )
}

rs_m11_artifacts_ready <- function(output_paths) {
  all(file.exists(unlist(output_paths, use.names = FALSE)))
}

rs_m11_cache_is_current <- function(output_paths) {
  if (!rs_m11_artifacts_ready(output_paths)) {
    return(FALSE)
  }

  validation <- tryCatch(
    readr::read_csv(output_paths$validation_summary_csv, show_col_types = FALSE),
    error = function(...) NULL
  )

  if (is.null(validation)) {
    return(FALSE)
  }

  schema_value <- validation |>
    dplyr::filter(metric == "output_schema_version") |>
    dplyr::pull(value)

  length(schema_value) == 1L && identical(schema_value[[1]], rs_m11_output_schema_version)
}

rs_m11_read_cached_outputs <- function(output_paths) {
  list(
    traffic_crosswalk = readr::read_csv(output_paths$traffic_crosswalk_csv, show_col_types = FALSE),
    sensor_crosswalk = readr::read_csv(output_paths$sensor_crosswalk_csv, show_col_types = FALSE),
    exposure_baseline = readr::read_csv(output_paths$exposure_baseline_csv, show_col_types = FALSE),
    historical_exposure_adjusted = readr::read_csv(output_paths$historical_adjusted_csv, show_col_types = FALSE),
    crosswalk_quality_summary = readr::read_csv(output_paths$crosswalk_quality_summary_csv, show_col_types = FALSE),
    validation_summary = readr::read_csv(output_paths$validation_summary_csv, show_col_types = FALSE),
    exposure_note = paste(readLines(output_paths$exposure_note_md, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
    used_cache = TRUE
  )
}

rs_m11_load_edges <- function(m8_result) {
  edges_sf <- sf::st_read(m8_result$edges_path, quiet = TRUE)

  required_columns <- c("edge_id", "edge_length_m")
  missing_columns <- setdiff(required_columns, names(edges_sf))
  if (length(missing_columns) > 0L) {
    stop(
      sprintf(
        "Faltan columnas requeridas en la red canonica para M11: %s",
        paste(missing_columns, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  if (!identical(sf::st_crs(edges_sf)$epsg, rs_m8_canonical_crs_epsg)) {
    stop(
      sprintf(
        "La red canonica de M8 no esta en EPSG:%s.",
        rs_m8_canonical_crs_epsg
      ),
      call. = FALSE
    )
  }

  edges_sf
}

rs_m11_load_m9_matches <- function(m9_result, paths) {
  if (!missing(m9_result) && !is.null(m9_result) && "matches" %in% names(m9_result)) {
    return(m9_result$matches)
  }

  matches_path <- file.path(paths$output_data, "m9_accident_edge_matches.csv")
  if (!file.exists(matches_path)) {
    stop("M11 necesita `m9_accident_edge_matches.csv`.", call. = FALSE)
  }

  readr::read_csv(matches_path, show_col_types = FALSE)
}

rs_m11_load_m10_aggregation <- function(m10_result, paths) {
  if (!missing(m10_result) && !is.null(m10_result) && "aggregation" %in% names(m10_result)) {
    return(m10_result$aggregation)
  }

  aggregation_path <- file.path(paths$output_data, "m10_edge_historical_aggregation.csv")
  if (!file.exists(aggregation_path)) {
    stop("M11 necesita `m10_edge_historical_aggregation.csv`.", call. = FALSE)
  }

  aggregation <- readr::read_csv(aggregation_path, show_col_types = FALSE)

  if (!"edge_length_m" %in% names(aggregation)) {
    edge_length_candidates <- intersect(c("edge_length_m.x", "edge_length_m.y"), names(aggregation))

    if (!length(edge_length_candidates)) {
      stop("M11 no encontro `edge_length_m` ni columnas equivalentes dentro de `m10_edge_historical_aggregation.csv`.", call. = FALSE)
    }

    aggregation$edge_length_m <- aggregation[[edge_length_candidates[[1]]]]
  }

  aggregation
}

rs_m11_load_accident_master <- function(accident_master, paths) {
  if (!missing(accident_master) && !is.null(accident_master) && nrow(accident_master)) {
    return(accident_master)
  }

  master_path <- file.path(paths$output_data, "accidentes_tabla_accidente_master.csv")
  if (!file.exists(master_path)) {
    stop("M11 necesita `accidentes_tabla_accidente_master.csv`.", call. = FALSE)
  }

  readr::read_csv(master_path, show_col_types = FALSE)
}

rs_m11_load_m10_quality_weights <- function(paths) {
  weights_path <- file.path(paths$output_tables, "m10_quality_weighting_rule.csv")
  if (!file.exists(weights_path)) {
    stop("M11 necesita `m10_quality_weighting_rule.csv` para mantener consistencia con M10.", call. = FALSE)
  }

  readr::read_csv(weights_path, show_col_types = FALSE) |>
    dplyr::select(quality_flag, weight)
}

rs_m11_load_trafico_tramos <- function(project_dir) {
  tramo_path <- file.path(project_dir, "bases de datos", "estat-transit-temps-real-estado-trafico-tiempo-real.csv")
  if (!file.exists(tramo_path)) {
    stop("M11 no encontro la capa lineal de trafico `estat-transit-temps-real-estado-trafico-tiempo-real.csv`.", call. = FALSE)
  }

  tramos_raw <- readr::read_delim(
    tramo_path,
    delim = ";",
    show_col_types = FALSE,
    progress = FALSE
  )

  current_names <- names(tramos_raw)
  tramo_name_col <- current_names[grepl("Denomin", current_names, ignore.case = TRUE)][1]
  tramo_state_col <- current_names[grepl("^Estat / Estado$", current_names, ignore.case = TRUE)][1]
  tramo_id_col <- current_names[grepl("Id\\. Tram / Id\\. Tramo", current_names, ignore.case = TRUE)][1]

  if (any(is.na(c(tramo_name_col, tramo_state_col, tramo_id_col)))) {
    stop("M11 no pudo reconocer las columnas clave de la capa lineal de trafico.", call. = FALSE)
  }

  names(tramos_raw)[names(tramos_raw) == tramo_name_col] <- "tramo_name"
  names(tramos_raw)[names(tramos_raw) == tramo_state_col] <- "tramo_state"
  names(tramos_raw)[names(tramos_raw) == tramo_id_col] <- "tramo_id"

  parse_linestring <- function(geo_shape_value) {
    parsed <- tryCatch(jsonlite::fromJSON(geo_shape_value), error = function(...) NULL)

    if (is.null(parsed) || is.null(parsed$type) || !identical(parsed$type, "LineString")) {
      return(NULL)
    }

    coords <- parsed$coordinates
    if (is.list(coords)) {
      coords <- do.call(rbind, coords)
    }

    coords <- as.matrix(coords)
    if (!is.matrix(coords) || nrow(coords) < 2L || ncol(coords) < 2L) {
      return(NULL)
    }

    sf::st_linestring(matrix(as.numeric(coords[, 1:2]), ncol = 2L))
  }

  geometries <- lapply(tramos_raw$geo_shape, parse_linestring)
  geometry_valid <- vapply(geometries, function(x) !is.null(x), logical(1))

  parse_point <- function(value, idx) {
    parts <- strsplit(value, ",", fixed = TRUE)
    coords <- trimws(vapply(parts, function(x) if (length(x) >= idx) x[[idx]] else NA_character_, character(1)))
    suppressWarnings(as.numeric(coords))
  }

  tramos_df <- tramos_raw |>
    dplyr::mutate(
      tramo_id = as.character(tramo_id),
      geo_point_lat = parse_point(geo_point_2d, 1),
      geo_point_lon = parse_point(geo_point_2d, 2),
      geometry_parse_ok = geometry_valid
    )

  tramos_sf <- sf::st_sf(
    tramos_df[geometry_valid, , drop = FALSE],
    geometry = sf::st_sfc(geometries[geometry_valid], crs = rs_m8_source_crs_epsg)
  ) |>
    sf::st_transform(rs_m8_canonical_crs_epsg) |>
    dplyr::mutate(
      tramo_length_m = as.numeric(sf::st_length(geometry))
    )

  list(
    tramos_sf = tramos_sf,
    tramos_raw = tramos_df,
    tramo_rows_total = nrow(tramos_df),
    tramo_geometry_valid_n = sum(geometry_valid)
  )
}

rs_m11_build_traffic_crosswalk <- function(tramos_info, edges_sf, buffer_m = rs_m11_tramo_buffer_m) {
  tramos_sf <- tramos_info$tramos_sf

  if (!nrow(tramos_sf)) {
    return(list(
      crosswalk = tibble::tibble(
        tramo_id = character(),
        tramo_name = character(),
        edge_id = character(),
        crosswalk_status = character(),
        crosswalk_quality_flag = character(),
        link_method = character(),
        candidate_edges_n = integer(),
        buffer_m = numeric(),
        tramo_length_m = numeric(),
        overlap_length_m = numeric(),
        overlap_ratio_to_tramo = numeric(),
        is_primary_link = logical(),
        nearest_edge_id_any = character(),
        nearest_distance_any_m = numeric(),
        bbox_overlap_with_network = logical(),
        notes_or_limitations = character()
      ),
      bbox_overlap_with_network = FALSE
    ))
  }

  bbox_overlap <- lengths(sf::st_intersects(sf::st_as_sfc(sf::st_bbox(tramos_sf)), sf::st_as_sfc(sf::st_bbox(edges_sf)))) > 0

  if (!bbox_overlap) {
    nearest_idx <- sf::st_nearest_feature(tramos_sf, edges_sf)
    nearest_edges <- edges_sf[nearest_idx, ]
    nearest_distance <- as.numeric(sf::st_distance(tramos_sf, nearest_edges, by_element = TRUE))

    crosswalk <- tramos_sf |>
      sf::st_drop_geometry() |>
      dplyr::transmute(
        tramo_id,
        tramo_name,
        edge_id = NA_character_,
        crosswalk_status = "outside_network_operational_area",
        crosswalk_quality_flag = "no_usable_spatial_overlap",
        link_method = "buffered_linestring_overlay_then_nearest_edge_diagnostic",
        candidate_edges_n = 0L,
        buffer_m = buffer_m,
        tramo_length_m = round(tramo_length_m, 3),
        overlap_length_m = 0,
        overlap_ratio_to_tramo = 0,
        is_primary_link = FALSE,
        nearest_edge_id_any = nearest_edges$edge_id,
        nearest_distance_any_m = round(nearest_distance, 3),
        bbox_overlap_with_network = FALSE,
        notes_or_limitations = "Traffic tramo layer falls outside the operational envelope of the canonical network; no usable geometric edge link."
      )

    return(list(
      crosswalk = crosswalk,
      bbox_overlap_with_network = FALSE
    ))
  }

  tramo_buffers <- sf::st_buffer(tramos_sf, buffer_m)
  candidate_list <- sf::st_intersects(tramo_buffers, edges_sf)
  crosswalk_rows <- vector("list", length = nrow(tramos_sf))

  for (i in seq_len(nrow(tramos_sf))) {
    tramo_row <- tramos_sf[i, ]
    candidate_idx <- candidate_list[[i]]

    if (!length(candidate_idx)) {
      nearest_idx <- sf::st_nearest_feature(tramo_row, edges_sf)
      nearest_edge <- edges_sf[nearest_idx, ]
      nearest_distance <- as.numeric(sf::st_distance(tramo_row, nearest_edge, by_element = TRUE))

      crosswalk_rows[[i]] <- tramo_row |>
        sf::st_drop_geometry() |>
        dplyr::transmute(
          tramo_id,
          tramo_name,
          edge_id = NA_character_,
          crosswalk_status = "no_candidate_within_buffer",
          crosswalk_quality_flag = "no_usable_spatial_overlap",
          link_method = "buffered_linestring_overlay_then_nearest_edge_diagnostic",
          candidate_edges_n = 0L,
          buffer_m = buffer_m,
          tramo_length_m = round(tramo_length_m, 3),
          overlap_length_m = 0,
          overlap_ratio_to_tramo = 0,
          is_primary_link = FALSE,
          nearest_edge_id_any = nearest_edge$edge_id,
          nearest_distance_any_m = round(nearest_distance, 3),
          bbox_overlap_with_network = TRUE,
          notes_or_limitations = "Tramo bbox overlaps the network, but no edge falls within the configured geometric buffer."
        )
      next
    }

    candidate_edges <- edges_sf[candidate_idx, ]
    candidate_distances <- as.numeric(sf::st_distance(candidate_edges, tramo_row, by_element = FALSE))

    overlap_geom <- suppressWarnings(sf::st_intersection(candidate_edges, tramo_buffers[i, ]))
    overlap_summary <- if (nrow(overlap_geom)) {
      overlap_geom |>
        dplyr::mutate(overlap_length_m = as.numeric(sf::st_length(geometry))) |>
        sf::st_drop_geometry() |>
        dplyr::group_by(edge_id) |>
        dplyr::summarise(overlap_length_m = sum(overlap_length_m), .groups = "drop")
    } else {
      tibble::tibble(edge_id = candidate_edges$edge_id, overlap_length_m = 0)
    }

    candidate_df <- candidate_edges |>
      sf::st_drop_geometry() |>
      dplyr::select(edge_id) |>
      dplyr::mutate(
        distance_to_tramo_m = candidate_distances
      ) |>
      dplyr::left_join(overlap_summary, by = "edge_id") |>
      dplyr::mutate(
        overlap_length_m = dplyr::coalesce(overlap_length_m, 0),
        tramo_length_m = tramo_row$tramo_length_m[[1]],
        overlap_ratio_to_tramo = dplyr::if_else(tramo_length_m > 0, overlap_length_m / tramo_length_m, 0),
        candidate_edges_n = nrow(candidate_edges)
      ) |>
      dplyr::arrange(dplyr::desc(overlap_length_m), distance_to_tramo_m, edge_id) |>
      dplyr::mutate(
        is_primary_link = dplyr::row_number() == 1L,
        crosswalk_status = dplyr::if_else(overlap_length_m > 0, "linked", "nearby_candidate_without_overlap"),
        crosswalk_quality_flag = dplyr::case_when(
          overlap_ratio_to_tramo >= 0.50 ~ "high_overlap",
          overlap_ratio_to_tramo >= 0.10 ~ "medium_overlap",
          overlap_length_m > 0 ~ "low_overlap",
          TRUE ~ "nearby_only"
        ),
        link_method = "buffered_linestring_overlay_then_overlap_ranking",
        buffer_m = buffer_m,
        nearest_edge_id_any = first(edge_id),
        nearest_distance_any_m = min(distance_to_tramo_m, na.rm = TRUE),
        bbox_overlap_with_network = TRUE,
        notes_or_limitations = dplyr::case_when(
          crosswalk_status == "linked" ~ "Traffic tramo linked to canonical edges through buffered geometric overlap.",
          TRUE ~ "Traffic tramo is near the network envelope but does not produce usable overlap against canonical edges."
        )
      ) |>
      dplyr::transmute(
        tramo_id = tramo_row$tramo_id[[1]],
        tramo_name = tramo_row$tramo_name[[1]],
        edge_id,
        crosswalk_status,
        crosswalk_quality_flag,
        link_method,
        candidate_edges_n,
        buffer_m,
        tramo_length_m = round(tramo_length_m, 3),
        overlap_length_m = round(overlap_length_m, 3),
        overlap_ratio_to_tramo = round(overlap_ratio_to_tramo, 4),
        is_primary_link,
        nearest_edge_id_any,
        nearest_distance_any_m = round(nearest_distance_any_m, 3),
        bbox_overlap_with_network,
        notes_or_limitations
      )

    crosswalk_rows[[i]] <- candidate_df
  }

  list(
    crosswalk = dplyr::bind_rows(crosswalk_rows),
    bbox_overlap_with_network = TRUE
  )
}

rs_m11_percent_rank_nonmissing <- function(x) {
  result <- rep(NA_real_, length(x))
  non_missing <- !is.na(x)

  if (sum(non_missing) == 1L) {
    result[non_missing] <- 1
    return(result)
  }

  if (sum(non_missing) > 1L) {
    result[non_missing] <- dplyr::percent_rank(x[non_missing])
  }

  result
}

rs_m11_prepare_sensor_crosswalk <- function(matches_df, accident_master, quality_weights) {
  required_master_columns <- c("num_expediente", "id_sensor_cercano", "intensidad", "ocupacion", "vmed")
  missing_columns <- setdiff(required_master_columns, names(accident_master))

  if (length(missing_columns) > 0L) {
    stop(
      sprintf(
        "Faltan columnas requeridas en accident_master para M11: %s",
        paste(missing_columns, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  matches_augmented <- matches_df |>
    dplyr::select(num_expediente, edge_id, quality_flag, match_status) |>
    dplyr::filter(match_status == "matched") |>
    dplyr::left_join(quality_weights, by = "quality_flag") |>
    dplyr::left_join(
      accident_master |>
        dplyr::select(num_expediente, id_sensor_cercano, intensidad, ocupacion, vmed),
      by = "num_expediente"
    ) |>
    dplyr::mutate(
      sensor_id = as.character(id_sensor_cercano),
      matched_quality_weight = dplyr::coalesce(weight, 0)
    ) |>
    dplyr::select(-id_sensor_cercano, -weight)

  sensor_profiles <- matches_augmented |>
    dplyr::group_by(sensor_id) |>
    dplyr::summarise(
      sensor_citywide_accident_n = dplyr::n(),
      sensor_citywide_weighted_n = sum(matched_quality_weight),
      sensor_intensidad_obs_n = sum(!is.na(intensidad)),
      sensor_intensidad_median = if (sum(!is.na(intensidad)) > 0) stats::median(intensidad, na.rm = TRUE) else NA_real_,
      sensor_ocupacion_obs_n = sum(!is.na(ocupacion)),
      sensor_ocupacion_median = if (sum(!is.na(ocupacion)) > 0) stats::median(ocupacion, na.rm = TRUE) else NA_real_,
      sensor_vmed_obs_n = sum(!is.na(vmed)),
      sensor_vmed_median = if (sum(!is.na(vmed)) > 0) stats::median(vmed, na.rm = TRUE) else NA_real_,
      .groups = "drop"
    ) |>
    dplyr::mutate(
      sensor_intensidad_rank01 = rs_m11_percent_rank_nonmissing(sensor_intensidad_median),
      sensor_ocupacion_rank01 = rs_m11_percent_rank_nonmissing(sensor_ocupacion_median),
      sensor_exposure_index = dplyr::if_else(
        !is.na(sensor_intensidad_rank01) | !is.na(sensor_ocupacion_rank01),
        rowMeans(cbind(sensor_intensidad_rank01, sensor_ocupacion_rank01), na.rm = TRUE),
        NA_real_
      )
    )

  sensor_crosswalk <- matches_augmented |>
    dplyr::group_by(edge_id, sensor_id) |>
    dplyr::summarise(
      matched_accident_n = dplyr::n(),
      matched_accident_weighted_n = sum(matched_quality_weight),
      edge_sensor_intensidad_obs_n = sum(!is.na(intensidad)),
      edge_sensor_ocupacion_obs_n = sum(!is.na(ocupacion)),
      .groups = "drop"
    ) |>
    dplyr::left_join(sensor_profiles, by = "sensor_id") |>
    dplyr::group_by(edge_id) |>
    dplyr::mutate(
      edge_sensor_weighted_total = sum(matched_accident_weighted_n),
      edge_sensor_weighted_share = dplyr::if_else(edge_sensor_weighted_total > 0, matched_accident_weighted_n / edge_sensor_weighted_total, 0),
      edge_sensor_rank = dplyr::min_rank(dplyr::desc(matched_accident_weighted_n)),
      is_primary_sensor = edge_sensor_rank == 1L
    ) |>
    dplyr::ungroup() |>
    dplyr::mutate(
      sensor_crosswalk_quality_flag = dplyr::case_when(
        is.na(sensor_exposure_index) ~ "no_numeric_proxy",
        edge_sensor_weighted_share >= rs_m11_sensor_primary_share_high & matched_accident_weighted_n >= rs_m11_sensor_weight_high ~ "dominant_sensor_high",
        edge_sensor_weighted_share >= rs_m11_sensor_primary_share_medium & matched_accident_weighted_n >= rs_m11_sensor_weight_medium ~ "dominant_sensor_medium",
        TRUE ~ "multi_sensor_or_sparse"
      ),
      link_method = "accident_backed_sensor_link_from_m9_matches",
      notes_or_limitations = dplyr::case_when(
        is.na(sensor_exposure_index) ~ "Sensor link exists via matched accidents, but no numeric intensidad/ocupacion proxy is available for this sensor.",
        is_primary_sensor & edge_sensor_weighted_share >= rs_m11_sensor_primary_share_high ~ "Primary sensor dominates the matched evidence on this edge.",
        TRUE ~ "Edge is linked to multiple sensors or sparse evidence; treat the proxy as lower confidence."
      )
    ) |>
    dplyr::arrange(edge_id, dplyr::desc(matched_accident_weighted_n), sensor_id)

  list(
    matches_augmented = matches_augmented,
    sensor_crosswalk = sensor_crosswalk
  )
}

rs_m11_build_exposure_baseline <- function(m10_aggregation, sensor_crosswalk, traffic_crosswalk) {
  linked_tramo_summary <- traffic_crosswalk |>
    dplyr::filter(!is.na(edge_id), crosswalk_status == "linked") |>
    dplyr::group_by(edge_id) |>
    dplyr::summarise(
      linked_tramo_n = dplyr::n_distinct(tramo_id),
      linked_tramo_overlap_total_m = sum(overlap_length_m, na.rm = TRUE),
      .groups = "drop"
    )

  sensor_edge_summary <- sensor_crosswalk |>
    dplyr::group_by(edge_id) |>
    dplyr::summarise(
      linked_sensor_n = dplyr::n_distinct(sensor_id),
      primary_sensor_id = sensor_id[which.max(matched_accident_weighted_n)][1],
      primary_sensor_weighted_share = edge_sensor_weighted_share[which.max(matched_accident_weighted_n)][1],
      primary_sensor_quality_flag = sensor_crosswalk_quality_flag[which.max(matched_accident_weighted_n)][1],
      sensor_proxy_support_weighted_n = sum(matched_accident_weighted_n[!is.na(sensor_exposure_index)], na.rm = TRUE),
      sensor_proxy_support_accident_n = sum(matched_accident_n[!is.na(sensor_exposure_index)], na.rm = TRUE),
      exposure_proxy_value = if (sum(!is.na(sensor_exposure_index)) > 0) stats::weighted.mean(sensor_exposure_index[!is.na(sensor_exposure_index)], matched_accident_weighted_n[!is.na(sensor_exposure_index)]) else NA_real_,
      sensor_intensidad_rank_proxy = if (sum(!is.na(sensor_intensidad_rank01)) > 0) stats::weighted.mean(sensor_intensidad_rank01[!is.na(sensor_intensidad_rank01)], matched_accident_weighted_n[!is.na(sensor_intensidad_rank01)]) else NA_real_,
      sensor_ocupacion_rank_proxy = if (sum(!is.na(sensor_ocupacion_rank01)) > 0) stats::weighted.mean(sensor_ocupacion_rank01[!is.na(sensor_ocupacion_rank01)], matched_accident_weighted_n[!is.na(sensor_ocupacion_rank01)]) else NA_real_,
      .groups = "drop"
    )

  traffic_layer_usable <- any(!is.na(traffic_crosswalk$edge_id))

  exposure_baseline <- m10_aggregation |>
    dplyr::select(edge_id, edge_length_m) |>
    dplyr::left_join(sensor_edge_summary, by = "edge_id") |>
    dplyr::left_join(linked_tramo_summary, by = "edge_id") |>
    dplyr::mutate(
      linked_sensor_n = dplyr::coalesce(linked_sensor_n, 0L),
      linked_tramo_n = dplyr::coalesce(linked_tramo_n, 0L),
      linked_tramo_overlap_total_m = dplyr::coalesce(linked_tramo_overlap_total_m, 0),
      exposure_proxy_type = dplyr::case_when(
        !is.na(exposure_proxy_value) ~ "sensor_context_index_from_accident_backed_intensidad_ocupacion",
        linked_sensor_n > 0 ~ "sensor_link_only_no_numeric_context",
        linked_tramo_n > 0 ~ "traffic_tramo_geometric_link_only",
        TRUE ~ "no_proxy_available"
      ),
      exposure_quality_flag = dplyr::case_when(
        !is.na(exposure_proxy_value) & primary_sensor_weighted_share >= rs_m11_sensor_primary_share_high & linked_sensor_n <= 2 ~ "high_proxy",
        !is.na(exposure_proxy_value) & primary_sensor_weighted_share >= rs_m11_sensor_primary_share_medium ~ "medium_proxy",
        !is.na(exposure_proxy_value) ~ "low_proxy",
        TRUE ~ "no_proxy"
      )
    )

  note_flags <- character(nrow(exposure_baseline))
  note_flags[] <- ""

  append_flag <- function(existing, mask, flag_name) {
    mask <- !is.na(mask) & mask
    existing[mask] <- ifelse(existing[mask] == "", flag_name, paste(existing[mask], flag_name, sep = " | "))
    existing
  }

  note_flags <- append_flag(note_flags, !traffic_layer_usable, "traffic_tramo_layer_outside_operational_area")
  note_flags <- append_flag(note_flags, exposure_baseline$linked_sensor_n > 0, "sensor_only_proxy")
  note_flags <- append_flag(note_flags, exposure_baseline$linked_sensor_n > 1, "multi_sensor_edge")
  note_flags <- append_flag(note_flags, exposure_baseline$linked_sensor_n > 0 & is.na(exposure_baseline$exposure_proxy_value), "no_numeric_sensor_proxy")
  note_flags <- append_flag(note_flags, exposure_baseline$linked_sensor_n == 0, "no_accident_backed_sensor_link")
  note_flags <- append_flag(note_flags, exposure_baseline$linked_tramo_n == 0, "no_geometric_tramo_link")

  exposure_baseline |>
    dplyr::mutate(
      exposure_proxy_value = round(exposure_proxy_value, 4),
      sensor_intensidad_rank_proxy = round(sensor_intensidad_rank_proxy, 4),
      sensor_ocupacion_rank_proxy = round(sensor_ocupacion_rank_proxy, 4),
      primary_sensor_weighted_share = round(primary_sensor_weighted_share, 4),
      linked_tramo_overlap_total_m = round(linked_tramo_overlap_total_m, 3),
      notes_or_limitations = dplyr::na_if(note_flags, "")
    )
}

rs_m11_build_historical_exposure_adjusted <- function(m10_aggregation, exposure_baseline) {
  historical_adjusted <- m10_aggregation |>
    dplyr::select(
      edge_id,
      edge_length_m,
      historical_count_raw = accident_count_raw,
      historical_count_weighted = accident_count_weighted_by_quality,
      accidents_per_km_raw,
      accidents_per_km,
      historical_score_prelim,
      notes_or_flags
    ) |>
    dplyr::left_join(
      exposure_baseline |>
        dplyr::select(
          edge_id,
          linked_sensor_n,
          linked_tramo_n,
          exposure_proxy_type,
          exposure_proxy_value,
          exposure_quality_flag,
          notes_or_limitations
        ),
      by = "edge_id"
    ) |>
    dplyr::mutate(
      exposure_adjustment_denominator = dplyr::if_else(!is.na(exposure_proxy_value), rs_m11_exposure_floor + exposure_proxy_value, NA_real_),
      historical_exposure_adjusted_density = dplyr::case_when(
        historical_count_weighted == 0 ~ 0,
        !is.na(exposure_adjustment_denominator) ~ accidents_per_km / exposure_adjustment_denominator,
        TRUE ~ NA_real_
      )
    )

  positive_adjusted <- historical_adjusted$historical_exposure_adjusted_density[historical_adjusted$historical_exposure_adjusted_density > 0]
  density_cap <- if (length(positive_adjusted)) {
    as.numeric(stats::quantile(positive_adjusted, rs_m11_adjusted_score_cap_quantile, na.rm = TRUE))
  } else {
    1
  }

  note_flags <- character(nrow(historical_adjusted))
  note_flags[] <- ""

  append_flag <- function(existing, mask, flag_name) {
    mask <- !is.na(mask) & mask
    existing[mask] <- ifelse(existing[mask] == "", flag_name, paste(existing[mask], flag_name, sep = " | "))
    existing
  }

  note_flags <- append_flag(note_flags, historical_adjusted$historical_count_weighted > 0 & is.na(historical_adjusted$exposure_proxy_value), "positive_history_without_exposure_proxy")
  note_flags <- append_flag(note_flags, historical_adjusted$historical_exposure_adjusted_density > density_cap & historical_adjusted$historical_count_weighted > 0, "adjusted_score_capped_at_p95_density")
  note_flags <- append_flag(note_flags, historical_adjusted$historical_count_weighted == 0, "no_historical_accidents")
  note_flags <- append_flag(note_flags, TRUE, "not_final_routing_weight")

  historical_adjusted <- historical_adjusted |>
    dplyr::mutate(
      historical_exposure_adjusted_score_prelim = dplyr::case_when(
        historical_count_weighted == 0 ~ 0,
        is.na(historical_exposure_adjusted_density) ~ NA_real_,
        density_cap > 0 ~ 100 * pmin(historical_exposure_adjusted_density, density_cap) / density_cap,
        TRUE ~ NA_real_
      ),
      historical_exposure_adjusted_density = round(historical_exposure_adjusted_density, 4),
      historical_exposure_adjusted_score_prelim = round(historical_exposure_adjusted_score_prelim, 3),
      notes_or_limitations = dplyr::case_when(
        is.na(notes_or_limitations) & notes_or_flags == "" ~ dplyr::na_if(note_flags, ""),
        TRUE ~ paste(dplyr::coalesce(notes_or_limitations, ""), note_flags, sep = " | ")
      )
    ) |>
    dplyr::mutate(
      notes_or_limitations = gsub("^ \\| |^\\| | \\| $", "", notes_or_limitations),
      notes_or_limitations = gsub("\\| \\|", "|", notes_or_limitations)
    )

  list(
    historical_adjusted = historical_adjusted,
    adjusted_density_cap = density_cap
  )
}

rs_m11_build_crosswalk_quality_summary <- function(traffic_crosswalk, sensor_crosswalk, exposure_baseline, historical_adjusted, tramos_info, m10_aggregation) {
  linked_traffic_pairs_n <- sum(traffic_crosswalk$crosswalk_status == "linked", na.rm = TRUE)
  linked_traffic_edges_n <- dplyr::n_distinct(traffic_crosswalk$edge_id[!is.na(traffic_crosswalk$edge_id)])
  linked_traffic_tramos_n <- dplyr::n_distinct(traffic_crosswalk$tramo_id[traffic_crosswalk$crosswalk_status == "linked"])

  edges_with_accidents_n <- sum(m10_aggregation$accident_count_raw > 0, na.rm = TRUE)
  edges_with_exposure_proxy_n <- sum(!is.na(exposure_baseline$exposure_proxy_value), na.rm = TRUE)
  edges_with_reliable_exposure_proxy_n <- sum(exposure_baseline$exposure_quality_flag %in% c("high_proxy", "medium_proxy"), na.rm = TRUE)
  historical_adjusted_nonmissing_n <- sum(!is.na(historical_adjusted$historical_exposure_adjusted_score_prelim), na.rm = TRUE)

  tibble::tibble(
    metric = c(
      "traffic_tramo_rows_total",
      "traffic_tramo_geometry_valid_n",
      "traffic_tramo_bbox_overlap_with_network",
      "traffic_tramo_linked_pairs_n",
      "traffic_tramo_linked_unique_tramos_n",
      "traffic_tramo_linked_unique_edges_n",
      "traffic_tramo_unlinked_rows_n",
      "sensor_crosswalk_pairs_n",
      "sensor_crosswalk_unique_edges_n",
      "sensor_crosswalk_unique_sensors_n",
      "edges_with_exposure_proxy_n",
      "edges_with_exposure_proxy_pct_over_network",
      "edges_with_exposure_proxy_pct_over_edges_with_accidents",
      "edges_with_reliable_exposure_proxy_n",
      "edges_with_no_proxy_n",
      "historical_exposure_adjusted_nonmissing_n"
    ),
    value = c(
      as.character(tramos_info$tramo_rows_total),
      as.character(tramos_info$tramo_geometry_valid_n),
      as.character(any(traffic_crosswalk$bbox_overlap_with_network)),
      as.character(linked_traffic_pairs_n),
      as.character(linked_traffic_tramos_n),
      as.character(linked_traffic_edges_n),
      as.character(sum(traffic_crosswalk$crosswalk_status != "linked", na.rm = TRUE)),
      as.character(nrow(sensor_crosswalk)),
      as.character(dplyr::n_distinct(sensor_crosswalk$edge_id)),
      as.character(dplyr::n_distinct(sensor_crosswalk$sensor_id)),
      as.character(edges_with_exposure_proxy_n),
      sprintf("%.2f", 100 * edges_with_exposure_proxy_n / nrow(exposure_baseline)),
      sprintf("%.2f", 100 * edges_with_exposure_proxy_n / edges_with_accidents_n),
      as.character(edges_with_reliable_exposure_proxy_n),
      as.character(sum(exposure_baseline$exposure_quality_flag == "no_proxy", na.rm = TRUE)),
      as.character(historical_adjusted_nonmissing_n)
    )
  )
}

rs_m11_build_validation_summary <- function(traffic_crosswalk, sensor_crosswalk, exposure_baseline, historical_adjusted, edges_sf, crosswalk_quality_summary) {
  get_quality_metric <- function(metric_name) {
    value <- crosswalk_quality_summary |>
      dplyr::filter(metric == metric_name) |>
      dplyr::pull(value)
    if (!length(value)) {
      return(NA_character_)
    }
    value[[1]]
  }

  tibble::tibble(
    metric = c(
      "edge_ids_in_traffic_crosswalk_exist_in_network",
      "edge_ids_in_sensor_crosswalk_exist_in_network",
      "edge_ids_in_exposure_baseline_exist_in_network",
      "edge_ids_in_historical_adjusted_exist_in_network",
      "traffic_crosswalk_direct_join_used",
      "sensor_crosswalk_direct_join_used",
      "traffic_crosswalk_coverage_quantified",
      "sensor_crosswalk_coverage_quantified",
      "traffic_tramo_spatially_usable_for_current_network",
      "exposure_proxy_documented_and_traceable",
      "edges_with_reliable_exposure_proxy_n",
      "edges_with_low_proxy_n",
      "edges_with_no_proxy_n",
      "historical_exposure_adjusted_score_prelim_is_final_routing_weight",
      "output_schema_version"
    ),
    value = c(
      as.character(all(traffic_crosswalk$edge_id[!is.na(traffic_crosswalk$edge_id)] %in% edges_sf$edge_id)),
      as.character(all(sensor_crosswalk$edge_id %in% edges_sf$edge_id)),
      as.character(all(exposure_baseline$edge_id %in% edges_sf$edge_id)),
      as.character(all(historical_adjusted$edge_id %in% edges_sf$edge_id)),
      "FALSE",
      "FALSE",
      "TRUE",
      "TRUE",
      get_quality_metric("traffic_tramo_linked_pairs_n") != "0",
      "TRUE",
      get_quality_metric("edges_with_reliable_exposure_proxy_n"),
      as.character(sum(exposure_baseline$exposure_quality_flag == "low_proxy", na.rm = TRUE)),
      as.character(sum(exposure_baseline$exposure_quality_flag == "no_proxy", na.rm = TRUE)),
      "FALSE",
      rs_m11_output_schema_version
    )
  )
}

rs_m11_build_exposure_note <- function(crosswalk_quality_summary, validation_summary, adjusted_density_cap) {
  get_metric <- function(tbl, metric_name) {
    value <- tbl |>
      dplyr::filter(metric == metric_name) |>
      dplyr::pull(value)
    if (!length(value)) {
      return(NA_character_)
    }
    value[[1]]
  }

  paste(
    "# M11 - Crosswalk trafico/exposicion -> edge",
    "",
    "## Logica de M11",
    "- M11 separa tres piezas metodologicas:",
    "  - `crosswalk geometrico`: intento de enlazar la capa lineal de trafico `Id. Tram` con la red canonica mediante geometria real.",
    "  - `exposure baseline`: proxy por edge construida a partir del puente `edge <-> sensor` respaldado por accidentes ya matcheados en M9.",
    "  - `historical_exposure_adjusted_score_prelim`: ajuste preliminar de la densidad historica ponderada de M10 contra una proxy de exposicion, todavia fuera del routing final.",
    "",
    "## Fuente base de exposicion",
    "- La proxy baseline se construye con sensores asociados a accidentes matcheados (`id_sensor_cercano`) y sus variables `intensidad` / `ocupacion`.",
    "- No se usa `id_sensor_cercano` como join directo a `edge_id`; el enlace se construye solo a traves de evidencia `accidente matcheado -> edge` ya validada en M9.",
    "- `exposure_proxy_value` es un indice `0-1` trazable, derivado de rankings robustos de `intensidad` y `ocupacion` a nivel sensor.",
    "",
    "## Estado del crosswalk geometrico de trafico",
    sprintf("- Tramos de trafico totales: %s", get_metric(crosswalk_quality_summary, "traffic_tramo_rows_total")),
    sprintf("- Geometrias de tramo validas: %s", get_metric(crosswalk_quality_summary, "traffic_tramo_geometry_valid_n")),
    sprintf("- BBox de tramos con solape usable frente a la red actual: %s", get_metric(crosswalk_quality_summary, "traffic_tramo_bbox_overlap_with_network")),
    sprintf("- Pairs tramo-edge linked: %s", get_metric(crosswalk_quality_summary, "traffic_tramo_linked_pairs_n")),
    "- Si la cobertura geometrica de tramos es nula o residual, M11 no la fuerza y deja constancia del bloqueo en las tablas de salida.",
    "",
    "## Exposure baseline y score ajustado",
    "- `historical_count_raw` y `historical_count_weighted` se mantienen separados del ajuste por exposicion.",
    sprintf("- `historical_exposure_adjusted_score_prelim` se obtiene reescalando la densidad historica ajustada y capando en el p95 no nulo (`%.3f`).", adjusted_density_cap),
    "- El ajuste usa `accidents_per_km / (0.25 + exposure_proxy_value)` para evitar explosiones en edges con proxy baja.",
    "",
    "## Limitaciones abiertas",
    "- La exposicion sigue siendo una proxy y no una medicion real independiente de flujo.",
    "- Todavia no hay modelo dinamico/contextual sobre la red.",
    "- Todavia no hay severidad ni suavizado espacial.",
    "- Todavia no existe coste final de routing.",
    "- `historical_exposure_adjusted_score_prelim` no es peso final de arista.",
    "",
    "## Cobertura resultante",
    sprintf("- Edges con exposure proxy disponible: %s", get_metric(crosswalk_quality_summary, "edges_with_exposure_proxy_n")),
    sprintf("- Edges con exposure proxy fiable (high/medium): %s", get_metric(validation_summary, "edges_with_reliable_exposure_proxy_n")),
    sprintf("- Edges sin proxy: %s", get_metric(validation_summary, "edges_with_no_proxy_n")),
    "",
    sprintf("- Schema de salida: `%s`.", rs_m11_output_schema_version),
    "",
    sep = "\n"
  )
}

rs_m11_write_outputs <- function(traffic_crosswalk, sensor_crosswalk, exposure_baseline, historical_adjusted, crosswalk_quality_summary, exposure_note, validation_summary, output_paths) {
  readr::write_csv(traffic_crosswalk, output_paths$traffic_crosswalk_csv)
  readr::write_csv(sensor_crosswalk, output_paths$sensor_crosswalk_csv)
  readr::write_csv(exposure_baseline, output_paths$exposure_baseline_csv)
  readr::write_csv(historical_adjusted, output_paths$historical_adjusted_csv)
  readr::write_csv(crosswalk_quality_summary, output_paths$crosswalk_quality_summary_csv)
  readr::write_csv(validation_summary, output_paths$validation_summary_csv)
  writeLines(exposure_note, output_paths$exposure_note_md, useBytes = TRUE)
}

rs_run_m11_edge_exposure_crosswalk <- function(m8_result, paths, m9_result = NULL, m10_result = NULL, accident_master = NULL, force_refresh = FALSE) {
  rs_check_m11_packages()
  rs_validate_m11_inputs(m8_result, paths)

  output_paths <- rs_m11_output_paths(paths)
  if (!force_refresh && rs_m11_cache_is_current(output_paths)) {
    return(rs_m11_read_cached_outputs(output_paths))
  }

  edges_sf <- rs_m11_load_edges(m8_result)
  matches_df <- rs_m11_load_m9_matches(m9_result, paths)
  m10_aggregation <- rs_m11_load_m10_aggregation(m10_result, paths)
  accident_master <- rs_m11_load_accident_master(accident_master, paths)
  quality_weights <- rs_m11_load_m10_quality_weights(paths)
  tramos_info <- rs_m11_load_trafico_tramos(paths$project_dir)

  traffic_crosswalk_result <- rs_m11_build_traffic_crosswalk(tramos_info, edges_sf)
  sensor_crosswalk_result <- rs_m11_prepare_sensor_crosswalk(matches_df, accident_master, quality_weights)
  exposure_baseline <- rs_m11_build_exposure_baseline(
    m10_aggregation = m10_aggregation,
    sensor_crosswalk = sensor_crosswalk_result$sensor_crosswalk,
    traffic_crosswalk = traffic_crosswalk_result$crosswalk
  )
  historical_adjusted_result <- rs_m11_build_historical_exposure_adjusted(m10_aggregation, exposure_baseline)
  crosswalk_quality_summary <- rs_m11_build_crosswalk_quality_summary(
    traffic_crosswalk = traffic_crosswalk_result$crosswalk,
    sensor_crosswalk = sensor_crosswalk_result$sensor_crosswalk,
    exposure_baseline = exposure_baseline,
    historical_adjusted = historical_adjusted_result$historical_adjusted,
    tramos_info = tramos_info,
    m10_aggregation = m10_aggregation
  )
  validation_summary <- rs_m11_build_validation_summary(
    traffic_crosswalk = traffic_crosswalk_result$crosswalk,
    sensor_crosswalk = sensor_crosswalk_result$sensor_crosswalk,
    exposure_baseline = exposure_baseline,
    historical_adjusted = historical_adjusted_result$historical_adjusted,
    edges_sf = edges_sf,
    crosswalk_quality_summary = crosswalk_quality_summary
  )
  exposure_note <- rs_m11_build_exposure_note(
    crosswalk_quality_summary = crosswalk_quality_summary,
    validation_summary = validation_summary,
    adjusted_density_cap = historical_adjusted_result$adjusted_density_cap
  )

  rs_m11_write_outputs(
    traffic_crosswalk = traffic_crosswalk_result$crosswalk,
    sensor_crosswalk = sensor_crosswalk_result$sensor_crosswalk,
    exposure_baseline = exposure_baseline,
    historical_adjusted = historical_adjusted_result$historical_adjusted,
    crosswalk_quality_summary = crosswalk_quality_summary,
    exposure_note = exposure_note,
    validation_summary = validation_summary,
    output_paths = output_paths
  )

  list(
    traffic_crosswalk = traffic_crosswalk_result$crosswalk,
    sensor_crosswalk = sensor_crosswalk_result$sensor_crosswalk,
    exposure_baseline = exposure_baseline,
    historical_exposure_adjusted = historical_adjusted_result$historical_adjusted,
    crosswalk_quality_summary = crosswalk_quality_summary,
    validation_summary = validation_summary,
    exposure_note = exposure_note,
    used_cache = FALSE
  )
}
