parse_args <- function(args) {
  parsed <- list(
    accidents_csv = NULL,
    output_parquet = NULL,
    network_zip = NULL,
    force = FALSE
  )

  i <- 1L
  while (i <= length(args)) {
    arg <- args[[i]]
    if (identical(arg, "--accidents-csv")) {
      i <- i + 1L
      parsed$accidents_csv <- args[[i]]
    } else if (identical(arg, "--output-parquet")) {
      i <- i + 1L
      parsed$output_parquet <- args[[i]]
    } else if (identical(arg, "--network-zip")) {
      i <- i + 1L
      parsed$network_zip <- args[[i]]
    } else if (identical(arg, "--force")) {
      parsed$force <- TRUE
    } else {
      stop(sprintf("Unknown argument: %s", arg), call. = FALSE)
    }
    i <- i + 1L
  }

  required <- c("accidents_csv", "output_parquet")
  missing <- required[!nzchar(vapply(parsed[required], function(x) if (is.null(x)) "" else x, character(1)))]
  if (length(missing) > 0L) {
    stop(sprintf("Missing required arguments: %s", paste(missing, collapse = ", ")), call. = FALSE)
  }

  parsed
}

check_required_packages <- function() {
  required_packages <- c("arrow", "digest", "dplyr", "janitor", "lubridate", "readr", "sf", "tibble")
  missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]

  if (length(missing_packages) > 0L) {
    stop(
      sprintf("Missing required R packages: %s", paste(missing_packages, collapse = ", ")),
      call. = FALSE
    )
  }
}

resolve_existing_file <- function(path_value, label) {
  if (is.null(path_value) || !nzchar(path_value)) {
    stop(sprintf("%s is required.", label), call. = FALSE)
  }

  resolved <- normalizePath(path_value, winslash = "/", mustWork = FALSE)
  if (!file.exists(resolved)) {
    stop(sprintf("Missing required input for %s: %s", label, resolved), call. = FALSE)
  }

  resolved
}

resolve_output_file <- function(path_value) {
  if (is.null(path_value) || !nzchar(path_value)) {
    stop("output_parquet is required.", call. = FALSE)
  }

  path_value <- normalizePath(path_value, winslash = "/", mustWork = FALSE)
  output_dir <- dirname(path_value)
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  }
  path_value
}

pick_first_column <- function(data, candidates, label) {
  existing <- intersect(candidates, names(data))
  if (!length(existing)) {
    stop(sprintf("Could not find a column for %s. Tried: %s", label, paste(candidates, collapse = ", ")), call. = FALSE)
  }
  existing[[1]]
}

map_temporal_bin <- function(hour_value) {
  dplyr::case_when(
    hour_value < 4 ~ "00_03",
    hour_value < 8 ~ "04_07",
    hour_value < 12 ~ "08_11",
    hour_value < 16 ~ "12_15",
    hour_value < 20 ~ "16_19",
    TRUE ~ "20_23"
  )
}

temporal_bin_center <- function(bin_label) {
  dplyr::case_when(
    identical(bin_label, "00_03") ~ 1.5,
    identical(bin_label, "04_07") ~ 5.5,
    identical(bin_label, "08_11") ~ 9.5,
    identical(bin_label, "12_15") ~ 13.5,
    identical(bin_label, "16_19") ~ 17.5,
    TRUE ~ 21.5
  )
}

