rs_m10_required_match_columns <- c(
  "num_expediente",
  "edge_id",
  "fecha",
  "quality_flag",
  "match_status"
)

rs_m10_quality_weights <- c(
  high_confidence = 1.00,
  medium_confidence = 0.75,
  low_confidence = 0.40,
  unmatched = 0.00
)

rs_m10_output_schema_version <- "m10_schema_v1_full_network_weighted_density_prelim_score"
rs_m10_short_edge_flag_threshold_m <- 25
rs_m10_score_cap_quantile <- 0.95
rs_m10_top_n <- 25L

rs_check_m10_packages <- function() {
  required_packages <- c("dplyr", "tibble", "readr", "sf")
  missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]

  if (length(missing_packages) > 0L) {
    stop(
      sprintf(
        "Faltan paquetes requeridos para M10: %s",
        paste(missing_packages, collapse = ", ")
      ),
      call. = FALSE
    )
  }
}

rs_validate_m10_inputs <- function(m8_result, paths) {
  if (missing(m8_result) || is.null(m8_result)) {
    stop("M10 necesita los artefactos de M8 para la red canonica.", call. = FALSE)
  }

  if (!"edges_path" %in% names(m8_result) || !file.exists(m8_result$edges_path)) {
    stop("M10 necesita `edges_path` valido dentro de m8_result.", call. = FALSE)
  }

  required_paths <- c("output_data", "output_tables")
  if (!all(required_paths %in% names(paths))) {
    stop("M10 necesita output_data y output_tables dentro de paths.", call. = FALSE)
  }
}

rs_m10_output_paths <- function(paths) {
  list(
    aggregation_csv = file.path(paths$output_data, "m10_edge_historical_aggregation.csv"),
    aggregation_geojson = file.path(paths$output_data, "m10_edge_historical_aggregation.geojson"),
    score_summary_csv = file.path(paths$output_tables, "m10_historical_score_summary.csv"),
    coverage_summary_csv = file.path(paths$output_tables, "m10_edge_coverage_summary.csv"),
    weighting_rule_csv = file.path(paths$output_tables, "m10_quality_weighting_rule.csv"),
    top_edges_csv = file.path(paths$output_tables, "m10_top_risk_edges.csv"),
    note_md = file.path(paths$output_tables, "m10_historical_score_note.md"),
    validation_csv = file.path(paths$output_tables, "m10_validation_summary.csv")
  )
}

rs_m10_artifacts_ready <- function(output_paths) {
  all(file.exists(unlist(output_paths, use.names = FALSE)))
}

rs_m10_quality_weighting_rule <- function() {
  tibble::tribble(
    ~quality_flag, ~weight, ~used_in_raw_count, ~used_in_weighted_count, ~rationale, ~schema_version,
    "high_confidence", 1.00, TRUE, TRUE, "Referencia completa: match sin ambiguedad y con distancia corta.", rs_m10_output_schema_version,
    "medium_confidence", 0.75, TRUE, TRUE, "Conserva la mayor parte de la senal historica, pero descuenta incertidumbre geometrica moderada.", rs_m10_output_schema_version,
    "low_confidence", 0.40, TRUE, TRUE, "Se mantiene para no borrar historia plausible, pero con descuento fuerte porque el edge especifico es mas ambiguo.", rs_m10_output_schema_version,
    "unmatched", 0.00, FALSE, FALSE, "No entra en la agregacion por edge; se reporta aparte como exclusion.", rs_m10_output_schema_version
  )
}

