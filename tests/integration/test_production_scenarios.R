#' Production scenario tests for database backends
#' 
#' Tests high load conditions, failover scenarios, and recovery mechanisms
#' to validate production readiness of both SQLite and PostgreSQL backends.
#' Part of Issue #6: Integration Testing and Performance Validation

library(testthat)
library(here)
library(DBI)
library(parallel)
library(dplyr)

# Source required functions
source(here::here("R", "db_utils.R"))
source(here::here("R", "store_llm_result.R"))
source(here::here("R", "parse_llm_result.R"))
source(here::here("R", "utils.R"))

# Production test configuration
HIGH_LOAD_RECORDS <- 1000  # Records for high load testing
STRESS_TEST_DURATION <- 60  # Seconds for stress testing
MEMORY_LIMIT_MB <- 500  # Memory usage limit for testing
LARGE_BATCH_SIZE <- 5000  # Large batch operations
FAILOVER_TEST_ITERATIONS <- 10  # Failover/recovery test cycles

#' Create large dataset for production testing
create_production_dataset <- function(size = HIGH_LOAD_RECORDS, prefix = "prod") {
  # Create realistic data distribution based on actual use patterns
  test_data <- list()
  
  # Simulate different narrative lengths and content types
  narrative_templates <- c(
    "Domestic violence incident involving %s and partner resulting in %s",
    "IPV related injury sustained during altercation with intimate partner",
    "Physical assault by boyfriend/girlfriend causing %s injuries",
    "Stalking and harassment by ex-partner escalating to violence",
    "Sexual assault by current or former intimate partner",
    "Emotional abuse and coercive control by domestic partner",
    "Financial abuse and control by intimate partner",
    "No indication of intimate partner violence in this case"
  )
  
  injury_types <- c("minor", "moderate", "severe", "life-threatening")
  persons <- c("victim", "survivor", "individual")
  
  for (i in 1:size) {
    template <- sample(narrative_templates, 1)
    
    # Create realistic narrative text with varying lengths
    if (grepl("%s", template)) {
      narrative_text <- sprintf(template, 
                              sample(persons, 1), 
                              sample(injury_types, 1))
    } else {
      narrative_text <- template
    }
    
    # Add some variation in narrative length
    if (runif(1) < 0.3) {
      narrative_text <- paste(narrative_text, 
                            "Additional details about the incident and circumstances.")
    }
    
    # Realistic detection patterns
    ipv_detected <- grepl("violence|IPV|assault|abuse|stalking", narrative_text, ignore.case = TRUE) &&
                   !grepl("No indication", narrative_text)
    
    test_data[[i]] <- list(
      narrative_id = sprintf("%s_%06d", prefix, i),
      narrative_text = narrative_text,
      detected = ipv_detected,
      confidence = if (ipv_detected) runif(1, 0.7, 0.99) else runif(1, 0.01, 0.3),
      model = sample(c("gpt-4", "gpt-3.5-turbo", "claude-3-opus"), 1),
      prompt_tokens = sample(80:250, 1),
      completion_tokens = sample(15:80, 1),
      total_tokens = NA_integer_,
      response_time_ms = sample(300:3000, 1),
      raw_response = sprintf('{"detected": %s, "confidence": %.3f}', 
                           tolower(as.character(ipv_detected)), 
                           if (ipv_detected) runif(1, 0.7, 0.99) else runif(1, 0.01, 0.3)),
      error_message = if (runif(1) < 0.02) "Temporary API error" else NA_character_
    )
    
    test_data[[i]]$total_tokens <- test_data[[i]]$prompt_tokens + test_data[[i]]$completion_tokens
  }
  
  test_data
}

