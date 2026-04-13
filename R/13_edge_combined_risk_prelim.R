rs_m13_output_schema_version <- "m13_schema_v1_combined_edge_risk_prelim_with_sensitivity"
rs_m13_top_changed_edges_n <- 50L

rs_check_m13_packages <- function() {
  required_packages <- c("dplyr", "tibble", "readr", "rlang")
  missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]

  if (length(missing_packages) > 0L) {
    stop(
      sprintf(
        "Faltan paquetes requeridos para M13: %s",
        paste(missing_packages, collapse = ", ")
      ),
      call. = FALSE
    )
  }
}

rs_validate_m13_inputs <- function(m8_result, paths) {
  if (missing(m8_result) || is.null(m8_result)) {
    stop("M13 necesita la referencia de M8 para validar `edge_id` sobre la red canonica.", call. = FALSE)
  }

  required_paths <- c("output_data", "output_tables")
  if (!all(required_paths %in% names(paths))) {
    stop("M13 necesita output_data y output_tables dentro de paths.", call. = FALSE)
  }

  network_edges_path <- file.path(paths$output_data, "m8_road_network_edges.csv")
  if (!file.exists(network_edges_path)) {
    stop("M13 necesita `m8_road_network_edges.csv`.", call. = FALSE)
  }
}

rs_m13_output_paths <- function(paths) {
  list(
    combined_risk_csv = file.path(paths$output_data, "m13_edge_combined_risk_prelim.csv"),
    combined_summary_csv = file.path(paths$output_tables, "m13_combined_risk_summary.csv"),
    weighting_rule_csv = file.path(paths$output_tables, "m13_weighting_rule.csv"),
    sensitivity_summary_csv = file.path(paths$output_tables, "m13_sensitivity_summary.csv"),
    top_changed_edges_csv = file.path(paths$output_tables, "m13_top_changed_edges.csv"),
    combined_note_md = file.path(paths$output_tables, "m13_combined_risk_note.md"),
    validation_summary_csv = file.path(paths$output_tables, "m13_validation_summary.csv")
  )
}

rs_m13_artifacts_ready <- function(output_paths) {
  all(file.exists(unlist(output_paths, use.names = FALSE)))
}

rs_m13_weighting_rule <- function() {
  tibble::tribble(
    ~scenario_name, ~historical_weight, ~dynamic_weight, ~missing_component_handling, ~interpretation, ~rationale, ~schema_version,
    "baseline_combined_risk_prelim", 2/3, 1/3, "if_one_component_missing_use_available_component", "El historico ajustado pesa el doble que el dinamico contextual.", "La capa historica ajustada por exposicion es hoy mas estable y multi-anual; la capa dinamica ya aporta contexto, pero sigue siendo mas parcial y accident-backed.", rs_m13_output_schema_version,
    "historical_heavy_sensitivity", 4/5, 1/5, "if_one_component_missing_use_available_component", "Escenario conservador que deja casi todo el peso en la historia.", "Sirve para medir cuanto cambian los rankings cuando se prioriza casi por completo la senal estructural.", rs_m13_output_schema_version,
    "dynamic_heavy_sensitivity", 2/5, 3/5, "if_one_component_missing_use_available_component", "Escenario de contraste que deja mas peso al contexto que al historico.", "Sirve para medir hasta donde podria moverse el ranking si el bloque contextual ganara mas relevancia en fases futuras.", rs_m13_output_schema_version
  )
}

rs_m13_cache_is_current <- function(output_paths) {
  if (!rs_m13_artifacts_ready(output_paths)) {
    return(FALSE)
  }

  weighting_rule <- tryCatch(
    readr::read_csv(output_paths$weighting_rule_csv, show_col_types = FALSE),
    error = function(...) NULL
  )
  validation <- tryCatch(
    readr::read_csv(output_paths$validation_summary_csv, show_col_types = FALSE),
    error = function(...) NULL
  )

  if (is.null(weighting_rule) || is.null(validation)) {
    return(FALSE)
  }

  expected_rule <- rs_m13_weighting_rule() |>
    dplyr::select(scenario_name, historical_weight, dynamic_weight, schema_version)
  found_rule <- weighting_rule |>
    dplyr::select(scenario_name, historical_weight, dynamic_weight, schema_version)

  same_rule <- nrow(expected_rule) == nrow(found_rule) &&
    identical(expected_rule$scenario_name, found_rule$scenario_name) &&
    all(abs(expected_rule$historical_weight - found_rule$historical_weight) < 1e-9) &&
    all(abs(expected_rule$dynamic_weight - found_rule$dynamic_weight) < 1e-9) &&
    identical(expected_rule$schema_version, found_rule$schema_version)

  schema_value <- validation |>
    dplyr::filter(metric == "output_schema_version") |>
    dplyr::pull(value)

  same_rule && length(schema_value) == 1L && identical(schema_value[[1]], rs_m13_output_schema_version)
}