rs_m10_cache_is_current <- function(output_paths) {
  if (!rs_m10_artifacts_ready(output_paths)) {
    return(FALSE)
  }

  weighting_rule <- tryCatch(
    readr::read_csv(output_paths$weighting_rule_csv, show_col_types = FALSE),
    error = function(...) NULL
  )
  validation <- tryCatch(
    readr::read_csv(output_paths$validation_csv, show_col_types = FALSE),
    error = function(...) NULL
  )

  if (is.null(weighting_rule) || is.null(validation)) {
    return(FALSE)
  }

  expected_rule <- rs_m10_quality_weighting_rule() |>
    dplyr::select(quality_flag, weight, schema_version)
  found_rule <- weighting_rule |>
    dplyr::select(quality_flag, weight, schema_version)

  same_rule <- nrow(expected_rule) == nrow(found_rule) &&
    identical(expected_rule$quality_flag, found_rule$quality_flag) &&
    all(abs(expected_rule$weight - found_rule$weight) < 1e-9) &&
    identical(expected_rule$schema_version, found_rule$schema_version)

  schema_value <- validation |>
    dplyr::filter(metric == "output_schema_version") |>
    dplyr::pull(value)

  same_rule && length(schema_value) == 1L && identical(schema_value[[1]], rs_m10_output_schema_version)
}

