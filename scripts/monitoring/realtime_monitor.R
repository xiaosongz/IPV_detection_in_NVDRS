#!/usr/bin/env Rscript

# Real-time monitoring of IPV detection progress
library(cli)

monitor_live <- function(interval = 30) {
  intermediate_file <- "tests/test_results/all_289_intermediate.csv"
  
  repeat {
    cli::cli_h1("IPV Detection Live Monitor - {Sys.time()}")
    
    if (file.exists(intermediate_file)) {
      results <- read.csv(intermediate_file)
      n_processed <- nrow(results)
      
      # Basic stats
      cli::cli_alert_success("Processed: {n_processed}/289 cases ({round(n_processed/289*100, 1)}%)")
      
      # IPV detection stats
      ipv_count <- sum(results$combined_ipv, na.rm = TRUE)
      cli::cli_alert_info("IPV detected: {ipv_count} cases ({round(ipv_count/n_processed*100, 1)}%)")
      
      # Accuracy if ground truth available
      results$actual_combined <- results$actual_le | results$actual_cme
      valid <- !is.na(results$combined_ipv) & !is.na(results$actual_combined)
      
      if (sum(valid) > 0) {
        tp <- sum(results$combined_ipv[valid] & results$actual_combined[valid])
        tn <- sum(!results$combined_ipv[valid] & !results$actual_combined[valid])
        fp <- sum(results$combined_ipv[valid] & !results$actual_combined[valid])
        fn <- sum(!results$combined_ipv[valid] & results$actual_combined[valid])
        
        accuracy <- (tp + tn) / sum(valid)
        precision <- if(tp + fp > 0) tp / (tp + fp) else 0
        recall <- if(tp + fn > 0) tp / (tp + fn) else 0
        f1 <- if(precision + recall > 0) 2 * precision * recall / (precision + recall) else 0
        
        cli::cli_h2("Performance Metrics")
        cli::cli_alert_success("Accuracy: {round(accuracy * 100, 1)}%")
        cli::cli_alert_info("Precision: {round(precision * 100, 1)}%")
        cli::cli_alert_info("Recall: {round(recall * 100, 1)}%")
        cli::cli_alert_info("F1 Score: {round(f1, 3)}")
        
        # Confusion matrix
        cli::cli_h3("Confusion Matrix")
        cat(sprintf("  TP: %d  FP: %d\n  FN: %d  TN: %d\n", tp, fp, fn, tn))
      }
      
      # Progress bar
      cli::cli_progress_bar(
        format = "Progress: {cli::pb_bar} {cli::pb_percent}",
        total = 289,
        current = n_processed
      )
      
      # Check if complete
      if (n_processed >= 289) {
        cli::cli_alert_success("Processing COMPLETE!")
        break
      }
      
      # Estimate remaining time
      if (n_processed > 10) {
        # Assume ~6 seconds per case
        remaining_cases <- 289 - n_processed
        est_minutes <- remaining_cases * 6 / 60
        cli::cli_alert_info("Estimated time remaining: {round(est_minutes, 1)} minutes")
      }
      
    } else {
      cli::cli_alert_warning("No intermediate results found yet")
    }
    
    cli::cli_rule()
    
    # Wait for next update
    Sys.sleep(interval)
  }
}

# Run live monitoring
monitor_live(30)