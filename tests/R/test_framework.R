#' Enhanced Test Framework for IPV Detection System
#' 
#' This module provides comprehensive testing infrastructure including:
#' - Test run management
#' - Performance metric calculations  
#' - Confidence calibration analysis
#' - Statistical significance testing
#' - Visualization helpers

# Load required libraries
suppressPackageStartupMessages({
  library(DBI)
  library(RSQLite) 
  library(dplyr)
  library(purrr)
  library(tibble)
  library(readr)
  library(yaml)
  library(digest)
  library(jsonlite)
  library(cli)
  library(ggplot2)
  library(pROC)
})

#' Initialize Enhanced Test Database
#' 
#' @param db_path Path to SQLite database file
#' @return Database connection with enhanced schema
#' @export
init_test_database <- function(db_path = "tests/test_logs.sqlite") {
  dir.create(dirname(db_path), recursive = TRUE, showWarnings = FALSE)
  conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  
  # Enable WAL mode for better concurrent access
  DBI::dbExecute(conn, "PRAGMA journal_mode = WAL")
  DBI::dbExecute(conn, "PRAGMA synchronous = NORMAL")
  DBI::dbExecute(conn, "PRAGMA cache_size = 10000")
  
  # Execute schema from file
  schema_path <- file.path("tests", "schema", "enhanced_test_tracking_schema.sql")
  if (file.exists(schema_path)) {
    schema_sql <- readr::read_file(schema_path)
    # Split by semicolon and execute each statement
    statements <- strsplit(schema_sql, ";\\s*\n")[[1]]
    statements <- statements[nzchar(trimws(statements))]
    
    for (stmt in statements) {
      if (nzchar(trimws(stmt))) {
        DBI::dbExecute(conn, stmt)
      }
    }
  } else {
    cli::cli_alert_warning("Schema file not found: {schema_path}")
  }
  
  return(conn)
}

#' Create New Test Run
#' 
#' @param conn Database connection
#' @param run_name Descriptive name for the test run
#' @param prompt_version_id ID of prompt version being tested
#' @param model_name Name of the LLM model
#' @param model_version Version of the model (optional)
#' @param config Configuration object or path
#' @param test_set_name Name of test dataset
#' @param test_set_size Number of cases in test set
#' @param description Optional description
#' @param started_by Who initiated the test run
#' @return Test run ID
#' @export
create_test_run <- function(conn, run_name, prompt_version_id, model_name, 
                           model_version = NULL, config = NULL, 
                           test_set_name = "default", test_set_size = 0,
                           description = NULL, started_by = Sys.info()["user"]) {
  
  # Generate unique run ID
  run_id <- paste0("run_", format(Sys.time(), "%Y%m%d_%H%M%S"), "_", 
                   digest::digest(paste(run_name, Sys.time()), algo = "md5", serialize = FALSE)[1:8])
  
  # Calculate config hash
  config_hash <- if (is.null(config)) {
    "default"
  } else {
    digest::digest(config, algo = "sha256", serialize = TRUE)[1:16]
  }
  
  DBI::dbExecute(conn, "
    INSERT INTO test_runs (
      run_id, run_name, run_timestamp, prompt_version_id, model_name, 
      model_version, config_hash, test_set_name, test_set_size, 
      description, status, started_by
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'running', ?)
  ", params = list(
    run_id, run_name, as.integer(Sys.time()), prompt_version_id, model_name,
    model_version, config_hash, test_set_name, test_set_size, 
    description, started_by
  ))
  
  cli::cli_alert_success("Created test run: {run_id}")
  return(run_id)
}

