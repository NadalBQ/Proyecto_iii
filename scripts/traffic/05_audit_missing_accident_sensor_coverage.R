if (!requireNamespace("data.table", quietly = TRUE)) {
  stop("This script requires data.table.", call. = FALSE)
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

safe_pct <- function(num, den) {
  if (is.na(den) || den == 0) NA_real_ else round(num / den * 100, 2)
}

root <- find_repo_root()
outputs_dir <- file.path(root, "outputs")

accident_path <- file.path(root, "data/raw/accidents/accidentes_con_trafico_final.csv")
traffic_aggregated_path <- file.path(root, "data/processed/traffic_2024_4months_aggregated.csv")
traffic_panel_path <- file.path(root, "data/processed/traffic_2024_4months_sensor_panel.csv")
traffic_subset_path <- file.path(root, "data/processed/traffic_2024_4months_aggregated_accident_sensor_subset.csv")
overlap_summary_path <- file.path(root, "outputs/traffic_accident_sensor_overlap_summary.csv")
sensor_locations_path <- file.path(root, "data/raw/traffic_sensor_locations/sensor_locations.csv")

required_paths <- c(
  accident_path,
  traffic_aggregated_path,
  traffic_panel_path,
  traffic_subset_path,
  overlap_summary_path
)

missing_paths <- required_paths[!file.exists(required_paths)]
if (length(missing_paths) > 0L) {
  stop(
    sprintf("Missing required files:\n%s", paste(missing_paths, collapse = "\n")),
    call. = FALSE
  )
}

accidents <- fread(
  input = accident_path,
  sep = ",",
  encoding = "UTF-8",
  select = c("fecha", "hora", "distrito", "id_sensor_cercano"),
  showProgress = FALSE,
  na.strings = c("", "NA", "NULL")
)
setnames(accidents, normalize_names(names(accidents)))

traffic_aggregated <- fread(
  input = traffic_aggregated_path,
  encoding = "UTF-8",
  select = "sensor_id",
  showProgress = FALSE,
  na.strings = c("", "NA", "NULL")
)

overlap_summary <- fread(
  input = overlap_summary_path,
  encoding = "UTF-8",
  showProgress = FALSE
)

sensor_locations <- NULL
if (file.exists(sensor_locations_path)) {
  sensor_locations <- fread(
    input = sensor_locations_path,
    sep = ";",
    encoding = "UTF-8",
    select = c("id", "tipo_elem", "distrito", "nombre", "latitud", "longitud"),
    showProgress = FALSE,
    na.strings = c("", "NA", "NULL")
  )
  setnames(sensor_locations, normalize_names(names(sensor_locations)))
  sensor_locations[, sensor_id := suppressWarnings(as.integer(as.numeric(id)))]
  sensor_locations[, distrito_sensor := suppressWarnings(as.integer(as.numeric(distrito)))]
  sensor_locations[, sensor_name := as.character(nombre)]
  sensor_locations[, latitud := suppressWarnings(as.numeric(latitud))]
  sensor_locations[, longitud := suppressWarnings(as.numeric(longitud))]
  sensor_locations <- unique(
    sensor_locations[!is.na(sensor_id), .(sensor_id, tipo_elem, distrito_sensor, sensor_name, latitud, longitud)],
    by = "sensor_id"
  )
}

accidents[, sensor_id := suppressWarnings(as.integer(as.numeric(id_sensor_cercano)))]
accidents[, analysis_year := suppressWarnings(as.integer(substr(as.character(fecha), 1L, 4L)))]
accidents[, hour := suppressWarnings(as.integer(substr(as.character(hora), 1L, 2L)))]
accidents[, temporal_bin_4h := fifelse(
  is.na(hour),
  NA_character_,
  c("00_03", "04_07", "08_11", "12_15", "16_19", "20_23")[pmax(pmin(floor(hour / 4) + 1L, 6L), 1L)]
)]
accidents[, distrito := as.character(distrito)]

covered_sensor_set <- sort(unique(traffic_aggregated$sensor_id[!is.na(traffic_aggregated$sensor_id)]))
accident_sensor_set <- sort(unique(accidents$sensor_id[!is.na(accidents$sensor_id)]))
missing_sensor_set <- setdiff(accident_sensor_set, covered_sensor_set)

accidents[, coverage_status := fifelse(
  is.na(sensor_id),
  "sensor_id_missing_in_accident_row",
  fifelse(sensor_id %in% covered_sensor_set, "covered_sensor", "missing_sensor")
)]

accidents_with_sensor <- accidents[!is.na(sensor_id)]
missing_rows_n <- nrow(accidents_with_sensor[coverage_status == "missing_sensor"])
covered_rows_n <- nrow(accidents_with_sensor[coverage_status == "covered_sensor"])
total_rows_n <- nrow(accidents)

missing_sensor_impact <- accidents_with_sensor[
  coverage_status == "missing_sensor",
  .(
    accident_rows = .N,
    years_present_n = uniqueN(analysis_year),
    first_year = suppressWarnings(min(analysis_year, na.rm = TRUE)),
    last_year = suppressWarnings(max(analysis_year, na.rm = TRUE)),
    top_distrito = names(sort(table(distrito), decreasing = TRUE))[1],
    top_temporal_bin_4h = names(sort(table(temporal_bin_4h), decreasing = TRUE))[1]
  ),
  by = .(sensor_id)
][order(-accident_rows, sensor_id)]

missing_sensor_impact[!is.finite(first_year), first_year := NA_integer_]
missing_sensor_impact[!is.finite(last_year), last_year := NA_integer_]
missing_sensor_impact[, cumulative_missing_rows := cumsum(accident_rows)]
missing_sensor_impact[, cumulative_missing_rows_pct := safe_pct(cumulative_missing_rows, missing_rows_n)]
missing_sensor_impact[, missing_sensor_rank := seq_len(.N)]

if (!is.null(sensor_locations)) {
  missing_sensor_impact <- merge(
    missing_sensor_impact,
    sensor_locations,
    by = "sensor_id",
    all.x = TRUE
  )
  missing_sensor_impact[, in_official_sensor_locations := !is.na(sensor_name) | !is.na(distrito_sensor) | !is.na(latitud) | !is.na(longitud)]
} else {
  missing_sensor_impact[, `:=`(
    tipo_elem = NA_character_,
    distrito_sensor = NA_integer_,
    sensor_name = NA_character_,
    latitud = NA_real_,
    longitud = NA_real_,
    in_official_sensor_locations = NA
  )]
}

setorder(missing_sensor_impact, -accident_rows, sensor_id)
missing_sensor_impact[, cumulative_missing_rows := cumsum(accident_rows)]
missing_sensor_impact[, cumulative_missing_rows_pct := safe_pct(cumulative_missing_rows, missing_rows_n)]
missing_sensor_impact[, missing_sensor_rank := seq_len(.N)]

missing_list_path <- file.path(outputs_dir, "missing_accident_sensors_list.csv")
fwrite(missing_sensor_impact, file = missing_list_path)

top_contributors <- copy(missing_sensor_impact[seq_len(min(nrow(missing_sensor_impact), 25L))])
top_contributors_path <- file.path(outputs_dir, "missing_accident_sensor_top_contributors.csv")
fwrite(top_contributors, file = top_contributors_path)

year_breakdown <- accidents_with_sensor[
  ,
  .(
    total_accident_rows = .N,
    missing_sensor_rows = sum(coverage_status == "missing_sensor"),
    covered_sensor_rows = sum(coverage_status == "covered_sensor"),
    missing_sensor_row_pct = safe_pct(sum(coverage_status == "missing_sensor"), .N)
  ),
  by = .(analysis_year)
][order(analysis_year)]

distrito_breakdown <- accidents_with_sensor[
  coverage_status == "missing_sensor",
  .(missing_sensor_rows = .N),
  by = .(distrito)
][order(-missing_sensor_rows, distrito)]

hour_breakdown <- accidents_with_sensor[
  coverage_status == "missing_sensor",
  .(missing_sensor_rows = .N),
  by = .(temporal_bin_4h)
][order(temporal_bin_4h)]

concentration_top_10_n <- sum(head(missing_sensor_impact$accident_rows, 10L))
concentration_top_25_n <- sum(head(missing_sensor_impact$accident_rows, 25L))

impact_summary <- rbindlist(list(
  data.table(
    section = "overall",
    subgroup = "all",
    metric = c(
      "total_accident_rows",
      "accident_rows_with_sensor_id",
      "accident_rows_with_covered_sensors",
      "accident_rows_with_missing_sensors",
      "affected_accident_row_pct",
      "accident_unique_sensors",
      "covered_accident_sensors",
      "missing_accident_sensors",
      "top_10_missing_sensors_row_pct_of_missing_rows",
      "top_25_missing_sensors_row_pct_of_missing_rows"
    ),
    value = c(
      total_rows_n,
      nrow(accidents_with_sensor),
      covered_rows_n,
      missing_rows_n,
      safe_pct(missing_rows_n, nrow(accidents_with_sensor)),
      uniqueN(accident_sensor_set),
      length(covered_sensor_set[covered_sensor_set %in% accident_sensor_set]),
      length(missing_sensor_set),
      safe_pct(concentration_top_10_n, missing_rows_n),
      safe_pct(concentration_top_25_n, missing_rows_n)
    )
  ),
  data.table(
    section = "by_analysis_year",
    subgroup = as.character(year_breakdown$analysis_year),
    metric = "missing_sensor_row_pct",
    value = year_breakdown$missing_sensor_row_pct
  ),
  data.table(
    section = "by_analysis_year",
    subgroup = as.character(year_breakdown$analysis_year),
    metric = "missing_sensor_rows",
    value = year_breakdown$missing_sensor_rows
  ),
  data.table(
    section = "top_missing_distritos",
    subgroup = as.character(distrito_breakdown$distrito[1:min(nrow(distrito_breakdown), 15L)]),
    metric = "missing_sensor_rows",
    value = distrito_breakdown$missing_sensor_rows[1:min(nrow(distrito_breakdown), 15L)]
  ),
  data.table(
    section = "missing_rows_by_temporal_bin_4h",
    subgroup = as.character(hour_breakdown$temporal_bin_4h),
    metric = "missing_sensor_rows",
    value = hour_breakdown$missing_sensor_rows
  )
), use.names = TRUE, fill = TRUE)

impact_summary_path <- file.path(outputs_dir, "missing_accident_sensor_impact_summary.csv")
fwrite(impact_summary, file = impact_summary_path)

operationally_acceptable <- safe_pct(missing_rows_n, nrow(accidents_with_sensor)) <= 10
top_10_pct <- safe_pct(concentration_top_10_n, missing_rows_n)

recommendation <- if (isTRUE(operationally_acceptable)) {
  "Coverage gap looks operationally acceptable for a pilot traffic integration. Keep the current 4-month layer and document the uncovered sensors as a bounded limitation."
} else {
  "Coverage gap looks too large for a clean pilot integration. Do not assume the current 4-month traffic layer is enough; revisit period expansion before downstream integration."
}

note_lines <- c(
  "# Missing Accident Sensor Coverage Audit",
  "",
  "## Scope",
  "- This audit uses the already-built 4-month 2024 traffic layer.",
  "- It does not reprocess traffic, does not add months, and does not enter modeling or routing.",
  "",
  "## Join key",
  "- `id_sensor_cercano` in accidents was normalized to `sensor_id` and compared against `sensor_id` in `traffic_2024_4months_aggregated.csv`.",
  "",
  "## Core impact",
  sprintf("- Total accident rows: %s.", total_rows_n),
  sprintf("- Accident rows with covered sensors: %s.", covered_rows_n),
  sprintf("- Accident rows with missing sensors: %s.", missing_rows_n),
  sprintf("- Affected accident row percentage: %s%%.", safe_pct(missing_rows_n, nrow(accidents_with_sensor))),
  sprintf("- Missing sensors count: %s.", length(missing_sensor_set)),
  sprintf("- Top 10 missing sensors concentrate %s%% of the missing-sensor accident rows.", top_10_pct),
  "",
  "## Operational reading",
  if (isTRUE(operationally_acceptable)) {
    "- The gap is not zero, but its row-level impact stays below a 10% threshold and is operationally manageable for a pilot integration."
  } else {
    "- The gap is large enough at row level to risk a material blind spot in any downstream pilot integration."
  },
  "",
  "## Recommendation",
  paste0("- ", recommendation)
)

note_path <- file.path(outputs_dir, "missing_accident_sensor_impact_note.md")
writeLines(note_lines, note_path, useBytes = TRUE)

cat("Created missing sensor list:", missing_list_path, "\n")
cat("Created impact summary:", impact_summary_path, "\n")
cat("Created top contributors:", top_contributors_path, "\n")
cat("Created note:", note_path, "\n")
