# Integration Performance Benchmarking
#
# Comprehensive performance benchmarks for all IPV detection components
# Tests parsing, storage, and query performance against defined targets
# Uses real narrative data for realistic performance validation
#
# Performance Targets:
# - Parsing: >500 responses/second
# - Storage: >5000 inserts/second (PostgreSQL)
# - Query: <10ms for simple queries

library(DBI)
library(RPostgres)
library(tibble)
library(dplyr)
library(readxl)

# Use system.time instead of microbenchmark if not available
if (!requireNamespace("microbenchmark", quietly = TRUE)) {
  microbenchmark <- function(expr, times = 100) {
    results <- replicate(times, {
      start_time <- Sys.time()
      eval(expr)
      as.numeric(difftime(Sys.time(), start_time, units = "secs")) * 1e9  # nanoseconds
    })
    return(list(time = results))
  }
}

# Source required functions
if (!exists("parse_llm_result")) {
  source("../../R/parse_llm_result.R")
}
if (!exists("store_llm_result")) {
  source("../../R/store_llm_result.R")
}
if (!exists("connect_postgres")) {
  source("../../R/db_utils.R")
}
if (!exists("call_llm")) {
  source("../../R/call_llm.R")
}

#' Load real test data from NVDRS suicide dataset
#'
#' Loads manually flagged IPV cases for realistic performance testing
#' 
#' @param limit Maximum number of narratives to load (NULL for all)
#' @return List of narrative data with IPV flags
load_real_test_data <- function(limit = NULL) {
  
  data_path <- "../../data-raw/suicide_IPV_manuallyflagged.xlsx"
  
  if (!file.exists(data_path)) {
    stop("Test data not found: ", data_path)
  }
  
  cat("Loading real NVDRS test data...\n")
  raw_data <- read_excel(data_path)
  
  # Combine CME and LE narratives, preferring CME when available
  narratives <- ifelse(
    !is.na(raw_data$NarrativeCME) & nchar(trimws(raw_data$NarrativeCME)) > 10,
    raw_data$NarrativeCME,
    raw_data$NarrativeLE
  )
  
  # Filter out empty narratives
  valid_idx <- !is.na(narratives) & nchar(trimws(narratives)) > 20
  
  test_data <- list(
    narratives = narratives[valid_idx],
    ipv_flags = raw_data$ipv_manual[valid_idx],
    incident_ids = raw_data$IncidentID[valid_idx],
    reasoning = raw_data$reasoning[valid_idx]
  )
  
  if (!is.null(limit) && length(test_data$narratives) > limit) {
    idx <- sample(seq_along(test_data$narratives), limit)
    test_data$narratives <- test_data$narratives[idx]
    test_data$ipv_flags <- test_data$ipv_flags[idx]
    test_data$incident_ids <- test_data$incident_ids[idx]
    test_data$reasoning <- test_data$reasoning[idx]
  }
  
  cat(sprintf("Loaded %d narratives (%d IPV positive)\n", 
             length(test_data$narratives), sum(test_data$ipv_flags, na.rm = TRUE)))
  
  return(test_data)
}

