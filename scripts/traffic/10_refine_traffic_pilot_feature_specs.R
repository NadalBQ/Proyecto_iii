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
  if (is.na(den) || den == 0) NA_real_ else round(num / den * 100, 4)
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

metric_rows <- function(dt, pred_col, model_spec) {
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
      model_spec = model_spec,
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
      calibration_mean_abs_gap_decile = calibration_gap_decile(y, mu)
    )
  }), use.names = TRUE, fill = TRUE)
}

quant_stat <- function(x, p) {
  if (all(is.na(x))) return(NA_real_)
  as.numeric(quantile(x, probs = p, na.rm = TRUE, type = 8))
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
  stop("Pilot training table is not restricted to 2024.", call. = FALSE)
}
if (!identical(sort(unique(dt$month)), c(1L, 4L, 7L, 10L))) {
  stop("Pilot training table is not restricted to months 1,4,7,10.", call. = FALSE)
}

dt[, split := add_split(month)]
if (anyNA(dt$split)) {
  stop("Split assignment failed for some pilot rows.", call. = FALSE)
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
covered_train <- train_dt[traffic_coverage_flag == "covered"]

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

median_intensidad <- covered_train[!is.na(traffic_intensidad_mean), median(traffic_intensidad_mean)]
median_ocupacion <- covered_train[!is.na(traffic_ocupacion_mean), median(traffic_ocupacion_mean)]
median_vmed <- covered_train[!is.na(traffic_vmed_mean), median(traffic_vmed_mean)]
median_n_obs <- covered_train[!is.na(traffic_n_observations), median(traffic_n_observations)]
median_support_n <- covered_train[!is.na(traffic_support_n), median(traffic_support_n)]

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

int_q01 <- quant_stat(covered_train$traffic_intensidad_mean, 0.01)
int_q99 <- quant_stat(covered_train$traffic_intensidad_mean, 0.99)
occ_q01 <- quant_stat(covered_train$traffic_ocupacion_mean, 0.01)
occ_q99 <- quant_stat(covered_train$traffic_ocupacion_mean, 0.99)
vmed_q01 <- quant_stat(covered_train$traffic_vmed_mean, 0.01)
vmed_q99 <- quant_stat(covered_train$traffic_vmed_mean, 0.99)

dt[, traffic_intensidad_wins := pmin(pmax(traffic_intensidad_imputed, int_q01), int_q99)]
dt[, traffic_ocupacion_wins := pmin(pmax(traffic_ocupacion_imputed, occ_q01), occ_q99)]
dt[, traffic_vmed_wins := pmin(pmax(traffic_vmed_imputed, vmed_q01), vmed_q99)]
dt[, traffic_intensidad_wins_log := log1p(pmax(traffic_intensidad_wins, 0))]
dt[, traffic_vmed_wins_log := log1p(pmax(traffic_vmed_wins, 0))]

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

spec_registry <- data.table(
  model_spec = c("no_traffic", "traffic_A_core", "traffic_B_core_support", "traffic_C_core_support_vmed", "traffic_D_transformed"),
  traffic_block_description = c(
    "Base only, no traffic block.",
    "Covered flag + intensidad + ocupacion.",
    "Core traffic + support/quality block.",
    "Core traffic + support/quality + vmed.",
    "Covered flag + no-time flag + robust transformed traffic core + support/quality."
  ),
  includes_traffic = c(FALSE, TRUE, TRUE, TRUE, TRUE),
  includes_support_quality = c(FALSE, FALSE, TRUE, TRUE, TRUE),
  includes_vmed = c(FALSE, FALSE, FALSE, TRUE, FALSE),
  uses_transformed_traffic = c(FALSE, FALSE, FALSE, FALSE, TRUE)
)

traffic_term_map <- list(
  no_traffic = character(),
  traffic_A_core = c(
    "traffic_covered_flag",
    "traffic_intensidad_imputed",
    "traffic_ocupacion_imputed"
  ),
  traffic_B_core_support = c(
    "traffic_covered_flag",
    "traffic_missing_due_to_no_time_flag",
    "traffic_intensidad_imputed",
    "traffic_ocupacion_imputed",
    "log1p_traffic_n_observations",
    "log1p_traffic_support_n"
  ),
  traffic_C_core_support_vmed = c(
    "traffic_covered_flag",
    "traffic_missing_due_to_no_time_flag",
    "traffic_intensidad_imputed",
    "traffic_ocupacion_imputed",
    "log1p_traffic_n_observations",
    "log1p_traffic_support_n",
    "traffic_vmed_imputed"
  ),
  traffic_D_transformed = c(
    "traffic_covered_flag",
    "traffic_missing_due_to_no_time_flag",
    "traffic_intensidad_wins_log",
    "traffic_ocupacion_wins",
    "log1p_traffic_n_observations",
    "log1p_traffic_support_n"
  )
)

fit_spec <- function(model_spec, all_dt, base_terms, traffic_term_map) {
  traffic_terms <- traffic_term_map[[model_spec]]
  all_terms <- c(base_terms, traffic_terms)
  form <- as.formula(paste("target ~", paste(all_terms, collapse = " + ")))
  fit <- glm(form, data = all_dt[split == "train"], family = poisson())

  alias_complete <- alias(fit)$Complete
  aliased_terms <- character()
  if (!is.null(alias_complete)) {
    aliased_terms <- rownames(alias_complete)
    stop(
      sprintf(
        "Rank-deficient fit detected for %s. Aliased terms: %s",
        model_spec,
        paste(aliased_terms, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  pred <- copy(all_dt[, .(
    edge_id, analysis_year, month, temporal_bin_4h, is_weekend,
    split, pilot_accident_count, pilot_row_type, traffic_coverage_flag, traffic_missing_reason
  )])
  pred[, model_spec := model_spec]
  pred[, pred_poisson := predict(fit, newdata = all_dt, type = "response")]

  if (anyNA(pred$pred_poisson)) {
    stop(sprintf("NA predictions detected for %s.", model_spec), call. = FALSE)
  }

  metrics <- rbindlist(lapply(c("train", "validation", "test"), function(split_name) {
    metric_rows(pred[split == split_name], "pred_poisson", model_spec)
  }), use.names = TRUE, fill = TRUE)

  coef_mat <- summary(fit)$coefficients
  coef_dt <- as.data.table(coef_mat, keep.rownames = "term")
  setnames(coef_dt, c("Estimate", "Std. Error", "z value", "Pr(>|z|)"), c("estimate", "std_error", "z_value", "p_value"))
  coef_dt[, abs_z_value := abs(z_value)]
  coef_dt[, model_spec := model_spec]
  coef_dt[, term_group := fifelse(
    term %in% traffic_terms,
    "traffic",
    "base"
  )]
  coef_dt[, effect_direction := fifelse(estimate > 0, "positive", fifelse(estimate < 0, "negative", "neutral"))]
  coef_dt[, exp_estimate := exp(estimate)]

  list(
    fit = fit,
    predictions = pred,
    metrics = metrics,
    coefficients = coef_dt,
    aliased_terms = aliased_terms
  )
}

fit_results <- lapply(spec_registry$model_spec, function(spec_name) {
  fit_spec(spec_name, dt, base_feature_terms, traffic_term_map)
})
names(fit_results) <- spec_registry$model_spec

refined_no_traffic_metrics <- fit_results[["no_traffic"]]$metrics
refined_with_traffic_metrics <- rbindlist(
  lapply(setdiff(spec_registry$model_spec, "no_traffic"), function(spec_name) fit_results[[spec_name]]$metrics),
  use.names = TRUE,
  fill = TRUE
)
refined_predictions <- rbindlist(
  lapply(spec_registry$model_spec, function(spec_name) fit_results[[spec_name]]$predictions),
  use.names = TRUE,
  fill = TRUE
)

baseline_metrics <- refined_no_traffic_metrics[, .(
  split, scope, n_rows, target_mean, target_variance, zero_pct,
  mean_poisson_deviance_base = mean_poisson_deviance,
  mae_base = mae,
  rmse_base = rmse,
  pearson_dispersion_base = pearson_dispersion,
  calibration_gap_base = calibration_mean_abs_gap_decile
)]

traffic_spec_comparison <- merge(
  refined_with_traffic_metrics,
  baseline_metrics,
  by = c("split", "scope", "n_rows", "target_mean", "target_variance", "zero_pct"),
  all.x = TRUE,
  sort = FALSE
)
traffic_spec_comparison[, delta_mean_poisson_deviance := mean_poisson_deviance - mean_poisson_deviance_base]
traffic_spec_comparison[, delta_mae := mae - mae_base]
traffic_spec_comparison[, delta_rmse := rmse - rmse_base]
traffic_spec_comparison[, delta_pearson_dispersion := pearson_dispersion - pearson_dispersion_base]
traffic_spec_comparison[, delta_calibration_gap := calibration_mean_abs_gap_decile - calibration_gap_base]
traffic_spec_comparison <- merge(traffic_spec_comparison, spec_registry, by = "model_spec", all.x = TRUE, sort = FALSE)

traffic_vars <- c("traffic_intensidad_mean", "traffic_ocupacion_mean", "traffic_vmed_mean", "traffic_n_observations", "traffic_support_n")
traffic_var_audit <- rbindlist(lapply(traffic_vars, function(var_name) {
  data.table(
    section = "traffic_variable_audit",
    variable = var_name,
    overall_missing_pct = safe_pct(sum(is.na(dt[[var_name]])), nrow(dt)),
    covered_missing_pct = safe_pct(sum(is.na(dt[traffic_coverage_flag == "covered"][[var_name]])), dt[traffic_coverage_flag == "covered", .N]),
    covered_median = safe_mean(covered_train[[var_name]][!is.na(covered_train[[var_name]])]),
    covered_p95 = quant_stat(covered_train[[var_name]], 0.95),
    covered_p99 = quant_stat(covered_train[[var_name]], 0.99),
    train_transform = fifelse(
      var_name == "traffic_intensidad_mean", "median_impute + winsorize_1_99 + log1p in spec D",
      fifelse(
        var_name == "traffic_ocupacion_mean", "median_impute + winsorize_1_99 in spec D",
        fifelse(
          var_name == "traffic_vmed_mean", "median_impute; winsorized log available but only raw imputed tested in spec C",
          "median_impute + log1p"
        )
      )
    )
  )
}), use.names = TRUE, fill = TRUE)

coef_summary <- rbindlist(
  lapply(setdiff(spec_registry$model_spec, "no_traffic"), function(spec_name) {
    fit_results[[spec_name]]$coefficients[term_group == "traffic"][
      ,
      .(
        section = "traffic_term_coefficient",
        model_spec,
        variable = term,
        estimate,
        std_error,
        z_value,
        abs_z_value,
        p_value,
        exp_estimate,
        effect_direction
      )
    ]
  }),
  use.names = TRUE,
  fill = TRUE
)

incremental_gain_summary <- traffic_spec_comparison[
  scope %in% c("overall", "positive_only", "zero_only"),
  .(
    section = "traffic_spec_incremental_gain",
    model_spec,
    split,
    scope,
    mean_poisson_deviance,
    mean_poisson_deviance_base,
    delta_mean_poisson_deviance,
    mae,
    mae_base,
    delta_mae,
    rmse,
    rmse_base,
    delta_rmse,
    calibration_mean_abs_gap_decile,
    calibration_gap_base,
    delta_calibration_gap
  )
]

traffic_effect_summary <- rbindlist(
  list(traffic_var_audit, incremental_gain_summary, coef_summary),
  use.names = TRUE,
  fill = TRUE
)

validation_overall <- traffic_spec_comparison[split == "validation" & scope == "overall"]
test_overall <- traffic_spec_comparison[split == "test" & scope == "overall"]
best_validation_spec <- validation_overall[order(delta_mean_poisson_deviance, delta_rmse)][1, model_spec]
best_test_spec <- test_overall[order(delta_mean_poisson_deviance, delta_rmse)][1, model_spec]

best_validation_positive <- traffic_spec_comparison[split == "validation" & scope == "positive_only"][order(delta_mean_poisson_deviance)][1, model_spec]
best_test_positive <- traffic_spec_comparison[split == "test" & scope == "positive_only"][order(delta_mean_poisson_deviance)][1, model_spec]

vmed_validation_delta <- traffic_spec_comparison[model_spec == "traffic_C_core_support_vmed" & split == "validation" & scope == "overall", delta_mean_poisson_deviance]
support_validation_delta <- traffic_spec_comparison[model_spec == "traffic_B_core_support" & split == "validation" & scope == "overall", delta_mean_poisson_deviance]
core_validation_delta <- traffic_spec_comparison[model_spec == "traffic_A_core" & split == "validation" & scope == "overall", delta_mean_poisson_deviance]
transformed_validation_delta <- traffic_spec_comparison[model_spec == "traffic_D_transformed" & split == "validation" & scope == "overall", delta_mean_poisson_deviance]

vmed_test_delta <- traffic_spec_comparison[model_spec == "traffic_C_core_support_vmed" & split == "test" & scope == "overall", delta_mean_poisson_deviance]
support_test_delta <- traffic_spec_comparison[model_spec == "traffic_B_core_support" & split == "test" & scope == "overall", delta_mean_poisson_deviance]
core_test_delta <- traffic_spec_comparison[model_spec == "traffic_A_core" & split == "test" & scope == "overall", delta_mean_poisson_deviance]
transformed_test_delta <- traffic_spec_comparison[model_spec == "traffic_D_transformed" & split == "test" & scope == "overall", delta_mean_poisson_deviance]

no_traffic_metrics_path <- file.path(outputs_dir, "traffic_pilot_refined_no_traffic_metrics.csv")
with_traffic_metrics_path <- file.path(outputs_dir, "traffic_pilot_refined_with_traffic_metrics.csv")
comparison_path <- file.path(outputs_dir, "traffic_pilot_traffic_feature_spec_comparison.csv")
effect_summary_path <- file.path(outputs_dir, "traffic_pilot_traffic_feature_effect_summary.csv")
predictions_path <- file.path(outputs_dir, "traffic_pilot_refined_predictions.csv")
note_path <- file.path(outputs_dir, "traffic_pilot_refined_model_note.md")

fwrite(refined_no_traffic_metrics, no_traffic_metrics_path)
fwrite(refined_with_traffic_metrics, with_traffic_metrics_path)
fwrite(traffic_spec_comparison, comparison_path)
fwrite(traffic_effect_summary, effect_summary_path)
fwrite(refined_predictions, predictions_path)

note_lines <- c(
  "# Traffic Pilot Refined Model Note",
  "",
  "## Scope",
  "- Pilot-only refinement restricted to analysis year 2024 and months 1, 4, 7 and 10.",
  "- Unit: `edge_id + analysis_year + month + temporal_bin_4h + is_weekend`.",
  "- Target: `pilot_accident_count`.",
  "- Split kept from the previous pilot phase: train months 1 and 4, validation month 7, test month 10.",
  "",
  "## Traffic audit",
  sprintf("- `traffic_intensidad_mean` missing overall: %.4f%%; covered missing: %.4f%%.", traffic_var_audit[variable == "traffic_intensidad_mean", overall_missing_pct], traffic_var_audit[variable == "traffic_intensidad_mean", covered_missing_pct]),
  sprintf("- `traffic_ocupacion_mean` missing overall: %.4f%%; covered missing: %.4f%%.", traffic_var_audit[variable == "traffic_ocupacion_mean", overall_missing_pct], traffic_var_audit[variable == "traffic_ocupacion_mean", covered_missing_pct]),
  sprintf("- `traffic_vmed_mean` missing overall: %.4f%%; covered missing: %.4f%%.", traffic_var_audit[variable == "traffic_vmed_mean", overall_missing_pct], traffic_var_audit[variable == "traffic_vmed_mean", covered_missing_pct]),
  sprintf("- Covered-row medians: intensidad %.4f, ocupacion %.4f, vmed %.4f, n_observations %.4f, support_n %.4f.",
          traffic_var_audit[variable == "traffic_intensidad_mean", covered_median],
          traffic_var_audit[variable == "traffic_ocupacion_mean", covered_median],
          traffic_var_audit[variable == "traffic_vmed_mean", covered_median],
          traffic_var_audit[variable == "traffic_n_observations", covered_median],
          traffic_var_audit[variable == "traffic_support_n", covered_median]),
  "",
  "## Compared traffic specifications",
  "- `traffic_A_core`: covered flag + intensidad + ocupacion.",
  "- `traffic_B_core_support`: A + no-time flag + `n_observations` + `support_n`.",
  "- `traffic_C_core_support_vmed`: B + `vmed`.",
  "- `traffic_D_transformed`: covered flag + no-time flag + winsorized/log intensity + winsorized occupancy + support/quality.",
  "",
  "## Missing and transformation rules",
  "- Traffic numeric columns were median-imputed using train covered rows.",
  "- `traffic_covered_flag` and `traffic_missing_due_to_no_time_flag` were kept explicit.",
  "- Robust transformed spec uses train 1st/99th percentile winsorization for intensidad/ocupacion before transformation.",
  "",
  "## Recommendation signals",
  sprintf("- Best validation spec by overall deviance delta: %s.", best_validation_spec),
  sprintf("- Best test spec by overall deviance delta: %s.", best_test_spec),
  sprintf("- Best validation spec on positives: %s.", best_validation_positive),
  sprintf("- Best test spec on positives: %s.", best_test_positive),
  sprintf("- Validation overall deltas vs no traffic: A %.6f, B %.6f, C %.6f, D %.6f.",
          core_validation_delta, support_validation_delta, vmed_validation_delta, transformed_validation_delta),
  sprintf("- Test overall deltas vs no traffic: A %.6f, B %.6f, C %.6f, D %.6f.",
          core_test_delta, support_test_delta, vmed_test_delta, transformed_test_delta),
  "",
  "## Interpretation boundary",
  "- This note is pilot-only and must not be interpreted as validation of the full 2016-2024 system.",
  "- It supports a next pilot step for traffic integration inside modeling, not routing or final edge weighting."
)
writeLines(note_lines, note_path, useBytes = TRUE)

cat("Created refined no-traffic metrics:", no_traffic_metrics_path, "\n")
cat("Created refined with-traffic metrics:", with_traffic_metrics_path, "\n")
cat("Created traffic spec comparison:", comparison_path, "\n")
cat("Created traffic effect summary:", effect_summary_path, "\n")
cat("Created refined predictions:", predictions_path, "\n")
cat("Created refined note:", note_path, "\n")
