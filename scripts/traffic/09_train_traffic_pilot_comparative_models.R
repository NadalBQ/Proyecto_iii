if (!requireNamespace("data.table", quietly = TRUE)) {
  stop("This script requires data.table.", call. = FALSE)
}
if (!requireNamespace("MASS", quietly = TRUE)) {
  stop("This script requires MASS.", call. = FALSE)
}

suppressPackageStartupMessages({
  library(data.table)
  library(MASS)
})

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

safe_mean <- function(x) {
  if (length(x) == 0L) return(NA_real_)
  mean(x, na.rm = TRUE)
}

safe_var <- function(x) {
  if (length(x) <= 1L) return(NA_real_)
  var(x, na.rm = TRUE)
}

parse_bool_flag <- function(x) {
  x_chr <- trimws(tolower(as.character(x)))
  fifelse(
    x_chr %in% c("t", "true", "1", "y", "yes"),
    1L,
    fifelse(x_chr %in% c("f", "false", "0", "n", "no", ""), 0L, 0L)
  )
}

parse_maxspeed <- function(x) {
  x_chr <- as.character(x)
  num_chr <- sub("^.*?([0-9]+(?:\\.[0-9]+)?).*$", "\\1", x_chr)
  num <- suppressWarnings(as.numeric(num_chr))
  num[grepl("^[^0-9]*$", x_chr)] <- NA_real_
  num[num <= 0] <- NA_real_
  num
}

road_class_group <- function(x) {
  x_chr <- trimws(tolower(as.character(x)))
  out <- fifelse(
    x_chr %in% c("motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link"),
    "major",
    fifelse(
      x_chr %in% c("secondary", "secondary_link", "tertiary", "tertiary_link", "unclassified"),
      "collector",
      fifelse(
        x_chr %in% c("residential", "living_street", "service"),
        "local",
        fifelse(is.na(x_chr) | x_chr == "", "missing", "other")
      )
    )
  )
  factor(out, levels = c("major", "collector", "local", "other", "missing"))
}

add_split <- function(month_vec) {
  split <- rep(NA_character_, length(month_vec))
  split[month_vec %in% c(1L, 4L)] <- "train"
  split[month_vec == 7L] <- "validation"
  split[month_vec == 10L] <- "test"
  split
}

poisson_deviance_mean <- function(y, mu) {
  if (length(y) == 0L) return(NA_real_)
  mu <- pmax(mu, 1e-12)
  contrib <- ifelse(
    y == 0,
    2 * mu,
    2 * (y * log(y / mu) - (y - mu))
  )
  mean(contrib)
}

pearson_dispersion <- function(y, mu, df_residual = NA_real_) {
  if (length(y) == 0L) return(NA_real_)
  mu <- pmax(mu, 1e-12)
  resid_pearson <- (y - mu) / sqrt(mu)
  numerator <- sum(resid_pearson^2)
  denominator <- if (!is.na(df_residual) && is.finite(df_residual) && df_residual > 0) df_residual else length(y)
  numerator / denominator
}

calibration_gap_decile <- function(y, mu) {
  if (length(y) == 0L) return(NA_real_)
  mu <- pmax(mu, 1e-12)
  probs <- seq(0, 1, by = 0.1)
  breaks <- unique(quantile(mu, probs = probs, na.rm = TRUE, type = 8))
  if (length(breaks) < 3L) {
    return(abs(mean(y) - mean(mu)))
  }
  bins <- cut(mu, breaks = breaks, include.lowest = TRUE, ordered_result = TRUE)
  cal <- data.table(actual = y, pred = mu, bin = bins)[
    ,
    .(actual_mean = mean(actual), pred_mean = mean(pred)),
    by = .(bin)
  ]
  mean(abs(cal$actual_mean - cal$pred_mean))
}

