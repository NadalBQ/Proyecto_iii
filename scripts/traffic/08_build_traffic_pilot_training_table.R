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

safe_pct <- function(num, den) {
  if (is.na(den) || den == 0) NA_real_ else round(num / den * 100, 2)
}

coalesce_char <- function(x, y) {
  out <- x
  out[is.na(out) | out == ""] <- y[is.na(out) | out == ""]
  out
}

root <- find_repo_root()
processed_dir <- file.path(root, "data", "processed")
outputs_dir <- file.path(root, "outputs")
outputs_data_dir <- file.path(root, "outputs", "data")

pilot_unit_path <- file.path(processed_dir, "traffic_2024_4months_model_integration_pilot.csv")
traffic_joined_path <- file.path(processed_dir, "traffic_2024_4months_accident_joined.csv")
traffic_aggregated_path <- file.path(processed_dir, "traffic_2024_4months_aggregated.csv")
m9_path <- file.path(outputs_data_dir, "m9_accident_edge_matches.csv")
m10_path <- file.path(outputs_data_dir, "m10_edge_historical_aggregation.csv")

required_paths <- c(pilot_unit_path, traffic_joined_path, traffic_aggregated_path, m9_path)
missing_paths <- required_paths[!file.exists(required_paths)]
if (length(missing_paths) > 0L) {
  stop(
    sprintf("Missing required files:\n%s", paste(missing_paths, collapse = "\n")),
    call. = FALSE
  )
}

pilot_positive <- fread(
  input = pilot_unit_path,
  encoding = "UTF-8",
  showProgress = FALSE,
  na.strings = c("", "NA", "NULL")
)

pilot_positive <- pilot_positive[
  analysis_year == 2024L & month %in% c(1L, 4L, 7L, 10L)
]

pilot_key_cols <- c("edge_id", "analysis_year", "month", "temporal_bin_4h", "is_weekend")
pilot_dup_surplus <- pilot_positive[, .N, by = pilot_key_cols][N > 1, sum(N - 1L)]
if (is.na(pilot_dup_surplus)) pilot_dup_surplus <- 0L
if (pilot_dup_surplus > 0L) {
  stop(
    sprintf("traffic_2024_4months_model_integration_pilot.csv is not unique on the pilot key. Duplicate surplus rows: %s", pilot_dup_surplus),
    call. = FALSE
  )
}

traffic_joined <- fread(
  input = traffic_joined_path,
  encoding = "UTF-8",
  select = c(
    "num_expediente", "sensor_id", "analysis_year", "month", "temporal_bin_4h", "is_weekend",
    "traffic_join_status", "traffic_intensidad_mean", "traffic_ocupacion_mean", "traffic_vmed_mean", "traffic_n_observations"
  ),
  showProgress = FALSE,
  na.strings = c("", "NA", "NULL")
)

traffic_joined <- traffic_joined[
  analysis_year == 2024L & month %in% c(1L, 4L, 7L, 10L)
]

m9 <- fread(
  input = m9_path,
  encoding = "UTF-8",
  select = c("num_expediente", "edge_id"),
  showProgress = FALSE,
  na.strings = c("", "NA", "NULL")
)

traffic_aggregated <- fread(
  input = traffic_aggregated_path,
  encoding = "UTF-8",
  select = c(
    "sensor_id", "analysis_year", "month", "temporal_bin_4h", "is_weekend",
    "intensidad_mean", "ocupacion_mean", "vmed_mean", "n_observations"
  ),
  showProgress = FALSE,
  na.strings = c("", "NA", "NULL")
)
setnames(
  traffic_aggregated,
  old = c("intensidad_mean", "ocupacion_mean", "vmed_mean", "n_observations"),
  new = c("traffic_intensidad_mean", "traffic_ocupacion_mean", "traffic_vmed_mean", "traffic_n_observations")
)

time_grid <- unique(
  traffic_aggregated[
    analysis_year == 2024L & month %in% c(1L, 4L, 7L, 10L),
    .(analysis_year, month, temporal_bin_4h, is_weekend)
  ]
)
setorder(time_grid, analysis_year, month, temporal_bin_4h, is_weekend)

edge_universe <- unique(pilot_positive[, .(edge_id)])
edge_universe[, tmp_join_key := 1L]
time_grid[, tmp_join_key := 1L]
training_grid <- merge(edge_universe, time_grid, by = "tmp_join_key", allow.cartesian = TRUE)
training_grid[, tmp_join_key := NULL]

