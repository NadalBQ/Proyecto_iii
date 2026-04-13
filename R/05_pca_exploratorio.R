rs_m5_recent_year_min <- 2020L
rs_m5_recent_year_max <- 2024L

rs_m5_run_registry <- tibble::tibble(
  run_name = c(
    "baseline_recent",
    "baseline_full_period",
    "with_vmed_recent",
    "with_weekend_recent"
  ),
  period_used = c(
    "2020-2024",
    "2016-2024",
    "2020-2024",
    "2020-2024"
  ),
  variables = list(
    c("intensidad", "ocupacion", "hour_sin", "hour_cos"),
    c("intensidad", "ocupacion", "hour_sin", "hour_cos"),
    c("intensidad", "ocupacion", "hour_sin", "hour_cos", "vmed"),
    c("intensidad", "ocupacion", "hour_sin", "hour_cos", "is_weekend")
  )
)

rs_check_m5_packages <- function() {
  required_packages <- c("dplyr", "tibble", "readr", "ggplot2", "lubridate")
  missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]

  if (length(missing_packages) > 0) {
    stop(
      sprintf(
        "Faltan paquetes requeridos para M5: %s",
        paste(missing_packages, collapse = ", ")
      ),
      call. = FALSE
    )
  }
}

rs_validate_m5_inputs <- function(screening_base) {
  required_columns <- c(
    "num_expediente",
    "fecha",
    "intensidad",
    "ocupacion",
    "hour_sin",
    "hour_cos",
    "vmed",
    "is_weekend"
  )

  missing_columns <- setdiff(required_columns, names(screening_base))

  if (length(missing_columns) > 0L) {
    stop(
      sprintf(
        "Faltan columnas requeridas para M5: %s",
        paste(missing_columns, collapse = ", ")
      ),
      call. = FALSE
    )
  }
}

rs_parse_m5_year <- function(fecha_values) {
  parsed_fecha <- rs_parse_m4_fecha(fecha_values)
  lubridate::year(parsed_fecha)
}

rs_prepare_m5_screening_base <- function(screening_base) {
  screening_base |>
    dplyr::mutate(
      year = rs_parse_m5_year(fecha)
    )
}

rs_filter_m5_period <- function(screening_base, period_used) {
  if (period_used == "2020-2024") {
    return(
      screening_base |>
        dplyr::filter(!is.na(year), year >= rs_m5_recent_year_min, year <= rs_m5_recent_year_max)
    )
  }

  screening_base |>
    dplyr::filter(!is.na(year))
}

rs_extract_m5_complete_cases <- function(filtered_data, variables) {
  run_data <- filtered_data |>
    dplyr::select(num_expediente, year, dplyr::all_of(variables))

  complete_case_mask <- stats::complete.cases(run_data[, variables, drop = FALSE])

  list(
    all_rows_n = nrow(run_data),
    complete_case_rows_n = sum(complete_case_mask),
    run_data = run_data[complete_case_mask, , drop = FALSE]
  )
}

rs_build_m5_eigen_table <- function(pca_result) {
  eigenvalues <- pca_result$sdev ^ 2
  variance_pct <- 100 * eigenvalues / sum(eigenvalues)
  cumulative_variance_pct <- cumsum(variance_pct)

  tibble::tibble(
    component = paste0("PC", seq_along(eigenvalues)),
    eigenvalue = eigenvalues,
    variance_pct = variance_pct,
    cumulative_variance_pct = cumulative_variance_pct
  )
}

rs_build_m5_loadings_table <- function(pca_result) {
  loadings <- as.data.frame(pca_result$rotation)
  loadings <- tibble::rownames_to_column(loadings, var = "variable")
  tibble::as_tibble(loadings)
}

rs_build_m5_variable_coordinates <- function(pca_result) {
  coords <- sweep(pca_result$rotation, 2, pca_result$sdev, "*")
  coords <- as.data.frame(coords)
  coords <- tibble::rownames_to_column(coords, var = "variable")
  tibble::as_tibble(coords)
}