rs_m10_read_cached_outputs <- function(output_paths) {
  list(
    aggregation = readr::read_csv(output_paths$aggregation_csv, show_col_types = FALSE),
    score_summary = readr::read_csv(output_paths$score_summary_csv, show_col_types = FALSE),
    coverage_summary = readr::read_csv(output_paths$coverage_summary_csv, show_col_types = FALSE),
    weighting_rule = readr::read_csv(output_paths$weighting_rule_csv, show_col_types = FALSE),
    top_risk_edges = readr::read_csv(output_paths$top_edges_csv, show_col_types = FALSE),
    validation_summary = readr::read_csv(output_paths$validation_csv, show_col_types = FALSE),
    historical_note = paste(readLines(output_paths$note_md, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
    used_cache = TRUE
  )
}

rs_m10_load_m9_inputs <- function(m9_result, paths) {
  if (!missing(m9_result) && !is.null(m9_result) && all(c("matches", "unmatched", "validation_summary") %in% names(m9_result))) {
    return(list(
      matches = m9_result$matches,
      unmatched = m9_result$unmatched,
      validation_summary = m9_result$validation_summary
    ))
  }

  matches_path <- file.path(paths$output_data, "m9_accident_edge_matches.csv")
  unmatched_path <- file.path(paths$output_data, "m9_unmatched_accidents.csv")
  validation_path <- file.path(paths$output_tables, "m9_matching_validation_summary.csv")

  if (!file.exists(matches_path) || !file.exists(unmatched_path) || !file.exists(validation_path)) {
    stop("M10 necesita los artefactos M9 (`matches`, `unmatched`, `validation_summary`).", call. = FALSE)
  }

  list(
    matches = readr::read_csv(matches_path, show_col_types = FALSE),
    unmatched = readr::read_csv(unmatched_path, show_col_types = FALSE),
    validation_summary = readr::read_csv(validation_path, show_col_types = FALSE)
  )
}

rs_m10_load_edges <- function(m8_result) {
  edges_sf <- sf::st_read(m8_result$edges_path, quiet = TRUE)

  required_edge_columns <- c("edge_id", "edge_length_m")
  missing_columns <- setdiff(required_edge_columns, names(edges_sf))
  if (length(missing_columns) > 0L) {
    stop(
      sprintf(
        "Faltan columnas requeridas en la red canonica para M10: %s",
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

rs_m10_validate_matches <- function(matches_df) {
  missing_columns <- setdiff(rs_m10_required_match_columns, names(matches_df))
  if (length(missing_columns) > 0L) {
    stop(
      sprintf(
        "Faltan columnas requeridas en los matches de M9 para M10: %s",
        paste(missing_columns, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  if (any(matches_df$match_status != "matched")) {
    stop("M10 solo debe recibir accidentes matched en la tabla principal de M9.", call. = FALSE)
  }
}

rs_m10_prepare_matches <- function(matches_df) {
  rs_m10_validate_matches(matches_df)

  quality_weights <- rs_m10_quality_weighting_rule() |>
    dplyr::select(quality_flag, weight)

  matches_df |>
    dplyr::mutate(
      fecha = as.Date(fecha),
      match_year = as.integer(format(fecha, "%Y"))
    ) |>
    dplyr::left_join(quality_weights, by = "quality_flag") |>
    dplyr::rename(quality_weight = weight) |>
    dplyr::mutate(
      quality_weight = dplyr::coalesce(quality_weight, 0)
    )
}

rs_m10_build_edge_level_aggregation <- function(matches_prepared, edges_sf) {
  edge_history <- matches_prepared |>
    dplyr::group_by(edge_id) |>
    dplyr::summarise(
      accident_count_raw = dplyr::n(),
      accident_count_high_confidence = sum(quality_flag == "high_confidence"),
      accident_count_medium_confidence = sum(quality_flag == "medium_confidence"),
      accident_count_low_confidence = sum(quality_flag == "low_confidence"),
      accident_count_weighted_by_quality = sum(quality_weight),
      first_accident_date = min(fecha, na.rm = TRUE),
      last_accident_date = max(fecha, na.rm = TRUE),
      active_years_n = dplyr::n_distinct(match_year),
      .groups = "drop"
    )

  edges_df <- edges_sf |>
    sf::st_drop_geometry() |>
    dplyr::select(edge_id, edge_length_m)

  full_edge_history <- edges_df |>
    dplyr::left_join(edge_history, by = "edge_id") |>
    dplyr::mutate(
      accident_count_raw = dplyr::coalesce(accident_count_raw, 0L),
      accident_count_high_confidence = dplyr::coalesce(accident_count_high_confidence, 0L),
      accident_count_medium_confidence = dplyr::coalesce(accident_count_medium_confidence, 0L),
      accident_count_low_confidence = dplyr::coalesce(accident_count_low_confidence, 0L),
      accident_count_weighted_by_quality = dplyr::coalesce(accident_count_weighted_by_quality, 0),
      active_years_n = dplyr::coalesce(active_years_n, 0L),
      first_accident_date = as.Date(first_accident_date),
      last_accident_date = as.Date(last_accident_date)
    )

  full_edge_history
}

rs_m10_add_density_and_score <- function(edge_history_df) {
  edge_history_df <- edge_history_df |>
    dplyr::mutate(
      accidents_per_km_raw = dplyr::if_else(
        edge_length_m > 0,
        accident_count_raw / (edge_length_m / 1000),
        NA_real_
      ),
      accidents_per_km = dplyr::if_else(
        edge_length_m > 0,
        accident_count_weighted_by_quality / (edge_length_m / 1000),
        NA_real_
      )
    )

  positive_density <- edge_history_df$accidents_per_km[edge_history_df$accidents_per_km > 0]
  density_cap <- if (length(positive_density)) {
    as.numeric(stats::quantile(positive_density, rs_m10_score_cap_quantile, na.rm = TRUE))
  } else {
    1
  }

  edge_history_df <- edge_history_df |>
    dplyr::mutate(
      historical_score_prelim = dplyr::if_else(
        accident_count_weighted_by_quality > 0 & density_cap > 0,
        100 * pmin(accidents_per_km, density_cap) / density_cap,
        0
      )
    )

  note_flags <- character(nrow(edge_history_df))
  note_flags[] <- ""

  append_flag <- function(existing, mask, flag_name) {
    existing[mask] <- ifelse(
      existing[mask] == "",
      flag_name,
      paste(existing[mask], flag_name, sep = " | ")
    )
    existing
  }

  note_flags <- append_flag(note_flags, edge_history_df$accident_count_raw == 0L, "no_matched_accidents")
  note_flags <- append_flag(
    note_flags,
    edge_history_df$accident_count_raw > 0L &
      edge_history_df$accident_count_high_confidence == 0L &
      edge_history_df$accident_count_medium_confidence == 0L,
    "only_low_confidence_history"
  )
  note_flags <- append_flag(note_flags, edge_history_df$accident_count_raw == 1L, "single_matched_accident")
  note_flags <- append_flag(note_flags, edge_history_df$active_years_n == 1L & edge_history_df$accident_count_raw > 0L, "single_year_history")
  note_flags <- append_flag(note_flags, edge_history_df$edge_length_m < rs_m10_short_edge_flag_threshold_m, "short_edge_under_25m")
  note_flags <- append_flag(note_flags, edge_history_df$accidents_per_km > density_cap & edge_history_df$accident_count_raw > 0L, "score_capped_at_p95_density")

  edge_history_df |>
    dplyr::mutate(
      historical_score_prelim = round(historical_score_prelim, 3),
      accident_count_weighted_by_quality = round(accident_count_weighted_by_quality, 3),
      accidents_per_km_raw = round(accidents_per_km_raw, 3),
      accidents_per_km = round(accidents_per_km, 3),
      notes_or_flags = dplyr::na_if(note_flags, "")
    ) |>
    list(
      edge_history = _,
      density_cap = density_cap
    )
}

rs_m10_metric_summary <- function(values, summary_name) {
  non_missing <- values[!is.na(values)]
  positive <- non_missing[non_missing > 0]

  target <- if (length(positive)) positive else non_missing
  if (!length(target)) {
    return(tibble::tibble(
      summary_name = summary_name,
      scope = "non_zero_if_available",
      n = 0L,
      mean = NA_real_,
      p50 = NA_real_,
      p95 = NA_real_,
      p99 = NA_real_,
      max = NA_real_
    ))
  }

  tibble::tibble(
    summary_name = summary_name,
    scope = "non_zero_if_available",
    n = length(target),
    mean = mean(target, na.rm = TRUE),
    p50 = stats::median(target, na.rm = TRUE),
    p95 = as.numeric(stats::quantile(target, 0.95, na.rm = TRUE)),
    p99 = as.numeric(stats::quantile(target, 0.99, na.rm = TRUE)),
    max = max(target, na.rm = TRUE)
  )
}

rs_m10_build_score_summary <- function(edge_history_df, density_cap) {
  dplyr::bind_rows(
    rs_m10_metric_summary(edge_history_df$accident_count_raw, "accident_count_raw"),
    rs_m10_metric_summary(edge_history_df$accident_count_weighted_by_quality, "accident_count_weighted_by_quality"),
    rs_m10_metric_summary(edge_history_df$accidents_per_km_raw, "accidents_per_km_raw"),
    rs_m10_metric_summary(edge_history_df$accidents_per_km, "accidents_per_km"),
    rs_m10_metric_summary(edge_history_df$historical_score_prelim, "historical_score_prelim")
  ) |>
    dplyr::mutate(
      mean = round(mean, 3),
      p50 = round(p50, 3),
      p95 = round(p95, 3),
      p99 = round(p99, 3),
      max = round(max, 3),
      density_cap_p95_used = round(density_cap, 3),
      output_schema_version = rs_m10_output_schema_version
    )
}

rs_m10_get_metric <- function(validation_summary, metric_name) {
  value <- validation_summary |>
    dplyr::filter(metric == metric_name) |>
    dplyr::pull(value)

  if (!length(value)) {
    return(NA_character_)
  }

  value[[1]]
}

rs_m10_build_coverage_summary <- function(edge_history_df, unmatched_df, m9_validation_summary, matches_used_n) {
  total_edges_n <- nrow(edge_history_df)
  edges_with_accidents_n <- sum(edge_history_df$accident_count_raw > 0L)
  total_accidents_n <- as.numeric(rs_m10_get_metric(m9_validation_summary, "accidents_total_n"))
  outside_operational_envelope_n <- as.numeric(rs_m10_get_metric(m9_validation_summary, "accidents_outside_operational_envelope_n"))

  tibble::tibble(
    metric = c(
      "network_edges_n",
      "edges_with_at_least_one_accident_n",
      "edges_with_at_least_one_accident_pct",
      "edges_without_accident_n",
      "matched_accidents_used_n",
      "matched_accidents_used_pct_over_total_accidents",
      "excluded_unmatched_n",
      "excluded_unmatched_pct_over_total_accidents",
      "outside_operational_envelope_n",
      "outside_operational_envelope_pct_over_total_accidents",
      "accident_count_raw_p50_nonzero",
      "accident_count_raw_p95_nonzero",
      "accidents_per_km_p50_nonzero",
      "accidents_per_km_p95_nonzero"
    ),
    value = c(
      as.character(total_edges_n),
      as.character(edges_with_accidents_n),
      sprintf("%.2f", 100 * edges_with_accidents_n / total_edges_n),
      as.character(total_edges_n - edges_with_accidents_n),
      as.character(matches_used_n),
      sprintf("%.2f", 100 * matches_used_n / total_accidents_n),
      as.character(nrow(unmatched_df)),
      sprintf("%.2f", 100 * nrow(unmatched_df) / total_accidents_n),
      as.character(outside_operational_envelope_n),
      sprintf("%.2f", 100 * outside_operational_envelope_n / total_accidents_n),
      sprintf("%.3f", stats::median(edge_history_df$accident_count_raw[edge_history_df$accident_count_raw > 0], na.rm = TRUE)),
      sprintf("%.3f", as.numeric(stats::quantile(edge_history_df$accident_count_raw[edge_history_df$accident_count_raw > 0], 0.95, na.rm = TRUE))),
      sprintf("%.3f", stats::median(edge_history_df$accidents_per_km[edge_history_df$accidents_per_km > 0], na.rm = TRUE)),
      sprintf("%.3f", as.numeric(stats::quantile(edge_history_df$accidents_per_km[edge_history_df$accidents_per_km > 0], 0.95, na.rm = TRUE)))
    )
  )
}

rs_m10_rank_edges <- function(edge_history_df, ranking_variable, ranking_name, top_n = rs_m10_top_n) {
  ranked <- edge_history_df |>
    dplyr::filter(.data[[ranking_variable]] > 0) |>
    dplyr::arrange(dplyr::desc(.data[[ranking_variable]]), dplyr::desc(accident_count_weighted_by_quality), edge_id) |>
    dplyr::slice_head(n = top_n) |>
    dplyr::mutate(
      ranking_type = ranking_name,
      rank = dplyr::row_number()
    ) |>
    dplyr::select(
      ranking_type,
      rank,
      edge_id,
      edge_length_m,
      accident_count_raw,
      accident_count_high_confidence,
      accident_count_medium_confidence,
      accident_count_low_confidence,
      accident_count_weighted_by_quality,
      accidents_per_km,
      historical_score_prelim,
      first_accident_date,
      last_accident_date,
      active_years_n,
      notes_or_flags
    )

  ranked
}

rs_m10_build_top_risk_edges <- function(edge_history_df) {
  dplyr::bind_rows(
    rs_m10_rank_edges(edge_history_df, "accident_count_raw", "top_accident_count_raw"),
    rs_m10_rank_edges(edge_history_df, "accident_count_weighted_by_quality", "top_weighted_historical_count"),
    rs_m10_rank_edges(edge_history_df, "historical_score_prelim", "top_historical_score_prelim")
  )
}

rs_m10_build_validation_summary <- function(edge_history_df, matches_df, unmatched_df, edges_sf, density_cap) {
  aggregated_edge_ids <- edge_history_df$edge_id[edge_history_df$accident_count_raw > 0L]

  tibble::tibble(
    metric = c(
      "network_edges_n",
      "edges_with_accidents_n",
      "aggregated_edge_ids_exist_in_network",
      "duplicated_edge_id_in_output",
      "matched_used_n",
      "accident_count_raw_sum",
      "accident_count_raw_sum_matches_used",
      "accident_count_weighted_by_quality_sum",
      "unmatched_excluded_n",
      "edge_length_positive_all",
      "accidents_per_km_nonnegative",
      "historical_score_prelim_nonnegative",
      "historical_score_prelim_max",
      "historical_score_prelim_is_final_routing_weight",
      "quality_weighting_rule_documented",
      "historical_score_cap_p95_density",
      "output_schema_version"
    ),
    value = c(
      as.character(nrow(edge_history_df)),
      as.character(sum(edge_history_df$accident_count_raw > 0L)),
      as.character(all(aggregated_edge_ids %in% edges_sf$edge_id)),
      as.character(anyDuplicated(edge_history_df$edge_id) > 0L),
      as.character(nrow(matches_df)),
      as.character(sum(edge_history_df$accident_count_raw)),
      as.character(sum(edge_history_df$accident_count_raw) == nrow(matches_df)),
      sprintf("%.3f", sum(edge_history_df$accident_count_weighted_by_quality)),
      as.character(nrow(unmatched_df)),
      as.character(all(edge_history_df$edge_length_m > 0)),
      as.character(all(edge_history_df$accidents_per_km >= 0, na.rm = TRUE)),
      as.character(all(edge_history_df$historical_score_prelim >= 0, na.rm = TRUE)),
      sprintf("%.3f", max(edge_history_df$historical_score_prelim, na.rm = TRUE)),
      "FALSE",
      "TRUE",
      sprintf("%.3f", density_cap),
      rs_m10_output_schema_version
    )
  )
}

rs_m10_build_note <- function(coverage_summary, validation_summary, density_cap) {
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
    "# M10 - Agregacion historica preliminar por edge",
    "",
    "## Logica de M10",
    "- M10 agrega solo accidentes `matched` de M9 sobre la red canonica de M8.",
    "- Se mantienen separados tres niveles de informacion:",
    "  - `accident_count_raw`: conteo historico sin ponderar de accidentes asignados al edge.",
    "  - `accident_count_weighted_by_quality`: conteo historico ponderado por calidad de matching.",
    "  - `historical_score_prelim`: transformacion monotona de la densidad historica ponderada, util para ranking preliminar pero no para routing final.",
    "",
    "## Regla de ponderacion por quality_flag",
    "- `high_confidence = 1.00`",
    "- `medium_confidence = 0.75`",
    "- `low_confidence = 0.40`",
    "- `unmatched = 0.00`",
    "- Justificacion: M9 mostro que gran parte de los `low_confidence` tienen distancias cortas pero alta ambiguedad local; se conservan como senal historica plausible, pero no con peso completo edge-especifico.",
    "",
    "## Definiciones operativas",
    "- `accidents_per_km = accident_count_weighted_by_quality / (edge_length_m / 1000)`.",
    sprintf("- `historical_score_prelim` reescala `accidents_per_km` a `0-100`, capando la densidad en el p95 no nulo (`%s`) para que tramos muy cortos o extremos no dominen el ranking preliminar.", sprintf('%.3f', density_cap)),
    "",
    "## Cobertura observada",
    sprintf("- Edges con al menos un accidente: %s (%s%% de la red canonica)", get_metric(coverage_summary, "edges_with_at_least_one_accident_n"), get_metric(coverage_summary, "edges_with_at_least_one_accident_pct")),
    sprintf("- Accidentes matched usados en la agregacion historica: %s (%s%% sobre el total)", get_metric(coverage_summary, "matched_accidents_used_n"), get_metric(coverage_summary, "matched_accidents_used_pct_over_total_accidents")),
    sprintf("- Accidentes excluidos por unmatched: %s (%s%% sobre el total)", get_metric(coverage_summary, "excluded_unmatched_n"), get_metric(coverage_summary, "excluded_unmatched_pct_over_total_accidents")),
    sprintf("- Accidentes fuera del envelope operativo: %s (%s%% sobre el total)", get_metric(coverage_summary, "outside_operational_envelope_n"), get_metric(coverage_summary, "outside_operational_envelope_pct_over_total_accidents")),
    "",
    "## Limitaciones abiertas",
    "- Todavia no hay ajuste serio por exposicion real.",
    "- Todavia no hay suavizado espacial entre aristas vecinas.",
    "- Todavia no hay severidad incorporada.",
    "- Todavia no hay combinacion final con el bloque contextual/dinamico.",
    "- `historical_score_prelim` no es todavia peso final de routing.",
    "",
    "## Que deja listo M10",
    "- Una capa historica por edge auditable y reusable.",
    "- Conteos raw y ponderados separados.",
    "- Un score preliminar interpretable para la siguiente fase de combinacion, no para routing directo.",
    sprintf("- Schema de salida: `%s`.", rs_m10_output_schema_version),
    "",
    sep = "\n"
  )
}

rs_m10_write_outputs <- function(edge_history_df, edges_sf, score_summary, coverage_summary, weighting_rule, top_edges, historical_note, validation_summary, output_paths) {
  edge_history_sf <- edges_sf |>
    dplyr::left_join(edge_history_df, by = "edge_id")

  edge_history_csv <- edge_history_sf |>
    sf::st_drop_geometry()

  readr::write_csv(edge_history_csv, output_paths$aggregation_csv)
  readr::write_csv(score_summary, output_paths$score_summary_csv)
  readr::write_csv(coverage_summary, output_paths$coverage_summary_csv)
  readr::write_csv(weighting_rule, output_paths$weighting_rule_csv)
  readr::write_csv(top_edges, output_paths$top_edges_csv)
  readr::write_csv(validation_summary, output_paths$validation_csv)
  writeLines(historical_note, output_paths$note_md, useBytes = TRUE)

  if (file.exists(output_paths$aggregation_geojson)) {
    file.remove(output_paths$aggregation_geojson)
  }

  sf::st_write(
    sf::st_transform(edge_history_sf, rs_m8_source_crs_epsg),
    output_paths$aggregation_geojson,
    driver = "GeoJSON",
    quiet = TRUE
  )
}

rs_run_m10_edge_historical_aggregation <- function(m8_result, paths, m9_result = NULL, force_refresh = FALSE) {
  rs_check_m10_packages()
  rs_validate_m10_inputs(m8_result, paths)

  output_paths <- rs_m10_output_paths(paths)
  if (!force_refresh && rs_m10_cache_is_current(output_paths)) {
    return(rs_m10_read_cached_outputs(output_paths))
  }

  m9_inputs <- rs_m10_load_m9_inputs(m9_result = m9_result, paths = paths)
  matches_prepared <- rs_m10_prepare_matches(m9_inputs$matches)
  edges_sf <- rs_m10_load_edges(m8_result)

  edge_history <- rs_m10_build_edge_level_aggregation(
    matches_prepared = matches_prepared,
    edges_sf = edges_sf
  )

  density_result <- rs_m10_add_density_and_score(edge_history)
  edge_history <- density_result$edge_history
  density_cap <- density_result$density_cap

  score_summary <- rs_m10_build_score_summary(edge_history, density_cap)
  coverage_summary <- rs_m10_build_coverage_summary(
    edge_history_df = edge_history,
    unmatched_df = m9_inputs$unmatched,
    m9_validation_summary = m9_inputs$validation_summary,
    matches_used_n = nrow(matches_prepared)
  )
  weighting_rule <- rs_m10_quality_weighting_rule()
  top_edges <- rs_m10_build_top_risk_edges(edge_history)
  validation_summary <- rs_m10_build_validation_summary(
    edge_history_df = edge_history,
    matches_df = matches_prepared,
    unmatched_df = m9_inputs$unmatched,
    edges_sf = edges_sf,
    density_cap = density_cap
  )
  historical_note <- rs_m10_build_note(
    coverage_summary = coverage_summary,
    validation_summary = validation_summary,
    density_cap = density_cap
  )

  rs_m10_write_outputs(
    edge_history_df = edge_history,
    edges_sf = edges_sf,
    score_summary = score_summary,
    coverage_summary = coverage_summary,
    weighting_rule = weighting_rule,
    top_edges = top_edges,
    historical_note = historical_note,
    validation_summary = validation_summary,
    output_paths = output_paths
  )

  list(
    aggregation = edge_history,
    score_summary = score_summary,
    coverage_summary = coverage_summary,
    weighting_rule = weighting_rule,
    top_risk_edges = top_edges,
    validation_summary = validation_summary,
    historical_note = historical_note,
    used_cache = FALSE
  )
}