training_table <- merge(
  training_grid,
  pilot_positive,
  by = pilot_key_cols,
  all.x = TRUE,
  sort = FALSE
)

training_table[, pilot_accident_count := fifelse(is.na(pilot_accident_count), 0L, as.integer(pilot_accident_count))]
training_table[, pilot_accident_row_count_raw := fifelse(is.na(pilot_accident_row_count_raw), 0L, as.integer(pilot_accident_row_count_raw))]
training_table[, traffic_supported_accident_count := fifelse(is.na(traffic_supported_accident_count), 0L, as.integer(traffic_supported_accident_count))]
training_table[, traffic_unsupported_accident_count := fifelse(is.na(traffic_unsupported_accident_count), 0L, as.integer(traffic_unsupported_accident_count))]
training_table[, pilot_zero_generation_flag := pilot_accident_count == 0L]
training_table[, pilot_row_type := fifelse(pilot_zero_generation_flag, "zero", "positive")]
training_table[, zero_generation_rule := fifelse(
  pilot_zero_generation_flag,
  "edge_universe_from_positive_pilot_x_pilot_time_grid",
  "observed_positive_unit"
)]

edge_sensor_support <- unique(
  merge(
    traffic_joined[traffic_join_status == "matched" & !is.na(sensor_id), .(num_expediente, sensor_id)],
    m9,
    by = "num_expediente",
    all.x = FALSE,
    all.y = FALSE
  )[
    !is.na(edge_id) & !is.na(sensor_id),
    .(edge_id, sensor_id)
  ],
  by = c("edge_id", "sensor_id")
)

edge_sensor_support_summary <- edge_sensor_support[
  ,
  .(edge_sensor_support_n_total = uniqueN(sensor_id)),
  by = .(edge_id)
]

edge_sensor_traffic <- merge(
  edge_sensor_support,
  traffic_aggregated[analysis_year == 2024L & month %in% c(1L, 4L, 7L, 10L)],
  by = "sensor_id",
  all.x = FALSE,
  all.y = FALSE,
  allow.cartesian = TRUE
)

unit_traffic <- edge_sensor_traffic[
  ,
  .(
    traffic_intensidad_mean = mean(traffic_intensidad_mean, na.rm = TRUE),
    traffic_ocupacion_mean = mean(traffic_ocupacion_mean, na.rm = TRUE),
    traffic_vmed_mean = mean(traffic_vmed_mean, na.rm = TRUE),
    traffic_n_observations = sum(traffic_n_observations, na.rm = TRUE),
    traffic_support_n = uniqueN(sensor_id)
  ),
  by = .(edge_id, analysis_year, month, temporal_bin_4h, is_weekend)
]

training_table <- merge(
  training_table,
  edge_sensor_support_summary,
  by = "edge_id",
  all.x = TRUE,
  sort = FALSE
)
training_table[, edge_sensor_support_n_total := fifelse(is.na(edge_sensor_support_n_total), 0L, as.integer(edge_sensor_support_n_total))]

cols_to_drop <- intersect(
  c("traffic_intensidad_mean", "traffic_ocupacion_mean", "traffic_vmed_mean", "traffic_n_observations", "traffic_support_n", "traffic_coverage_flag", "traffic_integration_status", "traffic_integration_note"),
  names(training_table)
)
if (length(cols_to_drop) > 0L) {
  training_table[, (cols_to_drop) := NULL]
}

training_table <- merge(
  training_table,
  unit_traffic,
  by = pilot_key_cols,
  all.x = TRUE,
  sort = FALSE
)

training_table[, traffic_support_n := fifelse(is.na(traffic_support_n), 0L, as.integer(traffic_support_n))]
training_table[, traffic_n_observations := fifelse(is.na(traffic_n_observations), 0L, as.integer(traffic_n_observations))]
training_table[, traffic_coverage_flag := fifelse(traffic_support_n > 0L, "covered", "not_covered")]

training_table[, traffic_missing_reason := fifelse(
  traffic_support_n > 0L,
  "covered",
  fifelse(
    edge_sensor_support_n_total == 0L,
    "edge_has_no_pilot_sensor_support",
    "pilot_sensor_support_but_no_traffic_for_time"
  )
)]