rs_build_m5_contrib_table <- function(pca_result) {
  contributions <- 100 * (pca_result$rotation ^ 2)
  contributions <- as.data.frame(contributions)
  contributions <- tibble::rownames_to_column(contributions, var = "variable")
  tibble::as_tibble(contributions)
}

rs_build_m5_cos2_table <- function(pca_result) {
  coords_matrix <- sweep(pca_result$rotation, 2, pca_result$sdev, "*")
  row_norms <- rowSums(coords_matrix ^ 2)
  cos2 <- coords_matrix ^ 2 / row_norms
  cos2 <- as.data.frame(cos2)
  cos2 <- tibble::rownames_to_column(cos2, var = "variable")
  tibble::as_tibble(cos2)
}

rs_build_m5_scores_table <- function(pca_result, run_data) {
  scores <- as.data.frame(pca_result$x)
  scores <- tibble::rownames_to_column(scores, var = "row_id")
  tibble::as_tibble(scores) |>
    dplyr::mutate(
      num_expediente = run_data$num_expediente,
      year = run_data$year,
      .before = 1L
    ) |>
    dplyr::select(-row_id)
}

rs_get_m5_top_variables <- function(table_df, component_name, top_n = 2L) {
  table_df |>
    dplyr::transmute(variable, value = abs(.data[[component_name]])) |>
    dplyr::arrange(dplyr::desc(value), variable) |>
    dplyr::slice_head(n = top_n) |>
    dplyr::pull(variable)
}

rs_build_m5_run_note <- function(contributions_table, run_name) {
  pc1_top <- rs_get_m5_top_variables(contributions_table, "PC1", top_n = 2L)
  pc2_top <- rs_get_m5_top_variables(contributions_table, "PC2", top_n = 2L)

  sprintf(
    "%s: PC1 queda dominado por %s; PC2 queda dominado por %s. Interpretar como estructura latente/redundancia, no como escala directa de riesgo.",
    run_name,
    paste(pc1_top, collapse = " + "),
    paste(pc2_top, collapse = " + ")
  )
}

rs_plot_m5_scree <- function(eigen_table, run_name, paths) {
  plot_data <- eigen_table |>
    dplyr::mutate(component = factor(component, levels = component))

  plot_object <- ggplot2::ggplot(plot_data, ggplot2::aes(x = component, y = variance_pct)) +
    ggplot2::geom_col(fill = "#4c78a8") +
    ggplot2::geom_line(ggplot2::aes(y = cumulative_variance_pct, group = 1), color = "#d62728") +
    ggplot2::geom_point(ggplot2::aes(y = cumulative_variance_pct), color = "#d62728", size = 2) +
    ggplot2::labs(
      title = sprintf("M5 scree plot - %s", run_name),
      x = "Componente",
      y = "Varianza explicada (%)"
    ) +
    ggplot2::theme_minimal()

  ggplot2::ggsave(
    filename = file.path(paths$output_plots, sprintf("m5_%s_scree_plot.png", run_name)),
    plot = plot_object,
    width = 7,
    height = 5,
    dpi = 150
  )
}

rs_plot_m5_correlation_circle <- function(variable_coordinates, run_name, paths) {
  plot_data <- variable_coordinates |>
    dplyr::select(variable, PC1, PC2)

  circle_points <- tibble::tibble(
    angle = seq(0, 2 * pi, length.out = 500)
  ) |>
    dplyr::mutate(x = cos(angle), y = sin(angle))

  plot_object <- ggplot2::ggplot() +
    ggplot2::geom_path(
      data = circle_points,
      ggplot2::aes(x = x, y = y),
      color = "grey70"
    ) +
    ggplot2::geom_hline(yintercept = 0, color = "grey85") +
    ggplot2::geom_vline(xintercept = 0, color = "grey85") +
    ggplot2::geom_segment(
      data = plot_data,
      ggplot2::aes(x = 0, y = 0, xend = PC1, yend = PC2),
      arrow = ggplot2::arrow(length = grid::unit(0.18, "cm")),
      color = "#2166ac"
    ) +
    ggplot2::geom_text(
      data = plot_data,
      ggplot2::aes(x = PC1, y = PC2, label = variable),
      size = 3,
      vjust = -0.4
    ) +
    ggplot2::coord_equal(xlim = c(-1.1, 1.1), ylim = c(-1.1, 1.1)) +
    ggplot2::labs(
      title = sprintf("M5 correlation circle - %s", run_name),
      x = "PC1",
      y = "PC2"
    ) +
    ggplot2::theme_minimal()

  ggplot2::ggsave(
    filename = file.path(paths$output_plots, sprintf("m5_%s_correlation_circle.png", run_name)),
    plot = plot_object,
    width = 6,
    height = 6,
    dpi = 150
  )
}

