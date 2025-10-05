#!/usr/bin/env Rscript

#' View Experiment Details and Results
#'
#' Display comprehensive details about completed experiments from the database.
#' This is the primary tool for examining experiment results, metrics, and
#' performance statistics.
#'
#' @description
#' This script provides detailed analysis of experiment results including:
#' 1. Experiment configuration and metadata
#' 2. Performance metrics (accuracy, precision, recall, F1)
#' 3. Confusion matrix and prediction distribution
#' 4. Confidence score analysis
#' 5. Error case breakdown and examples
#' 6. Processing statistics and timing information
#' 7. Token usage and cost tracking
#'
#' @param experiment_id Experiment identifier (command line argument)
#'   - Can be full UUID (e.g., "60376368-2f1b-4b08-81a9-2f0ea815cd21")
#'   - Can be experiment name (e.g., "demo_synthetic_test")
#'   - Use "latest" for most recent experiment
#'   - Omit for list of recent experiments
#'
#' @return
#' Console output with comprehensive experiment analysis. Optional CSV export
#' of detailed results.
#'
#' @examples
#' \dontrun{
#' # View specific experiment by ID
#' Rscript scripts/view_experiment.R 60376368-2f1b-4b08-81a9-2f0ea815cd21
#'
#' # View specific experiment by name
#' Rscript scripts/view_experiment.R demo_synthetic_test
#'
#' # View most recent experiment
#' Rscript scripts/view_experiment.R latest
#'
#' # List all experiments
#' Rscript scripts/view_experiment.R
#' }
#'
#' @section Output Sections:
#' 1. **Experiment Overview**: Name, model, configuration, timestamps
#' 2. **Performance Metrics**: Accuracy, precision, recall, F1 score
#' 3. **Confusion Matrix**: TP, TN, FP, FN counts and rates
#' 4. **Prediction Distribution**: Counts and percentages by prediction type
#' 5. **Confidence Analysis**: Mean confidence by prediction accuracy
#' 6. **Error Examples**: Sample false positives and false negatives
#' 7. **Processing Statistics**: Runtime, throughput, token usage
#' 8. **Database Information**: Record counts and storage details
#'
#' @section Dependencies:
#' - R packages: DBI, RSQLite, here
#' - Functions: db_config.R, db_schema.R
#' - Database: experiments.db (must exist)
#'
#' @section Error Handling:
#' - Graceful handling of missing experiments
#' - Database connection retry logic
#' - Validation of experiment IDs and formats
#' - Clear error messages with troubleshooting hints
#'
#' @section Export Options:
#' Set environment variable EXPORT_RESULTS=1 to save detailed results to CSV:
#' ```bash
#' EXPORT_RESULTS=1 Rscript scripts/view_experiment.R <experiment_id>
#' ```
#'
#' @author Research Team
#' @date 2025-10-05
#' @version 1.0 (Research Compendium)
#'
#' @seealso
#' - \code{\link{run_experiment.R}} for running experiments
#' - \code{\link{demo_workflow.R}} for quick demonstration
#' - \code{R/experiment_queries.R} for database query functions
#'
#' @references
#' - Database schema: docs/20251005-database_schema.md
#' - Metrics definitions: docs/20251005-publication_task_list.md
#'
#' @note
#' This script only reads from the database and cannot modify experiment data.
#' It's safe to run multiple times without affecting results.
#'
#' @warning
#' Large experiments (>10,000 narratives) may take several seconds to load
#' and analyze. Consider using max_narratives parameter for quick previews.

library(DBI)
library(RSQLite)
library(here)
source(here::here("R/db_config.R"))
source(here::here("R/db_schema.R"))

args <- commandArgs(trailingOnly = TRUE)

if (length(args) == 0) {
  cat("Usage: Rscript scripts/view_experiment.R <experiment_id|latest>\n")
  cat("\nRecent experiments:\n")
  con <- get_db_connection()
  recent <- dbGetQuery(con,
    "SELECT experiment_id, experiment_name, model_name, status, start_time
     FROM experiments
     ORDER BY start_time DESC
     LIMIT 10"
  )
  dbDisconnect(con)
  print(recent)
  quit(status = 0)
}

exp_id <- args[1]
# exp_id <- "71d93444-4528-4c9e-8c3a-fa057dabdb45"

con <- get_db_connection()

# Handle "latest" keyword
if (tolower(exp_id) == "latest") {
  latest <- dbGetQuery(con,
    "SELECT experiment_id FROM experiments ORDER BY start_time DESC LIMIT 1"
  )
  if (nrow(latest) == 0) {
    cat("No experiments found in database\n")
    dbDisconnect(con)
    quit(status = 1)
  }
  exp_id <- latest$experiment_id
  cat("Using latest experiment:", exp_id, "\n\n")
}

# Query experiment
exp <- dbGetQuery(con,
  "SELECT * FROM experiments WHERE experiment_id = ?",
  params = list(exp_id)
)

if (nrow(exp) == 0) {
  cat("No experiment found with ID:", exp_id, "\n")
  cat("\nRecent experiments:\n")
  recent <- dbGetQuery(con,
    "SELECT experiment_id, experiment_name, model_name, status, start_time
     FROM experiments
     ORDER BY start_time DESC
     LIMIT 5"
  )
  print(recent)
  dbDisconnect(con)
  quit(status = 1)
}

