#' Database Configuration
#'
#' Centralized database path configuration.
#' Single source of truth for all database locations.
#'
#' @description
#' This module provides centralized configuration for database paths.
#' Instead of hardcoding paths in multiple files, use these functions
#' to get consistent database locations throughout the codebase.
#'
#' Database names can be customized via environment variables:
#' - EXPERIMENTS_DB: Main experiments database (default: "experiments.db")
#'
#' @examples
#' \dontrun{
#' # Get default path
#' db_path <- get_experiments_db_path()
#'
#' # Override via environment variable
#' Sys.setenv(EXPERIMENTS_DB = "my_custom.db")
#' db_path <- get_experiments_db_path()
#'
#' # Or from command line:
#' # EXPERIMENTS_DB=custom.db Rscript scripts/run_experiment.R config.yaml
#' }
#'
#' @keywords internal

#' Get Main Experiments Database Path
#'
#' Returns the path to the main experiments database.
#' Can be overridden via EXPERIMENTS_DB environment variable.
#'
#' @return Character string with full path to experiments database
#' @export
#'
#' @examples
#' \dontrun{
#' db_path <- get_experiments_db_path()
#' conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
#' }
get_experiments_db_path <- function() {
  db_name <- Sys.getenv("EXPERIMENTS_DB", "experiments.db")
  here::here(db_name)
}

#' Get Test Database Path
#'
#' Returns the path to the test database.
#' Can be overridden via TEST_DB environment variable.
#'
#' @return Character string with full path to test database
#' @export
#'
#' @examples
#' \dontrun{
#' db_path <- get_test_db_path()
#' conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
#' }
get_test_db_path <- function() {
  db_name <- Sys.getenv("TEST_DB", "test_experiments.db")
  here::here("tests", "fixtures", db_name)
}

#' Get All Database Paths
#'
#' Returns a named list of all database paths.
#' Useful for scripts that need to know about all databases.
#'
#' @return Named list with database paths:
#'   \describe{
#'     \item{experiments}{Main experiments database}
#'     \item{test}{Test database}
#'   }
#' @export
#'
#' @examples
#' \dontrun{
#' paths <- get_all_db_paths()
#' cat("Experiments DB:", paths$experiments, "\n")
#' cat("Test DB:", paths$test, "\n")
#' }
get_all_db_paths <- function() {
  list(
    experiments = get_experiments_db_path(),
    test = get_test_db_path()
  )
}

#' Validate Database Path
#'
#' Checks if a database path is valid and accessible.
#'
#' @param db_path Character string with database path
#' @param create_if_missing Logical. If TRUE, creates parent directories if needed.
#'
#' @return TRUE if valid, stops with error otherwise
#' @export
#'
#' @examples
#' \dontrun{
#' db_path <- get_experiments_db_path()
#' validate_db_path(db_path, create_if_missing = TRUE)
#' }
validate_db_path <- function(db_path, create_if_missing = FALSE) {
  if (!is.character(db_path) || length(db_path) != 1) {
    stop("db_path must be a single character string", call. = FALSE)
  }
  
  parent_dir <- dirname(db_path)
  
  if (!dir.exists(parent_dir)) {
    if (create_if_missing) {
      dir.create(parent_dir, recursive = TRUE, showWarnings = FALSE)
    } else {
      stop("Parent directory does not exist: ", parent_dir, call. = FALSE)
    }
  }
  
  TRUE
}

#' Print Database Configuration
#'
#' Prints current database configuration.
#' Useful for debugging and verification.
#'
#' @return Invisibly returns list of paths
#' @export
#'
#' @examples
#' \dontrun{
#' print_db_config()
#' }
print_db_config <- function() {
  paths <- get_all_db_paths()
  
  cat("\n========================================\n")
  cat("Database Configuration\n")
  cat("========================================\n\n")
  
  cat("Experiments DB:\n")
  cat("  Path:", paths$experiments, "\n")
  cat("  Exists:", file.exists(paths$experiments), "\n")
  if (file.exists(paths$experiments)) {
    cat("  Size:", format(file.info(paths$experiments)$size, units = "auto"), "\n")
  }
  
  cat("\nTest DB:\n")
  cat("  Path:", paths$test, "\n")
  cat("  Exists:", file.exists(paths$test), "\n")
  if (file.exists(paths$test)) {
    cat("  Size:", format(file.info(paths$test)$size, units = "auto"), "\n")
  }
  
  cat("\nEnvironment Variables:\n")
  cat("  EXPERIMENTS_DB:", Sys.getenv("EXPERIMENTS_DB", "(not set, using default)"), "\n")
  cat("  TEST_DB:", Sys.getenv("TEST_DB", "(not set, using default)"), "\n")
  
  cat("\n========================================\n\n")
  
  invisible(paths)
}
