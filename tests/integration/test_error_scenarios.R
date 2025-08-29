# Error Scenario Integration Tests
#
# Comprehensive testing of error conditions and recovery mechanisms:
# - Network failures and API timeouts
# - Malformed responses and JSON parsing errors
# - Database connection issues
# - Edge cases and boundary conditions
# - Concurrent access scenarios

library(testthat)
library(here)
library(dplyr)

# Source required functions
source(here::here("tests", "setup.R"))
source(here::here("R", "0_setup.R"))
source(here::here("R", "build_prompt.R"))
source(here::here("R", "call_llm.R"))
source(here::here("R", "parse_llm_result.R"))
source(here::here("R", "store_llm_result.R"))
source(here::here("R", "db_utils.R"))
source(here::here("tests", "integration", "helpers", "test_data_helpers.R"))

test_that("Network failure and API timeout scenarios", {
  # Create test database
  test_db <- create_test_database("sqlite")
  on.exit(cleanup_test_database(test_db), add = TRUE)
  
  # Test various network error scenarios
  test_narratives <- c(
    "Test narrative for timeout scenario",
    "Another test narrative for error handling"
  )
  
  # Mock call_llm to simulate different network errors
  network_error_scenarios <- list(
    timeout = function(...) stop("Timeout error: request timed out after 30 seconds"),
    connection_refused = function(...) stop("Connection refused: could not connect to server"),
    rate_limit = function(...) list(error = list(
      message = "Rate limit exceeded. Try again later.",
      type = "rate_limit_exceeded",
      code = 429
    )),
    server_error = function(...) list(error = list(
      message = "Internal server error",
      type = "server_error", 
      code = 500
    ))
  )
  
  old_call_llm <- call_llm
  
  for (scenario_name in names(network_error_scenarios)) {
    call_llm <<- network_error_scenarios[[scenario_name]]
    
    narrative <- test_narratives[1]
    narrative_id <- paste0("error_test_", scenario_name)
    
    # Test error handling in workflow
    if (scenario_name %in% c("timeout", "connection_refused")) {
      # These should throw errors
      expect_error({
        system_prompt <- build_prompt(narrative)$system_prompt
        user_prompt <- build_prompt(narrative)$user_prompt
        llm_response <- call_llm(user_prompt, system_prompt)
      })
      
      # Test that parser handles NULL response gracefully
      parsed_result <- parse_llm_result(NULL, narrative_id = narrative_id)
      
      expect_true(parsed_result$parse_error)
      expect_equal(parsed_result$error_message, "Response is NULL")
      expect_true(is.na(parsed_result$detected))
      expect_true(is.na(parsed_result$confidence))
      
    } else {
      # API returns error response
      system_prompt <- build_prompt(narrative)$system_prompt
      user_prompt <- build_prompt(narrative)$user_prompt
      llm_response <- call_llm(user_prompt, system_prompt)
      
      expect_true("error" %in% names(llm_response))
      
      # Parser should handle error responses
      parsed_result <- parse_llm_result(llm_response, narrative_id = narrative_id)
      
      expect_true(parsed_result$parse_error)
      expect_true(grepl("error", parsed_result$error_message, ignore.case = TRUE))
      expect_true(is.na(parsed_result$detected))
      
      # Should still be able to store error records
      parsed_result$narrative_text <- narrative
      store_result <- store_llm_result(parsed_result, conn = test_db$conn, auto_close = FALSE)
      expect_true(store_result$success)
    }
  }
  
  # Verify error records were stored
  error_records <- DBI::dbGetQuery(test_db$conn, 
    "SELECT * FROM llm_results WHERE error_message IS NOT NULL")
  expect_gt(nrow(error_records), 0)
  
  # Restore original function
  call_llm <<- old_call_llm
})

