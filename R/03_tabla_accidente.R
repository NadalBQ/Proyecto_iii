rs_master_value_columns <- c(
  "fecha",
  "hora",
  "dia_semana",
  "distrito",
  "tipo_accidente",
  "estado_meteorologico",
  "coordenada_x_utm",
  "coordenada_y_utm",
  "direccion_unica",
  "es_festivo",
  "id_sensor_cercano",
  "intensidad",
  "ocupacion",
  "vmed"
)

rs_diagnostic_only_columns <- c(
  "sexo",
  "rango_edad",
  "tipo_vehiculo"
)

rs_pca_candidate_source_columns <- c(
  "fecha",
  "hora",
  "dia_semana",
  "es_festivo",
  "intensidad",
  "ocupacion",
  "vmed"
)

rs_validate_m3_columns <- function(data) {
  required_columns <- unique(c(
    "num_expediente",
    rs_master_value_columns,
    rs_diagnostic_only_columns,
    rs_pca_candidate_source_columns
  ))

  missing_columns <- setdiff(required_columns, names(data))

  if (length(missing_columns) > 0) {
    stop(
      sprintf(
        "Faltan columnas requeridas para M3: %s",
        paste(missing_columns, collapse = ", ")
      ),
      call. = FALSE
    )
  }
}

rs_resolve_group_value <- function(x) {
  non_null_values <- x[!is.na(x)]

  if (length(non_null_values) == 0L) {
    return(x[NA_integer_][1])
  }

  unique_values <- unique(non_null_values)

  if (length(unique_values) == 1L) {
    return(unique_values[1])
  }

  x[NA_integer_][1]
}

rs_format_value_examples <- function(x, max_values = 5L) {
  unique_values <- unique(x[!is.na(x)])

  if (length(unique_values) == 0L) {
    return(NA_character_)
  }

  formatted_values <- as.character(unique_values[seq_len(min(length(unique_values), max_values))])
  paste(formatted_values, collapse = " | ")
}

rs_build_variable_role_registry <- function(data) {
  analyzed_variables <- setdiff(names(data), "num_expediente")

  tibble::tibble(variable = analyzed_variables) |>
    dplyr::mutate(
      use_in_master_value = variable %in% rs_master_value_columns,
      use_in_pca_base = variable %in% rs_pca_candidate_source_columns,
      variable_role = dplyr::case_when(
        variable %in% rs_master_value_columns ~ "master_accident_level",
        variable %in% rs_diagnostic_only_columns ~ "diagnostic_only_entity_level",
        TRUE ~ "analyzed_not_selected"
      ),
      selection_reason = dplyr::case_when(
        variable %in% rs_master_value_columns ~ "Compatible with accident-level consolidation after intra-expediente inspection.",
        variable %in% rs_diagnostic_only_columns ~ "Entity-level field retained only for conflict diagnostics, not as accident-level value.",
        TRUE ~ "Analyzed for consistency but not selected for the conservative accident master."
      )
    ) |>
    dplyr::arrange(variable)
}

