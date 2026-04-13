get_runner_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- "--file="
  file_match <- grep(file_arg, args)

  if (length(file_match) > 0) {
    script_path <- sub(file_arg, "", args[file_match[1]])
    return(dirname(normalizePath(script_path, winslash = "/", mustWork = TRUE)))
  }

  frame_file <- tryCatch(sys.frames()[[1]]$ofile, error = function(...) NULL)
  if (!is.null(frame_file)) {
    return(dirname(normalizePath(frame_file, winslash = "/", mustWork = TRUE)))
  }

  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

main <- function() {
  project_dir <- get_runner_dir()

  source(file.path(project_dir, "R", "01_ingesta_y_perfilado.R"), local = TRUE)
  source(file.path(project_dir, "R", "02_duplicados_y_expedientes.R"), local = TRUE)
  source(file.path(project_dir, "R", "03_tabla_accidente.R"), local = TRUE)
  source(file.path(project_dir, "R", "04_screening_pca.R"), local = TRUE)
  source(file.path(project_dir, "R", "05_pca_exploratorio.R"), local = TRUE)
  source(file.path(project_dir, "R", "06_indice_blueprint.R"), local = TRUE)
  source(file.path(project_dir, "R", "07_historico_espacial_blueprint.R"), local = TRUE)
  source(file.path(project_dir, "R", "08_preparacion_red_canonica.R"), local = TRUE)
  source(file.path(project_dir, "R", "09_accidente_edge_matching.R"), local = TRUE)
  source(file.path(project_dir, "R", "10_edge_historical_aggregation.R"), local = TRUE)
  source(file.path(project_dir, "R", "11_edge_exposure_crosswalk.R"), local = TRUE)
  source(file.path(project_dir, "R", "12_edge_dynamic_context.R"), local = TRUE)
  source(file.path(project_dir, "R", "13_edge_combined_risk_prelim.R"), local = TRUE)

  paths <- rs_prepare_project_paths(project_dir)
  ingesta_result <- rs_run_m1_ingesta(paths)
  m2_result <- rs_run_m2_duplicados_y_expedientes(ingesta_result$data, paths)
  m3_result <- rs_run_m3_tabla_accidente(
    deduplicated_data = m2_result$deduplicated_data,
    expediente_counts = m2_result$expediente_counts,
    paths = paths
  )
  m4_result <- rs_run_m4_screening_pca(
    accident_master = m3_result$accident_master,
    pca_base = m3_result$pca_base,
    paths = paths
  )
  m5_result <- rs_run_m5_pca_exploratorio(
    screening_base = m4_result$screening_base,
    paths = paths
  )
  m6_result <- rs_run_m6_indice_blueprint(
    variable_screening = m4_result$variable_screening,
    set_screening = m4_result$set_screening,
    m5_result = m5_result,
    paths = paths
  )
  m7_result <- rs_run_m7_historico_espacial_blueprint(
    accident_master = m3_result$accident_master,
    paths = paths
  )
  m8_result <- rs_run_m8_preparacion_red_canonica(
    accident_master = m3_result$accident_master,
    paths = paths,
    force_refresh = FALSE
  )
  m9_result <- rs_run_m9_accidente_edge_matching(
    accident_master = m3_result$accident_master,
    m8_result = m8_result,
    paths = paths,
    force_refresh = FALSE
  )
  m10_result <- rs_run_m10_edge_historical_aggregation(
    m8_result = m8_result,
    paths = paths,
    m9_result = m9_result,
    force_refresh = FALSE
  )
  m11_result <- rs_run_m11_edge_exposure_crosswalk(
    m8_result = m8_result,
    paths = paths,
    m9_result = m9_result,
    m10_result = m10_result,
    accident_master = m3_result$accident_master,
    force_refresh = FALSE
  )
  m12_result <- rs_run_m12_edge_dynamic_context(
    m8_result = m8_result,
    paths = paths,
    m9_result = m9_result,
    m11_result = m11_result,
    accident_master = m3_result$accident_master,
    force_refresh = FALSE
  )
  m13_result <- rs_run_m13_edge_combined_risk_prelim(
    m8_result = m8_result,
    paths = paths,
    m10_result = m10_result,
    m11_result = m11_result,
    m12_result = m12_result,
    force_refresh = FALSE
  )

  cat("\nPipeline M1 + M2 + M3 + M4 + M5 + M6 + M7 + M8 + M9 + M10 + M11 + M12 + M13 completado.\n")
  cat(sprintf("nrow raw: %s\n", format(nrow(ingesta_result$data), big.mark = ",")))
  cat(sprintf("numero de duplicados exactos: %s\n", format(m2_result$exact_duplicate_count, big.mark = ",")))
  cat(sprintf("nrow tras deduplicacion exacta: %s\n", format(nrow(m2_result$deduplicated_data), big.mark = ",")))
  cat(sprintf("numero de expedientes unicos: %s\n", format(m2_result$unique_expedientes, big.mark = ",")))
  cat("distribucion de filas por expediente (tras deduplicacion exacta):\n")
  print(m2_result$expediente_distribution_after_exact_dedup, n = nrow(m2_result$expediente_distribution_after_exact_dedup))
  cat(sprintf("nrow tabla_accidente_master: %s\n", format(nrow(m3_result$accident_master), big.mark = ",")))
  cat(sprintf("expedientes con algun conflicto: %s\n", format(sum(m3_result$accident_master$has_any_conflict), big.mark = ",")))
  cat(sprintf("expedientes aptos para PCA inicial (sin conflictos en variables PCA): %s\n", format(nrow(m3_result$pca_base), big.mark = ",")))
  cat("retencion de casos por set PCA:\n")
  print(m4_result$set_screening)
  cat("recomendacion de vmed:\n")
  print(dplyr::filter(m4_result$variable_screening, variable == "vmed"))
  cat("resumen de corridas PCA:\n")
  print(m5_result$run_summary)
  cat("blueprint preliminar del indice:\n")
  print(m6_result$index_blueprint)
  cat("unidad espacial baseline recomendada para M7:\n")
  print(dplyr::filter(m7_result$spatial_unit_options, is_recommended_baseline))
  cat("inputs faltantes para map-matching / score historico real:\n")
  print(m7_result$missing_inputs)
  cat("validacion resumida de readiness espacial:\n")
  print(m7_result$validation_summary)
  cat("metadata resumida de red canonica M8:\n")
  print(m8_result$metadata)
  cat("validacion resumida de red canonica M8:\n")
  print(m8_result$validation_summary)
  cat("resumen de calidad del matching M9:\n")
  print(m9_result$quality_summary)
  cat("validacion resumida del matching M9:\n")
  print(m9_result$validation_summary)
  cat("resumen de cobertura historica por edge M10:\n")
  print(m10_result$coverage_summary)
  cat("validacion resumida de agregacion historica M10:\n")
  print(m10_result$validation_summary)
  cat("resumen de calidad del crosswalk/exposicion M11:\n")
  print(m11_result$crosswalk_quality_summary)
  cat("validacion resumida de exposicion baseline M11:\n")
  print(m11_result$validation_summary)
  cat("resumen de capa dinamica/contextual M12:\n")
  print(m12_result$dynamic_context_summary)
  cat("validacion resumida de capa dinamica/contextual M12:\n")
  print(m12_result$validation_summary)
  cat("resumen de riesgo combinado preliminar M13:\n")
  print(m13_result$combined_summary)
  cat("sensibilidad resumida de M13:\n")
  print(m13_result$sensitivity_summary)
  cat("validacion resumida de M13:\n")
  print(m13_result$validation_summary)
}

main()