rs_plot_m5_biplot <- function(pca_result, variable_coordinates, run_data, run_name, paths) {
  scores <- as.data.frame(pca_result$x[, c("PC1", "PC2"), drop = FALSE])
  scores$num_expediente <- run_data$num_expediente
  scores$year <- run_data$year

  if (nrow(scores) > 3000L) {
    set.seed(42)
    sample_idx <- sort(sample.int(nrow(scores), 3000L))
    scores_plot <- scores[sample_idx, , drop = FALSE]
  } else {
    scores_plot <- scores
  }

  variable_plot <- variable_coordinates |>
    dplyr::select(variable, PC1, PC2)

  score_range <- max(abs(c(scores_plot$PC1, scores_plot$PC2)))
  variable_range <- max(abs(c(variable_plot$PC1, variable_plot$PC2)))
  arrow_scale <- if (variable_range == 0) 1 else 0.7 * score_range / variable_range

  variable_plot <- variable_plot |>
    dplyr::mutate(
      xend = PC1 * arrow_scale,
      yend = PC2 * arrow_scale
    )

  plot_object <- ggplot2::ggplot(scores_plot, ggplot2::aes(x = PC1, y = PC2)) +
    ggplot2::geom_point(alpha = 0.18, size = 0.7, color = "#4c78a8") +
    ggplot2::geom_segment(
      data = variable_plot,
      ggplot2::aes(x = 0, y = 0, xend = xend, yend = yend),
      inherit.aes = FALSE,
      arrow = ggplot2::arrow(length = grid::unit(0.18, "cm")),
      color = "#d62728"
    ) +
    ggplot2::geom_text(
      data = variable_plot,
      ggplot2::aes(x = xend, y = yend, label = variable),
      inherit.aes = FALSE,
      color = "#d62728",
      size = 3,
      vjust = -0.4
    ) +
    ggplot2::labs(
      title = sprintf("M5 biplot - %s", run_name),
      subtitle = if (nrow(scores) > nrow(scores_plot)) "Individuals downsampled to 3000 points for readability" else NULL,
      x = "PC1 scores",
      y = "PC2 scores"
    ) +
    ggplot2::theme_minimal()

  ggplot2::ggsave(
    filename = file.path(paths$output_plots, sprintf("m5_%s_biplot.png", run_name)),
    plot = plot_object,
    width = 7,
    height = 6,
    dpi = 150
  )
}

rs_prepare_m5_comparison_matrix <- function(variable_coordinates, common_variables) {
  variable_coordinates |>
    dplyr::filter(variable %in% common_variables) |>
    dplyr::arrange(match(variable, common_variables)) |>
    dplyr::select(PC1, PC2) |>
    as.matrix()
}

rs_align_m5_first_two_dims <- function(reference_matrix, target_matrix) {
  candidate_matrices <- list(
    target_matrix,
    target_matrix %*% diag(c(-1, 1)),
    target_matrix %*% diag(c(1, -1)),
    target_matrix %*% diag(c(-1, -1)),
    target_matrix[, c(2, 1), drop = FALSE],
    target_matrix[, c(2, 1), drop = FALSE] %*% diag(c(-1, 1)),
    target_matrix[, c(2, 1), drop = FALSE] %*% diag(c(1, -1)),
    target_matrix[, c(2, 1), drop = FALSE] %*% diag(c(-1, -1))
  )

  distances <- vapply(
    candidate_matrices,
    function(candidate) mean(abs(reference_matrix - candidate)),
    numeric(1)
  )

  best_idx <- which.min(distances)

  list(
    aligned_matrix = candidate_matrices[[best_idx]],
    mean_abs_diff = distances[[best_idx]]
  )
}