rs_summarise_variable_consistency <- function(data, variable_name, role_row) {
  grouped_summary <- data |>
    dplyr::group_by(num_expediente) |>
    dplyr::summarise(
      non_null_n = sum(!is.na(.data[[variable_name]])),
      non_null_distinct_n = dplyr::n_distinct(.data[[variable_name]], na.rm = TRUE),
      resolved_value = rs_resolve_group_value(.data[[variable_name]]),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      all_na = non_null_distinct_n == 0L,
      stable = non_null_distinct_n == 1L,
      has_conflict = non_null_distinct_n > 1L
    )

  conflict_cases <- grouped_summary |>
    dplyr::filter(has_conflict) |>
    dplyr::select(num_expediente, non_null_distinct_n)

  if (nrow(conflict_cases) > 0L) {
    conflict_examples <- data |>
      dplyr::semi_join(conflict_cases, by = "num_expediente") |>
      dplyr::group_by(num_expediente) |>
      dplyr::summarise(
        observed_non_null_values = rs_format_value_examples(.data[[variable_name]]),
        .groups = "drop"
      )

    conflict_cases <- conflict_cases |>
      dplyr::left_join(conflict_examples, by = "num_expediente") |>
      dplyr::mutate(variable = variable_name, .before = 1L)
  } else {
    conflict_cases <- tibble::tibble(
      variable = character(),
      num_expediente = character(),
      non_null_distinct_n = integer(),
      observed_non_null_values = character()
    )
  }

  example_expedientes <- if (nrow(conflict_cases) > 0L) {
    paste(utils::head(conflict_cases$num_expediente, 5L), collapse = " | ")
  } else {
    NA_character_
  }

  consistency_summary <- tibble::tibble(
    variable = variable_name,
    variable_role = role_row$variable_role,
    use_in_master_value = role_row$use_in_master_value,
    use_in_pca_base = role_row$use_in_pca_base,
    selection_reason = role_row$selection_reason,
    all_na_expedientes = sum(grouped_summary$all_na),
    stable_expedientes = sum(grouped_summary$stable),
    conflict_expedientes = sum(grouped_summary$has_conflict),
    conflict_pct = 100 * mean(grouped_summary$has_conflict),
    example_conflict_expedientes = example_expedientes
  )

  conflict_column_name <- paste0("conflict_", variable_name)

  if (isTRUE(role_row$use_in_master_value)) {
    master_fragment <- grouped_summary |>
      dplyr::transmute(
        num_expediente,
        !!variable_name := resolved_value,
        !!conflict_column_name := has_conflict
      )
  } else {
    master_fragment <- grouped_summary |>
      dplyr::transmute(
        num_expediente,
        !!conflict_column_name := has_conflict
      )
  }

  list(
    master_fragment = master_fragment,
    consistency_summary = consistency_summary,
    conflict_cases = conflict_cases
  )
}

rs_build_accident_master <- function(expediente_counts, master_fragments, analyzed_variables) {
  accident_master <- expediente_counts |>
    dplyr::select(
      num_expediente,
      rows_raw,
      rows_after_exact_dedup,
      exact_duplicate_rows_within_expediente,
      has_exact_duplicates,
      has_multiplicity_after_exact_dedup
    )

  for (fragment in master_fragments) {
    accident_master <- dplyr::left_join(accident_master, fragment, by = "num_expediente")
  }

  conflict_columns <- paste0("conflict_", analyzed_variables)
  pca_conflict_columns <- paste0("conflict_", rs_pca_candidate_source_columns)

  accident_master |>
    dplyr::mutate(
      has_any_conflict = dplyr::if_any(dplyr::all_of(conflict_columns), ~ .x),
      has_pca_candidate_conflict = dplyr::if_any(dplyr::all_of(pca_conflict_columns), ~ .x),
      pca_initial_eligible = !has_pca_candidate_conflict
    )
}

