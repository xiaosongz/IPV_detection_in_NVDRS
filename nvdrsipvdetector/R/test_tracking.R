#' Enhanced Test Tracking System
#'
#' @description Functions for comprehensive test run tracking and analysis
#' @name test_tracking
#' @keywords internal
NULL

#' Initialize Enhanced Test Database
#'
#' @description Creates all tables for comprehensive test tracking
#' @param db_path Path to SQLite database
#' @return Database connection
#' @export
init_test_database <- function(db_path = "logs/test_tracking.sqlite") {
  dir.create(dirname(db_path), recursive = TRUE, showWarnings = FALSE)
  conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  
  # Enable WAL mode for better concurrency
  DBI::dbExecute(conn, "PRAGMA journal_mode = WAL")
  
  # Test runs table
  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS test_runs (
      run_id TEXT PRIMARY KEY,
      run_timestamp INTEGER NOT NULL,
      prompt_version TEXT NOT NULL,
      model_name TEXT,
      temperature REAL,
      max_tokens INTEGER,
      test_description TEXT,
      total_cases INTEGER,
      completed_cases INTEGER,
      status TEXT CHECK(status IN ('running', 'completed', 'failed')),
      created_at INTEGER DEFAULT (strftime('%s', 'now')),
      completed_at INTEGER
    )
  ")
  
  # Classification results table
  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS classification_results (
      result_id TEXT PRIMARY KEY,
      run_id TEXT NOT NULL,
      incident_id TEXT NOT NULL,
      narrative_type TEXT CHECK(narrative_type IN ('LE', 'CME', 'COMBINED')),
      predicted_ipv INTEGER,
      confidence REAL,
      actual_ipv INTEGER,
      indicators TEXT,
      rationale TEXT,
      processing_time_ms INTEGER,
      error_message TEXT,
      created_at INTEGER DEFAULT (strftime('%s', 'now')),
      FOREIGN KEY (run_id) REFERENCES test_runs(run_id)
    )
  ")
  
  # Performance metrics table
  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS performance_metrics (
      metric_id TEXT PRIMARY KEY,
      run_id TEXT NOT NULL,
      narrative_type TEXT,
      accuracy REAL,
      precision_score REAL,
      recall REAL,
      f1_score REAL,
      true_positives INTEGER,
      true_negatives INTEGER,
      false_positives INTEGER,
      false_negatives INTEGER,
      auc_roc REAL,
      average_confidence REAL,
      confidence_std REAL,
      created_at INTEGER DEFAULT (strftime('%s', 'now')),
      FOREIGN KEY (run_id) REFERENCES test_runs(run_id)
    )
  ")
  
  # Prompt versions table
  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS prompt_versions (
      version_id TEXT PRIMARY KEY,
      version_name TEXT NOT NULL,
      prompt_template TEXT NOT NULL,
      forensic_template TEXT,
      weights_json TEXT,
      description TEXT,
      created_at INTEGER DEFAULT (strftime('%s', 'now')),
      created_by TEXT
    )
  ")
  
  # Error analysis table
  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS error_analysis (
      error_id TEXT PRIMARY KEY,
      run_id TEXT NOT NULL,
      incident_id TEXT NOT NULL,
      error_type TEXT CHECK(error_type IN ('false_positive', 'false_negative', 'processing_error')),
      predicted_confidence REAL,
      actual_label INTEGER,
      predicted_label INTEGER,
      misclassification_reason TEXT,
      narrative_quality_score REAL,
      created_at INTEGER DEFAULT (strftime('%s', 'now')),
      FOREIGN KEY (run_id) REFERENCES test_runs(run_id)
    )
  ")
  
  # Indicator frequency table
  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS indicator_frequency (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      run_id TEXT NOT NULL,
      indicator TEXT NOT NULL,
      frequency INTEGER,
      true_positive_count INTEGER,
      false_positive_count INTEGER,
      predictive_value REAL,
      FOREIGN KEY (run_id) REFERENCES test_runs(run_id)
    )
  ")
  
  # Create indices for performance
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_results_run ON classification_results(run_id)")
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_results_incident ON classification_results(incident_id)")
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_metrics_run ON performance_metrics(run_id)")
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_errors_run ON error_analysis(run_id)")
  
  return(conn)
}

