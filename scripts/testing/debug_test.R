#!/usr/bin/env Rscript

# Debug test script
library(nvdrsipvdetector)
library(DBI)
library(cli)

# Load configuration
config <- load_config()

# Test single narrative
test_narrative <- "LE responded to a report of an unresponsive female. The V was a 38 year old white female. She had domestic issues with another previous boyfriend."

cli::cli_alert_info("Testing IPV detection...")

# Test detection
result <- tryCatch({
  detect_ipv(
    narrative = test_narrative,
    type = "LE",
    config = config,
    conn = NULL,  # No database logging for now
    log_to_db = FALSE
  )
}, error = function(e) {
  cli::cli_alert_danger("Error: {e$message}")
  list(success = FALSE, error = e$message)
})

# Display result
if (!is.null(result)) {
  cli::cli_alert_info("Success: {result$success}")
  if (isTRUE(result$success)) {
    cli::cli_alert_success("IPV Detected: {result$ipv_detected}")
    cli::cli_alert_info("Confidence: {result$confidence}")
    cli::cli_alert_info("Indicators: {paste(result$indicators, collapse = ', ')}")
    cli::cli_alert_info("Rationale: {result$rationale}")
  } else {
    cli::cli_alert_danger("Error: {result$error}")
  }
}

cli::cli_alert_success("Test completed!")