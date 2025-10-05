#!/usr/bin/env Rscript
#' View Experiment Details
#' 
#' Display comprehensive details about an experiment from the database
#' 
#' Usage:
#'   Rscript scripts/view_experiment.R <experiment_id>
#'   Rscript scripts/view_experiment.R latest
#'   
#' Examples:
#'   Rscript scripts/view_experiment.R 60376368-2f1b-4b08-81a9-2f0ea815cd21
#'   Rscript scripts/view_experiment.R latest

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