metric_rows <- function(dt, pred_col, family_name, feature_block_name, use_vmed_flag, nb_justified_flag) {
  scopes <- list(
    overall = dt,
    covered_only = dt[traffic_coverage_flag == "covered"],
    positive_only = dt[pilot_accident_count > 0L],
    zero_only = dt[pilot_accident_count == 0L]
  )

  rbindlist(lapply(names(scopes), function(scope_name) {
    scope_dt <- scopes[[scope_name]]
    y <- scope_dt$pilot_accident_count
    mu <- scope_dt[[pred_col]]
    data.table(
      feature_block = feature_block_name,
      family = family_name,
      split = unique(scope_dt$split)[1],
      scope = scope_name,
      n_rows = nrow(scope_dt),
      target_mean = safe_mean(y),
      target_variance = safe_var(y),
      zero_pct = safe_pct(sum(y == 0L), length(y)),
      mean_poisson_deviance = poisson_deviance_mean(y, mu),
      mae = if (length(y) == 0L) NA_real_ else mean(abs(y - mu)),
      rmse = if (length(y) == 0L) NA_real_ else sqrt(mean((y - mu)^2)),
      pearson_dispersion = pearson_dispersion(y, mu),
      calibration_mean_abs_gap_decile = calibration_gap_decile(y, mu),
      use_traffic_vmed = use_vmed_flag,
      nb_justified = nb_justified_flag
    )
  }), use.names = TRUE, fill = TRUE)
}

root <- find_repo_root()
processed_dir <- file.path(root, "data", "processed")
outputs_dir <- file.path(root, "outputs")

training_path <- file.path(processed_dir, "traffic_2024_4months_pilot_training_table.csv")
if (!file.exists(training_path)) {
  stop("Missing traffic_2024_4months_pilot_training_table.csv", call. = FALSE)
}

dt <- fread(
  input = training_path,
  encoding = "UTF-8",
  showProgress = FALSE,
  na.strings = c("", "NA", "NULL")
)

key_cols <- c("edge_id", "analysis_year", "month", "temporal_bin_4h", "is_weekend")
dup_surplus <- dt[, .N, by = key_cols][N > 1L, sum(N - 1L)]
if (is.na(dup_surplus)) dup_surplus <- 0L
if (dup_surplus > 0L) {
  stop(sprintf("Pilot training table is not unique on the pilot key. Duplicate surplus rows: %s", dup_surplus), call. = FALSE)
}

if (!identical(sort(unique(dt$analysis_year)), 2024L)) {
  stop("Pilot training table is not restricted to analysis_year = 2024.", call. = FALSE)
}
if (!identical(sort(unique(dt$month)), c(1L, 4L, 7L, 10L))) {
  stop("Pilot training table is not restricted to months 1,4,7,10.", call. = FALSE)
}

dt[, split := add_split(month)]
if (anyNA(dt$split)) {
  stop("Failed to assign pilot split to all rows.", call. = FALSE)
}

dt[, target := as.integer(pilot_accident_count)]
dt[, is_weekend_int := as.integer(is_weekend)]
dt[, log_edge_length_m := log1p(pmax(edge_length_m, 0))]
dt[, road_class_group := road_class_group(road_class)]
dt[, oneway_flag := parse_bool_flag(oneway_raw)]
dt[, bridge_flag := parse_bool_flag(bridge_raw)]
dt[, tunnel_flag := parse_bool_flag(tunnel_raw)]
dt[, maxspeed_kph_raw := parse_maxspeed(maxspeed_raw)]
dt[, maxspeed_missing_flag := as.integer(is.na(maxspeed_kph_raw))]
dt[, month_sin := sin(2 * pi * month / 12)]

train_dt <- dt[split == "train"]
road_class_maxspeed <- train_dt[
  !is.na(maxspeed_kph_raw),
  .(road_class_median_maxspeed = median(maxspeed_kph_raw)),
  by = .(road_class_group)
]
global_maxspeed_median <- train_dt[!is.na(maxspeed_kph_raw), median(maxspeed_kph_raw)]
if (is.na(global_maxspeed_median)) global_maxspeed_median <- 50
dt <- merge(dt, road_class_maxspeed, by = "road_class_group", all.x = TRUE, sort = FALSE)
dt[, maxspeed_kph_imputed := fifelse(
  !is.na(maxspeed_kph_raw),
  maxspeed_kph_raw,
  fifelse(!is.na(road_class_median_maxspeed), road_class_median_maxspeed, global_maxspeed_median)
)]

