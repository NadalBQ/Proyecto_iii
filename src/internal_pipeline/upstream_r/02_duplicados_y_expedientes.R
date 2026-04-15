rs_build_exact_duplicate_summary <- function(raw_data, deduplicated_data) {
  exact_duplicate_count <- nrow(raw_data) - nrow(deduplicated_data)

  tibble::tibble(
    metric = c(
      "nrow_raw",
      "exact_duplicate_rows",
      "exact_duplicate_rate",
      "nrow_after_exact_dedup"
    ),
    value = c(
      nrow(raw_data),
      exact_duplicate_count,
      exact_duplicate_count / nrow(raw_data),
      nrow(deduplicated_data)
    )
  )
}

rs_build_expediente_counts <- function(raw_data, deduplicated_data) {
  raw_counts <- raw_data |>
    dplyr::count(num_expediente, name = "rows_raw")

  dedup_counts <- deduplicated_data |>
    dplyr::count(num_expediente, name = "rows_after_exact_dedup")

  raw_counts |>
    dplyr::full_join(dedup_counts, by = "num_expediente") |>
    dplyr::mutate(
      rows_raw = dplyr::coalesce(rows_raw, 0L),
      rows_after_exact_dedup = dplyr::coalesce(rows_after_exact_dedup, 0L),
      exact_duplicate_rows_within_expediente = rows_raw - rows_after_exact_dedup,
      has_exact_duplicates = exact_duplicate_rows_within_expediente > 0L,
      has_multiplicity_after_exact_dedup = rows_after_exact_dedup > 1L
    ) |>
    dplyr::arrange(dplyr::desc(rows_after_exact_dedup), num_expediente)
}

rs_build_expediente_summary <- function(expediente_counts) {
  tibble::tibble(
    metric = c(
      "unique_expedientes",
      "expedientes_with_raw_multiplicity",
      "expedientes_with_exact_duplicates",
      "expedientes_with_multiplicity_after_exact_dedup",
      "median_rows_raw",
      "median_rows_after_exact_dedup",
      "max_rows_raw",
      "max_rows_after_exact_dedup"
    ),
    value = c(
      nrow(expediente_counts),
      sum(expediente_counts$rows_raw > 1L),
      sum(expediente_counts$has_exact_duplicates),
      sum(expediente_counts$has_multiplicity_after_exact_dedup),
      stats::median(expediente_counts$rows_raw),
      stats::median(expediente_counts$rows_after_exact_dedup),
      max(expediente_counts$rows_raw),
      max(expediente_counts$rows_after_exact_dedup)
    )
  )
}

rs_build_expediente_distribution <- function(expediente_counts, count_column, output_name) {
  expediente_counts |>
    dplyr::select(rows_per_expediente = dplyr::all_of(count_column)) |>
    dplyr::count(rows_per_expediente, name = "expediente_count") |>
    dplyr::arrange(rows_per_expediente) |>
    dplyr::mutate(source = output_name)
}

rs_run_m2_duplicados_y_expedientes <- function(data, paths) {
  deduplicated_data <- dplyr::distinct(data)
  exact_duplicate_count <- nrow(data) - nrow(deduplicated_data)

  exact_duplicate_summary <- rs_build_exact_duplicate_summary(data, deduplicated_data)
  expediente_counts <- rs_build_expediente_counts(data, deduplicated_data)
  expediente_summary <- rs_build_expediente_summary(expediente_counts)
  expediente_distribution_raw <- rs_build_expediente_distribution(
    expediente_counts,
    count_column = "rows_raw",
    output_name = "raw"
  )
  expediente_distribution_after_exact_dedup <- rs_build_expediente_distribution(
    expediente_counts,
    count_column = "rows_after_exact_dedup",
    output_name = "after_exact_dedup"
  )

  readr::write_csv(
    deduplicated_data,
    file.path(paths$output_data, "accidentes_con_trafico_final_exact_dedup.csv")
  )
  readr::write_csv(
    exact_duplicate_summary,
    file.path(paths$output_tables, "m2_exact_duplicate_summary.csv")
  )
  readr::write_csv(
    expediente_counts,
    file.path(paths$output_tables, "m2_expediente_counts.csv")
  )
  readr::write_csv(
    expediente_summary,
    file.path(paths$output_tables, "m2_expediente_summary.csv")
  )
  readr::write_csv(
    expediente_distribution_raw,
    file.path(paths$output_tables, "m2_expediente_distribution_raw.csv")
  )
  readr::write_csv(
    expediente_distribution_after_exact_dedup,
    file.path(paths$output_tables, "m2_expediente_distribution_after_exact_dedup.csv")
  )

  list(
    deduplicated_data = deduplicated_data,
    exact_duplicate_count = exact_duplicate_count,
    unique_expedientes = nrow(expediente_counts),
    expediente_counts = expediente_counts,
    expediente_distribution_raw = expediente_distribution_raw,
    expediente_distribution_after_exact_dedup = expediente_distribution_after_exact_dedup
  )
}
