rs_m8_required_master_columns <- c(
  "num_expediente",
  "coordenada_x_utm",
  "coordenada_y_utm",
  "fecha",
  "hora",
  "tipo_accidente"
)

rs_m8_canonical_crs_epsg <- 25830L
rs_m8_source_crs_epsg <- 4326L
rs_m8_matching_output_schema_version <- "m9_schema_v1_edge_id_projected_point_geometry_binary_match_status"
rs_m8_geofabrik_url <- "https://download.geofabrik.de/europe/spain/madrid-latest-free.shp.zip"
rs_m8_geofabrik_zip_name <- "madrid-latest-free.shp.zip"
rs_m8_geofabrik_extract_dir <- "madrid-latest-free-shp"
rs_m8_geofabrik_roads_layer <- "gis_osm_roads_free_1"
rs_m8_drivable_fclass <- c(
  "motorway", "motorway_link",
  "trunk", "trunk_link",
  "primary", "primary_link",
  "secondary", "secondary_link",
  "tertiary", "tertiary_link",
  "residential", "living_street", "service", "unclassified"
)

rs_check_m8_packages <- function() {
  required_packages <- c("dplyr", "tibble", "readr", "sf", "digest")
  missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]

  if (length(missing_packages) > 0L) {
    stop(
      sprintf(
        "Faltan paquetes requeridos para M8: %s",
        paste(missing_packages, collapse = ", ")
      ),
      call. = FALSE
    )
  }
}

