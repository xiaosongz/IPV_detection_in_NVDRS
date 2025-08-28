#!/usr/bin/env Rscript

#' Benchmark storage performance
#' Target: >1000 inserts/second

# Load required functions
source("R/db_utils.R")
source("R/store_llm_result.R")

benchmark_storage <- function(n_records = 10000) {
  cat("Storage Performance Benchmark\n")
  cat("=============================\n")
  cat(sprintf("Testing with %d records\n\n", n_records))
  
  # Setup
  db_file <- tempfile(fileext = ".db")
  
  # Generate test data
  cat("Generating test data...\n")
  test_data <- lapply(seq_len(n_records), function(i) {
    list(
      narrative_id = sprintf("PERF%06d", i),
      narrative_text = paste(sample(letters, 100, replace = TRUE), collapse = ""),
      detected = runif(1) > 0.5,
      confidence = runif(1),
      model = sample(c("gpt-4", "gpt-3.5", "claude"), 1),
      prompt_tokens = sample(100:500, 1),
      completion_tokens = sample(50:200, 1),
      total_tokens = sample(150:700, 1),
      response_time_ms = sample(500:3000, 1),
      raw_response = sprintf('{"id": %d}', i)
    )
  })
  
  # Test 1: Individual inserts
  cat("\nTest 1: Individual inserts (first 100 records)\n")
  conn <- get_db_connection(db_file)
  ensure_schema(conn)
  
  start_time <- Sys.time()
  for (i in 1:min(100, n_records)) {
    store_llm_result(test_data[[i]], conn = conn, auto_close = FALSE)
  }
  elapsed <- as.numeric(Sys.time() - start_time, units = "secs")
  rate <- min(100, n_records) / elapsed
  
  cat(sprintf("  Time: %.3f seconds\n", elapsed))
  cat(sprintf("  Rate: %.0f inserts/second\n", rate))
  
  close_db_connection(conn)
  
  # Test 2: Batch insert (all records)
  cat(sprintf("\nTest 2: Batch insert (%d records)\n", n_records))
  unlink(db_file)  # Start fresh
  
  start_time <- Sys.time()
  result <- store_llm_results_batch(test_data, db_path = db_file)
  elapsed <- as.numeric(Sys.time() - start_time, units = "secs")
  rate <- n_records / elapsed
  
  cat(sprintf("  Time: %.3f seconds\n", elapsed))
  cat(sprintf("  Rate: %.0f inserts/second\n", rate))
  cat(sprintf("  Success rate: %.1f%%\n", result$success_rate * 100))
  
  # Performance verdict
  cat("\nPerformance Verdict:\n")
  if (rate > 1000) {
    cat(sprintf("  ✅ PASS: %.0f inserts/sec exceeds 1000/sec target\n", rate))
  } else {
    cat(sprintf("  ❌ FAIL: %.0f inserts/sec below 1000/sec target\n", rate))
  }
  
  # Test 3: Query performance
  cat("\nTest 3: Query performance\n")
  conn <- get_db_connection(db_file)
  
  queries <- list(
    "Count all" = "SELECT COUNT(*) FROM llm_results",
    "Count detected" = "SELECT COUNT(*) FROM llm_results WHERE detected = 1",
    "By narrative_id" = sprintf("SELECT * FROM llm_results WHERE narrative_id = 'PERF%06d'", 
                                sample(n_records, 1)),
    "Recent 100" = "SELECT * FROM llm_results ORDER BY created_at DESC LIMIT 100"
  )
  
  for (query_name in names(queries)) {
    start_time <- Sys.time()
    result <- DBI::dbGetQuery(conn, queries[[query_name]])
    elapsed <- as.numeric(Sys.time() - start_time, units = "secs") * 1000
    cat(sprintf("  %s: %.1f ms\n", query_name, elapsed))
  }
  
  # Database size
  file_size <- file.info(db_file)$size / 1024 / 1024
  cat(sprintf("\nDatabase size: %.2f MB\n", file_size))
  cat(sprintf("Size per record: %.0f bytes\n", file.info(db_file)$size / n_records))
  
  # Clean up
  close_db_connection(conn)
  unlink(db_file)
  
  cat("\nBenchmark complete!\n")
}

# Run benchmark if executed directly
if (!interactive() && length(commandArgs(TRUE)) == 0) {
  benchmark_storage(10000)
}