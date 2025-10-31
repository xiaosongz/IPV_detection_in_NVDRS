#' Start New Experiment
#'
#' Creates new experiment record in database and returns experiment ID
#'
#' @param conn Database connection
#' @param config Experiment configuration list
#' @return experiment_id (UUID)
#' @export
#' @examples
#' \dontrun{
#' # Create test configuration
#' config <- list(
#'   experiment = list(
#'     name = "Test IPV Detection",
#'     author = "Research Team"
#'   ),
#'   model = list(
#'     name = "gpt-4",
#'     provider = "openai",
#'     temperature = 0.1,
#'     api_url = "https://api.openai.com/v1/chat/completions"
#'   ),
#'   prompt = list(
#'     system_prompt = "You are an IPV detection expert.",
#'     user_template = "Analyze: {narrative}",
#'     version = "v1.0"
#'   ),
#'   data = list(
#'     file = "nvdrs_data.csv"
#'   ),
#'   run = list(
#'     seed = 42
#'   )
#' )
#'
#' # Start experiment
#' conn <- get_db_connection()
#' experiment_id <- start_experiment(conn, config)
#' cat("Started experiment:", experiment_id, "\n")
#' dbDisconnect(conn)
#' }
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
    params = list(log_dir, experiment_id)
  )

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
  # Helper to coerce possibly NULL/NA values to a scalar of the right type
  as_int1 <- function(x, default = NA_integer_) {
    if (is.null(x) || length(x) == 0 || all(is.na(x))) return(default)
    as.integer(x)[1]
  }
  as_num1 <- function(x, default = NA_real_) {
    if (is.null(x) || length(x) == 0 || all(is.na(x))) return(default)
    as.numeric(x)[1]
    }
  as_chr1 <- function(x, default = NA_character_) {
    if (is.null(x) || length(x) == 0 || all(is.na(x))) return(default)
    as.character(x)[1]
  }
  as_logi1 <- function(x, default = NA) {
    if (is.null(x) || length(x) == 0 || all(is.na(x))) return(default)
    as.logical(x)[1]
  }

  # Convert indicators list/vector to a JSON string (length-1)
  indicators_json <- "[]"
  if (!is.null(result$indicators) && length(result$indicators) > 0) {
    ind <- result$indicators
    # If wrapped as tibble list-column, unwrap the first element
    if (is.list(ind) && length(ind) == 1 && !is.null(ind[[1]])) ind <- ind[[1]]
    indicators_json <- jsonlite::toJSON(ind, auto_unbox = TRUE)
  }

  # Compute classification flags (TP/TN/FP/FN) if both labels available
  is_tp <- is_tn <- is_fp <- is_fn <- NA_integer_
  det_val <- as_logi1(result$detected, default = NA)
  man_val <- as_logi1(result$manual_flag_ind, default = NA)
  if (!is.na(det_val) && !is.na(man_val)) {
    is_tp <- as.integer(det_val && man_val)
    is_tn <- as.integer(!det_val && !man_val)
    is_fp <- as.integer(det_val && !man_val)
    is_fn <- as.integer(!det_val && man_val)
  }

  # Token fields
  prompt_tokens     <- as_int1(result$prompt_tokens)
  completion_tokens <- as_int1(result$completion_tokens)
  total_tokens      <- as_int1(result$tokens_used)

  # Narrative keys (allow minimal error rows)
  incident_id_value <- as_chr1(result$incident_id)
  narrative_type    <- as_chr1(result$narrative_type)
  row_num           <- as_int1(result$row_num)
  narrative_text    <- as_chr1(result$narrative_text)
  manual_flag_ind   <- as_int1(result$manual_flag_ind)
  manual_flag       <- as_int1(result$manual_flag)
  detected_int      <- as_int1(result$detected)
  confidence_val    <- as_num1(result$confidence)
  rationale_val     <- as_chr1(result$rationale)
  reasoning_val     <- as_chr1(result$reasoning)
  raw_response_val  <- as_chr1(result$raw_response)
  response_sec_val  <- as_num1(result$response_sec)

  # Error flags: accept either parse_error or error_occurred
  # Avoid tibble warning when column is absent by checking names first
  parse_err_val <- as_logi1(result$parse_error, default = FALSE)
  error_occ_input <- if ("error_occurred" %in% names(result)) {
    as_logi1(result$error_occurred, default = FALSE)
  } else {
    FALSE
  }
  error_occurred <- as.integer(isTRUE(parse_err_val) || isTRUE(error_occ_input))
  error_message_val <- as_chr1(result$error_message)

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
      narrative_type,
      row_num,
      narrative_text,
      manual_flag_ind,
      manual_flag,
      detected_int,
      confidence_val,
      as_chr1(indicators_json, default = "[]"),
      rationale_val,
      reasoning_val,
      raw_response_val,
      response_sec_val,
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      as_int1(error_occurred, default = 0L),
      error_message_val,
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
#' @examples
#' \dontrun{
#' # After completing an experiment
#' conn <- get_db_connection()
#' experiment_id <- "your-experiment-id"
#'
#' # Finalize with metrics calculation
#' finalize_experiment(conn, experiment_id)
#'
#' # Finalize with result files
#' finalize_experiment(
#'   conn,
#'   experiment_id,
#'   csv_file = "results.csv",
#'   json_file = "results.json"
#' )
#'
#' dbDisconnect(conn)
#' }
finalize_experiment <- function(conn, experiment_id, csv_file = NULL, json_file = NULL) {
  end_time <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

  # Get start time to compute total runtime
  start_info <- DBI::dbGetQuery(conn,
    "SELECT start_time, n_narratives_total FROM experiments WHERE experiment_id = ?",
    params = list(experiment_id)
  )

  total_runtime_sec <- as.numeric(difftime(
    as.POSIXct(end_time, format = "%Y-%m-%d %H:%M:%S"),
    as.POSIXct(start_info$start_time, format = "%Y-%m-%d %H:%M:%S"),
    units = "secs"
  ))

  avg_time_per_narrative <- if (!is.null(start_info$n_narratives_total) &&
    !is.na(start_info$n_narratives_total) &&
    start_info$n_narratives_total > 0) {
    total_runtime_sec / start_info$n_narratives_total
  } else {
    NA_real_
  }

  # Compute enhanced metrics from database results
  enhanced_metrics <- compute_enhanced_metrics(conn, experiment_id)

  # Normalize optional file paths to scalar values
  csv_file_val  <- if (is.null(csv_file)) NA_character_ else as.character(csv_file)
  json_file_val <- if (is.null(json_file)) NA_character_ else as.character(json_file)

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
      csv_file_val,
      json_file_val,
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
    params = list(experiment_id)
  )

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
    params = list(end_time, notes, experiment_id)
  )
}

