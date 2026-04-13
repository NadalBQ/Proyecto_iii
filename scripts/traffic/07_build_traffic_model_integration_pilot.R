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

unique_or_na <- function(x) {
  values <- unique(x[!is.na(x) & x != ""])
  if (length(values) == 0L) {
    return(NA)
  }
  if (length(values) == 1L) {
    return(values[[1L]])
  }
  NA
}

safe_pct <- function(num, den) {
  if (is.na(den) || den == 0) NA_real_ else round(num / den * 100, 2)
}

collapse_reason <- function(reasons) {
  reasons <- sort(unique(reasons[!is.na(reasons) & reasons != "matched" & reasons != ""]))
  if (length(reasons) == 0L) {
    return(NA_character_)
  }
  if (length(reasons) == 1L) {
    return(reasons[[1L]])
  }
  "mixed_missing_reasons"
}

root <- find_repo_root()
processed_dir <- file.path(root, "data", "processed")
outputs_dir <- file.path(root, "outputs")
outputs_data_dir <- file.path(root, "outputs", "data")

traffic_joined_path <- file.path(processed_dir, "traffic_2024_4months_accident_joined.csv")
traffic_model_ready_path <- file.path(processed_dir, "traffic_2024_4months_model_ready.csv")
m9_path <- file.path(outputs_data_dir, "m9_accident_edge_matches.csv")
m10_path <- file.path(outputs_data_dir, "m10_edge_historical_aggregation.csv")
m11_path <- file.path(outputs_data_dir, "m11_historical_exposure_adjusted.csv")
m12_path <- file.path(outputs_data_dir, "m12_edge_context_dynamic_base.csv")

required_paths <- c(traffic_joined_path, traffic_model_ready_path, m9_path)
missing_paths <- required_paths[!file.exists(required_paths)]
if (length(missing_paths) > 0L) {
  stop(
    sprintf("Missing required files:\n%s", paste(missing_paths, collapse = "\n")),
    call. = FALSE
  )
}

traffic_joined <- fread(
  input = traffic_joined_path,
  encoding = "UTF-8",
  select = c(
    "accident_row_id", "num_expediente", "analysis_year", "month", "temporal_bin_4h", "is_weekend",
    "sensor_id", "traffic_join_status", "traffic_missing_reason",
    "traffic_intensidad_mean", "traffic_ocupacion_mean", "traffic_vmed_mean", "traffic_n_observations",
    "traffic_sensor_match_flag", "traffic_sensor_id_usable_flag", "traffic_time_match_flag",
    "traffic_within_pilot_period_flag"
  ),
  showProgress = FALSE,
  na.strings = c("", "NA", "NULL")
)

m9 <- fread(
  input = m9_path,
  encoding = "UTF-8",
  select = c("num_expediente", "edge_id", "quality_flag", "match_status"),
  showProgress = FALSE,
  na.strings = c("", "NA", "NULL")
)

if (file.exists(m10_path)) {
  m10_header <- names(fread(m10_path, nrows = 0L))
} else {
  m10_header <- character()
}
if (file.exists(m11_path)) {
  m11_header <- names(fread(m11_path, nrows = 0L))
} else {
  m11_header <- character()
}
if (file.exists(m12_path)) {
  m12_header <- names(fread(m12_path, nrows = 0L))
} else {
  m12_header <- character()
}

m9_dup_surplus <- m9[, .N, by = .(num_expediente)][N > 1, sum(N - 1L)]
if (is.na(m9_dup_surplus)) m9_dup_surplus <- 0L
if (m9_dup_surplus > 0L) {
  stop(
    sprintf("m9_accident_edge_matches.csv is not unique on num_expediente. Duplicate surplus rows: %s", m9_dup_surplus),
    call. = FALSE
  )
}

pilot_rows <- traffic_joined[
  analysis_year == 2024L & month %in% c(1L, 4L, 7L, 10L) & traffic_within_pilot_period_flag == TRUE
]