rs_compare_m5_runs <- function(run_outputs, run_summary) {
  baseline_recent_coords <- run_outputs[["baseline_recent"]]$variable_coordinates
  baseline_full_coords <- run_outputs[["baseline_full_period"]]$variable_coordinates
  with_vmed_coords <- run_outputs[["with_vmed_recent"]]$variable_coordinates
  with_weekend_coords <- run_outputs[["with_weekend_recent"]]$variable_coordinates

  baseline_common_vars <- c("intensidad", "ocupacion", "hour_sin", "hour_cos")

  baseline_recent_matrix <- rs_prepare_m5_comparison_matrix(baseline_recent_coords, baseline_common_vars)
  baseline_full_matrix <- rs_prepare_m5_comparison_matrix(baseline_full_coords, baseline_common_vars)
  with_vmed_matrix <- rs_prepare_m5_comparison_matrix(with_vmed_coords, baseline_common_vars)
  with_weekend_matrix <- rs_prepare_m5_comparison_matrix(with_weekend_coords, baseline_common_vars)

  full_alignment <- rs_align_m5_first_two_dims(baseline_recent_matrix, baseline_full_matrix)
  vmed_alignment <- rs_align_m5_first_two_dims(baseline_recent_matrix, with_vmed_matrix)
  weekend_alignment <- rs_align_m5_first_two_dims(baseline_recent_matrix, with_weekend_matrix)

  recent_contrib <- run_outputs[["baseline_recent"]]$contributions
  recent_loadings <- run_outputs[["baseline_recent"]]$loadings
  with_vmed_contrib <- run_outputs[["with_vmed_recent"]]$contributions
  with_weekend_contrib <- run_outputs[["with_weekend_recent"]]$contributions

  traffic_same_block <- {
    traffic_primary_components <- recent_contrib |>
      dplyr::filter(variable %in% c("intensidad", "ocupacion")) |>
      dplyr::transmute(
        variable,
        primary_component = dplyr::case_when(
          abs(PC1) >= abs(PC2) ~ "PC1",
          TRUE ~ "PC2"
        )
      )

    length(unique(traffic_primary_components$primary_component)) == 1L
  }

  temporal_primary <- recent_contrib |>
    dplyr::filter(variable %in% c("hour_sin", "hour_cos")) |>
    dplyr::transmute(
      variable,
      primary_component = dplyr::case_when(
        abs(PC1) >= abs(PC2) ~ "PC1",
        TRUE ~ "PC2"
      )
    )

  temporal_clear <- length(unique(temporal_primary$primary_component)) <= 2L

  baseline_variance <- run_summary |>
    dplyr::filter(run_name == "baseline_recent") |>
    dplyr::pull(cumulative_variance_pc1_pc2)
  full_variance <- run_summary |>
    dplyr::filter(run_name == "baseline_full_period") |>
    dplyr::pull(cumulative_variance_pc1_pc2)
  vmed_variance <- run_summary |>
    dplyr::filter(run_name == "with_vmed_recent") |>
    dplyr::pull(cumulative_variance_pc1_pc2)
  weekend_variance <- run_summary |>
    dplyr::filter(run_name == "with_weekend_recent") |>
    dplyr::pull(cumulative_variance_pc1_pc2)

  vmed_loading <- with_vmed_contrib |>
    dplyr::filter(variable == "vmed") |>
    dplyr::select(PC1, PC2) |>
    as.list()

  weekend_loading <- with_weekend_contrib |>
    dplyr::filter(variable == "is_weekend") |>
    dplyr::select(PC1, PC2) |>
    as.list()

  comparison_table <- tibble::tribble(
    ~question, ~answer, ~evidence,
    "intensidad_y_ocupacion_mismo_bloque",
    if (traffic_same_block) "Sí, forman un bloque compartido en la corrida baseline_recent y siguen anclando la misma subestructura en las sensibilidades." else "No de forma nítida; el acoplamiento entre intensidad y ocupacion cambia entre componentes.",
    sprintf(
      "baseline_recent: contribuciones PC1/PC2 -> intensidad (%.3f, %.3f), ocupacion (%.3f, %.3f).",
      recent_contrib$PC1[recent_contrib$variable == "intensidad"],
      recent_contrib$PC2[recent_contrib$variable == "intensidad"],
      recent_contrib$PC1[recent_contrib$variable == "ocupacion"],
      recent_contrib$PC2[recent_contrib$variable == "ocupacion"]
    ),
    "hour_sin_y_hour_cos_eje_temporal_claro",
    if (temporal_clear) "Sí, hour_sin y hour_cos estructuran el subespacio temporal del plano principal, aunque no deben leerse como una sola variable lineal." else "La estructura temporal aparece, pero no domina de forma consistente el plano principal.",
    sprintf(
      "baseline_recent: contribuciones PC1/PC2 -> hour_sin (%.3f, %.3f), hour_cos (%.3f, %.3f).",
      recent_contrib$PC1[recent_contrib$variable == "hour_sin"],
      recent_contrib$PC2[recent_contrib$variable == "hour_sin"],
      recent_contrib$PC1[recent_contrib$variable == "hour_cos"],
      recent_contrib$PC2[recent_contrib$variable == "hour_cos"]
    ),
    "cambio_al_anadir_vmed",
    dplyr::case_when(
      vmed_alignment$mean_abs_diff < 0.10 ~ "El cambio al añadir vmed es pequeño; la estructura principal de las variables baseline se mantiene y vmed actúa como sensibilidad acoplada sobre todo al bloque de trafico.",
      vmed_alignment$mean_abs_diff < 0.20 ~ "El cambio al añadir vmed es moderado; conviene mantenerlo como sensibilidad y no como parte del baseline.",
      TRUE ~ "El cambio al añadir vmed es material; refuerza que vmed no debe entrar en el baseline."
    ),
    sprintf(
      "mean_abs_diff vs baseline_recent = %.3f; variance PC1+PC2 pasa de %.2f%% a %.2f%%; contribucion de vmed en PC1/PC2 = %.3f / %.3f.",
      vmed_alignment$mean_abs_diff,
      baseline_variance,
      vmed_variance,
      vmed_loading$PC1,
      vmed_loading$PC2
    ),
    "cambio_al_anadir_is_weekend",
    dplyr::case_when(
      weekend_alignment$mean_abs_diff < 0.10 ~ "El cambio al añadir is_weekend es pequeño; sirve como sensibilidad, pero no reconfigura el bloque principal.",
      weekend_alignment$mean_abs_diff < 0.20 ~ "El cambio al añadir is_weekend es moderado; util para contraste, no para el baseline.",
      TRUE ~ "El cambio al añadir is_weekend es material; revisar si el eje temporal se deforma demasiado con esta binaria."
    ),
    sprintf(
      "mean_abs_diff vs baseline_recent = %.3f; variance PC1+PC2 pasa de %.2f%% a %.2f%%; contribucion de is_weekend en PC1/PC2 = %.3f / %.3f.",
      weekend_alignment$mean_abs_diff,
      baseline_variance,
      weekend_variance,
      weekend_loading$PC1,
      weekend_loading$PC2
    ),
    "diferencia_periodo_completo_vs_reciente",
    dplyr::case_when(
      full_alignment$mean_abs_diff < 0.10 ~ "La estructura del periodo completo se parece mucho a la reciente, aunque se mantiene la preferencia metodologica por el tramo 2020-2024.",
      full_alignment$mean_abs_diff < 0.20 ~ "La estructura del periodo completo cambia de forma moderada respecto al tramo reciente; esto justifica priorizar 2020-2024 como baseline.",
      TRUE ~ "La estructura del periodo completo difiere de forma clara respecto al tramo reciente; no conviene usar ambos periodos como si fueran plenamente comparables."
    ),
    sprintf(
      "mean_abs_diff baseline_recent vs baseline_full_period = %.3f; variance PC1+PC2 pasa de %.2f%% a %.2f%%.",
      full_alignment$mean_abs_diff,
      baseline_variance,
      full_variance
    )
  )

  technical_note_lines <- c(
    "# M5 - Nota Tecnica ROAD-SAFETY",
    "",
    sprintf(
      "- El baseline principal se ejecuta sobre 2020-2024 con `%s`.",
      paste(rs_m5_run_registry$variables[[1]], collapse = ", ")
    ),
    "- El PCA se ha usado como detector exploratorio de redundancias y bloques latentes, no como definicion final de riesgo.",
    if (traffic_same_block) {
      "- `intensidad` y `ocupacion` aparecen como un bloque de trafico/condicion de circulacion suficientemente proximo como para evitar sobreponderarlas juntas sin control."
    } else {
      "- `intensidad` y `ocupacion` no quedan totalmente fundidas en un unico eje, pero siguen siendo variables vecinas que no conviene sumar a ciegas."
    },
    "- `hour_sin` y `hour_cos` estructuran el bloque temporal; deben tratarse como codificacion conjunta del ciclo horario y no como dos senales independientes a sobreponderar por separado.",
    "- `vmed` modifica la estructura solo como sensibilidad y permanece bajo revision metodologica; no debe entrar en el baseline del indice.",
    "- `is_weekend` puede servir para contraste, pero su papel es de sensibilidad y no de nucleo del bloque continuo principal.",
    "- Para el indice futuro, la traduccion razonable es trabajar por bloques interpretables: bloque de trafico (`intensidad`, `ocupacion`), bloque temporal (hora codificada en seno/coseno) y variables bajo revision aparte.",
    "- Una implementacion posterior del indice deberia evitar sumar con peso pleno variables del mismo bloque sin una regla explicita de control de redundancia."
  )

  list(
    comparison_table = comparison_table,
    technical_note_lines = technical_note_lines
  )
}

