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

pilot_months <- c(1L, 4L, 7L, 10L)
temporal_bin_labels <- c("00_03", "04_07", "08_11", "12_15", "16_19", "20_23")

root <- find_repo_root()
processed_dir <- file.path(root, "data", "processed")
outputs_dir <- file.path(root, "outputs")

accident_path <- file.path(root, "data", "raw", "accidents", "accidentes_con_trafico_final.csv")
traffic_aggregated_path <- file.path(processed_dir, "traffic_2024_4months_aggregated.csv")

required_paths <- c(accident_path, traffic_aggregated_path)
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
  showProgress = FALSE,
  na.strings = c("", "NA", "NULL")
)
setnames(accidents, normalize_names(names(accidents)))
accidents[, accident_row_id := .I]

traffic <- fread(
  input = traffic_aggregated_path,
  encoding = "UTF-8",
  select = c(
    "sensor_id", "analysis_year", "month", "temporal_bin_4h", "is_weekend",
    "intensidad_mean", "ocupacion_mean", "vmed_mean", "n_observations"
  ),
  showProgress = FALSE,
  na.strings = c("", "NA", "NULL")
)

traffic_key_cols <- c("sensor_id", "analysis_year", "month", "temporal_bin_4h", "is_weekend")
traffic_dup_n <- traffic[, .N, by = traffic_key_cols][N > 1, sum(N - 1L)]
if (is.na(traffic_dup_n)) traffic_dup_n <- 0L
if (traffic_dup_n > 0L) {
  stop(
    sprintf("traffic_2024_4months_aggregated.csv is not unique on the join key. Duplicate surplus rows: %s", traffic_dup_n),
    call. = FALSE
  )
}

setnames(
  traffic,
  old = c("intensidad_mean", "ocupacion_mean", "vmed_mean", "n_observations"),
  new = c("traffic_intensidad_mean", "traffic_ocupacion_mean", "traffic_vmed_mean", "traffic_n_observations")
)

traffic_sensor_set <- sort(unique(traffic$sensor_id[!is.na(traffic$sensor_id)]))
traffic_time_keys <- unique(traffic[, .(analysis_year, month, temporal_bin_4h, is_weekend)])
traffic_time_keys[, traffic_time_match_flag := TRUE]

accidents[, fecha_text := as.character(fecha)]
accidents[, hora_text := trimws(as.character(hora))]
accidents[, accident_date := as.IDate(fecha_text, format = "%Y-%m-%d")]
accidents[, hour := suppressWarnings(as.integer(substr(hora_text, 1L, 2L)))]
accidents[, sensor_id := suppressWarnings(as.integer(as.numeric(id_sensor_cercano)))]
accidents[, analysis_year := fifelse(is.na(accident_date), NA_integer_, as.integer(format(accident_date, "%Y")))]
accidents[, month := fifelse(is.na(accident_date), NA_integer_, as.integer(format(accident_date, "%m")))]
accidents[, is_weekend := fifelse(
  is.na(accident_date),
  NA_integer_,
  as.integer(as.POSIXlt(as.Date(accident_date), tz = "Europe/Madrid")$wday %in% c(0L, 6L))
)]
accidents[, temporal_bin_4h := fifelse(
  is.na(hour) | hour < 0L | hour > 23L,
  NA_character_,
  temporal_bin_labels[pmax(pmin(floor(hour / 4) + 1L, length(temporal_bin_labels)), 1L)]
)]
accidents[, traffic_parse_success_flag := !is.na(accident_date) & !is.na(hour) & hour >= 0L & hour <= 23L & !is.na(analysis_year) & !is.na(month) & !is.na(temporal_bin_4h) & !is.na(is_weekend)]
accidents[, traffic_within_pilot_period_flag := traffic_parse_success_flag & analysis_year == 2024L & month %in% pilot_months]
accidents[, traffic_sensor_id_usable_flag := !is.na(sensor_id) & sensor_id > 0L]
accidents[, traffic_sensor_match_flag := traffic_sensor_id_usable_flag & sensor_id %in% traffic_sensor_set]

joined <- merge(
  accidents,
  traffic_time_keys,
  by = c("analysis_year", "month", "temporal_bin_4h", "is_weekend"),
  all.x = TRUE,
  sort = FALSE
)
joined[is.na(traffic_time_match_flag), traffic_time_match_flag := FALSE]

joined <- merge(
  joined,
  traffic,
  by = traffic_key_cols,
  all.x = TRUE,
  sort = FALSE
)