rs_validate_m8_inputs <- function(accident_master, paths) {
  if (missing(accident_master) || is.null(accident_master) || !nrow(accident_master)) {
    stop("M8 necesita una tabla accidente no vacia.", call. = FALSE)
  }

  missing_columns <- setdiff(rs_m8_required_master_columns, names(accident_master))
  if (length(missing_columns) > 0L) {
    stop(
      sprintf(
        "Faltan columnas requeridas en accident_master para M8: %s",
        paste(missing_columns, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  required_paths <- c("project_dir", "output_data", "output_tables")
  missing_paths <- setdiff(required_paths, names(paths))
  if (length(missing_paths) > 0L) {
    stop(
      sprintf(
        "M8 necesita paths con campos: %s",
        paste(required_paths, collapse = ", ")
      ),
      call. = FALSE
    )
  }
}

rs_m8_source_paths <- function(paths) {
  network_root <- file.path(paths$project_dir, "bases de datos", "network")
  extract_root <- file.path(network_root, rs_m8_geofabrik_extract_dir)
  roads_path <- file.path(extract_root, paste0(rs_m8_geofabrik_roads_layer, ".shp"))

  list(
    network_root = network_root,
    zip_path = file.path(network_root, rs_m8_geofabrik_zip_name),
    extract_root = extract_root,
    roads_path = roads_path
  )
}

rs_m8_output_paths <- function(paths) {
  list(
    nodes_geojson = file.path(paths$output_data, "m8_road_network_nodes.geojson"),
    edges_geojson = file.path(paths$output_data, "m8_road_network_edges.geojson"),
    nodes_csv = file.path(paths$output_data, "m8_road_network_nodes.csv"),
    edges_csv = file.path(paths$output_data, "m8_road_network_edges.csv"),
    metadata_csv = file.path(paths$output_tables, "m8_network_metadata.csv"),
    matching_contract_csv = file.path(paths$output_tables, "m8_accident_edge_matching_contract.csv"),
    validation_csv = file.path(paths$output_tables, "m8_network_validation_summary.csv"),
    file_structure_csv = file.path(paths$output_tables, "m8_file_structure_updates.csv"),
    note_md = file.path(paths$output_tables, "m8_canonical_network_note.md")
  )
}

rs_m8_artifacts_ready <- function(output_paths) {
  all(file.exists(unlist(output_paths, use.names = FALSE)))
}

rs_m8_expected_bbox_strategy <- function(buffer_m = 1000, lower_prob = 0.05, upper_prob = 0.999) {
  sprintf("quantile_%.3f_%.3f_plus_%sm_buffer", lower_prob, upper_prob, buffer_m)
}

rs_m8_network_config_is_current <- function(metadata) {
  bbox_strategy <- metadata |>
    dplyr::filter(metric == "bbox_strategy") |>
    dplyr::pull(value)
  source_url <- metadata |>
    dplyr::filter(metric == "source_distribution_url") |>
    dplyr::pull(value)

  length(bbox_strategy) &&
    length(source_url) &&
    identical(bbox_strategy[[1]], rs_m8_expected_bbox_strategy()) &&
    identical(source_url[[1]], rs_m8_geofabrik_url)
}

rs_m8_read_cached_outputs <- function(output_paths) {
  list(
    nodes_path = output_paths$nodes_geojson,
    edges_path = output_paths$edges_geojson,
    metadata = readr::read_csv(output_paths$metadata_csv, show_col_types = FALSE),
    matching_contract = readr::read_csv(output_paths$matching_contract_csv, show_col_types = FALSE),
    validation_summary = readr::read_csv(output_paths$validation_csv, show_col_types = FALSE),
    file_structure_updates = readr::read_csv(output_paths$file_structure_csv, show_col_types = FALSE),
    technical_note = paste(readLines(output_paths$note_md, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  )
}

rs_m8_refresh_auxiliary_outputs_from_cached_network <- function(output_paths, source_paths) {
  nodes_sf <- sf::st_read(output_paths$nodes_geojson, quiet = TRUE)
  edges_sf <- sf::st_read(output_paths$edges_geojson, quiet = TRUE)
  metadata <- readr::read_csv(output_paths$metadata_csv, show_col_types = FALSE) |>
    dplyr::filter(metric != "matching_output_schema_version")

  metadata <- dplyr::bind_rows(
    metadata,
    tibble::tibble(
      metric = "matching_output_schema_version",
      value = rs_m8_matching_output_schema_version
    )
  )

  matching_contract <- rs_m8_build_matching_contract()
  validation_summary <- rs_m8_build_validation_summary(nodes_sf, edges_sf)
  file_structure_updates <- rs_m8_build_file_structure_updates(source_paths)
  technical_note <- rs_m8_build_technical_note(metadata, validation_summary)

  readr::write_csv(metadata, output_paths$metadata_csv)
  readr::write_csv(matching_contract, output_paths$matching_contract_csv)
  readr::write_csv(validation_summary, output_paths$validation_csv)
  readr::write_csv(file_structure_updates, output_paths$file_structure_csv)
  writeLines(technical_note, output_paths$note_md, useBytes = TRUE)

  list(
    nodes_path = output_paths$nodes_geojson,
    edges_path = output_paths$edges_geojson,
    metadata = metadata,
    matching_contract = matching_contract,
    validation_summary = validation_summary,
    file_structure_updates = file_structure_updates,
    technical_note = technical_note
  )
}

rs_m8_cache_is_current <- function(output_paths) {
  if (!rs_m8_artifacts_ready(output_paths)) {
    return(FALSE)
  }

  metadata <- tryCatch(
    readr::read_csv(output_paths$metadata_csv, show_col_types = FALSE),
    error = function(...) NULL
  )

  if (is.null(metadata)) {
    return(FALSE)
  }

  if (!rs_m8_network_config_is_current(metadata)) {
    return(FALSE)
  }

  schema_version <- metadata |>
    dplyr::filter(metric == "matching_output_schema_version") |>
    dplyr::pull(value)

  if (!length(schema_version)) {
    return(FALSE)
  }

  identical(schema_version[[1]], rs_m8_matching_output_schema_version)
}

rs_m8_can_refresh_auxiliary_outputs <- function(output_paths) {
  if (!rs_m8_artifacts_ready(output_paths)) {
    return(FALSE)
  }

  metadata <- tryCatch(
    readr::read_csv(output_paths$metadata_csv, show_col_types = FALSE),
    error = function(...) NULL
  )

  if (is.null(metadata)) {
    return(FALSE)
  }

  rs_m8_network_config_is_current(metadata)
}

rs_m8_ensure_geofabrik_source <- function(source_paths) {
  if (!dir.exists(source_paths$network_root)) {
    dir.create(source_paths$network_root, recursive = TRUE, showWarnings = FALSE)
  }

  if (!file.exists(source_paths$zip_path)) {
    utils::download.file(
      url = rs_m8_geofabrik_url,
      destfile = source_paths$zip_path,
      mode = "wb",
      quiet = FALSE
    )
  }

  if (!file.exists(source_paths$roads_path)) {
    if (!dir.exists(source_paths$extract_root)) {
      dir.create(source_paths$extract_root, recursive = TRUE, showWarnings = FALSE)
    }

    utils::unzip(
      zipfile = source_paths$zip_path,
      exdir = source_paths$extract_root
    )
  }

  if (!file.exists(source_paths$roads_path)) {
    stop(
      sprintf(
        "No se encontro la capa de carreteras esperada tras extraer Geofabrik: %s",
        source_paths$roads_path
      ),
      call. = FALSE
    )
  }
}

rs_m8_build_accident_bbox <- function(accident_master, buffer_m = 1000, lower_prob = 0.05, upper_prob = 0.999) {
  x <- accident_master$coordenada_x_utm
  y <- accident_master$coordenada_y_utm
  valid_mask <- !is.na(x) & !is.na(y) & x != 0 & y != 0

  if (!any(valid_mask)) {
    stop("M8 no puede construir bbox: no hay accidentes con coordenadas validas.", call. = FALSE)
  }

  x_valid <- x[valid_mask]
  y_valid <- y[valid_mask]

  x_lower <- as.numeric(stats::quantile(x_valid, lower_prob))
  x_upper <- as.numeric(stats::quantile(x_valid, upper_prob))
  y_lower <- as.numeric(stats::quantile(y_valid, lower_prob))
  y_upper <- as.numeric(stats::quantile(y_valid, upper_prob))

  inlier_mask <- valid_mask &
    x >= x_lower & x <= x_upper &
    y >= y_lower & y <= y_upper

  inlier_df <- tibble::tibble(
    x = x[inlier_mask],
    y = y[inlier_mask]
  )

  points_sf <- sf::st_as_sf(
    inlier_df,
    coords = c("x", "y"),
    crs = rs_m8_canonical_crs_epsg,
    remove = FALSE
  )

  bbox_utm <- sf::st_as_sfc(sf::st_bbox(points_sf)) |>
    sf::st_buffer(buffer_m)
  bbox_ll <- sf::st_transform(bbox_utm, rs_m8_source_crs_epsg)

  list(
    valid_coordinate_n = sum(valid_mask),
    inlier_coordinate_n = sum(inlier_mask),
    points_sf = points_sf,
    bbox_utm = bbox_utm,
    bbox_ll = bbox_ll,
    bbox_utm_numeric = sf::st_bbox(bbox_utm),
    bbox_ll_numeric = sf::st_bbox(bbox_ll),
    bbox_strategy = sprintf("quantile_%.3f_%.3f_plus_%sm_buffer", lower_prob, upper_prob, buffer_m)
  )
}

rs_m8_read_geofabrik_roads <- function(source_paths, accident_bbox) {
  roads <- sf::st_read(source_paths$roads_path, quiet = TRUE)

  source_feature_n <- nrow(roads)

  roads <- roads |>
    dplyr::select(osm_id, code, fclass, name, ref, oneway, maxspeed, layer, bridge, tunnel, geometry) |>
    dplyr::filter(fclass %in% rs_m8_drivable_fclass)

  filtered_feature_n <- nrow(roads)

  roads <- sf::st_transform(roads, rs_m8_canonical_crs_epsg)
  roads <- sf::st_make_valid(roads)
  roads <- sf::st_crop(roads, sf::st_bbox(accident_bbox$bbox_utm))
  roads <- sf::st_collection_extract(roads, "LINESTRING", warn = FALSE)
  roads <- sf::st_cast(roads, "LINESTRING", warn = FALSE)
  roads <- roads[!sf::st_is_empty(roads), ]

  geom_signature <- vapply(
    sf::st_as_text(sf::st_geometry(roads)),
    function(wkt) digest::digest(wkt, algo = "xxhash64"),
    character(1)
  )

  roads <- roads |>
    dplyr::mutate(
      source_feature_id = paste0(
        "m8f_",
        vapply(
          seq_len(nrow(roads)),
          function(i) digest::digest(
            paste(roads$osm_id[i], geom_signature[i], sep = "|"),
            algo = "xxhash64"
          ),
          character(1)
        )
      )
    ) |>
    dplyr::distinct(source_feature_id, .keep_all = TRUE)

  list(
    roads = roads,
    source_feature_n = source_feature_n,
    filtered_feature_n = filtered_feature_n,
    clipped_feature_n = nrow(roads)
  )
}

rs_m8_segment_line_features <- function(roads_sf) {
  edge_records <- vector("list", length = nrow(roads_sf))
  edge_geometries <- vector("list", length = nrow(roads_sf))
  edge_idx <- 1L

  for (i in seq_len(nrow(roads_sf))) {
    coords <- sf::st_coordinates(roads_sf$geometry[i])[, c("X", "Y"), drop = FALSE]
    if (nrow(coords) < 2L) {
      next
    }

    dedup_mask <- c(TRUE, rowSums(abs(diff(coords))) > 0)
    coords <- coords[dedup_mask, , drop = FALSE]
    if (nrow(coords) < 2L) {
      next
    }

    for (segment_i in seq_len(nrow(coords) - 1L)) {
      from_x <- coords[segment_i, 1]
      from_y <- coords[segment_i, 2]
      to_x <- coords[segment_i + 1L, 1]
      to_y <- coords[segment_i + 1L, 2]
      from_key <- sprintf("%.3f|%.3f", from_x, from_y)
      to_key <- sprintf("%.3f|%.3f", to_x, to_y)

      edge_records[[edge_idx]] <- tibble::tibble(
        source_feature_id = roads_sf$source_feature_id[i],
        source_osm_id = as.character(roads_sf$osm_id[i]),
        source_segment_index = segment_i,
        road_code = as.character(roads_sf$code[i]),
        road_class = as.character(roads_sf$fclass[i]),
        street_name = as.character(roads_sf$name[i]),
        road_ref = as.character(roads_sf$ref[i]),
        oneway_raw = as.character(roads_sf$oneway[i]),
        maxspeed_raw = as.character(roads_sf$maxspeed[i]),
        layer_raw = as.character(roads_sf$layer[i]),
        bridge_raw = as.character(roads_sf$bridge[i]),
        tunnel_raw = as.character(roads_sf$tunnel[i]),
        from_node_key = from_key,
        to_node_key = to_key,
        from_x = from_x,
        from_y = from_y,
        to_x = to_x,
        to_y = to_y
      )

      edge_geometries[[edge_idx]] <- sf::st_linestring(
        matrix(c(from_x, from_y, to_x, to_y), ncol = 2L, byrow = TRUE)
      )

      edge_idx <- edge_idx + 1L
    }
  }

  edge_records <- edge_records[seq_len(edge_idx - 1L)]
  edge_geometries <- edge_geometries[seq_len(edge_idx - 1L)]

  if (!length(edge_records)) {
    stop("M8 no pudo segmentar la red en edges utilizables.", call. = FALSE)
  }

  edges <- dplyr::bind_rows(edge_records)
  edges_sf <- sf::st_sf(edges, geometry = sf::st_sfc(edge_geometries, crs = rs_m8_canonical_crs_epsg))

  edge_id <- vapply(
    seq_len(nrow(edges_sf)),
    function(i) {
      paste0(
        "m8e_",
        digest::digest(
          paste(
            edges_sf$source_osm_id[i],
            edges_sf$source_feature_id[i],
            edges_sf$source_segment_index[i],
            edges_sf$from_node_key[i],
            edges_sf$to_node_key[i],
            sep = "|"
          ),
          algo = "xxhash64"
        )
      )
    },
    character(1)
  )

  edges_sf |>
    dplyr::mutate(edge_id = edge_id, .before = 1)
}

rs_m8_build_nodes_from_edges <- function(edges_sf) {
  nodes_raw <- dplyr::bind_rows(
    edges_sf |>
      sf::st_drop_geometry() |>
      dplyr::transmute(node_key = from_node_key, x_utm = from_x, y_utm = from_y),
    edges_sf |>
      sf::st_drop_geometry() |>
      dplyr::transmute(node_key = to_node_key, x_utm = to_x, y_utm = to_y)
  ) |>
    dplyr::distinct(node_key, .keep_all = TRUE) |>
    dplyr::mutate(
      node_id = paste0("m8n_", vapply(node_key, digest::digest, character(1), algo = "xxhash64"))
    )

  nodes_sf <- sf::st_as_sf(nodes_raw, coords = c("x_utm", "y_utm"), crs = rs_m8_canonical_crs_epsg, remove = FALSE)

  nodes_ll <- sf::st_transform(nodes_sf, rs_m8_source_crs_epsg)
  ll_coords <- sf::st_coordinates(nodes_ll)
  degree_table <- table(c(edges_sf$from_node_key, edges_sf$to_node_key))

  nodes_sf |>
    dplyr::mutate(
      lon = ll_coords[, 1],
      lat = ll_coords[, 2],
      degree_total = as.integer(degree_table[node_key]),
      .before = 1
    )
}

rs_m8_attach_node_ids_and_lengths <- function(edges_sf, nodes_sf) {
  node_lookup <- nodes_sf |>
    sf::st_drop_geometry() |>
    dplyr::select(node_key, node_id)

  edges_sf |>
    dplyr::left_join(
      node_lookup |>
        dplyr::rename(from_node_key = node_key, from_node_id = node_id),
      by = "from_node_key"
    ) |>
    dplyr::left_join(
      node_lookup |>
        dplyr::rename(to_node_key = node_key, to_node_id = node_id),
      by = "to_node_key"
    ) |>
    dplyr::mutate(
      edge_length_m = as.numeric(sf::st_length(geometry))
    ) |>
    dplyr::select(
      edge_id,
      from_node_id,
      to_node_id,
      source_osm_id,
      source_feature_id,
      source_segment_index,
      road_code,
      road_class,
      street_name,
      road_ref,
      oneway_raw,
      maxspeed_raw,
      layer_raw,
      bridge_raw,
      tunnel_raw,
      edge_length_m,
      from_x,
      from_y,
      to_x,
      to_y,
      geometry
    )
}

rs_m8_build_network_metadata <- function(accident_bbox, source_paths, roads_profile, nodes_sf, edges_sf) {
  node_bbox <- sf::st_bbox(nodes_sf)
  edge_bbox <- sf::st_bbox(edges_sf)

  tibble::tibble(
    metric = c(
      "network_source",
      "source_distribution_url",
      "source_zip_path",
      "source_layer",
      "source_extract_crs_epsg",
      "canonical_network_crs_epsg",
      "assumed_accident_crs_epsg",
      "matching_output_schema_version",
      "bbox_strategy",
      "accident_valid_coordinates_n",
      "accident_inlier_coordinates_n",
      "query_bbox_ll_xmin",
      "query_bbox_ll_ymin",
      "query_bbox_ll_xmax",
      "query_bbox_ll_ymax",
      "query_bbox_utm_xmin",
      "query_bbox_utm_ymin",
      "query_bbox_utm_xmax",
      "query_bbox_utm_ymax",
      "roads_source_features_n",
      "roads_filtered_features_n",
      "roads_clipped_features_n",
      "network_nodes_n",
      "network_edges_n",
      "total_edge_length_m",
      "node_bbox_utm_xmin",
      "node_bbox_utm_ymin",
      "node_bbox_utm_xmax",
      "node_bbox_utm_ymax",
      "edge_bbox_utm_xmin",
      "edge_bbox_utm_ymin",
      "edge_bbox_utm_xmax",
      "edge_bbox_utm_ymax",
      "traffic_tramo_used_as_canonical_edge"
    ),
    value = c(
      "Geofabrik OpenStreetMap roads extract for Madrid",
      rs_m8_geofabrik_url,
      source_paths$zip_path,
      rs_m8_geofabrik_roads_layer,
      as.character(rs_m8_source_crs_epsg),
      as.character(rs_m8_canonical_crs_epsg),
      as.character(rs_m8_canonical_crs_epsg),
      rs_m8_matching_output_schema_version,
      accident_bbox$bbox_strategy,
      as.character(accident_bbox$valid_coordinate_n),
      as.character(accident_bbox$inlier_coordinate_n),
      sprintf("%.6f", accident_bbox$bbox_ll_numeric["xmin"]),
      sprintf("%.6f", accident_bbox$bbox_ll_numeric["ymin"]),
      sprintf("%.6f", accident_bbox$bbox_ll_numeric["xmax"]),
      sprintf("%.6f", accident_bbox$bbox_ll_numeric["ymax"]),
      sprintf("%.3f", accident_bbox$bbox_utm_numeric["xmin"]),
      sprintf("%.3f", accident_bbox$bbox_utm_numeric["ymin"]),
      sprintf("%.3f", accident_bbox$bbox_utm_numeric["xmax"]),
      sprintf("%.3f", accident_bbox$bbox_utm_numeric["ymax"]),
      as.character(roads_profile$source_feature_n),
      as.character(roads_profile$filtered_feature_n),
      as.character(roads_profile$clipped_feature_n),
      as.character(nrow(nodes_sf)),
      as.character(nrow(edges_sf)),
      sprintf("%.3f", sum(edges_sf$edge_length_m)),
      sprintf("%.3f", node_bbox["xmin"]),
      sprintf("%.3f", node_bbox["ymin"]),
      sprintf("%.3f", node_bbox["xmax"]),
      sprintf("%.3f", node_bbox["ymax"]),
      sprintf("%.3f", edge_bbox["xmin"]),
      sprintf("%.3f", edge_bbox["ymin"]),
      sprintf("%.3f", edge_bbox["xmax"]),
      sprintf("%.3f", edge_bbox["ymax"]),
      "FALSE"
    )
  )
}

rs_m8_build_matching_contract <- function() {
  tibble::tribble(
    ~contract_section, ~field_name, ~data_type, ~required, ~description, ~traceability_rule,
    "accident_input", "num_expediente", "character", TRUE, "Stable accident identifier at expediente level.", "Must come from accident_master and remain unchanged through matching.",
    "accident_input", "accident_x_utm", "double", TRUE, "Projected x coordinate in EPSG:25830.", "Distance calculations are only valid if CRS stays explicit.",
    "accident_input", "accident_y_utm", "double", TRUE, "Projected y coordinate in EPSG:25830.", "Distance calculations are only valid if CRS stays explicit.",
    "accident_input", "accident_crs_epsg", "integer", TRUE, "Coordinate reference system of the accident point.", "Must equal the canonical network CRS before matching.",
    "accident_input", "fecha", "date", TRUE, "Accident date for later historical aggregation windows.", "Should stay at accident level, not raw row level.",
    "accident_input", "hora", "time", TRUE, "Accident time for future temporal bucketing.", "Should remain attached to the matched edge record.",
    "accident_input", "tipo_accidente", "character", FALSE, "Accident type retained for downstream descriptive summaries.", "Not required to compute distance, but useful in later aggregation.",
    "edge_input", "edge_id", "character", TRUE, "Stable canonical edge identifier.", "Primary edge key; never substitute with sensor or tramo ids.",
    "edge_input", "from_node_id", "character", TRUE, "Origin node of the edge geometry orientation.", "Must exist in the canonical nodes table.",
    "edge_input", "to_node_id", "character", TRUE, "Destination node of the edge geometry orientation.", "Must exist in the canonical nodes table.",
    "edge_input", "edge_length_m", "double", TRUE, "Edge length in meters in the canonical CRS.", "Should be recomputable from geometry if needed.",
    "edge_input", "geometry", "LINESTRING", TRUE, "Canonical edge geometry in EPSG:25830.", "Distance to accident is always traced against this geometry.",
    "edge_input", "source_osm_id", "character", TRUE, "Original OSM feature id behind the canonical segment.", "Preserves provenance after segmentation.",
    "edge_input", "road_class", "character", FALSE, "Geofabrik road class retained for filtering and later routing logic.", "Auxiliary context; not a substitute for edge_id.",
    "matching_output", "match_status", "character", TRUE, "Binary match status: matched / unmatched.", "Ambiguity does not create a third status; it is reflected through quality_flag and tie diagnostics.",
    "matching_output", "edge_id", "character", TRUE, "Chosen canonical edge for the accident.", "Primary matched-edge field; must reference canonical edge_id, never tramo or sensor ids.",
    "matching_output", "candidate_edges_n", "integer", TRUE, "Number of candidate edges evaluated inside the search radius.", "Useful to detect ambiguous local geometry.",
    "matching_output", "search_radius_m", "double", TRUE, "Radius used to look for candidate edges around the accident point.", "Must be stored to reproduce the matching decision.",
    "matching_output", "distance_accident_to_edge_m", "double", TRUE, "Shortest point-to-line distance from accident to matched edge.", "Primary geometric traceability metric.",
    "matching_output", "distance_to_from_node_m", "double", FALSE, "Distance along the matched edge from the projected point to the start node.", "Useful to inspect projection position along the edge.",
    "matching_output", "distance_to_to_node_m", "double", FALSE, "Distance along the matched edge from the projected point to the end node.", "Useful to inspect projection position along the edge.",
    "matching_output", "projection_fraction_0_1", "double", FALSE, "Relative position of the projected point along the edge geometry.", "Useful to reproduce where along the edge the accident fell.",
    "matching_output", "projected_point_geometry", "character", FALSE, "Projected point geometry stored as WKT in the CSV output.", "Supports spatial QA of the matching output; the GeoJSON also stores the projected geometry as real geometry.",
    "matching_output", "matching_method", "character", TRUE, "Method identifier used in M9, e.g. nearest_edge_projected.", "Needed for auditability if the matching logic changes later.",
    "matching_output", "quality_flag", "character", TRUE, "Match quality label: high_confidence / medium_confidence / low_confidence / unmatched.", "Ambiguity is reflected here, not in match_status.",
    "matching_output", "tie_candidate_count", "integer", FALSE, "Number of candidates within the tie tolerance of the minimum distance.", "Useful to trace ambiguous local geometry around the selected edge.",
    "matching_output", "match_decision_rule", "character", FALSE, "Deterministic rule used to choose the final edge among candidates.", "Documents whether the match was resolved by min distance only or by tie-breaking.",
    "matching_output", "candidate_top3_edge_ids", "character", FALSE, "Top candidate edge ids ordered by selection priority.", "Compact audit trail for near alternatives.",
    "matching_output", "candidate_top3_distances_m", "character", FALSE, "Top candidate distances in meters ordered by selection priority.", "Compact audit trail for near alternatives.",
    "matching_output", "unmatched_reason", "character", FALSE, "Reason for unmatched status.", "Makes invalid coordinates, outside envelope and no-candidate cases explicit.",
    "matching_output", "outside_operational_envelope", "logical", FALSE, "Whether the accident lies outside the canonical network operational envelope.", "Supports explicit reporting of envelope coverage.",
    "matching_output", "nearest_edge_id_any", "character", FALSE, "Nearest canonical edge even when the accident remains unmatched.", "Diagnostic only; never treated as a successful match.",
    "matching_output", "nearest_distance_any_m", "double", FALSE, "Distance to the nearest canonical edge for unmatched cases.", "Diagnostic only; useful to inspect misses near the envelope or search radius."
  )
}

rs_m8_build_validation_summary <- function(nodes_sf, edges_sf) {
  node_valid <- sf::st_is_valid(nodes_sf)
  edge_valid <- sf::st_is_valid(edges_sf)
  node_geom_types <- unique(as.character(sf::st_geometry_type(nodes_sf)))
  edge_geom_types <- unique(as.character(sf::st_geometry_type(edges_sf)))
  node_ids_unique <- !anyDuplicated(nodes_sf$node_id)
  edge_ids_unique <- !anyDuplicated(edges_sf$edge_id)
  endpoints_exist <- all(edges_sf$from_node_id %in% nodes_sf$node_id) && all(edges_sf$to_node_id %in% nodes_sf$node_id)
  positive_lengths <- all(edges_sf$edge_length_m > 0)

  tibble::tibble(
    metric = c(
      "node_geometries_valid",
      "edge_geometries_valid",
      "node_geometry_type",
      "edge_geometry_type",
      "node_crs_epsg",
      "edge_crs_epsg",
      "node_ids_unique",
      "edge_ids_unique",
      "edge_endpoints_exist_in_nodes",
      "edge_lengths_positive",
      "routing_backbone_min_ready",
      "matching_contract_documented",
      "traffic_tramo_not_used_as_edge"
    ),
    value = c(
      as.character(all(node_valid)),
      as.character(all(edge_valid)),
      paste(node_geom_types, collapse = ","),
      paste(edge_geom_types, collapse = ","),
      as.character(sf::st_crs(nodes_sf)$epsg),
      as.character(sf::st_crs(edges_sf)$epsg),
      as.character(node_ids_unique),
      as.character(edge_ids_unique),
      as.character(endpoints_exist),
      as.character(positive_lengths),
      as.character(all(node_valid) && all(edge_valid) && node_ids_unique && edge_ids_unique && endpoints_exist && positive_lengths),
      "TRUE",
      "TRUE"
    )
  )
}

rs_m8_build_file_structure_updates <- function(source_paths) {
  tibble::tribble(
    ~path_blueprint, ~role_in_pipeline, ~status_after_m8, ~notes,
    "R/08_preparacion_red_canonica.R",
    "current_network_backbone_builder",
    "implemented_now",
    "Builds the canonical OSM road network backbone and the matching data contract.",
    source_paths$zip_path,
    "canonical_source_distribution",
    "implemented_now",
    "Cached Geofabrik source zip used to regenerate the canonical network when needed.",
    source_paths$roads_path,
    "canonical_source_layer",
    "implemented_now",
    "Geofabrik roads layer retained as the raw source for canonical edge preparation.",
    "outputs/data/m8_road_network_nodes.geojson",
    "canonical_nodes_geometry",
    "implemented_now",
    "Projected node geometry layer in EPSG:25830.",
    "outputs/data/m8_road_network_edges.geojson",
    "canonical_edges_geometry",
    "implemented_now",
    "Projected edge geometry layer in EPSG:25830 with stable edge ids.",
    "outputs/tables/m8_accident_edge_matching_contract.csv",
    "matching_contract",
    "implemented_now",
    "Documents the minimum fields and quality metrics for M9 matching.",
    "R/09_accidente_edge_matching.R",
    "future_matching_module",
    "planned_for_m9",
    "Will perform the real accident to edge assignment using the canonical network built in M8.",
    "R/10_agregacion_historica_edge.R",
    "future_historical_aggregation_module",
    "planned_for_m9_or_m10",
    "Will aggregate matched accidents by edge and time window.",
    "outputs/data/m9_accident_edge_matches.csv",
    "future_matching_output",
    "planned",
    "Will store audited matching outputs with distance metrics and quality flags."
  )
}

rs_m8_build_technical_note <- function(metadata, validation_summary) {
  get_metric <- function(metric_name) {
    values <- metadata |>
      dplyr::filter(metric == metric_name) |>
      dplyr::pull(value)
    if (!length(values)) {
      return(NA_character_)
    }
    values[[1]]
  }

  get_validation <- function(metric_name) {
    values <- validation_summary |>
      dplyr::filter(metric == metric_name) |>
      dplyr::pull(value)
    if (!length(values)) {
      return(NA_character_)
    }
    values[[1]]
  }

  paste(
    "# M8 - Red viaria canonica y contrato de matching",
    "",
    "## Por que esta red es la unidad canonica correcta",
    "- ROAD-SAFETY necesita una unidad espacial operativa para routing. Esa unidad no puede ser el accidente raw ni un tramo de trafico auxiliar: tiene que ser la arista del grafo.",
    "- Por eso M8 construye una red canonica de `nodes/edges` desde OpenStreetMap, usando un extracto estable de Geofabrik para Madrid, y la guarda en `EPSG:25830` para distancias y matching en metros.",
    "- El CSV de tramos de trafico sigue fuera de la definicion del edge final; puede servir despues como capa contextual, no como sustituto del backbone de routing.",
    "",
    "## Que queda listo tras M8",
    sprintf("- Red canonica preparada desde `%s` y normalizada a `EPSG:%s`.", get_metric("source_distribution_url"), get_metric("canonical_network_crs_epsg")),
            sprintf("- `nodes` y `edges` con IDs estables, geometrias validas y relaciones `from_node_id` / `to_node_id` trazables. Estado de backbone minimo: `%s`.", get_validation("routing_backbone_min_ready")),
            "- Contrato tecnico de matching accidente -> edge documentado, incluyendo distancia punto-edge, radio de busqueda, numero de candidatos y banderas de calidad.",
            sprintf("- El schema final esperado para M9 queda fijado como `%s`: `edge_id` como arista seleccionada, `projected_point_geometry` como WKT en CSV y `match_status` binario con la ambiguedad reflejada en `quality_flag`.", rs_m8_matching_output_schema_version),
            "- Separacion metodologica preservada: baseline/contextual, historico_espacial y routing final siguen desacoplados.",
    "",
    "## Que faltara en M9",
    "- Ejecutar el map-matching real accidente -> edge contra esta red canonica.",
    "- Definir umbrales operativos de distancia y reglas de calidad y ambiguedad.",
    "- Guardar el match con trazabilidad completa y preparar la agregacion historica por edge.",
    "- Seguir sin convertir todavia el resultado en score final de routing hasta que la capa historica y la exposicion esten cerradas.",
    "",
    sep = "\n"
  )
}

rs_m8_write_network_outputs <- function(nodes_sf, edges_sf, metadata, matching_contract, validation_summary, file_structure_updates, technical_note, output_paths) {
  for (path in c(output_paths$nodes_geojson, output_paths$edges_geojson)) {
    if (file.exists(path)) {
      file.remove(path)
    }
  }

  sf::st_write(nodes_sf, output_paths$nodes_geojson, driver = "GeoJSON", quiet = TRUE)
  sf::st_write(edges_sf, output_paths$edges_geojson, driver = "GeoJSON", quiet = TRUE)

  readr::write_csv(sf::st_drop_geometry(nodes_sf), output_paths$nodes_csv)
  readr::write_csv(sf::st_drop_geometry(edges_sf), output_paths$edges_csv)
  readr::write_csv(metadata, output_paths$metadata_csv)
  readr::write_csv(matching_contract, output_paths$matching_contract_csv)
  readr::write_csv(validation_summary, output_paths$validation_csv)
  readr::write_csv(file_structure_updates, output_paths$file_structure_csv)
  writeLines(technical_note, output_paths$note_md, useBytes = TRUE)
}

rs_run_m8_preparacion_red_canonica <- function(accident_master, paths, force_refresh = FALSE) {
  rs_check_m8_packages()
  rs_validate_m8_inputs(accident_master, paths)

  source_paths <- rs_m8_source_paths(paths)
  output_paths <- rs_m8_output_paths(paths)

  if (!force_refresh && rs_m8_cache_is_current(output_paths)) {
    cached <- rs_m8_read_cached_outputs(output_paths)
    cached$used_cache <- TRUE
    return(cached)
  }

  if (!force_refresh && rs_m8_can_refresh_auxiliary_outputs(output_paths)) {
    refreshed <- rs_m8_refresh_auxiliary_outputs_from_cached_network(output_paths, source_paths)
    refreshed$used_cache <- FALSE
    refreshed$used_cached_geometry <- TRUE
    return(refreshed)
  }

  rs_m8_ensure_geofabrik_source(source_paths)
  accident_bbox <- rs_m8_build_accident_bbox(accident_master)
  roads_profile <- rs_m8_read_geofabrik_roads(source_paths, accident_bbox)
  edges_raw <- rs_m8_segment_line_features(roads_profile$roads)
  nodes_sf <- rs_m8_build_nodes_from_edges(edges_raw)
  edges_sf <- rs_m8_attach_node_ids_and_lengths(edges_raw, nodes_sf)

  metadata <- rs_m8_build_network_metadata(accident_bbox, source_paths, roads_profile, nodes_sf, edges_sf)
  matching_contract <- rs_m8_build_matching_contract()
  validation_summary <- rs_m8_build_validation_summary(nodes_sf, edges_sf)
  file_structure_updates <- rs_m8_build_file_structure_updates(source_paths)
  technical_note <- rs_m8_build_technical_note(metadata, validation_summary)

  rs_m8_write_network_outputs(
    nodes_sf = nodes_sf,
    edges_sf = edges_sf,
    metadata = metadata,
    matching_contract = matching_contract,
    validation_summary = validation_summary,
    file_structure_updates = file_structure_updates,
    technical_note = technical_note,
    output_paths = output_paths
  )

  list(
    nodes_path = output_paths$nodes_geojson,
    edges_path = output_paths$edges_geojson,
    metadata = metadata,
    matching_contract = matching_contract,
    validation_summary = validation_summary,
    file_structure_updates = file_structure_updates,
    technical_note = technical_note,
    used_cache = FALSE,
    used_cached_geometry = FALSE
  )
}
