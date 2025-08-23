#!/usr/bin/env Rscript

# Full Test Runner - Process ALL cases
library(nvdrsipvdetector)
library(DBI)
library(RSQLite)
library(cli)
library(dplyr)
library(tibble)

# Source test tracking functions
source("nvdrsipvdetector/R/test_tracking.R")

cli::cli_h1("IPV Detection - FULL Dataset Test")
cli::cli_alert_info("Starting at {Sys.time()}")

# Load configuration
config <- load_config()
cli::cli_alert_success("Configuration loaded")

# Load ALL test data
test_data <- read.csv("tests/test_data/test_sample.csv", stringsAsFactors = FALSE)
cli::cli_alert_success("Loaded {nrow(test_data)} test cases")

# Initialize databases
api_conn <- init_database(config$database$path)
test_conn <- init_test_database("logs/test_tracking.sqlite")

# Create test run
run_id <- create_test_run(
  conn = test_conn,
  prompt_version = "baseline_full_v1.0",
  model_name = config$api$model,
  description = paste("FULL test - ALL", nrow(test_data), "cases"),
  config = config
)

# Results storage
all_results <- tibble()

cli::cli_h2("Processing ALL Test Cases")
pb <- cli::cli_progress_bar("Processing cases", total = nrow(test_data))

# Process EVERY case
for (i in seq_len(nrow(test_data))) {
  case <- test_data[i, ]
  cli::cli_progress_update(id = pb)
  
  # Process LE narrative
  le_start <- Sys.time()
  le_result <- tryCatch({
    result <- detect_ipv(
      narrative = case$NarrativeLE,
      type = "LE",
      config = config,
      conn = api_conn,
      log_to_db = TRUE
    )
    # Ensure all fields exist
    list(
      ipv_detected = result$ipv_detected %||% NA,
      confidence = result$confidence %||% NA,
      indicators = result$indicators %||% list(),
      rationale = result$rationale %||% "",
      success = TRUE
    )
  }, error = function(e) {
    list(
      ipv_detected = NA,
      confidence = NA,
      indicators = list(),
      rationale = paste("Error:", e$message),
      success = FALSE,
      error = e$message
    )
  })
  le_time <- as.numeric(difftime(Sys.time(), le_start, units = "secs")) * 1000
  
  # Process CME narrative
  cme_start <- Sys.time()
  cme_result <- tryCatch({
    result <- detect_ipv(
      narrative = case$NarrativeCME,
      type = "CME",
      config = config,
      conn = api_conn,
      log_to_db = TRUE
    )
    # Ensure all fields exist
    list(
      ipv_detected = result$ipv_detected %||% NA,
      confidence = result$confidence %||% NA,
      indicators = result$indicators %||% list(),
      rationale = result$rationale %||% "",
      success = TRUE
    )
  }, error = function(e) {
    list(
      ipv_detected = NA,
      confidence = NA,
      indicators = list(),
      rationale = paste("Error:", e$message),
      success = FALSE,
      error = e$message
    )
  })
  cme_time <- as.numeric(difftime(Sys.time(), cme_start, units = "secs")) * 1000
  
  # Log results to test database
  log_classification_result(
    conn = test_conn,
    run_id = run_id,
    incident_id = case$IncidentID,
    predicted = le_result,
    actual = case$ipv_flag_LE,
    narrative_type = "LE",
    processing_time_ms = le_time
  )
  
  log_classification_result(
    conn = test_conn,
    run_id = run_id,
    incident_id = case$IncidentID,
    predicted = cme_result,
    actual = case$ipv_flag_CME,
    narrative_type = "CME",
    processing_time_ms = cme_time
  )
  
  # Combined result using weights
  combined_confidence <- NA
  combined_ipv <- NA
  
  if (!is.na(le_result$ipv_detected) || !is.na(cme_result$ipv_detected)) {
    if (is.na(le_result$ipv_detected)) {
      combined_confidence <- cme_result$confidence
      combined_ipv <- cme_result$ipv_detected
    } else if (is.na(cme_result$ipv_detected)) {
      combined_confidence <- le_result$confidence
      combined_ipv <- le_result$ipv_detected
    } else {
      combined_confidence <- (le_result$confidence * config$weights$le + 
                            cme_result$confidence * config$weights$cme)
      combined_ipv <- combined_confidence >= config$weights$threshold
    }
  }
  
  # Store result
  result_row <- tibble(
    incident_id = case$IncidentID,
    actual_le = case$ipv_flag_LE,
    actual_cme = case$ipv_flag_CME,
    predicted_le = le_result$ipv_detected,
    predicted_cme = cme_result$ipv_detected,
    confidence_le = le_result$confidence,
    confidence_cme = cme_result$confidence,
    combined_ipv = combined_ipv,
    combined_confidence = combined_confidence,
    le_indicators = paste(unlist(le_result$indicators), collapse = "; "),
    cme_indicators = paste(unlist(cme_result$indicators), collapse = "; ")
  )
  
  all_results <- bind_rows(all_results, result_row)
}

cli::cli_progress_done(id = pb)

# Save detailed results
write.csv(all_results, paste0("tests/test_results/full_test_", run_id, ".csv"), row.names = FALSE)
cli::cli_alert_success("Results saved to tests/test_results/full_test_{run_id}.csv")

# Calculate and display metrics
cli::cli_h2("Performance Metrics")

