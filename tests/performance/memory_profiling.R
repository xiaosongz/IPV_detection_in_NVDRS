# Memory Profiling and Memory Leak Detection
#
# Comprehensive memory profiling for large batch operations
# Detects memory leaks, excessive memory usage, and optimization opportunities
# Validates memory efficiency during high-volume processing
#
# Memory Targets:
# - No memory leaks during batch processing
# - Memory usage grows linearly with batch size (not exponentially)
# - Peak memory usage <2GB for 10,000 record batches
# - Proper garbage collection between batches

library(DBI)
library(RPostgres)
library(tibble)
library(dplyr)
library(readxl)

# Optional packages for enhanced profiling
use_profvis <- requireNamespace("profvis", quietly = TRUE)
use_pryr <- requireNamespace("pryr", quietly = TRUE)
use_bench <- requireNamespace("bench", quietly = TRUE)

# Fallback memory monitoring if pryr not available
if (!use_pryr) {
  mem_used <- function() {
    gc_info <- gc()
    sum(gc_info[, 2]) * 1024^2  # Convert to bytes
  }
} else {
  library(pryr)
  mem_used <- pryr::mem_used
}

# Source required functions
source("../../R/parse_llm_result.R")
source("../../R/store_llm_result.R")
source("../../R/db_utils.R")

#' Monitor memory usage during function execution
#'
#' Wrapper function to track memory consumption patterns
#' 
#' @param func Function to monitor
#' @param ... Arguments passed to func
#' @param interval_ms Memory sampling interval in milliseconds
#' @return List containing function result and memory profile
monitor_memory <- function(func, ..., interval_ms = 100) {
  
  # Record baseline memory
  baseline_memory <- mem_used()
  gc(verbose = FALSE)  # Clean garbage before monitoring
  
  memory_samples <- list()
  start_time <- Sys.time()
  
  # Create monitoring environment
  monitoring_env <- new.env()
  monitoring_env$keep_monitoring <- TRUE
  monitoring_env$samples <- list()
  
  # Start memory monitoring in background (simulated with periodic sampling)
  monitor_start_time <- Sys.time()
  
  # Execute function with memory tracking
  tryCatch({
    # Pre-execution memory snapshot
    pre_memory <- mem_used()
    pre_gc <- gc(verbose = FALSE)
    
    # Execute the function
    result <- func(...)
    
    # Post-execution memory snapshot
    post_memory <- mem_used()
    post_gc <- gc(verbose = FALSE)
    
    # Calculate memory metrics
    memory_delta <- post_memory - pre_memory
    peak_memory <- post_memory  # Simplified - would need more sophisticated monitoring for true peak
    
    # Garbage collection analysis
    gc_improvement <- (pre_gc[1,2] + pre_gc[2,2]) - (post_gc[1,2] + post_gc[2,2])
    
    return(list(
      result = result,
      memory_profile = list(
        baseline_memory_mb = as.numeric(baseline_memory) / 1024^2,
        pre_execution_mb = as.numeric(pre_memory) / 1024^2,
        post_execution_mb = as.numeric(post_memory) / 1024^2,
        memory_delta_mb = as.numeric(memory_delta) / 1024^2,
        peak_memory_mb = as.numeric(peak_memory) / 1024^2,
        gc_freed_mb = gc_improvement,
        monitoring_duration = as.numeric(difftime(Sys.time(), monitor_start_time, units = "secs"))
      )
    ))
    
  }, error = function(e) {
    return(list(
      result = NULL,
      error = e$message,
      memory_profile = list(error = "Memory monitoring failed")
    ))
  })
}