rs_run_single_m5_pca <- function(run_name, period_used, variables, screening_base, paths) {
  period_data <- rs_filter_m5_period(screening_base, period_used)
  complete_case_result <- rs_extract_m5_complete_cases(period_data, variables)
  run_data <- complete_case_result$run_data

  if (nrow(run_data) < 10L) {
    stop(
      sprintf("La corrida %s no tiene suficientes casos completos para PCA.", run_name),
      call. = FALSE
    )
  }

  pca_input <- run_data[, variables, drop = FALSE]
  pca_result <- stats::prcomp(pca_input, center = TRUE, scale. = TRUE)

  eigen_table <- rs_build_m5_eigen_table(pca_result)
  loadings_table <- rs_build_m5_loadings_table(pca_result)
  variable_coordinates <- rs_build_m5_variable_coordinates(pca_result)
  contributions_table <- rs_build_m5_contrib_table(pca_result)
  cos2_table <- rs_build_m5_cos2_table(pca_result)
  scores_table <- rs_build_m5_scores_table(pca_result, run_data)
  run_note <- rs_build_m5_run_note(contributions_table, run_name)

  readr::write_csv(
    eigen_table,
    file.path(paths$output_tables, sprintf("m5_%s_eigenvalues.csv", run_name))
  )
  readr::write_csv(
    loadings_table,
    file.path(paths$output_tables, sprintf("m5_%s_loadings.csv", run_name))
  )
  readr::write_csv(
    contributions_table,
    file.path(paths$output_tables, sprintf("m5_%s_contributions.csv", run_name))
  )
  readr::write_csv(
    cos2_table,
    file.path(paths$output_tables, sprintf("m5_%s_cos2.csv", run_name))
  )
  readr::write_csv(
    variable_coordinates,
    file.path(paths$output_tables, sprintf("m5_%s_variable_coordinates.csv", run_name))
  )
  readr::write_csv(
    scores_table,
    file.path(paths$output_tables, sprintf("m5_%s_scores.csv", run_name))
  )

  rs_plot_m5_scree(eigen_table, run_name, paths)
  rs_plot_m5_correlation_circle(variable_coordinates, run_name, paths)
  rs_plot_m5_biplot(pca_result, variable_coordinates, run_data, run_name, paths)

  list(
    run_summary = tibble::tibble(
      run_name = run_name,
      period_used = period_used,
      variables = paste(variables, collapse = ", "),
      n_used = nrow(run_data),
      variance_pc1 = eigen_table$variance_pct[1],
      variance_pc2 = eigen_table$variance_pct[2],
      cumulative_variance_pc1_pc2 = eigen_table$cumulative_variance_pct[2],
      main_interpretation_note = run_note
    ),
    eigen_table = eigen_table,
    loadings = loadings_table,
    contributions = contributions_table,
    cos2 = cos2_table,
    variable_coordinates = variable_coordinates,
    scores = scores_table
  )
}

