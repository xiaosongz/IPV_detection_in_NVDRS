# Test Setup Utilities
#
# Core helper functions for test setup, fixtures, and utilities

library(testthat)
library(DBI)
library(RSQLite)
library(dplyr)
library(withr)

# Source required R functions for tests
source(here::here("R", "config_loader.R"), local = TRUE)
source(here::here("R", "data_loader.R"), local = TRUE)
source(here::here("R", "db_config.R"), local = TRUE)
source(here::here("R", "db_schema.R"), local = TRUE)
source(here::here("R", "experiment_logger.R"), local = TRUE)
source(here::here("R", "experiment_queries.R"), local = TRUE)
source(here::here("R", "build_prompt.R"), local = TRUE)
source(here::here("R", "call_llm.R"), local = TRUE)
source(here::here("R", "parse_llm_result.R"), local = TRUE)
source(here::here("R", "repair_json.R"), local = TRUE)
source(here::here("R", "run_benchmark_core.R"), local = TRUE)
source(here::here("tests/testthat/helper-mocks.R"), local = TRUE)

#' Create a temporary in-memory database for testing
#'
#' @param initialize If TRUE, run init_experiment_db()
#' @return Database connection
#' @export
create_temp_db <- function(initialize = TRUE, defer_env = parent.frame()) {
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")

  if (initialize) {
    # Source the db_schema.R to get init function
    source(here::here("R/db_schema.R"), local = TRUE)
    init_experiment_db_internal(con)
  }

  # Register cleanup in provided environment (ensures proper lifecycle in nested helpers)
  withr::defer(DBI::dbDisconnect(con), envir = defer_env)

  return(con)
}

#' Initialize database tables without file path complications
#' @keywords internal
init_experiment_db_internal <- function(conn) {
  # Create source_narratives table
  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS source_narratives (
      narrative_id INTEGER PRIMARY KEY AUTOINCREMENT,
      incident_id TEXT NOT NULL,
      narrative_type TEXT NOT NULL,
      narrative_text TEXT,
      manual_flag_ind INTEGER DEFAULT 0,
      manual_flag INTEGER DEFAULT 0,
      data_source TEXT,
      loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(incident_id, narrative_type)
    )
  ")

  # Create experiments table
  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS experiments (
      experiment_id TEXT PRIMARY KEY,
      experiment_name TEXT NOT NULL,
      status TEXT DEFAULT 'pending',
      model_name TEXT NOT NULL,
      model_provider TEXT,
      temperature REAL,
      system_prompt TEXT NOT NULL,
      user_template TEXT NOT NULL,
      prompt_version TEXT,
      prompt_author TEXT,
      run_seed INTEGER,
      data_file TEXT,
      n_narratives_total INTEGER,
      n_narratives_processed INTEGER DEFAULT 0,
      n_narratives_skipped INTEGER DEFAULT 0,
      start_time TIMESTAMP,
      end_time TIMESTAMP,
      total_runtime_sec REAL,
      avg_time_per_narrative_sec REAL,
      api_url TEXT,
      r_version TEXT,
      os_info TEXT,
      hostname TEXT,
      n_positive_detected INTEGER,
      n_negative_detected INTEGER,
      n_positive_manual INTEGER,
      n_negative_manual INTEGER,
      accuracy REAL,
      precision_ipv REAL,
      recall_ipv REAL,
      f1_ipv REAL,
      n_false_positive INTEGER,
      n_false_negative INTEGER,
      n_true_positive INTEGER,
      n_true_negative INTEGER,
      pct_overlap_with_manual REAL,
      csv_file TEXT,
      json_file TEXT,
      log_dir TEXT,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      notes TEXT
    )
  ")

  # Create narrative_results table
  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS narrative_results (
      result_id INTEGER PRIMARY KEY AUTOINCREMENT,
      experiment_id TEXT NOT NULL,
      incident_id TEXT,
      narrative_type TEXT,
      row_num INTEGER,
      narrative_text TEXT,
      manual_flag_ind INTEGER,
      manual_flag INTEGER,
      detected INTEGER,
      confidence REAL,
      indicators TEXT,
      rationale TEXT,
      reasoning_steps TEXT,
      raw_response TEXT,
      response_sec REAL,
      processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      error_occurred INTEGER DEFAULT 0,
      error_message TEXT,
      prompt_tokens INTEGER,
      completion_tokens INTEGER,
      tokens_used INTEGER,
      is_true_positive INTEGER,
      is_true_negative INTEGER,
      is_false_positive INTEGER,
      is_false_negative INTEGER,
      FOREIGN KEY (experiment_id) REFERENCES experiments(experiment_id)
    )
  ")

  invisible(TRUE)
}

