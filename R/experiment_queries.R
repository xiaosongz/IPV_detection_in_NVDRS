#' List Experiments
#'
#' Query experiments from database with optional filtering
#'
#' @param conn Database connection
#' @param status Optional status filter ('running', 'completed', 'failed')
#' @return Tibble with experiment information
#' @export
#' @examples
#' \dontrun{
#' # List all experiments
#' conn <- get_db_connection()
#' experiments <- list_experiments(conn)
#' print(experiments$experiment_name)
#'
#' # List only completed experiments
#' completed <- list_experiments(conn, status = "completed")
#' cat("Completed experiments:", nrow(completed), "\n")
#'
#' # List running experiments
#' running <- list_experiments(conn, status = "running")
#' for (exp in running$experiment_name) {
#'   cat("Running:", exp, "\n")
#' }
#'
#' dbDisconnect(conn)
#' }
list_experiments <- function(conn, status = NULL) {
  query <- "
    SELECT experiment_id, experiment_name, status,
           model_name, temperature, prompt_version,
           n_narratives_processed, n_narratives_total,
           f1_ipv, recall_ipv, precision_ipv,
           start_time, end_time, total_runtime_sec,
           created_at
    FROM experiments
  "

  params <- list()
  if (!is.null(status)) {
    query <- paste(query, "WHERE status = ?")
    params <- list(status)
  }

  query <- paste(query, "ORDER BY created_at DESC")

  if (length(params) > 0) {
    result <- DBI::dbGetQuery(conn, query, params = params)
  } else {
    result <- DBI::dbGetQuery(conn, query)
  }

  tibble::as_tibble(result)
}

#' Get Experiment Results
#'
#' Retrieve all narrative-level results for an experiment
#'
#' @param conn Database connection
#' @param experiment_id Experiment ID
#' @return Tibble with narrative results
#' @export
#' @examples
#' \dontrun{
#' # Get results for a specific experiment
#' conn <- get_db_connection()
#' experiment_id <- "your-experiment-id"
#' results <- get_experiment_results(conn, experiment_id)
#'
#' # Analyze detection performance
#' cat("Total narratives:", nrow(results), "\n")
#' cat("IPV detected:", sum(results$detected, na.rm = TRUE), "\n")
#' cat("Manual flags:", sum(results$manual_flag_ind, na.rm = TRUE), "\n")
#'
#' # View confidence scores
#' summary(results$confidence)
#'
#' dbDisconnect(conn)
#' }
get_experiment_results <- function(conn, experiment_id) {
  query <- "
    SELECT *
    FROM narrative_results
    WHERE experiment_id = ?
    ORDER BY row_num
  "

  result <- DBI::dbGetQuery(conn, query, params = list(experiment_id))

  # Ensure expected columns exist for downstream code that may reference them
  # This guards against older databases or partial migrations where
  # columns like `error_occurred` may be absent.
  if (!"error_occurred" %in% names(result)) {
    result$error_occurred <- 0L
  }
  if (!"is_true_positive" %in% names(result)) {
    result$is_true_positive <- NA_integer_
  }
  if (!"is_true_negative" %in% names(result)) {
    result$is_true_negative <- NA_integer_
  }
  if (!"is_false_positive" %in% names(result)) {
    result$is_false_positive <- NA_integer_
  }
  if (!"is_false_negative" %in% names(result)) {
    result$is_false_negative <- NA_integer_
  }

  tibble::as_tibble(result)
}

