#' Start New Experiment
#'
#' Creates new experiment record in database and returns experiment ID
#'
#' @param conn Database connection
#' @param config Experiment configuration list
#' @return experiment_id (UUID)
#' @export
start_experiment <- function(conn, config) {
  if (!requireNamespace("uuid", quietly = TRUE)) {
    stop("Package 'uuid' is required but not installed.")
  }
  
  experiment_id <- uuid::UUIDgenerate()
  
  # Get API URL (handle both cases)
  api_url <- if (!is.null(config$model$api_url)) {
    config$model$api_url
  } else {
    Sys.getenv("LLM_API_URL", "http://localhost:1234/v1/chat/completions")
  }
  
  DBI::dbExecute(conn,
    "INSERT INTO experiments (
      experiment_id, experiment_name, status,
      model_name, model_provider, temperature,
      system_prompt, user_template, prompt_version, prompt_author,
      data_file, start_time, created_at,
      r_version, os_info, hostname, api_url, run_seed
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    params = list(
      experiment_id,
      config$experiment$name,
      "running",
      config$model$name,
      config$model$provider,
      config$model$temperature,
      config$prompt$system_prompt,
      config$prompt$user_template,
      config$prompt$version,
      config$experiment$author,
      config$data$file,
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      R.version.string,
      Sys.info()["sysname"],
      Sys.info()["nodename"],
      api_url,
      config$run$seed
    )
  )
  
  # Update with log directory path
  log_dir <- file.path("logs", "experiments", experiment_id)
  DBI::dbExecute(conn,
    "UPDATE experiments SET log_dir = ? WHERE experiment_id = ?",
    params = list(log_dir, experiment_id))
  
  return(experiment_id)
}

#' Log Single Narrative Result
#'
#' Inserts narrative-level result into database
#'
#' @param conn Database connection
#' @param experiment_id Experiment ID
#' @param result Parsed LLM result (from parse_llm_result)
#' @export
log_narrative_result <- function(conn, experiment_id, result) {
  # Convert indicators list to JSON string
  indicators_json <- if (!is.null(result$indicators) && length(result$indicators) > 0) {
    jsonlite::toJSON(result$indicators, auto_unbox = TRUE)
  } else {
    "[]"
  }
  
  # Compute classification flags
  is_tp <- is_tn <- is_fp <- is_fn <- as.integer(NA)
  
  if (!is.na(result$detected) && !is.na(result$manual_flag_ind)) {
    detected_bool <- as.logical(result$detected)
    manual_bool <- as.logical(result$manual_flag_ind)
    
    is_tp <- as.integer(detected_bool && manual_bool)
    is_tn <- as.integer(!detected_bool && !manual_bool)
    is_fp <- as.integer(detected_bool && !manual_bool)
    is_fn <- as.integer(!detected_bool && manual_bool)
  }
  
  prompt_tokens <- if (is.null(result$prompt_tokens) || is.na(result$prompt_tokens)) {
    NA_integer_
  } else {
    as.integer(result$prompt_tokens)
  }
  completion_tokens <- if (is.null(result$completion_tokens) || is.na(result$completion_tokens)) {
    NA_integer_
  } else {
    as.integer(result$completion_tokens)
  }
  total_tokens <- if (is.null(result$tokens_used) || is.na(result$tokens_used)) {
    NA_integer_
  } else {
    as.integer(result$tokens_used)
  }
  
  incident_id_value <- if (is.null(result$incident_id) || is.na(result$incident_id)) {
    NA_character_
  } else {
    as.character(result$incident_id)
  }
  
  DBI::dbExecute(conn,
    "INSERT INTO narrative_results (
      experiment_id, incident_id, narrative_type, row_num,
      narrative_text, manual_flag_ind, manual_flag,
      detected, confidence, indicators, rationale, reasoning_steps,
      raw_response, response_sec, processed_at,
      error_occurred, error_message,
      prompt_tokens, completion_tokens, tokens_used,
      is_true_positive, is_true_negative, is_false_positive, is_false_negative
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    params = list(
      experiment_id,
      incident_id_value,
      result$narrative_type,
      result$row_num,
      result$narrative_text,
      as.integer(result$manual_flag_ind),
      as.integer(result$manual_flag),
      as.integer(result$detected),
      result$confidence,
      as.character(indicators_json),
      result$rationale,
      result$reasoning,
      result$raw_response,
      result$response_sec,
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      as.integer(result$parse_error),
      result$error_message,
      prompt_tokens,
      completion_tokens,
      total_tokens,
      is_tp, is_tn, is_fp, is_fn
    )
  )
}