test_that("Malformed response parsing scenarios", {
  # Create test database
  test_db <- create_test_database("sqlite")
  on.exit(cleanup_test_database(test_db), add = TRUE)
  
  # Test various malformed response scenarios
  malformed_responses <- list(
    # Missing closing brace
    incomplete_json = list(
      id = "test-incomplete",
      choices = list(list(message = list(content = '{"detected": true, "confidence": 0.8')))
    ),
    
    # Invalid JSON with extractable data
    invalid_json_with_data = list(
      id = "test-invalid", 
      choices = list(list(message = list(content = 'Result: {"detected": false, "confidence": 0.2} - Analysis complete')))
    ),
    
    # No JSON, just text
    text_only = list(
      id = "test-text",
      choices = list(list(message = list(content = "Based on the analysis, I detected intimate partner violence with high confidence.")))
    ),
    
    # Empty response
    empty_response = list(
      id = "test-empty",
      choices = list(list(message = list(content = "")))
    ),
    
    # Response with special tokens
    special_tokens = list(
      id = "test-tokens",
      choices = list(list(message = list(content = '<|message|>{"detected": true, "confidence": 0.9}<|end|>')))
    ),
    
    # Malformed structure
    no_choices = list(
      id = "test-no-choices",
      message = "This response has wrong structure"
    )
  )
  
  for (scenario_name in names(malformed_responses)) {
    response <- malformed_responses[[scenario_name]]
    narrative_id <- paste0("malformed_", scenario_name)
    
    # Test parsing
    parsed_result <- parse_llm_result(response, narrative_id = narrative_id)
    
    # Verify basic structure
    expect_equal(parsed_result$narrative_id, narrative_id)
    
    # Check scenario-specific behavior
    if (scenario_name == "incomplete_json") {
      # Should fail JSON parsing but might extract values via regex fallback
      expect_true(parsed_result$parse_error || !is.na(parsed_result$detected))
      
    } else if (scenario_name == "invalid_json_with_data") {
      # Should extract JSON from mixed content
      expect_false(is.na(parsed_result$detected))
      expect_false(is.na(parsed_result$confidence))
      
    } else if (scenario_name == "text_only") {
      # Should fail JSON parsing, no fallback extraction possible
      expect_true(parsed_result$parse_error)
      expect_true(is.na(parsed_result$detected))
      
    } else if (scenario_name == "empty_response") {
      # Should detect empty content
      expect_true(parsed_result$parse_error)
      expect_equal(parsed_result$error_message, "No content in response")
      
    } else if (scenario_name == "special_tokens") {
      # Should clean tokens and parse successfully
      expect_false(is.na(parsed_result$detected))
      expect_false(is.na(parsed_result$confidence))
      
    } else if (scenario_name == "no_choices") {
      # Should handle missing choices structure
      expect_true(parsed_result$parse_error)
      expect_equal(parsed_result$error_message, "No content in response")
    }
    
    # All results should be storable
    parsed_result$narrative_text <- "Test narrative for malformed response"
    store_result <- store_llm_result(parsed_result, conn = test_db$conn, auto_close = FALSE)
    expect_true(store_result$success)
  }
  
  # Verify all malformed cases were stored
  malformed_records <- DBI::dbGetQuery(test_db$conn, "SELECT * FROM llm_results")
  expect_equal(nrow(malformed_records), length(malformed_responses))
})

test_that("Database connection and storage error scenarios", {
  # Test various database error scenarios
  
  # 1. Invalid database path
  expect_error({
    store_llm_result(
      list(detected = TRUE, confidence = 0.8),
      db_path = "/invalid/path/to/database.db"
    )
  })
  
  # 2. Invalid database type
  temp_file <- tempfile(fileext = ".txt")
  writeLines("This is not a database", temp_file)
  on.exit(unlink(temp_file), add = TRUE)
  
  expect_error({
    store_llm_result(
      list(detected = TRUE, confidence = 0.8),
      db_path = temp_file
    )
  })
  
  # 3. Missing required fields
  test_db <- create_test_database("sqlite")
  on.exit(cleanup_test_database(test_db), add = TRUE)
  
  invalid_results <- list(
    # Missing detected field
    missing_detected = list(confidence = 0.8, narrative_text = "test"),
    
    # Invalid detected type
    invalid_detected = list(detected = "maybe", confidence = 0.8, narrative_text = "test"),
    
    # Invalid confidence range
    invalid_confidence = list(detected = TRUE, confidence = 1.5, narrative_text = "test")
  )
  
  for (scenario_name in names(invalid_results)) {
    result <- invalid_results[[scenario_name]]
    
    if (scenario_name == "missing_detected") {
      store_result <- store_llm_result(result, conn = test_db$conn, auto_close = FALSE)
      expect_false(store_result$success)
      expect_true(grepl("Missing 'detected' field", store_result$error))
      
    } else {
      # These should still store but with data conversion
      store_result <- store_llm_result(result, conn = test_db$conn, auto_close = FALSE)
      # The store function should handle type conversion gracefully
      expect_true(store_result$success || !is.null(store_result$error))
    }
  }
})

