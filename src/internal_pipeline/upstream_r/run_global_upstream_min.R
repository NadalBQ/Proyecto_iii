get_script_path <- function() {
  file_args <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (!length(file_args)) {
    stop("Could not resolve the current R runner path.", call. = FALSE)
  }
  normalizePath(sub("^--file=", "", file_args[[1]]), winslash = "/", mustWork = TRUE)
}

parse_runner_args <- function(args) {
  parsed <- list(project_dir = NULL, force = FALSE)

  i <- 1L
  while (i <= length(args)) {
    arg <- args[[i]]
    if (identical(arg, "--project-dir")) {
      i <- i + 1L
      if (i > length(args)) {
        stop("`--project-dir` requires a value.", call. = FALSE)
      }
      parsed$project_dir <- args[[i]]
    } else if (identical(arg, "--force")) {
      parsed$force <- TRUE
    } else {
      stop(sprintf("Unknown argument: %s", arg), call. = FALSE)
    }
    i <- i + 1L
  }

  if (is.null(parsed$project_dir) || !nzchar(parsed$project_dir)) {
    stop("`--project-dir` is required.", call. = FALSE)
  }

  parsed
}

source_upstream_modules <- function(script_dir) {
  modules <- c(
    "01_ingesta_y_perfilado.R",
    "02_duplicados_y_expedientes.R",
    "03_tabla_accidente.R",
    "08_preparacion_red_canonica.R",
    "09_accidente_edge_matching.R",
    "10_edge_historical_aggregation.R",
    "11_edge_exposure_crosswalk.R",
    "12_edge_dynamic_context.R"
  )

  for (module_name in modules) {
    source(file.path(script_dir, module_name), local = FALSE, chdir = TRUE)
  }
}

run_upstream_pipeline <- function(project_dir, force = FALSE) {
  paths <- rs_prepare_project_paths(project_dir)

  m1_result <- rs_run_m1_ingesta(paths)
  m2_result <- rs_run_m2_duplicados_y_expedientes(m1_result$data, paths)
  m3_result <- rs_run_m3_tabla_accidente(
    deduplicated_data = m2_result$deduplicated_data,
    expediente_counts = m2_result$expediente_counts,
    paths = paths
  )
  m8_result <- rs_run_m8_preparacion_red_canonica(
    accident_master = m3_result$accident_master,
    paths = paths,
    force_refresh = force
  )
  m9_result <- rs_run_m9_accidente_edge_matching(
    accident_master = m3_result$accident_master,
    m8_result = m8_result,
    paths = paths,
    force_refresh = force
  )
  m10_result <- rs_run_m10_edge_historical_aggregation(
    m8_result = m8_result,
    paths = paths,
    m9_result = m9_result,
    force_refresh = force
  )
  m11_result <- rs_run_m11_edge_exposure_crosswalk(
    m8_result = m8_result,
    paths = paths,
    m9_result = m9_result,
    m10_result = m10_result,
    accident_master = m3_result$accident_master,
    force_refresh = force
  )
  m12_result <- rs_run_m12_edge_dynamic_context(
    m8_result = m8_result,
    paths = paths,
    m9_result = m9_result,
    m11_result = m11_result,
    accident_master = m3_result$accident_master,
    force_refresh = force
  )

  list(
    paths = paths,
    m1_result = m1_result,
    m2_result = m2_result,
    m3_result = m3_result,
    m8_result = m8_result,
    m9_result = m9_result,
    m10_result = m10_result,
    m11_result = m11_result,
    m12_result = m12_result
  )
}

main <- function() {
  parsed <- parse_runner_args(commandArgs(trailingOnly = TRUE))
  script_dir <- dirname(get_script_path())
  source_upstream_modules(script_dir)

  result <- run_upstream_pipeline(parsed$project_dir, force = parsed$force)

  cat(sprintf("project_dir=%s\n", normalizePath(parsed$project_dir, winslash = "/", mustWork = TRUE)))
  cat(sprintf("accident_master_csv=%s\n", file.path(result$paths$output_data, "accidentes_tabla_accidente_master.csv")))
  cat(sprintf("m8_edges_csv=%s\n", file.path(result$paths$output_data, "m8_road_network_edges.csv")))
  cat(sprintf("m9_matches_csv=%s\n", file.path(result$paths$output_data, "m9_accident_edge_matches.csv")))
  cat(sprintf("m10_csv=%s\n", file.path(result$paths$output_data, "m10_edge_historical_aggregation.csv")))
  cat(sprintf("m11_csv=%s\n", file.path(result$paths$output_data, "m11_historical_exposure_adjusted.csv")))
  cat(sprintf("m12_csv=%s\n", file.path(result$paths$output_data, "m12_edge_context_dynamic_base.csv")))
}

main()