#' Finalize Experiment
#'
#' Updates experiment with final metrics and status
#'
#' @param conn Database connection
#' @param experiment_id Experiment ID
#' @param csv_file Optional path to CSV output file
#' @param json_file Optional path to JSON output file
#' @export
finalize_experiment <- function(conn, experiment_id, csv_file = NULL, json_file = NULL) {
  end_time <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  
  # Get start time to compute total runtime
  start_info <- DBI::dbGetQuery(conn,
    "SELECT start_time, n_narratives_total FROM experiments WHERE experiment_id = ?",
    params = list(experiment_id))
  
  total_runtime_sec <- as.numeric(difftime(
    as.POSIXct(end_time, format = "%Y-%m-%d %H:%M:%S"),
    as.POSIXct(start_info$start_time, format = "%Y-%m-%d %H:%M:%S"),
    units = "secs"
  ))
  
  avg_time_per_narrative <- if (!is.null(start_info$n_narratives_total) && start_info$n_narratives_total > 0) {
    total_runtime_sec / start_info$n_narratives_total
  } else {
    NA_real_
  }
  
  # Compute enhanced metrics from database results
  enhanced_metrics <- compute_enhanced_metrics(conn, experiment_id)
  
  DBI::dbExecute(conn,
    "UPDATE experiments SET
      status = 'completed',
      end_time = ?,
      total_runtime_sec = ?,
      avg_time_per_narrative_sec = ?,
      n_narratives_processed = ?,
      n_positive_detected = ?,
      n_negative_detected = ?,
      n_positive_manual = ?,
      n_negative_manual = ?,
      accuracy = ?,
      precision_ipv = ?,
      recall_ipv = ?,
      f1_ipv = ?,
      n_false_positive = ?,
      n_false_negative = ?,
      n_true_positive = ?,
      n_true_negative = ?,
      pct_overlap_with_manual = ?,
      csv_file = ?,
      json_file = ?
    WHERE experiment_id = ?",
    params = list(
      end_time,
      total_runtime_sec,
      avg_time_per_narrative,
      enhanced_metrics$n_narratives_processed,
      enhanced_metrics$n_positive_detected,
      enhanced_metrics$n_negative_detected,
      enhanced_metrics$n_positive_manual,
      enhanced_metrics$n_negative_manual,
      enhanced_metrics$accuracy,
      enhanced_metrics$precision_ipv,
      enhanced_metrics$recall_ipv,
      enhanced_metrics$f1_ipv,
      enhanced_metrics$n_false_positive,
      enhanced_metrics$n_false_negative,
      enhanced_metrics$n_true_positive,
      enhanced_metrics$n_true_negative,
      enhanced_metrics$pct_overlap_with_manual,
      csv_file,
      json_file,
      experiment_id
    )
  )
}

#' Compute Enhanced Metrics from Database Results
#'
#' Computes comprehensive metrics directly from narrative_results table
#'
#' @param conn Database connection
#' @param experiment_id Experiment ID
#' @return List with all metrics
#' @export
compute_enhanced_metrics <- function(conn, experiment_id) {
  # Query all results for this experiment
  results <- DBI::dbGetQuery(conn,
    "SELECT detected, manual_flag_ind,
            is_true_positive, is_true_negative,
            is_false_positive, is_false_negative
     FROM narrative_results
     WHERE experiment_id = ? AND error_occurred = 0",
    params = list(experiment_id))
  
  if (nrow(results) == 0) {
    return(list(
      n_narratives_processed = 0L,
      n_positive_detected = 0L,
      n_negative_detected = 0L,
      n_positive_manual = 0L,
      n_negative_manual = 0L,
      accuracy = NA_real_,
      precision_ipv = NA_real_,
      recall_ipv = NA_real_,
      f1_ipv = NA_real_,
      n_false_positive = 0L,
      n_false_negative = 0L,
      n_true_positive = 0L,
      n_true_negative = 0L,
      pct_overlap_with_manual = NA_real_
    ))
  }
  
  # Count classifications
  n_tp <- sum(results$is_true_positive, na.rm = TRUE)
  n_tn <- sum(results$is_true_negative, na.rm = TRUE)
  n_fp <- sum(results$is_false_positive, na.rm = TRUE)
  n_fn <- sum(results$is_false_negative, na.rm = TRUE)
  
  # Count detections
  n_positive_detected <- sum(results$detected, na.rm = TRUE)
  n_negative_detected <- sum(!results$detected, na.rm = TRUE)
  n_positive_manual <- sum(results$manual_flag_ind, na.rm = TRUE)
  n_negative_manual <- sum(!results$manual_flag_ind, na.rm = TRUE)
  
  # Compute metrics
  n_total <- nrow(results)
  accuracy <- (n_tp + n_tn) / n_total
  
  precision_ipv <- if ((n_tp + n_fp) > 0) n_tp / (n_tp + n_fp) else NA_real_
  recall_ipv <- if ((n_tp + n_fn) > 0) n_tp / (n_tp + n_fn) else NA_real_
  
  f1_ipv <- if (!is.na(precision_ipv) && !is.na(recall_ipv) && (precision_ipv + recall_ipv) > 0) {
    2 * (precision_ipv * recall_ipv) / (precision_ipv + recall_ipv)
  } else {
    NA_real_
  }
  
  # Compute overlap with manual flags
  n_correct <- n_tp + n_tn
  pct_overlap <- (n_correct / n_total) * 100
  
  list(
    n_narratives_processed = as.integer(n_total),
    n_positive_detected = as.integer(n_positive_detected),
    n_negative_detected = as.integer(n_negative_detected),
    n_positive_manual = as.integer(n_positive_manual),
    n_negative_manual = as.integer(n_negative_manual),
    accuracy = accuracy,
    precision_ipv = precision_ipv,
    recall_ipv = recall_ipv,
    f1_ipv = f1_ipv,
    n_false_positive = as.integer(n_fp),
    n_false_negative = as.integer(n_fn),
    n_true_positive = as.integer(n_tp),
    n_true_negative = as.integer(n_tn),
    pct_overlap_with_manual = pct_overlap
  )
}

