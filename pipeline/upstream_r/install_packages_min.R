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

install_missing_packages <- function(packages = required_packages, repos = "https://cloud.r-project.org") {
  missing_packages <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]

  if (!length(missing_packages)) {
    message("All required R packages are already installed.")
    return(invisible(packages))
  }

  message(
    sprintf(
      "Installing missing R packages: %s",
      paste(missing_packages, collapse = ", ")
    )
  )
  install.packages(missing_packages, repos = repos)

  still_missing <- missing_packages[!vapply(missing_packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(still_missing)) {
    stop(
      sprintf(
        "Failed to install all required R packages. Still missing: %s",
        paste(still_missing, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  invisible(packages)
}

if (sys.nframe() == 0L) {
  install_missing_packages()
}