dt[, traffic_covered_flag := as.integer(traffic_coverage_flag == "covered")]
dt[, traffic_missing_due_to_no_time_flag := as.integer(traffic_missing_reason == "pilot_sensor_support_but_no_traffic_for_time")]

median_intensidad <- train_dt[traffic_coverage_flag == "covered" & !is.na(traffic_intensidad_mean), median(traffic_intensidad_mean)]
median_ocupacion <- train_dt[traffic_coverage_flag == "covered" & !is.na(traffic_ocupacion_mean), median(traffic_ocupacion_mean)]
median_vmed <- train_dt[traffic_coverage_flag == "covered" & !is.na(traffic_vmed_mean), median(traffic_vmed_mean)]
median_n_obs <- train_dt[traffic_coverage_flag == "covered" & !is.na(traffic_n_observations), median(traffic_n_observations)]
median_support_n <- train_dt[traffic_coverage_flag == "covered" & !is.na(traffic_support_n), median(traffic_support_n)]

if (is.na(median_intensidad)) median_intensidad <- 0
if (is.na(median_ocupacion)) median_ocupacion <- 0
if (is.na(median_vmed)) median_vmed <- 0
if (is.na(median_n_obs)) median_n_obs <- 0
if (is.na(median_support_n)) median_support_n <- 0

dt[, traffic_intensidad_imputed := fifelse(is.na(traffic_intensidad_mean), median_intensidad, traffic_intensidad_mean)]
dt[, traffic_ocupacion_imputed := fifelse(is.na(traffic_ocupacion_mean), median_ocupacion, traffic_ocupacion_mean)]
dt[, traffic_vmed_imputed := fifelse(is.na(traffic_vmed_mean), median_vmed, traffic_vmed_mean)]
dt[, traffic_n_observations_imputed := fifelse(is.na(traffic_n_observations), median_n_obs, traffic_n_observations)]
dt[, traffic_support_n_imputed := fifelse(is.na(traffic_support_n), median_support_n, traffic_support_n)]
dt[, log1p_traffic_n_observations := log1p(pmax(traffic_n_observations_imputed, 0))]
dt[, log1p_traffic_support_n := log1p(pmax(traffic_support_n_imputed, 0))]

covered_vmed_missing_pct <- safe_pct(
  dt[traffic_coverage_flag == "covered", sum(is.na(traffic_vmed_mean))],
  dt[traffic_coverage_flag == "covered", .N]
)
use_traffic_vmed <- !is.na(covered_vmed_missing_pct) && covered_vmed_missing_pct <= 5

base_feature_terms <- c(
  "log_edge_length_m",
  "road_class_group",
  "oneway_flag",
  "maxspeed_kph_imputed",
  "maxspeed_missing_flag",
  "bridge_flag",
  "tunnel_flag",
  "hour_sin",
  "hour_cos",
  "month_sin",
  "is_weekend_int"
)

traffic_feature_terms <- c(
  "traffic_covered_flag",
  "traffic_missing_due_to_no_time_flag",
  "traffic_intensidad_imputed",
  "traffic_ocupacion_imputed",
  "log1p_traffic_n_observations",
  "log1p_traffic_support_n"
)
if (use_traffic_vmed) {
  traffic_feature_terms <- c(traffic_feature_terms, "traffic_vmed_imputed")
}

no_traffic_formula <- as.formula(
  paste("target ~", paste(base_feature_terms, collapse = " + "))
)
with_traffic_formula <- as.formula(
  paste("target ~", paste(c(base_feature_terms, traffic_feature_terms), collapse = " + "))
)

poisson_no_traffic <- glm(no_traffic_formula, data = dt[split == "train"], family = poisson())
poisson_with_traffic <- glm(with_traffic_formula, data = dt[split == "train"], family = poisson())

train_mean <- dt[split == "train", mean(target)]
train_var <- dt[split == "train", var(target)]
poisson_no_disp_train <- pearson_dispersion(
  dt[split == "train", target],
  predict(poisson_no_traffic, newdata = dt[split == "train"], type = "response"),
  poisson_no_traffic$df.residual
)
poisson_with_disp_train <- pearson_dispersion(
  dt[split == "train", target],
  predict(poisson_with_traffic, newdata = dt[split == "train"], type = "response"),
  poisson_with_traffic$df.residual
)
nb_justified <- isTRUE(train_var > train_mean * 1.2) ||
  isTRUE(poisson_no_disp_train > 1.2) ||
  isTRUE(poisson_with_disp_train > 1.2)

