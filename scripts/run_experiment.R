#!/usr/bin/env Rscript

#' Run Experiment from Configuration File
#'
#' Main orchestrator for running experiments with database tracking. This is the
#' primary entry point for conducting IPV detection experiments using LLMs.
#'
#' @description
#' This script orchestrates the complete experiment workflow:
#' 1. Loads and validates YAML configuration files
#' 2. Initializes database schema and connections
#' 3. Loads source data from Excel/CSV files
#' 4. Registers experiments with unique identifiers
#' 5. Processes narratives using specified LLM models and prompts
#' 6. Stores results with comprehensive logging and metrics
#' 7. Calculates performance statistics (accuracy, precision, recall, F1)
#' 8. Exports results in multiple formats (CSV, JSON)
#'
#' @param config_path Path to YAML configuration file (command line argument)
#'
#' @return
#' Invisible experiment ID string. Results are stored in database and
#' optionally exported to CSV/JSON files.
#'
#' @examples
#' \dontrun{
#' # Run single experiment
#' Rscript scripts/run_experiment.R configs/experiments/exp_037_baseline_v4_t00_medium.yaml
#'
#' # Run test experiment
#' Rscript scripts/run_experiment.R configs/experiments/exp_001_test_gpt_oss.yaml
#' }
#'
#' @section Dependencies:
#' - R packages: DBI, RSQLite, yaml, httr2, jsonlite, tictoc, here
#' - Functions sourced from: R/ directory (modular architecture)
#' - Database: SQLite (automatically created if needed)
#' - External: LLM API endpoint (configured in YAML)
#'
#' @section Database Schema:
#' Creates three tables if they don't exist:
#' - experiments: experiment metadata and metrics
#' - narrative_results: per-narrative predictions and confidence scores
#' - source_narratives: original narrative data for reproducibility
#'
#' @section Configuration:
#' YAML files must specify:
#' - experiment: name, author, notes
#' - model: name, provider, api_url, temperature
#' - prompt: version, system_prompt, user_template
#' - data: source file path
#' - run: seed, max_narratives, save options
#'
#' @section Error Handling:
#' - Configuration validation before processing
#' - Database connection retry logic
#' - Graceful degradation for optional features
#' - Comprehensive logging of errors and warnings
#' - Automatic experiment rollback on critical failures
#'
#' @section Performance:
#' - Batch processing for memory efficiency
#' - Progress reporting with timestamps
#' - Token usage tracking for cost management
#' - Configurable parallel processing (future enhancement)
#'
#' @author Research Team
#' @date 2025-10-05
#' @version 1.0 (Research Compendium)
#'
#' @seealso
#' - \code{\link{view_experiment.R}} for results visualization
#' - \code{\link{demo_workflow.R}} for quick demonstration
#' - \code{scripts/README.md} for complete workflow documentation
#'
#' @references
#' Research compendium methodology: https://research-compendium.github.io/
#' YAML configuration specification: See configs/experiments/README.md
#'
#' @warning
#' This script processes potentially sensitive narrative data. Ensure appropriate
#' IRB approval and data handling procedures are in place for production use.
#'
#' @note
#' First run automatically initializes the database schema. Subsequent runs
#' append new experiments while preserving historical data.

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

# Check for resume mode
resume_mode <- Sys.getenv("RESUME", "0") == "1"
resume_experiment_id <- Sys.getenv("EXPERIMENT_ID", "")
retry_errors_only <- Sys.getenv("RETRY_ERRORS_ONLY", "0") == "1"

if (resume_mode) {
  cat("========================================\n")
  cat("RESUME MODE ENABLED\n")
  cat("========================================\n")
  cat("Experiment ID:", resume_experiment_id, "\n")
  if (retry_errors_only) {
    cat("Mode: Retry errors only\n")
  } else {
    cat("Mode: Process missing narratives\n")
  }
  cat("\n")
  
  if (resume_experiment_id == "") {
    cat("ERROR: RESUME=1 requires EXPERIMENT_ID to be set\n\n")
    cat("Usage:\n")
    cat("  RESUME=1 EXPERIMENT_ID=<uuid> Rscript scripts/run_experiment.R <config.yaml>\n\n")
    quit(save = "no", status = 1)
  }
}

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

