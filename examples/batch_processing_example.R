#!/usr/bin/env Rscript

#' Batch Processing Example
#'
#' Demonstrates efficient batch processing of narratives through the IPV detection pipeline.
#' Shows different strategies for handling large datasets, error recovery, and performance optimization.
#' Follows Unix philosophy: let users control loops, parallelization, and error handling.

# Load required functions
source("R/build_prompt.R")
source("R/call_llm.R")
source("R/parse_llm_result.R")
source("R/store_llm_result.R")
source("R/db_utils.R")

cat("=== Batch Processing Example ===\n")

# Example 1: Small Batch Processing with Error Handling
cat("\n=== Example 1: Small Batch (Sequential) ===\n")

# Sample narratives for demonstration
sample_narratives <- list(
  list(id = "case_001", text = "Motor vehicle accident on Interstate 95"),
  list(id = "case_002", text = "Woman found dead, apparent strangulation by ex-boyfriend"), 
  list(id = "case_003", text = "Self-inflicted gunshot wound in garage"),
  list(id = "case_004", text = "Shot multiple times by former intimate partner"),
  list(id = "case_005", text = "Overdose of prescription medication"),
  list(id = "case_006", text = "Beaten to death by current boyfriend during argument"),
  list(id = "case_007", text = "Jumped from bridge after leaving suicide note"),
  list(id = "case_008", text = "Stabbed by ex-husband during custody exchange")
)

# Set up database
db_path <- "batch_example.db"
conn <- get_db_connection(db_path)
ensure_schema(conn)