#' Create Test Run
#'
#' @description Initializes a new test run with metadata
#' @param conn Database connection
#' @param prompt_version Version identifier for the prompt
#' @param model_name Name of the LLM model
#' @param description Description of the test run
#' @param config Configuration object
#' @return Test run ID
#' @export
create_test_run <- function(conn, prompt_version, model_name = NULL, 
                           description = NULL, config = NULL) {
  run_id <- paste0("run_", format(Sys.time(), "%Y%m%d_%H%M%S_"), 
                   sample(1000:9999, 1))
  
  if (is.null(model_name) && !is.null(config)) {
    model_name <- config$api$model
  }
  
  temperature <- if (!is.null(config)) config$api$temperature else NA
  max_tokens <- if (!is.null(config)) config$api$max_tokens else NA
  
  DBI::dbExecute(conn, "
    INSERT INTO test_runs (run_id, run_timestamp, prompt_version, model_name,
                           temperature, max_tokens, test_description, status)
    VALUES (?, ?, ?, ?, ?, ?, ?, 'running')
  ", params = list(
    run_id,
    as.integer(Sys.time()),
    prompt_version,
    model_name,
    temperature,
    max_tokens,
    description
  ))
  
  cli::cli_alert_success("Created test run: {run_id}")
  return(run_id)
}

#' Log Classification Result
#'
#' @description Logs a single classification result to the database
#' @param conn Database connection
#' @param run_id Test run identifier
#' @param incident_id Incident identifier
#' @param predicted Result from IPV detection
#' @param actual Ground truth label
#' @param narrative_type "LE", "CME", or "COMBINED"
#' @param processing_time_ms Processing time in milliseconds
#' @export
log_classification_result <- function(conn, run_id, incident_id, predicted, 
                                     actual, narrative_type = "LE",
                                     processing_time_ms = NULL) {
  result_id <- paste0(run_id, "_", incident_id, "_", narrative_type)
  
  # Extract values from predicted result
  predicted_ipv <- as.integer(predicted$ipv_detected %||% NA)
  confidence <- predicted$confidence %||% NA
  # Ensure indicators is a single string
  indicators <- as.character(jsonlite::toJSON(predicted$indicators %||% list(), auto_unbox = TRUE))
  rationale <- as.character(predicted$rationale %||% "")
  error_message <- if (!isTRUE(predicted$success)) {
    as.character(predicted$error %||% "Unknown error")
  } else {
    NULL
  }
  
  DBI::dbExecute(conn, "
    INSERT OR REPLACE INTO classification_results 
    (result_id, run_id, incident_id, narrative_type, predicted_ipv, confidence,
     actual_ipv, indicators, rationale, processing_time_ms, error_message)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ", params = list(
    result_id, run_id, incident_id, narrative_type,
    predicted_ipv, confidence, as.integer(actual),
    indicators, rationale, processing_time_ms, error_message
  ))
}

#' Calculate Performance Metrics
#'
#' @description Calculates and stores performance metrics for a test run
#' @param conn Database connection
#' @param run_id Test run identifier
#' @param narrative_type Optional filter by narrative type
#' @return Performance metrics list
#' @export
calculate_test_metrics <- function(conn, run_id, narrative_type = NULL) {
  # Build query based on narrative type
  where_clause <- if (!is.null(narrative_type)) {
    paste0(" AND narrative_type = '", narrative_type, "'")
  } else {
    ""
  }
  
  # Get classification results
  results <- DBI::dbGetQuery(conn, paste0("
    SELECT predicted_ipv, actual_ipv, confidence
    FROM classification_results
    WHERE run_id = ? AND predicted_ipv IS NOT NULL AND actual_ipv IS NOT NULL",
    where_clause
  ), params = list(run_id))
  
  if (nrow(results) == 0) {
    cli::cli_alert_warning("No results found for run {run_id}")
    return(NULL)
  }
  
  # Calculate confusion matrix
  tp <- sum(results$predicted_ipv == 1 & results$actual_ipv == 1)
  tn <- sum(results$predicted_ipv == 0 & results$actual_ipv == 0)
  fp <- sum(results$predicted_ipv == 1 & results$actual_ipv == 0)
  fn <- sum(results$predicted_ipv == 0 & results$actual_ipv == 1)
  
  # Calculate metrics
  accuracy <- (tp + tn) / nrow(results)
  precision <- if ((tp + fp) > 0) tp / (tp + fp) else 0
  recall <- if ((tp + fn) > 0) tp / (tp + fn) else 0
  f1 <- if ((precision + recall) > 0) 2 * precision * recall / (precision + recall) else 0
  
  # Calculate AUC-ROC if possible
  auc_roc <- tryCatch({
    if (requireNamespace("pROC", quietly = TRUE)) {
      roc_obj <- pROC::roc(results$actual_ipv, results$confidence, quiet = TRUE)
      as.numeric(pROC::auc(roc_obj))
    } else {
      NA
    }
  }, error = function(e) NA)
  
  # Store metrics
  metric_id <- paste0(run_id, "_", narrative_type %||% "ALL", "_", 
                     format(Sys.time(), "%Y%m%d%H%M%S"))
  
  DBI::dbExecute(conn, "
    INSERT INTO performance_metrics 
    (metric_id, run_id, narrative_type, accuracy, precision_score, recall, 
     f1_score, true_positives, true_negatives, false_positives, false_negatives,
     auc_roc, average_confidence, confidence_std)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ", params = list(
    metric_id, run_id, narrative_type %||% "ALL",
    accuracy, precision, recall, f1,
    tp, tn, fp, fn,
    auc_roc,
    mean(results$confidence, na.rm = TRUE),
    sd(results$confidence, na.rm = TRUE)
  ))
  
  # Return metrics
  list(
    accuracy = accuracy,
    precision = precision,
    recall = recall,
    f1_score = f1,
    confusion_matrix = list(tp = tp, tn = tn, fp = fp, fn = fn),
    auc_roc = auc_roc,
    avg_confidence = mean(results$confidence, na.rm = TRUE),
    confidence_std = sd(results$confidence, na.rm = TRUE)
  )
}