#' Generate synthetic LLM responses for performance testing
#'
#' Creates realistic LLM responses based on real narrative patterns
#' 
#' @param narratives Vector of narrative texts
#' @param response_variety Include response time variation (default: TRUE)
#' @return List of mock LLM results
generate_mock_llm_responses <- function(narratives, response_variety = TRUE) {
  
  models <- c("gpt-3.5-turbo", "gpt-4", "claude-3", "gemini-pro")
  
  responses <- vector("list", length(narratives))
  
  for (i in seq_along(narratives)) {
    narrative <- narratives[i]
    
    # Simulate realistic detection based on narrative content
    # Higher chance of detection for narratives with IPV keywords
    ipv_keywords <- c("partner", "boyfriend", "girlfriend", "spouse", "husband", "wife", 
                     "domestic", "violence", "abuse", "hit", "beat", "assault")
    
    keyword_count <- sum(sapply(ipv_keywords, function(kw) grepl(kw, narrative, ignore.case = TRUE)))
    detection_prob <- pmin(0.9, 0.2 + keyword_count * 0.1)
    
    detected <- runif(1) < detection_prob
    confidence <- if (detected) runif(1, 0.6, 0.95) else runif(1, 0.1, 0.6)
    
    # Simulate response times based on complexity
    narrative_length <- nchar(narrative)
    base_time <- 800 + narrative_length * 2
    response_time <- if (response_variety) {
      base_time + rnorm(1, 0, base_time * 0.2)
    } else {
      base_time
    }
    
    # Simulate token usage
    prompt_tokens <- round(narrative_length / 4 + runif(1, 50, 150))
    completion_tokens <- round(runif(1, 30, 100))
    
    responses[[i]] <- list(
      narrative_id = sprintf("NVDRS_%06d", i),
      narrative_text = narrative,
      detected = detected,
      confidence = confidence,
      model = sample(models, 1),
      prompt_tokens = prompt_tokens,
      completion_tokens = completion_tokens,
      total_tokens = prompt_tokens + completion_tokens,
      response_time_ms = round(response_time),
      raw_response = sprintf('{"detected": %s, "confidence": %.3f}', 
                           tolower(as.character(detected)), confidence),
      error_message = if (runif(1) > 0.98) "Transient API error" else NA
    )
  }
  
  return(responses)
}

#' Benchmark parsing performance
#'
#' Tests parse_llm_result() function performance against target
#' Target: >500 responses/second
#' 
#' @param test_responses List of mock LLM responses
#' @param iterations Number of benchmark iterations (default: 100)
#' @return Parsing performance metrics
benchmark_parsing <- function(test_responses, iterations = 100) {
  
  cat("=== Parsing Performance Benchmark ===\n")
  cat("Target: >500 responses/second\n\n")
  
  # Sample responses for benchmarking
  sample_size <- min(50, length(test_responses))
  sample_responses <- sample(test_responses, sample_size)
  
  # Create various response formats for robustness testing
  test_formats <- list(
    clean_json = sample_responses,
    with_whitespace = lapply(sample_responses, function(r) {
      r$raw_response <- paste0("  \n", r$raw_response, "\n  ")
      return(r)
    }),
    with_extra_text = lapply(sample_responses, function(r) {
      r$raw_response <- paste0("Analysis: ", r$raw_response, " (confidence level)")
      return(r)
    }),
    malformed_json = lapply(sample_responses, function(r) {
      if (runif(1) > 0.8) {  # 20% malformed
        r$raw_response <- gsub("}", "", r$raw_response)  # Remove closing brace
      }
      return(r)
    })
  )
  
  parsing_results <- list()
  
  for (format_name in names(test_formats)) {
    cat(sprintf("Testing %s format...\n", format_name))
    
    format_responses <- test_formats[[format_name]]
    
    # Benchmark parsing performance
    benchmark_result <- microbenchmark(
      {
        for (response in format_responses) {
          tryCatch({
            parsed <- parse_llm_result(response$raw_response)
          }, error = function(e) NULL)
        }
      },
      times = iterations
    )
    
    # Calculate performance metrics
    avg_time_ms <- mean(benchmark_result$time / 1e6)  # Convert to milliseconds
    responses_per_second <- (sample_size * 1000) / avg_time_ms
    
    # Test accuracy
    successful_parses <- 0
    for (response in format_responses) {
      tryCatch({
        parsed <- parse_llm_result(response$raw_response)
        if (!is.null(parsed) && "detected" %in% names(parsed)) {
          successful_parses <- successful_parses + 1
        }
      }, error = function(e) NULL)
    }
    
    success_rate <- successful_parses / sample_size
    target_met <- responses_per_second >= 500
    
    parsing_results[[format_name]] <- list(
      format = format_name,
      sample_size = sample_size,
      iterations = iterations,
      avg_time_ms = avg_time_ms,
      responses_per_second = responses_per_second,
      success_rate = success_rate,
      target_met = target_met
    )
    
    cat(sprintf("  ✓ Rate: %.0f responses/second (Success: %.1f%%) %s\n", 
               responses_per_second, success_rate * 100,
               if(target_met) "✅" else "❌"))
  }
  
  # Overall assessment
  best_performance <- max(sapply(parsing_results, function(x) x$responses_per_second))
  overall_target_met <- best_performance >= 500
  
  cat(sprintf("\nBest parsing rate: %.0f responses/second %s\n",
             best_performance, if(overall_target_met) "✅" else "❌"))
  
  return(list(
    target_met = overall_target_met,
    best_rate = best_performance,
    format_results = parsing_results,
    target = 500
  ))
}