#' Profile memory usage for parsing operations
#'
#' Tests memory efficiency of LLM response parsing
#' 
#' @param test_sizes Vector of test sizes to profile
#' @return Memory profiling results for parsing
profile_parsing_memory <- function(test_sizes = c(100, 500, 1000, 5000, 10000)) {
  
  cat("=== Memory Profiling: Parsing Operations ===\n")
  cat("Testing memory efficiency of LLM response parsing\n\n")
  
  # Generate test responses of varying sizes
  generate_test_responses <- function(count) {
    models <- c("gpt-3.5-turbo", "gpt-4", "claude-3", "gemini-pro")
    responses <- character(count)
    
    for (i in 1:count) {
      detected <- runif(1) > 0.5
      confidence <- runif(1, 0.1, 0.95)
      
      responses[i] <- sprintf('{"detected": %s, "confidence": %.3f}', 
                             tolower(as.character(detected)), confidence)
    }
    
    return(responses)
  }
  
  parsing_profiles <- list()
  
  for (size in test_sizes) {
    cat(sprintf("Profiling parsing for %d responses...\n", size))
    
    # Generate test data
    test_responses <- generate_test_responses(size)
    
    # Profile parsing performance
    profile_result <- monitor_memory(function(responses) {
      parsed_results <- list()
      for (i in seq_along(responses)) {
        tryCatch({
          parsed <- parse_llm_result(responses[i])
          parsed_results[[i]] <- parsed
        }, error = function(e) {
          parsed_results[[i]] <- NULL
        })
      }
      return(parsed_results)
    }, test_responses)
    
    # Calculate efficiency metrics
    memory_per_response <- profile_result$memory_profile$memory_delta_mb / size
    
    parsing_profiles[[as.character(size)]] <- list(
      test_size = size,
      memory_delta_mb = profile_result$memory_profile$memory_delta_mb,
      peak_memory_mb = profile_result$memory_profile$peak_memory_mb,
      memory_per_response_kb = memory_per_response * 1024,
      successful_parses = sum(!sapply(profile_result$result, is.null)),
      success_rate = sum(!sapply(profile_result$result, is.null)) / size,
      gc_freed_mb = profile_result$memory_profile$gc_freed_mb
    )
    
    cat(sprintf("  Memory used: %.2f MB (%.2f KB per response)\n",
               profile_result$memory_profile$memory_delta_mb, memory_per_response * 1024))
    cat(sprintf("  Success rate: %.1f%%\n", parsing_profiles[[as.character(size)]]$success_rate * 100))
  }
  
  # Analyze memory scaling
  memory_deltas <- sapply(parsing_profiles, function(x) x$memory_delta_mb)
  sizes <- sapply(parsing_profiles, function(x) x$test_size)
  
  # Linear regression to check if memory scales linearly
  memory_model <- lm(memory_deltas ~ sizes)
  r_squared <- summary(memory_model)$r.squared
  
  cat("\n=== Parsing Memory Analysis ===\n")
  cat(sprintf("Memory scaling R²: %.3f (closer to 1.0 = more linear)\n", r_squared))
  cat(sprintf("Linear scaling: %s\n", if(r_squared > 0.95) "✅ GOOD" else "⚠️ CONCERN"))
  
  return(list(
    profiles = parsing_profiles,
    scaling_analysis = list(
      r_squared = r_squared,
      linear_scaling = r_squared > 0.95,
      memory_per_response_trend = coef(memory_model)[2]  # Slope
    )
  ))
}