#' Compare Experiments
#'
#' Generate comparison table for multiple experiments
#'
#' @param conn Database connection
#' @param experiment_ids Vector of experiment IDs to compare
#' @return Tibble with comparison metrics
#' @export
compare_experiments <- function(conn, experiment_ids) {
  if (length(experiment_ids) == 0) {
    stop("No experiment IDs provided")
  }

  # Build placeholders for IN clause
  placeholders <- paste(rep("?", length(experiment_ids)), collapse = ", ")

  query <- sprintf("
    SELECT experiment_id, experiment_name, model_name, temperature,
           prompt_version, n_narratives_processed,
           accuracy, precision_ipv, recall_ipv, f1_ipv,
           n_true_positive, n_false_positive, n_false_negative, n_true_negative,
           total_runtime_sec, avg_time_per_narrative_sec,
           start_time, status
    FROM experiments
    WHERE experiment_id IN (%s)
    ORDER BY f1_ipv DESC
  ", placeholders)

  result <- DBI::dbGetQuery(conn, query, params = as.list(experiment_ids))
  tibble::as_tibble(result)
}

#' Find Disagreements
#'
#' Get false positives and false negatives for an experiment
#'
#' @param conn Database connection
#' @param experiment_id Experiment ID
#' @param type Type of disagreement ('false_positive', 'false_negative', or 'both')
#' @return Tibble with disagreement cases
#' @export
find_disagreements <- function(conn, experiment_id, type = "both") {
  if (type == "false_positive") {
    where_clause <- "is_false_positive = 1"
  } else if (type == "false_negative") {
    where_clause <- "is_false_negative = 1"
  } else {
    where_clause <- "(is_false_positive = 1 OR is_false_negative = 1)"
  }

  query <- sprintf("
    SELECT incident_id, narrative_type,
           substr(narrative_text, 1, 200) as narrative_preview,
           detected, confidence, manual_flag_ind,
           indicators, rationale,
           is_false_positive, is_false_negative
    FROM narrative_results
    WHERE experiment_id = ? AND %s
    ORDER BY confidence DESC
  ", where_clause)

  result <- DBI::dbGetQuery(conn, query, params = list(experiment_id))
  tibble::as_tibble(result)
}

#' Analyze Experiment Errors
#'
#' Get error summary and details for experiments
#'
#' @param conn Database connection
#' @param experiment_id Optional experiment ID to filter
#' @return Tibble with error summary
#' @export
analyze_experiment_errors <- function(conn, experiment_id = NULL) {
  if (!is.null(experiment_id)) {
    query <- "
      SELECT e.experiment_id, e.experiment_name,
             COUNT(*) as error_count,
             GROUP_CONCAT(DISTINCT nr.error_message) as error_types
      FROM experiments e
      JOIN narrative_results nr ON e.experiment_id = nr.experiment_id
      WHERE nr.error_occurred = 1 AND e.experiment_id = ?
      GROUP BY e.experiment_id
      ORDER BY error_count DESC
    "
    errors_summary <- DBI::dbGetQuery(conn, query, params = list(experiment_id))

    # Also read error log file if available
    log_file <- here::here("logs", "experiments", experiment_id, "errors.log")
    if (file.exists(log_file)) {
      cat("\n=== Detailed Error Log ===\n")
      cat(readLines(log_file), sep = "\n")
    }
  } else {
    query <- "
      SELECT e.experiment_id, e.experiment_name,
             COUNT(*) as error_count,
             GROUP_CONCAT(DISTINCT nr.error_message) as error_types
      FROM experiments e
      JOIN narrative_results nr ON e.experiment_id = nr.experiment_id
      WHERE nr.error_occurred = 1
      GROUP BY e.experiment_id
      ORDER BY error_count DESC
    "
    errors_summary <- DBI::dbGetQuery(conn, query)
  }

  tibble::as_tibble(errors_summary)
}

#' Read Experiment Log
#'
#' Read log file for manual inspection
#'
#' @param experiment_id Experiment ID
#' @param log_type Type of log ('main', 'api', 'errors', 'performance')
#' @return Character vector of log lines
#' @export
read_experiment_log <- function(experiment_id, log_type = "main") {
  log_files <- list(
    main = "experiment.log",
    api = "api_calls.log",
    errors = "errors.log",
    performance = "performance.log"
  )

  if (!log_type %in% names(log_files)) {
    stop("Invalid log_type. Must be one of: ", paste(names(log_files), collapse = ", "))
  }

  log_path <- here::here("logs", "experiments", experiment_id, log_files[[log_type]])

  if (!file.exists(log_path)) {
    stop("Log file not found: ", log_path)
  }

  readLines(log_path)
}
