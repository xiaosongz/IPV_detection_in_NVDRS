#!/usr/bin/env Rscript
# Standalone Phase 1 Test - Run with: Rscript tests/run_phase1_test.R

cat("\n========================================\n")
cat("Phase 1 Implementation Test\n")
cat("========================================\n\n")

# Load required libraries
cat("Step 1: Loading libraries...\n")
required_libs <- c("here", "DBI", "RSQLite", "yaml", "uuid", "dplyr", "tibble", "readxl", "jsonlite", "tidyr")

for (lib in required_libs) {
  if (!requireNamespace(lib, quietly = TRUE)) {
    cat("✗ Missing library:", lib, "\n")
    cat("  Install with: install.packages('", lib, "')\n", sep = "")
    quit(save = "no", status = 1)
  }
}

library(here)  # Automatically finds project root
library(DBI)
library(RSQLite)
library(yaml)
library(uuid)
library(dplyr)
library(tibble)
library(readxl)
library(jsonlite)
library(tidyr)

cat("✓ All libraries loaded\n\n")

# Load our new functions
cat("Step 2: Loading new functions...\n")
tryCatch({
  source(here("R", "db_schema.R"))
  source(here("R", "data_loader.R"))
  source(here("R", "config_loader.R"))
  source(here("R", "experiment_logger.R"))
  source(here("R", "experiment_queries.R"))
  cat("✓ Functions loaded\n\n")
}, error = function(e) {
  cat("✗ Error loading functions:", conditionMessage(e), "\n")
  quit(save = "no", status = 1)
})

# Clean up any existing test database
cat("Step 3: Cleaning up old test files...\n")
test_db <- here("test_experiments.db")
if (file.exists(test_db)) {
  file.remove(test_db)
  cat("  Removed old test database\n")
}
if (dir.exists(here("logs", "experiments"))) {
  old_logs <- list.dirs(here("logs", "experiments"), full.names = TRUE, recursive = FALSE)
  if (length(old_logs) > 0) {
    for (log_dir in old_logs) {
      unlink(log_dir, recursive = TRUE)
    }
    cat("  Removed", length(old_logs), "old log directories\n")
  }
}
cat("✓ Cleanup complete\n\n")

# Initialize test database
cat("Step 4: Creating test database...\n")
tryCatch({
  conn <- init_experiment_db(test_db)
  tables <- dbListTables(conn)
  cat("✓ Database created with", length(tables), "tables\n")
  cat("  Tables:", paste(tables, collapse = ", "), "\n\n")
}, error = function(e) {
  cat("✗ Error creating database:", conditionMessage(e), "\n")
  quit(save = "no", status = 1)
})

# Load config
cat("Step 5: Loading configuration...\n")
config_path <- here("configs", "experiments", "exp_001_test_gpt_oss.yaml")
tryCatch({
  config <- load_experiment_config(config_path)
  cat("  Config loaded\n")
  validate_config(config)
  cat("✓ Configuration validated\n")
  cat("  Model:", config$model$name, "\n")
  cat("  API URL:", config$model$api_url, "\n")
  cat("  Temperature:", config$model$temperature, "\n")
  cat("  Max narratives:", config$run$max_narratives, "\n\n")
}, error = function(e) {
  cat("✗ Error with config:", conditionMessage(e), "\n")
  dbDisconnect(conn)
  quit(save = "no", status = 1)
})

# Load source data
cat("Step 6: Loading source data...\n")
data_file <- config$data$file
tryCatch({
  n_loaded <- load_source_data(conn, data_file)
  cat("✓ Loaded", n_loaded, "narratives\n\n")
}, error = function(e) {
  cat("✗ Error loading data:", conditionMessage(e), "\n")
  dbDisconnect(conn)
  quit(save = "no", status = 1)
})

# Query narratives
cat("Step 7: Querying narratives...\n")
tryCatch({
  narratives <- get_source_narratives(conn, max_narratives = 5)
  cat("✓ Retrieved", nrow(narratives), "sample narratives\n")
  cat("  Columns:", paste(names(narratives), collapse = ", "), "\n\n")
}, error = function(e) {
  cat("✗ Error querying:", conditionMessage(e), "\n")
  dbDisconnect(conn)
  quit(save = "no", status = 1)
})

# Start experiment
cat("Step 8: Creating experiment record...\n")
tryCatch({
  experiment_id <- start_experiment(conn, config)
  cat("✓ Experiment created\n")
  cat("  ID:", experiment_id, "\n\n")
}, error = function(e) {
  cat("✗ Error starting experiment:", conditionMessage(e), "\n")
  dbDisconnect(conn)
  quit(save = "no", status = 1)
})

# Initialize logger
cat("Step 9: Testing logger...\n")
tryCatch({
  logger <- init_experiment_logger(experiment_id)
  logger$info("Test initialization message")
  logger$warn("Test warning message")
  logger$performance("test_narrative_001", 1.23, "OK")
  cat("✓ Logger initialized\n")
  cat("  Log directory:", logger$log_dir, "\n")
  cat("  Log files created:\n")
  for (log_type in names(logger$paths)) {
    if (file.exists(logger$paths[[log_type]])) {
      cat("    ✓", basename(logger$paths[[log_type]]), "\n")
    } else {
      cat("    ✗", basename(logger$paths[[log_type]]), "NOT CREATED\n")
    }
  }
  cat("\n")
}, error = function(e) {
  cat("✗ Error with logger:", conditionMessage(e), "\n")
  dbDisconnect(conn)
  quit(save = "no", status = 1)
})

# Test queries
cat("Step 10: Testing query functions...\n")
tryCatch({
  experiments <- list_experiments(conn)
  cat("✓ Found", nrow(experiments), "experiment(s)\n\n")
}, error = function(e) {
  cat("✗ Error with queries:", conditionMessage(e), "\n")
  dbDisconnect(conn)
  quit(save = "no", status = 1)
})

# Inspect database
cat("Step 11: Database inspection...\n")
cat("  source_narratives:", dbGetQuery(conn, "SELECT COUNT(*) as n FROM source_narratives")$n, "rows\n")
cat("  experiments:", dbGetQuery(conn, "SELECT COUNT(*) as n FROM experiments")$n, "rows\n")
cat("  narrative_results:", dbGetQuery(conn, "SELECT COUNT(*) as n FROM narrative_results")$n, "rows\n\n")

# Cleanup
dbDisconnect(conn)

cat("========================================\n")
cat("✅ ALL TESTS PASSED!\n")
cat("========================================\n\n")

cat("Test artifacts created:\n")
cat("  Database:", test_db, "\n")
cat("  Logs:", file.path("logs", "experiments", experiment_id), "\n\n")

cat("Next step: Implement Phase 2 (run_experiment.R orchestrator)\n\n")