training_table[, traffic_integration_status := fifelse(
  traffic_support_n > 0L,
  fifelse(pilot_row_type == "positive", "positive_with_traffic", "zero_with_traffic"),
  fifelse(pilot_row_type == "positive", paste0("positive_", traffic_missing_reason), paste0("zero_", traffic_missing_reason))
)]

training_table[, traffic_integration_note := fifelse(
  traffic_support_n > 0L,
  paste0(
    "sensor_support_n=", traffic_support_n,
    "; edge_sensor_support_n_total=", edge_sensor_support_n_total,
    "; pilot_row_type=", pilot_row_type
  ),
  paste0(
    "edge_sensor_support_n_total=", edge_sensor_support_n_total,
    "; pilot_row_type=", pilot_row_type,
    "; reason=", traffic_missing_reason
  )
)]

if (file.exists(m10_path)) {
  m10 <- fread(
    input = m10_path,
    encoding = "UTF-8",
    select = c("edge_id", "road_class", "street_name", "oneway_raw", "maxspeed_raw", "bridge_raw", "tunnel_raw", "edge_length_m.x", "edge_length_m.y"),
    showProgress = FALSE,
    na.strings = c("", "NA", "NULL")
  )
  m10[, edge_length_m := fifelse(!is.na(edge_length_m.x), edge_length_m.x, edge_length_m.y)]
  m10_static <- unique(
    m10[, .(edge_id, road_class, street_name, oneway_raw, maxspeed_raw, bridge_raw, tunnel_raw, edge_length_m)],
    by = "edge_id"
  )
  training_table <- merge(training_table, m10_static, by = "edge_id", all.x = TRUE, sort = FALSE)
}

temporal_bin_center_map <- data.table(
  temporal_bin_4h = c("00_03", "04_07", "08_11", "12_15", "16_19", "20_23"),
  temporal_bin_center_hour = c(1.5, 5.5, 9.5, 13.5, 17.5, 21.5)
)
training_table <- merge(training_table, temporal_bin_center_map, by = "temporal_bin_4h", all.x = TRUE, sort = FALSE)
training_table[, hour_sin := sin(2 * pi * temporal_bin_center_hour / 24)]
training_table[, hour_cos := cos(2 * pi * temporal_bin_center_hour / 24)]

setcolorder(training_table, c(
  "edge_id", "analysis_year", "month", "temporal_bin_4h", "is_weekend",
  "pilot_accident_count", "pilot_accident_row_count_raw", "pilot_row_type", "pilot_zero_generation_flag", "zero_generation_rule",
  "traffic_intensidad_mean", "traffic_ocupacion_mean", "traffic_vmed_mean", "traffic_n_observations", "traffic_support_n",
  "traffic_coverage_flag", "traffic_missing_reason", "traffic_integration_status", "traffic_integration_note",
  "edge_sensor_support_n_total", "road_class", "street_name", "oneway_raw", "maxspeed_raw", "bridge_raw", "tunnel_raw", "edge_length_m",
  "temporal_bin_center_hour", "hour_sin", "hour_cos"
))

training_table_path <- file.path(processed_dir, "traffic_2024_4months_pilot_training_table.csv")
fwrite(training_table, file = training_table_path)

summary_dt <- data.table(
  metric = c(
    "pilot_training_rows_total",
    "pilot_training_positive_rows",
    "pilot_training_zero_rows",
    "pilot_training_zero_rows_pct",
    "pilot_training_edges",
    "pilot_training_time_cells",
    "pilot_training_rows_with_traffic",
    "pilot_training_rows_with_traffic_pct",
    "pilot_training_rows_without_traffic",
    "pilot_training_rows_without_traffic_pct",
    "pilot_training_positive_rows_with_traffic",
    "pilot_training_positive_rows_with_traffic_pct",
    "pilot_training_zero_rows_with_traffic",
    "pilot_training_zero_rows_with_traffic_pct"
  ),
  value = c(
    nrow(training_table),
    sum(training_table$pilot_row_type == "positive"),
    sum(training_table$pilot_row_type == "zero"),
    safe_pct(sum(training_table$pilot_row_type == "zero"), nrow(training_table)),
    uniqueN(training_table$edge_id),
    uniqueN(training_table[, .(analysis_year, month, temporal_bin_4h, is_weekend)]),
    sum(training_table$traffic_coverage_flag == "covered"),
    safe_pct(sum(training_table$traffic_coverage_flag == "covered"), nrow(training_table)),
    sum(training_table$traffic_coverage_flag == "not_covered"),
    safe_pct(sum(training_table$traffic_coverage_flag == "not_covered"), nrow(training_table)),
    sum(training_table$pilot_row_type == "positive" & training_table$traffic_coverage_flag == "covered"),
    safe_pct(sum(training_table$pilot_row_type == "positive" & training_table$traffic_coverage_flag == "covered"), sum(training_table$pilot_row_type == "positive")),
    sum(training_table$pilot_row_type == "zero" & training_table$traffic_coverage_flag == "covered"),
    safe_pct(sum(training_table$pilot_row_type == "zero" & training_table$traffic_coverage_flag == "covered"), sum(training_table$pilot_row_type == "zero"))
  )
)

