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

detect_separator <- function(path) {
  header <- readLines(path, n = 1L, warn = FALSE, encoding = "UTF-8")
  semi_n <- lengths(regmatches(header, gregexpr(";", header, fixed = TRUE)))
  comma_n <- lengths(regmatches(header, gregexpr(",", header, fixed = TRUE)))
  if (semi_n >= comma_n) ";" else ","
}

read_sample <- function(path, sep, nrows = 1000L, encoding = "UTF-8") {
  if (requireNamespace("data.table", quietly = TRUE)) {
    data.table::fread(
      input = path,
      sep = sep,
      nrows = nrows,
      encoding = encoding,
      showProgress = FALSE,
      na.strings = c("", "NA", "NULL")
    )
  } else {
    utils::read.csv(
      file = path,
      sep = sep,
      nrows = nrows,
      fileEncoding = encoding,
      stringsAsFactors = FALSE,
      na.strings = c("", "NA", "NULL")
    )
  }
}

inspect_file <- function(label, path, encoding = "UTF-8") {
  sep <- detect_separator(path)
  sample_dt <- read_sample(path, sep = sep, encoding = encoding)
  names(sample_dt) <- normalize_names(names(sample_dt))

  cat("\n==", label, "==\n")
  cat("path:", path, "\n")
  cat("separator:", sep, "\n")
  cat("encoding:", encoding, "\n")
  cat("sample_rows:", nrow(sample_dt), "\n")
  cat("columns:", paste(names(sample_dt), collapse = ", "), "\n")

  missing_pct <- vapply(sample_dt, function(col) {
    round(mean(is.na(col)) * 100, 2)
  }, numeric(1))

  type_info <- vapply(sample_dt, function(col) class(col)[1], character(1))
  info_df <- data.frame(
    column = names(sample_dt),
    sample_type = unname(type_info),
    sample_missing_pct = unname(missing_pct),
    stringsAsFactors = FALSE
  )
  print(utils::head(info_df, 15))
}

root <- find_repo_root()

traffic_paths <- file.path(
  root,
  "data/raw/traffic_history_2024",
  c("01-2024.csv", "04-2024.csv", "07-2024.csv", "10-2024.csv")
)

sensor_path <- file.path(root, "data/raw/traffic_sensor_locations/sensor_locations.csv")
accident_path <- file.path(root, "data/raw/accidents/accidentes_con_trafico_final.csv")

required_paths <- c(traffic_paths, sensor_path, accident_path)
missing_paths <- required_paths[!file.exists(required_paths)]
if (length(missing_paths) > 0L) {
  stop(
    sprintf("Missing required files:\n%s", paste(missing_paths, collapse = "\n")),
    call. = FALSE
  )
}

for (path in traffic_paths) {
  inspect_file(basename(path), path, encoding = "UTF-8")
}

inspect_file("sensor_locations.csv", sensor_path, encoding = "UTF-8")
inspect_file("accidentes_con_trafico_final.csv", accident_path, encoding = "UTF-8")

traffic_headers <- lapply(traffic_paths, function(path) {
  header <- readLines(path, n = 1L, warn = FALSE, encoding = "UTF-8")
  normalize_names(strsplit(header, split = ";", fixed = TRUE)[[1]])
})
names(traffic_headers) <- basename(traffic_paths)

reference_header <- traffic_headers[[1]]
header_match <- vapply(traffic_headers, function(cols) identical(cols, reference_header), logical(1))

cat("\n== Traffic month schema consistency ==\n")
print(data.frame(
  file = names(header_match),
  normalized_schema_matches_reference = unname(header_match),
  stringsAsFactors = FALSE
))

cat("\nCandidate join keys:\n")
cat("- traffic_history: id\n")
cat("- sensor_locations: id\n")
cat("- accidents: id_sensor_cercano\n")
cat("- expected normalized key: sensor_id\n")