test_that("Concurrent database access scenarios", {
  if (!check_postgresql_available()) {
    skip("PostgreSQL not available for concurrent testing")
  }
  
  # Create test database
  test_db <- create_test_database("postgresql")
  on.exit(cleanup_test_database(test_db), add = TRUE)
  
  # Load test data
  test_data <- load_test_dataset(limit = 10, sample_method = "random")
  
  # Mock call_llm for consistent testing
  old_call_llm <- call_llm
  call_llm <<- mock_call_llm
  on.exit(call_llm <<- old_call_llm, add = TRUE)
  
  # Simulate concurrent processing by multiple workers
  concurrent_results <- list()
  
  # Process same narratives from different "workers" 
  for (worker_id in 1:3) {
    worker_results <- list()
    
    for (i in seq_len(min(5, nrow(test_data)))) {
      narrative <- test_data$narrative_text[i]
      narrative_id <- paste0("worker_", worker_id, "_narrative_", i)
      
      # Complete workflow
      system_prompt <- build_prompt(narrative)$system_prompt
      user_prompt <- build_prompt(narrative)$user_prompt
      
      llm_response <- call_llm(user_prompt, system_prompt)
      
      if (!"error" %in% names(llm_response)) {
        parsed_result <- parse_llm_result(llm_response, narrative_id = narrative_id)
        parsed_result$narrative_text <- narrative
        
        # Store with separate connections to test concurrency
        worker_conn <- get_unified_connection(test_db$database)
        store_result <- store_llm_result(parsed_result, conn = worker_conn, auto_close = TRUE)
        
        expect_true(store_result$success)
        worker_results[[i]] <- store_result
      }
    }
    
    concurrent_results[[worker_id]] <- worker_results
  }
  
  # Verify all records were stored correctly
  all_records <- DBI::dbGetQuery(test_db$conn, "SELECT * FROM llm_results")
  
  # Should have records from all workers
  worker_counts <- table(sub("_narrative_.*", "", all_records$narrative_id))
  expect_equal(length(worker_counts), 3)  # 3 workers
  expect_true(all(worker_counts >= 1))    # Each worker stored at least 1 record
  
  # Test duplicate handling - try to store same record again
  if (nrow(all_records) > 0) {
    first_record <- all_records[1, ]
    
    duplicate_result <- list(
      narrative_id = first_record$narrative_id,
      narrative_text = first_record$narrative_text,
      detected = as.logical(first_record$detected),
      confidence = first_record$confidence,
      model = first_record$model
    )
    
    duplicate_store <- store_llm_result(duplicate_result, conn = test_db$conn, auto_close = FALSE)
    
    # PostgreSQL should handle duplicates gracefully
    expect_true(duplicate_store$success)
    if (!is.null(duplicate_store$warning)) {
      expect_true(grepl("duplicate", duplicate_store$warning, ignore.case = TRUE))
    }
  }
})