# Load source data if needed (or verify checksum on resume)
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
  cat("✓ Source data already loaded (", n_existing, "narratives)\n")
  
  # Verify checksum if resuming
  if (resume_mode) {
    cat("  Verifying data file checksum...\n")
    checksum_ok <- verify_source_checksum(conn, data_source)
    if (is.na(checksum_ok)) {
      warning("No checksum stored for source data - cannot verify integrity")
    } else if (!checksum_ok) {
      cat("✗ ERROR: Data file checksum mismatch!\n")
      cat("  The source file has changed since the experiment started.\n")
      cat("  Cannot safely resume with modified data.\n\n")
      DBI::dbDisconnect(conn)
      quit(save = "no", status = 1)
    } else {
      cat("  ✓ Checksum verified: data file unchanged\n")
    }
  }
  cat("\n")
}

# RESUME PATH: Load existing experiment or create new one
if (resume_mode) {
  cat("Step 4: Loading existing experiment for resume...\n")
  
  # Validate experiment exists and can be resumed
  exp_info <- DBI::dbGetQuery(conn,
    "SELECT experiment_id, experiment_name, status, data_file, 
            n_narratives_total, n_narratives_completed, model_name, temperature,
            system_prompt, user_template
     FROM experiments 
     WHERE experiment_id = ?",
    params = list(resume_experiment_id)
  )
  
  if (nrow(exp_info) == 0) {
    cat("✗ ERROR: Experiment not found:", resume_experiment_id, "\n\n")
    DBI::dbDisconnect(conn)
    quit(save = "no", status = 1)
  }
  
  # Check status
  if (exp_info$status == "completed") {
    cat("✗ ERROR: Cannot resume completed experiment\n")
    cat("  Experiment", resume_experiment_id, "has status: completed\n\n")
    DBI::dbDisconnect(conn)
    quit(save = "no", status = 1)
  }
  
  cat("✓ Found experiment:", exp_info$experiment_name, "\n")
  cat("  Status:", exp_info$status, "\n")
  cat("  Model:", exp_info$model_name, "(T=", exp_info$temperature, ")\n")
  
  if (!is.na(exp_info$n_narratives_completed) && exp_info$n_narratives_completed > 0) {
    pct_complete <- (exp_info$n_narratives_completed / exp_info$n_narratives_total) * 100
    cat("  Progress:", exp_info$n_narratives_completed, "/", exp_info$n_narratives_total,
        sprintf("(%.1f%%)", pct_complete), "\n")
  }
  cat("\n")
  
  # Warn if YAML config differs from DB (DB is authoritative)
  if (config$model$name != exp_info$model_name) {
    warning("YAML model (", config$model$name, ") differs from experiment model (", 
            exp_info$model_name, "). Using DB config.")
  }
  if (config$model$temperature != exp_info$temperature) {
    warning("YAML temperature (", config$model$temperature, ") differs from experiment (", 
            exp_info$temperature, "). Using DB config.")
  }
  
  # Acquire resume lock
  cat("Step 5: Acquiring resume lock...\n")
  acquire_resume_lock(resume_experiment_id)
  cat("✓ Lock acquired\n\n")
  
  # Use existing experiment ID
  experiment_id <- resume_experiment_id
  
  # Determine remaining work
  cat("Step 6: Building remaining work set...\n")
  
  if (retry_errors_only) {
    # Get narratives that errored
    remaining_query <- "
      SELECT sn.* 
      FROM source_narratives sn
      INNER JOIN narrative_results nr ON 
        sn.incident_id = nr.incident_id AND 
        sn.narrative_type = nr.narrative_type
      WHERE nr.experiment_id = ? 
        AND nr.error_occurred = 1
        AND sn.data_source = ?
    "
    narratives <- DBI::dbGetQuery(conn, remaining_query, 
                                   params = list(experiment_id, data_source))
    cat("✓ Found", nrow(narratives), "narratives with errors to retry\n\n")
    
  } else {
    # Get all narratives not yet processed
    remaining_query <- "
      SELECT sn.* 
      FROM source_narratives sn
      LEFT JOIN narrative_results nr ON 
        sn.incident_id = nr.incident_id AND 
        sn.narrative_type = nr.narrative_type AND
        nr.experiment_id = ?
      WHERE sn.data_source = ?
        AND nr.result_id IS NULL
    "
    narratives <- DBI::dbGetQuery(conn, remaining_query, 
                                   params = list(experiment_id, data_source))
    cat("✓ Found", nrow(narratives), "narratives not yet processed\n\n")
  }
  
  # Check if already complete
  if (nrow(narratives) == 0) {
    cat("========================================\n")
    cat("No remaining work!\n")
    cat("========================================\n\n")
    cat("All narratives have been processed for this experiment.\n")
    cat("Use RETRY_ERRORS_ONLY=1 if you want to reprocess errors.\n\n")
    
    release_resume_lock(experiment_id)
    DBI::dbDisconnect(conn)
    quit(save = "no", status = 0)
  }
  
  # Convert to tibble
  narratives <- tibble::as_tibble(narratives)
  
  # Initialize logger (use existing log directory)
  cat("Step 7: Initializing logger...\n")
  logger <- init_experiment_logger(experiment_id)
  cat("✓ Logger initialized\n")
  cat("  Log directory:", logger$log_dir, "\n\n")
  
  logger$info("========================================")
  logger$info("RESUME MODE")
  logger$info(paste("Experiment:", exp_info$experiment_name))
  logger$info(paste("Remaining narratives:", nrow(narratives)))
  if (retry_errors_only) {
    logger$info("Mode: Retry errors only")
  }
  logger$info("========================================")
  
} else {
  # NEW EXPERIMENT PATH
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
}