#' Benchmark storage performance
#'
#' Tests database storage performance for both SQLite and PostgreSQL
#' Target: >5000 inserts/second for PostgreSQL
#' 
#' @param test_data List of parsed results to store
#' @param test_postgres Whether to test PostgreSQL (default: TRUE)
#' @param test_sqlite Whether to test SQLite (default: FALSE)
#' @return Storage performance metrics
benchmark_storage <- function(test_data, test_postgres = TRUE, test_sqlite = FALSE) {
  
  cat("=== Storage Performance Benchmark ===\n")
  cat("Target: >5000 inserts/second (PostgreSQL)\n\n")
  
  storage_results <- list()
  
  # Test PostgreSQL if requested
  if (test_postgres) {
    cat("Testing PostgreSQL storage...\n")
    
    postgres_conn <- tryCatch({
      connect_postgres()
    }, error = function(e) {
      cat("❌ PostgreSQL connection failed:", e$message, "\n")
      return(NULL)
    })
    
    if (!is.null(postgres_conn)) {
      # Test different batch sizes
      batch_sizes <- c(100, 500, 1000, 2500, 5000)
      
      postgres_results <- list()
      
      for (batch_size in batch_sizes) {
        if (length(test_data) < batch_size) next
        
        sample_data <- sample(test_data, batch_size)
        
        start_time <- Sys.time()
        result <- store_llm_results_batch(sample_data, conn = postgres_conn)
        duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
        
        rate <- batch_size / duration
        target_met <- rate >= 5000
        
        postgres_results[[as.character(batch_size)]] <- list(
          batch_size = batch_size,
          duration_seconds = duration,
          inserts_per_second = rate,
          success_rate = result$success_rate,
          target_met = target_met
        )
        
        cat(sprintf("  Batch %d: %.0f inserts/sec (%.1f%% success) %s\n",
                   batch_size, rate, result$success_rate * 100,
                   if(target_met) "✅" else "❌"))
      }
      
      close_db_connection(postgres_conn)
      
      # Find best PostgreSQL performance
      best_postgres <- postgres_results[[which.max(
        sapply(postgres_results, function(x) x$inserts_per_second)
      )]]
      
      storage_results$postgresql <- list(
        available = TRUE,
        best_rate = best_postgres$inserts_per_second,
        optimal_batch_size = best_postgres$batch_size,
        target_met = best_postgres$target_met,
        batch_results = postgres_results
      )
    } else {
      storage_results$postgresql <- list(available = FALSE, error = "Connection failed")
    }
  }
  
  # Test SQLite if requested
  if (test_sqlite) {
    cat("Testing SQLite storage...\n")
    
    # Create temporary SQLite database
    sqlite_path <- tempfile(fileext = ".db")
    sqlite_conn <- DBI::dbConnect(RSQLite::SQLite(), sqlite_path)
    
    # Create schema
    ensure_schema(sqlite_conn)
    
    # Test smaller batch sizes for SQLite (it's typically slower)
    batch_sizes <- c(100, 500, 1000)
    sqlite_results <- list()
    
    for (batch_size in batch_sizes) {
      if (length(test_data) < batch_size) next
      
      sample_data <- sample(test_data, batch_size)
      
      start_time <- Sys.time()
      result <- store_llm_results_batch(sample_data, conn = sqlite_conn)
      duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
      
      rate <- batch_size / duration
      
      sqlite_results[[as.character(batch_size)]] <- list(
        batch_size = batch_size,
        duration_seconds = duration,
        inserts_per_second = rate,
        success_rate = result$success_rate
      )
      
      cat(sprintf("  Batch %d: %.0f inserts/sec (%.1f%% success)\n",
                 batch_size, rate, result$success_rate * 100))
    }
    
    DBI::dbDisconnect(sqlite_conn)
    unlink(sqlite_path)
    
    best_sqlite <- sqlite_results[[which.max(
      sapply(sqlite_results, function(x) x$inserts_per_second)
    )]]
    
    storage_results$sqlite <- list(
      best_rate = best_sqlite$inserts_per_second,
      optimal_batch_size = best_sqlite$batch_size,
      batch_results = sqlite_results
    )
  }
  
  return(storage_results)
}