# Display experiment details
cat("=== EXPERIMENT DETAILS ===\n\n")
cat("Experiment ID:", exp$experiment_id, "\n")
cat("Name:", exp$experiment_name, "\n")
cat("Status:", exp$status, "\n\n")

cat("=== MODEL CONFIGURATION ===\n")
cat("Model Name:", exp$model_name, "\n")
cat("Provider:", if(is.na(exp$model_provider)) "(not set)" else exp$model_provider, "\n")
cat("Temperature:", exp$temperature, "\n")
cat("API URL:", if(is.na(exp$api_url)) "(not set)" else exp$api_url, "\n\n")

cat("=== PROMPTS ===\n")
cat("System Prompt:\n")
cat(exp$system_prompt, "\n\n")
cat("User Template:\n")
cat(exp$user_template, "\n\n")
cat("Prompt Version:", if(is.na(exp$prompt_version)) "(not set)" else exp$prompt_version, "\n")
cat("Prompt Author:", if(is.na(exp$prompt_author)) "(not set)" else exp$prompt_author, "\n\n")

cat("=== DATA & PROCESSING ===\n")
cat("Data File:", if(is.na(exp$data_file)) "(not set)" else exp$data_file, "\n")
cat("Total Narratives:", if(is.na(exp$n_narratives_total)) 0 else exp$n_narratives_total, "\n")
cat("Processed:", if(is.na(exp$n_narratives_processed)) 0 else exp$n_narratives_processed, "\n")
cat("Skipped:", if(is.na(exp$n_narratives_skipped)) 0 else exp$n_narratives_skipped, "\n\n")

cat("=== TIMING ===\n")
cat("Start Time:", exp$start_time, "\n")
cat("End Time:", if(is.na(exp$end_time)) "(not completed)" else exp$end_time, "\n")
cat("Total Runtime:", if(is.na(exp$total_runtime_sec)) "N/A" else paste(round(exp$total_runtime_sec, 2), "seconds"), "\n")
cat("Avg Time/Narrative:", if(is.na(exp$avg_time_per_narrative_sec)) "N/A" else paste(round(exp$avg_time_per_narrative_sec, 2), "seconds"), "\n\n")

cat("=== RESULTS ===\n")
cat("Positive Detected:", if(is.na(exp$n_positive_detected)) 0 else exp$n_positive_detected, "\n")
cat("Negative Detected:", if(is.na(exp$n_negative_detected)) 0 else exp$n_negative_detected, "\n")
cat("Positive Manual:", if(is.na(exp$n_positive_manual)) 0 else exp$n_positive_manual, "\n")
cat("Negative Manual:", if(is.na(exp$n_negative_manual)) 0 else exp$n_negative_manual, "\n\n")

cat("=== METRICS ===\n")
cat("Accuracy:", if(is.na(exp$accuracy)) "N/A" else sprintf("%.2f%%", exp$accuracy * 100), "\n")
cat("Precision:", if(is.na(exp$precision_ipv)) "N/A" else sprintf("%.2f%%", exp$precision_ipv * 100), "\n")
cat("Recall:", if(is.na(exp$recall_ipv)) "N/A" else sprintf("%.2f%%", exp$recall_ipv * 100), "\n")
cat("F1 Score:", if(is.na(exp$f1_ipv)) "N/A" else sprintf("%.3f", exp$f1_ipv), "\n\n")

cat("=== CONFUSION MATRIX ===\n")
cat("True Positives:", if(is.na(exp$n_true_positive)) 0 else exp$n_true_positive, "\n")
cat("True Negatives:", if(is.na(exp$n_true_negative)) 0 else exp$n_true_negative, "\n")
cat("False Positives:", if(is.na(exp$n_false_positive)) 0 else exp$n_false_positive, "\n")
cat("False Negatives:", if(is.na(exp$n_false_negative)) 0 else exp$n_false_negative, "\n\n")

cat("=== OUTPUT FILES ===\n")
cat("CSV File:", if(is.na(exp$csv_file)) "(not saved)" else exp$csv_file, "\n")
cat("JSON File:", if(is.na(exp$json_file)) "(not saved)" else exp$json_file, "\n")
cat("Log Directory:", if(is.na(exp$log_dir)) "(not saved)" else exp$log_dir, "\n\n")

cat("=== SYSTEM INFO ===\n")
cat("R Version:", if(is.na(exp$r_version)) "(not recorded)" else exp$r_version, "\n")
cat("OS:", if(is.na(exp$os_info)) "(not recorded)" else exp$os_info, "\n")
cat("Hostname:", if(is.na(exp$hostname)) "(not recorded)" else exp$hostname, "\n")
cat("Seed:", if(is.na(exp$run_seed)) "(not set)" else exp$run_seed, "\n\n")

if (!is.na(exp$notes) && nchar(trimws(exp$notes)) > 0) {
  cat("=== NOTES ===\n")
  cat(exp$notes, "\n\n")
}

dbDisconnect(con)
