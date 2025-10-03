#' Database Configuration
#'
#' Centralized database path configuration.
#' Single source of truth for all database locations.
#'
#' @description
#' This module provides centralized configuration for database paths.
#' 
#' Configuration priority (highest to lowest):
#' 1. Environment variables (EXPERIMENTS_DB, TEST_DB)
#' 2. .db_config file in project root
#' 3. Default values (data/experiments.db, tests/fixtures/test_experiments.db)
#'
#' @section Configuration Methods:
#' 
#' **Method 1: Edit .db_config file (RECOMMENDED)**
#' ```
#' # Edit .db_config in project root
#' EXPERIMENTS_DB=data/experiments.db
#' TEST_DB=tests/fixtures/test_experiments.db
#' ```
#' 
#' **Method 2: Environment variable**
#' ```bash
#' EXPERIMENTS_DB=custom.db Rscript scripts/run_experiment.R config.yaml
#' ```
#' 
#' **Method 3: In R code**
#' ```r
#' Sys.setenv(EXPERIMENTS_DB = "my_custom.db")
#' ```
#'
#' @keywords internal

#' Load Database Configuration from File
#'
#' Reads .db_config file if it exists and sets environment variables.
#' This is called automatically by get_experiments_db_path().
#'
#' @return Invisible list of loaded config values
#' @keywords internal
load_db_config_file <- function() {
  config_file <- here::here(".db_config")
  
  if (!file.exists(config_file)) {
    return(invisible(NULL))
  }
  
  # Read config file
  lines <- readLines(config_file, warn = FALSE)
  
  # Parse lines
  config <- list()
  for (line in lines) {
    line <- trimws(line)
    
    # Skip comments and empty lines
    if (line == "" || grepl("^#", line)) {
      next
    }
    
    # Parse KEY=VALUE
    parts <- strsplit(line, "=", fixed = TRUE)[[1]]
    if (length(parts) == 2) {
      key <- trimws(parts[1])
      value <- trimws(parts[2])
      
      # Only set if not already set by environment
      if (Sys.getenv(key, "") == "") {
        # Set environment variable properly
        env_list <- list()
        env_list[[key]] <- value
        do.call(Sys.setenv, env_list)
      }
      
      config[[key]] <- value
    }
  }
  
  invisible(config)
}

#' Get Main Experiments Database Path
#'
#' Returns the path to the main experiments database.
#' Configuration priority:
#' 1. EXPERIMENTS_DB environment variable
#' 2. .db_config file
#' 3. Default: data/experiments.db
#'
#' @return Character string with full path to experiments database
#' @export
#'
#' @examples
#' \dontrun{
#' # Uses configuration priority
#' db_path <- get_experiments_db_path()
#' conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
#' }
get_experiments_db_path <- function() {
  # Load config file if not already loaded
  load_db_config_file()
  
  # Get from environment (either set directly or loaded from file)
  db_path <- Sys.getenv("EXPERIMENTS_DB", "")
  
  # Use default if not set
  if (db_path == "") {
    db_path <- "data/experiments.db"
  }
  
  # Expand home directory if used
  db_path <- path.expand(db_path)
  
  # Make absolute path if relative
  if (!startsWith(db_path, "/") && !grepl("^[A-Z]:", db_path)) {
    db_path <- here::here(db_path)
  }
  
  db_path
}

#' Get Test Database Path
#'
#' Returns the path to the test database.
#' Configuration priority:
#' 1. TEST_DB environment variable
#' 2. .db_config file
#' 3. Default: tests/fixtures/test_experiments.db
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
  # Load config file if not already loaded
  load_db_config_file()
  
  # Get from environment (either set directly or loaded from file)
  db_path <- Sys.getenv("TEST_DB", "")
  
  # Use default if not set
  if (db_path == "") {
    db_path <- "tests/fixtures/test_experiments.db"
  }
  
  # Expand home directory if used
  db_path <- path.expand(db_path)
  
  # Make absolute path if relative
  if (!startsWith(db_path, "/") && !grepl("^[A-Z]:", db_path)) {
    db_path <- here::here(db_path)
  }
  
  db_path
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
  
  cat("Configuration File:\n")
  config_file <- here::here(".db_config")
  cat("  Location:", config_file, "\n")
  cat("  Exists:", file.exists(config_file), "\n\n")
  
  cat("Experiments DB:\n")
  cat("  Path:", paths$experiments, "\n")
  cat("  Exists:", file.exists(paths$experiments), "\n")
  if (file.exists(paths$experiments)) {
    cat("  Size:", format(file.info(paths$experiments)$size, units = "auto"), "\n")
  }
  cat("  Directory:", dirname(paths$experiments), "\n")
  
  cat("\nTest DB:\n")
  cat("  Path:", paths$test, "\n")
  cat("  Exists:", file.exists(paths$test), "\n")
  if (file.exists(paths$test)) {
    cat("  Size:", format(file.info(paths$test)$size, units = "auto"), "\n")
  }
  cat("  Directory:", dirname(paths$test), "\n")
  
  cat("\nConfiguration Priority:\n")
  cat("  1. Environment variables (highest)\n")
  cat("  2. .db_config file\n")
  cat("  3. Default values (lowest)\n")
  
  cat("\nCurrent Environment Variables:\n")
  cat("  EXPERIMENTS_DB:", Sys.getenv("EXPERIMENTS_DB", "(not set)"), "\n")
  cat("  TEST_DB:", Sys.getenv("TEST_DB", "(not set)"), "\n")
  
  cat("\nTo Change Database Locations:\n")
  cat("  Edit .db_config file in project root\n")
  cat("  Example: EXPERIMENTS_DB=data/experiments.db\n")
  
  cat("\n========================================\n\n")
  
  invisible(paths)
}
