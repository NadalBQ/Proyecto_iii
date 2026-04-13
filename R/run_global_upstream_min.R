get_script_path <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)

  if (length(file_arg) == 1L) {
    return(normalizePath(sub("^--file=", "", file_arg[[1]]), winslash = "/", mustWork = TRUE))
  }

  if (!is.null(sys.frames()[[1]]$ofile)) {
    return(normalizePath(sys.frames()[[1]]$ofile, winslash = "/", mustWork = TRUE))
  }

  stop("No se pudo determinar la ruta del script `run_global_upstream_min.R`.", call. = FALSE)
}

parse_runner_args <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  list(
    force = "--force" %in% args,
    project_dir = {
      project_arg <- grep("^--project-dir=", args, value = TRUE)
      if (length(project_arg) == 1L) {
        normalizePath(sub("^--project-dir=", "", project_arg[[1]]), winslash = "/", mustWork = TRUE)
      } else {
        NA_character_
      }
    }
  )
}

source_active_global_scripts <- function(project_dir) {
  script_paths <- c(
    "R/01_ingesta_y_perfilado.R",
    "R/02_duplicados_y_expedientes.R",
    "R/03_tabla_accidente.R",
    "R/08_preparacion_red_canonica.R",
    "R/09_accidente_edge_matching.R",
    "R/10_edge_historical_aggregation.R",
    "R/11_edge_exposure_crosswalk.R",
    "R/12_edge_dynamic_context.R"
  )

  for (relative_path in script_paths) {
    absolute_path <- file.path(project_dir, relative_path)
    if (!file.exists(absolute_path)) {
      stop(sprintf("Falta el script activo requerido: %s", absolute_path), call. = FALSE)
    }

    message(sprintf("[SOURCE] %s", relative_path))
    source(absolute_path, encoding = "UTF-8", local = .GlobalEnv)
  }
}

run_step <- function(step_name, expr) {
  message(sprintf("[START] %s", step_name))
  started_at <- Sys.time()
  result <- eval.parent(substitute(expr))
  elapsed <- round(as.numeric(difftime(Sys.time(), started_at, units = "secs")), 2)
  message(sprintf("[DONE] %s (%.2fs)", step_name, elapsed))
  result
}

main <- function() {
  args <- parse_runner_args()
  script_path <- get_script_path()
  project_dir <- if (!is.na(args$project_dir)) {
    args$project_dir
  } else {
    normalizePath(file.path(dirname(script_path), ".."), winslash = "/", mustWork = TRUE)
  }

  message("[INFO] ROAD-SAFETY global upstream minimal runner")
  message(sprintf("[INFO] project_dir = %s", project_dir))
  message(sprintf("[INFO] force_refresh = %s", args$force))

  source_active_global_scripts(project_dir)

  paths <- run_step("Prepare project paths", rs_prepare_project_paths(project_dir))

  m1_result <- run_step("M1 ingest and profile", rs_run_m1_ingesta(paths))
  m2_result <- run_step(
    "M2 exact deduplication and expediente audit",
    rs_run_m2_duplicados_y_expedientes(m1_result$data, paths)
  )
  m3_result <- run_step(
    "M3 accident-level master table",
    rs_run_m3_tabla_accidente(
      deduplicated_data = m2_result$deduplicated_data,
      expediente_counts = m2_result$expediente_counts,
      paths = paths
    )
  )
  m8_result <- run_step(
    "M8 canonical network preparation",
    rs_run_m8_preparacion_red_canonica(
      accident_master = m3_result$accident_master,
      paths = paths,
      force_refresh = args$force
    )
  )
  m9_result <- run_step(
    "M9 accident-to-edge matching",
    rs_run_m9_accidente_edge_matching(
      accident_master = m3_result$accident_master,
      m8_result = m8_result,
      paths = paths,
      force_refresh = args$force
    )
  )
  m10_result <- run_step(
    "M10 edge historical aggregation",
    rs_run_m10_edge_historical_aggregation(
      m8_result = m8_result,
      paths = paths,
      m9_result = m9_result,
      force_refresh = args$force
    )
  )
  m11_result <- run_step(
    "M11 edge exposure crosswalk",
    rs_run_m11_edge_exposure_crosswalk(
      m8_result = m8_result,
      paths = paths,
      m9_result = m9_result,
      m10_result = m10_result,
      accident_master = m3_result$accident_master,
      force_refresh = args$force
    )
  )
  m12_result <- run_step(
    "M12 edge dynamic context",
    rs_run_m12_edge_dynamic_context(
      m8_result = m8_result,
      paths = paths,
      m9_result = m9_result,
      m11_result = m11_result,
      accident_master = m3_result$accident_master,
      force_refresh = args$force
    )
  )

  message("[INFO] Global upstream minimal line completed.")
  message(sprintf("[INFO] accident master: %s", file.path(paths$output_data, "accidentes_tabla_accidente_master.csv")))
  message(sprintf("[INFO] m8 edges: %s", file.path(paths$output_data, "m8_road_network_edges.csv")))
  message(sprintf("[INFO] m9 matches: %s", file.path(paths$output_data, "m9_accident_edge_matches.csv")))
  message(sprintf("[INFO] m10 aggregation: %s", file.path(paths$output_data, "m10_edge_historical_aggregation.csv")))
  message(sprintf("[INFO] m11 historical adjusted: %s", file.path(paths$output_data, "m11_historical_exposure_adjusted.csv")))
  message(sprintf("[INFO] m12 dynamic base: %s", file.path(paths$output_data, "m12_edge_context_dynamic_base.csv")))

  invisible(
    list(
      paths = paths,
      m1 = m1_result,
      m2 = m2_result,
      m3 = m3_result,
      m8 = m8_result,
      m9 = m9_result,
      m10 = m10_result,
      m11 = m11_result,
      m12 = m12_result
    )
  )
}

main()
