parse_install_args <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  repos_arg <- grep("^--repos=", args, value = TRUE)
  repos <- if (length(repos_arg) == 1L) sub("^--repos=", "", repos_arg[[1]]) else "https://cloud.r-project.org"
  list(repos = repos)
}

main <- function() {
  args <- parse_install_args()
  required_packages <- c(
    "readr",
    "dplyr",
    "tibble",
    "janitor",
    "lubridate",
    "sf",
    "digest",
    "jsonlite"
  )

  installed <- rownames(installed.packages())
  missing <- setdiff(required_packages, installed)

  message("[INFO] ROAD-SAFETY minimal R package setup")
  message(sprintf("[INFO] CRAN mirror: %s", args$repos))
  message(sprintf("[INFO] Required packages: %s", paste(required_packages, collapse = ", ")))

  if (!length(missing)) {
    message("[INFO] All required packages are already installed.")
    return(invisible(required_packages))
  }

  message(sprintf("[INFO] Installing missing packages: %s", paste(missing, collapse = ", ")))
  install.packages(missing, repos = args$repos)

  still_missing <- missing[!vapply(missing, requireNamespace, logical(1), quietly = TRUE)]
  if (length(still_missing)) {
    stop(
      sprintf("Some required packages are still unavailable after installation: %s", paste(still_missing, collapse = ", ")),
      call. = FALSE
    )
  }

  message("[INFO] Minimal R package setup completed.")
  invisible(required_packages)
}

main()