# LE metrics
le_metrics <- all_results %>%
  filter(!is.na(predicted_le) & !is.na(actual_le)) %>%
  summarise(
    total = n(),
    tp = sum(predicted_le == TRUE & actual_le == TRUE),
    tn = sum(predicted_le == FALSE & actual_le == FALSE),
    fp = sum(predicted_le == TRUE & actual_le == FALSE),
    fn = sum(predicted_le == FALSE & actual_le == TRUE)
  ) %>%
  mutate(
    accuracy = (tp + tn) / total,
    precision = ifelse(tp + fp > 0, tp / (tp + fp), 0),
    recall = ifelse(tp + fn > 0, tp / (tp + fn), 0),
    f1 = ifelse(precision + recall > 0, 2 * precision * recall / (precision + recall), 0)
  )

cli::cli_alert_info("LE Performance:")
cli::cli_alert_info("  Accuracy: {round(le_metrics$accuracy, 3)}")
cli::cli_alert_info("  Precision: {round(le_metrics$precision, 3)}")
cli::cli_alert_info("  Recall: {round(le_metrics$recall, 3)}")
cli::cli_alert_info("  F1 Score: {round(le_metrics$f1, 3)}")
cli::cli_alert_info("  Confusion Matrix: TP={le_metrics$tp}, TN={le_metrics$tn}, FP={le_metrics$fp}, FN={le_metrics$fn}")

# CME metrics
cme_metrics <- all_results %>%
  filter(!is.na(predicted_cme) & !is.na(actual_cme)) %>%
  summarise(
    total = n(),
    tp = sum(predicted_cme == TRUE & actual_cme == TRUE),
    tn = sum(predicted_cme == FALSE & actual_cme == FALSE),
    fp = sum(predicted_cme == TRUE & actual_cme == FALSE),
    fn = sum(predicted_cme == FALSE & actual_cme == TRUE)
  ) %>%
  mutate(
    accuracy = (tp + tn) / total,
    precision = ifelse(tp + fp > 0, tp / (tp + fp), 0),
    recall = ifelse(tp + fn > 0, tp / (tp + fn), 0),
    f1 = ifelse(precision + recall > 0, 2 * precision * recall / (precision + recall), 0)
  )

cli::cli_alert_info("CME Performance:")
cli::cli_alert_info("  Accuracy: {round(cme_metrics$accuracy, 3)}")
cli::cli_alert_info("  Precision: {round(cme_metrics$precision, 3)}")
cli::cli_alert_info("  Recall: {round(cme_metrics$recall, 3)}")
cli::cli_alert_info("  F1 Score: {round(cme_metrics$f1, 3)}")
cli::cli_alert_info("  Confusion Matrix: TP={cme_metrics$tp}, TN={cme_metrics$tn}, FP={cme_metrics$fp}, FN={cme_metrics$fn}")

# Combined metrics
combined_metrics <- all_results %>%
  mutate(actual_combined = actual_le | actual_cme) %>%
  filter(!is.na(combined_ipv) & !is.na(actual_combined)) %>%
  summarise(
    total = n(),
    tp = sum(combined_ipv == TRUE & actual_combined == TRUE),
    tn = sum(combined_ipv == FALSE & actual_combined == FALSE),
    fp = sum(combined_ipv == TRUE & actual_combined == FALSE),
    fn = sum(combined_ipv == FALSE & actual_combined == TRUE)
  ) %>%
  mutate(
    accuracy = (tp + tn) / total,
    precision = ifelse(tp + fp > 0, tp / (tp + fp), 0),
    recall = ifelse(tp + fn > 0, tp / (tp + fn), 0),
    f1 = ifelse(precision + recall > 0, 2 * precision * recall / (precision + recall), 0)
  )

cli::cli_alert_success("COMBINED Performance:")
cli::cli_alert_success("  Accuracy: {round(combined_metrics$accuracy, 3)}")
cli::cli_alert_success("  Precision: {round(combined_metrics$precision, 3)}")
cli::cli_alert_success("  Recall: {round(combined_metrics$recall, 3)}")
cli::cli_alert_success("  F1 Score: {round(combined_metrics$f1, 3)}")
cli::cli_alert_success("  Confusion Matrix: TP={combined_metrics$tp}, TN={combined_metrics$tn}, FP={combined_metrics$fp}, FN={combined_metrics$fn}")

# Complete test run
complete_test_run(test_conn, run_id, status = "completed")

# Identify misclassifications for analysis
cli::cli_h2("Misclassification Analysis")
misclassified <- all_results %>%
  mutate(
    le_error = predicted_le != actual_le,
    cme_error = predicted_cme != actual_cme,
    combined_error = combined_ipv != (actual_le | actual_cme)
  ) %>%
  filter(le_error | cme_error | combined_error)

if (nrow(misclassified) > 0) {
  cli::cli_alert_warning("Found {nrow(misclassified)} cases with errors")
  write.csv(misclassified, paste0("tests/test_results/misclassified_", run_id, ".csv"), row.names = FALSE)
  cli::cli_alert_info("Misclassified cases saved for analysis")
  
  # Show first few errors
  cli::cli_alert_info("Sample misclassifications:")
  for (i in 1:min(3, nrow(misclassified))) {
    error_case <- misclassified[i, ]
    cli::cli_alert_info("  Case {error_case$incident_id}: LE={error_case$predicted_le}/{error_case$actual_le}, CME={error_case$predicted_cme}/{error_case$actual_cme}")
  }
}

# Cleanup
DBI::dbDisconnect(api_conn)
DBI::dbDisconnect(test_conn)

cli::cli_alert_success("Full test completed at {Sys.time()}")
cli::cli_alert_success("Run ID: {run_id}")

# Return summary for further analysis
list(
  run_id = run_id,
  results = all_results,
  le_metrics = le_metrics,
  cme_metrics = cme_metrics,
  combined_metrics = combined_metrics,
  misclassified = misclassified
)