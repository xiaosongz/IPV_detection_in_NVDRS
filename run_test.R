#!/usr/bin/env Rscript

# Simple test runner script
library(nvdrsipvdetector)
library(DBI)
library(RSQLite)
library(cli)
library(dplyr)
library(purrr)

# Source the test tracking functions
source("nvdrsipvdetector/R/test_tracking.R")

# Load configuration
config <- load_config()

# Initialize databases
api_conn <- init_database(config$database$path)
test_conn <- init_test_database("logs/test_tracking.sqlite")

# Create test run
run_id <- create_test_run(
  conn = test_conn,
  prompt_version = "baseline_v1.0",
  model_name = config$api$model,
  description = "Baseline test with original prompt",
  config = config
)

# Load test data
test_data <- read.csv("tests/test_data/test_sample.csv", stringsAsFactors = FALSE)
cli::cli_alert_success("Loaded {nrow(test_data)} test cases")

# Process subset for testing (first 5 cases)
test_subset <- head(test_data, 5)

cli::cli_h2("Processing Test Cases")
pb <- cli::cli_progress_bar("Processing", total = nrow(test_subset))

for (i in seq_len(nrow(test_subset))) {
  case <- test_subset[i, ]
  cli::cli_progress_update(id = pb)
  
  cli::cli_alert_info("Processing case {case$IncidentID}")
  
  # Process LE narrative
  le_result <- tryCatch({
    detect_ipv(
      narrative = case$NarrativeLE,
      type = "LE",
      config = config,
      conn = api_conn,
      log_to_db = TRUE
    )
  }, error = function(e) {
    cli::cli_alert_danger("Error in LE narrative: {e$message}")
    list(
      ipv_detected = NA,
      confidence = NA,
      indicators = list(),
      rationale = paste("Error:", e$message),
      success = FALSE
    )
  })
  
  # Log result
  log_classification_result(
    conn = test_conn,
    run_id = run_id,
    incident_id = case$IncidentID,
    predicted = le_result,
    actual = case$ipv_flag_LE,
    narrative_type = "LE",
    processing_time_ms = 100
  )
  
  # Process CME narrative
  cme_result <- tryCatch({
    detect_ipv(
      narrative = case$NarrativeCME,
      type = "CME",
      config = config,
      conn = api_conn,
      log_to_db = TRUE
    )
  }, error = function(e) {
    cli::cli_alert_danger("Error in CME narrative: {e$message}")
    list(
      ipv_detected = NA,
      confidence = NA,
      indicators = list(),
      rationale = paste("Error:", e$message),
      success = FALSE
    )
  })
  
  # Log result
  log_classification_result(
    conn = test_conn,
    run_id = run_id,
    incident_id = case$IncidentID,
    predicted = cme_result,
    actual = case$ipv_flag_CME,
    narrative_type = "CME",
    processing_time_ms = 100
  )
  
  # Display results
  cli::cli_alert_info(
    "LE: Predicted={le_result$ipv_detected}, Actual={case$ipv_flag_LE}, Conf={round(le_result$confidence, 2)}"
  )
  cli::cli_alert_info(
    "CME: Predicted={cme_result$ipv_detected}, Actual={case$ipv_flag_CME}, Conf={round(cme_result$confidence, 2)}"
  )
}

cli::cli_progress_done(id = pb)

# Calculate metrics
cli::cli_h2("Calculating Metrics")
metrics <- calculate_test_metrics(test_conn, run_id)

if (!is.null(metrics)) {
  cli::cli_alert_success(
    "Overall: Accuracy={round(metrics$accuracy, 3)}, F1={round(metrics$f1_score, 3)}"
  )
  cli::cli_alert_info("Confusion Matrix:")
  cli::cli_alert_info("  TP={metrics$confusion_matrix$tp}, TN={metrics$confusion_matrix$tn}")
  cli::cli_alert_info("  FP={metrics$confusion_matrix$fp}, FN={metrics$confusion_matrix$fn}")
}

# Complete test run
complete_test_run(test_conn, run_id, status = "completed")

# Cleanup
DBI::dbDisconnect(api_conn)
DBI::dbDisconnect(test_conn)

cli::cli_alert_success("Test completed!")