accident_level <- pilot_rows[
  ,
  .(
    accident_row_count_raw = .N,
    analysis_year = as.integer(unique_or_na(as.character(analysis_year))),
    month = as.integer(unique_or_na(as.character(month))),
    temporal_bin_4h = as.character(unique_or_na(as.character(temporal_bin_4h))),
    is_weekend = as.integer(unique_or_na(as.character(is_weekend))),
    pilot_key_conflict_flag = (
      uniqueN(analysis_year[!is.na(analysis_year)]) > 1L |
      uniqueN(month[!is.na(month)]) > 1L |
      uniqueN(temporal_bin_4h[!is.na(temporal_bin_4h)]) > 1L |
      uniqueN(is_weekend[!is.na(is_weekend)]) > 1L
    ),
    traffic_matched_row_count = sum(traffic_join_status == "matched"),
    traffic_sensor_id_usable_any = any(traffic_sensor_id_usable_flag == TRUE, na.rm = TRUE),
    traffic_sensor_match_any = any(traffic_sensor_match_flag == TRUE, na.rm = TRUE),
    traffic_time_match_any = any(traffic_time_match_flag == TRUE, na.rm = TRUE),
    traffic_missing_reason_primary = collapse_reason(traffic_missing_reason),
    traffic_missing_reason_set = paste(sort(unique(traffic_missing_reason[traffic_missing_reason != "matched" & !is.na(traffic_missing_reason)])), collapse = ";")
  ),
  by = .(num_expediente)
]

accident_traffic_support <- unique(
  pilot_rows[
    traffic_join_status == "matched",
    .(
      num_expediente,
      sensor_id,
      traffic_intensidad_mean,
      traffic_ocupacion_mean,
      traffic_vmed_mean,
      traffic_n_observations
    )
  ],
  by = c("num_expediente", "sensor_id")
)

accident_traffic_support_summary <- accident_traffic_support[
  ,
  .(
    accident_traffic_intensidad_mean = mean(traffic_intensidad_mean, na.rm = TRUE),
    accident_traffic_ocupacion_mean = mean(traffic_ocupacion_mean, na.rm = TRUE),
    accident_traffic_vmed_mean = mean(traffic_vmed_mean, na.rm = TRUE),
    accident_traffic_n_observations = sum(traffic_n_observations, na.rm = TRUE),
    accident_traffic_support_n = uniqueN(sensor_id)
  ),
  by = .(num_expediente)
]

accident_level <- merge(
  accident_level,
  accident_traffic_support_summary,
  by = "num_expediente",
  all.x = TRUE
)

accident_level <- merge(
  accident_level,
  m9[, .(num_expediente, edge_id, edge_match_quality_flag = quality_flag)],
  by = "num_expediente",
  all.x = TRUE
)

accident_level[, edge_match_flag := !is.na(edge_id)]
accident_level[, traffic_data_available_flag := traffic_matched_row_count > 0L]
accident_level[, accident_integration_status := fifelse(
  pilot_key_conflict_flag,
  "pilot_key_conflict",
  fifelse(
    !edge_match_flag,
    "edge_missing_from_m9",
    fifelse(
      traffic_data_available_flag,
      "traffic_available",
      fifelse(
        is.na(traffic_missing_reason_primary),
        "traffic_missing_unknown",
        traffic_missing_reason_primary
      )
    )
  )
)]

accident_level_eligible <- accident_level[
  edge_match_flag == TRUE &
    pilot_key_conflict_flag == FALSE &
    !is.na(analysis_year) &
    !is.na(month) &
    !is.na(temporal_bin_4h) &
    !is.na(is_weekend)
]

unit_accident_base <- accident_level_eligible[
  ,
  .(
    pilot_accident_count = .N,
    pilot_accident_row_count_raw = sum(accident_row_count_raw),
    traffic_supported_accident_count = sum(traffic_data_available_flag),
    traffic_unsupported_accident_count = sum(!traffic_data_available_flag),
    traffic_unit_missing_reason_primary = collapse_reason(accident_integration_status[!traffic_data_available_flag]),
    traffic_unit_missing_reason_set = paste(sort(unique(accident_integration_status[!traffic_data_available_flag & !is.na(accident_integration_status)])), collapse = ";")
  ),
  by = .(edge_id, analysis_year, month, temporal_bin_4h, is_weekend)
]

