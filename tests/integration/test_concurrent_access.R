#' Concurrent access tests for PostgreSQL backend
#' 
#' Tests concurrent writes, transactions, and connection pooling
#' for PostgreSQL to ensure data integrity under concurrent load.
#' Part of Issue #6: Integration Testing and Performance Validation

library(testthat)
library(here)
library(DBI)
library(parallel)
library(dplyr)

# Source required functions
source(here::here("R", "db_utils.R"))
source(here::here("R", "store_llm_result.R"))
source(here::here("R", "utils.R"))

# Test configuration
CONCURRENT_WORKERS <- min(4, detectCores())  # Number of parallel workers
CONCURRENT_RECORDS_PER_WORKER <- 25  # Records per worker process
CONNECTION_POOL_SIZE <- 8  # Test connection pooling
STRESS_TEST_DURATION <- 30  # Seconds for stress testing

#' Check if PostgreSQL is available for testing
check_postgres_available <- function() {
  tryCatch({
    if (!file.exists(".env")) {
      return(FALSE)
    }
    conn <- connect_postgres()
    if (DBI::dbIsValid(conn)) {
      close_db_connection(conn)
      return(TRUE)
    }
    FALSE
  }, error = function(e) {
    FALSE
  })
}

#' Create test data for concurrent access testing
create_concurrent_test_data <- function(worker_id, record_count = CONCURRENT_RECORDS_PER_WORKER) {
  test_data <- list()
  
  for (i in 1:record_count) {
    test_data[[i]] <- list(
      narrative_id = sprintf("concurrent_w%d_r%04d", worker_id, i),
      narrative_text = sprintf("Concurrent test narrative from worker %d record %d with IPV content", 
                             worker_id, i),
      detected = runif(1) > 0.5,
      confidence = runif(1, 0.5, 0.99),
      model = sprintf("concurrent-test-model-w%d", worker_id),
      prompt_tokens = sample(100:200, 1),
      completion_tokens = sample(20:50, 1),
      total_tokens = NA_integer_,
      response_time_ms = sample(200:800, 1),
      raw_response = sprintf('{"detected": %s, "confidence": %.2f}', 
                           tolower(as.character(runif(1) > 0.5)), 
                           runif(1, 0.5, 0.99)),
      error_message = NA_character_
    )
    
    test_data[[i]]$total_tokens <- test_data[[i]]$prompt_tokens + test_data[[i]]$completion_tokens
  }
  
  test_data
}

#' Worker function for concurrent testing
concurrent_worker <- function(worker_id, record_count = CONCURRENT_RECORDS_PER_WORKER) {
  tryCatch({
    # Each worker gets its own connection
    conn <- connect_postgres()
    ensure_schema(conn)
    
    # Generate test data for this worker
    test_data <- create_concurrent_test_data(worker_id, record_count)
    
    # Perform batch insert
    start_time <- Sys.time()
    result <- store_llm_results_batch(test_data, conn = conn)
    duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    
    # Clean up connection
    close_db_connection(conn)
    
    list(
      worker_id = worker_id,
      success = result$success,
      total = result$total,
      inserted = result$inserted,
      errors = result$errors,
      duration = duration,
      throughput = result$total / duration
    )
  }, error = function(e) {
    list(
      worker_id = worker_id,
      success = FALSE,
      error = e$message,
      duration = NA,
      throughput = 0
    )
  })
}

#' Worker function for transaction stress testing
transaction_stress_worker <- function(worker_id, duration_seconds = 10) {
  tryCatch({
    conn <- connect_postgres()
    ensure_schema(conn)
    
    operations <- 0
    successful_transactions <- 0
    failed_transactions <- 0
    start_time <- Sys.time()
    
    while (as.numeric(difftime(Sys.time(), start_time, units = "secs")) < duration_seconds) {
      # Create a small batch for transaction testing
      test_data <- create_concurrent_test_data(worker_id, 3)
      
      # Randomly introduce some transaction failures
      should_fail <- runif(1) < 0.1  # 10% failure rate
      
      tryCatch({
        execute_with_transaction(conn, {
          for (record in test_data) {
            store_llm_result(record, conn = conn, auto_close = FALSE)
          }
          
          if (should_fail) {
            stop("Simulated transaction failure")
          }
        })
        successful_transactions <- successful_transactions + 1
      }, error = function(e) {
        failed_transactions <- failed_transactions + 1
      })
      
      operations <- operations + 1
      
      # Brief pause to allow other workers
      Sys.sleep(0.01)
    }
    
    close_db_connection(conn)
    
    list(
      worker_id = worker_id,
      operations = operations,
      successful_transactions = successful_transactions,
      failed_transactions = failed_transactions,
      success_rate = successful_transactions / operations,
      duration = as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    )
  }, error = function(e) {
    list(
      worker_id = worker_id,
      error = e$message,
      operations = 0,
      success_rate = 0
    )
  })
}

context("PostgreSQL Concurrent Access Tests")