setorder(joined, accident_row_id)

if (nrow(joined) != nrow(accidents)) {
  stop(
    sprintf("LEFT JOIN changed row count: accidents=%s, joined=%s", nrow(accidents), nrow(joined)),
    call. = FALSE
  )
}

joined[, traffic_exact_match_flag := !is.na(traffic_n_observations)]
joined[, traffic_missing_reason := fifelse(
  traffic_exact_match_flag,
  "matched",
  fifelse(
    !traffic_parse_success_flag,
    "parse_failure",
    fifelse(
      !traffic_within_pilot_period_flag,
      "outside_traffic_pilot_period",
      fifelse(
        !traffic_sensor_id_usable_flag,
        "missing_sensor_id",
        fifelse(
          !traffic_time_match_flag,
          "time_key_not_found",
          fifelse(
            !traffic_sensor_match_flag,
            "sensor_not_in_traffic_pilot",
            "sensor_and_time_match_not_found"
          )
        )
      )
    )
  )
)]

joined[, traffic_join_status := fifelse(traffic_exact_match_flag, "matched", "not_matched")]

if (any(joined$traffic_join_status == "not_matched" & is.na(joined$traffic_missing_reason))) {
  stop("Found unmatched rows without traffic_missing_reason.", call. = FALSE)
}

joined_path <- file.path(processed_dir, "traffic_2024_4months_accident_joined.csv")
fwrite(joined, file = joined_path)

model_ready <- joined[traffic_parse_success_flag == TRUE & traffic_within_pilot_period_flag == TRUE]
model_ready_path <- file.path(processed_dir, "traffic_2024_4months_model_ready.csv")
fwrite(model_ready, file = model_ready_path)

overall_n <- nrow(joined)
pilot_n <- nrow(joined[traffic_within_pilot_period_flag == TRUE])
outside_pilot_n <- nrow(joined[traffic_parse_success_flag == TRUE & traffic_within_pilot_period_flag == FALSE])
parse_failure_n <- nrow(joined[traffic_missing_reason == "parse_failure"])
matched_n <- nrow(joined[traffic_join_status == "matched"])
matched_pilot_n <- nrow(joined[traffic_within_pilot_period_flag == TRUE & traffic_join_status == "matched"])

join_quality_summary <- data.table(
  metric = c(
    "accident_rows_total",
    "accident_rows_after_left_join",
    "row_loss_n",
    "row_loss_pct",
    "traffic_duplicate_key_surplus_rows",
    "parse_success_rows",
    "parse_success_pct",
    "pilot_period_rows",
    "pilot_period_rows_pct",
    "outside_pilot_period_rows",
    "outside_pilot_period_rows_pct",
    "matched_rows_global",
    "matched_rows_global_pct",
    "matched_rows_within_pilot_period",
    "matched_rows_within_pilot_period_pct",
    "model_ready_rows"
  ),
  value = c(
    nrow(accidents),
    nrow(joined),
    nrow(accidents) - nrow(joined),
    safe_pct(nrow(accidents) - nrow(joined), nrow(accidents)),
    traffic_dup_n,
    sum(joined$traffic_parse_success_flag),
    safe_pct(sum(joined$traffic_parse_success_flag), overall_n),
    pilot_n,
    safe_pct(pilot_n, overall_n),
    outside_pilot_n,
    safe_pct(outside_pilot_n, overall_n),
    matched_n,
    safe_pct(matched_n, overall_n),
    matched_pilot_n,
    safe_pct(matched_pilot_n, pilot_n),
    nrow(model_ready)
  )
)

join_quality_path <- file.path(outputs_dir, "traffic_2024_4months_join_quality_summary.csv")
fwrite(join_quality_summary, file = join_quality_path)

missing_reasons_overall <- joined[
  ,
  .(row_count = .N),
  by = .(traffic_join_status, traffic_missing_reason)
][, `:=`(
  scope = "overall_dataset",
  row_pct = safe_pct(row_count, overall_n)
)]

missing_reasons_within_pilot <- joined[
  traffic_within_pilot_period_flag == TRUE,
  .(row_count = .N),
  by = .(traffic_join_status, traffic_missing_reason)
][, `:=`(
  scope = "within_pilot_period",
  row_pct = safe_pct(row_count, pilot_n)
)]

