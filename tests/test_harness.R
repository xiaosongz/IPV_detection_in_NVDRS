#!/usr/bin/env Rscript

#' IPV Detection Test Harness
#'
#' @description Comprehensive test harness for batch processing and optimization
#' @author Test Framework

# Load required libraries
library(nvdrsipvdetector)
library(tibble)
library(dplyr)
library(cli)
library(purrr)

#' Run Comprehensive Test
#'
#' @description Runs a complete test cycle on sample data
#' @param data_path Path to test data CSV
#' @param config_path Path to configuration file
#' @param prompt_version Version identifier for the prompt
#' @param description Test run description
#' @param test_db_path Path to test tracking database
#' @return Test run results
run_comprehensive_test <- function(
  data_path = "tests/test_data/test_sample.csv",
  config_path = NULL,
  prompt_version = "v1.0",
  description = NULL,
  test_db_path = "logs/test_tracking.sqlite"
) {
  
  cli::cli_h1("IPV Detection Comprehensive Test")
  cli::cli_alert_info("Starting test run at {Sys.time()}")
  
  # Load configuration
  cli::cli_h2("Loading Configuration")
  config <- if (is.null(config_path)) {
    load_config()
  } else {
    load_config(config_path)
  }
  cli::cli_alert_success("Configuration loaded")
  
  # Load test data
  cli::cli_h2("Loading Test Data")
  test_data <- read.csv(data_path, stringsAsFactors = FALSE)
  cli::cli_alert_success("Loaded {nrow(test_data)} test cases")
  
  # Validate data
  required_cols <- c("IncidentID", "NarrativeLE", "NarrativeCME", 
                     "ipv_flag_LE", "ipv_flag_CME")
  missing_cols <- setdiff(required_cols, names(test_data))
  if (length(missing_cols) > 0) {
    stop(paste("Missing required columns:", paste(missing_cols, collapse = ", ")))
  }
  
  # Initialize databases
  cli::cli_h2("Initializing Databases")
  
  # Main API logging database
  api_conn <- init_database(config$database$path)
  on.exit(DBI::dbDisconnect(api_conn), add = TRUE)
  
  # Test tracking database
  test_conn <- init_test_database(test_db_path)
  on.exit(DBI::dbDisconnect(test_conn), add = TRUE)
  
  cli::cli_alert_success("Databases initialized")
  
  # Create test run
  cli::cli_h2("Creating Test Run")
  run_id <- create_test_run(
    conn = test_conn,
    prompt_version = prompt_version,
    model_name = config$api$model,
    description = description %||% paste("Comprehensive test on", Sys.Date()),
    config = config
  )
  
  # Process each case
  cli::cli_h2("Processing Test Cases")
  pb <- cli::cli_progress_bar("Processing cases", total = nrow(test_data))
  
  results_list <- list()
  
  for (i in seq_len(nrow(test_data))) {
    case <- test_data[i, ]
    cli::cli_progress_update(id = pb)
    
    # Process LE narrative
    le_start <- Sys.time()
    le_result <- tryCatch({
      detect_ipv(
        narrative = case$NarrativeLE,
        type = "LE",
        config = config,
        conn = api_conn,
        log_to_db = TRUE
      )
    }, error = function(e) {
      list(
        ipv_detected = NA,
        confidence = NA,
        indicators = list(),
        rationale = paste("Error:", e$message),
        success = FALSE,
        error = e$message
      )
    })
    le_time <- as.numeric(difftime(Sys.time(), le_start, units = "secs")) * 1000
    
    # Log LE result
    log_classification_result(
      conn = test_conn,
      run_id = run_id,
      incident_id = case$IncidentID,
      predicted = le_result,
      actual = case$ipv_flag_LE,
      narrative_type = "LE",
      processing_time_ms = le_time
    )
    
    # Process CME narrative
    cme_start <- Sys.time()
    cme_result <- tryCatch({
      detect_ipv(
        narrative = case$NarrativeCME,
        type = "CME",
        config = config,
        conn = api_conn,
        log_to_db = TRUE
      )
    }, error = function(e) {
      list(
        ipv_detected = NA,
        confidence = NA,
        indicators = list(),
        rationale = paste("Error:", e$message),
        success = FALSE,
        error = e$message
      )
    })
    cme_time <- as.numeric(difftime(Sys.time(), cme_start, units = "secs")) * 1000
    
    # Log CME result
    log_classification_result(
      conn = test_conn,
      run_id = run_id,
      incident_id = case$IncidentID,
      predicted = cme_result,
      actual = case$ipv_flag_CME,
      narrative_type = "CME",
      processing_time_ms = cme_time
    )
    
    # Combine results using reconciliation
    combined_result <- list(
      le_ipv = le_result$ipv_detected,
      le_confidence = le_result$confidence,
      cme_ipv = cme_result$ipv_detected,
      cme_confidence = cme_result$confidence
    )
    
    # Apply reconciliation logic
    if (!is.na(combined_result$le_ipv) || !is.na(combined_result$cme_ipv)) {
      if (is.na(combined_result$le_ipv)) {
        combined_confidence <- combined_result$cme_confidence
        combined_ipv <- combined_result$cme_ipv
      } else if (is.na(combined_result$cme_ipv)) {
        combined_confidence <- combined_result$le_confidence
        combined_ipv <- combined_result$le_ipv
      } else {
        # Weighted average
        combined_confidence <- (combined_result$le_confidence * config$weights$le + 
                              combined_result$cme_confidence * config$weights$cme)
        combined_ipv <- combined_confidence >= config$weights$threshold
      }
      
      # Log combined result
      log_classification_result(
        conn = test_conn,
        run_id = run_id,
        incident_id = case$IncidentID,
        predicted = list(
          ipv_detected = combined_ipv,
          confidence = combined_confidence,
          indicators = c(le_result$indicators, cme_result$indicators),
          rationale = paste("Combined:", le_result$rationale, "|", cme_result$rationale),
          success = TRUE
        ),
        actual = case$ipv_flag_LE || case$ipv_flag_CME,  # Either flag indicates IPV
        narrative_type = "COMBINED",
        processing_time_ms = le_time + cme_time
      )
    }
    
    # Store results
    results_list[[i]] <- list(
      incident_id = case$IncidentID,
      le_result = le_result,
      cme_result = cme_result,
      combined_ipv = combined_ipv,
      combined_confidence = combined_confidence,
      actual_le = case$ipv_flag_LE,
      actual_cme = case$ipv_flag_CME
    )
  }
  
  cli::cli_progress_done(id = pb)
  
  # Complete test run and calculate metrics
  cli::cli_h2("Calculating Performance Metrics")
  complete_test_run(test_conn, run_id, status = "completed")
  
  # Get summary
  summary <- get_test_run_summary(test_conn, run_id)
  
  # Display results
  cli::cli_h2("Test Results Summary")
  
  if (nrow(summary$metrics) > 0) {
    for (i in seq_len(nrow(summary$metrics))) {
      metric <- summary$metrics[i, ]
      cli::cli_alert_info(
        "{metric$narrative_type}: Acc={round(metric$accuracy, 3)}, " %+%
        "Prec={round(metric$precision_score, 3)}, " %+%
        "Rec={round(metric$recall, 3)}, " %+%
        "F1={round(metric$f1_score, 3)}"
      )
    }
  }
  
  # Return results
  list(
    run_id = run_id,
    results = results_list,
    summary = summary,
    config = config
  )
}