#' Analyze Errors
#'
#' @description Analyzes and logs classification errors
#' @param conn Database connection
#' @param run_id Test run identifier
#' @export
analyze_errors <- function(conn, run_id) {
  # Get misclassified cases
  errors <- DBI::dbGetQuery(conn, "
    SELECT incident_id, predicted_ipv, actual_ipv, confidence, 
           indicators, rationale, narrative_type
    FROM classification_results
    WHERE run_id = ? AND predicted_ipv != actual_ipv
  ", params = list(run_id))
  
  if (nrow(errors) == 0) {
    cli::cli_alert_success("No classification errors found for run {run_id}")
    return(NULL)
  }
  
  # Analyze each error
  for (i in seq_len(nrow(errors))) {
    error_row <- errors[i, ]
    error_type <- if (error_row$predicted_ipv == 1) "false_positive" else "false_negative"
    
    # Determine misclassification reason based on confidence
    reason <- if (error_row$confidence > 0.8) {
      "High confidence misclassification - possible labeling issue"
    } else if (error_row$confidence < 0.3) {
      "Low confidence - insufficient evidence in narrative"
    } else {
      "Moderate confidence - ambiguous indicators"
    }
    
    # Log error
    error_id <- paste0(run_id, "_", error_row$incident_id, "_", 
                      format(Sys.time(), "%Y%m%d%H%M%S"))
    
    DBI::dbExecute(conn, "
      INSERT INTO error_analysis 
      (error_id, run_id, incident_id, error_type, predicted_confidence,
       actual_label, predicted_label, misclassification_reason)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      error_id, run_id, error_row$incident_id, error_type,
      error_row$confidence, error_row$actual_ipv, 
      error_row$predicted_ipv, reason
    ))
  }
  
  cli::cli_alert_info("Analyzed {nrow(errors)} classification errors")
  return(errors)
}