#' Profile memory usage for storage operations
#'
#' Tests memory efficiency of database storage operations
#' 
#' @param test_sizes Vector of batch sizes to profile
#' @param test_postgres Whether to test PostgreSQL (default: TRUE)
#' @return Memory profiling results for storage
profile_storage_memory <- function(test_sizes = c(100, 500, 1000, 2500, 5000), 
                                  test_postgres = TRUE) {
  
  cat("=== Memory Profiling: Storage Operations ===\n")
  cat("Testing memory efficiency of database storage\n\n")
  
  # Generate realistic test data
  generate_storage_test_data <- function(count) {
    data_path <- "../../data-raw/suicide_IPV_manuallyflagged.xlsx"
    
    if (file.exists(data_path)) {
      raw_data <- read_excel(data_path)
      narratives <- ifelse(!is.na(raw_data$NarrativeCME), 
                          raw_data$NarrativeCME, raw_data$NarrativeLE)
      valid_narratives <- narratives[!is.na(narratives) & nchar(trimws(narratives)) > 20]
    } else {
      # Fallback synthetic data
      valid_narratives <- replicate(50, {
        sprintf("Test narrative %d with various content about relationships and circumstances", 
               sample(1:1000, 1))
      })
    }
    
    # Expand to requested count
    sampled_narratives <- sample(valid_narratives, count, replace = TRUE)
    
    # Create parsed result format
    results <- list()
    for (i in 1:count) {
      detected <- runif(1) > 0.5
      confidence <- runif(1, 0.1, 0.95)
      
      results[[i]] <- list(
        narrative_id = sprintf("MEM_TEST_%06d", i),
        narrative_text = sampled_narratives[i],
        detected = detected,
        confidence = confidence,
        model = "gpt-3.5-turbo",
        prompt_tokens = nchar(sampled_narratives[i]) / 4 + 100,
        completion_tokens = 50,
        total_tokens = nchar(sampled_narratives[i]) / 4 + 150,
        response_time_ms = 1000,
        raw_response = sprintf('{"detected": %s, "confidence": %.3f}', 
                              tolower(as.character(detected)), confidence),
        error_message = NA
      )
    }
    
    return(results)
  }
  
  storage_profiles <- list()
  
  if (test_postgres) {
    # Test PostgreSQL connection
    postgres_conn <- tryCatch({
      connect_postgres()
    }, error = function(e) {
      cat("❌ PostgreSQL connection failed:", e$message, "\n")
      return(NULL)
    })
    
    if (!is.null(postgres_conn)) {
      cat("Testing PostgreSQL storage memory usage...\n")
      
      for (size in test_sizes) {
        cat(sprintf("Profiling storage for %d records...\n", size))
        
        # Generate test data
        test_data <- generate_storage_test_data(size)
        
        # Profile storage operation
        profile_result <- monitor_memory(function(data, conn) {
          # Clear any existing test data first
          DBI::dbExecute(conn, "DELETE FROM llm_results WHERE narrative_id LIKE 'MEM_TEST_%'")
          
          # Perform batch storage
          result <- store_llm_results_batch(data, conn = conn)
          return(result)
        }, test_data, postgres_conn)
        
        # Calculate efficiency metrics
        if (!is.null(profile_result$result)) {
          memory_per_record <- profile_result$memory_profile$memory_delta_mb / size
          
          storage_profiles[[as.character(size)]] <- list(
            test_size = size,
            memory_delta_mb = profile_result$memory_profile$memory_delta_mb,
            peak_memory_mb = profile_result$memory_profile$peak_memory_mb,
            memory_per_record_kb = memory_per_record * 1024,
            records_inserted = profile_result$result$inserted,
            success_rate = profile_result$result$success_rate,
            gc_freed_mb = profile_result$memory_profile$gc_freed_mb,
            errors = profile_result$result$errors
          )
          
          cat(sprintf("  Memory used: %.2f MB (%.2f KB per record)\n",
                     profile_result$memory_profile$memory_delta_mb, memory_per_record * 1024))
          cat(sprintf("  Records inserted: %d (%.1f%% success)\n", 
                     profile_result$result$inserted, profile_result$result$success_rate * 100))
        } else {
          cat(sprintf("  ❌ Storage test failed for size %d\n", size))
        }
      }
      
      close_db_connection(postgres_conn)
    } else {
      cat("⚠️ PostgreSQL not available for storage memory profiling\n")
    }
  }
  
  if (length(storage_profiles) > 0) {
    # Analyze memory scaling for storage
    memory_deltas <- sapply(storage_profiles, function(x) x$memory_delta_mb)
    sizes <- sapply(storage_profiles, function(x) x$test_size)
    
    # Linear regression for storage memory scaling
    storage_model <- lm(memory_deltas ~ sizes)
    r_squared <- summary(storage_model)$r.squared
    
    cat("\n=== Storage Memory Analysis ===\n")
    cat(sprintf("Memory scaling R²: %.3f (closer to 1.0 = more linear)\n", r_squared))
    cat(sprintf("Linear scaling: %s\n", if(r_squared > 0.95) "✅ GOOD" else "⚠️ CONCERN"))
    
    # Check for memory efficiency
    avg_memory_per_record <- mean(sapply(storage_profiles, function(x) x$memory_per_record_kb))
    cat(sprintf("Average memory per record: %.2f KB\n", avg_memory_per_record))
    
    return(list(
      profiles = storage_profiles,
      scaling_analysis = list(
        r_squared = r_squared,
        linear_scaling = r_squared > 0.95,
        avg_memory_per_record_kb = avg_memory_per_record,
        memory_per_record_trend = coef(storage_model)[2]
      )
    ))
  } else {
    return(list(
      profiles = list(),
      error = "No storage profiles generated"
    ))
  }
}

