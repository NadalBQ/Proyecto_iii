rs_m4_candidate_registry <- tibble::tribble(
  ~variable,     ~type,
  "intensidad",  "continuous_context",
  "ocupacion",   "continuous_context",
  "hour_sin",    "continuous_cyclical",
  "hour_cos",    "continuous_cyclical",
  "es_festivo",  "binary_calendar",
  "is_weekend",  "binary_calendar",
  "vmed",        "continuous_under_review"
)

rs_m4_set_registry <- tibble::tibble(
  set_name = c(
    "main_continuous",
    "with_vmed",
    "with_binary_calendar",
    "full_candidate"
  ),
  variables = list(
    c("intensidad", "ocupacion", "hour_sin", "hour_cos"),
    c("intensidad", "ocupacion", "hour_sin", "hour_cos", "vmed"),
    c("intensidad", "ocupacion", "hour_sin", "hour_cos", "es_festivo", "is_weekend"),
    c("intensidad", "ocupacion", "hour_sin", "hour_cos", "es_festivo", "is_weekend", "vmed")
  )
)

rs_check_m4_packages <- function() {
  required_packages <- c("dplyr", "tibble", "readr", "lubridate", "ggplot2")
  missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]

  if (length(missing_packages) > 0) {
    stop(
      sprintf(
        "Faltan paquetes requeridos para M4: %s",
        paste(missing_packages, collapse = ", ")
      ),
      call. = FALSE
    )
  }
}

