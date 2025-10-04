#!/usr/bin/env Rscript

#' Run Experiment from Configuration File
#'
#' Main orchestrator for running experiments with database tracking
#'
#' Usage:
#'   Rscript scripts/run_experiment.R configs/experiments/exp_001.yaml

library(here)
library(DBI)
library(RSQLite)
library(tictoc)

cat("\n")
cat("================================================================================\n")
cat("                    IPV Detection Experiment Runner\n")
cat("================================================================================\n\n")

# Source all required functions
source(here("R", "db_config.R"))      # FIRST: Centralized config
source(here("R", "db_schema.R"))
source(here("R", "data_loader.R"))
source(here("R", "config_loader.R"))
source(here("R", "experiment_logger.R"))
source(here("R", "experiment_queries.R"))
source(here("R", "run_benchmark_core.R"))
source(here("R", "call_llm.R"))
source(here("R", "repair_json.R"))
source(here("R", "parse_llm_result.R"))
source(here("R", "build_prompt.R"))

# Parse command line arguments
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  cat("ERROR: No configuration file specified\n\n")
  cat("Usage:\n")
  cat("  Rscript scripts/run_experiment.R <config.yaml>\n\n")
  cat("Example:\n")
  cat("  Rscript scripts/run_experiment.R configs/experiments/exp_001_test_gpt_oss.yaml\n\n")
  quit(save = "no", status = 1)
}

config_path <- args[1]
cat("Configuration file:", config_path, "\n\n")

# Load and validate configuration
cat("Step 1: Loading configuration...\n")
tryCatch({
  config <- load_experiment_config(config_path)
  validate_config(config)
  cat("✓ Configuration validated\n")
  cat("  Experiment:", config$experiment$name, "\n")
  cat("  Model:", config$model$name, "\n")
  cat("  Temperature:", config$model$temperature, "\n")
  cat("  API URL:", config$model$api_url, "\n")
  if (!is.null(config$run$max_narratives)) {
    cat("  Max narratives:", config$run$max_narratives, "(testing mode)\n")
  }
  cat("\n")
}, error = function(e) {
  cat("✗ Configuration error:", conditionMessage(e), "\n\n")
  quit(save = "no", status = 1)
})

# Connect to database
cat("Step 2: Connecting to database...\n")
db_path <- get_experiments_db_path()  # Uses centralized config

if (!file.exists(db_path)) {
  cat("  Database not found. Initializing...\n")
  conn <- init_experiment_db()  # Will use centralized config
} else {
  conn <- get_db_connection()  # Will use centralized config
}
cat("✓ Connected to database:", db_path, "\n\n")

# Load source data if needed
cat("Step 3: Loading source data...\n")
data_source <- config$data$file

if (!check_data_loaded(conn, data_source)) {
  cat("  Loading data from Excel...\n")
  n_loaded <- load_source_data(conn, data_source)
  cat("✓ Loaded", n_loaded, "narratives\n\n")
} else {
  n_existing <- DBI::dbGetQuery(conn,
    "SELECT COUNT(*) as n FROM source_narratives WHERE data_source = ?",
    params = list(data_source))$n
  cat("✓ Source data already loaded (", n_existing, "narratives)\n\n")
}

# Get narratives for this experiment
cat("Step 4: Retrieving narratives...\n")
narratives <- get_source_narratives(
  conn,
  data_source = data_source,
  max_narratives = config$run$max_narratives
)
cat("✓ Retrieved", nrow(narratives), "narratives\n")
cat("  CME:", sum(narratives$narrative_type == "cme"), "\n")
cat("  LE:", sum(narratives$narrative_type == "le"), "\n")
cat("  Positive labels:", sum(narratives$manual_flag_ind, na.rm = TRUE), "\n\n")

# Start experiment
cat("Step 5: Creating experiment record...\n")
experiment_id <- start_experiment(conn, config)
cat("✓ Experiment created\n")
cat("  Experiment ID:", experiment_id, "\n\n")

# Initialize logger
cat("Step 6: Initializing logger...\n")
logger <- init_experiment_logger(experiment_id)
cat("✓ Logger initialized\n")
cat("  Log directory:", logger$log_dir, "\n\n")

logger$info("========================================")
logger$info(paste("Experiment:", config$experiment$name))
logger$info(paste("Model:", config$model$name))
logger$info(paste("Temperature:", config$model$temperature))
logger$info(paste("Narratives:", nrow(narratives)))
logger$info("========================================")