#' Run A/B Test
#'
#' @description Runs A/B test comparing two configurations
#' @param config_a Path to configuration A
#' @param config_b Path to configuration B
#' @param data_path Path to test data
#' @param test_db_path Path to test database
#' @return Comparison results
run_ab_test <- function(
  config_a,
  config_b,
  data_path = "tests/test_data/test_sample.csv",
  test_db_path = "logs/test_tracking.sqlite"
) {
  
  cli::cli_h1("A/B Test: Configuration Comparison")
  
  # Run test with config A
  cli::cli_h2("Testing Configuration A")
  results_a <- run_comprehensive_test(
    data_path = data_path,
    config_path = config_a,
    prompt_version = "config_a",
    description = "A/B Test - Configuration A",
    test_db_path = test_db_path
  )
  
  # Run test with config B
  cli::cli_h2("Testing Configuration B")
  results_b <- run_comprehensive_test(
    data_path = data_path,
    config_path = config_b,
    prompt_version = "config_b",
    description = "A/B Test - Configuration B",
    test_db_path = test_db_path
  )
  
  # Compare results
  cli::cli_h2("Comparing Results")
  test_conn <- DBI::dbConnect(RSQLite::SQLite(), test_db_path)
  on.exit(DBI::dbDisconnect(test_conn))
  
  comparison <- compare_test_runs(
    conn = test_conn,
    run_id1 = results_a$run_id,
    run_id2 = results_b$run_id
  )
  
  # Display comparison
  if (!is.null(comparison)) {
    cli::cli_h3("Performance Comparison")
    print(comparison)
    
    if ("significant" %in% names(comparison)) {
      if (comparison$significant[1]) {
        cli::cli_alert_success("Statistically significant difference detected (p < 0.05)")
      } else {
        cli::cli_alert_info("No statistically significant difference (p >= 0.05)")
      }
    }
  }
  
  list(
    results_a = results_a,
    results_b = results_b,
    comparison = comparison
  )
}

