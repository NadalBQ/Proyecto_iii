if (!requireNamespace("data.table", quietly = TRUE)) {
  stop("This script requires data.table for efficient processing.", call. = FALSE)
}

suppressPackageStartupMessages(library(data.table))

find_repo_root <- function() {
  root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  if (!file.exists(file.path(root, "AGENTS.md"))) {
    stop("Run this script from the repository root.", call. = FALSE)
  }
  root
}

normalize_names <- function(x) {
  x <- iconv(x, from = "", to = "ASCII//TRANSLIT")
  x <- tolower(x)
  x <- gsub("[^a-z0-9]+", "_", x)
  x <- gsub("^_+|_+$", "", x)
  x
}

safe_mean <- function(x) {
  if (all(is.na(x))) NA_real_ else mean(x, na.rm = TRUE)
}

safe_median <- function(x) {
  if (all(is.na(x))) NA_real_ else stats::median(x, na.rm = TRUE)
}

root <- find_repo_root()
processed_dir <- file.path(root, "data", "processed")
dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)

traffic_files <- file.path(
  root,
  "data/raw/traffic_history_2024",
  c("01-2024.csv", "04-2024.csv", "07-2024.csv", "10-2024.csv")
)

missing_paths <- traffic_files[!file.exists(traffic_files)]
if (length(missing_paths) > 0L) {
  stop(
    sprintf("Missing traffic files:\n%s", paste(missing_paths, collapse = "\n")),
    call. = FALSE
  )
}

required_cols <- c(
  "id", "fecha", "tipo_elem", "intensidad",
  "ocupacion", "vmed", "error", "periodo_integracion"
)

panel_path <- file.path(processed_dir, "traffic_2024_4months_sensor_panel.csv")
aggregated_temp_path <- file.path(processed_dir, "traffic_2024_4months_aggregated_unjoined.csv")

if (file.exists(panel_path)) file.remove(panel_path)
if (file.exists(aggregated_temp_path)) file.remove(aggregated_temp_path)

traffic_time_bin_labels <- c("00_03", "04_07", "08_11", "12_15", "16_19", "20_23")
aggregated_list <- vector("list", length(traffic_files))

for (i in seq_along(traffic_files)) {
  path <- traffic_files[[i]]
  dt <- fread(
    input = path,
    sep = ";",
    encoding = "UTF-8",
    select = required_cols,
    colClasses = c(fecha = "character"),
    showProgress = FALSE,
    na.strings = c("", "NA", "NULL")
  )

  setnames(dt, normalize_names(names(dt)))
  missing_required <- setdiff(required_cols, names(dt))
  if (length(missing_required) > 0L) {
    stop(
      sprintf("File %s is missing required columns: %s", basename(path), paste(missing_required, collapse = ", ")),
      call. = FALSE
    )
  }

  source_month <- as.integer(substr(basename(path), 1L, 2L))
  dt[, sensor_id := suppressWarnings(as.integer(as.numeric(id)))]
  dt[, timestamp := as.POSIXct(fecha, format = "%Y-%m-%d %H:%M:%S", tz = "Europe/Madrid")]
  dt[, intensidad := suppressWarnings(as.numeric(intensidad))]
  dt[, ocupacion := suppressWarnings(as.numeric(ocupacion))]
  dt[, vmed := suppressWarnings(as.numeric(vmed))]
  dt[, error := fifelse(is.na(error), NA_character_, trimws(as.character(error)))]
  dt[, periodo_integracion := suppressWarnings(as.integer(as.numeric(periodo_integracion)))]
  dt[, analysis_year := as.integer(format(timestamp, "%Y"))]
  dt[, month := as.integer(format(timestamp, "%m"))]
  dt[, hour := as.integer(format(timestamp, "%H"))]
  dt[, weekday_index := as.POSIXlt(timestamp, tz = "Europe/Madrid")$wday]
  dt[, temporal_bin_4h := traffic_time_bin_labels[pmax(pmin(floor(hour / 4) + 1L, length(traffic_time_bin_labels)), 1L)]]
  dt[, is_weekend := as.integer(weekday_index %in% c(0L, 6L))]
  dt[, source_month := source_month]

  panel_dt <- dt[
    !is.na(sensor_id) & !is.na(timestamp),
    .(
      sensor_id,
      timestamp,
      tipo_elem = as.character(tipo_elem),
      intensidad,
      ocupacion,
      vmed,
      error,
      periodo_integracion,
      analysis_year,
      month,
      hour,
      temporal_bin_4h,
      is_weekend,
      source_month
    )
  ]

  fwrite(panel_dt, file = panel_path, append = i > 1L, col.names = i == 1L)

  aggregated_list[[i]] <- panel_dt[
    ,
    .(
      intensidad_mean = safe_mean(intensidad),
      ocupacion_mean = safe_mean(ocupacion),
      vmed_mean = safe_mean(vmed),
      intensidad_median = safe_median(intensidad),
      ocupacion_median = safe_median(ocupacion),
      vmed_median = safe_median(vmed),
      n_observations = .N
    ),
    by = .(sensor_id, analysis_year, month, temporal_bin_4h, is_weekend, tipo_elem_traffic = tipo_elem)
  ]
}

aggregated <- rbindlist(aggregated_list, use.names = TRUE, fill = TRUE)
fwrite(aggregated, file = aggregated_temp_path)

cat("Created panel:", panel_path, "\n")
cat("Created intermediate aggregated table:", aggregated_temp_path, "\n")
cat("Panel months processed:", paste(c(1, 4, 7, 10), collapse = ", "), "\n")
cat("Aggregated rows:", nrow(aggregated), "\n")