# Run benchmark
cat("Step 7: Running benchmark...\n")
cat("  This may take several minutes depending on number of narratives...\n\n")

tryCatch({
  results <- run_benchmark_core(config, conn, experiment_id, narratives, logger)
  
  cat("\nStep 8: Computing metrics...\n")
  # Metrics are computed by finalize_experiment from database
  
  # Optionally save CSV/JSON files
  csv_file <- NULL
  json_file <- NULL
  
  if (config$run$save_csv_json) {
    timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
    model_clean <- gsub("/", "_", config$model$name)
    csv_file <- here("benchmark_results", paste0("experiment_", experiment_id, "_", timestamp, ".csv"))
    json_file <- here("benchmark_results", paste0("experiment_", experiment_id, "_", timestamp, ".json"))
    
    # Prepare results for CSV (flatten lists)
    csv_results <- results
    if ("indicators" %in% names(csv_results) && is.list(csv_results$indicators)) {
      csv_results$indicators <- sapply(csv_results$indicators, function(x) {
        if (is.null(x) || length(x) == 0) "" else paste(x, collapse = "; ")
      })
    }
    
    write.csv(csv_results, csv_file, row.names = FALSE)
    jsonlite::write_json(results, json_file, pretty = TRUE, auto_unbox = TRUE)
    
    cat("✓ Results saved:\n")
    cat("  CSV:", csv_file, "\n")
    cat("  JSON:", json_file, "\n\n")
    
    logger$info(paste("Saved CSV:", csv_file))
    logger$info(paste("Saved JSON:", json_file))
  }
  
  # Finalize experiment
  finalize_experiment(conn, experiment_id, csv_file, json_file)
  
  cat("Step 9: Experiment finalized\n\n")
  logger$info("Experiment finalized successfully")
  
  # Display results
  cat("================================================================================\n")
  cat("                        Experiment Complete!\n")
  cat("================================================================================\n\n")
  
  exp_info <- DBI::dbGetQuery(conn,
    "SELECT experiment_name, model_name, temperature,
            n_narratives_processed,
            accuracy, precision_ipv, recall_ipv, f1_ipv,
            n_true_positive, n_false_positive, n_false_negative, n_true_negative,
            total_runtime_sec
     FROM experiments WHERE experiment_id = ?",
    params = list(experiment_id))
  
  cat("Experiment:", exp_info$experiment_name, "\n")
  cat("Model:", exp_info$model_name, "(temperature =", exp_info$temperature, ")\n")
  cat("Narratives processed:", exp_info$n_narratives_processed, "\n\n")
  
  cat("Performance Metrics:\n")
  cat("  Accuracy:   ", sprintf("%.2f%%", exp_info$accuracy * 100), "\n")
  cat("  Precision:  ", sprintf("%.2f%%", exp_info$precision_ipv * 100), "\n")
  cat("  Recall:     ", sprintf("%.2f%%", exp_info$recall_ipv * 100), "\n")
  cat("  F1 Score:   ", sprintf("%.2f", exp_info$f1_ipv), "\n\n")
  
  cat("Confusion Matrix:\n")
  cat("  True Positives:  ", exp_info$n_true_positive, "\n")
  cat("  False Positives: ", exp_info$n_false_positive, "\n")
  cat("  True Negatives:  ", exp_info$n_true_negative, "\n")
  cat("  False Negatives: ", exp_info$n_false_negative, "\n\n")
  
  cat("Runtime:", sprintf("%.1f", exp_info$total_runtime_sec), "seconds\n")
  cat("Average per narrative:", sprintf("%.2f", exp_info$total_runtime_sec / exp_info$n_narratives_processed), "seconds\n\n")
  
  cat("Experiment ID:", experiment_id, "\n")
  cat("Log directory:", logger$log_dir, "\n")
  if (!is.null(csv_file)) {
    cat("Results saved to:", csv_file, "\n")
  }
  
  cat("\n================================================================================\n\n")
  
}, error = function(e) {
  cat("\n✗ ERROR during experiment:\n")
  cat("  ", conditionMessage(e), "\n\n")
  
  logger$error("Experiment failed", e)
  mark_experiment_failed(conn, experiment_id, conditionMessage(e))
  
  cat("Experiment marked as failed in database\n")
  cat("Check error log:", file.path(logger$log_dir, "errors.log"), "\n\n")
  
  DBI::dbDisconnect(conn)
  quit(save = "no", status = 1)
})

# Cleanup
DBI::dbDisconnect(conn)
cat("✓ Database connection closed\n\n")