rs_build_pca_base <- function(accident_master) {
  accident_master |>
    dplyr::filter(pca_initial_eligible) |>
    dplyr::mutate(
      is_weekend = dplyr::case_when(
        is.na(dia_semana) ~ NA,
        dia_semana %in% c("sabado", "domingo") ~ TRUE,
        TRUE ~ FALSE
      ),
      hour_decimal = dplyr::if_else(is.na(hora), NA_real_, as.numeric(hora) / 3600),
      hour_sin = dplyr::if_else(is.na(hour_decimal), NA_real_, sin(2 * pi * hour_decimal / 24)),
      hour_cos = dplyr::if_else(is.na(hour_decimal), NA_real_, cos(2 * pi * hour_decimal / 24))
    ) |>
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

rs_build_m3_validation_summary <- function(accident_master, pca_base, conflict_cases) {
  distinct_expedientes <- dplyr::n_distinct(accident_master$num_expediente)
  duplicate_master_rows <- nrow(accident_master) - distinct_expedientes
  conflict_flag_columns <- grep("^conflict_", names(accident_master), value = TRUE)

  tibble::tibble(
    metric = c(
      "nrow_tabla_accidente_master",
      "n_distinct_num_expediente_master",
      "duplicate_num_expediente_rows_master",
      "master_row_equals_distinct_expediente",
      "master_has_no_duplicate_expedientes",
      "conflict_flag_columns_n",
      "conflict_case_rows",
      "expedientes_aptos_pca_inicial"
    ),
    value = c(
      as.character(nrow(accident_master)),
      as.character(distinct_expedientes),
      as.character(duplicate_master_rows),
      as.character(nrow(accident_master) == distinct_expedientes),
      as.character(duplicate_master_rows == 0L),
      as.character(length(conflict_flag_columns)),
      as.character(nrow(conflict_cases)),
      as.character(nrow(pca_base))
    )
  )
}

rs_run_m3_tabla_accidente <- function(deduplicated_data, expediente_counts, paths) {
  rs_validate_m3_columns(deduplicated_data)

  variable_role_registry <- rs_build_variable_role_registry(deduplicated_data)
  analyzed_variables <- variable_role_registry$variable

  master_fragments <- vector("list", length(analyzed_variables))
  consistency_summaries <- vector("list", length(analyzed_variables))
  conflict_cases_list <- vector("list", length(analyzed_variables))

  for (i in seq_along(analyzed_variables)) {
    variable_name <- analyzed_variables[i]
    role_row <- variable_role_registry |>
      dplyr::filter(variable == variable_name)

    variable_result <- rs_summarise_variable_consistency(
      data = deduplicated_data,
      variable_name = variable_name,
      role_row = role_row
    )

    master_fragments[[i]] <- variable_result$master_fragment
    consistency_summaries[[i]] <- variable_result$consistency_summary
    conflict_cases_list[[i]] <- variable_result$conflict_cases
  }

  variable_consistency_summary <- dplyr::bind_rows(consistency_summaries) |>
    dplyr::arrange(dplyr::desc(conflict_expedientes), variable)

  conflict_cases <- dplyr::bind_rows(conflict_cases_list) |>
    dplyr::arrange(variable, num_expediente)

  conflict_report <- variable_consistency_summary |>
    dplyr::transmute(
      variable,
      variable_role,
      conflict_expedientes,
      conflict_pct,
      example_conflict_expedientes
    )

  accident_master <- rs_build_accident_master(
    expediente_counts = expediente_counts,
    master_fragments = master_fragments,
    analyzed_variables = analyzed_variables
  )

  pca_base <- rs_build_pca_base(accident_master)
  validation_summary <- rs_build_m3_validation_summary(accident_master, pca_base, conflict_cases)

  readr::write_csv(
    variable_role_registry,
    file.path(paths$output_tables, "m3_variable_role_registry.csv")
  )
  readr::write_csv(
    variable_consistency_summary,
    file.path(paths$output_tables, "m3_variable_consistency_summary.csv")
  )
  readr::write_csv(
    conflict_report,
    file.path(paths$output_tables, "m3_conflict_report.csv")
  )
  readr::write_csv(
    conflict_cases,
    file.path(paths$output_tables, "m3_conflict_cases.csv")
  )
  readr::write_csv(
    validation_summary,
    file.path(paths$output_tables, "m3_validation_summary.csv")
  )
  readr::write_csv(
    accident_master,
    file.path(paths$output_data, "accidentes_tabla_accidente_master.csv")
  )
  readr::write_csv(
    pca_base,
    file.path(paths$output_data, "accidentes_pca_base_conflict_free.csv")
  )

  list(
    accident_master = accident_master,
    pca_base = pca_base,
    variable_role_registry = variable_role_registry,
    variable_consistency_summary = variable_consistency_summary,
    conflict_report = conflict_report,
    conflict_cases = conflict_cases,
    validation_summary = validation_summary
  )
}