# Define prompts  
system_prompt <- "You are analyzing death narratives for intimate partner violence (IPV). 
Respond with JSON: {\"detected\": true/false, \"confidence\": 0.0-1.0, \"reasoning\": \"brief explanation\"}"

# Process small batch sequentially
cat(sprintf("Processing %d narratives sequentially...\n", length(sample_narratives)))

results <- list()
start_time <- Sys.time()

for (i in seq_along(sample_narratives)) {
  narrative <- sample_narratives[[i]]
  cat(sprintf("[%d/%d] Processing %s... ", i, length(sample_narratives), narrative$id))
  
  # Call LLM with error handling
  llm_result <- tryCatch({
    call_llm(
      user_prompt = narrative$text,
      system_prompt = system_prompt,
      model = "gpt-4o-mini"  # Use faster model for batch processing
    )
  }, error = function(e) {
    list(error = TRUE, error_message = e$message)
  })
  
  # Parse result
  parsed <- parse_llm_result(llm_result, narrative_id = narrative$id)
  
  # Store in database immediately (fail-fast approach)
  store_result <- store_llm_result(parsed, conn = conn, auto_close = FALSE)
  
  if (!store_result$success) {
    cat(sprintf("❌ Storage failed: %s\n", store_result$error))
  } else if (parsed$parse_error) {
    cat(sprintf("❌ Parse error: %s\n", parsed$error_message))
  } else {
    cat(sprintf("✓ IPV: %s (%.2f)\n", parsed$detected, parsed$confidence))
  }
  
  results[[narrative$id]] <- parsed
  
  # Rate limiting (be respectful to API)
  Sys.sleep(0.5)
}

processing_time <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
cat(sprintf("Sequential processing completed in %.1f seconds\n", processing_time))

# Example 2: Batch Storage with Optimized Performance
cat("\n=== Example 2: Batch Storage Optimization ===\n")

# Simulate larger dataset
larger_narratives <- lapply(1:50, function(i) {
  list(
    id = sprintf("batch_%03d", i),
    text = sample(c(
      "Motor vehicle accident", 
      "Shot by intimate partner",
      "Suicide by hanging",
      "Domestic violence incident",
      "Overdose incident",
      "Stabbing by ex-boyfriend"
    ), 1)
  )
})

cat(sprintf("Processing %d narratives with batch storage...\n", length(larger_narratives)))

# Process and collect results (don't store individually)
batch_results <- list()
batch_start <- Sys.time()

for (i in seq_along(larger_narratives)) {
  narrative <- larger_narratives[[i]]
  
  # Simulate LLM call (using mock data for speed)
  mock_response <- list(
    choices = list(list(message = list(content = sprintf(
      '{"detected": %s, "confidence": %.2f, "reasoning": "Mock response"}',
      ifelse(runif(1) > 0.7, "true", "false"),
      runif(1, 0.3, 0.95)
    )))),
    usage = list(prompt_tokens = 50, completion_tokens = 20, total_tokens = 70),
    model = "gpt-4o-mini"
  )
  
  parsed <- parse_llm_result(mock_response, narrative_id = narrative$id)
  parsed$narrative_text <- narrative$text  # Add narrative text for storage
  batch_results[[i]] <- parsed
  
  if (i %% 10 == 0) {
    cat(sprintf("Processed %d/%d narratives...\n", i, length(larger_narratives)))
  }
}

# Batch store all results at once
cat("Storing batch results in database...\n")
batch_store_result <- store_llm_results_batch(batch_results, db_path = db_path, conn = conn)

batch_time <- as.numeric(difftime(Sys.time(), batch_start, units = "secs"))

cat(sprintf("Batch processing summary:\n"))
cat(sprintf("  Total narratives: %d\n", batch_store_result$total))
cat(sprintf("  Successfully stored: %d\n", batch_store_result$inserted))
cat(sprintf("  Duplicates: %d\n", batch_store_result$duplicates))
cat(sprintf("  Errors: %d\n", batch_store_result$errors))
cat(sprintf("  Success rate: %.1f%%\n", batch_store_result$success_rate * 100))
cat(sprintf("  Processing time: %.1f seconds\n", batch_time))
cat(sprintf("  Rate: %.1f records/second\n", batch_store_result$total / batch_time))

# Example 3: Chunked Processing for Large Datasets
cat("\n=== Example 3: Chunked Processing Strategy ===\n")

# Simulate very large dataset
large_dataset_size <- 1000
chunk_size <- 100

cat(sprintf("Demonstrating chunked processing for %d records (chunks of %d)\n", 
           large_dataset_size, chunk_size))

# Function to process a chunk
process_chunk <- function(chunk_data, chunk_num, total_chunks) {
  cat(sprintf("Processing chunk %d/%d (%d records)...\n", 
             chunk_num, total_chunks, length(chunk_data)))
  
  chunk_results <- list()
  for (i in seq_along(chunk_data)) {
    # Simulate processing
    mock_result <- list(
      narrative_id = chunk_data[[i]]$id,
      narrative_text = chunk_data[[i]]$text,
      detected = runif(1) > 0.75,
      confidence = runif(1, 0.4, 0.95),
      model = "gpt-4o-mini",
      prompt_tokens = sample(40:60, 1),
      completion_tokens = sample(15:25, 1),
      total_tokens = sample(55:85, 1),
      response_time_ms = sample(800:1200, 1),
      raw_response = '{"detected": true, "confidence": 0.85}',
      parse_error = FALSE
    )
    chunk_results[[i]] <- mock_result
  }
  
  # Store chunk
  store_result <- store_llm_results_batch(chunk_results, db_path = db_path, conn = conn)
  
  return(list(
    chunk_num = chunk_num,
    processed = length(chunk_data),
    stored = store_result$inserted,
    errors = store_result$errors
  ))
}

# Create large dataset
large_narratives <- lapply(1:large_dataset_size, function(i) {
  list(
    id = sprintf("large_%04d", i),
    text = paste("Narrative", i, "with various content")
  )
})

# Split into chunks
chunks <- split(large_narratives, ceiling(seq_along(large_narratives) / chunk_size))
total_chunks <- length(chunks)

cat(sprintf("Split %d records into %d chunks\n", large_dataset_size, total_chunks))

# Process chunks
chunk_start <- Sys.time()
chunk_results <- list()

for (i in seq_along(chunks)) {
  chunk_result <- process_chunk(chunks[[i]], i, total_chunks)
  chunk_results[[i]] <- chunk_result
  
  # Progress update
  if (i %% 2 == 0) {
    elapsed <- as.numeric(difftime(Sys.time(), chunk_start, units = "secs"))
    rate <- sum(sapply(chunk_results, function(x) x$processed)) / elapsed
    eta <- (large_dataset_size - sum(sapply(chunk_results, function(x) x$processed))) / rate
    cat(sprintf("Progress: %.1f%%, Rate: %.1f records/sec, ETA: %.0f sec\n", 
               (i/total_chunks)*100, rate, eta))
  }
}

chunk_total_time <- as.numeric(difftime(Sys.time(), chunk_start, units = "secs"))
total_processed <- sum(sapply(chunk_results, function(x) x$processed))
total_stored <- sum(sapply(chunk_results, function(x) x$stored))
total_errors <- sum(sapply(chunk_results, function(x) x$errors))

cat(sprintf("Chunked processing completed:\n"))
cat(sprintf("  Total processed: %d\n", total_processed))
cat(sprintf("  Total stored: %d\n", total_stored))
cat(sprintf("  Total errors: %d\n", total_errors))
cat(sprintf("  Processing time: %.1f seconds\n", chunk_total_time))
cat(sprintf("  Overall rate: %.1f records/second\n", total_processed / chunk_total_time))

# Example 4: Error Recovery and Retry Logic
cat("\n=== Example 4: Error Recovery Strategy ===\n")

# Function with retry logic
process_with_retry <- function(narrative, max_retries = 3) {
  for (attempt in 1:max_retries) {
    result <- tryCatch({
      # Simulate occasional failures
      if (runif(1) < 0.2) {  # 20% failure rate for demonstration
        stop("Simulated API timeout")
      }
      
      # Mock successful response
      list(
        choices = list(list(message = list(content = '{"detected": true, "confidence": 0.85}'))),
        usage = list(prompt_tokens = 45, completion_tokens = 18, total_tokens = 63),
        model = "gpt-4o-mini"
      )
    }, error = function(e) {
      if (attempt < max_retries) {
        wait_time <- 2^(attempt - 1)  # Exponential backoff: 1, 2, 4 seconds
        cat(sprintf("  Attempt %d failed: %s. Retrying in %d seconds...\n", 
                   attempt, e$message, wait_time))
        Sys.sleep(wait_time)
        NULL
      } else {
        cat(sprintf("  All %d attempts failed: %s\n", max_retries, e$message))
        list(error = TRUE, error_message = e$message)
      }
    })
    
    if (!is.null(result)) {
      if (attempt > 1) {
        cat(sprintf("  ✓ Succeeded on attempt %d\n", attempt))
      }
      return(result)
    }
  }
}

# Test retry logic
cat("Testing retry logic with simulated failures...\n")
test_narratives <- sample_narratives[1:5]

retry_results <- list()
for (i in seq_along(test_narratives)) {
  narrative <- test_narratives[[i]]
  cat(sprintf("Processing %s...\n", narrative$id))
  
  llm_result <- process_with_retry(narrative)
  parsed <- parse_llm_result(llm_result, narrative_id = narrative$id)
  retry_results[[narrative$id]] <- parsed
  
  if (parsed$parse_error) {
    cat(sprintf("  ❌ Final result: Parse error\n"))
  } else {
    cat(sprintf("  ✓ Final result: IPV %s (%.2f)\n", parsed$detected, parsed$confidence))
  }
}

# Example 5: Performance Monitoring and Metrics
cat("\n=== Example 5: Performance Monitoring ===\n")

# Query database for performance metrics
cat("Database performance metrics:\n")

# Count total records by database type
db_type <- detect_db_type(conn)
total_records <- DBI::dbGetQuery(conn, "SELECT COUNT(*) as count FROM llm_results")$count
cat(sprintf("  Database type: %s\n", db_type))
cat(sprintf("  Total records: %d\n", total_records))

# Performance by model
model_stats <- DBI::dbGetQuery(conn, "
  SELECT model, 
         COUNT(*) as count,
         AVG(response_time_ms) as avg_response_time,
         AVG(total_tokens) as avg_tokens,
         SUM(CASE WHEN detected = 1 THEN 1 ELSE 0 END) as ipv_detected
  FROM llm_results 
  WHERE model IS NOT NULL
  GROUP BY model
  ORDER BY count DESC
")

if (nrow(model_stats) > 0) {
  cat("  Model performance:\n")
  for (i in 1:nrow(model_stats)) {
    row <- model_stats[i,]
    cat(sprintf("    %s: %d calls, %.0f ms avg, %.0f tokens avg, %.1f%% IPV\n",
               row$model, row$count, row$avg_response_time %||% 0, 
               row$avg_tokens %||% 0, (row$ipv_detected / row$count) * 100))
  }
}

# Processing rate over time  
recent_stats <- DBI::dbGetQuery(conn, "
  SELECT DATE(created_at) as date,
         COUNT(*) as daily_count,
         AVG(response_time_ms) as avg_response_time
  FROM llm_results 
  WHERE created_at >= DATE('now', '-7 days')
  GROUP BY DATE(created_at)
  ORDER BY date DESC
")

if (nrow(recent_stats) > 0) {
  cat("  Recent processing rates:\n")
  for (i in 1:nrow(recent_stats)) {
    row <- recent_stats[i,]
    cat(sprintf("    %s: %d records, %.0f ms avg response\n",
               row$date, row$daily_count, row$avg_response_time %||% 0))
  }
}

# Clean up
close_db_connection(conn)

# Clean up test database
if (file.exists(db_path)) {
  file.remove(db_path)
  cat(sprintf("Cleaned up: %s\n", db_path))
}

cat("\n✓ Batch processing examples completed!\n")
cat("\nKey strategies:\n")
cat("1. Sequential processing: Simple, reliable, good for small batches\n")
cat("2. Batch storage: Collect results, then store in bulk for efficiency\n")  
cat("3. Chunked processing: Handle large datasets without memory issues\n")
cat("4. Retry logic: Handle temporary failures with exponential backoff\n")
cat("5. Performance monitoring: Track metrics to optimize processing\n")
cat("\nChoose the strategy that fits your data size and reliability needs.\n")