rs_validate_m4_inputs <- function(accident_master, pca_base) {
  master_required_columns <- c(
    "num_expediente",
    "fecha",
    "hora",
    "dia_semana",
    "es_festivo",
    "intensidad",
    "ocupacion",
    "vmed",
    "pca_initial_eligible"
  )
  pca_base_required_columns <- c(
    "num_expediente",
    "fecha",
    "hora",
    "dia_semana",
    "es_festivo",
    "is_weekend",
    "hour_decimal",
    "hour_sin",
    "hour_cos",
    "intensidad",
    "ocupacion",
    "vmed"
  )

  missing_master <- setdiff(master_required_columns, names(accident_master))
  missing_pca_base <- setdiff(pca_base_required_columns, names(pca_base))

  if (length(missing_master) > 0) {
    stop(
      sprintf(
        "Faltan columnas requeridas en tabla_accidente_master para M4: %s",
        paste(missing_master, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  if (length(missing_pca_base) > 0) {
    stop(
      sprintf(
        "Faltan columnas requeridas en la base conflict-free para M4: %s",
        paste(missing_pca_base, collapse = ", ")
      ),
      call. = FALSE
    )
  }
}

rs_parse_m4_fecha <- function(x) {
  if (inherits(x, "Date")) {
    return(x)
  }

  suppressWarnings(lubridate::ymd(as.character(x), quiet = TRUE))
}

rs_parse_m4_hour_decimal <- function(x) {
  if (inherits(x, "difftime")) {
    return(as.numeric(x) / 3600)
  }

  parsed_hora <- suppressWarnings(lubridate::hms(as.character(x), quiet = TRUE))

  if (all(is.na(parsed_hora))) {
    return(rep(NA_real_, length(x)))
  }

  as.numeric(parsed_hora) / 3600
}

rs_build_m4_screening_base <- function(accident_master) {
  parsed_fecha <- rs_parse_m4_fecha(accident_master$fecha)
  hour_decimal <- rs_parse_m4_hour_decimal(accident_master$hora)

  accident_master |>
    dplyr::mutate(
      fecha = parsed_fecha,
      hour_decimal = hour_decimal,
      is_weekend = dplyr::case_when(
        is.na(dia_semana) ~ NA,
        dia_semana %in% c("sabado", "domingo") ~ TRUE,
        TRUE ~ FALSE
      ),
      hour_sin = dplyr::if_else(is.na(hour_decimal), NA_real_, sin(2 * pi * hour_decimal / 24)),
      hour_cos = dplyr::if_else(is.na(hour_decimal), NA_real_, cos(2 * pi * hour_decimal / 24))
    ) |>
    dplyr::filter(pca_initial_eligible) |>
    dplyr::select(
      num_expediente,
      fecha,
      hora,
      dia_semana,
      es_festivo,
      is_weekend,
      hour_decimal,
      hour_sin,
      hour_cos,
      intensidad,
      ocupacion,
      vmed
    )
}

rs_validate_m4_screening_base <- function(screening_base, pca_base) {
  screening_ids <- screening_base |>
    dplyr::arrange(num_expediente) |>
    dplyr::pull(num_expediente)
  pca_base_ids <- pca_base |>
    dplyr::arrange(num_expediente) |>
    dplyr::pull(num_expediente)

  if (!identical(screening_ids, pca_base_ids)) {
    stop(
      "La base de screening derivada de tabla_accidente_master no coincide en expedientes con la base conflict-free.",
      call. = FALSE
    )
  }
}

rs_numericize_candidate <- function(x) {
  if (is.logical(x)) {
    return(as.numeric(x))
  }

  as.numeric(x)
}

rs_safe_quantile <- function(x, prob) {
  if (length(x) == 0L) {
    return(NA_real_)
  }

  as.numeric(stats::quantile(x, probs = prob, na.rm = TRUE, names = FALSE, type = 7))
}

rs_zero_pct <- function(x) {
  if (length(x) == 0L) {
    return(NA_real_)
  }

  mean(abs(x) < sqrt(.Machine$double.eps)) * 100
}

rs_negative_pct <- function(x) {
  if (length(x) == 0L) {
    return(NA_real_)
  }

  mean(x < -sqrt(.Machine$double.eps)) * 100
}

rs_near_zero_variance_flag <- function(x) {
  non_missing <- x[!is.na(x)]

  if (length(non_missing) < 2L) {
    return(TRUE)
  }

  value_counts <- sort(table(non_missing), decreasing = TRUE)
  unique_n <- length(value_counts)

  if (unique_n <= 1L) {
    return(TRUE)
  }

  if (unique_n == 2L) {
    freq_ratio <- as.numeric(value_counts[1] / value_counts[2])
    pct_unique <- 100 * unique_n / length(non_missing)
    return(freq_ratio > 19 && pct_unique <= 10)
  }

  FALSE
}

rs_recommend_candidate <- function(variable_name, near_zero_variance_flag, missing_pct, negative_pct, zero_pct) {
  if (variable_name == "vmed") {
    return(list(
      recommendation = "sensitivity",
      rationale = "Known noisy variable in ROAD-SAFETY; heavy zero mass and some negative values keep it under review rather than in the main PCA block."
    ))
  }

  if (variable_name == "es_festivo") {
    return(list(
      recommendation = "exclude",
      rationale = sprintf(
        "Binary rare-event calendar flag with %.2f%% zeros%s; keep out of the preferred PCA specification and inspect only as a non-priority contrast.",
        zero_pct,
        if (isTRUE(near_zero_variance_flag)) " and near-zero variance" else ""
      )
    ))
  }

  if (variable_name == "is_weekend") {
    return(list(
      recommendation = "sensitivity",
      rationale = "Binary calendar indicator with full coverage but non-continuous scale; useful for sensitivity checks, not as part of the preferred continuous PCA core."
    ))
  }

  if (variable_name %in% c("hour_sin", "hour_cos")) {
    return(list(
      recommendation = "main",
      rationale = "Preferred cyclical hour encoding with full coverage; preserves circular structure better than linear hour for exploratory redundancy analysis."
    ))
  }

  if (variable_name == "ocupacion") {
    return(list(
      recommendation = "main",
      rationale = sprintf(
        "Promising traffic-context variable with substantial variability; keep in the main set but note %.4f%% negative values for later data-quality review.",
        negative_pct
      )
    ))
  }

  if (variable_name == "intensidad") {
    return(list(
      recommendation = "main",
      rationale = sprintf(
        "Promising traffic-context variable with wide support and no negative values; suitable for the main exploratory PCA despite %.2f%% missingness.",
        missing_pct
      )
    ))
  }

  list(
    recommendation = "exclude",
    rationale = "No methodological basis was defined to keep this variable in the current exploratory PCA sets."
  )
}

rs_build_candidate_screening_table <- function(screening_base) {
  total_n <- nrow(screening_base)

  screening_rows <- lapply(seq_len(nrow(rs_m4_candidate_registry)), function(i) {
    variable_name <- rs_m4_candidate_registry$variable[i]
    variable_type <- rs_m4_candidate_registry$type[i]
    numeric_values <- rs_numericize_candidate(screening_base[[variable_name]])
    non_missing <- numeric_values[!is.na(numeric_values)]

    missing_n <- sum(is.na(numeric_values))
    missing_pct <- 100 * missing_n / total_n
    near_zero_variance_flag <- rs_near_zero_variance_flag(numeric_values)
    zero_pct <- rs_zero_pct(non_missing)
    negative_pct <- rs_negative_pct(non_missing)
    recommendation_info <- rs_recommend_candidate(
      variable_name = variable_name,
      near_zero_variance_flag = near_zero_variance_flag,
      missing_pct = missing_pct,
      negative_pct = negative_pct,
      zero_pct = zero_pct
    )

    tibble::tibble(
      variable = variable_name,
      type = variable_type,
      n = total_n,
      missing_n = missing_n,
      missing_pct = missing_pct,
      unique_n = length(unique(non_missing)),
      mean = if (length(non_missing) > 0L) mean(non_missing) else NA_real_,
      sd = if (length(non_missing) > 1L) stats::sd(non_missing) else NA_real_,
      min = if (length(non_missing) > 0L) min(non_missing) else NA_real_,
      p01 = rs_safe_quantile(non_missing, 0.01),
      p05 = rs_safe_quantile(non_missing, 0.05),
      p50 = rs_safe_quantile(non_missing, 0.50),
      p95 = rs_safe_quantile(non_missing, 0.95),
      p99 = rs_safe_quantile(non_missing, 0.99),
      max = if (length(non_missing) > 0L) max(non_missing) else NA_real_,
      zero_pct = zero_pct,
      negative_pct = negative_pct,
      near_zero_variance_flag = near_zero_variance_flag,
      recommendation = recommendation_info$recommendation,
      rationale = recommendation_info$rationale
    )
  })

  dplyr::bind_rows(screening_rows)
}

rs_set_methodological_comment <- function(set_name, set_variables, variable_screening) {
  variable_meta <- variable_screening |>
    dplyr::filter(variable %in% set_variables)

  sensitivity_variables <- variable_meta |>
    dplyr::filter(recommendation == "sensitivity") |>
    dplyr::pull(variable)
  excluded_variables <- variable_meta |>
    dplyr::filter(recommendation == "exclude") |>
    dplyr::pull(variable)

  if (set_name == "main_continuous") {
    return("Preferred baseline set: continuous/contextual block without binary calendar indicators and without vmed.")
  }

  if (set_name == "with_vmed") {
    return("Sensitivity set: tests whether vmed changes structure, but vmed remains under review and should not define the main PCA specification.")
  }

  if (set_name == "with_binary_calendar") {
    return("Calendar sensitivity set: adds binary indicators for exploratory stress-testing; interpretability is weaker than the main continuous block.")
  }

  if (length(excluded_variables) > 0L) {
    return(
      sprintf(
        "High-risk candidate set because it includes excluded variables (%s) plus sensitivity variables (%s). Use only to inspect robustness, not as the preferred PCA input.",
        paste(excluded_variables, collapse = ", "),
        paste(sensitivity_variables, collapse = ", ")
      )
    )
  }

  sprintf(
    "Sensitivity set including variables under special review: %s.",
    paste(sensitivity_variables, collapse = ", ")
  )
}

rs_build_set_screening_table <- function(screening_base, variable_screening) {
  total_n <- nrow(screening_base)

  screening_rows <- lapply(seq_len(nrow(rs_m4_set_registry)), function(i) {
    set_name <- rs_m4_set_registry$set_name[i]
    set_variables <- rs_m4_set_registry$variables[[i]]
    set_data <- screening_base[, set_variables, drop = FALSE]
    complete_cases_n <- sum(stats::complete.cases(set_data))
    dropped_n <- total_n - complete_cases_n

    tibble::tibble(
      set_name = set_name,
      variables = paste(set_variables, collapse = ", "),
      complete_cases_n = complete_cases_n,
      complete_cases_pct = 100 * complete_cases_n / total_n,
      dropped_n = dropped_n,
      dropped_pct = 100 * dropped_n / total_n,
      methodological_comment = rs_set_methodological_comment(set_name, set_variables, variable_screening)
    )
  })

  dplyr::bind_rows(screening_rows)
}

rs_build_continuous_correlation_matrix <- function(screening_base) {
  correlation_variables <- c("intensidad", "ocupacion", "hour_sin", "hour_cos")
  correlation_data <- screening_base[, correlation_variables, drop = FALSE]
  complete_cases <- stats::complete.cases(correlation_data)
  matrix_values <- stats::cor(correlation_data[complete_cases, , drop = FALSE], use = "pairwise.complete.obs")
  correlation_matrix <- as.data.frame(matrix_values)
  correlation_matrix <- tibble::rownames_to_column(correlation_matrix, var = "variable")

  list(
    matrix = correlation_matrix,
    matrix_values = matrix_values
  )
}

rs_build_vmed_profile <- function(screening_base) {
  vmed_values <- rs_numericize_candidate(screening_base$vmed)
  non_missing <- vmed_values[!is.na(vmed_values)]
  reference_variables <- c("intensidad", "ocupacion", "hour_sin", "hour_cos")
  correlation_rows <- lapply(reference_variables, function(reference_variable) {
    reference_values <- rs_numericize_candidate(screening_base[[reference_variable]])
    usable_rows <- !is.na(vmed_values) & !is.na(reference_values)

    tibble::tibble(
      reference_variable = reference_variable,
      pair_complete_n = sum(usable_rows),
      pearson_correlation = if (sum(usable_rows) > 1L) stats::cor(vmed_values[usable_rows], reference_values[usable_rows]) else NA_real_
    )
  })

  list(
    profile = tibble::tibble(
      variable = "vmed",
      n = nrow(screening_base),
      missing_n = sum(is.na(vmed_values)),
      missing_pct = 100 * mean(is.na(vmed_values)),
      unique_n = length(unique(non_missing)),
      zero_pct = rs_zero_pct(non_missing),
      negative_pct = rs_negative_pct(non_missing),
      positive_pct = if (length(non_missing) > 0L) mean(non_missing > sqrt(.Machine$double.eps)) * 100 else NA_real_,
      mean = if (length(non_missing) > 0L) mean(non_missing) else NA_real_,
      sd = if (length(non_missing) > 1L) stats::sd(non_missing) else NA_real_,
      min = if (length(non_missing) > 0L) min(non_missing) else NA_real_,
      p50 = rs_safe_quantile(non_missing, 0.50),
      p95 = rs_safe_quantile(non_missing, 0.95),
      p99 = rs_safe_quantile(non_missing, 0.99),
      max = if (length(non_missing) > 0L) max(non_missing) else NA_real_,
      recommendation = "sensitivity",
      rationale = "Known noisy variable with heavy zero inflation and small negative tail; retain only for sensitivity analyses."
    ),
    correlations = dplyr::bind_rows(correlation_rows)
  )
}

rs_build_yearly_candidate_summary <- function(screening_base) {
  candidate_variables <- rs_m4_candidate_registry$variable
  screening_with_year <- screening_base |>
    dplyr::mutate(year = lubridate::year(fecha))

  yearly_rows <- lapply(candidate_variables, function(variable_name) {
    numeric_values <- rs_numericize_candidate(screening_with_year[[variable_name]])

    screening_with_year |>
      dplyr::mutate(.candidate_value = numeric_values) |>
      dplyr::group_by(year) |>
      dplyr::summarise(
        variable = variable_name,
        n = dplyr::n(),
        missing_n = sum(is.na(.candidate_value)),
        missing_pct = 100 * mean(is.na(.candidate_value)),
        unique_n = dplyr::n_distinct(.candidate_value, na.rm = TRUE),
        mean = mean(.candidate_value, na.rm = TRUE),
        sd = stats::sd(.candidate_value, na.rm = TRUE),
        p50 = rs_safe_quantile(.candidate_value[!is.na(.candidate_value)], 0.50),
        p95 = rs_safe_quantile(.candidate_value[!is.na(.candidate_value)], 0.95),
        zero_pct = rs_zero_pct(.candidate_value[!is.na(.candidate_value)]),
        .groups = "drop"
      )
  })

  dplyr::bind_rows(yearly_rows) |>
    dplyr::arrange(variable, year)
}

rs_build_yearly_set_retention <- function(screening_base) {
  screening_with_year <- screening_base |>
    dplyr::mutate(year = lubridate::year(fecha))

  retention_rows <- lapply(seq_len(nrow(rs_m4_set_registry)), function(i) {
    set_name <- rs_m4_set_registry$set_name[i]
    set_variables <- rs_m4_set_registry$variables[[i]]

    screening_with_year |>
      dplyr::group_by(year) |>
      dplyr::summarise(
        set_name = set_name,
        total_n = dplyr::n(),
        complete_cases_n = sum(stats::complete.cases(dplyr::pick(dplyr::all_of(set_variables)))),
        complete_cases_pct = 100 * complete_cases_n / total_n,
        dropped_n = total_n - complete_cases_n,
        dropped_pct = 100 * dropped_n / total_n,
        .groups = "drop"
      )
  })

  dplyr::bind_rows(retention_rows) |>
    dplyr::arrange(set_name, year)
}

rs_build_temporal_comparability_overview <- function(yearly_candidate_summary) {
  yearly_candidate_summary |>
    dplyr::group_by(variable) |>
    dplyr::summarise(
      years_present = dplyr::n_distinct(year),
      missing_pct_min = min(missing_pct, na.rm = TRUE),
      missing_pct_max = max(missing_pct, na.rm = TRUE),
      missing_pct_range = missing_pct_max - missing_pct_min,
      p50_min = min(p50, na.rm = TRUE),
      p50_max = max(p50, na.rm = TRUE),
      p50_range = p50_max - p50_min,
      mean_min = min(mean, na.rm = TRUE),
      mean_max = max(mean, na.rm = TRUE),
      mean_range = mean_max - mean_min,
      .groups = "drop"
    ) |>
    dplyr::mutate(
      comparability_note = dplyr::case_when(
        variable == "vmed" ~ "Variable under review; inspect temporal behavior separately before using it outside sensitivity checks.",
        variable == "es_festivo" ~ "Rare binary flag; temporal comparability depends more on coding and calendar composition than on continuous scale shifts.",
        missing_pct_range > 10 ~ "Temporal coverage changes materially across years; consider a more comparable time segment before PCA.",
        variable %in% c("intensidad", "ocupacion") & p50_range > 500 ~ "Traffic-level medians shift substantially by year; compare whole-period PCA against a more comparable temporal subset.",
        TRUE ~ "No obvious temporal breakdown from this screening alone, but yearly summaries should still be reviewed before committing to whole-period PCA."
      )
    ) |>
    dplyr::arrange(variable)
}

rs_build_m4_validation_summary <- function(screening_base, pca_base, variable_screening, set_screening, temporal_comparability_overview) {
  screening_id_matches_pca_base <- identical(
    screening_base |>
      dplyr::arrange(num_expediente) |>
      dplyr::pull(num_expediente),
    pca_base |>
      dplyr::arrange(num_expediente) |>
      dplyr::pull(num_expediente)
  )

  tibble::tibble(
    metric = c(
      "screening_source",
      "screening_n",
      "pca_base_n",
      "screening_n_matches_pca_base",
      "screening_id_matches_pca_base",
      "candidate_variables_screened",
      "pca_sets_screened",
      "vmed_recommendation",
      "main_set_complete_cases_n",
      "main_set_complete_cases_pct",
      "temporal_warning_variables_n"
    ),
    value = c(
      "tabla_accidente_master filtered by pca_initial_eligible",
      as.character(nrow(screening_base)),
      as.character(nrow(pca_base)),
      as.character(nrow(screening_base) == nrow(pca_base)),
      as.character(screening_id_matches_pca_base),
      as.character(nrow(variable_screening)),
      as.character(nrow(set_screening)),
      variable_screening$recommendation[variable_screening$variable == "vmed"],
      as.character(set_screening$complete_cases_n[set_screening$set_name == "main_continuous"]),
      as.character(set_screening$complete_cases_pct[set_screening$set_name == "main_continuous"]),
      as.character(sum(grepl("consider a more comparable time segment|compare whole-period PCA against a more comparable temporal subset", temporal_comparability_overview$comparability_note)))
    )
  )
}

rs_plot_candidate_missingness <- function(variable_screening, paths) {
  plot_data <- variable_screening |>
    dplyr::mutate(variable = stats::reorder(variable, missing_pct))

  plot_object <- ggplot2::ggplot(plot_data, ggplot2::aes(x = variable, y = missing_pct, fill = recommendation)) +
    ggplot2::geom_col() +
    ggplot2::coord_flip() +
    ggplot2::labs(
      title = "M4 candidate screening: missingness by variable",
      x = "Variable",
      y = "Missing pct"
    ) +
    ggplot2::theme_minimal()

  ggplot2::ggsave(
    filename = file.path(paths$output_plots, "m4_candidate_missing_pct.png"),
    plot = plot_object,
    width = 9,
    height = 5,
    dpi = 150
  )
}

rs_plot_set_retention <- function(set_screening, paths) {
  plot_data <- set_screening |>
    dplyr::mutate(set_name = stats::reorder(set_name, complete_cases_pct))

  plot_object <- ggplot2::ggplot(plot_data, ggplot2::aes(x = set_name, y = complete_cases_pct, fill = set_name)) +
    ggplot2::geom_col(show.legend = FALSE) +
    ggplot2::coord_flip() +
    ggplot2::labs(
      title = "M4 PCA set screening: complete-case retention",
      x = "Set",
      y = "Complete cases pct"
    ) +
    ggplot2::theme_minimal()

  ggplot2::ggsave(
    filename = file.path(paths$output_plots, "m4_pca_set_complete_cases_pct.png"),
    plot = plot_object,
    width = 9,
    height = 5,
    dpi = 150
  )
}

rs_plot_continuous_correlation_heatmap <- function(correlation_matrix_values, paths) {
  heatmap_data <- as.data.frame(as.table(correlation_matrix_values))
  names(heatmap_data) <- c("variable_x", "variable_y", "correlation")

  plot_object <- ggplot2::ggplot(heatmap_data, ggplot2::aes(x = variable_x, y = variable_y, fill = correlation)) +
    ggplot2::geom_tile() +
    ggplot2::geom_text(ggplot2::aes(label = sprintf("%.2f", correlation)), size = 3) +
    ggplot2::scale_fill_gradient2(low = "#b2182b", mid = "#f7f7f7", high = "#2166ac", midpoint = 0, limits = c(-1, 1)) +
    ggplot2::labs(
      title = "M4 continuous block correlation matrix",
      x = NULL,
      y = NULL
    ) +
    ggplot2::theme_minimal()

  ggplot2::ggsave(
    filename = file.path(paths$output_plots, "m4_continuous_correlation_heatmap.png"),
    plot = plot_object,
    width = 6,
    height = 5,
    dpi = 150
  )
}

rs_plot_yearly_missingness <- function(yearly_candidate_summary, paths) {
  plot_object <- ggplot2::ggplot(
    yearly_candidate_summary,
    ggplot2::aes(x = year, y = missing_pct, color = variable)
  ) +
    ggplot2::geom_line(linewidth = 0.8) +
    ggplot2::geom_point(size = 1.5) +
    ggplot2::labs(
      title = "M4 yearly missingness profile for PCA candidates",
      x = "Year",
      y = "Missing pct"
    ) +
    ggplot2::theme_minimal()

  ggplot2::ggsave(
    filename = file.path(paths$output_plots, "m4_yearly_missing_pct_candidates.png"),
    plot = plot_object,
    width = 9,
    height = 5,
    dpi = 150
  )
}

rs_plot_vmed_distribution <- function(screening_base, paths) {
  plot_data <- screening_base |>
    dplyr::filter(!is.na(vmed))

  plot_object <- ggplot2::ggplot(plot_data, ggplot2::aes(x = vmed)) +
    ggplot2::geom_histogram(bins = 60, fill = "#4c78a8", color = "white") +
    ggplot2::coord_cartesian(xlim = c(stats::quantile(plot_data$vmed, 0.01), stats::quantile(plot_data$vmed, 0.99))) +
    ggplot2::labs(
      title = "M4 vmed profile: central distribution (1st-99th pct window)",
      x = "vmed",
      y = "Count"
    ) +
    ggplot2::theme_minimal()

  ggplot2::ggsave(
    filename = file.path(paths$output_plots, "m4_vmed_distribution.png"),
    plot = plot_object,
    width = 8,
    height = 5,
    dpi = 150
  )
}

rs_run_m4_screening_pca <- function(accident_master, pca_base, paths) {
  rs_check_m4_packages()
  rs_validate_m4_inputs(accident_master, pca_base)

  screening_base <- rs_build_m4_screening_base(accident_master)
  rs_validate_m4_screening_base(screening_base, pca_base)

  variable_screening <- rs_build_candidate_screening_table(screening_base)
  set_screening <- rs_build_set_screening_table(screening_base, variable_screening)
  continuous_correlation <- rs_build_continuous_correlation_matrix(screening_base)
  vmed_profile <- rs_build_vmed_profile(screening_base)
  yearly_candidate_summary <- rs_build_yearly_candidate_summary(screening_base)
  yearly_set_retention <- rs_build_yearly_set_retention(screening_base)
  temporal_comparability_overview <- rs_build_temporal_comparability_overview(yearly_candidate_summary)
  validation_summary <- rs_build_m4_validation_summary(
    screening_base = screening_base,
    pca_base = pca_base,
    variable_screening = variable_screening,
    set_screening = set_screening,
    temporal_comparability_overview = temporal_comparability_overview
  )

  readr::write_csv(
    variable_screening,
    file.path(paths$output_tables, "m4_candidate_variable_screening.csv")
  )
  readr::write_csv(
    set_screening,
    file.path(paths$output_tables, "m4_pca_set_screening.csv")
  )
  readr::write_csv(
    continuous_correlation$matrix,
    file.path(paths$output_tables, "m4_continuous_correlation_matrix.csv")
  )
  readr::write_csv(
    vmed_profile$profile,
    file.path(paths$output_tables, "m4_vmed_profile.csv")
  )
  readr::write_csv(
    vmed_profile$correlations,
    file.path(paths$output_tables, "m4_vmed_correlations.csv")
  )
  readr::write_csv(
    yearly_candidate_summary,
    file.path(paths$output_tables, "m4_yearly_candidate_summary.csv")
  )
  readr::write_csv(
    yearly_set_retention,
    file.path(paths$output_tables, "m4_yearly_pca_set_retention.csv")
  )
  readr::write_csv(
    temporal_comparability_overview,
    file.path(paths$output_tables, "m4_temporal_comparability_overview.csv")
  )
  readr::write_csv(
    validation_summary,
    file.path(paths$output_tables, "m4_validation_summary.csv")
  )

  rs_plot_candidate_missingness(variable_screening, paths)
  rs_plot_set_retention(set_screening, paths)
  rs_plot_continuous_correlation_heatmap(continuous_correlation$matrix_values, paths)
  rs_plot_yearly_missingness(yearly_candidate_summary, paths)
  rs_plot_vmed_distribution(screening_base, paths)

  list(
    screening_base = screening_base,
    variable_screening = variable_screening,
    set_screening = set_screening,
    continuous_correlation = continuous_correlation$matrix,
    vmed_profile = vmed_profile$profile,
    yearly_candidate_summary = yearly_candidate_summary,
    yearly_set_retention = yearly_set_retention,
    temporal_comparability_overview = temporal_comparability_overview,
    validation_summary = validation_summary
  )
}