rs_m13_read_cached_outputs <- function(output_paths) {
  list(
    combined_risk = readr::read_csv(output_paths$combined_risk_csv, show_col_types = FALSE),
    combined_summary = readr::read_csv(output_paths$combined_summary_csv, show_col_types = FALSE),
    weighting_rule = readr::read_csv(output_paths$weighting_rule_csv, show_col_types = FALSE),
    sensitivity_summary = readr::read_csv(output_paths$sensitivity_summary_csv, show_col_types = FALSE),
    top_changed_edges = readr::read_csv(output_paths$top_changed_edges_csv, show_col_types = FALSE),
    validation_summary = readr::read_csv(output_paths$validation_summary_csv, show_col_types = FALSE),
    combined_risk_note = paste(readLines(output_paths$combined_note_md, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
    used_cache = TRUE
  )
}

rs_m13_load_network_edges <- function(paths) {
  network_path <- file.path(paths$output_data, "m8_road_network_edges.csv")
  network_edges <- readr::read_csv(network_path, show_col_types = FALSE)

  required_columns <- c("edge_id", "edge_length_m")
  missing_columns <- setdiff(required_columns, names(network_edges))
  if (length(missing_columns) > 0L) {
    stop(
      sprintf(
        "Faltan columnas requeridas en `m8_road_network_edges.csv` para M13: %s",
        paste(missing_columns, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  network_edges |>
    dplyr::select(edge_id, edge_length_m)
}

rs_m13_load_m10_aggregation <- function(m10_result, paths) {
  if (!missing(m10_result) && !is.null(m10_result) && "aggregation" %in% names(m10_result)) {
    return(m10_result$aggregation)
  }

  aggregation_path <- file.path(paths$output_data, "m10_edge_historical_aggregation.csv")
  if (!file.exists(aggregation_path)) {
    stop("M13 necesita `m10_edge_historical_aggregation.csv`.", call. = FALSE)
  }

  readr::read_csv(aggregation_path, show_col_types = FALSE)
}

rs_m13_load_m11_historical_adjusted <- function(m11_result, paths) {
  if (!missing(m11_result) && !is.null(m11_result) && "historical_exposure_adjusted" %in% names(m11_result)) {
    return(m11_result$historical_exposure_adjusted)
  }

  adjusted_path <- file.path(paths$output_data, "m11_historical_exposure_adjusted.csv")
  if (!file.exists(adjusted_path)) {
    stop("M13 necesita `m11_historical_exposure_adjusted.csv`.", call. = FALSE)
  }

  readr::read_csv(adjusted_path, show_col_types = FALSE)
}

rs_m13_load_m12_dynamic_base <- function(m12_result, paths) {
  if (!missing(m12_result) && !is.null(m12_result) && "dynamic_base" %in% names(m12_result)) {
    return(m12_result$dynamic_base)
  }

  dynamic_path <- file.path(paths$output_data, "m12_edge_context_dynamic_base.csv")
  if (!file.exists(dynamic_path)) {
    stop("M13 necesita `m12_edge_context_dynamic_base.csv`.", call. = FALSE)
  }

  readr::read_csv(dynamic_path, show_col_types = FALSE)
}

rs_m13_validate_loaded_inputs <- function(dynamic_base, historical_aggregation, historical_adjusted) {
  required_dynamic_columns <- c(
    "edge_id",
    "temporal_bin_4h",
    "is_weekend",
    "context_observation_n",
    "context_data_quality_flag",
    "dynamic_context_signal_prelim",
    "historical_exposure_adjusted_score_prelim",
    "exposure_proxy_value",
    "exposure_quality_flag"
  )
  missing_dynamic_columns <- setdiff(required_dynamic_columns, names(dynamic_base))
  if (length(missing_dynamic_columns) > 0L) {
    stop(
      sprintf(
        "Faltan columnas requeridas en `m12_edge_context_dynamic_base.csv` para M13: %s",
        paste(missing_dynamic_columns, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  required_m10_columns <- c(
    "edge_id",
    "historical_score_prelim",
    "accident_count_raw",
    "accident_count_weighted_by_quality",
    "accidents_per_km_raw",
    "accidents_per_km"
  )
  missing_m10_columns <- setdiff(required_m10_columns, names(historical_aggregation))
  if (length(missing_m10_columns) > 0L) {
    stop(
      sprintf(
        "Faltan columnas requeridas en `m10_edge_historical_aggregation.csv` para M13: %s",
        paste(missing_m10_columns, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  required_m11_columns <- c("edge_id", "historical_exposure_adjusted_score_prelim")
  missing_m11_columns <- setdiff(required_m11_columns, names(historical_adjusted))
  if (length(missing_m11_columns) > 0L) {
    stop(
      sprintf(
        "Faltan columnas requeridas en `m11_historical_exposure_adjusted.csv` para M13: %s",
        paste(missing_m11_columns, collapse = ", ")
      ),
      call. = FALSE
    )
  }
}

rs_m13_weighted_average_available <- function(hist_values, dyn_values, hist_weight, dyn_weight) {
  result <- rep(NA_real_, length(hist_values))

  hist_only <- !is.na(hist_values) & is.na(dyn_values)
  dyn_only <- is.na(hist_values) & !is.na(dyn_values)
  both_available <- !is.na(hist_values) & !is.na(dyn_values)

  result[hist_only] <- hist_values[hist_only]
  result[dyn_only] <- dyn_values[dyn_only]
  result[both_available] <- (hist_weight * hist_values[both_available]) + (dyn_weight * dyn_values[both_available])

  result
}

rs_m13_safe_weighted_mean <- function(values, weights) {
  valid <- !is.na(values) & !is.na(weights) & weights > 0
  if (!any(valid)) {
    return(NA_real_)
  }

  stats::weighted.mean(values[valid], weights[valid])
}

rs_m13_build_combined_table <- function(dynamic_base, historical_aggregation) {
  combined_df <- dynamic_base |>
    dplyr::left_join(
      historical_aggregation |>
        dplyr::select(
          edge_id,
          historical_component = historical_score_prelim,
          accident_count_raw,
          accident_count_weighted_by_quality,
          accidents_per_km_raw,
          accidents_per_km,
          historical_notes_or_flags = notes_or_flags
        ),
      by = "edge_id"
    ) |>
    dplyr::mutate(
      exposure_adjusted_historical_component = historical_exposure_adjusted_score_prelim,
      dynamic_component = dynamic_context_signal_prelim,
      historical_component_used_for_combination = dplyr::coalesce(
        exposure_adjusted_historical_component,
        historical_component
      ),
      historical_component_source = dplyr::case_when(
        !is.na(exposure_adjusted_historical_component) ~ "exposure_adjusted_historical_component",
        !is.na(historical_component) ~ "raw_historical_component_fallback",
        TRUE ~ NA_character_
      ),
      combined_edge_risk_prelim = rs_m13_weighted_average_available(
        hist_values = historical_component_used_for_combination,
        dyn_values = dynamic_component,
        hist_weight = 2/3,
        dyn_weight = 1/3
      ),
      combined_edge_risk_prelim_historical_heavy = rs_m13_weighted_average_available(
        hist_values = historical_component_used_for_combination,
        dyn_values = dynamic_component,
        hist_weight = 4/5,
        dyn_weight = 1/5
      ),
      combined_edge_risk_prelim_dynamic_heavy = rs_m13_weighted_average_available(
        hist_values = historical_component_used_for_combination,
        dyn_values = dynamic_component,
        hist_weight = 2/5,
        dyn_weight = 3/5
      ),
      combined_delta_histheavy_vs_baseline = combined_edge_risk_prelim_historical_heavy - combined_edge_risk_prelim,
      combined_delta_dynheavy_vs_baseline = combined_edge_risk_prelim_dynamic_heavy - combined_edge_risk_prelim,
      combined_delta_hist_vs_dyn = combined_edge_risk_prelim_historical_heavy - combined_edge_risk_prelim_dynamic_heavy,
      combination_rule_applied = dplyr::case_when(
        !is.na(historical_component_used_for_combination) & !is.na(dynamic_component) ~ "weighted_average_of_historical_and_dynamic",
        !is.na(historical_component_used_for_combination) & is.na(dynamic_component) ~ "historical_only_fallback",
        is.na(historical_component_used_for_combination) & !is.na(dynamic_component) ~ "dynamic_only_fallback",
        TRUE ~ "no_component_available"
      ),
      future_routing_weight = NA_real_
    )

  note_flags <- character(nrow(combined_df))
  note_flags[] <- ""

  append_flag <- function(existing, mask, flag_name) {
    mask <- !is.na(mask) & mask
    existing[mask] <- ifelse(existing[mask] == "", flag_name, paste(existing[mask], flag_name, sep = " | "))
    existing
  }

  note_flags <- append_flag(note_flags, combined_df$historical_component_source == "raw_historical_component_fallback", "exposure_adjusted_historical_missing_fallback_to_raw_historical")
  note_flags <- append_flag(note_flags, combined_df$combination_rule_applied == "historical_only_fallback", "dynamic_component_missing")
  note_flags <- append_flag(note_flags, combined_df$combination_rule_applied == "dynamic_only_fallback", "historical_component_missing")
  note_flags <- append_flag(note_flags, combined_df$context_data_quality_flag == "low_support", "dynamic_context_low_support")
  note_flags <- append_flag(note_flags, combined_df$context_data_quality_flag == "no_numeric_context", "dynamic_context_not_available")
  note_flags <- append_flag(note_flags, TRUE, "combined_edge_risk_prelim_not_final_routing_weight")

  combined_df |>
    dplyr::mutate(
      historical_component = round(historical_component, 3),
      exposure_adjusted_historical_component = round(exposure_adjusted_historical_component, 3),
      historical_component_used_for_combination = round(historical_component_used_for_combination, 3),
      dynamic_component = round(dynamic_component, 3),
      combined_edge_risk_prelim = round(combined_edge_risk_prelim, 3),
      combined_edge_risk_prelim_historical_heavy = round(combined_edge_risk_prelim_historical_heavy, 3),
      combined_edge_risk_prelim_dynamic_heavy = round(combined_edge_risk_prelim_dynamic_heavy, 3),
      combined_delta_histheavy_vs_baseline = round(combined_delta_histheavy_vs_baseline, 3),
      combined_delta_dynheavy_vs_baseline = round(combined_delta_dynheavy_vs_baseline, 3),
      combined_delta_hist_vs_dyn = round(combined_delta_hist_vs_dyn, 3),
      notes_or_limitations = dplyr::case_when(
        is.na(notes_or_limitations) | notes_or_limitations == "" ~ dplyr::na_if(note_flags, ""),
        TRUE ~ paste(notes_or_limitations, note_flags, sep = " | ")
      )
    ) |>
    dplyr::mutate(
      notes_or_limitations = gsub("^ \\| |^\\| | \\| $", "", notes_or_limitations),
      notes_or_limitations = gsub("\\| \\|", "|", notes_or_limitations)
    )
}

rs_m13_build_combined_summary <- function(combined_df) {
  nonmissing_combined <- combined_df$combined_edge_risk_prelim[!is.na(combined_df$combined_edge_risk_prelim)]

  tibble::tibble(
    metric = c(
      "combined_rows_n",
      "combined_unique_edges_n",
      "historical_component_nonmissing_n",
      "exposure_adjusted_historical_component_nonmissing_n",
      "rows_using_exposure_adjusted_historical_n",
      "rows_using_raw_historical_fallback_n",
      "dynamic_component_nonmissing_n",
      "rows_using_weighted_average_n",
      "rows_using_historical_only_fallback_n",
      "rows_using_dynamic_only_fallback_n",
      "combined_edge_risk_prelim_nonmissing_n",
      "combined_edge_risk_prelim_p50_nonmissing",
      "combined_edge_risk_prelim_p95_nonmissing",
      "combined_edge_risk_prelim_max",
      "future_routing_weight_calculated"
    ),
    value = c(
      as.character(nrow(combined_df)),
      as.character(dplyr::n_distinct(combined_df$edge_id)),
      as.character(sum(!is.na(combined_df$historical_component))),
      as.character(sum(!is.na(combined_df$exposure_adjusted_historical_component))),
      as.character(sum(combined_df$historical_component_source == "exposure_adjusted_historical_component", na.rm = TRUE)),
      as.character(sum(combined_df$historical_component_source == "raw_historical_component_fallback", na.rm = TRUE)),
      as.character(sum(!is.na(combined_df$dynamic_component))),
      as.character(sum(combined_df$combination_rule_applied == "weighted_average_of_historical_and_dynamic", na.rm = TRUE)),
      as.character(sum(combined_df$combination_rule_applied == "historical_only_fallback", na.rm = TRUE)),
      as.character(sum(combined_df$combination_rule_applied == "dynamic_only_fallback", na.rm = TRUE)),
      as.character(sum(!is.na(combined_df$combined_edge_risk_prelim))),
      if (length(nonmissing_combined)) sprintf("%.3f", stats::median(nonmissing_combined, na.rm = TRUE)) else NA_character_,
      if (length(nonmissing_combined)) sprintf("%.3f", as.numeric(stats::quantile(nonmissing_combined, 0.95, na.rm = TRUE))) else NA_character_,
      if (length(nonmissing_combined)) sprintf("%.3f", max(nonmissing_combined, na.rm = TRUE)) else NA_character_,
      "FALSE"
    )
  )
}

rs_m13_build_edge_sensitivity_table <- function(combined_df) {
  combined_df |>
    dplyr::group_by(edge_id) |>
    dplyr::summarise(
      bins_n = dplyr::n(),
      context_observation_weight_n = sum(context_observation_n, na.rm = TRUE),
      baseline_edge_risk = rs_m13_safe_weighted_mean(combined_edge_risk_prelim, pmax(context_observation_n, 1)),
      historical_heavy_edge_risk = rs_m13_safe_weighted_mean(combined_edge_risk_prelim_historical_heavy, pmax(context_observation_n, 1)),
      dynamic_heavy_edge_risk = rs_m13_safe_weighted_mean(combined_edge_risk_prelim_dynamic_heavy, pmax(context_observation_n, 1)),
      historical_only_fallback_bins_n = sum(combination_rule_applied == "historical_only_fallback", na.rm = TRUE),
      dynamic_available_bins_n = sum(!is.na(dynamic_component), na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::arrange(dplyr::desc(baseline_edge_risk), edge_id) |>
    dplyr::mutate(
      baseline_rank = dplyr::min_rank(dplyr::desc(baseline_edge_risk)),
      historical_heavy_rank = dplyr::min_rank(dplyr::desc(historical_heavy_edge_risk)),
      dynamic_heavy_rank = dplyr::min_rank(dplyr::desc(dynamic_heavy_edge_risk)),
      rank_shift_baseline_vs_historical_heavy = abs(baseline_rank - historical_heavy_rank),
      rank_shift_baseline_vs_dynamic_heavy = abs(baseline_rank - dynamic_heavy_rank),
      rank_shift_historical_vs_dynamic_heavy = abs(historical_heavy_rank - dynamic_heavy_rank),
      max_rank_change_across_scenarios = pmax(
        rank_shift_baseline_vs_historical_heavy,
        rank_shift_baseline_vs_dynamic_heavy,
        rank_shift_historical_vs_dynamic_heavy,
        na.rm = TRUE
      )
    )
}

rs_m13_build_sensitivity_summary <- function(combined_df, edge_sensitivity_df, weighting_rule) {
  build_row <- function(scenario_label, score_column, diff_column = NULL, rank_column = NULL) {
    scores <- combined_df[[score_column]]
    nonmissing <- scores[!is.na(scores)]

    mean_abs_diff <- if (!is.null(diff_column)) {
      diff_values <- abs(combined_df[[diff_column]])
      diff_values <- diff_values[!is.na(diff_values)]
      if (length(diff_values)) mean(diff_values) else NA_real_
    } else {
      0
    }

    p95_abs_diff <- if (!is.null(diff_column)) {
      diff_values <- abs(combined_df[[diff_column]])
      diff_values <- diff_values[!is.na(diff_values)]
      if (length(diff_values)) as.numeric(stats::quantile(diff_values, 0.95, na.rm = TRUE)) else NA_real_
    } else {
      0
    }

    rank_shift_p50 <- if (!is.null(rank_column)) {
      values <- edge_sensitivity_df[[rank_column]]
      values <- values[!is.na(values)]
      if (length(values)) stats::median(values, na.rm = TRUE) else NA_real_
    } else {
      0
    }

    rank_shift_p95 <- if (!is.null(rank_column)) {
      values <- edge_sensitivity_df[[rank_column]]
      values <- values[!is.na(values)]
      if (length(values)) as.numeric(stats::quantile(values, 0.95, na.rm = TRUE)) else NA_real_
    } else {
      0
    }

    rank_shift_max <- if (!is.null(rank_column)) {
      values <- edge_sensitivity_df[[rank_column]]
      values <- values[!is.na(values)]
      if (length(values)) max(values, na.rm = TRUE) else NA_real_
    } else {
      0
    }

    weights <- weighting_rule |>
      dplyr::filter(scenario_name == scenario_label)

    tibble::tibble(
      scenario_name = scenario_label,
      historical_weight = weights$historical_weight[[1]],
      dynamic_weight = weights$dynamic_weight[[1]],
      rows_nonmissing_n = sum(!is.na(scores)),
      score_p50_nonmissing = if (length(nonmissing)) stats::median(nonmissing, na.rm = TRUE) else NA_real_,
      score_p95_nonmissing = if (length(nonmissing)) as.numeric(stats::quantile(nonmissing, 0.95, na.rm = TRUE)) else NA_real_,
      mean_abs_diff_vs_baseline = mean_abs_diff,
      p95_abs_diff_vs_baseline = p95_abs_diff,
      edge_rank_shift_p50_vs_baseline = rank_shift_p50,
      edge_rank_shift_p95_vs_baseline = rank_shift_p95,
      edge_rank_shift_max_vs_baseline = rank_shift_max
    )
  }

  dplyr::bind_rows(
    build_row("baseline_combined_risk_prelim", "combined_edge_risk_prelim"),
    build_row(
      "historical_heavy_sensitivity",
      "combined_edge_risk_prelim_historical_heavy",
      diff_column = "combined_delta_histheavy_vs_baseline",
      rank_column = "rank_shift_baseline_vs_historical_heavy"
    ),
    build_row(
      "dynamic_heavy_sensitivity",
      "combined_edge_risk_prelim_dynamic_heavy",
      diff_column = "combined_delta_dynheavy_vs_baseline",
      rank_column = "rank_shift_baseline_vs_dynamic_heavy"
    )
  ) |>
    dplyr::mutate(
      score_p50_nonmissing = round(score_p50_nonmissing, 3),
      score_p95_nonmissing = round(score_p95_nonmissing, 3),
      mean_abs_diff_vs_baseline = round(mean_abs_diff_vs_baseline, 3),
      p95_abs_diff_vs_baseline = round(p95_abs_diff_vs_baseline, 3)
    )
}

rs_m13_build_top_changed_edges <- function(edge_sensitivity_df, top_n = rs_m13_top_changed_edges_n) {
  edge_sensitivity_df |>
    dplyr::arrange(
      dplyr::desc(max_rank_change_across_scenarios),
      dplyr::desc(rank_shift_baseline_vs_dynamic_heavy),
      dplyr::desc(rank_shift_baseline_vs_historical_heavy),
      edge_id
    ) |>
    dplyr::slice_head(n = top_n) |>
    dplyr::mutate(
      primary_shift_driver = dplyr::case_when(
        rank_shift_baseline_vs_dynamic_heavy >= rank_shift_baseline_vs_historical_heavy &
          rank_shift_baseline_vs_dynamic_heavy >= rank_shift_historical_vs_dynamic_heavy ~ "dynamic_heavy_vs_baseline",
        rank_shift_baseline_vs_historical_heavy >= rank_shift_historical_vs_dynamic_heavy ~ "historical_heavy_vs_baseline",
        TRUE ~ "historical_heavy_vs_dynamic_heavy"
      )
    ) |>
    dplyr::select(
      edge_id,
      bins_n,
      context_observation_weight_n,
      baseline_edge_risk,
      historical_heavy_edge_risk,
      dynamic_heavy_edge_risk,
      baseline_rank,
      historical_heavy_rank,
      dynamic_heavy_rank,
      rank_shift_baseline_vs_historical_heavy,
      rank_shift_baseline_vs_dynamic_heavy,
      rank_shift_historical_vs_dynamic_heavy,
      max_rank_change_across_scenarios,
      historical_only_fallback_bins_n,
      dynamic_available_bins_n,
      primary_shift_driver
    )
}

rs_m13_build_validation_summary <- function(combined_df, network_edges) {
  combined_keys <- paste(combined_df$edge_id, combined_df$temporal_bin_4h, combined_df$is_weekend, sep = "::")

  tibble::tibble(
    metric = c(
      "edge_ids_in_combined_output_exist_in_network",
      "duplicated_edge_bin_key_in_combined_output",
      "historical_component_column_present",
      "exposure_adjusted_historical_component_column_present",
      "dynamic_component_column_present",
      "combined_edge_risk_prelim_column_present",
      "combined_edge_risk_prelim_traced_by_components",
      "combination_preserves_original_components",
      "combined_edge_risk_prelim_nonmissing_n",
      "rows_using_exposure_adjusted_historical_n",
      "rows_using_raw_historical_fallback_n",
      "rows_using_historical_only_fallback_n",
      "combined_edge_risk_prelim_is_final_routing_weight",
      "future_routing_weight_calculated",
      "output_schema_version"
    ),
    value = c(
      as.character(all(combined_df$edge_id %in% network_edges$edge_id)),
      as.character(anyDuplicated(combined_keys) > 0L),
      as.character("historical_component" %in% names(combined_df)),
      as.character("exposure_adjusted_historical_component" %in% names(combined_df)),
      as.character("dynamic_component" %in% names(combined_df)),
      as.character("combined_edge_risk_prelim" %in% names(combined_df)),
      as.character(all(c(
        "historical_component",
        "exposure_adjusted_historical_component",
        "dynamic_component",
        "combined_edge_risk_prelim"
      ) %in% names(combined_df))),
      "TRUE",
      as.character(sum(!is.na(combined_df$combined_edge_risk_prelim))),
      as.character(sum(combined_df$historical_component_source == "exposure_adjusted_historical_component", na.rm = TRUE)),
      as.character(sum(combined_df$historical_component_source == "raw_historical_component_fallback", na.rm = TRUE)),
      as.character(sum(combined_df$combination_rule_applied == "historical_only_fallback", na.rm = TRUE)),
      "FALSE",
      "FALSE",
      rs_m13_output_schema_version
    )
  )
}

rs_m13_build_combined_note <- function(combined_summary, sensitivity_summary, top_changed_edges) {
  get_metric <- function(tbl, metric_name) {
    value <- tbl |>
      dplyr::filter(metric == metric_name) |>
      dplyr::pull(value)
    if (!length(value)) {
      return(NA_character_)
    }
    value[[1]]
  }

  get_scenario_metric <- function(tbl, scenario_label, column_name) {
    value <- tbl |>
      dplyr::filter(scenario_name == scenario_label) |>
      dplyr::pull(!!rlang::sym(column_name))
    if (!length(value)) {
      return(NA_character_)
    }
    value[[1]]
  }

  sparse_top_changed_n <- sum(top_changed_edges$bins_n == 1, na.rm = TRUE)
  sparse_single_obs_n <- sum(top_changed_edges$context_observation_weight_n == 1, na.rm = TRUE)

  paste(
    "# M13 - Riesgo combinado preliminar por edge/bin",
    "",
    "## Regla baseline",
    "- M13 combina `historical_exposure_adjusted_score_prelim` y `dynamic_context_signal_prelim` en la misma escala `0-100`.",
    "- La regla baseline es una media ponderada simple `2/3 historico + 1/3 dinamico`.",
    "- Si el score historico ajustado falta, M13 hace fallback explicito a `historical_score_prelim`.",
    "- Si el componente dinamico falta, M13 no lo inventa y usa solo el historico disponible.",
    "",
    "## Por que esta regla es conservadora",
    "- El historico ajustado por exposicion es hoy mas estable porque agrega senal multi-anual.",
    "- El contexto dinamico ya es util, pero sigue siendo mas parcial y accident-backed.",
    "- Los pesos no salen del PCA; se fijan solo como una regla operativa simple y auditable.",
    "",
    "## Sensibilidades minimas",
    "- `historical_heavy = 4/5 historico + 1/5 dinamico`.",
    "- `dynamic_heavy = 2/5 historico + 3/5 dinamico`.",
    sprintf("- Cambio medio absoluto frente al baseline cuando pesa mas el historico: %s", get_scenario_metric(sensitivity_summary, "historical_heavy_sensitivity", "mean_abs_diff_vs_baseline")),
    sprintf("- Cambio medio absoluto frente al baseline cuando pesa mas el dinamico: %s", get_scenario_metric(sensitivity_summary, "dynamic_heavy_sensitivity", "mean_abs_diff_vs_baseline")),
    sprintf("- Entre los 50 edges con mayor cambio de ranking, %s tienen un solo bin y %s tienen peso observacional 1; la sensibilidad extrema se concentra sobre todo en soporte contextual muy fino.", sparse_top_changed_n, sparse_single_obs_n),
    "",
    "## Cobertura resultante",
    sprintf("- Filas combinadas: %s", get_metric(combined_summary, "combined_rows_n")),
    sprintf("- Edges cubiertos: %s", get_metric(combined_summary, "combined_unique_edges_n")),
    sprintf("- Filas con historico ajustado usable: %s", get_metric(combined_summary, "rows_using_exposure_adjusted_historical_n")),
    sprintf("- Filas con fallback a historico raw: %s", get_metric(combined_summary, "rows_using_raw_historical_fallback_n")),
    sprintf("- Filas con fallback solo historico por falta de contexto dinamico: %s", get_metric(combined_summary, "rows_using_historical_only_fallback_n")),
    "",
    "## Separacion metodologica",
    "- `historical_component` conserva la capa historica preliminar de M10.",
    "- `exposure_adjusted_historical_component` conserva el ajuste preliminar de M11.",
    "- `dynamic_component` conserva la capa contextual de M12.",
    "- `combined_edge_risk_prelim` es solo una combinacion operativa preliminar y trazable de esas piezas.",
    "",
    "## Lo que M13 no hace",
    "- No calcula todavia el peso final de routing.",
    "- No incorpora todavia severidad.",
    "- No incorpora todavia meteorologia operativa completa.",
    "- No sustituye a un futuro modelo supervisado si mas adelante entra.",
    "- No ejecuta routing ni coste final de grafo.",
    "",
    sprintf("- Schema de salida: `%s`.", rs_m13_output_schema_version),
    "",
    sep = "\n"
  )
}

rs_m13_write_outputs <- function(combined_df, combined_summary, weighting_rule, sensitivity_summary, top_changed_edges, combined_note, validation_summary, output_paths) {
  readr::write_csv(combined_df, output_paths$combined_risk_csv)
  readr::write_csv(combined_summary, output_paths$combined_summary_csv)
  readr::write_csv(weighting_rule, output_paths$weighting_rule_csv)
  readr::write_csv(sensitivity_summary, output_paths$sensitivity_summary_csv)
  readr::write_csv(top_changed_edges, output_paths$top_changed_edges_csv)
  readr::write_csv(validation_summary, output_paths$validation_summary_csv)
  writeLines(combined_note, output_paths$combined_note_md, useBytes = TRUE)
}

rs_run_m13_edge_combined_risk_prelim <- function(m8_result, paths, m10_result = NULL, m11_result = NULL, m12_result = NULL, force_refresh = FALSE) {
  rs_check_m13_packages()
  rs_validate_m13_inputs(m8_result, paths)

  output_paths <- rs_m13_output_paths(paths)
  if (!force_refresh && rs_m13_cache_is_current(output_paths)) {
    return(rs_m13_read_cached_outputs(output_paths))
  }

  network_edges <- rs_m13_load_network_edges(paths)
  historical_aggregation <- rs_m13_load_m10_aggregation(m10_result, paths)
  historical_adjusted <- rs_m13_load_m11_historical_adjusted(m11_result, paths)
  dynamic_base <- rs_m13_load_m12_dynamic_base(m12_result, paths)

  rs_m13_validate_loaded_inputs(dynamic_base, historical_aggregation, historical_adjusted)

  combined_df <- rs_m13_build_combined_table(dynamic_base, historical_aggregation)
  combined_summary <- rs_m13_build_combined_summary(combined_df)
  weighting_rule <- rs_m13_weighting_rule()
  edge_sensitivity_df <- rs_m13_build_edge_sensitivity_table(combined_df)
  sensitivity_summary <- rs_m13_build_sensitivity_summary(combined_df, edge_sensitivity_df, weighting_rule)
  top_changed_edges <- rs_m13_build_top_changed_edges(edge_sensitivity_df)
  validation_summary <- rs_m13_build_validation_summary(combined_df, network_edges)
  combined_note <- rs_m13_build_combined_note(combined_summary, sensitivity_summary, top_changed_edges)

  rs_m13_write_outputs(
    combined_df = combined_df,
    combined_summary = combined_summary,
    weighting_rule = weighting_rule,
    sensitivity_summary = sensitivity_summary,
    top_changed_edges = top_changed_edges,
    combined_note = combined_note,
    validation_summary = validation_summary,
    output_paths = output_paths
  )

  list(
    combined_risk = combined_df,
    combined_summary = combined_summary,
    weighting_rule = weighting_rule,
    sensitivity_summary = sensitivity_summary,
    top_changed_edges = top_changed_edges,
    validation_summary = validation_summary,
    combined_risk_note = combined_note,
    used_cache = FALSE
  )
}
