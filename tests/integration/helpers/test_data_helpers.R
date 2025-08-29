# Test Data Management Helpers
# 
# Helper functions for managing test data, database setup, and mock responses
# for integration testing of the IPV detection workflow.

library(here)
library(testthat)
library(readxl)
library(dplyr)
library(DBI)
library(jsonlite)

# Source required R functions for database operations
suppressMessages({
  source(here::here("R", "0_setup.R"))
  source(here::here("R", "db_utils.R"))
  source(here::here("R", "utils.R"))
})

#' Load Test Dataset
#' 
#' Loads the real IPV detection test data from the Excel file
#' and prepares it for integration testing.
#' 
#' @param limit Integer. Maximum number of records to load (default: NULL for all)
#' @param sample_method Character. Sampling method: "first", "random", "balanced"
#' @return tibble with test narratives and expected results
load_test_dataset <- function(limit = NULL, sample_method = "first") {
  test_data_path <- here::here("data-raw", "suicide_IPV_manuallyflagged.xlsx")
  
  if (!file.exists(test_data_path)) {
    skip("Test dataset not found: data-raw/suicide_IPV_manuallyflagged.xlsx")
  }
  
  data <- readxl::read_excel(test_data_path)
  
  # Standardize column names and prepare for testing
  test_data <- data %>%
    dplyr::select(
      incident_id = IncidentID,
      narrative_cme = NarrativeCME,
      narrative_le = NarrativeLE,
      ipv_expected = ipv_manual,
      ipv_cme_expected = ipv_manualCME,
      ipv_le_expected = ipv_manualLE,
      reasoning = reasoning
    ) %>%
    dplyr::mutate(
      # Create combined narrative for testing (prioritize CME, fallback to LE)
      narrative_text = dplyr::coalesce(narrative_cme, narrative_le),
      # Convert expected values to logical
      ipv_expected = as.logical(ipv_expected),
      # Add row identifiers for tracking
      test_id = paste0("test_", row_number())
    ) %>%
    dplyr::filter(!is.na(narrative_text), nchar(trimws(narrative_text)) > 0)
  
  # Apply sampling if requested
  if (!is.null(limit) && limit < nrow(test_data)) {
    if (sample_method == "random") {
      test_data <- test_data %>% dplyr::slice_sample(n = limit)
    } else if (sample_method == "balanced") {
      # Try to get balanced positive/negative samples
      positive_samples <- test_data %>% 
        dplyr::filter(ipv_expected == TRUE) %>%
        dplyr::slice_head(n = ceiling(limit / 2))
      
      negative_samples <- test_data %>%
        dplyr::filter(ipv_expected == FALSE) %>%
        dplyr::slice_head(n = limit - nrow(positive_samples))
      
      test_data <- dplyr::bind_rows(positive_samples, negative_samples)
    } else {
      # Default: first N records
      test_data <- test_data %>% dplyr::slice_head(n = limit)
    }
  }
  
  test_data
}

#' Create Test Database
#' 
#' Creates a temporary test database with proper schema for integration testing.
#' 
#' @param db_type Character. "sqlite" or "postgresql"
#' @param temp_name Character. Optional custom name for temp database
#' @return Database connection
create_test_database <- function(db_type = "sqlite", temp_name = NULL) {
  if (db_type == "sqlite") {
    if (is.null(temp_name)) {
      temp_name <- paste0("test_", format(Sys.time(), "%Y%m%d_%H%M%S"), "_", 
                         sample(10000:99999, 1), ".db")
    }
    
    db_path <- file.path(tempdir(), temp_name)
    
    # Create SQLite connection and schema
    conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
    
    # Create schema
    ensure_schema(conn)
    
    return(list(conn = conn, path = db_path, type = "sqlite"))
    
  } else if (db_type == "postgresql") {
    # For PostgreSQL testing, use a test database
    # This requires PostgreSQL to be set up and running
    
    if (!check_postgresql_available()) {
      skip("PostgreSQL not available for testing")
    }
    
    test_db_name <- temp_name %||% paste0("test_ipv_", 
                                         format(Sys.time(), "%Y%m%d_%H%M%S"))
    
    # Create test database
    admin_conn <- get_postgresql_admin_connection()
    DBI::dbExecute(admin_conn, paste0("CREATE DATABASE ", test_db_name))
    DBI::dbDisconnect(admin_conn)
    
    # Connect to test database
    conn <- get_postgresql_connection(database = test_db_name)
    ensure_schema(conn)
    
    return(list(conn = conn, database = test_db_name, type = "postgresql"))
    
  } else {
    stop("Unsupported database type: ", db_type)
  }
}