#' Benchmark query performance
#'
#' Tests database query performance against target
#' Target: <10ms for simple queries
#' 
#' @param conn Database connection
#' @param iterations Number of queries to test (default: 100)
#' @return Query performance metrics
benchmark_queries <- function(conn = NULL, iterations = 100) {
  
  cat("=== Query Performance Benchmark ===\n")
  cat("Target: <10ms for simple queries\n\n")
  
  if (is.null(conn)) {
    conn <- tryCatch(connect_postgres(), error = function(e) NULL)
    if (is.null(conn)) {
      cat("❌ No database connection available\n")
      return(list(available = FALSE))
    }
    auto_close <- TRUE
  } else {
    auto_close <- FALSE
  }
  
  # Ensure we have some data to query
  record_count <- DBI::dbGetQuery(conn, "SELECT COUNT(*) as count FROM llm_results")$count
  if (record_count == 0) {
    cat("⚠️ No data in database for query testing\n")
    if (auto_close) close_db_connection(conn)
    return(list(available = FALSE, reason = "No data"))
  }
  
  cat(sprintf("Testing queries against %d records...\n", record_count))
  
  # Define test queries
  test_queries <- list(
    count_all = "SELECT COUNT(*) FROM llm_results",
    count_detected = "SELECT COUNT(*) FROM llm_results WHERE detected = TRUE",
    avg_confidence = "SELECT AVG(confidence) FROM llm_results",
    recent_results = "SELECT * FROM llm_results ORDER BY created_at DESC LIMIT 10",
    high_confidence = "SELECT * FROM llm_results WHERE confidence > 0.8 LIMIT 10",
    model_stats = "SELECT model, COUNT(*) as count FROM llm_results GROUP BY model",
    complex_aggregate = paste0(
      "SELECT model, ",
      "COUNT(*) as total, ",
      "SUM(CASE WHEN detected THEN 1 ELSE 0 END) as detected_count, ",
      "AVG(confidence) as avg_confidence, ",
      "AVG(total_tokens) as avg_tokens ",
      "FROM llm_results GROUP BY model"
    )
  )
  
  query_results <- list()
  
  for (query_name in names(test_queries)) {
    query_sql <- test_queries[[query_name]]
    
    cat(sprintf("Testing %s...\n", query_name))
    
    # Benchmark the query
    times <- numeric(iterations)
    successful_queries <- 0
    
    for (i in 1:iterations) {
      start_time <- Sys.time()
      tryCatch({
        result <- DBI::dbGetQuery(conn, query_sql)
        successful_queries <- successful_queries + 1
      }, error = function(e) NULL)
      end_time <- Sys.time()
      
      times[i] <- as.numeric(difftime(end_time, start_time, units = "secs")) * 1000
    }
    
    # Calculate statistics
    valid_times <- times[times > 0 & times < 10000]  # Remove outliers
    if (length(valid_times) > 0) {
      avg_time_ms <- mean(valid_times)
      median_time_ms <- median(valid_times)
      p95_time_ms <- quantile(valid_times, 0.95)
      target_met <- avg_time_ms < 10
      
      query_results[[query_name]] <- list(
        query = query_name,
        sql = query_sql,
        iterations = iterations,
        successful_queries = successful_queries,
        success_rate = successful_queries / iterations,
        avg_time_ms = avg_time_ms,
        median_time_ms = median_time_ms,
        p95_time_ms = p95_time_ms,
        target_met = target_met
      )
      
      cat(sprintf("  ✓ Avg: %.2fms, Median: %.2fms, P95: %.2fms %s\n",
                 avg_time_ms, median_time_ms, p95_time_ms,
                 if(target_met) "✅" else "❌"))
    }
  }
  
  if (auto_close) close_db_connection(conn)
  
  # Overall assessment
  avg_times <- sapply(query_results, function(x) x$avg_time_ms)
  overall_target_met <- all(avg_times < 10)
  worst_query_time <- max(avg_times)
  
  cat(sprintf("\nWorst query performance: %.2fms %s\n",
             worst_query_time, if(overall_target_met) "✅" else "❌"))
  
  return(list(
    available = TRUE,
    target_met = overall_target_met,
    worst_time_ms = worst_query_time,
    query_results = query_results,
    target = 10
  ))
}