nb_no_traffic <- NULL
nb_with_traffic <- NULL
if (nb_justified) {
  nb_no_traffic <- glm.nb(no_traffic_formula, data = dt[split == "train"], link = log)
  nb_with_traffic <- glm.nb(with_traffic_formula, data = dt[split == "train"], link = log)
}

prediction_base_cols <- c(
  "edge_id", "analysis_year", "month", "temporal_bin_4h", "is_weekend",
  "split", "pilot_accident_count", "pilot_row_type", "traffic_coverage_flag", "traffic_missing_reason"
)

pred_no_traffic <- copy(dt[, ..prediction_base_cols])
pred_no_traffic[, pred_poisson := predict(poisson_no_traffic, newdata = dt, type = "response")]
if (nb_justified) {
  pred_no_traffic[, pred_negative_binomial := predict(nb_no_traffic, newdata = dt, type = "response")]
}

pred_with_traffic <- copy(dt[, ..prediction_base_cols])
pred_with_traffic[, pred_poisson := predict(poisson_with_traffic, newdata = dt, type = "response")]
if (nb_justified) {
  pred_with_traffic[, pred_negative_binomial := predict(nb_with_traffic, newdata = dt, type = "response")]
}

metrics_no_traffic <- rbindlist(lapply(split_levels <- c("train", "validation", "test"), function(split_name) {
  split_dt <- pred_no_traffic[split == split_name]
  split_dt[, target := pilot_accident_count]
  rows <- list(
    metric_rows(split_dt, "pred_poisson", "poisson", "no_traffic", use_traffic_vmed, nb_justified)
  )
  if (nb_justified) {
    rows[[length(rows) + 1L]] <- metric_rows(split_dt, "pred_negative_binomial", "negative_binomial", "no_traffic", use_traffic_vmed, nb_justified)
  }
  rbindlist(rows, use.names = TRUE, fill = TRUE)
}), use.names = TRUE, fill = TRUE)

metrics_with_traffic <- rbindlist(lapply(c("train", "validation", "test"), function(split_name) {
  split_dt <- pred_with_traffic[split == split_name]
  split_dt[, target := pilot_accident_count]
  rows <- list(
    metric_rows(split_dt, "pred_poisson", "poisson", "with_traffic", use_traffic_vmed, nb_justified)
  )
  if (nb_justified) {
    rows[[length(rows) + 1L]] <- metric_rows(split_dt, "pred_negative_binomial", "negative_binomial", "with_traffic", use_traffic_vmed, nb_justified)
  }
  rbindlist(rows, use.names = TRUE, fill = TRUE)
}), use.names = TRUE, fill = TRUE)

comparison_dt <- merge(
  metrics_no_traffic,
  metrics_with_traffic,
  by = c("family", "split", "scope", "n_rows", "target_mean", "target_variance", "zero_pct", "use_traffic_vmed", "nb_justified"),
  suffixes = c("_no_traffic", "_with_traffic"),
  allow.cartesian = FALSE
)

comparison_dt[, delta_mean_poisson_deviance := mean_poisson_deviance_with_traffic - mean_poisson_deviance_no_traffic]
comparison_dt[, delta_mae := mae_with_traffic - mae_no_traffic]
comparison_dt[, delta_rmse := rmse_with_traffic - rmse_no_traffic]
comparison_dt[, delta_pearson_dispersion := pearson_dispersion_with_traffic - pearson_dispersion_no_traffic]
comparison_dt[, delta_calibration_gap := calibration_mean_abs_gap_decile_with_traffic - calibration_mean_abs_gap_decile_no_traffic]

summary_distribution <- dt[
  ,
  .(
    n_rows = .N,
    positives = sum(target > 0L),
    zero_rows = sum(target == 0L),
    zero_pct = safe_pct(sum(target == 0L), .N),
    target_mean = mean(target),
    target_variance = var(target)
  ),
  by = .(split)
]