#' Cleanup Test Database
#' 
#' Safely removes test database and closes connections.
#' 
#' @param test_db Test database object returned by create_test_database()
cleanup_test_database <- function(test_db) {
  if (test_db$type == "sqlite") {
    if (DBI::dbIsValid(test_db$conn)) {
      DBI::dbDisconnect(test_db$conn)
    }
    if (file.exists(test_db$path)) {
      unlink(test_db$path)
    }
  } else if (test_db$type == "postgresql") {
    if (DBI::dbIsValid(test_db$conn)) {
      DBI::dbDisconnect(test_db$conn)
    }
    # Drop test database
    tryCatch({
      admin_conn <- get_postgresql_admin_connection()
      DBI::dbExecute(admin_conn, paste0("DROP DATABASE IF EXISTS ", test_db$database))
      DBI::dbDisconnect(admin_conn)
    }, error = function(e) {
      warning("Failed to cleanup test database: ", e$message)
    })
  }
}

#' Create Mock LLM Response
#' 
#' Creates realistic mock LLM API responses for testing without API calls.
#' 
#' @param detected Logical. Whether IPV should be detected
#' @param confidence Numeric. Confidence score (0-1)
#' @param include_errors Logical. Whether to include various error scenarios
#' @param response_format Character. "json", "malformed", "empty", "error"
#' @return Mock LLM response in the same format as call_llm()
create_mock_llm_response <- function(detected = TRUE, 
                                   confidence = 0.85,
                                   include_errors = FALSE,
                                   response_format = "json") {
  
  base_response <- list(
    id = paste0("chatcmpl-test-", sample(1000000:9999999, 1)),
    object = "chat.completion",
    created = as.integer(Sys.time()),
    model = "test-model-v1",
    usage = list(
      prompt_tokens = sample(100:500, 1),
      completion_tokens = sample(20:100, 1),
      total_tokens = NULL  # Will be calculated
    ),
    choices = list()
  )
  
  # Calculate total tokens
  base_response$usage$total_tokens <- base_response$usage$prompt_tokens + 
                                     base_response$usage$completion_tokens
  
  # Create response content based on format
  if (response_format == "json") {
    content <- jsonlite::toJSON(list(
      detected = detected,
      confidence = confidence,
      reasoning = if (detected) "Evidence of intimate partner violence found" 
                 else "No clear indicators of intimate partner violence"
    ), auto_unbox = TRUE)
    
  } else if (response_format == "malformed") {
    # Simulate malformed JSON that still has extractable information
    content <- paste0('{\n  "detected": ', tolower(as.character(detected)), 
                     ',\n  "confidence": ', confidence,
                     '\n  "reasoning": "Analysis complete"\n  // missing closing brace')
    
  } else if (response_format == "empty") {
    content <- ""
    
  } else if (response_format == "error") {
    return(list(
      error = list(
        message = "API rate limit exceeded",
        type = "rate_limit_exceeded",
        code = "rate_limit"
      )
    ))
  }
  
  base_response$choices <- list(
    list(
      index = 0,
      message = list(
        role = "assistant",
        content = content
      ),
      finish_reason = "stop"
    )
  )
  
  base_response
}

