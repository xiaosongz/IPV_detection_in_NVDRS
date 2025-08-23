#!/usr/bin/env Rscript

# Monitor progress of the 289 cases processing
library(cli)

cli::cli_h1("Monitoring IPV Detection Progress")

# Check for intermediate results file
intermediate_file <- "tests/test_results/all_289_intermediate.csv"

if (file.exists(intermediate_file)) {
  results <- read.csv(intermediate_file)
  cli::cli_alert_success("Found intermediate results: {nrow(results)} cases processed")
  
  # Quick stats
  ipv_count <- sum(results$combined_ipv, na.rm = TRUE)
  cli::cli_alert_info("IPV detected in {ipv_count} cases so far")
  cli::cli_alert_info("Detection rate: {round(ipv_count/nrow(results) * 100, 1)}%")
  
  # Check accuracy if ground truth available
  results$actual_combined <- results$actual_le | results$actual_cme
  valid <- !is.na(results$combined_ipv) & !is.na(results$actual_combined)
  if (sum(valid) > 0) {
    accuracy <- mean(results$combined_ipv[valid] == results$actual_combined[valid])
    cli::cli_alert_info("Current accuracy: {round(accuracy * 100, 1)}%")
  }
  
  cli::cli_alert_info("Progress: {round(nrow(results)/289 * 100, 1)}% complete")
  cli::cli_alert_info("Estimated remaining: {round((289 - nrow(results)) * 6 / 60, 1)} minutes")
} else {
  cli::cli_alert_warning("No intermediate results found yet")
  cli::cli_alert_info("Processing should save results every 50 cases")
}

# Estimate completion time
start_time <- as.POSIXct("2025-08-23 13:23:07", tz = "America/New_York")
estimated_duration <- 29 # minutes
estimated_completion <- start_time + (estimated_duration * 60)
cli::cli_alert_info("Estimated completion: {format(estimated_completion, '%H:%M:%S')}")