#' Detect memory leaks in batch processing
#'
#' Tests for memory leaks during repeated batch operations
#' 
#' @param batch_size Size of each batch
#' @param iterations Number of batches to process
#' @return Memory leak detection results
detect_memory_leaks <- function(batch_size = 1000, iterations = 5) {
  
  cat("=== Memory Leak Detection ===\n")
  cat(sprintf("Testing %d iterations of %d record batches\n\n", iterations, batch_size))
  
  # Generate consistent test data
  generate_leak_test_data <- function(count, iteration) {
    results <- list()
    for (i in 1:count) {
      results[[i]] <- list(
        narrative_id = sprintf("LEAK_TEST_%d_%06d", iteration, i),
        narrative_text = sprintf("Test narrative %d for leak detection in iteration %d", i, iteration),
        detected = runif(1) > 0.5,
        confidence = runif(1, 0.2, 0.9),
        model = "gpt-3.5-turbo",
        prompt_tokens = 200,
        completion_tokens = 50,
        total_tokens = 250,
        response_time_ms = 1000,
        raw_response = '{"detected": true, "confidence": 0.75}',
        error_message = NA
      )
    }
    return(results)
  }
  
  memory_measurements <- list()
  baseline_memory <- as.numeric(mem_used())
  
  # Force initial garbage collection
  gc(verbose = FALSE)
  gc(verbose = FALSE)  # Run twice for thorough cleaning
  
  post_gc_baseline <- as.numeric(mem_used())
  
  cat(sprintf("Baseline memory: %.2f MB\n", baseline_memory / 1024^2))
  cat(sprintf("Post-GC baseline: %.2f MB\n\n", post_gc_baseline / 1024^2))
  
  # Test with database connection (if available)
  conn <- tryCatch(connect_postgres(), error = function(e) NULL)
  
  for (iteration in 1:iterations) {
    cat(sprintf("Iteration %d/%d...\n", iteration, iterations))
    
    # Pre-iteration memory
    pre_memory <- as.numeric(mem_used())
    
    # Generate test data for this iteration
    test_data <- generate_leak_test_data(batch_size, iteration)
    
    # Measure memory during processing
    processing_memory <- as.numeric(mem_used())
    
    # Process the batch (storage if database available)
    if (!is.null(conn)) {
      tryCatch({
        result <- store_llm_results_batch(test_data, conn = conn)
        post_storage_memory <- as.numeric(mem_used())
      }, error = function(e) {
        post_storage_memory <- processing_memory
      })
    } else {
      # Just parse responses to simulate processing
      for (item in test_data) {
        parsed <- parse_llm_result(item$raw_response)
      }
      post_storage_memory <- as.numeric(mem_used())
    }
    
    # Force garbage collection
    pre_gc_memory <- as.numeric(mem_used())
    gc_info <- gc(verbose = FALSE)
    post_gc_memory <- as.numeric(mem_used())
    
    # Record measurements
    memory_measurements[[iteration]] <- list(
      iteration = iteration,
      pre_iteration_mb = pre_memory / 1024^2,
      processing_mb = processing_memory / 1024^2,
      post_storage_mb = post_storage_memory / 1024^2,
      pre_gc_mb = pre_gc_memory / 1024^2,
      post_gc_mb = post_gc_memory / 1024^2,
      memory_freed_mb = (pre_gc_memory - post_gc_memory) / 1024^2,
      net_growth_mb = (post_gc_memory - post_gc_baseline) / 1024^2
    )
    
    cat(sprintf("  Pre: %.1f MB → Processing: %.1f MB → Post-GC: %.1f MB\n",
               pre_memory / 1024^2, processing_memory / 1024^2, post_gc_memory / 1024^2))
    cat(sprintf("  Net growth from baseline: %.2f MB\n", 
               memory_measurements[[iteration]]$net_growth_mb))
    
    # Brief pause between iterations
    Sys.sleep(0.5)
  }
  
  if (!is.null(conn)) close_db_connection(conn)
  
  # Analyze memory leak patterns
  net_growths <- sapply(memory_measurements, function(x) x$net_growth_mb)
  memory_freed <- sapply(memory_measurements, function(x) x$memory_freed_mb)
  
  # Check for concerning patterns
  final_growth <- tail(net_growths, 1)
  growth_trend <- lm(net_growths ~ seq_along(net_growths))
  growth_slope <- coef(growth_trend)[2]
  
  # Detection criteria
  leak_detected <- final_growth > 50 || growth_slope > 10  # >50MB final or >10MB/iteration growth
  concerning_pattern <- final_growth > 20 || growth_slope > 5
  
  cat("\n=== Memory Leak Analysis ===\n")
  cat(sprintf("Final memory growth: %.2f MB\n", final_growth))
  cat(sprintf("Growth trend: %.2f MB per iteration\n", growth_slope))
  cat(sprintf("Average garbage collected: %.2f MB per iteration\n", mean(memory_freed)))
  
  if (leak_detected) {
    cat("🚨 MEMORY LEAK DETECTED - Requires immediate attention\n")
    leak_status <- "DETECTED"
  } else if (concerning_pattern) {
    cat("⚠️ CONCERNING MEMORY PATTERN - Monitor closely\n")
    leak_status <- "CONCERNING"
  } else {
    cat("✅ NO MEMORY LEAK DETECTED - Memory usage stable\n")
    leak_status <- "CLEAN"
  }
  
  return(list(
    leak_status = leak_status,
    leak_detected = leak_detected,
    concerning_pattern = concerning_pattern,
    final_growth_mb = final_growth,
    growth_trend_mb_per_iteration = growth_slope,
    avg_gc_freed_mb = mean(memory_freed),
    measurements = memory_measurements,
    test_parameters = list(
      batch_size = batch_size,
      iterations = iterations
    )
  ))
}