accident_support_with_unit <- merge(
  accident_traffic_support,
  accident_level_eligible[, .(num_expediente, edge_id, analysis_year, month, temporal_bin_4h, is_weekend)],
  by = "num_expediente",
  all.x = FALSE,
  all.y = FALSE
)

unit_sensor_support <- unique(
  accident_support_with_unit,
  by = c("edge_id", "analysis_year", "month", "temporal_bin_4h", "is_weekend", "sensor_id")
)

unit_traffic_summary <- unit_sensor_support[
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

pilot_unit <- merge(
  unit_accident_base,
  unit_traffic_summary,
  by = c("edge_id", "analysis_year", "month", "temporal_bin_4h", "is_weekend"),
  all.x = TRUE
)

pilot_unit[, traffic_support_n := fifelse(is.na(traffic_support_n), 0L, as.integer(traffic_support_n))]
pilot_unit[, traffic_coverage_flag := fifelse(traffic_support_n > 0L, "covered", "not_covered")]
pilot_unit[, traffic_integration_status := fifelse(
  traffic_support_n == 0L,
  fifelse(
    is.na(traffic_unit_missing_reason_primary) | traffic_unit_missing_reason_primary == "",
    "no_traffic_support_unknown",
    paste0("no_traffic_support_", traffic_unit_missing_reason_primary)
  ),
  fifelse(
    traffic_supported_accident_count == pilot_accident_count,
    "full_traffic_support",
    "partial_traffic_support"
  )
)]
pilot_unit[, traffic_integration_note := fifelse(
  traffic_support_n > 0L,
  paste0(
    "pilot_accidents=", pilot_accident_count,
    "; traffic_supported_accidents=", traffic_supported_accident_count,
    "; sensor_support_n=", traffic_support_n
  ),
  paste0(
    "pilot_accidents=", pilot_accident_count,
    "; no traffic support; reasons=",
    fifelse(is.na(traffic_unit_missing_reason_set) | traffic_unit_missing_reason_set == "", "unknown", traffic_unit_missing_reason_set)
  )
)]

setorder(pilot_unit, edge_id, analysis_year, month, temporal_bin_4h, is_weekend)

pilot_output_path <- file.path(processed_dir, "traffic_2024_4months_model_integration_pilot.csv")
fwrite(pilot_unit, file = pilot_output_path)

full_joined_rows_n <- nrow(traffic_joined)
pilot_rows_n <- nrow(pilot_rows)
pilot_unique_accidents_n <- uniqueN(pilot_rows$num_expediente)
pilot_unique_accidents_edge_linked_n <- nrow(accident_level_eligible)
pilot_unique_accidents_edge_missing_n <- sum(accident_level$accident_integration_status == "edge_missing_from_m9")
pilot_units_total_n <- nrow(pilot_unit)
pilot_units_covered_n <- nrow(pilot_unit[traffic_coverage_flag == "covered"])
pilot_units_not_covered_n <- nrow(pilot_unit[traffic_coverage_flag == "not_covered"])

integration_summary <- data.table(
  metric = c(
    "full_joined_dataset_rows",
    "pilot_period_rows_raw",
    "pilot_period_rows_raw_pct_of_full_joined",
    "pilot_period_unique_accidents",
    "pilot_period_unique_accidents_edge_linked",
    "pilot_period_unique_accidents_edge_linked_pct",
    "pilot_period_unique_accidents_edge_missing",
    "pilot_unit_rows_total",
    "pilot_unit_rows_with_traffic_coverage",
    "pilot_unit_rows_with_traffic_coverage_pct",
    "pilot_unit_rows_without_traffic_coverage",
    "pilot_unit_rows_without_traffic_coverage_pct",
    "m9_duplicate_num_expediente_surplus_rows",
    "m10_header_found",
    "m11_header_found",
    "m12_header_found"
  ),
  value = c(
    full_joined_rows_n,
    pilot_rows_n,
    safe_pct(pilot_rows_n, full_joined_rows_n),
    pilot_unique_accidents_n,
    pilot_unique_accidents_edge_linked_n,
    safe_pct(pilot_unique_accidents_edge_linked_n, pilot_unique_accidents_n),
    pilot_unique_accidents_edge_missing_n,
    pilot_units_total_n,
    pilot_units_covered_n,
    safe_pct(pilot_units_covered_n, pilot_units_total_n),
    pilot_units_not_covered_n,
    safe_pct(pilot_units_not_covered_n, pilot_units_total_n),
    m9_dup_surplus,
    length(m10_header) > 0L,
    length(m11_header) > 0L,
    length(m12_header) > 0L
  )
)

integration_summary_path <- file.path(outputs_dir, "traffic_2024_4months_model_integration_summary.csv")
fwrite(integration_summary, file = integration_summary_path)

missing_reasons_accident <- accident_level[
  ,
  .(n = .N),
  by = .(reason = accident_integration_status)
][, `:=`(
  scope = "pilot_unique_accidents",
  pct = safe_pct(n, nrow(accident_level))
)]

missing_reasons_unit <- pilot_unit[
  ,
  .(n = .N),
  by = .(reason = traffic_integration_status)
][, `:=`(
  scope = "pilot_model_units",
  pct = safe_pct(n, nrow(pilot_unit))
)]

missing_reasons_summary <- rbindlist(
  list(missing_reasons_accident, missing_reasons_unit),
  use.names = TRUE,
  fill = TRUE
)[, .(scope, reason, n, pct)]

missing_reasons_path <- file.path(outputs_dir, "traffic_2024_4months_model_integration_missing_reasons.csv")
fwrite(missing_reasons_summary, file = missing_reasons_path)

integration_note_lines <- c(
  "# Traffic 2024 4-Month Model Integration Pilot Note",
  "",
  "## Chosen unit",
  "- `edge_id + analysis_year + month + temporal_bin_4h + is_weekend`.",
  "- This is a conservative extension of the existing edge-based modeling logic because the traffic pilot is explicitly monthly and only covers months 1, 4, 7 and 10 of 2024.",
  "",
  "## Integration logic",
  "- Base traffic source: `traffic_2024_4months_accident_joined.csv` restricted to 2024 and months 1, 4, 7 and 10.",
  "- Edge linkage: `num_expediente -> edge_id` through `m9_accident_edge_matches.csv`.",
  "- Accident rows were first collapsed to one pilot row per `num_expediente` for auditability; then those accident-level rows were aggregated to the chosen unit.",
  "- Traffic support inside each unit was summarized from distinct contributing `sensor_id` values to avoid accident-row repetition inflating the traffic signal.",
  "",
  "## Coverage reading",
  sprintf("- Pilot-period unique accidents: %s.", pilot_unique_accidents_n),
  sprintf("- Pilot-period unique accidents linked to edge_id: %s (%s%%).", pilot_unique_accidents_edge_linked_n, safe_pct(pilot_unique_accidents_edge_linked_n, pilot_unique_accidents_n)),
  sprintf("- Pilot model units total: %s.", pilot_units_total_n),
  sprintf("- Pilot model units with usable traffic support: %s (%s%%).", pilot_units_covered_n, safe_pct(pilot_units_covered_n, pilot_units_total_n)),
  sprintf("- Pilot model units without usable traffic support: %s (%s%%).", pilot_units_not_covered_n, safe_pct(pilot_units_not_covered_n, pilot_units_total_n)),
  "",
  "## Missing interpretation",
  "- Outside-pilot temporal absence is not carried into this table as a normal feature missing; the table is already restricted to the pilot period.",
  "- Remaining non-coverage inside the pilot is therefore interpreted as pilot-period support/match limitation, not as historical absence of traffic for 2016-2024.",
  "",
  "## Status",
  "- This table is ready for a next pilot re-training phase with traffic, but only as a restricted 2024 pilot subset.",
  "- It is not a routing-ready layer and it must not be treated as full historical traffic coverage."
)

integration_note_path <- file.path(outputs_dir, "traffic_2024_4months_model_integration_note.md")
writeLines(integration_note_lines, integration_note_path, useBytes = TRUE)

cat("Created pilot model integration table:", pilot_output_path, "\n")
cat("Created integration summary:", integration_summary_path, "\n")
cat("Created missing reasons summary:", missing_reasons_path, "\n")
cat("Created integration note:", integration_note_path, "\n")
