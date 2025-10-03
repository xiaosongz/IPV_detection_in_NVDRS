#!/usr/bin/env Rscript

#' Manual Test for Experiment Setup Functions
#' 
#' This script tests the core functions before running a full experiment

library(here)

cat("=== Testing Experiment Setup Functions ===\n\n")

# Test 1: Load functions
cat("Test 1: Loading functions...\n")
tryCatch({
  source(here("R", "db_schema.R"))
  source(here("R", "data_loader.R"))
  source(here("R", "config_loader.R"))
  source(here("R", "experiment_logger.R"))
  source(here("R", "experiment_queries.R"))
  cat("✓ All functions loaded successfully\n\n")
}, error = function(e) {
  cat("✗ Error loading functions:", conditionMessage(e), "\n")
  quit(save = "no", status = 1)
})

# Test 2: Check required packages
cat("Test 2: Checking required packages...\n")
required_pkgs <- c("DBI", "RSQLite", "yaml", "uuid", "here", "dplyr", "tibble", "readxl", "jsonlite", "tidyr")
for (pkg in required_pkgs) {
  has_pkg <- requireNamespace(pkg, quietly = TRUE)
  status <- if (has_pkg) "✓" else "✗"
  cat(sprintf("  %s %s\n", status, pkg))
  if (!has_pkg) {
    cat("\n✗ Missing required package:", pkg, "\n")
    cat("Install with: install.packages('", pkg, "')\n", sep = "")
    quit(save = "no", status = 1)
  }
}
cat("\n")

# Test 3: Initialize test database
cat("Test 3: Creating test database...\n")
test_db <- here("test_experiments.db")
if (file.exists(test_db)) {
  file.remove(test_db)
  cat("  Removed existing test database\n")
}

tryCatch({
  conn <- init_experiment_db(test_db)
  tables <- DBI::dbListTables(conn)
  cat("✓ Database created with tables:", paste(tables, collapse = ", "), "\n\n")
}, error = function(e) {
  cat("✗ Error creating database:", conditionMessage(e), "\n")
  quit(save = "no", status = 1)
})

# Test 4: Load and validate config
cat("Test 4: Loading and validating config...\n")
config_path <- here("configs", "experiments", "exp_001_test_gpt_oss.yaml")

if (!file.exists(config_path)) {
  cat("✗ Config file not found:", config_path, "\n")
  DBI::dbDisconnect(conn)
  quit(save = "no", status = 1)
}

tryCatch({
  config <- load_experiment_config(config_path)
  cat("  Config loaded successfully\n")
  validate_config(config)
  cat("✓ Config validated successfully\n\n")
}, error = function(e) {
  cat("✗ Error with config:", conditionMessage(e), "\n")
  DBI::dbDisconnect(conn)
  quit(save = "no", status = 1)
})

# Test 5: Load source data
cat("Test 5: Loading source data...\n")
data_file <- here("data-raw", "suicide_IPV_manuallyflagged.xlsx")

if (!file.exists(data_file)) {
  cat("✗ Data file not found:", data_file, "\n")
  DBI::dbDisconnect(conn)
  quit(save = "no", status = 1)
}

tryCatch({
  n_loaded <- load_source_data(conn, data_file)
  cat("✓ Loaded", n_loaded, "narratives\n\n")
}, error = function(e) {
  cat("✗ Error loading data:", conditionMessage(e), "\n")
  DBI::dbDisconnect(conn)
  quit(save = "no", status = 1)
})

# Test 6: Query source narratives
cat("Test 6: Querying source narratives...\n")
tryCatch({
  narratives <- get_source_narratives(conn, max_narratives = 5)
  cat("✓ Retrieved", nrow(narratives), "narratives\n")
  cat("  Columns:", paste(names(narratives), collapse = ", "), "\n\n")
}, error = function(e) {
  cat("✗ Error querying narratives:", conditionMessage(e), "\n")
  DBI::dbDisconnect(conn)
  quit(save = "no", status = 1)
})

# Test 7: Start experiment
cat("Test 7: Starting experiment...\n")
tryCatch({
  experiment_id <- start_experiment(conn, config)
  cat("✓ Experiment started with ID:", experiment_id, "\n\n")
}, error = function(e) {
  cat("✗ Error starting experiment:", conditionMessage(e), "\n")
  DBI::dbDisconnect(conn)
  quit(save = "no", status = 1)
})

# Test 8: Initialize logger
cat("Test 8: Initializing logger...\n")
tryCatch({
  logger <- init_experiment_logger(experiment_id)
  logger$info("Test log message")
  logger$warn("Test warning message")
  logger$performance("test_narrative_001", 1.23, "OK")
  cat("✓ Logger initialized and tested\n")
  cat("  Log directory:", logger$log_dir, "\n\n")
}, error = function(e) {
  cat("✗ Error with logger:", conditionMessage(e), "\n")
  DBI::dbDisconnect(conn)
  quit(save = "no", status = 1)
})

# Test 9: List experiments
cat("Test 9: Querying experiments...\n")
tryCatch({
  experiments <- list_experiments(conn)
  cat("✓ Found", nrow(experiments), "experiment(s)\n")
  if (nrow(experiments) > 0) {
    print(experiments[, c("experiment_id", "experiment_name", "status", "model_name")])
  }
  cat("\n")
}, error = function(e) {
  cat("✗ Error querying experiments:", conditionMessage(e), "\n")
  DBI::dbDisconnect(conn)
  quit(save = "no", status = 1)
})

# Cleanup
cat("Cleanup: Closing database connection...\n")
DBI::dbDisconnect(conn)

cat("\n=== All Tests Passed! ===\n\n")
cat("Test database created at:", test_db, "\n")
cat("Test logs created at:", file.path("logs", "experiments", experiment_id), "\n\n")
cat("You can inspect the test database with:\n")
cat("  sqlite3", test_db, "\n\n")
cat("Ready to implement run_experiment.R!\n")
