rs_m12_output_schema_version <- "m12_schema_v1_edge_temporal_bin_4h_weekend_dynamic_context_baseline"
rs_m12_observation_unit <- "edge_id + temporal_bin_4h + is_weekend"
rs_m12_temporal_bin_hours <- 4L
rs_m12_signal_cap_quantile <- 0.95

rs_check_m12_packages <- function() {
  required_packages <- c("dplyr", "tibble", "readr")
  missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]

  if (length(missing_packages) > 0L) {
    stop(
      sprintf(
        "Faltan paquetes requeridos para M12: %s",
        paste(missing_packages, collapse = ", ")
      ),
      call. = FALSE
    )
  }
}

rs_validate_m12_inputs <- function(m8_result, paths) {
  if (missing(m8_result) || is.null(m8_result)) {
    stop("M12 necesita la referencia de M8 para la red canonica.", call. = FALSE)
  }

  required_paths <- c("output_data", "output_tables")
  if (!all(required_paths %in% names(paths))) {
    stop("M12 necesita output_data y output_tables dentro de paths.", call. = FALSE)
  }

  network_edges_path <- file.path(paths$output_data, "m8_road_network_edges.csv")
  if (!file.exists(network_edges_path)) {
    stop("M12 necesita `m8_road_network_edges.csv`.", call. = FALSE)
  }
}

rs_m12_output_paths <- function(paths) {
  list(
    dynamic_base_csv = file.path(paths$output_data, "m12_edge_context_dynamic_base.csv"),
    dynamic_summary_csv = file.path(paths$output_tables, "m12_dynamic_context_summary.csv"),
    variable_registry_csv = file.path(paths$output_tables, "m12_context_variable_registry.csv"),
    dynamic_note_md = file.path(paths$output_tables, "m12_dynamic_signal_note.md"),
    validation_summary_csv = file.path(paths$output_tables, "m12_validation_summary.csv")
  )
}

rs_m12_artifacts_ready <- function(output_paths) {
  all(file.exists(unlist(output_paths, use.names = FALSE)))
}