#' Run comprehensive integration benchmarks
#'
#' Tests all components and validates performance targets
#' 
#' @param data_limit Maximum number of narratives to test (NULL for all)
#' @param test_postgres Whether to test PostgreSQL (default: TRUE)
#' @param test_sqlite Whether to test SQLite (default: FALSE)
#' @return Complete benchmark results
run_integration_benchmarks <- function(data_limit = NULL, test_postgres = TRUE, test_sqlite = FALSE) {
  
  cat("=== IPV Detection Integration Performance Benchmarks ===\n")
  cat("Testing all components against performance targets\n\n")
  
  # Load real test data
  real_data <- load_real_test_data(data_limit)
  
  # Generate mock LLM responses
  cat("\nGenerating mock LLM responses...\n")
  mock_responses <- generate_mock_llm_responses(real_data$narratives)
  
  # Convert to parsed format for storage testing
  parsed_results <- lapply(mock_responses, function(response) {
    tryCatch({
      parsed <- parse_llm_result(response$raw_response)
      if (!is.null(parsed)) {
        # Merge with response metadata
        parsed$narrative_id <- response$narrative_id
        parsed$narrative_text <- response$narrative_text
        parsed$model <- response$model
        parsed$prompt_tokens <- response$prompt_tokens
        parsed$completion_tokens <- response$completion_tokens
        parsed$total_tokens <- response$total_tokens
        parsed$response_time_ms <- response$response_time_ms
        parsed$raw_response <- response$raw_response
        parsed$error_message <- response$error_message
      }
      return(parsed)
    }, error = function(e) return(NULL))
  })
  
  # Remove failed parses
  parsed_results <- parsed_results[!sapply(parsed_results, is.null)]
  
  cat(sprintf("Generated %d mock responses, %d parsed successfully\n",
             length(mock_responses), length(parsed_results)))
  
  # Run component benchmarks
  benchmark_results <- list()
  
  # 1. Parsing Performance
  cat("\n", paste0(rep("=", 50), collapse = ""), "\n")
  benchmark_results$parsing <- benchmark_parsing(mock_responses)
  
  # 2. Storage Performance
  cat("\n", paste0(rep("=", 50), collapse = ""), "\n")
  benchmark_results$storage <- benchmark_storage(
    parsed_results, test_postgres = test_postgres, test_sqlite = test_sqlite
  )
  
  # 3. Query Performance
  cat("\n", paste0(rep("=", 50), collapse = ""), "\n")
  benchmark_results$queries <- benchmark_queries()
  
  # Overall assessment
  cat("\n", paste0(rep("=", 50), collapse = ""), "\n")
  cat("=== OVERALL PERFORMANCE ASSESSMENT ===\n\n")
  
  # Check each target
  targets_met <- list()
  
  # Parsing target
  parsing_met <- benchmark_results$parsing$target_met
  targets_met$parsing <- parsing_met
  cat(sprintf("Parsing (>500 responses/sec): %s (%.0f/sec)\n",
             if(parsing_met) "✅ MET" else "❌ NOT MET",
             benchmark_results$parsing$best_rate))
  
  # Storage target
  if (!is.null(benchmark_results$storage$postgresql) && 
      benchmark_results$storage$postgresql$available) {
    storage_met <- benchmark_results$storage$postgresql$target_met
    targets_met$storage <- storage_met
    cat(sprintf("Storage (>5000 inserts/sec): %s (%.0f/sec)\n",
               if(storage_met) "✅ MET" else "❌ NOT MET",
               benchmark_results$storage$postgresql$best_rate))
  } else {
    cat("Storage (>5000 inserts/sec): ⚠️ NOT TESTED (PostgreSQL unavailable)\n")
    targets_met$storage <- NA
  }
  
  # Query target
  if (benchmark_results$queries$available) {
    query_met <- benchmark_results$queries$target_met
    targets_met$queries <- query_met
    cat(sprintf("Queries (<10ms): %s (%.2fms worst)\n",
               if(query_met) "✅ MET" else "❌ NOT MET",
               benchmark_results$queries$worst_time_ms))
  } else {
    cat("Queries (<10ms): ⚠️ NOT TESTED (Database unavailable)\n")
    targets_met$queries <- NA
  }
  
  # Overall status
  met_count <- sum(targets_met == TRUE, na.rm = TRUE)
  total_tested <- sum(!is.na(targets_met))
  
  cat(sprintf("\nOverall: %d/%d targets met\n", met_count, total_tested))
  
  if (met_count == total_tested && total_tested > 0) {
    cat("🎉 ALL PERFORMANCE TARGETS MET - READY FOR PRODUCTION\n")
    overall_status <- "PASSED"
  } else {
    cat("⚠️ SOME TARGETS NOT MET - OPTIMIZATION REQUIRED\n")
    overall_status <- "FAILED"
  }
  
  # Add summary to results
  benchmark_results$summary <- list(
    overall_status = overall_status,
    targets_met = targets_met,
    data_samples = length(real_data$narratives),
    test_timestamp = Sys.time()
  )
  
  return(benchmark_results)
}

