# PostgreSQL Performance Benchmarking Script
# 
# Comprehensive performance testing for PostgreSQL backend
# Validates >5000 inserts/second target and provides detailed metrics

library(DBI)
library(RPostgres)
library(tibble)
library(dplyr)

# Source required functions
if (exists("connect_postgres")) {
  # Already loaded
} else if (file.exists("../../R/db_utils.R")) {
  source("../../R/db_utils.R")
  source("../../R/store_llm_result.R")
  source("../../R/utils.R")
} else {
  stop("Cannot find required R files. Run from tests/performance/ directory.")
}

#' Generate synthetic LLM results for benchmarking
#' 
#' Creates realistic test data matching actual LLM result structure.
#' Uses variety of narrative types to simulate production workload.
#' 
#' @param count Number of records to generate
#' @param unique_ratio Proportion of unique narratives (default: 0.8)
#' @return List of parsed LLM results
generate_benchmark_data <- function(count = 10000, unique_ratio = 0.8) {
  
  # Sample narrative templates for realistic variety
  narrative_templates <- c(
    "Patient experienced domestic violence from partner involving %s. Multiple injuries documented including %s.",
    "History of intimate partner violence reported. Victim sustained %s during altercation with spouse.",
    "Medical examination revealed %s consistent with physical abuse. Patient disclosed ongoing domestic violence.",
    "Emergency department visit for %s. Social worker assessment confirmed intimate partner violence.",
    "Police report indicates domestic disturbance. Victim hospitalized with %s from partner assault.",
    "Patient admitted with %s. Medical history significant for repeated episodes of domestic violence.",
    "Forensic examination documented %s. Pattern consistent with intimate partner violence over time.",
    "Social services contacted regarding %s. Investigation confirmed domestic violence in household."
  )
  
  injury_types <- c(
    "bruising and lacerations", "fractures and contusions", "head trauma",
    "abdominal injuries", "burns and cuts", "strangulation marks",
    "defensive wounds", "multiple trauma sites"
  )
  
  violence_types <- c(
    "physical assault", "strangulation", "weapon use",
    "repeated hitting", "pushing and shoving", "burning",
    "sexual assault", "psychological abuse"
  )
  
  models <- c("gpt-3.5-turbo", "gpt-4", "claude-3", "gemini-pro")
  
  # Generate unique narratives
  unique_count <- ceiling(count * unique_ratio)
  narratives <- replicate(unique_count, {
    template <- sample(narrative_templates, 1)
    violence <- sample(violence_types, 1)
    injury <- sample(injury_types, 1)
    sprintf(template, violence, injury)
  }, simplify = FALSE)
  
  # Generate results
  results <- vector("list", count)
  
  for (i in seq_len(count)) {
    # Use existing narratives for some duplicates
    narrative_idx <- if (i <= unique_count) i else sample(unique_count, 1)
    narrative <- narratives[[narrative_idx]]
    
    # Simulate realistic detection patterns
    detected <- runif(1) > 0.3  # 70% detection rate
    confidence <- if (detected) runif(1, 0.6, 0.95) else runif(1, 0.1, 0.6)
    
    results[[i]] <- list(
      narrative_id = sprintf("BENCH_%06d", i),
      narrative_text = narrative,
      detected = detected,
      confidence = confidence,
      model = sample(models, 1),
      prompt_tokens = sample(200:800, 1),
      completion_tokens = sample(50:200, 1),
      total_tokens = NA,  # Will be calculated
      response_time_ms = sample(500:2000, 1),
      raw_response = sprintf('{"detected": %s, "confidence": %.2f}', 
                           tolower(as.character(detected)), confidence),
      error_message = if (runif(1) > 0.95) "Transient error" else NA
    )
    
    # Calculate total tokens
    results[[i]]$total_tokens <- results[[i]]$prompt_tokens + results[[i]]$completion_tokens
  }
  
  results
}

