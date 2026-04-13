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

read_delim_file <- function(path, sep, encoding = "UTF-8") {
  if (requireNamespace("data.table", quietly = TRUE)) {
    data.table::fread(
      input = path,
      sep = sep,
      encoding = encoding,
      showProgress = FALSE,
      na.strings = c("", "NA", "NULL")
    )
  } else {
    utils::read.csv(
      file = path,
      sep = sep,
      fileEncoding = encoding,
      stringsAsFactors = FALSE,
      na.strings = c("", "NA", "NULL")
    )
  }
}

read_csv_file <- function(path, select = NULL) {
  if (requireNamespace("data.table", quietly = TRUE)) {
    data.table::fread(
      input = path,
      encoding = "UTF-8",
      select = select,
      showProgress = FALSE,
      na.strings = c("", "NA", "NULL")
    )
  } else {
    out <- utils::read.csv(file = path, stringsAsFactors = FALSE, na.strings = c("", "NA", "NULL"))
    if (!is.null(select)) {
      out <- out[select]
    }
    out
  }
}

write_csv_file <- function(x, path) {
  if (requireNamespace("data.table", quietly = TRUE) && data.table::is.data.table(x)) {
    data.table::fwrite(x, file = path)
  } else {
    utils::write.csv(x, file = path, row.names = FALSE, na = "")
  }
}

root <- find_repo_root()
processed_dir <- file.path(root, "data", "processed")
outputs_dir <- file.path(root, "outputs")
dir.create(outputs_dir, recursive = TRUE, showWarnings = FALSE)

panel_path <- file.path(processed_dir, "traffic_2024_4months_sensor_panel.csv")
aggregated_temp_path <- file.path(processed_dir, "traffic_2024_4months_aggregated_unjoined.csv")
sensor_path <- file.path(root, "data/raw/traffic_sensor_locations/sensor_locations.csv")

required_paths <- c(panel_path, aggregated_temp_path, sensor_path)
missing_paths <- required_paths[!file.exists(required_paths)]
if (length(missing_paths) > 0L) {
  stop(
    sprintf("Missing required inputs for sensor join:\n%s", paste(missing_paths, collapse = "\n")),
    call. = FALSE
  )
}

panel <- read_csv_file(
  panel_path,
  select = c("sensor_id", "timestamp", "intensidad", "ocupacion", "vmed", "error")
)
aggregated <- read_csv_file(aggregated_temp_path)
sensors <- read_delim_file(sensor_path, sep = ";", encoding = "UTF-8")

names(sensors) <- normalize_names(names(sensors))
required_sensor_cols <- c("id", "tipo_elem", "distrito", "nombre", "utm_x", "utm_y", "longitud", "latitud")
missing_sensor_cols <- setdiff(required_sensor_cols, names(sensors))
if (length(missing_sensor_cols) > 0L) {
  stop(
    sprintf("sensor_locations.csv is missing required columns: %s", paste(missing_sensor_cols, collapse = ", ")),
    call. = FALSE
  )
}

sensors$sensor_id <- suppressWarnings(as.integer(as.numeric(sensors$id)))
sensors$tipo_elem_sensor <- as.character(sensors$tipo_elem)
sensors$distrito_sensor <- suppressWarnings(as.integer(as.numeric(sensors$distrito)))
sensors$sensor_name <- as.character(sensors$nombre)
sensors$utm_x <- suppressWarnings(as.numeric(sensors$utm_x))
sensors$utm_y <- suppressWarnings(as.numeric(sensors$utm_y))
sensors$longitud <- suppressWarnings(as.numeric(sensors$longitud))
sensors$latitud <- suppressWarnings(as.numeric(sensors$latitud))
sensors$cod_cent <- if ("cod_cent" %in% names(sensors)) as.character(sensors$cod_cent) else NA_character_

sensors <- sensors[!is.na(sensors$sensor_id), c(
  "sensor_id", "tipo_elem_sensor", "distrito_sensor",
  "cod_cent", "sensor_name", "utm_x", "utm_y", "longitud", "latitud"
)]

sensor_id_dups <- sum(duplicated(sensors$sensor_id))
join_key_used <- if (sensor_id_dups == 0L) "sensor_id" else "sensor_id + tipo_elem"

if (join_key_used == "sensor_id") {
  final_aggregated <- merge(aggregated, sensors, by = "sensor_id", all.x = TRUE)
} else {
  sensors$join_tipo_elem <- sensors$tipo_elem_sensor
  aggregated$join_tipo_elem <- aggregated$tipo_elem_traffic
  final_aggregated <- merge(
    aggregated,
    sensors,
    by.x = c("sensor_id", "join_tipo_elem"),
    by.y = c("sensor_id", "join_tipo_elem"),
    all.x = TRUE
  )
  final_aggregated$join_tipo_elem <- NULL
}

final_path <- file.path(processed_dir, "traffic_2024_4months_aggregated.csv")
write_csv_file(final_aggregated, final_path)

panel_unique_sensors <- length(unique(panel$sensor_id[!is.na(panel$sensor_id)]))
aggregated_unique_sensors <- length(unique(final_aggregated$sensor_id[!is.na(final_aggregated$sensor_id)]))
sensor_unique_sensors <- length(unique(sensors$sensor_id))
join_match_n <- sum(!is.na(final_aggregated$latitud) & !is.na(final_aggregated$longitud))
join_match_pct <- if (nrow(final_aggregated) == 0L) NA_real_ else round(join_match_n / nrow(final_aggregated) * 100, 2)
error_non_n_pct <- round(mean(!is.na(panel$error) & panel$error != "N") * 100, 2)

summary_df <- data.frame(
  metric = c(
    "traffic_month_files_processed_n",
    "months_processed",
    "sensor_panel_row_count",
    "sensor_panel_unique_sensors",
    "aggregated_row_count",
    "aggregated_unique_sensors",
    "sensor_locations_unique_sensors",
    "sensor_id_duplicates_in_official_locations_n",
    "sensor_join_key_used",
    "sensor_join_match_rows_n",
    "sensor_join_match_rows_pct",
    "panel_missing_intensidad_pct",
    "panel_missing_ocupacion_pct",
    "panel_missing_vmed_pct",
    "panel_error_non_n_pct",
    "panel_min_timestamp",
    "panel_max_timestamp"
  ),
  value = c(
    4,
    "1,4,7,10",
    nrow(panel),
    panel_unique_sensors,
    nrow(final_aggregated),
    aggregated_unique_sensors,
    sensor_unique_sensors,
    sensor_id_dups,
    join_key_used,
    join_match_n,
    join_match_pct,
    round(mean(is.na(panel$intensidad)) * 100, 2),
    round(mean(is.na(panel$ocupacion)) * 100, 2),
    round(mean(is.na(panel$vmed)) * 100, 2),
    error_non_n_pct,
    as.character(min(panel$timestamp, na.rm = TRUE)),
    as.character(max(panel$timestamp, na.rm = TRUE))
  ),
  stringsAsFactors = FALSE
)

summary_path <- file.path(outputs_dir, "traffic_aggregation_summary.csv")
write_csv_file(summary_df, summary_path)

cat("Created joined aggregated table:", final_path, "\n")
cat("Created aggregation summary:", summary_path, "\n")
cat("Join key used:", join_key_used, "\n")