#' Mark Experiment as Failed
#'
#' Updates experiment status to failed with error message
#'
#' @param conn Database connection
#' @param experiment_id Experiment ID
#' @param error_msg Error message
#' @export
mark_experiment_failed <- function(conn, experiment_id, error_msg) {
  end_time <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  
  notes <- paste("FAILED:", error_msg)
  
  DBI::dbExecute(conn,
    "UPDATE experiments SET
      status = 'failed',
      end_time = ?,
      notes = ?
    WHERE experiment_id = ?",
    params = list(end_time, notes, experiment_id))
}

#' Initialize Experiment Logger
#'
#' Creates log directory and returns logger object with logging functions
#'
#' @param experiment_id Unique experiment ID
#' @return Logger object (list with log functions)
#' @export
init_experiment_logger <- function(experiment_id) {
  log_dir <- here::here("logs", "experiments", experiment_id)
  dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
  
  log_paths <- list(
    main = file.path(log_dir, "experiment.log"),
    api = file.path(log_dir, "api_calls.log"),
    errors = file.path(log_dir, "errors.log"),
    performance = file.path(log_dir, "performance.log")
  )
  
  # Initialize log files with headers
  writeLines(
    paste("=== Experiment Log:", experiment_id, "==="),
    log_paths$main
  )
  
  # Add CSV header to performance log
  writeLines(
    "timestamp,narrative_id,response_sec,status",
    log_paths$performance
  )
  
  list(
    log_dir = log_dir,
    paths = log_paths,
    
    info = function(msg) {
      log_message(log_paths$main, "INFO", msg)
    },
    
    warn = function(msg) {
      log_message(log_paths$main, "WARN", msg)
      log_message(log_paths$errors, "WARN", msg)
    },
    
    error = function(msg, error_obj = NULL) {
      log_message(log_paths$main, "ERROR", msg)
      log_message(log_paths$errors, "ERROR", msg)
      if (!is.null(error_obj)) {
        log_message(log_paths$errors, "ERROR", paste("Details:", as.character(error_obj)))
      }
    },
    
    api_call = function(narrative_id, duration_sec, status = "SUCCESS") {
      log_line <- sprintf(
        "[%s] narrative_id=%s duration=%.2fs status=%s",
        format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        narrative_id,
        duration_sec,
        status
      )
      cat(log_line, "\n", file = log_paths$api, append = TRUE)
    },
    
    performance = function(narrative_id, response_sec, status = "OK") {
      log_line <- sprintf(
        "%s,%s,%.2f,%s",
        format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        narrative_id,
        response_sec,
        status
      )
      cat(log_line, "\n", file = log_paths$performance, append = TRUE)
    }
  )
}

# Helper: Write log message with timestamp
log_message <- function(file_path, level, msg) {
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  log_line <- sprintf("[%s] [%s] %s", timestamp, level, msg)
  cat(log_line, "\n", file = file_path, append = TRUE)
}