#' Run comprehensive PostgreSQL performance benchmark
#' 
#' Tests various insertion patterns and measures performance metrics.
#' Validates target of >5000 inserts/second for batch operations.
#' 
#' @param test_sizes Vector of test sizes to benchmark
#' @param chunk_sizes Vector of chunk sizes to test
#' @param connection_tests Whether to test connection overhead
#' @return Comprehensive benchmark results
run_postgres_benchmark <- function(test_sizes = c(1000, 5000, 10000, 50000),
                                  chunk_sizes = c(1000, 2500, 5000, 10000),
                                  connection_tests = TRUE) {
  
  cat("=== PostgreSQL Performance Benchmark ===\n")
  cat("Starting comprehensive performance testing...\n\n")
  
  # Test connection
  cat("1. Testing connection...\n")
  conn_start <- Sys.time()
  conn <- tryCatch(connect_postgres(), error = function(e) {
    cat("ERROR: Cannot connect to PostgreSQL:", e$message, "\n")
    return(NULL)
  })
  
  if (is.null(conn)) {
    return(list(success = FALSE, error = "Connection failed"))
  }
  
  conn_time <- as.numeric(difftime(Sys.time(), conn_start, units = "secs"))
  cat(sprintf("✓ Connection established in %.3f seconds\n", conn_time))
  
  # Test connection health
  health <- test_connection_health(conn, detailed = TRUE)
  cat(sprintf("✓ Connection health: %s (%.1f ms response time)\n", 
             if(health$healthy) "HEALTHY" else "WARNING", health$response_time_ms))
  
  # Ensure clean schema
  ensure_schema(conn)
  
  # Initialize results collection
  benchmark_results <- list(
    connection_time = conn_time,
    connection_health = health,
    single_insert_tests = list(),
    batch_insert_tests = list(),
    chunk_size_tests = list(),
    concurrent_tests = list()
  )
  
  cat("\n2. Single Insert Performance...\n")
  
  # Test single inserts
  single_test_data <- generate_benchmark_data(100)
  
  start_time <- Sys.time()
  for (i in 1:min(50, length(single_test_data))) {
    store_llm_result(single_test_data[[i]], conn = conn, auto_close = FALSE)
  }
  end_time <- Sys.time()
  
  single_duration <- as.numeric(difftime(end_time, start_time, units = "secs"))
  single_rate <- 50 / single_duration
  
  benchmark_results$single_insert_tests <- list(
    duration_seconds = single_duration,
    inserts_per_second = single_rate,
    target_met = single_rate >= 100  # Target: 100 inserts/sec for single
  )
  
  cat(sprintf("✓ Single insert rate: %.1f inserts/second\n", single_rate))
  
  cat("\n3. Batch Insert Performance...\n")
  
  # Test different batch sizes
  for (size in test_sizes) {
    cat(sprintf("Testing batch size: %d records...\n", size))
    
    test_data <- generate_benchmark_data(size)
    
    start_time <- Sys.time()
    result <- store_llm_results_batch(test_data, conn = conn)
    end_time <- Sys.time()
    
    duration <- as.numeric(difftime(end_time, start_time, units = "secs"))
    rate <- size / duration
    
    test_result <- list(
      size = size,
      duration_seconds = duration,
      inserts_per_second = rate,
      success_rate = result$success_rate,
      target_met = rate >= 5000,  # Target: 5000 inserts/sec
      inserted = result$inserted,
      duplicates = result$duplicates,
      errors = result$errors
    )
    
    benchmark_results$batch_insert_tests[[as.character(size)]] <- test_result
    
    cat(sprintf("  ✓ Rate: %.1f inserts/second (Success: %.1f%%)\n", 
               rate, result$success_rate * 100))
    
    # Brief pause between tests
    Sys.sleep(0.5)
  }
  
  cat("\n4. Chunk Size Optimization...\n")
  
  # Test different chunk sizes with moderate dataset
  test_data_chunk <- generate_benchmark_data(10000)
  
  for (chunk_size in chunk_sizes) {
    cat(sprintf("Testing chunk size: %d...\n", chunk_size))
    
    start_time <- Sys.time()
    result <- store_llm_results_batch(test_data_chunk, conn = conn, chunk_size = chunk_size)
    end_time <- Sys.time()
    
    duration <- as.numeric(difftime(end_time, start_time, units = "secs"))
    rate <- 10000 / duration
    
    chunk_result <- list(
      chunk_size = chunk_size,
      duration_seconds = duration,
      inserts_per_second = rate,
      success_rate = result$success_rate,
      memory_efficient = chunk_size <= 5000
    )
    
    benchmark_results$chunk_size_tests[[as.character(chunk_size)]] <- chunk_result
    
    cat(sprintf("  ✓ Rate: %.1f inserts/second\n", rate))
    
    Sys.sleep(0.5)
  }
  
  cat("\n5. Connection Overhead Analysis...\n")
  
  if (connection_tests) {
    # Test connection reuse vs new connections
    test_data_conn <- generate_benchmark_data(1000)
    
    # Test with connection reuse
    start_time <- Sys.time()
    store_llm_results_batch(test_data_conn, conn = conn)
    reuse_time <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    
    # Test with new connection
    close_db_connection(conn)
    start_time <- Sys.time()
    store_llm_results_batch(test_data_conn)  # Creates new connection
    new_conn_time <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    
    # Reconnect for cleanup
    conn <- connect_postgres()
    
    benchmark_results$concurrent_tests <- list(
      reuse_duration = reuse_time,
      new_connection_duration = new_conn_time,
      overhead_seconds = new_conn_time - reuse_time,
      overhead_percentage = ((new_conn_time - reuse_time) / reuse_time) * 100
    )
    
    cat(sprintf("  ✓ Connection reuse: %.3f seconds\n", reuse_time))
    cat(sprintf("  ✓ New connection: %.3f seconds (%.1f%% overhead)\n", 
               new_conn_time, benchmark_results$concurrent_tests$overhead_percentage))
  }
  
  # Database statistics
  cat("\n6. Database Statistics...\n")
  
  stats_query <- "
    SELECT 
      COUNT(*) as total_records,
      COUNT(DISTINCT narrative_text) as unique_narratives,
      AVG(confidence) as avg_confidence,
      SUM(CASE WHEN detected THEN 1 ELSE 0 END) as detected_count,
      AVG(total_tokens) as avg_tokens
    FROM llm_results
  "
  
  db_stats <- DBI::dbGetQuery(conn, stats_query)
  benchmark_results$database_stats <- db_stats
  
  cat(sprintf("  ✓ Total records: %d\n", db_stats$total_records))
  cat(sprintf("  ✓ Unique narratives: %d\n", db_stats$unique_narratives))
  cat(sprintf("  ✓ Detection rate: %.1f%%\n", 
             (db_stats$detected_count / db_stats$total_records) * 100))
  
  # Performance summary
  cat("\n=== PERFORMANCE SUMMARY ===\n")
  
  # Find best batch performance
  best_batch <- benchmark_results$batch_insert_tests[[which.max(
    sapply(benchmark_results$batch_insert_tests, function(x) x$inserts_per_second)
  )]]
  
  cat(sprintf("Single Insert Rate: %.1f inserts/second %s\n",
             benchmark_results$single_insert_tests$inserts_per_second,
             if(benchmark_results$single_insert_tests$target_met) "✓" else "✗"))
  
  cat(sprintf("Best Batch Rate: %.1f inserts/second (%d records) %s\n",
             best_batch$inserts_per_second, best_batch$size,
             if(best_batch$target_met) "✓" else "✗"))
  
  # Find optimal chunk size
  best_chunk <- benchmark_results$chunk_size_tests[[which.max(
    sapply(benchmark_results$chunk_size_tests, function(x) x$inserts_per_second)
  )]]
  
  cat(sprintf("Optimal Chunk Size: %d (%.1f inserts/second)\n",
             best_chunk$chunk_size, best_chunk$inserts_per_second))
  
  # Overall assessment
  target_met <- best_batch$inserts_per_second >= 5000
  cat(sprintf("\nTarget Performance (>5000 inserts/sec): %s\n",
             if(target_met) "✓ MET" else "✗ NOT MET"))
  
  close_db_connection(conn)
  
  benchmark_results$summary <- list(
    target_met = target_met,
    best_batch_rate = best_batch$inserts_per_second,
    optimal_chunk_size = best_chunk$chunk_size,
    connection_overhead_pct = if(connection_tests) benchmark_results$concurrent_tests$overhead_percentage else NA
  )
  
  return(benchmark_results)
}