#' Mock Call LLM Function
#' 
#' Replaces call_llm() during testing to avoid actual API calls.
#' Returns deterministic responses based on narrative content.
#' 
#' @param user_prompt Character. The user prompt (narrative)
#' @param system_prompt Character. System prompt (ignored in mock)
#' @param ... Additional arguments (ignored)
#' @return Mock LLM response
mock_call_llm <- function(user_prompt, system_prompt = "", ...) {
  # Add small delay to simulate API latency
  Sys.sleep(runif(1, 0.01, 0.05))
  
  # Determine response based on narrative content (simple heuristics)
  user_lower <- tolower(user_prompt)
  
  # Look for IPV indicators in the text
  ipv_indicators <- c(
    "domestic violence", "intimate partner", "boyfriend", "girlfriend",
    "husband", "wife", "partner", "relationship", "argument", "fight",
    "abuse", "violent", "threatened", "stalking", "jealous", "controlling"
  )
  
  has_indicators <- any(sapply(ipv_indicators, function(indicator) {
    grepl(indicator, user_lower, fixed = TRUE)
  }))
  
  # Simulate detection with some variability
  detected <- has_indicators && runif(1) > 0.2  # 80% accuracy for indicators
  confidence <- if (has_indicators) runif(1, 0.6, 0.95) else runif(1, 0.05, 0.4)
  
  # Occasionally return malformed responses for testing
  if (runif(1) < 0.05) {  # 5% malformed rate
    return(create_mock_llm_response(detected, confidence, response_format = "malformed"))
  }
  
  create_mock_llm_response(detected, confidence, response_format = "json")
}

#' Check PostgreSQL Availability
#' 
#' Checks if PostgreSQL is available for testing.
#' 
#' @return Logical indicating if PostgreSQL testing is possible
check_postgresql_available <- function() {
  # Check if PostgreSQL configuration exists
  config_exists <- file.exists(here::here("config", "config.yml"))
  
  if (!config_exists) {
    return(FALSE)
  }
  
  # Try to connect to PostgreSQL
  tryCatch({
    conn <- get_postgresql_admin_connection()
    DBI::dbDisconnect(conn)
    return(TRUE)
  }, error = function(e) {
    return(FALSE)
  })
}

#' Performance Timer
#' 
#' Simple utility for timing operations in tests.
#' 
#' @param expr Expression to time
#' @return List with result and elapsed time in milliseconds
time_operation <- function(expr) {
  start_time <- Sys.time()
  result <- expr
  end_time <- Sys.time()
  
  list(
    result = result,
    elapsed_ms = as.numeric(difftime(end_time, start_time, units = "secs")) * 1000
  )
}

#' Generate Performance Report
#' 
#' Creates a summary report of performance metrics from integration tests.
#' 
#' @param metrics List of performance measurements
#' @param target_file Optional file path to save report
#' @return Character string with formatted report
generate_performance_report <- function(metrics, target_file = NULL) {
  report_lines <- c(
    "# Integration Test Performance Report",
    paste("Generated:", Sys.time()),
    "",
    "## Summary Statistics",
    paste("Total operations:", length(metrics$operations)),
    paste("Average response time:", round(mean(metrics$response_times), 2), "ms"),
    paste("95th percentile:", round(quantile(metrics$response_times, 0.95), 2), "ms"),
    paste("Database operations/sec:", round(metrics$ops_per_second, 1)),
    "",
    "## Performance Targets",
    paste("✓ API response time < 2000ms:", all(metrics$response_times < 2000)),
    paste("✓ Database insert rate > 100/sec:", metrics$ops_per_second > 100),
    paste("✓ Memory usage reasonable:", metrics$memory_mb < 500),
    "",
    "## Detailed Metrics"
  )
  
  # Add detailed breakdowns if available
  if (!is.null(metrics$by_operation)) {
    for (op in names(metrics$by_operation)) {
      op_metrics <- metrics$by_operation[[op]]
      report_lines <- c(report_lines,
        paste("###", op),
        paste("  Average:", round(mean(op_metrics), 2), "ms"),
        paste("  Max:", round(max(op_metrics), 2), "ms")
      )
    }
  }
  
  report <- paste(report_lines, collapse = "\n")
  
  if (!is.null(target_file)) {
    writeLines(report, target_file)
  }
  
  report
}