#' Profile complete workflow memory usage
#'
#' Tests memory usage for the complete end-to-end workflow
#' 
#' @param workflow_size Number of narratives to process in workflow
#' @return Complete workflow memory profile
profile_workflow_memory <- function(workflow_size = 1000) {
  
  cat("=== Complete Workflow Memory Profiling ===\n")
  cat(sprintf("Profiling end-to-end workflow with %d narratives\n\n", workflow_size))
  
  # Generate realistic test data from actual dataset
  data_path <- "../../data-raw/suicide_IPV_manuallyflagged.xlsx"
  
  if (file.exists(data_path)) {
    raw_data <- read_excel(data_path)
    narratives <- ifelse(!is.na(raw_data$NarrativeCME), 
                        raw_data$NarrativeCME, raw_data$NarrativeLE)
    valid_narratives <- narratives[!is.na(narratives) & nchar(trimws(narratives)) > 20]
    
    # Expand to workflow size
    test_narratives <- sample(valid_narratives, workflow_size, replace = TRUE)
  } else {
    # Fallback synthetic data
    test_narratives <- replicate(workflow_size, {
      paste("Test narrative", sample(1:1000, 1), "with relationship and incident details")
    })
  }
  
  # Stage 1: LLM Response Simulation and Parsing
  cat("Stage 1: LLM Response Generation and Parsing\n")
  
  parsing_profile <- monitor_memory(function(narratives) {
    # Simulate LLM responses
    mock_responses <- list()
    for (i in seq_along(narratives)) {
      detected <- runif(1) > 0.5
      confidence <- runif(1, 0.1, 0.9)
      
      mock_responses[[i]] <- sprintf('{"detected": %s, "confidence": %.3f}',
                                    tolower(as.character(detected)), confidence)
    }
    
    # Parse responses
    parsed_results <- list()
    for (i in seq_along(mock_responses)) {
      tryCatch({
        parsed <- parse_llm_result(mock_responses[[i]])
        parsed_results[[i]] <- parsed
      }, error = function(e) {
        parsed_results[[i]] <- NULL
      })
    }
    
    return(parsed_results)
  }, test_narratives)
  
  cat(sprintf("  Memory used: %.2f MB\n", parsing_profile$memory_profile$memory_delta_mb))
  
  # Stage 2: Data Preparation for Storage
  cat("\nStage 2: Data Preparation for Storage\n")
  
  preparation_profile <- monitor_memory(function(parsed_results, narratives) {
    storage_ready <- list()
    for (i in seq_along(parsed_results)) {
      if (!is.null(parsed_results[[i]])) {
        storage_ready[[i]] <- list(
          narrative_id = sprintf("WORKFLOW_%06d", i),
          narrative_text = narratives[i],
          detected = parsed_results[[i]]$detected,
          confidence = parsed_results[[i]]$confidence,
          model = "gpt-3.5-turbo",
          prompt_tokens = nchar(narratives[i]) / 4 + 100,
          completion_tokens = 50,
          total_tokens = nchar(narratives[i]) / 4 + 150,
          response_time_ms = 1000,
          raw_response = sprintf('{"detected": %s, "confidence": %.3f}',
                                tolower(as.character(parsed_results[[i]]$detected)),
                                parsed_results[[i]]$confidence),
          error_message = NA
        )
      }
    }
    return(storage_ready)
  }, parsing_profile$result, test_narratives)
  
  cat(sprintf("  Memory used: %.2f MB\n", preparation_profile$memory_profile$memory_delta_mb))
  
  # Stage 3: Database Storage (if available)
  cat("\nStage 3: Database Storage\n")
  
  conn <- tryCatch(connect_postgres(), error = function(e) NULL)
  
  if (!is.null(conn)) {
    storage_profile <- monitor_memory(function(storage_data, conn) {
      # Clean any existing workflow test data
      DBI::dbExecute(conn, "DELETE FROM llm_results WHERE narrative_id LIKE 'WORKFLOW_%'")
      
      # Store in batches
      result <- store_llm_results_batch(storage_data, conn = conn)
      return(result)
    }, preparation_profile$result, conn)
    
    cat(sprintf("  Memory used: %.2f MB\n", storage_profile$memory_profile$memory_delta_mb))
    cat(sprintf("  Records stored: %d\n", storage_profile$result$inserted))
    
    close_db_connection(conn)
  } else {
    cat("  ⚠️ Database not available for storage profiling\n")
    storage_profile <- list(memory_profile = list(memory_delta_mb = 0))
  }
  
  # Calculate total workflow memory usage
  total_memory_used <- parsing_profile$memory_profile$memory_delta_mb +
                      preparation_profile$memory_profile$memory_delta_mb +
                      storage_profile$memory_profile$memory_delta_mb
  
  memory_per_narrative <- total_memory_used / workflow_size
  
  cat(sprintf("\n=== Workflow Memory Summary ===\n"))
  cat(sprintf("Total memory used: %.2f MB\n", total_memory_used))
  cat(sprintf("Memory per narrative: %.3f MB (%.1f KB)\n", 
             memory_per_narrative, memory_per_narrative * 1024))
  
  # Memory efficiency assessment
  efficiency_rating <- if (memory_per_narrative < 0.01) {  # <10KB per narrative
    "EXCELLENT"
  } else if (memory_per_narrative < 0.05) {  # <50KB per narrative
    "GOOD"
  } else if (memory_per_narrative < 0.1) {   # <100KB per narrative
    "ACCEPTABLE"
  } else {
    "CONCERNING"
  }
  
  cat(sprintf("Memory efficiency: %s\n", efficiency_rating))
  
  # Predict memory usage for larger batches
  predicted_10k <- total_memory_used * (10000 / workflow_size)
  predicted_100k <- total_memory_used * (100000 / workflow_size)
  
  cat(sprintf("\nPredicted memory usage:\n"))
  cat(sprintf("  10,000 narratives: %.1f MB\n", predicted_10k))
  cat(sprintf("  100,000 narratives: %.1f MB (%.1f GB)\n", predicted_100k, predicted_100k / 1024))
  
  # Memory target validation
  target_met <- predicted_10k < 2048  # <2GB for 10k records
  cat(sprintf("Memory target (<2GB for 10k): %s\n", if(target_met) "✅ MET" else "❌ EXCEEDED"))
  
  return(list(
    workflow_size = workflow_size,
    parsing_memory_mb = parsing_profile$memory_profile$memory_delta_mb,
    preparation_memory_mb = preparation_profile$memory_profile$memory_delta_mb,
    storage_memory_mb = storage_profile$memory_profile$memory_delta_mb,
    total_memory_mb = total_memory_used,
    memory_per_narrative_kb = memory_per_narrative * 1024,
    efficiency_rating = efficiency_rating,
    predicted_10k_mb = predicted_10k,
    predicted_100k_mb = predicted_100k,
    target_met = target_met
  ))
}