#' Complete Test Run
#'
#' @description Marks a test run as completed and calculates final metrics
#' @param conn Database connection
#' @param run_id Test run identifier
#' @param status "completed" or "failed"
#' @export
complete_test_run <- function(conn, run_id, status = "completed") {
  # Update test run status
  DBI::dbExecute(conn, "
    UPDATE test_runs 
    SET status = ?, 
        completed_at = ?,
        completed_cases = (
          SELECT COUNT(DISTINCT incident_id) 
          FROM classification_results 
          WHERE run_id = ?
        )
    WHERE run_id = ?
  ", params = list(status, as.integer(Sys.time()), run_id, run_id))
  
  # Calculate metrics for all narrative types
  for (type in c("LE", "CME", "COMBINED", NULL)) {
    metrics <- calculate_test_metrics(conn, run_id, type)
    if (!is.null(metrics)) {
      cli::cli_alert_success(
        "Metrics for {type %||% 'ALL'}: Accuracy={round(metrics$accuracy, 3)}, F1={round(metrics$f1_score, 3)}"
      )
    }
  }
  
  # Analyze errors
  analyze_errors(conn, run_id)
  
  cli::cli_alert_success("Test run {run_id} completed with status: {status}")
}

#' Compare Test Runs
#'
#' @description Compares performance between two test runs
#' @param conn Database connection
#' @param run_id1 First test run ID
#' @param run_id2 Second test run ID
#' @return Comparison results
#' @export
compare_test_runs <- function(conn, run_id1, run_id2) {
  # Get metrics for both runs
  metrics1 <- DBI::dbGetQuery(conn, "
    SELECT * FROM performance_metrics 
    WHERE run_id = ? AND narrative_type = 'ALL'
  ", params = list(run_id1))
  
  metrics2 <- DBI::dbGetQuery(conn, "
    SELECT * FROM performance_metrics 
    WHERE run_id = ? AND narrative_type = 'ALL'
  ", params = list(run_id2))
  
  if (nrow(metrics1) == 0 || nrow(metrics2) == 0) {
    cli::cli_alert_warning("Metrics not found for one or both runs")
    return(NULL)
  }
  
  # Calculate differences
  comparison <- data.frame(
    metric = c("accuracy", "precision", "recall", "f1_score", "auc_roc"),
    run1 = c(metrics1$accuracy, metrics1$precision_score, metrics1$recall, 
            metrics1$f1_score, metrics1$auc_roc),
    run2 = c(metrics2$accuracy, metrics2$precision_score, metrics2$recall,
            metrics2$f1_score, metrics2$auc_roc)
  )
  
  comparison$difference <- comparison$run2 - comparison$run1
  comparison$pct_change <- (comparison$difference / comparison$run1) * 100
  
  # Statistical significance test (McNemar's test for accuracy)
  results1 <- DBI::dbGetQuery(conn, "
    SELECT predicted_ipv, actual_ipv FROM classification_results
    WHERE run_id = ? AND predicted_ipv IS NOT NULL
  ", params = list(run_id1))
  
  results2 <- DBI::dbGetQuery(conn, "
    SELECT predicted_ipv, actual_ipv FROM classification_results
    WHERE run_id = ? AND predicted_ipv IS NOT NULL
  ", params = list(run_id2))
  
  if (nrow(results1) == nrow(results2)) {
    # Create contingency table for McNemar's test
    correct1 <- results1$predicted_ipv == results1$actual_ipv
    correct2 <- results2$predicted_ipv == results2$actual_ipv
    
    # Build 2x2 table
    both_correct <- sum(correct1 & correct2)
    only1_correct <- sum(correct1 & !correct2)
    only2_correct <- sum(!correct1 & correct2)
    both_wrong <- sum(!correct1 & !correct2)
    
    # McNemar's test
    if ((only1_correct + only2_correct) > 0) {
      mcnemar_stat <- (abs(only1_correct - only2_correct) - 1)^2 / 
                     (only1_correct + only2_correct)
      p_value <- pchisq(mcnemar_stat, df = 1, lower.tail = FALSE)
      
      comparison$mcnemar_p_value <- c(p_value, rep(NA, 4))
      comparison$significant <- c(p_value < 0.05, rep(NA, 4))
    }
  }
  
  return(comparison)
}

#' Get Test Run Summary
#'
#' @description Retrieves comprehensive summary for a test run
#' @param conn Database connection
#' @param run_id Test run identifier
#' @return Summary list
#' @export
get_test_run_summary <- function(conn, run_id) {
  # Get run info
  run_info <- DBI::dbGetQuery(conn, "
    SELECT * FROM test_runs WHERE run_id = ?
  ", params = list(run_id))
  
  # Get performance metrics
  metrics <- DBI::dbGetQuery(conn, "
    SELECT * FROM performance_metrics WHERE run_id = ?
  ", params = list(run_id))
  
  # Get error summary
  error_summary <- DBI::dbGetQuery(conn, "
    SELECT error_type, COUNT(*) as count
    FROM error_analysis
    WHERE run_id = ?
    GROUP BY error_type
  ", params = list(run_id))
  
  # Get top indicators
  indicators <- DBI::dbGetQuery(conn, "
    SELECT indicator, frequency, predictive_value
    FROM indicator_frequency
    WHERE run_id = ?
    ORDER BY predictive_value DESC
    LIMIT 10
  ", params = list(run_id))
  
  list(
    run_info = run_info,
    metrics = metrics,
    error_summary = error_summary,
    top_indicators = indicators
  )
}