#' Generate integration benchmark report
#'
#' Creates comprehensive report with performance analysis and recommendations
#' 
#' @param benchmark_results Results from run_integration_benchmarks()
#' @param output_file Optional file to save report
#' @return Formatted report text
generate_integration_report <- function(benchmark_results, output_file = NULL) {
  
  report_lines <- c(
    "# IPV Detection Integration Performance Report",
    sprintf("Generated: %s", Sys.time()),
    sprintf("Test Status: **%s**", benchmark_results$summary$overall_status),
    sprintf("Data Samples: %d narratives from NVDRS dataset", benchmark_results$summary$data_samples),
    "",
    "## Executive Summary",
    ""
  )
  
  # Status summary
  if (benchmark_results$summary$overall_status == "PASSED") {
    report_lines <- c(report_lines,
      "✅ **All Performance Targets Met**",
      "🚀 **Production Ready**: System meets all performance requirements",
      "📊 **Validated Components**: Parsing, Storage, and Query performance confirmed"
    )
  } else {
    report_lines <- c(report_lines,
      "⚠️ **Performance Issues Detected**",
      "🔧 **Optimization Required**: Some components below target performance",
      "📋 **Action Required**: Review recommendations before production deployment"
    )
  }
  
  # Performance targets section
  report_lines <- c(report_lines,
    "",
    "## Performance Targets & Results",
    ""
  )
  
  # Parsing results
  parsing_status <- if (benchmark_results$summary$targets_met$parsing) "✅ MET" else "❌ NOT MET"
  report_lines <- c(report_lines,
    "### Parsing Performance",
    sprintf("- **Target**: >500 responses/second"),
    sprintf("- **Result**: %.0f responses/second", benchmark_results$parsing$best_rate),
    sprintf("- **Status**: %s", parsing_status),
    ""
  )
  
  # Storage results
  if (!is.na(benchmark_results$summary$targets_met$storage)) {
    storage_status <- if (benchmark_results$summary$targets_met$storage) "✅ MET" else "❌ NOT MET"
    report_lines <- c(report_lines,
      "### Storage Performance (PostgreSQL)",
      sprintf("- **Target**: >5,000 inserts/second"),
      sprintf("- **Result**: %.0f inserts/second", benchmark_results$storage$postgresql$best_rate),
      sprintf("- **Optimal Batch**: %d records", benchmark_results$storage$postgresql$optimal_batch_size),
      sprintf("- **Status**: %s", storage_status),
      ""
    )
  } else {
    report_lines <- c(report_lines,
      "### Storage Performance",
      "- **Status**: ⚠️ PostgreSQL not available for testing",
      ""
    )
  }
  
  # Query results
  if (!is.na(benchmark_results$summary$targets_met$queries)) {
    query_status <- if (benchmark_results$summary$targets_met$queries) "✅ MET" else "❌ NOT MET"
    report_lines <- c(report_lines,
      "### Query Performance",
      sprintf("- **Target**: <10ms for simple queries"),
      sprintf("- **Result**: %.2fms (worst case)", benchmark_results$queries$worst_time_ms),
      sprintf("- **Status**: %s", query_status),
      ""
    )
  } else {
    report_lines <- c(report_lines,
      "### Query Performance",
      "- **Status**: ⚠️ Database not available for testing",
      ""
    )
  }
  
  # Detailed results section
  if (!is.null(benchmark_results$parsing$format_results)) {
    report_lines <- c(report_lines,
      "## Detailed Performance Analysis",
      "",
      "### Parsing Robustness"
    )
    
    for (format_name in names(benchmark_results$parsing$format_results)) {
      result <- benchmark_results$parsing$format_results[[format_name]]
      status <- if (result$target_met) "✅" else "❌"
      
      report_lines <- c(report_lines,
        sprintf("- **%s**: %.0f resp/sec (%.1f%% success) %s", 
               format_name, result$responses_per_second, result$success_rate * 100, status)
      )
    }
  }
  
  # Recommendations section
  report_lines <- c(report_lines,
    "",
    "## Recommendations",
    ""
  )
  
  if (benchmark_results$summary$overall_status == "PASSED") {
    report_lines <- c(report_lines,
      "✅ **Production Deployment**: All systems meet performance requirements",
      "📈 **Monitoring**: Implement performance monitoring in production",
      "🔄 **Regular Testing**: Schedule periodic performance validation",
      "📊 **Scaling**: Current configuration supports production workloads"
    )
  } else {
    if (!benchmark_results$summary$targets_met$parsing) {
      report_lines <- c(report_lines,
        "🔧 **Parsing Optimization**:",
        "- Review JSON parsing implementation",
        "- Consider caching parsed results",
        "- Optimize error handling paths"
      )
    }
    
    if (!is.na(benchmark_results$summary$targets_met$storage) && 
        !benchmark_results$summary$targets_met$storage) {
      report_lines <- c(report_lines,
        "",
        "🗄️ **Storage Optimization**:",
        "- Increase PostgreSQL `shared_buffers`",
        "- Optimize batch insert sizes",
        "- Consider SSD storage",
        "- Review network latency"
      )
    }
    
    if (!is.na(benchmark_results$summary$targets_met$queries) && 
        !benchmark_results$summary$targets_met$queries) {
      report_lines <- c(report_lines,
        "",
        "🔍 **Query Optimization**:",
        "- Add database indexes for common queries",
        "- Review query execution plans",
        "- Consider query result caching"
      )
    }
  }
  
  report_lines <- c(report_lines,
    "",
    "---",
    "*Report generated by IPV Detection Integration Benchmark Suite*"
  )
  
  report_text <- paste(report_lines, collapse = "\n")
  
  if (!is.null(output_file)) {
    writeLines(report_text, output_file)
    cat(sprintf("Integration benchmark report saved to: %s\n", output_file))
  }
  
  return(report_text)
}

# Main execution when run as script
if (!interactive()) {
  cat("IPV Detection Integration Performance Benchmarks\n")
  cat("==============================================\n\n")
  
  args <- commandArgs(trailingOnly = TRUE)
  data_limit <- if ("--full" %in% args) NULL else 50  # Default to sample for speed
  
  # Run benchmarks
  results <- run_integration_benchmarks(
    data_limit = data_limit,
    test_postgres = TRUE,
    test_sqlite = "--sqlite" %in% args
  )
  
  # Generate report
  report_file <- sprintf("integration_benchmarks_%s.md", 
                        format(Sys.time(), "%Y%m%d_%H%M%S"))
  
  generate_integration_report(results, report_file)
  
  # Exit with appropriate code
  exit_code <- if (results$summary$overall_status == "PASSED") 0 else 1
  quit(status = exit_code)
}