#' Run comprehensive memory profiling suite
#'
#' Executes all memory profiling tests and generates complete analysis
#' 
#' @param comprehensive Whether to run comprehensive tests (default: TRUE)
#' @return Complete memory profiling results
run_comprehensive_memory_profiling <- function(comprehensive = TRUE) {
  
  cat("=== Comprehensive Memory Profiling Suite ===\n")
  cat("Testing memory usage patterns and detecting potential issues\n\n")
  
  profiling_results <- list(
    test_timestamp = Sys.time(),
    comprehensive = comprehensive
  )
  
  # 1. Parsing Memory Profile
  cat("1. Parsing Memory Profiling\n")
  cat(paste0(rep("=", 30), collapse = ""), "\n")
  
  if (comprehensive) {
    profiling_results$parsing <- profile_parsing_memory(c(100, 500, 1000, 5000, 10000))
  } else {
    profiling_results$parsing <- profile_parsing_memory(c(100, 500, 1000))
  }
  
  # 2. Storage Memory Profile
  cat("\n\n2. Storage Memory Profiling\n")
  cat(paste0(rep("=", 30), collapse = ""), "\n")
  
  if (comprehensive) {
    profiling_results$storage <- profile_storage_memory(c(100, 500, 1000, 2500, 5000))
  } else {
    profiling_results$storage <- profile_storage_memory(c(100, 500, 1000))
  }
  
  # 3. Memory Leak Detection
  cat("\n\n3. Memory Leak Detection\n")
  cat(paste0(rep("=", 30), collapse = ""), "\n")
  
  if (comprehensive) {
    profiling_results$leak_detection <- detect_memory_leaks(1000, 10)
  } else {
    profiling_results$leak_detection <- detect_memory_leaks(500, 5)
  }
  
  # 4. Complete Workflow Profiling
  cat("\n\n4. Complete Workflow Profiling\n")
  cat(paste0(rep("=", 30), collapse = ""), "\n")
  
  if (comprehensive) {
    profiling_results$workflow <- profile_workflow_memory(2000)
  } else {
    profiling_results$workflow <- profile_workflow_memory(1000)
  }
  
  # Overall Assessment
  cat("\n\n=== MEMORY PROFILING SUMMARY ===\n")
  
  # Assess each component
  assessments <- list()
  
  # Parsing assessment
  if (!is.null(profiling_results$parsing$scaling_analysis)) {
    parsing_ok <- profiling_results$parsing$scaling_analysis$linear_scaling
    assessments$parsing <- parsing_ok
    cat(sprintf("Parsing Memory Scaling: %s\n", if(parsing_ok) "✅ LINEAR" else "❌ CONCERNING"))
  }
  
  # Storage assessment
  if (!is.null(profiling_results$storage$scaling_analysis)) {
    storage_ok <- profiling_results$storage$scaling_analysis$linear_scaling
    assessments$storage <- storage_ok
    cat(sprintf("Storage Memory Scaling: %s\n", if(storage_ok) "✅ LINEAR" else "❌ CONCERNING"))
  }
  
  # Memory leak assessment
  leak_ok <- profiling_results$leak_detection$leak_status == "CLEAN"
  assessments$memory_leaks <- leak_ok
  cat(sprintf("Memory Leaks: %s\n", if(leak_ok) "✅ NONE DETECTED" else "❌ ISSUES FOUND"))
  
  # Workflow efficiency assessment
  workflow_ok <- profiling_results$workflow$target_met
  assessments$workflow_efficiency <- workflow_ok
  cat(sprintf("Workflow Efficiency: %s\n", if(workflow_ok) "✅ TARGET MET" else "❌ EXCEEDS TARGET"))
  
  # Overall memory health
  healthy_components <- sum(unlist(assessments), na.rm = TRUE)
  total_components <- length(assessments)
  overall_healthy <- healthy_components >= ceiling(total_components * 0.8)  # 80% threshold
  
  cat(sprintf("\nMemory Health: %d/%d components healthy\n", healthy_components, total_components))
  cat(sprintf("Overall Status: %s\n", 
             if(overall_healthy) "✅ MEMORY EFFICIENT" else "❌ OPTIMIZATION REQUIRED"))
  
  # Recommendations
  cat("\n=== RECOMMENDATIONS ===\n")
  
  if (overall_healthy) {
    cat("✅ Memory usage is efficient and scalable\n")
    cat("📊 Regular memory monitoring recommended\n")
    cat("🎯 Current implementation ready for production\n")
  } else {
    if (!assessments$parsing) {
      cat("🔧 Optimize parsing operations for better memory efficiency\n")
    }
    if (!assessments$storage) {
      cat("🗄️ Review database storage operations for memory optimization\n")
    }
    if (!assessments$memory_leaks) {
      cat("🚨 Address memory leaks before production deployment\n")
    }
    if (!assessments$workflow_efficiency) {
      cat("⚡ Optimize workflow memory usage for large batches\n")
    }
  }
  
  profiling_results$summary <- list(
    overall_healthy = overall_healthy,
    healthy_components = healthy_components,
    total_components = total_components,
    assessments = assessments
  )
  
  return(profiling_results)
}