#' Initialize Experiment Logger
#'
#' Creates log directory and returns logger object with logging functions
#'
#' @param experiment_id Unique experiment ID
#' @return Logger object (list with log functions)
#' @export
#' @examples
#' \dontrun{
#' # Initialize logger for experiment
#' experiment_id <- "your-experiment-id"
#' logger <- init_experiment_logger(experiment_id)
#'
#' # Log messages
#' logger$info("Starting experiment")
#' logger$warn("API call slow")
#' logger$error("Failed to process narrative", error_obj = err)
#'
#' # Log API call performance
#' logger$api_call("narrative_001", 2.5, "SUCCESS")
#' logger$performance("narrative_001", 2.5, "OK")
#'
#' cat("Log directory:", logger$log_dir, "\n")
#' }
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
  # Ensure errors log exists
  if (!file.exists(log_paths$errors)) {
    writeLines(paste("=== Errors Log:", experiment_id, "==="), log_paths$errors)
  }

  list(
    log_dir = log_dir,
    # Back-compat fields expected by tests
    log_file = log_paths$main,
    error_file = log_paths$errors,
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

#' Save Experiment Results to CSV/JSON Files
#'
#' Exports experiment results to CSV and/or JSON format with proper formatting
#'
#' @param experiment_id Character string. The experiment identifier
#' @param format Character. Output format: "csv", "json", or "both" (default: "both")
#' @param output_dir Character. Directory to save files (default: benchmark_results/)
#' @param timestamp Character. Optional timestamp for filenames (default: current time)
#'
#' @return Named list with file paths (or NULL if not saved)
#' @export
#'
#' @examples
#' \dontrun{
#' # Save experiment results in both formats
#' files <- save_experiment_results("exp-123-456", format = "both")
#' 
#' # Save only CSV
#' csv_file <- save_experiment_results("exp-123-456", format = "csv")
#' 
#' # Save to custom directory
#' files <- save_experiment_results("exp-123-456", output_dir = "custom_output")
#' }
save_experiment_results <- function(experiment_id, 
                                  format = c("both", "csv", "json"),
                                  output_dir = here::here("benchmark_results"),
                                  timestamp = format(Sys.time(), "%Y%m%d_%H%M%S")) {
  
  format <- match.arg(format)
  
  # Create output directory if it doesn't exist
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  }
  
  # Get experiment results from database
  conn <- get_db_connection()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  
  results <- get_experiment_results(conn, experiment_id)
  
  output_files <- list()
  base_filename <- paste0("experiment_", experiment_id, "_", timestamp)
  
  if (nrow(results) == 0) {
    # Create empty result structure for consistent return value
    empty_results <- data.frame(
      experiment_id = character(0),
      incident_id = character(0),
      narrative_type = character(0),
      detected = logical(0),
      confidence = numeric(0),
      indicators = I(list()),
      stringsAsFactors = FALSE
    )
    
    # Create empty files for consistency
    if (format %in% c("csv", "both")) {
      csv_path <- file.path(output_dir, paste0(base_filename, ".csv"))
      write.csv(empty_results, csv_path, row.names = FALSE)
      output_files$csv <- csv_path
    }
    
    if (format %in% c("json", "both")) {
      json_path <- file.path(output_dir, paste0(base_filename, ".json"))
      jsonlite::write_json(empty_results, json_path, pretty = TRUE, auto_unbox = TRUE)
      output_files$json <- json_path
    }
    
    return(invisible(output_files))
  }
  
  # Save CSV format
  if (format %in% c("csv", "both")) {
    csv_path <- file.path(output_dir, paste0(base_filename, ".csv"))
    
    # Prepare results for CSV (flatten list columns)
    csv_data <- results
    
    # Convert list columns to strings
    list_columns <- names(results)[sapply(results, is.list)]
    for (col in list_columns) {
      if (col == "indicators") {
        csv_data[[col]] <- sapply(results[[col]], function(x) {
          if (is.null(x) || length(x) == 0) "" else paste(x, collapse = "; ")
        })
      } else {
        csv_data[[col]] <- sapply(results[[col]], function(x) {
          if (is.null(x)) "" else paste(unlist(x), collapse = "; ")
        })
      }
    }
    
    write.csv(csv_data, csv_path, row.names = FALSE, na = "")
    output_files$csv <- csv_path
  }
  
  # Save JSON format
  if (format %in% c("json", "both")) {
    json_path <- file.path(output_dir, paste0(base_filename, ".json"))
    
    # Prepare results for JSON (handle list objects properly)
    json_data <- results
    
    # Convert POSIXct to character for JSON compatibility
    date_columns <- names(results)[sapply(results, function(x) inherits(x, "POSIXct"))]
    for (col in date_columns) {
      json_data[[col]] <- as.character(results[[col]])
    }
    
    jsonlite::write_json(json_data, json_path, pretty = TRUE, auto_unbox = TRUE, na = "null")
    output_files$json <- json_path
  }
  
  return(invisible(output_files))
}

