#' Integration tests for database backend validation
#' 
#' Tests both SQLite and PostgreSQL backends with identical data
#' to ensure data consistency and performance equivalence.
#' Part of Issue #6: Integration Testing and Performance Validation

library(testthat)
library(here)
library(DBI)
library(dplyr)
library(tibble)

# Source required functions
source(here::here("R", "db_utils.R"))
source(here::here("R", "store_llm_result.R"))
source(here::here("R", "parse_llm_result.R"))
source(here::here("R", "utils.R"))

# Test configuration
TEST_DATA_SIZE <- 100  # Number of test records
PERFORMANCE_THRESHOLD_MS <- 5000  # Max time for 100 inserts

#' Create test dataset with consistent data for both backends
create_test_dataset <- function(size = TEST_DATA_SIZE) {
  # Load sample responses if available
  sample_files <- list.files(here::here("results", "sample_responses"), 
                           pattern = "\\.rds$", full.names = TRUE)
  
  test_data <- list()
  
  for (i in 1:size) {
    # Create consistent test data
    test_data[[i]] <- list(
      narrative_id = sprintf("test_%04d", i),
      narrative_text = sprintf("Test narrative %d with IPV content involving partner violence", i),
      detected = i %% 2 == 1,  # Alternate TRUE/FALSE
      confidence = runif(1, 0.5, 0.99),
      model = "test-model-gpt-4",
      prompt_tokens = sample(100:200, 1),
      completion_tokens = sample(20:50, 1),
      total_tokens = NA_integer_,  # Will be calculated
      response_time_ms = sample(500:2000, 1),
      raw_response = sprintf('{"detected": %s, "confidence": %.2f}', 
                           tolower(as.character(i %% 2 == 1)), 
                           runif(1, 0.5, 0.99)),
      error_message = if (i %% 10 == 0) "Test error message" else NA_character_
    )
    
    # Calculate total tokens
    test_data[[i]]$total_tokens <- test_data[[i]]$prompt_tokens + test_data[[i]]$completion_tokens
  }
  
  test_data
}

#' Setup test databases (SQLite and PostgreSQL)
setup_test_databases <- function() {
  # SQLite setup
  sqlite_db <- tempfile(fileext = ".db")
  sqlite_conn <- get_db_connection(sqlite_db)
  ensure_schema(sqlite_conn)
  
  # PostgreSQL setup - skip if not available
  postgres_conn <- NULL
  postgres_available <- FALSE
  
  tryCatch({
    if (file.exists(".env")) {
      postgres_conn <- connect_postgres()
      postgres_available <- TRUE
      
      # Clean up any existing test data
      DBI::dbExecute(postgres_conn, "DELETE FROM llm_results WHERE narrative_id LIKE 'test_%'")
      
      # Ensure schema exists
      ensure_schema(postgres_conn)
    }
  }, error = function(e) {
    message("PostgreSQL not available for testing: ", e$message)
  })
  
  list(
    sqlite = list(conn = sqlite_conn, db_path = sqlite_db),
    postgres = list(conn = postgres_conn, available = postgres_available)
  )
}

#' Clean up test databases
cleanup_test_databases <- function(db_setup) {
  # Clean up SQLite
  if (!is.null(db_setup$sqlite$conn)) {
    close_db_connection(db_setup$sqlite$conn)
    unlink(db_setup$sqlite$db_path)
  }
  
  # Clean up PostgreSQL test data
  if (db_setup$postgres$available && !is.null(db_setup$postgres$conn)) {
    tryCatch({
      DBI::dbExecute(db_setup$postgres$conn, "DELETE FROM llm_results WHERE narrative_id LIKE 'test_%'")
      close_db_connection(db_setup$postgres$conn)
    }, error = function(e) {
      message("Error cleaning up PostgreSQL: ", e$message)
    })
  }
}

context("Database Backend Validation")