#' Generate performance report
#' 
#' Creates detailed performance report with recommendations.
#' 
#' @param benchmark_results Results from run_postgres_benchmark()
#' @param output_file Optional file to save report
#' @return Formatted report string
generate_performance_report <- function(benchmark_results, output_file = NULL) {
  
  report_lines <- c(
    "# PostgreSQL Performance Benchmark Report",
    sprintf("Generated: %s", Sys.time()),
    "",
    "## Executive Summary",
    ""
  )
  
  if (benchmark_results$summary$target_met) {
    report_lines <- c(report_lines,
      "✅ **Performance Target Met**: PostgreSQL backend achieves >5000 inserts/second",
      sprintf("📊 **Best Performance**: %.0f inserts/second", benchmark_results$summary$best_batch_rate),
      sprintf("⚙️ **Optimal Configuration**: %d record chunks", benchmark_results$summary$optimal_chunk_size)
    )
  } else {
    report_lines <- c(report_lines,
      "❌ **Performance Target Not Met**: PostgreSQL backend falls short of 5000 inserts/second",
      sprintf("📊 **Current Best**: %.0f inserts/second", benchmark_results$summary$best_batch_rate),
      "🔧 **Requires Optimization**: Review database configuration and hardware"
    )
  }
  
  # Connection performance
  report_lines <- c(report_lines,
    "",
    "## Connection Performance",
    sprintf("- Connection establishment: %.3f seconds", benchmark_results$connection_time),
    sprintf("- Health check response: %.1f ms", benchmark_results$connection_health$response_time_ms)
  )
  
  if (!is.na(benchmark_results$summary$connection_overhead_pct)) {
    report_lines <- c(report_lines,
      sprintf("- Connection overhead: %.1f%%", benchmark_results$summary$connection_overhead_pct)
    )
  }
  
  # Batch performance details
  report_lines <- c(report_lines,
    "",
    "## Batch Insert Performance",
    ""
  )
  
  for (size_name in names(benchmark_results$batch_insert_tests)) {
    test <- benchmark_results$batch_insert_tests[[size_name]]
    status <- if(test$target_met) "✅" else "⚠️"
    
    report_lines <- c(report_lines,
      sprintf("### %s records %s", format(test$size, big.mark = ","), status),
      sprintf("- Rate: **%.0f inserts/second**", test$inserts_per_second),
      sprintf("- Duration: %.2f seconds", test$duration_seconds),
      sprintf("- Success Rate: %.1f%%", test$success_rate * 100),
      ""
    )
  }
  
  # Chunk size analysis
  report_lines <- c(report_lines,
    "## Chunk Size Optimization",
    ""
  )
  
  for (chunk_name in names(benchmark_results$chunk_size_tests)) {
    test <- benchmark_results$chunk_size_tests[[chunk_name]]
    
    report_lines <- c(report_lines,
      sprintf("- **%s records/chunk**: %.0f inserts/second", 
             format(test$chunk_size, big.mark = ","), test$inserts_per_second)
    )
  }
  
  # Database statistics
  stats <- benchmark_results$database_stats
  report_lines <- c(report_lines,
    "",
    "## Database Statistics",
    sprintf("- Total Records: %s", format(stats$total_records, big.mark = ",")),
    sprintf("- Unique Narratives: %s", format(stats$unique_narratives, big.mark = ",")),
    sprintf("- Average Confidence: %.3f", stats$avg_confidence),
    sprintf("- Detection Rate: %.1f%%", (stats$detected_count / stats$total_records) * 100),
    sprintf("- Average Tokens: %.0f", stats$avg_tokens)
  )
  
  # Recommendations
  report_lines <- c(report_lines,
    "",
    "## Recommendations",
    ""
  )
  
  if (benchmark_results$summary$target_met) {
    report_lines <- c(report_lines,
      "✅ **Production Ready**: Current configuration meets performance requirements",
      sprintf("🚀 **Optimal Settings**: Use %d-record chunks for batch operations", 
             benchmark_results$summary$optimal_chunk_size),
      "📈 **Scaling**: Consider connection pooling for high-concurrency workloads"
    )
  } else {
    report_lines <- c(report_lines,
      "🔧 **Database Tuning Required**:",
      "   - Increase `work_mem` and `shared_buffers`",
      "   - Enable write-ahead logging optimization",
      "   - Consider SSD storage for better I/O",
      "",
      "🖥️ **Hardware Considerations**:",
      "   - More RAM for larger buffer pools",
      "   - Faster storage (NVMe SSD)",
      "   - Network latency optimization"
    )
  }
  
  report_lines <- c(report_lines,
    "",
    "---",
    "*Report generated by IPV Detection PostgreSQL Benchmark Suite*"
  )
  
  report_text <- paste(report_lines, collapse = "\n")
  
  if (!is.null(output_file)) {
    writeLines(report_text, output_file)
    cat(sprintf("Report saved to: %s\n", output_file))
  }
  
  return(report_text)
}

