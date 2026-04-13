rs_required_columns <- c(
  "num_expediente",
  "fecha",
  "hora",
  "dia_semana",
  "es_festivo",
  "intensidad",
  "ocupacion",
  "vmed"
)

rs_prepare_project_paths <- function(project_dir) {
  if (missing(project_dir) || is.null(project_dir) || !nzchar(project_dir)) {
    stop("Se necesita un directorio de proyecto valido para ejecutar el pipeline.", call. = FALSE)
  }

  project_dir <- normalizePath(project_dir, winslash = "/", mustWork = TRUE)

  paths <- list(
    project_dir = project_dir,
    input_csv = file.path(project_dir, "accidentes_con_trafico_final.csv"),
    outputs_root = file.path(project_dir, "outputs"),
    output_data = file.path(project_dir, "outputs", "data"),
    output_tables = file.path(project_dir, "outputs", "tables"),
    output_plots = file.path(project_dir, "outputs", "plots")
  )

  for (dir_path in c(paths$outputs_root, paths$output_data, paths$output_tables, paths$output_plots)) {
    if (!dir.exists(dir_path)) {
      dir.create(dir_path, recursive = TRUE, showWarnings = FALSE)
    }
  }

  paths
}

rs_check_required_packages <- function() {
  required_packages <- c("readr", "dplyr", "tibble", "janitor", "lubridate")
  missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]

  if (length(missing_packages) > 0) {
    stop(
      sprintf(
        "Faltan paquetes requeridos para M1/M2: %s",
        paste(missing_packages, collapse = ", ")
      ),
      call. = FALSE
    )
  }
}

rs_validate_required_columns <- function(data, required_columns = rs_required_columns) {
  missing_columns <- setdiff(required_columns, names(data))

  if (length(missing_columns) > 0) {
    stop(
      sprintf(
        "Faltan columnas clave tras clean_names(): %s",
        paste(missing_columns, collapse = ", ")
      ),
      call. = FALSE
    )
  }
}

rs_build_ingesta_summary <- function(data) {
  parsed_fecha <- suppressWarnings(lubridate::ymd(data$fecha, quiet = TRUE))
  parsed_hora <- suppressWarnings(lubridate::hms(data$hora, quiet = TRUE))

  tibble::tibble(
    metric = c(
      "nrow_raw",
      "ncol_raw",
      "fecha_parse_na",
      "hora_parse_na"
    ),
    value = c(
      nrow(data),
      ncol(data),
      sum(is.na(parsed_fecha)),
      sum(is.na(parsed_hora))
    )
  )
}

rs_build_key_column_profile <- function(data, required_columns = rs_required_columns) {
  tibble::tibble(
    column_name = required_columns,
    missing_n = vapply(required_columns, function(column_name) sum(is.na(data[[column_name]])), numeric(1)),
    non_missing_n = vapply(required_columns, function(column_name) sum(!is.na(data[[column_name]])), numeric(1)),
    class = vapply(required_columns, function(column_name) paste(class(data[[column_name]]), collapse = "|"), character(1))
  )
}

rs_run_m1_ingesta <- function(paths) {
  rs_check_required_packages()

  if (!file.exists(paths$input_csv)) {
    stop(
      sprintf("No se encontro el archivo de entrada esperado: %s", paths$input_csv),
      call. = FALSE
    )
  }

  data <- readr::read_csv(
    file = paths$input_csv,
    show_col_types = FALSE,
    progress = FALSE
  )
  data <- janitor::clean_names(data)

  rs_validate_required_columns(data)

  ingesta_summary <- rs_build_ingesta_summary(data)
  key_column_profile <- rs_build_key_column_profile(data)

  readr::write_csv(ingesta_summary, file.path(paths$output_tables, "m1_ingesta_summary.csv"))
  readr::write_csv(key_column_profile, file.path(paths$output_tables, "m1_key_column_profile.csv"))

  list(
    data = data,
    ingesta_summary = ingesta_summary,
    key_column_profile = key_column_profile
  )
}