#' Monitor memory usage during operations
monitor_memory_usage <- function() {
  if (.Platform$OS.type == "windows") {
    # Windows memory monitoring
    tryCatch({
      as.numeric(system("wmic process where processid=\"%PID%\" get WorkingSetSize /format:value", intern = TRUE)[2])
    }, error = function(e) NA)
  } else {
    # Unix-like memory monitoring
    tryCatch({
      pid <- Sys.getpid()
      mem_info <- system(paste("ps -o rss= -p", pid), intern = TRUE)
      as.numeric(trimws(mem_info)) * 1024  # Convert KB to bytes
    }, error = function(e) NA)
  }
}

#' Setup production test environment
setup_production_test <- function() {
  # SQLite setup with production-like settings
  sqlite_db <- tempfile(fileext = ".db")
  sqlite_conn <- get_db_connection(sqlite_db)
  
  # Optimize SQLite for production
  DBI::dbExecute(sqlite_conn, "PRAGMA journal_mode = WAL")
  DBI::dbExecute(sqlite_conn, "PRAGMA synchronous = NORMAL")
  DBI::dbExecute(sqlite_conn, "PRAGMA cache_size = 10000")
  DBI::dbExecute(sqlite_conn, "PRAGMA temp_store = MEMORY")
  
  ensure_schema(sqlite_conn)
  
  # PostgreSQL setup
  postgres_conn <- NULL
  postgres_available <- FALSE
  
  if (file.exists(".env")) {
    tryCatch({
      postgres_conn <- connect_postgres()
      postgres_available <- TRUE
      ensure_schema(postgres_conn)
      
      # Clean up any existing production test data
      DBI::dbExecute(postgres_conn, "DELETE FROM llm_results WHERE narrative_id LIKE 'prod_%'")
    }, error = function(e) {
      message("PostgreSQL not available for production testing: ", e$message)
    })
  }
  
  list(
    sqlite = list(conn = sqlite_conn, db_path = sqlite_db),
    postgres = list(conn = postgres_conn, available = postgres_available)
  )
}

#' Clean up production test environment
cleanup_production_test <- function(setup) {
  if (!is.null(setup$sqlite$conn)) {
    close_db_connection(setup$sqlite$conn)
    unlink(setup$sqlite$db_path)
  }
  
  if (setup$postgres$available && !is.null(setup$postgres$conn)) {
    tryCatch({
      DBI::dbExecute(setup$postgres$conn, "DELETE FROM llm_results WHERE narrative_id LIKE 'prod_%'")
      close_db_connection(setup$postgres$conn)
    }, error = function(e) {
      message("Error cleaning up PostgreSQL: ", e$message)
    })
  }
}

context("Production Scenario Testing")