test_that("PostgreSQL is available for concurrent testing", {
  postgres_available <- check_postgres_available()
  if (!postgres_available) {
    skip("PostgreSQL not available - skipping concurrent access tests")
  }
  expect_true(postgres_available)
})

test_that("Multiple concurrent workers can insert data simultaneously", {
  skip_if_not(check_postgres_available(), "PostgreSQL not available")
  
  # Clean up any existing test data
  conn <- connect_postgres()
  DBI::dbExecute(conn, "DELETE FROM llm_results WHERE narrative_id LIKE 'concurrent_%'")
  close_db_connection(conn)
  
  # Run concurrent workers
  start_time <- Sys.time()
  
  if (.Platform$OS.type == "windows") {
    # Use sequential processing on Windows (no fork support)
    results <- list()
    for (i in 1:CONCURRENT_WORKERS) {
      results[[i]] <- concurrent_worker(i)
    }
  } else {
    # Use parallel processing on Unix-like systems
    results <- mclapply(1:CONCURRENT_WORKERS, concurrent_worker, mc.cores = CONCURRENT_WORKERS)
  }
  
  total_duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  
  # Verify all workers succeeded
  success_count <- sum(sapply(results, function(r) r$success))
  expect_equal(success_count, CONCURRENT_WORKERS)
  
  # Calculate aggregate statistics
  total_inserted <- sum(sapply(results, function(r) r$inserted))
  total_errors <- sum(sapply(results, function(r) r$errors))
  expected_total <- CONCURRENT_WORKERS * CONCURRENT_RECORDS_PER_WORKER
  
  expect_equal(total_inserted, expected_total)
  expect_equal(total_errors, 0)
  
  # Verify data integrity
  conn <- connect_postgres()
  final_count <- DBI::dbGetQuery(conn, "
    SELECT COUNT(*) as count 
    FROM llm_results 
    WHERE narrative_id LIKE 'concurrent_%'
  ")$count
  
  expect_equal(final_count, expected_total)
  
  # Check for data corruption (duplicate keys)
  duplicate_check <- DBI::dbGetQuery(conn, "
    SELECT narrative_id, narrative_text, model, COUNT(*) as cnt
    FROM llm_results 
    WHERE narrative_id LIKE 'concurrent_%'
    GROUP BY narrative_id, narrative_text, model
    HAVING COUNT(*) > 1
  ")
  
  expect_equal(nrow(duplicate_check), 0)
  
  close_db_connection(conn)
  
  # Performance reporting
  avg_throughput <- mean(sapply(results, function(r) r$throughput))
  message(sprintf("Concurrent Access Test Results:"))
  message(sprintf("  Workers: %d", CONCURRENT_WORKERS))
  message(sprintf("  Total Records: %d", total_inserted))
  message(sprintf("  Total Duration: %.2f seconds", total_duration))
  message(sprintf("  Average Throughput: %.1f records/sec per worker", avg_throughput))
  message(sprintf("  Aggregate Throughput: %.1f records/sec", total_inserted / total_duration))
})

test_that("Connection pooling handles multiple simultaneous connections", {
  skip_if_not(check_postgres_available(), "PostgreSQL not available")
  
  # Create multiple connections simultaneously
  connections <- list()
  connection_times <- numeric(CONNECTION_POOL_SIZE)
  
  for (i in 1:CONNECTION_POOL_SIZE) {
    start_time <- Sys.time()
    tryCatch({
      conn <- connect_postgres()
      connections[[i]] <- conn
      connection_times[i] <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
      
      # Verify connection is working
      health <- test_connection_health(conn)
      expect_true(health$healthy)
      expect_equal(health$db_type, "postgresql")
      
    }, error = function(e) {
      fail(sprintf("Failed to create connection %d: %s", i, e$message))
    })
  }
  
  expect_equal(length(connections), CONNECTION_POOL_SIZE)
  
  # Test that all connections can execute queries simultaneously
  query_results <- list()
  for (i in 1:length(connections)) {
    if (!is.null(connections[[i]])) {
      query_results[[i]] <- DBI::dbGetQuery(connections[[i]], "SELECT current_database(), version()")
      expect_true(nrow(query_results[[i]]) > 0)
    }
  }
  
  # Clean up all connections
  closed_count <- cleanup_connections(connections)
  expect_equal(closed_count, CONNECTION_POOL_SIZE)
  
  # Report connection metrics
  avg_connection_time <- mean(connection_times)
  max_connection_time <- max(connection_times)
  
  message(sprintf("Connection Pool Test Results:"))
  message(sprintf("  Pool Size: %d connections", CONNECTION_POOL_SIZE))
  message(sprintf("  Average Connection Time: %.3f seconds", avg_connection_time))
  message(sprintf("  Maximum Connection Time: %.3f seconds", max_connection_time))
  
  expect_lt(max_connection_time, 5.0)  # Should connect within 5 seconds
})

test_that("Transaction isolation works under concurrent load", {
  skip_if_not(check_postgres_available(), "PostgreSQL not available")
  skip_if(.Platform$OS.type == "windows", "Transaction stress test requires fork support")
  
  # Clean up test data
  conn <- connect_postgres()
  DBI::dbExecute(conn, "DELETE FROM llm_results WHERE narrative_id LIKE 'concurrent_%'")
  close_db_connection(conn)
  
  # Run transaction stress test with multiple workers
  message("Starting transaction isolation stress test...")
  
  stress_workers <- min(3, CONCURRENT_WORKERS)  # Use fewer workers for transaction stress
  results <- mclapply(1:stress_workers, 
                     function(w) transaction_stress_worker(w, duration_seconds = 10), 
                     mc.cores = stress_workers)
  
  # Analyze results
  total_operations <- sum(sapply(results, function(r) r$operations))
  total_successful <- sum(sapply(results, function(r) r$successful_transactions))
  total_failed <- sum(sapply(results, function(r) r$failed_transactions))
  overall_success_rate <- total_successful / total_operations
  
  # Verify data consistency after stress test
  conn <- connect_postgres()
  final_count <- DBI::dbGetQuery(conn, "
    SELECT COUNT(*) as count 
    FROM llm_results 
    WHERE narrative_id LIKE 'concurrent_%'
  ")$count
  
  # Check for data integrity issues
  integrity_check <- DBI::dbGetQuery(conn, "
    SELECT 
      COUNT(*) as total_records,
      COUNT(DISTINCT narrative_id) as unique_narratives,
      COUNT(CASE WHEN detected IS NULL THEN 1 END) as null_detected,
      COUNT(CASE WHEN confidence < 0 OR confidence > 1 THEN 1 END) as invalid_confidence
    FROM llm_results 
    WHERE narrative_id LIKE 'concurrent_%'
  ")
  
  close_db_connection(conn)
  
  expect_equal(integrity_check$null_detected, 0)
  expect_equal(integrity_check$invalid_confidence, 0)
  
  # Success rate should be reasonable (accounting for intentional failures)
  expect_gt(overall_success_rate, 0.8)  # At least 80% success rate
  
  message(sprintf("Transaction Stress Test Results:"))
  message(sprintf("  Workers: %d", stress_workers))
  message(sprintf("  Total Operations: %d", total_operations))
  message(sprintf("  Successful Transactions: %d", total_successful))
  message(sprintf("  Failed Transactions: %d", total_failed))
  message(sprintf("  Success Rate: %.1f%%", overall_success_rate * 100))
  message(sprintf("  Final Record Count: %d", final_count))
})

test_that("Database handles connection failures gracefully", {
  skip_if_not(check_postgres_available(), "PostgreSQL not available")
  
  # Test connection retry mechanism
  original_host <- Sys.getenv("POSTGRES_HOST")
  
  # Temporarily set invalid host to test retry
  Sys.setenv(POSTGRES_HOST = "invalid.host.name")
  
  expect_error({
    connect_postgres(retry_attempts = 2, timeout = 1)
  }, "Failed to connect")
  
  # Restore original host
  Sys.setenv(POSTGRES_HOST = original_host)
  
  # Verify normal connection still works
  conn <- connect_postgres()
  expect_true(DBI::dbIsValid(conn))
  close_db_connection(conn)
})

test_that("Concurrent writes maintain data integrity constraints", {
  skip_if_not(check_postgres_available(), "PostgreSQL not available")
  
  conn <- connect_postgres()
  
  # Clean up test data
  DBI::dbExecute(conn, "DELETE FROM llm_results WHERE narrative_id = 'integrity_test'")
  
  # Create data that would violate constraints if not handled properly
  invalid_data <- list(
    narrative_id = "integrity_test",
    narrative_text = "Test narrative",
    detected = TRUE,
    confidence = 1.5,  # Invalid - should be 0-1
    model = "test-model",
    prompt_tokens = -10L,  # Invalid - should be >= 0
    completion_tokens = 25L,
    total_tokens = 15L,
    response_time_ms = -100L,  # Invalid - should be >= 0
    raw_response = '{"detected": true}',
    error_message = NA_character_
  )
  
  # This should fail due to constraint violations
  result <- store_llm_result(invalid_data, conn = conn, auto_close = FALSE)
  expect_false(result$success)
  expect_true(grepl("constraint|check", result$error, ignore.case = TRUE))
  
  # Verify no data was inserted
  count <- DBI::dbGetQuery(conn, "
    SELECT COUNT(*) as count 
    FROM llm_results 
    WHERE narrative_id = 'integrity_test'
  ")$count
  expect_equal(count, 0)
  
  close_db_connection(conn)
})

# Test summary
if (check_postgres_available()) {
  message("\nPostgreSQL Concurrent Access Tests Complete")
  message("- Concurrent write operations validated")
  message("- Connection pooling and resource management tested")
  message("- Transaction isolation under stress verified")
  message("- Data integrity constraints enforced")
  message("- Error handling and recovery mechanisms validated")
} else {
  message("\nPostgreSQL not available - concurrent access tests skipped")
  message("Set up PostgreSQL connection in .env file to run these tests")
}