rs_write_m5_technical_note <- function(technical_note_lines, paths) {
  writeLines(
    technical_note_lines,
    con = file.path(paths$output_tables, "m5_road_safety_note.md"),
    useBytes = TRUE
  )
}

rs_build_m5_validation_summary <- function(run_summary) {
  tibble::tibble(
    metric = c(
      "recent_comparable_period",
      "runs_executed",
      "baseline_recent_n",
      "baseline_full_period_n",
      "with_vmed_recent_n",
      "with_weekend_recent_n"
    ),
    value = c(
      sprintf("%s-%s", rs_m5_recent_year_min, rs_m5_recent_year_max),
      as.character(nrow(run_summary)),
      as.character(run_summary$n_used[run_summary$run_name == "baseline_recent"]),
      as.character(run_summary$n_used[run_summary$run_name == "baseline_full_period"]),
      as.character(run_summary$n_used[run_summary$run_name == "with_vmed_recent"]),
      as.character(run_summary$n_used[run_summary$run_name == "with_weekend_recent"])
    )
  )
}

rs_run_m5_pca_exploratorio <- function(screening_base, paths) {
  rs_check_m5_packages()
  rs_validate_m5_inputs(screening_base)

  prepared_base <- rs_prepare_m5_screening_base(screening_base)

  run_outputs <- list()
  run_summary_rows <- vector("list", nrow(rs_m5_run_registry))

  for (i in seq_len(nrow(rs_m5_run_registry))) {
    run_name <- rs_m5_run_registry$run_name[i]
    period_used <- rs_m5_run_registry$period_used[i]
    variables <- rs_m5_run_registry$variables[[i]]

    run_result <- rs_run_single_m5_pca(
      run_name = run_name,
      period_used = period_used,
      variables = variables,
      screening_base = prepared_base,
      paths = paths
    )

    run_outputs[[run_name]] <- run_result
    run_summary_rows[[i]] <- run_result$run_summary
  }

  run_summary <- dplyr::bind_rows(run_summary_rows)
  comparison_result <- rs_compare_m5_runs(run_outputs, run_summary)
  validation_summary <- rs_build_m5_validation_summary(run_summary)

  readr::write_csv(
    run_summary,
    file.path(paths$output_tables, "m5_pca_run_summary.csv")
  )
  readr::write_csv(
    comparison_result$comparison_table,
    file.path(paths$output_tables, "m5_pca_run_comparison.csv")
  )
  readr::write_csv(
    validation_summary,
    file.path(paths$output_tables, "m5_validation_summary.csv")
  )
  rs_write_m5_technical_note(comparison_result$technical_note_lines, paths)

  list(
    run_summary = run_summary,
    run_outputs = run_outputs,
    comparison_table = comparison_result$comparison_table,
    validation_summary = validation_summary
  )
}