#' Analyze Indicator Performance
#'
#' @description Analyzes which indicators are most predictive
#' @param run_id Test run identifier
#' @param test_db_path Path to test database
#' @return Indicator analysis
analyze_indicators <- function(run_id, test_db_path = "logs/test_tracking.sqlite") {
  
  cli::cli_h2("Analyzing Indicator Performance")
  
  test_conn <- DBI::dbConnect(RSQLite::SQLite(), test_db_path)
  on.exit(DBI::dbDisconnect(test_conn))
  
  # Get all results with indicators
  results <- DBI::dbGetQuery(test_conn, "
    SELECT incident_id, indicators, predicted_ipv, actual_ipv
    FROM classification_results
    WHERE run_id = ? AND indicators IS NOT NULL
  ", params = list(run_id))
  
  if (nrow(results) == 0) {
    cli::cli_alert_warning("No results with indicators found")
    return(NULL)
  }
  
  # Parse indicators and calculate frequencies
  indicator_stats <- list()
  
  for (i in seq_len(nrow(results))) {
    indicators <- tryCatch(
      jsonlite::fromJSON(results$indicators[i]),
      error = function(e) list()
    )
    
    if (length(indicators) > 0) {
      correct <- results$predicted_ipv[i] == results$actual_ipv[i]
      true_positive <- results$predicted_ipv[i] == 1 && results$actual_ipv[i] == 1
      false_positive <- results$predicted_ipv[i] == 1 && results$actual_ipv[i] == 0
      
      for (indicator in indicators) {
        if (!indicator %in% names(indicator_stats)) {
          indicator_stats[[indicator]] <- list(
            count = 0,
            correct = 0,
            true_positive = 0,
            false_positive = 0
          )
        }
        
        indicator_stats[[indicator]]$count <- indicator_stats[[indicator]]$count + 1
        if (correct) indicator_stats[[indicator]]$correct <- indicator_stats[[indicator]]$correct + 1
        if (true_positive) indicator_stats[[indicator]]$true_positive <- indicator_stats[[indicator]]$true_positive + 1
        if (false_positive) indicator_stats[[indicator]]$false_positive <- indicator_stats[[indicator]]$false_positive + 1
      }
    }
  }
  
  # Calculate predictive values
  indicator_df <- data.frame(
    indicator = names(indicator_stats),
    frequency = sapply(indicator_stats, function(x) x$count),
    accuracy = sapply(indicator_stats, function(x) x$correct / x$count),
    true_positives = sapply(indicator_stats, function(x) x$true_positive),
    false_positives = sapply(indicator_stats, function(x) x$false_positive),
    stringsAsFactors = FALSE
  )
  
  indicator_df$predictive_value <- with(indicator_df, 
    ifelse(true_positives + false_positives > 0,
           true_positives / (true_positives + false_positives),
           0)
  )
  
  # Sort by predictive value
  indicator_df <- indicator_df[order(indicator_df$predictive_value, decreasing = TRUE), ]
  
  # Store in database
  for (i in seq_len(nrow(indicator_df))) {
    DBI::dbExecute(test_conn, "
      INSERT INTO indicator_frequency 
      (run_id, indicator, frequency, true_positive_count, false_positive_count, predictive_value)
      VALUES (?, ?, ?, ?, ?, ?)
    ", params = list(
      run_id,
      indicator_df$indicator[i],
      indicator_df$frequency[i],
      indicator_df$true_positives[i],
      indicator_df$false_positives[i],
      indicator_df$predictive_value[i]
    ))
  }
  
  cli::cli_alert_success("Analyzed {nrow(indicator_df)} unique indicators")
  
  # Display top indicators
  cli::cli_h3("Top 10 Most Predictive Indicators")
  top_10 <- head(indicator_df, 10)
  print(top_10[, c("indicator", "frequency", "predictive_value", "accuracy")])
  
  return(indicator_df)
}

# Main execution
if (!interactive()) {
  cli::cli_h1("IPV Detection Test Harness")
  
  # Parse command line arguments
  args <- commandArgs(trailingOnly = TRUE)
  
  if (length(args) == 0) {
    # Run default comprehensive test
    results <- run_comprehensive_test()
    
    # Analyze indicators
    if (!is.null(results$run_id)) {
      analyze_indicators(results$run_id)
    }
  } else if (args[1] == "ab") {
    # Run A/B test
    if (length(args) < 3) {
      stop("Usage: Rscript test_harness.R ab config_a.yml config_b.yml")
    }
    run_ab_test(args[2], args[3])
  } else {
    # Run test with specified config
    results <- run_comprehensive_test(config_path = args[1])
    
    # Analyze indicators
    if (!is.null(results$run_id)) {
      analyze_indicators(results$run_id)
    }
  }
}