#' Acquire Resume Lock for Experiment
#'
#' Creates a PID lock file to prevent concurrent resumes
#'
#' @param experiment_id Experiment ID
#' @return TRUE if lock acquired, stops with error if lock exists
#' @export
acquire_resume_lock <- function(experiment_id) {
  lock_file <- here::here("data", paste0(".resume_lock_", experiment_id, ".pid"))
  
  # Check if lock exists
  if (file.exists(lock_file)) {
    # Read PID from lock file
    locked_pid <- readLines(lock_file, warn = FALSE)[1]
    
    # Check if process is still running (Unix-like systems)
    if (.Platform$OS.type == "unix") {
      pid_running <- system2("ps", args = c("-p", locked_pid), stdout = FALSE, stderr = FALSE) == 0
      
      if (pid_running) {
        stop("Resume lock exists for experiment ", experiment_id, 
             " (PID: ", locked_pid, "). Another process may be resuming this experiment.\n",
             "If the process crashed, verify PID is not active and remove: ", lock_file,
             call. = FALSE)
      } else {
        cat("Stale lock file found (PID", locked_pid, "not running). Removing...\n")
        file.remove(lock_file)
      }
    } else {
      # Windows: just warn
      warning("Lock file exists: ", lock_file, 
              "\nIf no other process is running, remove this file manually.",
              call. = FALSE)
      stop("Cannot acquire resume lock", call. = FALSE)
    }
  }
  
  # Create lock file with current PID
  current_pid <- Sys.getpid()
  cat(current_pid, file = lock_file)
  cat("Resume lock acquired (PID:", current_pid, ")\n")
  
  return(TRUE)
}