test_that("Both SQLite and PostgreSQL can store identical datasets", {
  db_setup <- setup_test_databases()
  on.exit(cleanup_test_databases(db_setup))
  
  test_data <- create_test_dataset(50)  # Smaller dataset for comparison
  
  # Test SQLite storage
  sqlite_start <- Sys.time()
  sqlite_results <- store_llm_results_batch(test_data, 
                                          db_path = db_setup$sqlite$db_path)
  sqlite_duration <- as.numeric(difftime(Sys.time(), sqlite_start, units = "secs"))
  
  expect_true(sqlite_results$success)
  expect_equal(sqlite_results$total, 50)
  expect_equal(sqlite_results$inserted, 50)
  expect_equal(sqlite_results$errors, 0)
  
  # Test PostgreSQL storage (if available)
  if (db_setup$postgres$available) {
    postgres_start <- Sys.time()
    postgres_results <- store_llm_results_batch(test_data,
                                              conn = db_setup$postgres$conn)
    postgres_duration <- as.numeric(difftime(Sys.time(), postgres_start, units = "secs"))
    
    expect_true(postgres_results$success)
    expect_equal(postgres_results$total, 50)
    expect_equal(postgres_results$inserted, 50)
    expect_equal(postgres_results$errors, 0)
    
    # Compare performance (PostgreSQL should be faster or comparable)
    message(sprintf("SQLite: %.3f seconds, PostgreSQL: %.3f seconds", 
                   sqlite_duration, postgres_duration))
    
    # Verify data consistency between backends
    sqlite_data <- DBI::dbGetQuery(db_setup$sqlite$conn, "
      SELECT narrative_id, detected, confidence, model
      FROM llm_results 
      WHERE narrative_id LIKE 'test_%'
      ORDER BY narrative_id
    ")
    
    postgres_data <- DBI::dbGetQuery(db_setup$postgres$conn, "
      SELECT narrative_id, detected, confidence, model
      FROM llm_results 
      WHERE narrative_id LIKE 'test_%'
      ORDER BY narrative_id
    ")
    
    expect_equal(nrow(sqlite_data), nrow(postgres_data))
    expect_equal(sqlite_data$narrative_id, postgres_data$narrative_id)
    expect_equal(sqlite_data$detected, postgres_data$detected)
    expect_equal(sqlite_data$model, postgres_data$model)
    
    # Allow small floating point differences in confidence
    expect_true(all(abs(sqlite_data$confidence - postgres_data$confidence) < 1e-10))
  } else {
    skip("PostgreSQL not available for backend comparison")
  }
})

test_that("Database schema consistency between backends", {
  db_setup <- setup_test_databases()
  on.exit(cleanup_test_databases(db_setup))
  
  # Get SQLite schema
  sqlite_fields <- DBI::dbListFields(db_setup$sqlite$conn, "llm_results")
  
  if (db_setup$postgres$available) {
    # Get PostgreSQL schema
    postgres_fields <- DBI::dbListFields(db_setup$postgres$conn, "llm_results")
    
    # Schemas should have same fields (order may differ)
    expect_setequal(sqlite_fields, postgres_fields)
    
    # Test schema versions
    sqlite_version <- get_schema_version(db_setup$sqlite$conn)
    postgres_version <- get_schema_version(db_setup$postgres$conn)
    
    # Both should start at version 0
    expect_equal(sqlite_version, 0L)
    expect_equal(postgres_version, 0L)
    
    # Test version setting
    set_schema_version(db_setup$sqlite$conn, 1L)
    set_schema_version(db_setup$postgres$conn, 1L)
    
    sqlite_version_new <- get_schema_version(db_setup$sqlite$conn)
    postgres_version_new <- get_schema_version(db_setup$postgres$conn)
    
    expect_equal(sqlite_version_new, 1L)
    expect_equal(postgres_version_new, 1L)
  } else {
    skip("PostgreSQL not available for schema comparison")
  }
})

test_that("Connection health and type detection work for both backends", {
  db_setup <- setup_test_databases()
  on.exit(cleanup_test_databases(db_setup))
  
  # Test SQLite connection health
  sqlite_health <- test_connection_health(db_setup$sqlite$conn, detailed = TRUE)
  expect_true(sqlite_health$healthy)
  expect_equal(sqlite_health$db_type, "sqlite")
  expect_true(is.numeric(sqlite_health$response_time_ms))
  expect_null(sqlite_health$error)
  expect_true(is.list(sqlite_health$query_result))
  
  if (db_setup$postgres$available) {
    # Test PostgreSQL connection health
    postgres_health <- test_connection_health(db_setup$postgres$conn, detailed = TRUE)
    expect_true(postgres_health$healthy)
    expect_equal(postgres_health$db_type, "postgresql")
    expect_true(is.numeric(postgres_health$response_time_ms))
    expect_null(postgres_health$error)
    expect_true(is.list(postgres_health$query_result))
    
    # PostgreSQL health check should include version information
    expect_true("version" %in% names(postgres_health$query_result) || 
               any(grepl("version", names(postgres_health$query_result))))
  } else {
    skip("PostgreSQL not available for health testing")
  }
})

test_that("Transaction rollback works correctly in both backends", {
  db_setup <- setup_test_databases()
  on.exit(cleanup_test_databases(db_setup))
  
  test_data <- create_test_dataset(5)
  
  # Test SQLite transaction rollback
  initial_count <- DBI::dbGetQuery(db_setup$sqlite$conn, 
                                  "SELECT COUNT(*) as count FROM llm_results")$count
  
  expect_error({
    execute_with_transaction(db_setup$sqlite$conn, {
      # Insert some data
      store_llm_result(test_data[[1]], conn = db_setup$sqlite$conn, auto_close = FALSE)
      store_llm_result(test_data[[2]], conn = db_setup$sqlite$conn, auto_close = FALSE)
      # Force an error
      stop("Simulated transaction error")
    })
  }, "Transaction failed")
  
  # Count should be unchanged due to rollback
  final_count <- DBI::dbGetQuery(db_setup$sqlite$conn, 
                                "SELECT COUNT(*) as count FROM llm_results")$count
  expect_equal(initial_count, final_count)
  
  if (db_setup$postgres$available) {
    # Test PostgreSQL transaction rollback
    initial_count_pg <- DBI::dbGetQuery(db_setup$postgres$conn, 
                                       "SELECT COUNT(*) as count FROM llm_results 
                                        WHERE narrative_id LIKE 'test_%'")$count
    
    expect_error({
      execute_with_transaction(db_setup$postgres$conn, {
        # Insert some data
        store_llm_result(test_data[[3]], conn = db_setup$postgres$conn, auto_close = FALSE)
        store_llm_result(test_data[[4]], conn = db_setup$postgres$conn, auto_close = FALSE)
        # Force an error
        stop("Simulated transaction error")
      })
    }, "Transaction failed")
    
    # Count should be unchanged due to rollback
    final_count_pg <- DBI::dbGetQuery(db_setup$postgres$conn, 
                                     "SELECT COUNT(*) as count FROM llm_results 
                                      WHERE narrative_id LIKE 'test_%'")$count
    expect_equal(initial_count_pg, final_count_pg)
  }
})

test_that("Duplicate handling is consistent between backends", {
  db_setup <- setup_test_databases()
  on.exit(cleanup_test_databases(db_setup))
  
  # Create test data with duplicate keys
  test_record <- list(
    narrative_id = "dup_test",
    narrative_text = "Duplicate test narrative",
    detected = TRUE,
    confidence = 0.95,
    model = "test-model",
    prompt_tokens = 100L,
    completion_tokens = 25L,
    total_tokens = 125L,
    response_time_ms = 1000L,
    raw_response = '{"detected": true, "confidence": 0.95}',
    error_message = NA_character_
  )
  
  # Test SQLite duplicate handling
  result1 <- store_llm_result(test_record, conn = db_setup$sqlite$conn, auto_close = FALSE)
  expect_true(result1$success)
  expect_equal(result1$rows_inserted, 1)
  
  # Insert duplicate - should be ignored
  result2 <- store_llm_result(test_record, conn = db_setup$sqlite$conn, auto_close = FALSE)
  expect_true(result2$success)
  expect_true(!is.null(result2$warning))
  expect_match(result2$warning, "duplicate")
  
  if (db_setup$postgres$available) {
    # Test PostgreSQL duplicate handling
    result3 <- store_llm_result(test_record, conn = db_setup$postgres$conn, auto_close = FALSE)
    expect_true(result3$success)
    expect_equal(result3$rows_inserted, 1)
    
    # Insert duplicate - should be ignored
    result4 <- store_llm_result(test_record, conn = db_setup$postgres$conn, auto_close = FALSE)
    expect_true(result4$success)
    expect_true(!is.null(result4$warning))
    expect_match(result4$warning, "duplicate")
    
    # Verify counts are identical
    sqlite_count <- DBI::dbGetQuery(db_setup$sqlite$conn, 
                                   "SELECT COUNT(*) as count FROM llm_results 
                                    WHERE narrative_id = 'dup_test'")$count
    postgres_count <- DBI::dbGetQuery(db_setup$postgres$conn, 
                                     "SELECT COUNT(*) as count FROM llm_results 
                                      WHERE narrative_id = 'dup_test'")$count
    expect_equal(sqlite_count, postgres_count)
    expect_equal(sqlite_count, 1)
  }
})

test_that("Performance comparison between backends", {
  skip_if(Sys.getenv("SKIP_PERFORMANCE_TESTS") == "true", "Performance tests disabled")
  
  db_setup <- setup_test_databases()
  on.exit(cleanup_test_databases(db_setup))
  
  test_data <- create_test_dataset(TEST_DATA_SIZE)
  
  # Benchmark SQLite performance
  sqlite_start <- Sys.time()
  sqlite_results <- store_llm_results_batch(test_data, 
                                          db_path = db_setup$sqlite$db_path,
                                          chunk_size = 50)
  sqlite_duration_ms <- as.numeric(difftime(Sys.time(), sqlite_start, units = "secs")) * 1000
  
  expect_true(sqlite_results$success)
  expect_lt(sqlite_duration_ms, PERFORMANCE_THRESHOLD_MS)
  
  if (db_setup$postgres$available) {
    # Benchmark PostgreSQL performance  
    postgres_start <- Sys.time()
    postgres_results <- store_llm_results_batch(test_data,
                                              conn = db_setup$postgres$conn,
                                              chunk_size = 100)
    postgres_duration_ms <- as.numeric(difftime(Sys.time(), postgres_start, units = "secs")) * 1000
    
    expect_true(postgres_results$success)
    expect_lt(postgres_duration_ms, PERFORMANCE_THRESHOLD_MS)
    
    # Calculate throughput
    sqlite_throughput <- TEST_DATA_SIZE / (sqlite_duration_ms / 1000)
    postgres_throughput <- TEST_DATA_SIZE / (postgres_duration_ms / 1000)
    
    message(sprintf("Performance Comparison (%d records):", TEST_DATA_SIZE))
    message(sprintf("  SQLite:     %.1f ms (%.1f records/sec)", 
                   sqlite_duration_ms, sqlite_throughput))
    message(sprintf("  PostgreSQL: %.1f ms (%.1f records/sec)", 
                   postgres_duration_ms, postgres_throughput))
    
    # PostgreSQL should generally be faster for batch operations
    if (postgres_duration_ms > sqlite_duration_ms * 2) {
      warning("PostgreSQL performance is significantly slower than expected")
    }
    
    # Verify data integrity after performance test
    sqlite_final_count <- DBI::dbGetQuery(db_setup$sqlite$conn, 
                                         "SELECT COUNT(*) as count FROM llm_results")$count
    postgres_final_count <- DBI::dbGetQuery(db_setup$postgres$conn, 
                                           "SELECT COUNT(*) as count FROM llm_results 
                                            WHERE narrative_id LIKE 'test_%'")$count
    
    expect_equal(sqlite_final_count, TEST_DATA_SIZE)
    expect_equal(postgres_final_count, TEST_DATA_SIZE)
  } else {
    skip("PostgreSQL not available for performance comparison")
  }
})

test_that("Database configuration validation works", {
  # Test SQLite configuration validation
  temp_dir <- tempdir()
  valid_sqlite_path <- file.path(temp_dir, "valid_test.db")
  
  validation <- validate_db_config(valid_sqlite_path, type = "sqlite")
  expect_true(validation$valid)
  expect_equal(validation$type, "sqlite")
  expect_length(validation$errors, 0)
  
  # Test invalid SQLite path
  invalid_path <- "/non/existent/directory/test.db"
  invalid_validation <- validate_db_config(invalid_path, type = "sqlite")
  expect_false(invalid_validation$valid)
  expect_gt(length(invalid_validation$errors), 0)
  
  # Test PostgreSQL configuration validation
  if (file.exists(".env")) {
    pg_validation <- validate_db_config(NULL, type = "postgresql")
    # Should be valid if .env file has proper PostgreSQL settings
    expect_true(is.logical(pg_validation$valid))
    expect_equal(pg_validation$type, "postgresql")
  }
})

# Integration test summary
message("Database Backend Validation Tests Complete")
message("- Tests validate consistency between SQLite and PostgreSQL backends")
message("- Performance benchmarking ensures both backends meet targets")
message("- Transaction integrity and error handling verified")
message("- Data consistency and duplicate handling validated")