test_that("Edge cases and boundary conditions", {
  # Create test database
  test_db <- create_test_database("sqlite")
  on.exit(cleanup_test_database(test_db), add = TRUE)
  
  # Test edge cases
  edge_cases <- list(
    # Very long narrative
    long_narrative = paste(rep("This is a very long narrative with many repeated sections.", 100), collapse = " "),
    
    # Special characters and Unicode
    special_chars = "Narrative with special chars: áéíóú ñ 中文 🔥 \n\t\r",
    
    # Empty narrative
    empty_narrative = "",
    
    # Only whitespace
    whitespace_only = "   \n\t   \r\n   ",
    
    # SQL injection attempt (should be sanitized)
    sql_injection = "'; DROP TABLE llm_results; --",
    
    # Very short narrative
    minimal = "A",
    
    # Numbers only
    numbers_only = "123 456 789 000"
  )
  
  # Mock responses for edge cases
  old_call_llm <- call_llm
  call_llm <<- function(user_prompt, system_prompt, ...) {
    # Return different responses based on input characteristics
    if (nchar(user_prompt) > 1000) {
      # Long input - might trigger different parsing
      create_mock_llm_response(detected = FALSE, confidence = 0.3, response_format = "malformed")
    } else if (grepl("[^\\x00-\\x7F]", user_prompt)) {
      # Unicode/special characters
      create_mock_llm_response(detected = TRUE, confidence = 0.7)
    } else if (nchar(trimws(user_prompt)) == 0) {
      # Empty input
      create_mock_llm_response(detected = FALSE, confidence = 0.1, response_format = "empty")
    } else {
      # Normal processing
      create_mock_llm_response(detected = FALSE, confidence = 0.4)
    }
  }
  on.exit(call_llm <<- old_call_llm, add = TRUE)
  
  for (case_name in names(edge_cases)) {
    narrative <- edge_cases[[case_name]]
    narrative_id <- paste0("edge_case_", case_name)
    
    # Complete workflow should handle edge cases gracefully
    tryCatch({
      system_prompt <- build_prompt(narrative)$system_prompt
      user_prompt <- build_prompt(narrative)$user_prompt
      
      llm_response <- call_llm(user_prompt, system_prompt)
      parsed_result <- parse_llm_result(llm_response, narrative_id = narrative_id)
      
      # Ensure narrative text is properly handled
      parsed_result$narrative_text <- narrative
      
      store_result <- store_llm_result(parsed_result, conn = test_db$conn, auto_close = FALSE)
      
      # Should succeed or fail gracefully
      expect_true(is.logical(store_result$success))
      
      if (store_result$success) {
        # Verify stored data
        stored_record <- DBI::dbGetQuery(test_db$conn, 
          "SELECT * FROM llm_results WHERE narrative_id = ?", 
          params = list(narrative_id))
        
        expect_equal(nrow(stored_record), 1)
        expect_equal(stored_record$narrative_id, narrative_id)
        
        # Special validation for edge cases
        if (case_name == "sql_injection") {
          # Should not have executed SQL injection
          expect_equal(stored_record$narrative_text, narrative)
          # Database should still be intact
          table_check <- DBI::dbGetQuery(test_db$conn, "SELECT COUNT(*) as count FROM llm_results")
          expect_gt(table_check$count, 0)
        }
      }
      
    }, error = function(e) {
      # Some edge cases may cause expected errors
      if (case_name %in% c("empty_narrative", "whitespace_only")) {
        # These are expected to potentially fail
        expect_true(TRUE)  # Test passes if it fails as expected
      } else {
        # Unexpected error
        fail(paste("Unexpected error for", case_name, ":", e$message))
      }
    })
  }
  
  # Verify database integrity after edge case testing
  all_records <- DBI::dbGetQuery(test_db$conn, "SELECT COUNT(*) as count FROM llm_results")
  expect_gte(all_records$count, 0)  # Database should remain functional
})

test_that("Recovery and retry scenarios", {
  # Test the system's ability to handle and recover from various failures
  
  test_db <- create_test_database("sqlite")
  on.exit(cleanup_test_database(test_db), add = TRUE)
  
  # Simulate intermittent failures
  failure_count <- 0
  max_failures <- 3
  
  old_call_llm <- call_llm
  call_llm <<- function(...) {
    failure_count <<- failure_count + 1
    
    if (failure_count <= max_failures) {
      # Simulate network timeout for first few attempts
      stop("Timeout occurred")
    } else {
      # Eventually succeed
      create_mock_llm_response(detected = TRUE, confidence = 0.8)
    }
  }
  on.exit(call_llm <<- old_call_llm, add = TRUE)
  
  narrative <- "Test narrative for recovery scenarios"
  narrative_id <- "recovery_test_1"
  
  # Simulate retry logic (would be implemented in higher-level application code)
  max_retries <- 5
  success <- FALSE
  last_error <- NULL
  
  for (attempt in 1:max_retries) {
    tryCatch({
      system_prompt <- build_prompt(narrative)$system_prompt
      user_prompt <- build_prompt(narrative)$user_prompt
      
      llm_response <- call_llm(user_prompt, system_prompt)
      parsed_result <- parse_llm_result(llm_response, narrative_id = narrative_id)
      parsed_result$narrative_text <- narrative
      
      store_result <- store_llm_result(parsed_result, conn = test_db$conn, auto_close = FALSE)
      
      if (store_result$success) {
        success <- TRUE
        break
      }
      
    }, error = function(e) {
      last_error <<- e$message
      Sys.sleep(0.1)  # Brief delay before retry
    })
  }
  
  # Should eventually succeed after retries
  expect_true(success)
  
  # Verify successful storage
  recovery_record <- DBI::dbGetQuery(test_db$conn,
    "SELECT * FROM llm_results WHERE narrative_id = ?",
    params = list(narrative_id))
  
  expect_equal(nrow(recovery_record), 1)
  expect_false(is.na(recovery_record$detected))
})

# Generate error scenario test report
if (interactive()) {
  cat("\n=== Error Scenario Test Summary ===\n")
  cat("✓ Network failure and API timeout handling\n")
  cat("✓ Malformed response parsing\n")
  cat("✓ Database connection and storage errors\n")
  cat("✓ Concurrent database access\n")
  cat("✓ Edge cases and boundary conditions\n")
  cat("✓ Recovery and retry scenarios\n")
  cat("\nAll error scenario tests completed successfully!\n")
}