#' Release Resume Lock for Experiment
#'
#' Removes PID lock file
#'
#' @param experiment_id Experiment ID
#' @export
release_resume_lock <- function(experiment_id) {
  lock_file <- here::here("data", paste0(".resume_lock_", experiment_id, ".pid"))
  
  if (file.exists(lock_file)) {
    file.remove(lock_file)
    cat("Resume lock released\n")
  }
  
  invisible(TRUE)
}

#' Update Progress for Running Experiment
#'
#' Updates n_narratives_completed and estimated completion time
#'
#' @param conn Database connection
#' @param experiment_id Experiment ID
#' @param n_completed Number of narratives completed so far
#' @export
update_experiment_progress <- function(conn, experiment_id, n_completed) {
  # Get start time and total narratives
  exp_info <- DBI::dbGetQuery(conn,
    "SELECT start_time, n_narratives_total FROM experiments WHERE experiment_id = ?",
    params = list(experiment_id)
  )
  
  if (nrow(exp_info) == 0) {
    warning("Experiment not found: ", experiment_id)
    return(invisible(FALSE))
  }
  
  # Calculate ETA
  start_time <- as.POSIXct(exp_info$start_time, format = "%Y-%m-%d %H:%M:%S")
  elapsed_sec <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  
  eta_text <- "Unknown"
  if (n_completed > 0 && !is.na(exp_info$n_narratives_total) && exp_info$n_narratives_total > 0) {
    avg_sec_per_narrative <- elapsed_sec / n_completed
    remaining <- exp_info$n_narratives_total - n_completed
    eta_sec <- remaining * avg_sec_per_narrative
    eta_time <- Sys.time() + eta_sec
    eta_text <- format(eta_time, "%Y-%m-%d %H:%M:%S")
  }
  
  # Update database
  DBI::dbExecute(conn,
    "UPDATE experiments SET 
      n_narratives_completed = ?,
      last_progress_update = ?,
      estimated_completion_time = ?
    WHERE experiment_id = ?",
    params = list(
      n_completed,
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      eta_text,
      experiment_id
    )
  )
  
  invisible(TRUE)
}