# Common processing path for both new and resumed experiments

# Run benchmark
step_num <- if (resume_mode) 8 else 7
cat("Step", step_num, ": Running benchmark...\n")
if (resume_mode) {
  cat("  Resuming from", nrow(narratives), "remaining narratives...\n\n")
} else {
  cat("  This may take several minutes depending on number of narratives...\n\n")
}

tryCatch({
  results <- run_benchmark_core(config, conn, experiment_id, narratives, logger)

  step_num <- step_num + 1
  cat("\nStep", step_num, ": Computing metrics...\n")
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

  step_num <- step_num + 1
  cat("Step", step_num, ": Experiment finalized\n\n")
  logger$info("Experiment finalized successfully")
  
  # Release resume lock if in resume mode
  if (resume_mode) {
    release_resume_lock(experiment_id)
  }

  # Display results
  cat("================================================================================\n")
  if (resume_mode) {
    cat("                        Resume Complete!\n")
  } else {
    cat("                        Experiment Complete!\n")
  }
  cat("================================================================================\n\n")

  exp_info <- DBI::dbGetQuery(conn,
    "SELECT experiment_name, model_name, temperature,
            n_narratives_processed,
            accuracy, precision_ipv, recall_ipv, f1_ipv,
            n_true_positive, n_false_positive, n_false_negative, n_true_negative,
            total_runtime_sec
     FROM experiments WHERE experiment_id = ?",
    params = list(experiment_id))
  token_stats <- DBI::dbGetQuery(conn,
    "SELECT
        MAX(tokens_used) AS max_tokens,
        AVG(tokens_used) AS avg_tokens
     FROM narrative_results
     WHERE experiment_id = ? AND tokens_used IS NOT NULL AND error_occurred = 0",
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
  if (!is.na(token_stats$max_tokens)) {
    cat("Token Usage:\n")
    cat("  Max tokens (single narrative): ", token_stats$max_tokens, "\n", sep = "")
    if (!is.na(token_stats$avg_tokens)) {
      cat("  Avg tokens (processed narratives): ", sprintf("%.0f", token_stats$avg_tokens), "\n", sep = "")
    }
    cat("\n")
  }

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
  
  # Release resume lock if in resume mode
  if (resume_mode) {
    release_resume_lock(experiment_id)
  }

  DBI::dbDisconnect(conn)
  quit(save = "no", status = 1)
})

# Cleanup
DBI::dbDisconnect(conn)
cat("✓ Database connection closed\n\n")
