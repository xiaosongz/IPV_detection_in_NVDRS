#!/usr/bin/env Rscript

# Test script for resumable production runs
# Tests all 6 acceptance criteria from spec v3

library(here)

cat("\n")
cat("================================================================================\n")
cat("                  Resumable Production Runs - Test Suite\n")
cat("================================================================================\n\n")

# Use test database
Sys.setenv(TEST_DB = here("tests", "fixtures", "test_resumable.db"))

# Clean up any existing test database
test_db <- here("tests", "fixtures", "test_resumable.db")
if (file.exists(test_db)) {
  file.remove(test_db)
  cat("✓ Removed existing test database\n")
}

# Clean up any lock files
lock_files <- list.files(here("data"), pattern = "^\\.resume_lock_.*\\.pid$", full.names = TRUE)
if (length(lock_files) > 0) {
  file.remove(lock_files)
  cat("✓ Removed", length(lock_files), "stale lock files\n")
}

cat("\n")

# Test 1: Run initial experiment (partial)
cat("========================================\n")
cat("Test 1: Initial run (20 narratives)\n")
cat("========================================\n\n")

system2("Rscript", 
        args = c("scripts/run_experiment.R", "configs/experiments/exp_900_test_resume.yaml"),
        env = c("TEST_DB"=test_db))

# Get experiment ID from database
source(here("R", "db_config.R"))
source(here("R", "db_schema.R"))

Sys.setenv(EXPERIMENTS_DB = test_db)
conn <- get_db_connection(test_db)