load_accidents <- function(path_value) {
  data <- readr::read_csv(path_value, show_col_types = FALSE, progress = FALSE)
  data <- janitor::clean_names(data)

  date_col <- pick_first_column(data, c("fecha", "fecha_accidente", "date"), "date")
  time_col <- pick_first_column(data, c("hora", "hora_accidente", "time"), "time")
  x_col <- pick_first_column(data, c("coordenada_x_utm", "coord_x_utm", "x_utm"), "utm x")
  y_col <- pick_first_column(data, c("coordenada_y_utm", "coord_y_utm", "y_utm"), "utm y")
  district_candidates <- intersect(c("distrito", "cod_distrito", "district"), names(data))
  address_candidates <- intersect(c("direccion_unica", "direccion", "localizacion", "street_name"), names(data))

  parsed_datetime <- suppressWarnings(
    lubridate::parse_date_time(
      paste(data[[date_col]], data[[time_col]]),
      orders = c("Ymd HMS", "Ymd HM", "dmY HMS", "dmY HM", "mdY HMS", "mdY HM"),
      quiet = TRUE
    )
  )

  accidents <- tibble::tibble(
    accident_row_id = seq_len(nrow(data)),
    raw_date = data[[date_col]],
    raw_time = data[[time_col]],
    accident_datetime = parsed_datetime,
    coordenada_x_utm = suppressWarnings(as.numeric(data[[x_col]])),
    coordenada_y_utm = suppressWarnings(as.numeric(data[[y_col]])),
    distrito = if (length(district_candidates)) as.character(data[[district_candidates[[1]]]]) else NA_character_,
    direccion_unica = if (length(address_candidates)) as.character(data[[address_candidates[[1]]]]) else NA_character_
  ) |>
    dplyr::filter(
      !is.na(accident_datetime),
      !is.na(coordenada_x_utm),
      !is.na(coordenada_y_utm)
    ) |>
    dplyr::mutate(
      analysis_year = lubridate::year(accident_datetime),
      hour_value = lubridate::hour(accident_datetime),
      temporal_bin_4h = map_temporal_bin(hour_value),
      is_weekend = lubridate::wday(accident_datetime, week_start = 1) >= 6
    ) |>
    dplyr::distinct(
      accident_datetime,
      coordenada_x_utm,
      coordenada_y_utm,
      distrito,
      direccion_unica,
      .keep_all = TRUE
    )

  if (!nrow(accidents)) {
    stop("No valid accident rows were left after parsing coordinates and timestamps.", call. = FALSE)
  }

  accidents
}

prepare_network_extract <- function(zip_path) {
  extract_root <- file.path(tempdir(), "road_safety_network_extract")
  if (!dir.exists(extract_root)) {
    dir.create(extract_root, recursive = TRUE, showWarnings = FALSE)
  }

  utils::unzip(zip_path, exdir = extract_root)
  shp_candidates <- list.files(
    extract_root,
    pattern = "gis_osm_roads_free_1\\.shp$",
    recursive = TRUE,
    full.names = TRUE
  )

  if (!length(shp_candidates)) {
    stop("Could not find gis_osm_roads_free_1.shp inside network_zip.", call. = FALSE)
  }

  shp_candidates[[1]]
}