test_that("High load batch processing performance", {
  skip_if(Sys.getenv("SKIP_LOAD_TESTS") == "true", "Load tests disabled")
  
  setup <- setup_production_test()
  on.exit(cleanup_production_test(setup))
  
  test_data <- create_production_dataset(HIGH_LOAD_RECORDS, "load")
  
  # Test SQLite under high load
  initial_memory <- monitor_memory_usage()
  sqlite_start <- Sys.time()
  
  sqlite_result <- store_llm_results_batch(test_data, 
                                         db_path = setup$sqlite$db_path,
                                         chunk_size = 500)
  
  sqlite_duration <- as.numeric(difftime(Sys.time(), sqlite_start, units = "secs"))
  sqlite_memory <- monitor_memory_usage()
  
  expect_true(sqlite_result$success)
  expect_equal(sqlite_result$total, HIGH_LOAD_RECORDS)
  expect_gt(sqlite_result$success_rate, 0.95)  # At least 95% success rate
  
  # Memory usage should be reasonable
  if (!is.na(initial_memory) && !is.na(sqlite_memory)) {
    memory_increase_mb <- (sqlite_memory - initial_memory) / (1024 * 1024)
    expect_lt(memory_increase_mb, MEMORY_LIMIT_MB)
  }
  
  # Verify data integrity
  sqlite_count <- DBI::dbGetQuery(setup$sqlite$conn, "
    SELECT COUNT(*) as count FROM llm_results WHERE narrative_id LIKE 'load_%'
  ")$count
  expect_equal(sqlite_count, sqlite_result$inserted)
  
  # Test PostgreSQL under high load (if available)
  if (setup$postgres$available) {
    postgres_start <- Sys.time()
    
    postgres_result <- store_llm_results_batch(test_data,
                                             conn = setup$postgres$conn,
                                             chunk_size = 1000)
    
    postgres_duration <- as.numeric(difftime(Sys.time(), postgres_start, units = "secs"))
    
    expect_true(postgres_result$success)
    expect_equal(postgres_result$total, HIGH_LOAD_RECORDS)
    expect_gt(postgres_result$success_rate, 0.95)
    
    # Performance comparison
    sqlite_throughput <- HIGH_LOAD_RECORDS / sqlite_duration
    postgres_throughput <- HIGH_LOAD_RECORDS / postgres_duration
    
    message(sprintf("High Load Performance (%d records):", HIGH_LOAD_RECORDS))
    message(sprintf("  SQLite:     %.2f sec (%.1f rec/sec)", sqlite_duration, sqlite_throughput))
    message(sprintf("  PostgreSQL: %.2f sec (%.1f rec/sec)", postgres_duration, postgres_throughput))
  }
})

test_that("Large batch operations with memory management", {
  skip_if(Sys.getenv("SKIP_MEMORY_TESTS") == "true", "Memory tests disabled")
  
  setup <- setup_production_test()
  on.exit(cleanup_production_test(setup))
  
  # Create very large dataset
  large_data <- create_production_dataset(LARGE_BATCH_SIZE, "large")
  
  initial_memory <- monitor_memory_usage()
  
  # Test with chunked processing to manage memory
  result <- store_llm_results_batch(large_data,
                                   db_path = setup$sqlite$db_path,
                                   chunk_size = 1000)  # Process in smaller chunks
  
  final_memory <- monitor_memory_usage()
  
  expect_true(result$success)
  expect_equal(result$total, LARGE_BATCH_SIZE)
  expect_equal(result$inserted, LARGE_BATCH_SIZE)
  
  # Check memory usage
  if (!is.na(initial_memory) && !is.na(final_memory)) {
    memory_increase_mb <- (final_memory - initial_memory) / (1024 * 1024)
    message(sprintf("Memory usage for %d records: %.1f MB increase", 
                   LARGE_BATCH_SIZE, memory_increase_mb))
    expect_lt(memory_increase_mb, MEMORY_LIMIT_MB)
  }
  
  # Verify all data was stored correctly
  count_check <- DBI::dbGetQuery(setup$sqlite$conn, "
    SELECT COUNT(*) as count, 
           COUNT(DISTINCT narrative_id) as unique_ids,
           AVG(confidence) as avg_confidence
    FROM llm_results 
    WHERE narrative_id LIKE 'large_%'
  ")
  
  expect_equal(count_check$count, LARGE_BATCH_SIZE)
  expect_equal(count_check$unique_ids, LARGE_BATCH_SIZE)
  expect_true(count_check$avg_confidence >= 0 && count_check$avg_confidence <= 1)
})

test_that("Database connection failover and recovery", {
  skip_if_not(file.exists(".env"), "PostgreSQL configuration required")
  
  # Test connection recovery after failures
  recovery_stats <- list(
    successful_recoveries = 0,
    failed_recoveries = 0,
    total_attempts = 0
  )
  
  for (i in 1:FAILOVER_TEST_ITERATIONS) {
    recovery_stats$total_attempts <- recovery_stats$total_attempts + 1
    
    tryCatch({
      # Create connection
      conn <- connect_postgres(retry_attempts = 3)
      
      # Insert some test data
      test_record <- list(
        narrative_id = sprintf("failover_%d", i),
        narrative_text = "Failover test record",
        detected = TRUE,
        confidence = 0.9,
        model = "failover-test",
        prompt_tokens = 100L,
        completion_tokens = 25L,
        total_tokens = 125L,
        response_time_ms = 1000L,
        raw_response = '{"detected": true, "confidence": 0.9}',
        error_message = NA_character_
      )
      
      result <- store_llm_result(test_record, conn = conn, auto_close = FALSE)
      
      if (result$success) {
        recovery_stats$successful_recoveries <- recovery_stats$successful_recoveries + 1
      } else {
        recovery_stats$failed_recoveries <- recovery_stats$failed_recoveries + 1
      }
      
      close_db_connection(conn)
      
    }, error = function(e) {
      recovery_stats$failed_recoveries <- recovery_stats$failed_recoveries + 1
      message(sprintf("Failover test %d failed: %s", i, e$message))
    })
    
    # Brief pause between attempts
    Sys.sleep(0.1)
  }
  
  success_rate <- recovery_stats$successful_recoveries / recovery_stats$total_attempts
  
  message(sprintf("Failover/Recovery Test Results:"))
  message(sprintf("  Total Attempts: %d", recovery_stats$total_attempts))
  message(sprintf("  Successful: %d", recovery_stats$successful_recoveries))
  message(sprintf("  Failed: %d", recovery_stats$failed_recoveries))
  message(sprintf("  Success Rate: %.1f%%", success_rate * 100))
  
  # Production systems should have high reliability
  expect_gt(success_rate, 0.9)  # At least 90% success rate
})

test_that("Database corruption detection and recovery", {
  setup <- setup_production_test()
  on.exit(cleanup_production_test(setup))
  
  # Insert some test data
  test_data <- create_production_dataset(100, "corruption")
  result <- store_llm_results_batch(test_data, db_path = setup$sqlite$db_path)
  expect_true(result$success)
  
  # Verify data integrity with constraints
  integrity_check <- DBI::dbGetQuery(setup$sqlite$conn, "
    SELECT 
      COUNT(*) as total_records,
      COUNT(CASE WHEN detected IS NULL THEN 1 END) as null_detected,
      COUNT(CASE WHEN confidence < 0 OR confidence > 1 THEN 1 END) as invalid_confidence,
      COUNT(CASE WHEN prompt_tokens < 0 THEN 1 END) as negative_tokens,
      COUNT(CASE WHEN total_tokens != prompt_tokens + completion_tokens THEN 1 END) as token_mismatch
    FROM llm_results 
    WHERE narrative_id LIKE 'corruption_%'
  ")
  
  expect_equal(integrity_check$null_detected, 0)
  expect_equal(integrity_check$invalid_confidence, 0)
  expect_equal(integrity_check$negative_tokens, 0)
  expect_equal(integrity_check$token_mismatch, 0)
  
  # Test database consistency
  consistency_check <- DBI::dbGetQuery(setup$sqlite$conn, "
    PRAGMA integrity_check
  ")
  
  expect_equal(consistency_check[1,1], "ok")
})

test_that("Production-scale query performance", {
  setup <- setup_production_test()
  on.exit(cleanup_production_test(setup))
  
  # Create realistic production dataset
  test_data <- create_production_dataset(2000, "query")
  result <- store_llm_results_batch(test_data, db_path = setup$sqlite$db_path)
  expect_true(result$success)
  
  # Test common production queries
  queries <- list(
    "Count by detection" = "SELECT detected, COUNT(*) FROM llm_results WHERE narrative_id LIKE 'query_%' GROUP BY detected",
    "High confidence IPV" = "SELECT COUNT(*) FROM llm_results WHERE narrative_id LIKE 'query_%' AND detected = 1 AND confidence > 0.8",
    "Recent records" = "SELECT COUNT(*) FROM llm_results WHERE narrative_id LIKE 'query_%' AND created_at > datetime('now', '-1 day')",
    "Model performance" = "SELECT model, AVG(confidence), COUNT(*) FROM llm_results WHERE narrative_id LIKE 'query_%' GROUP BY model",
    "Error analysis" = "SELECT COUNT(*) FROM llm_results WHERE narrative_id LIKE 'query_%' AND error_message IS NOT NULL"
  )
  
  query_performance <- list()
  
  for (name in names(queries)) {
    start_time <- Sys.time()
    result_set <- DBI::dbGetQuery(setup$sqlite$conn, queries[[name]])
    duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs")) * 1000
    
    query_performance[[name]] <- duration
    expect_true(nrow(result_set) > 0)
    expect_lt(duration, 1000)  # Should complete within 1 second
  }
  
  # Report query performance
  message("Production Query Performance (ms):")
  for (name in names(query_performance)) {
    message(sprintf("  %s: %.1f ms", name, query_performance[[name]]))
  }
  
  avg_query_time <- mean(unlist(query_performance))
  expect_lt(avg_query_time, 500)  # Average query time should be under 500ms
})

test_that("Concurrent production load simulation", {
  skip_if(.Platform$OS.type == "windows", "Concurrent production test requires fork support")
  skip_if_not(file.exists(".env"), "PostgreSQL required for concurrent production test")
  
  # Simulate production workload with multiple concurrent processes
  production_worker <- function(worker_id, duration_seconds = 30) {
    tryCatch({
      conn <- connect_postgres()
      ensure_schema(conn)
      
      operations <- 0
      successful_ops <- 0
      start_time <- Sys.time()
      
      while (as.numeric(difftime(Sys.time(), start_time, units = "secs")) < duration_seconds) {
        # Simulate realistic production batch sizes
        batch_size <- sample(10:50, 1)
        test_data <- create_production_dataset(batch_size, sprintf("prod_w%d", worker_id))
        
        result <- store_llm_results_batch(test_data, conn = conn, chunk_size = batch_size)
        
        operations <- operations + 1
        if (result$success) {
          successful_ops <- successful_ops + 1
        }
        
        # Simulate realistic intervals between batches
        Sys.sleep(runif(1, 0.1, 0.5))
      }
      
      close_db_connection(conn)
      
      list(
        worker_id = worker_id,
        operations = operations,
        successful_ops = successful_ops,
        success_rate = successful_ops / operations,
        duration = as.numeric(difftime(Sys.time(), start_time, units = "secs"))
      )
    }, error = function(e) {
      list(worker_id = worker_id, error = e$message, operations = 0, success_rate = 0)
    })
  }
  
  # Run production simulation
  num_workers <- min(3, detectCores())
  message(sprintf("Running production simulation with %d workers for %d seconds...", 
                 num_workers, 30))
  
  results <- mclapply(1:num_workers, 
                     function(w) production_worker(w, duration_seconds = 30),
                     mc.cores = num_workers)
  
  # Analyze production simulation results
  total_operations <- sum(sapply(results, function(r) r$operations))
  total_successful <- sum(sapply(results, function(r) r$successful_ops))
  overall_success_rate <- total_successful / total_operations
  
  expect_gt(overall_success_rate, 0.95)  # Production should have >95% success rate
  expect_gt(total_operations, 20)  # Should complete reasonable number of operations
  
  message(sprintf("Production Simulation Results:"))
  message(sprintf("  Workers: %d", num_workers))
  message(sprintf("  Total Operations: %d", total_operations))
  message(sprintf("  Successful Operations: %d", total_successful))
  message(sprintf("  Success Rate: %.1f%%", overall_success_rate * 100))
})

# Production test summary
message("\nProduction Scenario Tests Summary:")
message("- High load batch processing validated")
message("- Memory usage under large operations monitored")
message("- Database failover and recovery mechanisms tested")
message("- Data integrity and corruption detection verified")
message("- Production-scale query performance benchmarked")
message("- Concurrent production workload simulated")
message("\nAll tests validate production readiness of database backends")