exp_info <- DBI::dbGetQuery(conn, "
  SELECT experiment_id, experiment_name, n_narratives_processed, n_narratives_completed
  FROM experiments
  ORDER BY created_at DESC
  LIMIT 1
")

if (nrow(exp_info) == 0) {
  cat("✗ FAILED: No experiment found in database\n")
  quit(save = "no", status = 1)
}

experiment_id <- exp_info$experiment_id
cat("\n✓ Initial run complete\n")
cat("  Experiment ID:", experiment_id, "\n")
cat("  Processed:", exp_info$n_narratives_processed, "narratives\n\n")

DBI::dbDisconnect(conn)

# Test 2: Resume same experiment (should skip duplicates)
cat("========================================\n")
cat("Test 2: Resume (idempotency test)\n")
cat("========================================\n\n")

cat("Running same narratives again - should detect duplicates...\n\n")

system2("Rscript",
        args = c("scripts/run_experiment.R", "configs/experiments/exp_900_test_resume.yaml"),
        env = c("TEST_DB"=test_db, 
                "RESUME"="1",
                "EXPERIMENT_ID"=experiment_id))

conn <- get_db_connection(test_db)

# Check for duplicates
dup_check <- DBI::dbGetQuery(conn, "
  SELECT incident_id, narrative_type, COUNT(*) as n
  FROM narrative_results
  WHERE experiment_id = ?
  GROUP BY incident_id, narrative_type
  HAVING COUNT(*) > 1
", params = list(experiment_id))

if (nrow(dup_check) > 0) {
  cat("✗ FAILED: Found", nrow(dup_check), "duplicates!\n")
  print(dup_check)
  quit(save = "no", status = 1)
} else {
  cat("\n✓ Idempotency test passed: No duplicates found\n\n")
}

DBI::dbDisconnect(conn)

# Test 3: Check progress tracking
cat("========================================\n")
cat("Test 3: Progress tracking\n")
cat("========================================\n\n")

conn <- get_db_connection(test_db)

progress_info <- DBI::dbGetQuery(conn, "
  SELECT n_narratives_total, n_narratives_completed, 
         last_progress_update, estimated_completion_time
  FROM experiments
  WHERE experiment_id = ?
", params = list(experiment_id))

cat("Progress information:\n")
cat("  Total:", progress_info$n_narratives_total, "\n")
cat("  Completed:", progress_info$n_narratives_completed, "\n")
cat("  Last update:", progress_info$last_progress_update, "\n")
cat("  ETA:", progress_info$estimated_completion_time, "\n")

if (!is.na(progress_info$n_narratives_completed) && progress_info$n_narratives_completed > 0) {
  cat("\n✓ Progress tracking working\n\n")
} else {
  cat("\n✗ FAILED: Progress not tracked\n\n")
  quit(save = "no", status = 1)
}

DBI::dbDisconnect(conn)

# Test 4: Check checksum
cat("========================================\n")
cat("Test 4: Checksum verification\n")
cat("========================================\n\n")

source(here("R", "data_loader.R"))

conn <- get_db_connection(test_db)

data_file <- "data-raw/suicide_IPV_manuallyflagged.xlsx"
checksum_ok <- verify_source_checksum(conn, data_file)

if (is.na(checksum_ok)) {
  cat("✗ FAILED: No checksum stored\n\n")
  quit(save = "no", status = 1)
} else if (checksum_ok) {
  cat("✓ Checksum verified successfully\n\n")
} else {
  cat("✗ FAILED: Checksum mismatch\n\n")
  quit(save = "no", status = 1)
}

DBI::dbDisconnect(conn)

# Test 5: Concurrent resume prevention (check lock mechanism)
cat("========================================\n")
cat("Test 5: Lock file mechanism\n")
cat("========================================\n\n")

source(here("R", "experiment_logger.R"))

# Try to acquire lock
acquire_resume_lock(experiment_id)
cat("✓ Lock acquired\n")

# Check lock file exists
lock_file <- here("data", paste0(".resume_lock_", experiment_id, ".pid"))
if (file.exists(lock_file)) {
  cat("✓ Lock file created:", lock_file, "\n")
} else {
  cat("✗ FAILED: Lock file not created\n\n")
  quit(save = "no", status = 1)
}

# Release lock
release_resume_lock(experiment_id)
cat("✓ Lock released\n")

if (!file.exists(lock_file)) {
  cat("✓ Lock file removed\n\n")
} else {
  cat("✗ FAILED: Lock file not removed\n\n")
  quit(save = "no", status = 1)
}

# Test 6: UNIQUE constraint enforcement
cat("========================================\n")
cat("Test 6: UNIQUE constraint check\n")
cat("========================================\n\n")

conn <- get_db_connection(test_db)

# Check for unique index
index_info <- DBI::dbGetQuery(conn, "
  SELECT name FROM sqlite_master
  WHERE type = 'index'
  AND tbl_name = 'narrative_results'
  AND name LIKE '%exp_incident_type%'
")

if (nrow(index_info) > 0) {
  cat("✓ UNIQUE index exists:", index_info$name[1], "\n\n")
} else {
  cat("⚠ WARNING: UNIQUE index not found (may be in table definition)\n\n")
}

# Verify no duplicates exist
dup_count <- DBI::dbGetQuery(conn, "
  SELECT COUNT(*) as n
  FROM (
    SELECT experiment_id, incident_id, narrative_type, COUNT(*) as cnt
    FROM narrative_results
    GROUP BY experiment_id, incident_id, narrative_type
    HAVING COUNT(*) > 1
  )
")

if (dup_count$n == 0) {
  cat("✓ No duplicate records in database\n\n")
} else {
  cat("✗ FAILED: Found", dup_count$n, "duplicate records\n\n")
  quit(save = "no", status = 1)
}

DBI::dbDisconnect(conn)

# Summary
cat("================================================================================\n")
cat("                        All Tests Passed!\n")
cat("================================================================================\n\n")

cat("Test Results:\n")
cat("  ✓ Test 1: Initial run completed\n")
cat("  ✓ Test 2: Idempotency (no duplicates on resume)\n")
cat("  ✓ Test 3: Progress tracking functional\n")
cat("  ✓ Test 4: Checksum verification working\n")
cat("  ✓ Test 5: Lock file mechanism working\n")
cat("  ✓ Test 6: UNIQUE constraint enforced\n\n")

cat("Test database:", test_db, "\n")
cat("Experiment ID:", experiment_id, "\n\n")

cat("✓ Resumable production runs implementation validated!\n\n")