load_network_edges <- function(network_zip_path) {
  shp_path <- prepare_network_extract(network_zip_path)
  roads_sf <- sf::st_read(shp_path, quiet = TRUE)

  if (is.na(sf::st_crs(roads_sf))) {
    sf::st_crs(roads_sf) <- 4326
  }
  roads_sf <- sf::st_transform(roads_sf, 25830)

  roads_sf <- roads_sf |>
    dplyr::filter(
      .data$fclass %in% c(
        "motorway", "motorway_link",
        "trunk", "trunk_link",
        "primary", "primary_link",
        "secondary", "secondary_link",
        "tertiary", "tertiary_link",
        "residential", "living_street", "service", "unclassified"
      )
    ) |>
    dplyr::mutate(
      edge_id = paste0("edge_", seq_len(dplyr::n())),
      edge_length_m = as.numeric(sf::st_length(geometry))
    )

  if (!nrow(roads_sf)) {
    stop("No drivable road segments were found in the network layer.", call. = FALSE)
  }

  coords <- sf::st_coordinates(roads_sf)
  coords_df <- tibble::as_tibble(coords)
  line_parts <- split(coords_df, coords_df$L1)

  endpoint_df <- tibble::tibble(
    edge_id = roads_sf$edge_id,
    start_node = vapply(
      line_parts,
      function(part) sprintf("%.3f_%.3f", part$X[[1]], part$Y[[1]]),
      character(1)
    ),
    end_node = vapply(
      line_parts,
      function(part) sprintf("%.3f_%.3f", part$X[[nrow(part)]], part$Y[[nrow(part)]]),
      character(1)
    )
  )

  node_degree <- tibble::tibble(node_id = c(endpoint_df$start_node, endpoint_df$end_node)) |>
    dplyr::count(node_id, name = "degree_total")

  edges <- roads_sf |>
    dplyr::select(edge_id, fclass, maxspeed, oneway, tunnel, geometry, edge_length_m) |>
    dplyr::left_join(endpoint_df, by = "edge_id") |>
    dplyr::left_join(node_degree, by = c("start_node" = "node_id")) |>
    dplyr::rename(from_degree = degree_total) |>
    dplyr::left_join(node_degree, by = c("end_node" = "node_id")) |>
    dplyr::rename(to_degree = degree_total)

  maxspeed_numeric <- suppressWarnings(as.numeric(gsub("[^0-9.]+", "", as.character(edges$maxspeed))))
  maxspeed_numeric[maxspeed_numeric <= 0] <- NA_real_
  class_medians <- tibble::tibble(fclass = edges$fclass, maxspeed = maxspeed_numeric) |>
    dplyr::group_by(fclass) |>
    dplyr::summarise(class_median = median(maxspeed, na.rm = TRUE), .groups = "drop")
  global_median <- stats::median(maxspeed_numeric, na.rm = TRUE)
  if (!is.finite(global_median)) {
    global_median <- 50
  }

  edge_centroids <- sf::st_centroid(edges)
  network_centroid <- sf::st_centroid(sf::st_union(sf::st_geometry(edges)))

  edges <- edges |>
    dplyr::left_join(class_medians, by = "fclass") |>
    dplyr::mutate(
      from_degree = dplyr::coalesce(from_degree, 1L),
      to_degree = dplyr::coalesce(to_degree, 1L),
      exog_road_class_is_major_flag = as.integer(
        .data$fclass %in% c("motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link")
      ),
      exog_maxspeed_missing_flag = as.integer(is.na(maxspeed_numeric)),
      exog_maxspeed_kph_imputed_by_road_class = dplyr::coalesce(maxspeed_numeric, class_median, global_median),
      exog_oneway_code_b_flag = as.integer(tolower(as.character(.data$oneway)) == "b"),
      exog_tunnel_flag = as.integer(!is.na(.data$tunnel) & .data$tunnel != "" & .data$tunnel != "no"),
      exog_node_degree_mean = (from_degree + to_degree) / 2,
      exog_edge_touches_dead_end_flag = as.integer(from_degree == 1 | to_degree == 1),
      exog_distance_from_network_centroid_km = as.numeric(sf::st_distance(edge_centroids, network_centroid)) / 1000
    ) |>
    dplyr::select(
      edge_id,
      geometry,
      edge_length_m,
      exog_road_class_is_major_flag,
      exog_maxspeed_kph_imputed_by_road_class,
      exog_maxspeed_missing_flag,
      exog_oneway_code_b_flag,
      exog_tunnel_flag,
      exog_node_degree_mean,
      exog_edge_touches_dead_end_flag,
      exog_distance_from_network_centroid_km
    )

  edges
}