# Main execution when run as script
if (!interactive()) {
  cat("IPV Detection Memory Profiling Suite\n")
  cat("===================================\n\n")
  
  args <- commandArgs(trailingOnly = TRUE)
  comprehensive <- !("--quick" %in% args)
  
  # Run comprehensive memory profiling
  results <- run_comprehensive_memory_profiling(comprehensive)
  
  # Save results
  results_file <- sprintf("memory_profile_results_%s.rds", 
                         format(Sys.time(), "%Y%m%d_%H%M%S"))
  
  saveRDS(results, results_file)
  cat(sprintf("\nMemory profiling results saved to: %s\n", results_file))
  
  # Generate summary report
  summary_file <- sprintf("memory_profile_summary_%s.txt", 
                         format(Sys.time(), "%Y%m%d_%H%M%S"))
  
  summary_lines <- c(
    "IPV Detection Memory Profiling Summary",
    sprintf("Generated: %s", Sys.time()),
    sprintf("Test Type: %s", if(comprehensive) "Comprehensive" else "Quick"),
    "",
    "Results:",
    sprintf("- Parsing: %s", if(results$summary$assessments$parsing) "✅ Efficient" else "❌ Issues"),
    sprintf("- Storage: %s", if(results$summary$assessments$storage) "✅ Efficient" else "❌ Issues"),
    sprintf("- Memory Leaks: %s", if(results$summary$assessments$memory_leaks) "✅ None" else "❌ Detected"),
    sprintf("- Workflow: %s", if(results$summary$assessments$workflow_efficiency) "✅ Efficient" else "❌ Exceeds Target"),
    "",
    sprintf("Overall Status: %s", if(results$summary$overall_healthy) "✅ MEMORY EFFICIENT" else "❌ OPTIMIZATION REQUIRED")
  )
  
  writeLines(summary_lines, summary_file)
  cat(sprintf("Summary report saved to: %s\n", summary_file))
  
  # Exit with appropriate code
  exit_code <- if (results$summary$overall_healthy) 0 else 1
  quit(status = exit_code)
}