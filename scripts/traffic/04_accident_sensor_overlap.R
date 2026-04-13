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

read_delim_file <- function(path, sep, encoding = "UTF-8", select = NULL) {
  if (requireNamespace("data.table", quietly = TRUE)) {
    data.table::fread(
      input = path,
      sep = sep,
      encoding = encoding,
      select = select,
      showProgress = FALSE,
      na.strings = c("", "NA", "NULL")
    )
  } else {
    out <- utils::read.csv(
      file = path,
      sep = sep,
      fileEncoding = encoding,
      stringsAsFactors = FALSE,
      na.strings = c("", "NA", "NULL")
    )
    if (!is.null(select)) {
      out <- out[select]
    }
    out
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

get_metric <- function(summary_df, metric_name) {
  value <- summary_df$value[summary_df$metric == metric_name]
  if (length(value) == 0L) NA_character_ else as.character(value[[1L]])
}

root <- find_repo_root()
processed_dir <- file.path(root, "data", "processed")
outputs_dir <- file.path(root, "outputs")

aggregated_path <- file.path(processed_dir, "traffic_2024_4months_aggregated.csv")
panel_path <- file.path(processed_dir, "traffic_2024_4months_sensor_panel.csv")
sensor_path <- file.path(root, "data/raw/traffic_sensor_locations/sensor_locations.csv")
accident_path <- file.path(root, "data/raw/accidents/accidentes_con_trafico_final.csv")
aggregation_summary_path <- file.path(outputs_dir, "traffic_aggregation_summary.csv")

required_paths <- c(aggregated_path, panel_path, sensor_path, accident_path, aggregation_summary_path)
missing_paths <- required_paths[!file.exists(required_paths)]
if (length(missing_paths) > 0L) {
  stop(
    sprintf("Missing required inputs for overlap step:\n%s", paste(missing_paths, collapse = "\n")),
    call. = FALSE
  )
}

aggregated <- read_csv_file(aggregated_path)
panel <- read_csv_file(panel_path, select = "sensor_id")
sensor_locations <- read_delim_file(sensor_path, sep = ";", encoding = "UTF-8")
accidents <- read_delim_file(accident_path, sep = ",", encoding = "UTF-8", select = "id_sensor_cercano")
aggregation_summary <- read_csv_file(aggregation_summary_path)

names(sensor_locations) <- normalize_names(names(sensor_locations))
names(accidents) <- normalize_names(names(accidents))

if (!"id_sensor_cercano" %in% names(accidents)) {
  stop("accidentes_con_trafico_final.csv does not contain id_sensor_cercano.", call. = FALSE)
}

accident_sensor_id <- suppressWarnings(as.integer(as.numeric(accidents$id_sensor_cercano)))
official_sensor_id <- suppressWarnings(as.integer(as.numeric(sensor_locations$id)))
traffic_sensor_id <- suppressWarnings(as.integer(as.numeric(panel$sensor_id)))
aggregated_sensor_id <- suppressWarnings(as.integer(as.numeric(aggregated$sensor_id)))

accident_sensor_set <- sort(unique(accident_sensor_id[!is.na(accident_sensor_id)]))
official_sensor_set <- sort(unique(official_sensor_id[!is.na(official_sensor_id)]))
traffic_sensor_set <- sort(unique(traffic_sensor_id[!is.na(traffic_sensor_id)]))
aggregated_sensor_set <- sort(unique(aggregated_sensor_id[!is.na(aggregated_sensor_id)]))

overlap_official_n <- length(intersect(accident_sensor_set, official_sensor_set))
overlap_traffic_n <- length(intersect(accident_sensor_set, traffic_sensor_set))
overlap_aggregated_n <- length(intersect(accident_sensor_set, aggregated_sensor_set))

accident_sensor_subset <- aggregated[aggregated$sensor_id %in% accident_sensor_set, ]
subset_path <- file.path(processed_dir, "traffic_2024_4months_aggregated_accident_sensor_subset.csv")
write_csv_file(accident_sensor_subset, subset_path)

overlap_summary <- data.frame(
  metric = c(
    "accident_rows_total",
    "accident_rows_with_sensor_id",
    "accident_unique_sensors",
    "official_unique_sensors",
    "traffic_panel_unique_sensors",
    "aggregated_unique_sensors",
    "accident_sensor_overlap_with_official_n",
    "accident_sensor_overlap_with_official_pct",
    "accident_sensor_overlap_with_traffic_4months_n",
    "accident_sensor_overlap_with_traffic_4months_pct",
    "accident_sensor_overlap_with_aggregated_n",
    "accident_sensor_overlap_with_aggregated_pct"
  ),
  value = c(
    nrow(accidents),
    sum(!is.na(accident_sensor_id)),
    length(accident_sensor_set),
    length(official_sensor_set),
    length(traffic_sensor_set),
    length(aggregated_sensor_set),
    overlap_official_n,
    round(if (length(accident_sensor_set) == 0L) NA_real_ else overlap_official_n / length(accident_sensor_set) * 100, 2),
    overlap_traffic_n,
    round(if (length(accident_sensor_set) == 0L) NA_real_ else overlap_traffic_n / length(accident_sensor_set) * 100, 2),
    overlap_aggregated_n,
    round(if (length(accident_sensor_set) == 0L) NA_real_ else overlap_aggregated_n / length(accident_sensor_set) * 100, 2)
  ),
  stringsAsFactors = FALSE
)

overlap_summary_path <- file.path(outputs_dir, "traffic_accident_sensor_overlap_summary.csv")
write_csv_file(overlap_summary, overlap_summary_path)

traffic_sep <- ";"
accident_sep <- ","
join_key_used <- get_metric(aggregation_summary, "sensor_join_key_used")
panel_missing_intensidad_pct <- get_metric(aggregation_summary, "panel_missing_intensidad_pct")
panel_missing_ocupacion_pct <- get_metric(aggregation_summary, "panel_missing_ocupacion_pct")
panel_missing_vmed_pct <- get_metric(aggregation_summary, "panel_missing_vmed_pct")
error_non_n_pct <- get_metric(aggregation_summary, "panel_error_non_n_pct")

quality_note_path <- file.path(outputs_dir, "traffic_data_quality_note.md")
note_lines <- c(
  "# Traffic Data Quality Note",
  "",
  "## Scope",
  "- This pilot uses only January, April, July and October 2024 traffic history files.",
  "- It does not extend the period, does not enter modeling, and does not map to edge_id.",
  "",
  "## Input structure",
  sprintf("- Traffic monthly files were read with separator `%s`.", traffic_sep),
  sprintf("- Sensor locations were read with separator `%s`.", traffic_sep),
  sprintf("- Accident file was read with separator `%s` and UTF-8 encoding.", accident_sep),
  "- The project sensor field detected in accidents is `id_sensor_cercano`.",
  "- October keeps the same logical traffic schema but its header formatting drops quotes around `id` and `periodo_integracion`.",
  "",
  "## Parsing assumptions",
  "- Traffic timestamp was parsed from `fecha` using `%Y-%m-%d %H:%M:%S` and timezone `Europe/Madrid`.",
  "- `sensor_id` was standardized from traffic `id`, sensor location `id`, and accident `id_sensor_cercano` with explicit numeric coercion.",
  "- Temporal variables built in this phase are `analysis_year`, `month`, `hour`, `temporal_bin_4h`, and `is_weekend`.",
  "",
  "## Quality observations",
  sprintf("- Panel missingness: intensidad `%s%%`, ocupacion `%s%%`, vmed `%s%%`.", panel_missing_intensidad_pct, panel_missing_ocupacion_pct, panel_missing_vmed_pct),
  sprintf("- Non-`N` traffic error flags account for `%s%%` of cleaned panel rows.", error_non_n_pct),
  sprintf("- Sensor join key used for official locations: `%s`.", join_key_used),
  sprintf("- Unique sensors in accidents: %s.", overlap_summary$value[overlap_summary$metric == "accident_unique_sensors"]),
  sprintf("- Overlap with official sensor locations: %s%%.", overlap_summary$value[overlap_summary$metric == "accident_sensor_overlap_with_official_pct"]),
  sprintf("- Overlap with 4-month traffic history: %s%%.", overlap_summary$value[overlap_summary$metric == "accident_sensor_overlap_with_traffic_4months_pct"]),
  "",
  "## Interpretation",
  "- This phase only establishes whether a small historical traffic slice can be summarized and linked to the sensor universe already used in accidents.",
  "- Any weak or partial overlap must be treated as a data availability constraint, not as something to fix with ad-hoc joins."
)
writeLines(note_lines, quality_note_path, useBytes = TRUE)

cat("Created overlap summary:", overlap_summary_path, "\n")
cat("Created accident sensor subset:", subset_path, "\n")
cat("Created quality note:", quality_note_path, "\n")