build_pseudo_edges <- function(accidents) {
  grouped <- accidents |>
    dplyr::mutate(
      grid_x = round(coordenada_x_utm / 50),
      grid_y = round(coordenada_y_utm / 50),
      pseudo_key = ifelse(
        !is.na(direccion_unica) & nzchar(direccion_unica),
        paste0("addr_", direccion_unica),
        paste0("grid_", grid_x, "_", grid_y)
      )
    )

  edge_table <- grouped |>
    dplyr::group_by(pseudo_key) |>
    dplyr::summarise(
      x_mean = mean(coordenada_x_utm, na.rm = TRUE),
      y_mean = mean(coordenada_y_utm, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      edge_id = paste0("edge_", vapply(pseudo_key, digest::digest, character(1), algo = "xxhash64")),
      edge_length_m = 50,
      exog_road_class_is_major_flag = 0,
      exog_maxspeed_kph_imputed_by_road_class = 50,
      exog_maxspeed_missing_flag = 1,
      exog_oneway_code_b_flag = 0,
      exog_tunnel_flag = 0,
      exog_node_degree_mean = 2,
      exog_edge_touches_dead_end_flag = 0
    )

  centroid_x <- mean(edge_table$x_mean, na.rm = TRUE)
  centroid_y <- mean(edge_table$y_mean, na.rm = TRUE)
  edge_table$exog_distance_from_network_centroid_km <- sqrt(
    (edge_table$x_mean - centroid_x) ^ 2 + (edge_table$y_mean - centroid_y) ^ 2
  ) / 1000

  matched <- grouped |>
    dplyr::left_join(edge_table, by = "pseudo_key")

  list(matches = matched, edges = edge_table)
}

match_accidents_to_edges <- function(accidents, network_zip_path = NULL) {
  if (!is.null(network_zip_path) && nzchar(network_zip_path) && file.exists(network_zip_path)) {
    edges_sf <- load_network_edges(network_zip_path)
    accident_sf <- sf::st_as_sf(
      accidents,
      coords = c("coordenada_x_utm", "coordenada_y_utm"),
      crs = 25830,
      remove = FALSE
    )
    nearest_idx <- sf::st_nearest_feature(accident_sf, edges_sf)
    nearest_edges <- edges_sf[nearest_idx, ]

    matched <- tibble::as_tibble(accidents) |>
      dplyr::bind_cols(
        sf::st_drop_geometry(nearest_edges) |>
          dplyr::select(
            edge_id,
            edge_length_m,
            exog_road_class_is_major_flag,
            exog_maxspeed_kph_imputed_by_road_class,
            exog_maxspeed_missing_flag,
            exog_oneway_code_b_flag,
            exog_tunnel_flag,
            exog_node_degree_mean,
            exog_edge_touches_dead_end_flag,
            exog_distance_from_network_centroid_km
          )
      )

    list(matches = matched, edges = sf::st_drop_geometry(edges_sf))
  } else {
    build_pseudo_edges(accidents)
  }
}

build_full_panel <- function(matched_accidents, edge_table) {
  all_years <- seq(min(matched_accidents$analysis_year), max(matched_accidents$analysis_year))
  all_bins <- c("00_03", "04_07", "08_11", "12_15", "16_19", "20_23")

  panel <- expand.grid(
    edge_id = unique(edge_table$edge_id),
    analysis_year = all_years,
    temporal_bin_4h = all_bins,
    is_weekend = c(FALSE, TRUE),
    stringsAsFactors = FALSE
  ) |>
    tibble::as_tibble() |>
    dplyr::left_join(
      edge_table |>
        dplyr::select(
          edge_id,
          edge_length_m,
          exog_road_class_is_major_flag,
          exog_maxspeed_kph_imputed_by_road_class,
          exog_maxspeed_missing_flag,
          exog_oneway_code_b_flag,
          exog_tunnel_flag,
          exog_node_degree_mean,
          exog_edge_touches_dead_end_flag,
          exog_distance_from_network_centroid_km
        ),
      by = "edge_id"
    )

  accident_counts <- matched_accidents |>
    dplyr::group_by(edge_id, analysis_year, temporal_bin_4h, is_weekend) |>
    dplyr::summarise(accident_count = dplyr::n(), .groups = "drop")

  panel |>
    dplyr::left_join(accident_counts, by = c("edge_id", "analysis_year", "temporal_bin_4h", "is_weekend")) |>
    dplyr::mutate(
      accident_count = dplyr::coalesce(accident_count, 0L),
      temporal_bin_center_hour = dplyr::case_when(
        temporal_bin_4h == "00_03" ~ 1.5,
        temporal_bin_4h == "04_07" ~ 5.5,
        temporal_bin_4h == "08_11" ~ 9.5,
        temporal_bin_4h == "12_15" ~ 13.5,
        temporal_bin_4h == "16_19" ~ 17.5,
        TRUE ~ 21.5
      ),
      hour_sin = sin(2 * pi * temporal_bin_center_hour / 24),
      hour_cos = cos(2 * pi * temporal_bin_center_hour / 24),
      exog_temporal_is_night_flag = as.integer(temporal_bin_4h %in% c("00_03", "20_23")),
      exog_temporal_is_weekday_peak_flag = as.integer(!is_weekend & temporal_bin_4h %in% c("08_11", "16_19"))
    )
}

compute_prior_total <- function(values) {
  if (!length(values)) {
    return(numeric(0))
  }
  c(0, head(cumsum(values), -1))
}

compute_recent_window_sum <- function(values, window = 3L) {
  vapply(
    seq_along(values),
    function(i) {
      if (i == 1L) {
        return(0)
      }
      start_idx <- max(1L, i - window)
      sum(values[start_idx:(i - 1L)])
    },
    numeric(1)
  )
}

compute_recent_obs_n <- function(length_value, window = 3L) {
  vapply(
    seq_len(length_value),
    function(i) {
      min(window, max(0L, i - 1L))
    },
    numeric(1)
  )
}

add_historical_features <- function(panel) {
  edge_year <- panel |>
    dplyr::group_by(edge_id, analysis_year) |>
    dplyr::summarise(edge_year_accident_count = sum(accident_count), .groups = "drop") |>
    dplyr::arrange(edge_id, analysis_year) |>
    dplyr::group_by(edge_id) |>
    dplyr::mutate(
      edge_accident_count_prior_total = compute_prior_total(edge_year_accident_count),
      edge_accident_count_prior_recent_3y = compute_recent_window_sum(edge_year_accident_count, window = 3L)
    ) |>
    dplyr::ungroup() |>
    dplyr::select(edge_id, analysis_year, edge_accident_count_prior_total, edge_accident_count_prior_recent_3y)

  edge_bin_year <- panel |>
    dplyr::group_by(edge_id, temporal_bin_4h, is_weekend, analysis_year) |>
    dplyr::summarise(edge_bin_year_accident_count = sum(accident_count), .groups = "drop") |>
    dplyr::arrange(edge_id, temporal_bin_4h, is_weekend, analysis_year) |>
    dplyr::group_by(edge_id, temporal_bin_4h, is_weekend) |>
    dplyr::mutate(
      edge_bin_accident_count_prior = compute_prior_total(edge_bin_year_accident_count),
      edge_bin_accident_count_prior_recent_3y = compute_recent_window_sum(edge_bin_year_accident_count, window = 3L),
      prior_context_observation_n_recent_3y = compute_recent_obs_n(dplyr::n(), window = 3L)
    ) |>
    dplyr::ungroup() |>
    dplyr::select(
      edge_id,
      temporal_bin_4h,
      is_weekend,
      analysis_year,
      edge_bin_accident_count_prior,
      edge_bin_accident_count_prior_recent_3y,
      prior_context_observation_n_recent_3y
    )

  panel |>
    dplyr::left_join(edge_year, by = c("edge_id", "analysis_year")) |>
    dplyr::left_join(edge_bin_year, by = c("edge_id", "temporal_bin_4h", "is_weekend", "analysis_year")) |>
    dplyr::mutate(
      prior_dynamic_context_signal_recent_3y = edge_bin_accident_count_prior_recent_3y / pmax(edge_length_m / 1000, 0.001),
      prior_dynamic_context_signal_recent_3y_missing_flag = as.integer(prior_context_observation_n_recent_3y == 0),
      prior_dynamic_context_signal_recent_3y_fallback_level = dplyr::case_when(
        prior_context_observation_n_recent_3y > 0 ~ "edge_bin_weekend",
        edge_accident_count_prior_recent_3y > 0 ~ "edge_bin",
        TRUE ~ "global_bin_weekend"
      )
    )
}

finalize_output_table <- function(panel) {
  panel |>
    dplyr::transmute(
      edge_id = as.character(edge_id),
      analysis_year = as.integer(analysis_year),
      temporal_bin_4h = as.character(temporal_bin_4h),
      is_weekend = as.logical(is_weekend),
      accident_count = as.integer(accident_count),
      edge_length_m = as.numeric(edge_length_m),
      hour_sin = as.numeric(hour_sin),
      hour_cos = as.numeric(hour_cos),
      edge_accident_count_prior_total = as.numeric(edge_accident_count_prior_total),
      edge_bin_accident_count_prior = as.numeric(edge_bin_accident_count_prior),
      edge_accident_count_prior_recent_3y = as.numeric(edge_accident_count_prior_recent_3y),
      edge_bin_accident_count_prior_recent_3y = as.numeric(edge_bin_accident_count_prior_recent_3y),
      prior_dynamic_context_signal_recent_3y = as.numeric(prior_dynamic_context_signal_recent_3y),
      prior_context_observation_n_recent_3y = as.numeric(prior_context_observation_n_recent_3y),
      prior_dynamic_context_signal_recent_3y_missing_flag = as.integer(prior_dynamic_context_signal_recent_3y_missing_flag),
      prior_dynamic_context_signal_recent_3y_fallback_level = as.character(prior_dynamic_context_signal_recent_3y_fallback_level),
      exog_road_class_is_major_flag = as.integer(exog_road_class_is_major_flag),
      exog_maxspeed_kph_imputed_by_road_class = as.numeric(exog_maxspeed_kph_imputed_by_road_class),
      exog_maxspeed_missing_flag = as.integer(exog_maxspeed_missing_flag),
      exog_oneway_code_b_flag = as.integer(exog_oneway_code_b_flag),
      exog_tunnel_flag = as.integer(exog_tunnel_flag),
      exog_node_degree_mean = as.numeric(exog_node_degree_mean),
      exog_edge_touches_dead_end_flag = as.integer(exog_edge_touches_dead_end_flag),
      exog_distance_from_network_centroid_km = as.numeric(exog_distance_from_network_centroid_km),
      exog_temporal_is_night_flag = as.integer(exog_temporal_is_night_flag),
      exog_temporal_is_weekday_peak_flag = as.integer(exog_temporal_is_weekday_peak_flag)
    )
}

write_output_parquet <- function(data, output_path) {
  arrow::write_parquet(data, output_path)
}

build_final_parquet <- function(accidents_csv, output_parquet, network_zip = NULL, force = FALSE) {
  check_required_packages()

  accidents_csv <- resolve_existing_file(accidents_csv, "accidents_csv")
  output_parquet <- resolve_output_file(output_parquet)
  if (!is.null(network_zip)) {
    network_zip <- resolve_existing_file(network_zip, "network_zip")
  }

  if (file.exists(output_parquet) && !isTRUE(force)) {
    return(output_parquet)
  }

  accidents <- load_accidents(accidents_csv)
  matched <- match_accidents_to_edges(accidents, network_zip_path = network_zip)
  panel <- build_full_panel(matched$matches, matched$edges)
  panel <- add_historical_features(panel)
  final_table <- finalize_output_table(panel)

  write_output_parquet(final_table, output_parquet)
  output_parquet
}

main <- function() {
  parsed <- parse_args(commandArgs(trailingOnly = TRUE))
  output_parquet <- build_final_parquet(
    accidents_csv = parsed$accidents_csv,
    output_parquet = parsed$output_parquet,
    network_zip = parsed$network_zip,
    force = parsed$force
  )

  cat(sprintf("output_parquet=%s\n", normalizePath(output_parquet, winslash = "/", mustWork = TRUE)))
}

main()