#' Run lightweight performance check
#' 
#' Quick performance validation for CI/CD pipelines.
#' 
#' @param sample_size Number of records to test (default: 1000)
#' @return Boolean indicating if performance targets are met
quick_performance_check <- function(sample_size = 1000) {
  
  cat("Running quick performance check...\n")
  
  # Test connection
  conn <- tryCatch(connect_postgres(), error = function(e) NULL)
  if (is.null(conn)) {
    cat("❌ Connection failed\n")
    return(FALSE)
  }
  
  # Quick health check
  health <- test_connection_health(conn)
  if (!health$healthy || health$response_time_ms > 200) {
    cat("❌ Connection health check failed\n")
    close_db_connection(conn)
    return(FALSE)
  }
  
  # Generate test data
  test_data <- generate_benchmark_data(sample_size)
  
  # Test batch insert
  start_time <- Sys.time()
  result <- store_llm_results_batch(test_data, conn = conn)
  duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  
  rate <- sample_size / duration
  target_met <- rate >= 5000
  
  cat(sprintf("✅ Rate: %.0f inserts/second %s\n", rate, 
             if(target_met) "(Target Met)" else "(Below Target)"))
  
  close_db_connection(conn)
  return(target_met)
}

# Main execution when run as script
if (!interactive()) {
  cat("PostgreSQL Performance Benchmark\n")
  cat("================================\n\n")
  
  # Check if quick mode requested
  args <- commandArgs(trailingOnly = TRUE)
  if ("--quick" %in% args) {
    success <- quick_performance_check()
    quit(status = if(success) 0 else 1)
  }
  
  # Run full benchmark
  results <- run_postgres_benchmark()
  
  # Generate report
  report_file <- sprintf("postgresql_benchmark_%s.md", 
                        format(Sys.time(), "%Y%m%d_%H%M%S"))
  
  cat("\n" %+% "=" %+% rep("=", 50) %+% "\n")
  generate_performance_report(results, report_file)
  
  # Exit with appropriate code
  quit(status = if(results$summary$target_met) 0 else 1)
}