#' Record Test Results
#' 
#' @param conn Database connection
#' @param run_id Test run identifier
#' @param results Data frame with test results
#' @export
record_test_results <- function(conn, run_id, results) {
  
  # Validate required columns
  required_cols <- c("incident_id", "narrative_type", "predicted_ipv", 
                    "predicted_confidence", "actual_ipv")
  missing_cols <- setdiff(required_cols, names(results))
  if (length(missing_cols) > 0) {
    stop("Missing required columns: ", paste(missing_cols, collapse = ", "))
  }
  
  # Prepare data for insertion
  results_prep <- results %>%
    mutate(
      result_id = paste0(run_id, "_", incident_id, "_", narrative_type),
      run_id = run_id,
      indicators = if("indicators" %in% names(.)) {
        map_chr(indicators, ~ if(is.null(.x) || length(.x) == 0) NA_character_ else jsonlite::toJSON(.x, auto_unbox = TRUE))
      } else NA_character_,
      rationale = if("rationale" %in% names(.)) rationale else NA_character_,
      processing_time_ms = if("processing_time_ms" %in% names(.)) processing_time_ms else NA_integer_,
      token_count = if("token_count" %in% names(.)) token_count else NA_integer_,
      prompt_tokens = if("prompt_tokens" %in% names(.)) prompt_tokens else NA_integer_,
      completion_tokens = if("completion_tokens" %in% names(.)) completion_tokens else NA_integer_,
      api_cost = if("api_cost" %in% names(.)) api_cost else NA_real_,
      error_message = if("error_message" %in% names(.)) error_message else NA_character_,
      created_timestamp = as.integer(Sys.time())
    ) %>%
    select(result_id, run_id, incident_id, narrative_type, predicted_ipv,
           predicted_confidence, actual_ipv, indicators, rationale,
           processing_time_ms, token_count, prompt_tokens, completion_tokens,
           api_cost, error_message, created_timestamp)
  
  # Insert in batches for performance
  batch_size <- 100
  batches <- split(results_prep, ceiling(seq_len(nrow(results_prep)) / batch_size))
  
  pb <- cli::cli_progress_bar("Recording results", total = length(batches))
  
  for (batch in batches) {
    DBI::dbExecute(conn, "
      INSERT OR REPLACE INTO test_results (
        result_id, run_id, incident_id, narrative_type, predicted_ipv,
        predicted_confidence, actual_ipv, indicators, rationale,
        processing_time_ms, token_count, prompt_tokens, completion_tokens,
        api_cost, error_message, created_timestamp
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = as.list(batch))
    
    cli::cli_progress_update(id = pb)
  }
  
  cli::cli_alert_success("Recorded {nrow(results_prep)} test results")
}

#' Calculate Performance Metrics
#' 
#' @param conn Database connection
#' @param run_id Test run identifier
#' @param calculate_by Vector of grouping variables ("narrative_type" and/or "combined")
#' @export
calculate_performance_metrics <- function(conn, run_id, calculate_by = c("LE", "CME", "combined")) {
  
  # Get test results
  results <- DBI::dbGetQuery(conn, "
    SELECT * FROM test_results 
    WHERE run_id = ? AND predicted_ipv IS NOT NULL AND actual_ipv IS NOT NULL
  ", params = list(run_id))
  
  if (nrow(results) == 0) {
    cli::cli_alert_warning("No valid results found for run {run_id}")
    return(invisible())
  }
  
  # Calculate metrics by narrative type
  if ("LE" %in% calculate_by || "CME" %in% calculate_by) {
    type_metrics <- results %>%
      filter(narrative_type %in% intersect(c("LE", "CME"), calculate_by)) %>%
      group_by(narrative_type) %>%
      summarise(
        metrics = list(calculate_binary_metrics(predicted_ipv, actual_ipv, predicted_confidence)),
        .groups = "drop"
      ) %>%
      unnest_wider(metrics)
    
    # Store narrative type metrics
    for (i in seq_len(nrow(type_metrics))) {
      store_metrics(conn, run_id, type_metrics[i,])
    }
  }
  
  # Calculate combined metrics if requested
  if ("combined" %in% calculate_by) {
    combined_metrics <- results %>%
      summarise(
        narrative_type = "combined",
        metrics = list(calculate_binary_metrics(predicted_ipv, actual_ipv, predicted_confidence))
      ) %>%
      unnest_wider(metrics)
    
    store_metrics(conn, run_id, combined_metrics)
  }
  
  cli::cli_alert_success("Calculated performance metrics for run {run_id}")
}

#' Calculate Binary Classification Metrics
#' 
#' @param predicted Vector of predicted values (logical)
#' @param actual Vector of actual values (logical) 
#' @param confidence Vector of confidence scores (numeric)
#' @return List of metrics
calculate_binary_metrics <- function(predicted, actual, confidence = NULL) {
  
  # Convert to logical if needed
  predicted <- as.logical(predicted)
  actual <- as.logical(actual)
  
  # Confusion matrix components
  tp <- sum(predicted & actual, na.rm = TRUE)
  tn <- sum(!predicted & !actual, na.rm = TRUE)
  fp <- sum(predicted & !actual, na.rm = TRUE)
  fn <- sum(!predicted & actual, na.rm = TRUE)
  
  total <- tp + tn + fp + fn
  
  # Basic metrics
  accuracy <- (tp + tn) / total
  precision <- tp / (tp + fp)
  recall <- tp / (tp + fn)
  specificity <- tn / (tn + fp)
  f1_score <- 2 * (precision * recall) / (precision + recall)
  
  # Handle division by zero
  precision <- ifelse(is.finite(precision), precision, 0)
  recall <- ifelse(is.finite(recall), recall, 0)
  specificity <- ifelse(is.finite(specificity), specificity, 0)
  f1_score <- ifelse(is.finite(f1_score), f1_score, 0)
  
  # AUC-ROC if confidence scores available
  auc_roc <- if (!is.null(confidence) && length(unique(actual)) > 1) {
    tryCatch({
      roc_obj <- pROC::roc(actual, confidence, quiet = TRUE)
      as.numeric(roc_obj$auc)
    }, error = function(e) NA_real_)
  } else {
    NA_real_
  }
  
  # Confidence-based metrics
  avg_conf_correct <- if (!is.null(confidence)) {
    mean(confidence[predicted == actual], na.rm = TRUE)
  } else NA_real_
  
  avg_conf_incorrect <- if (!is.null(confidence)) {
    mean(confidence[predicted != actual], na.rm = TRUE) 
  } else NA_real_
  
  # Processing time metrics (assuming available globally)
  processing_times <- confidence # Placeholder - should be passed separately
  avg_processing_time_ms <- NA_real_
  
  list(
    accuracy = accuracy,
    precision = precision,
    recall = recall,
    f1_score = f1_score,
    specificity = specificity,
    auc_roc = auc_roc,
    true_positives = tp,
    true_negatives = tn,
    false_positives = fp,
    false_negatives = fn,
    total_cases = total,
    avg_confidence_correct = avg_conf_correct,
    avg_confidence_incorrect = avg_conf_incorrect,
    avg_processing_time_ms = avg_processing_time_ms
  )
}

#' Store Performance Metrics in Database
#' 
#' @param conn Database connection
#' @param run_id Test run identifier  
#' @param metrics_row Single row tibble with metrics
store_metrics <- function(conn, run_id, metrics_row) {
  
  metric_id <- paste0(run_id, "_", metrics_row$narrative_type)
  
  DBI::dbExecute(conn, "
    INSERT OR REPLACE INTO performance_metrics (
      metric_id, run_id, narrative_type, accuracy, precision, recall, f1_score,
      specificity, auc_roc, true_positives, true_negatives, false_positives,
      false_negatives, total_cases, avg_confidence_correct, avg_confidence_incorrect,
      avg_processing_time_ms, calculated_timestamp
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ", params = list(
    metric_id, run_id, metrics_row$narrative_type, metrics_row$accuracy,
    metrics_row$precision, metrics_row$recall, metrics_row$f1_score,
    metrics_row$specificity, metrics_row$auc_roc, metrics_row$true_positives,
    metrics_row$true_negatives, metrics_row$false_positives, metrics_row$false_negatives,
    metrics_row$total_cases, metrics_row$avg_confidence_correct, 
    metrics_row$avg_confidence_incorrect, metrics_row$avg_processing_time_ms,
    as.integer(Sys.time())
  ))
}

#' Perform Confidence Calibration Analysis
#' 
#' @param conn Database connection
#' @param run_id Test run identifier
#' @param n_bins Number of confidence bins (default: 10)
#' @export
analyze_confidence_calibration <- function(conn, run_id, n_bins = 10) {
  
  # Get results with confidence scores
  results <- DBI::dbGetQuery(conn, "
    SELECT narrative_type, predicted_ipv, actual_ipv, predicted_confidence
    FROM test_results 
    WHERE run_id = ? AND predicted_confidence IS NOT NULL 
      AND actual_ipv IS NOT NULL
  ", params = list(run_id))
  
  if (nrow(results) == 0) {
    cli::cli_alert_warning("No confidence data found for run {run_id}")
    return(invisible())
  }
  
  # Calculate calibration for each narrative type and combined
  for (nt in c(unique(results$narrative_type), "combined")) {
    
    data <- if (nt == "combined") results else filter(results, narrative_type == nt)
    
    # Create confidence bins
    bin_edges <- seq(0, 1, length.out = n_bins + 1)
    bin_centers <- (bin_edges[-1] + bin_edges[-length(bin_edges)]) / 2
    
    calibration_data <- tibble()
    
    for (i in seq_len(n_bins)) {
      bin_start <- bin_edges[i]
      bin_end <- bin_edges[i + 1]
      bin_center <- bin_centers[i]
      
      # Include right edge only for last bin
      if (i == n_bins) {
        bin_data <- filter(data, predicted_confidence >= bin_start & predicted_confidence <= bin_end)
      } else {
        bin_data <- filter(data, predicted_confidence >= bin_start & predicted_confidence < bin_end)
      }
      
      if (nrow(bin_data) > 0) {
        correct_preds <- sum(bin_data$predicted_ipv == bin_data$actual_ipv)
        accuracy_in_bin <- correct_preds / nrow(bin_data)
        avg_confidence <- mean(bin_data$predicted_confidence)
        calibration_error <- abs(accuracy_in_bin - bin_center)
        
        calibration_data <- bind_rows(calibration_data, tibble(
          calibration_id = paste0(run_id, "_", nt, "_bin", i),
          run_id = run_id,
          confidence_bin_start = bin_start,
          confidence_bin_end = bin_end,
          bin_center = bin_center,
          prediction_count = nrow(bin_data),
          correct_predictions = correct_preds,
          accuracy_in_bin = accuracy_in_bin,
          avg_confidence_in_bin = avg_confidence,
          calibration_error = calibration_error,
          narrative_type = nt,
          calculated_timestamp = as.integer(Sys.time())
        ))
      }
    }
    
    # Store calibration data
    if (nrow(calibration_data) > 0) {
      DBI::dbExecute(conn, "DELETE FROM confidence_calibration WHERE run_id = ? AND narrative_type = ?", 
                     params = list(run_id, nt))
      
      for (i in seq_len(nrow(calibration_data))) {
        row <- calibration_data[i, ]
        DBI::dbExecute(conn, "
          INSERT INTO confidence_calibration VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ", params = as.list(row))
      }
    }
  }
  
  cli::cli_alert_success("Calculated confidence calibration for run {run_id}")
}

#' Complete Test Run
#' 
#' @param conn Database connection
#' @param run_id Test run identifier
#' @param status Final status ('completed', 'failed', 'cancelled')
#' @export
complete_test_run <- function(conn, run_id, status = "completed") {
  
  # Get run start time
  run_info <- DBI::dbGetQuery(conn, "
    SELECT run_timestamp FROM test_runs WHERE run_id = ?
  ", params = list(run_id))
  
  if (nrow(run_info) == 0) {
    stop("Test run not found: ", run_id)
  }
  
  start_time <- run_info$run_timestamp[1]
  total_time_ms <- (as.integer(Sys.time()) - start_time) * 1000
  
  DBI::dbExecute(conn, "
    UPDATE test_runs 
    SET status = ?, completed_timestamp = ?, total_processing_time_ms = ?
    WHERE run_id = ?
  ", params = list(status, as.integer(Sys.time()), total_time_ms, run_id))
  
  cli::cli_alert_success("Test run {run_id} completed with status: {status}")
}

#' Run Complete IPV Detection Test
#' 
#' @param test_data Data frame with test cases
#' @param config Configuration for detection
#' @param run_name Name for this test run
#' @param conn Database connection (optional)
#' @return Test results
#' @export
run_ipv_detection_test <- function(test_data, config, run_name, conn = NULL) {
  
  # Initialize database if not provided
  manage_conn <- FALSE
  if (is.null(conn)) {
    conn <- init_test_database()
    manage_conn <- TRUE
    on.exit({
      if (manage_conn) DBI::dbDisconnect(conn)
    })
  }
  
  # Create prompt version if needed
  prompt_version_id <- ensure_prompt_version(conn, config)
  
  # Create test run
  run_id <- create_test_run(
    conn = conn,
    run_name = run_name,
    prompt_version_id = prompt_version_id,
    model_name = config$api$model %||% "unknown",
    test_set_size = nrow(test_data)
  )
  
  tryCatch({
    
    # Process test data
    cli::cli_alert_info("Processing {nrow(test_data)} test cases...")
    
    results <- test_data %>%
      rowwise() %>%
      mutate(
        # Process LE narratives
        le_result = if (!is.na(NarrativeLE) && trimws(NarrativeLE) != "") {
          list(nvdrsipvdetector::detect_ipv(NarrativeLE, "LE", config, conn, log_to_db = FALSE))
        } else {
          list(list(ipv_detected = NA, confidence = NA, indicators = character(), rationale = "No LE narrative"))
        },
        # Process CME narratives  
        cme_result = if (!is.na(NarrativeCME) && trimws(NarrativeCME) != "") {
          list(nvdrsipvdetector::detect_ipv(NarrativeCME, "CME", config, conn, log_to_db = FALSE))
        } else {
          list(list(ipv_detected = NA, confidence = NA, indicators = character(), rationale = "No CME narrative"))
        }
      ) %>%
      ungroup()
    
    # Prepare results for storage
    le_results <- results %>%
      filter(!is.na(map_lgl(le_result, ~ !is.na(.x$ipv_detected)))) %>%
      transmute(
        incident_id = IncidentID,
        narrative_type = "LE",
        predicted_ipv = map_lgl(le_result, ~ .x$ipv_detected %||% NA),
        predicted_confidence = map_dbl(le_result, ~ .x$confidence %||% NA),
        actual_ipv = ipv_flag_LE,
        indicators = map(le_result, ~ .x$indicators %||% character()),
        rationale = map_chr(le_result, ~ .x$rationale %||% "")
      )
    
    cme_results <- results %>%
      filter(!is.na(map_lgl(cme_result, ~ !is.na(.x$ipv_detected)))) %>%
      transmute(
        incident_id = IncidentID,
        narrative_type = "CME", 
        predicted_ipv = map_lgl(cme_result, ~ .x$ipv_detected %||% NA),
        predicted_confidence = map_dbl(cme_result, ~ .x$confidence %||% NA),
        actual_ipv = ipv_flag_CME,
        indicators = map(cme_result, ~ .x$indicators %||% character()),
        rationale = map_chr(cme_result, ~ .x$rationale %||% "")
      )
    
    all_results <- bind_rows(le_results, cme_results)
    
    # Record results
    record_test_results(conn, run_id, all_results)
    
    # Calculate metrics
    calculate_performance_metrics(conn, run_id, c("LE", "CME", "combined"))
    
    # Analyze confidence calibration
    analyze_confidence_calibration(conn, run_id)
    
    # Complete test run
    complete_test_run(conn, run_id, "completed")
    
    return(list(
      run_id = run_id,
      results = all_results,
      summary = get_test_summary(conn, run_id)
    ))
    
  }, error = function(e) {
    cli::cli_alert_danger("Test run failed: {e$message}")
    complete_test_run(conn, run_id, "failed")
    stop(e)
  })
}

#' Get Test Run Summary
#' 
#' @param conn Database connection
#' @param run_id Test run identifier
#' @return Summary tibble
#' @export
get_test_summary <- function(conn, run_id) {
  DBI::dbGetQuery(conn, "
    SELECT * FROM test_run_summary WHERE run_id = ?
  ", params = list(run_id)) %>%
    as_tibble()
}

#' Ensure Prompt Version Exists
#' 
#' @param conn Database connection
#' @param config Configuration object
#' @return Prompt version ID
ensure_prompt_version <- function(conn, config) {
  
  # Create a simple version based on config hash
  config_str <- jsonlite::toJSON(config, auto_unbox = TRUE, pretty = TRUE)
  version_hash <- digest::digest(config_str, algo = "md5", serialize = FALSE)[1:8]
  version_id <- paste0("v_", format(Sys.time(), "%Y%m%d"), "_", version_hash)
  
  # Check if version exists
  existing <- DBI::dbGetQuery(conn, "
    SELECT version_id FROM prompt_versions WHERE version_id = ?
  ", params = list(version_id))
  
  if (nrow(existing) == 0) {
    # Create new version
    DBI::dbExecute(conn, "
      INSERT INTO prompt_versions (
        version_id, version_name, version_number, prompt_type, 
        prompt_text, weights, created_timestamp, is_active
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      version_id,
      paste("Auto-generated", format(Sys.time(), "%Y-%m-%d %H:%M")),
      "1.0.0-auto",
      "combined",
      "Auto-generated from config",
      jsonlite::toJSON(config$weights %||% list(), auto_unbox = TRUE),
      as.integer(Sys.time()),
      TRUE
    ))
  }
  
  return(version_id)
}