summary_path <- file.path(outputs_dir, "traffic_2024_4months_pilot_training_table_summary.csv")
fwrite(summary_dt, file = summary_path)

missing_reasons_overall <- training_table[
  ,
  .(n = .N, pct = safe_pct(.N, nrow(training_table))),
  by = .(pilot_row_type, traffic_coverage_flag, traffic_missing_reason)
]
missing_reasons_overall[, scope := "overall"]

positive_total <- sum(training_table$pilot_row_type == "positive")
missing_reasons_positive <- training_table[
  pilot_row_type == "positive",
  .(n = .N, pct = safe_pct(.N, positive_total)),
  by = .(pilot_row_type, traffic_coverage_flag, traffic_missing_reason)
]
missing_reasons_positive[, scope := "positive_only"]

zero_total <- sum(training_table$pilot_row_type == "zero")
missing_reasons_zero <- training_table[
  pilot_row_type == "zero",
  .(n = .N, pct = safe_pct(.N, zero_total)),
  by = .(pilot_row_type, traffic_coverage_flag, traffic_missing_reason)
]
missing_reasons_zero[, scope := "zero_only"]

missing_reasons_dt <- rbindlist(
  list(missing_reasons_overall, missing_reasons_positive, missing_reasons_zero),
  use.names = TRUE,
  fill = TRUE
)
setcolorder(
  missing_reasons_dt,
  c("scope", "pilot_row_type", "traffic_coverage_flag", "traffic_missing_reason", "n", "pct")
)

missing_reasons_path <- file.path(outputs_dir, "traffic_2024_4months_pilot_training_table_missing_reasons.csv")
fwrite(missing_reasons_dt, file = missing_reasons_path)

note_lines <- c(
  "# Traffic 2024 4-Month Pilot Training Table Note",
  "",
  "## Scope",
  "- This table is restricted to analysis year 2024 and months 1, 4, 7 and 10.",
  "- It is a pilot partial training table, not a full historical training table for 2016-2024.",
  "",
  "## Unit",
  "- `edge_id + analysis_year + month + temporal_bin_4h + is_weekend`.",
  "",
  "## Zero generation rule",
  "- Edge universe: only edges already observed in the positive pilot model integration table.",
  "- Time grid: only `(analysis_year, month, temporal_bin_4h, is_weekend)` combinations actually present in the pilot traffic aggregate.",
  "- Zero rows were generated as `pilot_edge_universe x pilot_time_grid` minus observed positive units.",
  "- This avoids expanding the entire road network while still creating defensible zeros inside the pilot temporal frame.",
  "",
  "## Traffic integration",
  "- Traffic for both positives and zeros was propagated from a pilot edge-to-sensor support map derived from matched pilot accidents.",
  "- Rows with no traffic support are separated from rows with traffic support.",
  "- Missing traffic inside the pilot is therefore interpreted as pilot-period support limitation, not as absence outside the pilot temporal coverage.",
  "",
  "## Status",
  "- This table is ready for a next pilot re-training phase with and without traffic.",
  "- It must not be interpreted as a final system-wide table or as routing-ready coverage."
)

note_path <- file.path(outputs_dir, "traffic_2024_4months_pilot_training_table_note.md")
writeLines(note_lines, note_path, useBytes = TRUE)

cat("Created pilot training table:", training_table_path, "\n")
cat("Created training table summary:", summary_path, "\n")
cat("Created missing reasons summary:", missing_reasons_path, "\n")
cat("Created note:", note_path, "\n")