best_family_validation <- comparison_dt[split == "validation" & scope == "overall"][order(delta_mean_poisson_deviance)][1, family]
best_family_test <- comparison_dt[split == "test" & scope == "overall"][order(delta_mean_poisson_deviance)][1, family]

no_traffic_metrics_path <- file.path(outputs_dir, "traffic_pilot_baseline_no_traffic_metrics.csv")
with_traffic_metrics_path <- file.path(outputs_dir, "traffic_pilot_baseline_with_traffic_metrics.csv")
comparison_path <- file.path(outputs_dir, "traffic_pilot_model_comparison.csv")
pred_no_traffic_path <- file.path(outputs_dir, "traffic_pilot_predictions_no_traffic.csv")
pred_with_traffic_path <- file.path(outputs_dir, "traffic_pilot_predictions_with_traffic.csv")
note_path <- file.path(outputs_dir, "traffic_pilot_model_note.md")

fwrite(metrics_no_traffic, no_traffic_metrics_path)
fwrite(metrics_with_traffic, with_traffic_metrics_path)
fwrite(comparison_dt, comparison_path)
fwrite(pred_no_traffic, pred_no_traffic_path)
fwrite(pred_with_traffic, pred_with_traffic_path)

note_lines <- c(
  "# Traffic Pilot Model Comparison Note",
  "",
  "## Scope",
  "- Pilot-only comparison restricted to analysis year 2024 and months 1, 4, 7 and 10.",
  "- Unit: `edge_id + analysis_year + month + temporal_bin_4h + is_weekend`.",
  "- Target: `pilot_accident_count`.",
  "",
  "## Split",
  "- Train: months 1 and 4.",
  "- Validation: month 7.",
  "- Test: month 10.",
  "- This keeps the comparison temporal and avoids a random split.",
  "",
  "## Feature blocks",
  "- Baseline without traffic: static/base features only.",
  "- Baseline with traffic: same base block plus aggregated traffic features, simple train-median imputation and explicit traffic coverage flags.",
  sprintf("- `traffic_vmed_mean` used as predictor: %s.", ifelse(use_traffic_vmed, "yes", "no")),
  "",
  "## Dispersion decision",
  sprintf("- Train target mean: %.6f.", train_mean),
  sprintf("- Train target variance: %.6f.", train_var),
  sprintf("- Poisson train Pearson dispersion without traffic: %.6f.", poisson_no_disp_train),
  sprintf("- Poisson train Pearson dispersion with traffic: %.6f.", poisson_with_disp_train),
  sprintf("- Negative Binomial justified: %s.", ifelse(nb_justified, "yes", "no")),
  "",
  "## Interpretation boundary",
  "- This comparison is pilot-only and must not be interpreted as a result for the full 2016-2024 system.",
  "- Traffic missingness inside the pilot was kept explicit and documented; it is not interpreted as missing outside the pilot period.",
  "- These outputs are for next-step pilot model integration decisions, not for routing or final edge weighting.",
  "",
  "## Split distribution",
  paste0(
    apply(summary_distribution, 1, function(row) {
      sprintf(
        "- %s: n=%s, positives=%s, zero_pct=%.2f, mean=%.6f, var=%.6f.",
        row[["split"]], row[["n_rows"]], row[["positives"]], as.numeric(row[["zero_pct"]]),
        as.numeric(row[["target_mean"]]), as.numeric(row[["target_variance"]])
      )
    }),
    collapse = "\n"
  ),
  "",
  "## Best family by validation/test deviance delta",
  sprintf("- Validation best family: %s.", best_family_validation),
  sprintf("- Test best family: %s.", best_family_test)
)

writeLines(note_lines, note_path, useBytes = TRUE)

cat("Created no-traffic metrics:", no_traffic_metrics_path, "\n")
cat("Created with-traffic metrics:", with_traffic_metrics_path, "\n")
cat("Created model comparison:", comparison_path, "\n")
cat("Created no-traffic predictions:", pred_no_traffic_path, "\n")
cat("Created with-traffic predictions:", pred_with_traffic_path, "\n")
cat("Created note:", note_path, "\n")