missing_reasons_outside_pilot <- joined[
  traffic_parse_success_flag == TRUE & traffic_within_pilot_period_flag == FALSE,
  .(row_count = .N),
  by = .(traffic_join_status, traffic_missing_reason)
][, `:=`(
  scope = "outside_pilot_period",
  row_pct = safe_pct(row_count, outside_pilot_n)
)]

missing_reasons_summary <- rbindlist(
  list(missing_reasons_overall, missing_reasons_within_pilot, missing_reasons_outside_pilot),
  use.names = TRUE,
  fill = TRUE
)[, .(scope, traffic_join_status, traffic_missing_reason, row_count, row_pct)]

missing_reasons_path <- file.path(outputs_dir, "traffic_2024_4months_join_missing_reasons.csv")
fwrite(missing_reasons_summary, file = missing_reasons_path)

pilot_period_coverage_summary <- rbindlist(list(
  joined[
    traffic_within_pilot_period_flag == TRUE,
    .(
      row_count = .N,
      matched_rows = sum(traffic_join_status == "matched"),
      matched_pct = safe_pct(sum(traffic_join_status == "matched"), .N)
    ),
    by = .(analysis_year, month)
  ],
  joined[
    traffic_within_pilot_period_flag == TRUE,
    .(
      row_count = .N,
      matched_rows = sum(traffic_join_status == "matched"),
      matched_pct = safe_pct(sum(traffic_join_status == "matched"), .N)
    ),
    by = .(analysis_year, month, temporal_bin_4h)
  ]
), use.names = TRUE, fill = TRUE)

pilot_period_coverage_path <- file.path(outputs_dir, "traffic_2024_4months_pilot_period_coverage_summary.csv")
fwrite(pilot_period_coverage_summary, file = pilot_period_coverage_path)

top_missing_within_pilot <- joined[
  traffic_within_pilot_period_flag == TRUE & traffic_missing_reason != "matched",
  .N,
  by = .(traffic_missing_reason)
][order(-N, traffic_missing_reason)]

integration_note_lines <- c(
  "# Traffic 2024 4-Month Pilot Integration Note",
  "",
  "## Scope",
  "- This is a pilot partial integration from traffic to accidents.",
  "- It keeps the raw row structure of `accidentes_con_trafico_final.csv` and does not deduplicate accidents.",
  "- It does not use `edge_id`, does not enter modeling, and is not a routing-ready layer.",
  "",
  "## Join design",
  "- LEFT JOIN from accidents to traffic aggregated table.",
  "- Join key: `id_sensor_cercano -> sensor_id`, `analysis_year`, `month`, `temporal_bin_4h`, `is_weekend`.",
  "- Traffic aggregate uniqueness on that key was validated before join.",
  "",
  "## Coverage interpretation",
  sprintf("- Global matched rows: %s (%s%% of all accident rows).", matched_n, safe_pct(matched_n, overall_n)),
  sprintf("- Rows inside pilot period: %s (%s%% of all accident rows).", pilot_n, safe_pct(pilot_n, overall_n)),
  sprintf("- Matched rows within pilot period: %s (%s%% of pilot-period rows).", matched_pilot_n, safe_pct(matched_pilot_n, pilot_n)),
  sprintf("- Rows outside pilot period: %s (%s%% of all accident rows).", outside_pilot_n, safe_pct(outside_pilot_n, overall_n)),
  "- Non-match outside the pilot period is expected coverage absence, not a join failure.",
  "",
  "## Main non-match reasons inside pilot period",
  if (nrow(top_missing_within_pilot) == 0L) {
    "- None; all pilot-period rows matched."
  } else {
    sprintf(
      "- %s",
      paste(
        sprintf("%s: %s rows", top_missing_within_pilot$traffic_missing_reason, top_missing_within_pilot$N),
        collapse = "; "
      )
    )
  },
  "",
  "## Interpretation",
  "- This output is suitable as a pilot partial integration layer for future traffic-aware phases.",
  "- It must not be interpreted as full historical traffic coverage for 2016-2024."
)

integration_note_path <- file.path(outputs_dir, "traffic_2024_4months_integration_note.md")
writeLines(integration_note_lines, integration_note_path, useBytes = TRUE)

cat("Created joined accidents table:", joined_path, "\n")
cat("Created model-ready pilot subset:", model_ready_path, "\n")
cat("Created join quality summary:", join_quality_path, "\n")
cat("Created missing reasons summary:", missing_reasons_path, "\n")
cat("Created pilot period coverage summary:", pilot_period_coverage_path, "\n")
cat("Created integration note:", integration_note_path, "\n")