rs_m12_cache_is_current <- function(output_paths) {
  if (!rs_m12_artifacts_ready(output_paths)) {
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

  observation_unit <- validation |>
    dplyr::filter(metric == "observation_unit") |>
    dplyr::pull(value)

  length(schema_value) == 1L &&
    identical(schema_value[[1]], rs_m12_output_schema_version) &&
    length(observation_unit) == 1L &&
    identical(observation_unit[[1]], rs_m12_observation_unit)
}

rs_m12_read_cached_outputs <- function(output_paths) {
  list(
    dynamic_base = readr::read_csv(output_paths$dynamic_base_csv, show_col_types = FALSE),
    dynamic_context_summary = readr::read_csv(output_paths$dynamic_summary_csv, show_col_types = FALSE),
    variable_registry = readr::read_csv(output_paths$variable_registry_csv, show_col_types = FALSE),
    validation_summary = readr::read_csv(output_paths$validation_summary_csv, show_col_types = FALSE),
    dynamic_signal_note = paste(readLines(output_paths$dynamic_note_md, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
    used_cache = TRUE
  )
}

rs_m12_load_network_edges <- function(paths) {
  edges_path <- file.path(paths$output_data, "m8_road_network_edges.csv")
  edges_df <- readr::read_csv(edges_path, show_col_types = FALSE)

  required_columns <- c("edge_id", "edge_length_m")
  missing_columns <- setdiff(required_columns, names(edges_df))
  if (length(missing_columns) > 0L) {
    stop(
      sprintf(
        "Faltan columnas requeridas en `m8_road_network_edges.csv` para M12: %s",
        paste(missing_columns, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  edges_df |>
    dplyr::select(edge_id, edge_length_m)
}

rs_m12_load_m9_matches <- function(m9_result, paths) {
  if (!missing(m9_result) && !is.null(m9_result) && "matches" %in% names(m9_result)) {
    return(m9_result$matches)
  }

  matches_path <- file.path(paths$output_data, "m9_accident_edge_matches.csv")
  if (!file.exists(matches_path)) {
    stop("M12 necesita `m9_accident_edge_matches.csv`.", call. = FALSE)
  }

  readr::read_csv(matches_path, show_col_types = FALSE)
}

rs_m12_load_accident_master <- function(accident_master, paths) {
  if (!missing(accident_master) && !is.null(accident_master) && nrow(accident_master)) {
    return(accident_master)
  }

  master_path <- file.path(paths$output_data, "accidentes_tabla_accidente_master.csv")
  if (!file.exists(master_path)) {
    stop("M12 necesita `accidentes_tabla_accidente_master.csv`.", call. = FALSE)
  }

  readr::read_csv(master_path, show_col_types = FALSE)
}

rs_m12_load_historical_adjusted <- function(m11_result, paths) {
  if (!missing(m11_result) && !is.null(m11_result) && "historical_exposure_adjusted" %in% names(m11_result)) {
    return(m11_result$historical_exposure_adjusted)
  }

  historical_path <- file.path(paths$output_data, "m11_historical_exposure_adjusted.csv")
  if (!file.exists(historical_path)) {
    stop("M12 necesita `m11_historical_exposure_adjusted.csv`.", call. = FALSE)
  }

  readr::read_csv(historical_path, show_col_types = FALSE)
}

rs_m12_percent_rank_nonmissing <- function(x) {
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

rs_m12_parse_hour_decimal <- function(x) {
  values <- trimws(as.character(x))
  result <- rep(NA_real_, length(values))

  for (i in seq_along(values)) {
    value <- values[[i]]
    if (is.na(value) || !nzchar(value)) {
      next
    }

    parts <- strsplit(value, ":", fixed = TRUE)[[1]]
    if (length(parts) < 2L) {
      next
    }

    parts_num <- suppressWarnings(as.numeric(parts))
    if (any(is.na(parts_num[1:2]))) {
      next
    }

    hour <- parts_num[[1]]
    minute <- parts_num[[2]]
    second <- if (length(parts_num) >= 3L && !is.na(parts_num[[3]])) parts_num[[3]] else 0

    if (hour < 0 || hour > 23 || minute < 0 || minute >= 60 || second < 0 || second >= 60) {
      next
    }

    result[[i]] <- hour + (minute / 60) + (second / 3600)
  }

  result
}

rs_m12_prepare_context_observations <- function(matches_df, accident_master) {
  required_match_columns <- c("num_expediente", "edge_id", "fecha", "hora", "quality_flag")
  missing_match_columns <- setdiff(required_match_columns, names(matches_df))
  if (length(missing_match_columns) > 0L) {
    stop(
      sprintf(
        "Faltan columnas requeridas en los matches de M9 para M12: %s",
        paste(missing_match_columns, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  if ("match_status" %in% names(matches_df)) {
    matches_df <- matches_df |>
      dplyr::filter(match_status == "matched")
  }

  required_master_columns <- c(
    "num_expediente",
    "id_sensor_cercano",
    "intensidad",
    "ocupacion",
    "vmed",
    "es_festivo",
    "estado_meteorologico"
  )
  missing_master_columns <- setdiff(required_master_columns, names(accident_master))
  if (length(missing_master_columns) > 0L) {
    stop(
      sprintf(
        "Faltan columnas requeridas en accident_master para M12: %s",
        paste(missing_master_columns, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  context_obs <- matches_df |>
    dplyr::select(num_expediente, edge_id, fecha, hora, quality_flag) |>
    dplyr::left_join(
      accident_master |>
        dplyr::select(
          num_expediente,
          id_sensor_cercano,
          intensidad,
          ocupacion,
          vmed,
          es_festivo,
          estado_meteorologico
        ),
      by = "num_expediente"
    ) |>
    dplyr::mutate(
      fecha = as.Date(fecha),
      hour_decimal = rs_m12_parse_hour_decimal(hora),
      temporal_bin_start_hour = dplyr::if_else(
        !is.na(hour_decimal),
        as.integer(floor(hour_decimal / rs_m12_temporal_bin_hours) * rs_m12_temporal_bin_hours),
        NA_integer_
      ),
      temporal_bin_end_hour = dplyr::if_else(
        !is.na(temporal_bin_start_hour),
        temporal_bin_start_hour + (rs_m12_temporal_bin_hours - 1L),
        NA_integer_
      ),
      temporal_bin_center_hour = dplyr::if_else(
        !is.na(temporal_bin_start_hour),
        temporal_bin_start_hour + ((rs_m12_temporal_bin_hours - 1) / 2),
        NA_real_
      ),
      temporal_bin_4h = dplyr::if_else(
        !is.na(temporal_bin_start_hour),
        sprintf("%02d_%02d", temporal_bin_start_hour, temporal_bin_end_hour),
        NA_character_
      ),
      hour_sin = dplyr::if_else(
        !is.na(temporal_bin_center_hour),
        sin(2 * pi * temporal_bin_center_hour / 24),
        NA_real_
      ),
      hour_cos = dplyr::if_else(
        !is.na(temporal_bin_center_hour),
        cos(2 * pi * temporal_bin_center_hour / 24),
        NA_real_
      ),
      weekday_index = as.POSIXlt(fecha)$wday,
      is_weekend = weekday_index %in% c(0, 6),
      has_any_numeric_context = !is.na(intensidad) | !is.na(ocupacion)
    ) |>
    dplyr::select(-weekday_index)

  prep_summary <- tibble::tibble(
    metric = c(
      "matched_accidents_available_n",
      "matched_accidents_with_parsed_hour_n",
      "matched_accidents_with_any_numeric_context_n",
      "matched_accidents_with_both_numeric_context_n",
      "matched_accidents_with_vmed_observed_n",
      "matched_accidents_with_meteorology_observed_n"
    ),
    value = c(
      as.character(nrow(context_obs)),
      as.character(sum(!is.na(context_obs$temporal_bin_4h))),
      as.character(sum(context_obs$has_any_numeric_context, na.rm = TRUE)),
      as.character(sum(!is.na(context_obs$intensidad) & !is.na(context_obs$ocupacion))),
      as.character(sum(!is.na(context_obs$vmed))),
      as.character(sum(!is.na(context_obs$estado_meteorologico)))
    )
  )

  list(
    context_observations = context_obs,
    prep_summary = prep_summary
  )
}

rs_m12_build_dynamic_base <- function(context_observations, historical_adjusted, network_edges) {
  context_base <- context_observations |>
    dplyr::filter(!is.na(temporal_bin_4h)) |>
    dplyr::group_by(
      edge_id,
      temporal_bin_4h,
      temporal_bin_start_hour,
      temporal_bin_end_hour,
      temporal_bin_center_hour,
      is_weekend
    ) |>
    dplyr::summarise(
      context_observation_n = dplyr::n(),
      context_accident_date_n = dplyr::n_distinct(fecha),
      linked_sensor_n = dplyr::n_distinct(id_sensor_cercano[!is.na(id_sensor_cercano)]),
      high_confidence_obs_n = sum(quality_flag == "high_confidence", na.rm = TRUE),
      medium_confidence_obs_n = sum(quality_flag == "medium_confidence", na.rm = TRUE),
      low_confidence_obs_n = sum(quality_flag == "low_confidence", na.rm = TRUE),
      intensidad_obs_n = sum(!is.na(intensidad)),
      ocupacion_obs_n = sum(!is.na(ocupacion)),
      vmed_obs_n = sum(!is.na(vmed)),
      meteorology_obs_n = sum(!is.na(estado_meteorologico)),
      first_context_date = min(fecha, na.rm = TRUE),
      last_context_date = max(fecha, na.rm = TRUE),
      intensidad_context = if (sum(!is.na(intensidad)) > 0) stats::median(intensidad, na.rm = TRUE) else NA_real_,
      ocupacion_context = if (sum(!is.na(ocupacion)) > 0) stats::median(ocupacion, na.rm = TRUE) else NA_real_,
      hour_sin = dplyr::first(hour_sin),
      hour_cos = dplyr::first(hour_cos),
      .groups = "drop"
    ) |>
    dplyr::left_join(
      network_edges |>
        dplyr::select(edge_id, edge_length_m),
      by = "edge_id"
    ) |>
    dplyr::left_join(
      historical_adjusted |>
        dplyr::select(
          edge_id,
          historical_count_raw,
          historical_count_weighted,
          exposure_proxy_value,
          exposure_quality_flag,
          historical_exposure_adjusted_score_prelim
        ),
      by = "edge_id"
    ) |>
    dplyr::mutate(
      intensidad_context_rank01 = rs_m12_percent_rank_nonmissing(intensidad_context),
      ocupacion_context_rank01 = rs_m12_percent_rank_nonmissing(ocupacion_context),
      dynamic_context_signal_prelim = dplyr::case_when(
        is.na(intensidad_context_rank01) & is.na(ocupacion_context_rank01) ~ NA_real_,
        TRUE ~ 100 * rowMeans(
          cbind(intensidad_context_rank01, ocupacion_context_rank01),
          na.rm = TRUE
        )
      ),
      context_data_quality_flag = dplyr::case_when(
        intensidad_obs_n >= 3L & ocupacion_obs_n >= 3L & (high_confidence_obs_n + medium_confidence_obs_n) >= 1L ~ "high_support",
        intensidad_obs_n >= 1L & ocupacion_obs_n >= 1L & context_observation_n >= 2L ~ "medium_support",
        intensidad_obs_n >= 1L | ocupacion_obs_n >= 1L ~ "low_support",
        TRUE ~ "no_numeric_context"
      ),
      future_combined_edge_risk = NA_real_
    )

  note_flags <- character(nrow(context_base))
  note_flags[] <- ""

  append_flag <- function(existing, mask, flag_name) {
    mask <- !is.na(mask) & mask
    existing[mask] <- ifelse(existing[mask] == "", flag_name, paste(existing[mask], flag_name, sep = " | "))
    existing
  }

  note_flags <- append_flag(note_flags, context_base$linked_sensor_n > 1L, "multi_sensor_context_bin")
  note_flags <- append_flag(note_flags, context_base$context_observation_n == 1L, "single_observation_bin")
  note_flags <- append_flag(note_flags, context_base$intensidad_obs_n > 0L & context_base$ocupacion_obs_n == 0L, "only_intensidad_available")
  note_flags <- append_flag(note_flags, context_base$ocupacion_obs_n > 0L & context_base$intensidad_obs_n == 0L, "only_ocupacion_available")
  note_flags <- append_flag(note_flags, context_base$intensidad_obs_n == 0L & context_base$ocupacion_obs_n == 0L, "no_numeric_context")
  note_flags <- append_flag(note_flags, context_base$high_confidence_obs_n == 0L & context_base$medium_confidence_obs_n == 0L, "only_low_confidence_matches_in_bin")
  note_flags <- append_flag(note_flags, context_base$vmed_obs_n > 0L, "vmed_observed_but_not_used")
  note_flags <- append_flag(note_flags, context_base$meteorology_obs_n > 0L, "meteorology_observed_but_not_operationally_integrated")
  note_flags <- append_flag(note_flags, is.na(context_base$historical_exposure_adjusted_score_prelim), "historical_exposure_adjusted_score_missing_for_edge")
  note_flags <- append_flag(note_flags, TRUE, "future_combined_edge_risk_not_calculated")
  note_flags <- append_flag(note_flags, TRUE, "not_final_routing_weight")

  context_base |>
    dplyr::mutate(
      intensidad_context = round(intensidad_context, 3),
      ocupacion_context = round(ocupacion_context, 3),
      hour_sin = round(hour_sin, 4),
      hour_cos = round(hour_cos, 4),
      intensidad_context_rank01 = round(intensidad_context_rank01, 4),
      ocupacion_context_rank01 = round(ocupacion_context_rank01, 4),
      dynamic_context_signal_prelim = round(dynamic_context_signal_prelim, 3),
      historical_exposure_adjusted_score_prelim = round(historical_exposure_adjusted_score_prelim, 3),
      exposure_proxy_value = round(exposure_proxy_value, 4),
      notes_or_limitations = dplyr::na_if(note_flags, "")
    ) |>
    dplyr::arrange(edge_id, temporal_bin_start_hour, is_weekend)
}

rs_m12_build_variable_registry <- function() {
  tibble::tribble(
    ~variable, ~layer, ~status, ~used_in_dynamic_base, ~used_in_dynamic_signal_prelim, ~rationale,
    "intensidad", "dynamic_context", "usable_now", TRUE, TRUE, "Variable contextual priorizada desde M4-M5 y util para describir carga de trafico del edge/bin.",
    "ocupacion", "dynamic_context", "usable_now", TRUE, TRUE, "Variable contextual priorizada desde M4-M5 y util para complementar intensidad sin introducir IDs artificiales.",
    "hour_sin", "dynamic_context", "descriptor_ready", TRUE, FALSE, "Se conserva como descriptor temporal ciclico ya usable, pero no se convierte todavia en senal numerica de riesgo por si solo.",
    "hour_cos", "dynamic_context", "descriptor_ready", TRUE, FALSE, "Se conserva como descriptor temporal ciclico ya usable, pero no se convierte todavia en senal numerica de riesgo por si solo.",
    "is_weekend", "dynamic_context", "descriptor_ready", TRUE, FALSE, "Se mantiene como modulador descriptivo y bin de contexto, no como motor principal del signal preliminar.",
    "vmed", "dynamic_context", "under_review", FALSE, FALSE, "Se observa de forma diagnostica, pero queda fuera de la base dinamica usable y del signal preliminar por su ruido ya detectado en fases previas.",
    "es_festivo", "dynamic_context", "excluded_from_baseline_signal", FALSE, FALSE, "No entra en el baseline dinamico porque es binaria muy desbalanceada; puede reentrar despues como modulador contextual.",
    "estado_meteorologico", "dynamic_context", "excluded_pending_operational_integration", FALSE, FALSE, "No se usa todavia porque falta una integracion operativa y comparable a nivel edge/observacion.",
    "historical_exposure_adjusted_score_prelim", "historical_reference", "preserved_separately", TRUE, FALSE, "Se arrastra como referencia historica ya ajustada por exposicion, pero no se pisa ni se mezcla en una unica columna.",
    "future_combined_edge_risk", "future_placeholder", "placeholder_only", TRUE, FALSE, "Placeholder conceptual para fases posteriores; M12 no calcula todavia la combinacion final."
  )
}

rs_m12_build_dynamic_context_summary <- function(dynamic_base, prep_summary, network_edges, matches_df) {
  matched_edge_n <- dplyr::n_distinct(matches_df$edge_id)
  signal_values <- dynamic_base$dynamic_context_signal_prelim[!is.na(dynamic_base$dynamic_context_signal_prelim)]

  tibble::tibble(
    metric = c(
      "network_edges_n",
      "matched_accidents_available_n",
      "matched_accidents_with_parsed_hour_n",
      "matched_accidents_with_any_numeric_context_n",
      "dynamic_base_rows_n",
      "dynamic_base_unique_edges_n",
      "dynamic_base_unique_edges_pct_over_network",
      "dynamic_base_unique_edges_pct_over_matched_edges",
      "dynamic_base_unique_contextual_bins_n",
      "dynamic_rows_with_dynamic_signal_n",
      "dynamic_rows_without_numeric_context_n",
      "context_quality_high_n",
      "context_quality_medium_n",
      "context_quality_low_n",
      "context_quality_no_numeric_n",
      "rows_with_historical_score_available_n",
      "rows_with_historical_score_missing_n",
      "dynamic_signal_p50_nonmissing",
      "dynamic_signal_p95_nonmissing",
      "future_combined_edge_risk_calculated"
    ),
    value = c(
      as.character(nrow(network_edges)),
      prep_summary$value[prep_summary$metric == "matched_accidents_available_n"],
      prep_summary$value[prep_summary$metric == "matched_accidents_with_parsed_hour_n"],
      prep_summary$value[prep_summary$metric == "matched_accidents_with_any_numeric_context_n"],
      as.character(nrow(dynamic_base)),
      as.character(dplyr::n_distinct(dynamic_base$edge_id)),
      sprintf("%.2f", 100 * dplyr::n_distinct(dynamic_base$edge_id) / nrow(network_edges)),
      sprintf("%.2f", 100 * dplyr::n_distinct(dynamic_base$edge_id) / matched_edge_n),
      as.character(dplyr::n_distinct(paste(dynamic_base$temporal_bin_4h, dynamic_base$is_weekend, sep = "::"))),
      as.character(sum(!is.na(dynamic_base$dynamic_context_signal_prelim))),
      as.character(sum(dynamic_base$context_data_quality_flag == "no_numeric_context", na.rm = TRUE)),
      as.character(sum(dynamic_base$context_data_quality_flag == "high_support", na.rm = TRUE)),
      as.character(sum(dynamic_base$context_data_quality_flag == "medium_support", na.rm = TRUE)),
      as.character(sum(dynamic_base$context_data_quality_flag == "low_support", na.rm = TRUE)),
      as.character(sum(dynamic_base$context_data_quality_flag == "no_numeric_context", na.rm = TRUE)),
      as.character(sum(!is.na(dynamic_base$historical_exposure_adjusted_score_prelim))),
      as.character(sum(is.na(dynamic_base$historical_exposure_adjusted_score_prelim))),
      if (length(signal_values)) sprintf("%.3f", stats::median(signal_values, na.rm = TRUE)) else NA_character_,
      if (length(signal_values)) sprintf("%.3f", as.numeric(stats::quantile(signal_values, 0.95, na.rm = TRUE))) else NA_character_,
      "FALSE"
    )
  )
}

rs_m12_build_validation_summary <- function(dynamic_base, variable_registry, network_edges, historical_adjusted) {
  dynamic_keys <- paste(dynamic_base$edge_id, dynamic_base$temporal_bin_4h, dynamic_base$is_weekend, sep = "::")

  tibble::tibble(
    metric = c(
      "observation_unit",
      "edge_ids_in_dynamic_base_exist_in_network",
      "edge_ids_in_dynamic_base_exist_in_historical_layer",
      "duplicated_edge_bin_key_in_dynamic_base",
      "historical_layer_preserved_separately",
      "historical_exposure_adjusted_score_prelim_column_present",
      "context_variables_traced",
      "usable_variables_explicit",
      "excluded_variables_explicit",
      "dynamic_context_signal_prelim_present",
      "dynamic_context_signal_prelim_uses_only_intensidad_ocupacion_block",
      "dynamic_context_signal_prelim_is_final_routing_weight",
      "future_combined_edge_risk_calculated",
      "future_combined_edge_risk_placeholder_present",
      "output_schema_version"
    ),
    value = c(
      rs_m12_observation_unit,
      as.character(all(dynamic_base$edge_id %in% network_edges$edge_id)),
      as.character(all(dynamic_base$edge_id %in% historical_adjusted$edge_id)),
      as.character(anyDuplicated(dynamic_keys) > 0L),
      "TRUE",
      as.character("historical_exposure_adjusted_score_prelim" %in% names(dynamic_base)),
      as.character(all(c("intensidad", "ocupacion", "hour_sin", "hour_cos", "is_weekend") %in% variable_registry$variable)),
      as.character(all(c("intensidad", "ocupacion", "hour_sin", "hour_cos", "is_weekend") %in% variable_registry$variable[variable_registry$used_in_dynamic_base])),
      as.character(all(c("vmed", "es_festivo", "estado_meteorologico") %in% variable_registry$variable)),
      as.character("dynamic_context_signal_prelim" %in% names(dynamic_base)),
      "TRUE",
      "FALSE",
      "FALSE",
      as.character("future_combined_edge_risk" %in% names(dynamic_base)),
      rs_m12_output_schema_version
    )
  )
}

rs_m12_build_dynamic_signal_note <- function(dynamic_context_summary) {
  get_metric <- function(metric_name) {
    value <- dynamic_context_summary |>
      dplyr::filter(metric == metric_name) |>
      dplyr::pull(value)
    if (!length(value)) {
      return(NA_character_)
    }
    value[[1]]
  }

  paste(
    "# M12 - Capa dinamica/contextual preliminar por edge",
    "",
    "## Unidad observacional",
    sprintf("- M12 fija explicitamente la unidad `%s`.", rs_m12_observation_unit),
    "- La eleccion de bins de 4 horas evita una malla horaria demasiado dispersa con el soporte accident-backed actual y deja una base reutilizable para observaciones futuras.",
    "",
    "## Que entra ya de forma usable",
    "- `intensidad` y `ocupacion` entran como bloque contextual principal y son la unica base del `dynamic_context_signal_prelim`.",
    "- `hour_sin`, `hour_cos` e `is_weekend` se conservan como descriptores ya utilizables, pero todavia no se convierten por si solos en una senal numerica de riesgo.",
    "",
    "## Que queda fuera por ahora",
    "- `vmed` queda bajo revision y no entra en el signal preliminar.",
    "- `es_festivo` no entra en el baseline dinamico porque es una binaria muy desbalanceada para estructurar esta primera capa; puede seguir siendo modulador futuro.",
    "- `estado_meteorologico` queda fuera hasta que exista integracion operativa comparable por edge/observacion.",
    "",
    "## Logica del signal preliminar",
    "- M12 no fuerza un modelo contextual serio que todavia no existe.",
    "- El `dynamic_context_signal_prelim` se construye como promedio de ranks robustos `0-1` de `intensidad_context` y `ocupacion_context`, reescalado a `0-100`.",
    "- Esta regla refleja la evidencia de M4-M5: `intensidad` y `ocupacion` forman un mismo bloque y no conviene sobreponderarlas sumandolas a peso pleno.",
    "",
    "## Separacion metodologica",
    "- `historical_exposure_adjusted_score_prelim` se mantiene separado y solo se arrastra como referencia historica por edge.",
    "- `dynamic_context_signal_prelim` es una capa distinta, contextual y auditada por bin temporal.",
    "- `future_combined_edge_risk` queda solo como placeholder conceptual y no se calcula en M12.",
    "",
    "## Cobertura resultante",
    sprintf("- Filas en la base dinamica/contextual: %s", get_metric("dynamic_base_rows_n")),
    sprintf("- Edges cubiertos por la base dinamica/contextual: %s", get_metric("dynamic_base_unique_edges_n")),
    sprintf("- Rows con signal preliminar disponible: %s", get_metric("dynamic_rows_with_dynamic_signal_n")),
    sprintf("- Rows sin contexto numerico usable: %s", get_metric("dynamic_rows_without_numeric_context_n")),
    "",
    "## Limitaciones abiertas",
    "- Todavia no hay peso final de routing.",
    "- Todavia no hay integracion completa de meteorologia.",
    "- Todavia no hay severidad.",
    "- Todavia no hay calibracion final.",
    "- Todavia no hay combinacion definitiva entre historico, exposicion y contexto dinamico.",
    "",
    sprintf("- Schema de salida: `%s`.", rs_m12_output_schema_version),
    "",
    sep = "\n"
  )
}

rs_m12_write_outputs <- function(dynamic_base, dynamic_context_summary, variable_registry, dynamic_signal_note, validation_summary, output_paths) {
  readr::write_csv(dynamic_base, output_paths$dynamic_base_csv)
  readr::write_csv(dynamic_context_summary, output_paths$dynamic_summary_csv)
  readr::write_csv(variable_registry, output_paths$variable_registry_csv)
  readr::write_csv(validation_summary, output_paths$validation_summary_csv)
  writeLines(dynamic_signal_note, output_paths$dynamic_note_md, useBytes = TRUE)
}

rs_run_m12_edge_dynamic_context <- function(m8_result, paths, m9_result = NULL, m11_result = NULL, accident_master = NULL, force_refresh = FALSE) {
  rs_check_m12_packages()
  rs_validate_m12_inputs(m8_result, paths)

  output_paths <- rs_m12_output_paths(paths)
  if (!force_refresh && rs_m12_cache_is_current(output_paths)) {
    return(rs_m12_read_cached_outputs(output_paths))
  }

  network_edges <- rs_m12_load_network_edges(paths)
  matches_df <- rs_m12_load_m9_matches(m9_result, paths)
  accident_master <- rs_m12_load_accident_master(accident_master, paths)
  historical_adjusted <- rs_m12_load_historical_adjusted(m11_result, paths)

  prepared_context <- rs_m12_prepare_context_observations(matches_df, accident_master)
  dynamic_base <- rs_m12_build_dynamic_base(
    context_observations = prepared_context$context_observations,
    historical_adjusted = historical_adjusted,
    network_edges = network_edges
  )
  variable_registry <- rs_m12_build_variable_registry()
  dynamic_context_summary <- rs_m12_build_dynamic_context_summary(
    dynamic_base = dynamic_base,
    prep_summary = prepared_context$prep_summary,
    network_edges = network_edges,
    matches_df = matches_df
  )
  validation_summary <- rs_m12_build_validation_summary(
    dynamic_base = dynamic_base,
    variable_registry = variable_registry,
    network_edges = network_edges,
    historical_adjusted = historical_adjusted
  )
  dynamic_signal_note <- rs_m12_build_dynamic_signal_note(dynamic_context_summary)

  rs_m12_write_outputs(
    dynamic_base = dynamic_base,
    dynamic_context_summary = dynamic_context_summary,
    variable_registry = variable_registry,
    dynamic_signal_note = dynamic_signal_note,
    validation_summary = validation_summary,
    output_paths = output_paths
  )

  list(
    dynamic_base = dynamic_base,
    dynamic_context_summary = dynamic_context_summary,
    variable_registry = variable_registry,
    validation_summary = validation_summary,
    dynamic_signal_note = dynamic_signal_note,
    used_cache = FALSE
  )
}