#' Create sample narratives for testing
#'
#' @param n Number of narratives to create
#' @param with_ipv Proportion that are IPV cases (0-1)
#' @return tibble of narratives
#' @export
create_sample_narratives <- function(n = 10, with_ipv = 0.5) {
  n_ipv <- floor(n * with_ipv)
  n_non_ipv <- n - n_ipv

  ipv_texts <- c(
    "Boyfriend punched her in the face multiple times during argument",
    "Partner threatened to kill her if she left",
    "Husband controlled all finances and prevented her from working",
    "Ex-boyfriend stalked her and showed up at her workplace daily",
    "Partner isolated her from family and friends",
    "Boyfriend choked her until she lost consciousness",
    "Partner destroyed her belongings during fight",
    "Husband forced her to have sex against her will"
  )

  non_ipv_texts <- c(
    "Died by suicide, no indication of relationship violence",
    "Accidental overdose, living alone",
    "Single vehicle accident, no passengers",
    "Medical complications, no violence indicated",
    "Self-inflicted gunshot wound, note mentioned depression only",
    "Fell from building, investigation found no foul play"
  )

  tibble::tibble(
    incident_id = sprintf("INC-%05d", 1:n),
    narrative_type = "LE",
    narrative_text = c(
      sample(ipv_texts, n_ipv, replace = TRUE),
      sample(non_ipv_texts, n_non_ipv, replace = TRUE)
    ),
    manual_flag_ind = 1,
    manual_flag = c(rep(1, n_ipv), rep(0, n_non_ipv)),
    data_source = "test"
  )
}

#' Load sample narratives into database
#'
#' @param conn Database connection
#' @param narratives Tibble of narratives (optional, creates default if NULL)
#' @return Number of rows inserted
#' @export
load_sample_narratives <- function(conn, narratives = NULL) {
  if (is.null(narratives)) {
    narratives <- create_sample_narratives()
  }

  DBI::dbWriteTable(conn, "source_narratives", narratives, append = TRUE)
  return(nrow(narratives))
}

#' Get fixture file path
#'
#' @param type Type of fixture (configs, data, responses, databases)
#' @param filename Name of fixture file
#' @return Full path to fixture
#' @export
fixture_path <- function(type, filename) {
  here::here("tests", "fixtures", type, filename)
}

#' Skip test if not in appropriate environment
#'
#' @param env_var Environment variable to check
#' @param message Message to display when skipping
#' @export
skip_if_not_env <- function(env_var, message = NULL) {
  if (Sys.getenv(env_var) != "1") {
    if (is.null(message)) {
      message <- sprintf("Skipping: %s not set", env_var)
    }
    testthat::skip(message)
  }
}

#' Skip if live tests not enabled
#' @export
skip_if_not_live <- function() {
  skip_if_not_env("RUN_LIVE_TESTS", "Skipping live LLM test")
}

#' Skip if smoke tests not enabled
#' @export
skip_if_not_smoke <- function() {
  skip_if_not_env("RUN_SMOKE_TESTS", "Skipping smoke test")
}

#' Create a temporary directory and clean up after
#'
#' @param code Code to run in temp directory
#' @return Result of code
#' @export
with_temp_dir <- function(code) {
  withr::with_tempdir(code)
}

#' Silence messages during test
#'
#' @param code Code to run silently
#' @return Result of code
#' @export
quietly <- function(code) {
  suppressMessages(suppressWarnings(code))
}
