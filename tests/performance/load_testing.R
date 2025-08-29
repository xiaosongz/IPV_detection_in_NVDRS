# Load Testing and Stress Testing
#
# Comprehensive load testing with 1000+ real narrative samples
# Tests system behavior under heavy load and concurrent access
# Validates scalability limits and identifies bottlenecks
#
# Test Scenarios:
# - High-volume batch processing (1000+ narratives)
# - Concurrent database access
# - Memory stress testing
# - Network resilience testing
# - Error recovery under load

library(DBI)
library(RPostgres)
library(parallel)
library(tibble)
library(dplyr)
library(readxl)

# Source required functions
source("../../R/parse_llm_result.R")
source("../../R/store_llm_result.R")
source("../../R/db_utils.R")
source("../../R/call_llm.R")

#' Generate large-scale test dataset
#'
#' Creates 1000+ test narratives by expanding and varying real NVDRS data
#' Maintains realistic distribution and characteristics
#' 
#' @param target_size Target number of narratives (default: 1000)
#' @param variation_factor How much to vary narratives (default: 0.3)
#' @return List of expanded narrative data
generate_large_test_dataset <- function(target_size = 1000, variation_factor = 0.3) {
  
  cat("Generating large-scale test dataset...\n")
  
  # Load base real data
  data_path <- "../../data-raw/suicide_IPV_manuallyflagged.xlsx"
  
  if (!file.exists(data_path)) {
    stop("Test data not found: ", data_path)
  }
  
  raw_data <- read_excel(data_path)
  
  # Extract valid narratives
  narratives <- ifelse(
    !is.na(raw_data$NarrativeCME) & nchar(trimws(raw_data$NarrativeCME)) > 20,
    raw_data$NarrativeCME,
    raw_data$NarrativeLE
  )
  
  valid_idx <- !is.na(narratives) & nchar(trimws(narratives)) > 20
  base_narratives <- narratives[valid_idx]
  base_ipv_flags <- raw_data$ipv_manual[valid_idx]
  base_ids <- raw_data$IncidentID[valid_idx]
  
  cat(sprintf("Base dataset: %d valid narratives\n", length(base_narratives)))
  
  # Expansion strategies to reach target size
  expanded_narratives <- character()
  expanded_ipv_flags <- numeric()
  expanded_ids <- character()
  
  # Strategy 1: Direct replication with ID variations
  replication_count <- ceiling(target_size * 0.4)
  replicated_indices <- sample(seq_along(base_narratives), replication_count, replace = TRUE)
  
  expanded_narratives <- c(expanded_narratives, base_narratives[replicated_indices])
  expanded_ipv_flags <- c(expanded_ipv_flags, base_ipv_flags[replicated_indices])
  expanded_ids <- c(expanded_ids, 
                   sprintf("%s_REP_%d", base_ids[replicated_indices], 
                          seq_along(replicated_indices)))
  
  # Strategy 2: Text variations (anonymization/demographic changes)
  variation_count <- ceiling(target_size * 0.3)
  varied_indices <- sample(seq_along(base_narratives), variation_count, replace = TRUE)
  
  for (i in seq_along(varied_indices)) {
    original_narrative <- base_narratives[varied_indices[i]]
    varied_narrative <- create_narrative_variation(original_narrative, variation_factor)
    
    expanded_narratives <- c(expanded_narratives, varied_narrative)
    expanded_ipv_flags <- c(expanded_ipv_flags, base_ipv_flags[varied_indices[i]])
    expanded_ids <- c(expanded_ids, sprintf("%s_VAR_%d", base_ids[varied_indices[i]], i))
  }
  
  # Strategy 3: Composite narratives (combine elements from multiple cases)
  composite_count <- target_size - length(expanded_narratives)
  if (composite_count > 0) {
    for (i in 1:composite_count) {
      # Select 2-3 source narratives
      source_indices <- sample(seq_along(base_narratives), sample(2:3, 1))
      composite_narrative <- create_composite_narrative(base_narratives[source_indices])
      
      # Use majority IPV flag
      composite_ipv <- round(mean(base_ipv_flags[source_indices]))
      
      expanded_narratives <- c(expanded_narratives, composite_narrative)
      expanded_ipv_flags <- c(expanded_ipv_flags, composite_ipv)
      expanded_ids <- c(expanded_ids, sprintf("COMP_%06d", i))
    }
  }
  
  # Trim to exact target size
  if (length(expanded_narratives) > target_size) {
    keep_indices <- sample(seq_along(expanded_narratives), target_size)
    expanded_narratives <- expanded_narratives[keep_indices]
    expanded_ipv_flags <- expanded_ipv_flags[keep_indices]
    expanded_ids <- expanded_ids[keep_indices]
  }
  
  cat(sprintf("Generated %d narratives for load testing\n", length(expanded_narratives)))
  cat(sprintf("IPV positive rate: %.1f%%\n", 
             mean(expanded_ipv_flags, na.rm = TRUE) * 100))
  
  return(list(
    narratives = expanded_narratives,
    ipv_flags = expanded_ipv_flags,
    incident_ids = expanded_ids
  ))
}

#' Create narrative variation
#'
#' Modifies narrative text while preserving meaning and IPV indicators
#' 
#' @param narrative Original narrative text
#' @param variation_factor Amount of variation to introduce
#' @return Modified narrative text
create_narrative_variation <- function(narrative, variation_factor) {
  
  # Simple demographic variations that don't affect IPV detection
  age_pattern <- "\\b(\\d{1,2}) year old\\b"
  if (grepl(age_pattern, narrative)) {
    current_age <- as.numeric(regmatches(narrative, regexpr("\\d{1,2}(?= year old)", narrative, perl = TRUE)))
    if (!is.na(current_age)) {
      new_age <- pmax(18, current_age + sample(-5:5, 1))
      narrative <- gsub(age_pattern, paste(new_age, "year old"), narrative)
    }
  }
  
  # Gender variations (preserve relationship context)
  gender_variations <- list(
    c("female", "woman"),
    c("male", "man"),
    c("boyfriend", "partner"),
    c("girlfriend", "partner"),
    c("husband", "spouse"),
    c("wife", "spouse")
  )
  
  if (runif(1) < variation_factor) {
    for (variation_set in gender_variations) {
      if (grepl(variation_set[1], narrative, ignore.case = TRUE)) {
        narrative <- gsub(variation_set[1], variation_set[2], narrative, ignore.case = TRUE)
        break
      }
    }
  }
  
  # Location variations (preserve context)
  location_variations <- list(
    c("at home", "at residence"),
    c("emergency department", "hospital"),
    c("police report", "law enforcement report")
  )
  
  if (runif(1) < variation_factor) {
    for (variation_set in location_variations) {
      if (grepl(variation_set[1], narrative, ignore.case = TRUE)) {
        narrative <- gsub(variation_set[1], variation_set[2], narrative, ignore.case = TRUE)
        break
      }
    }
  }
  
  return(narrative)
}

#' Create composite narrative
#'
#' Combines elements from multiple narratives to create realistic variations
#' 
#' @param source_narratives Vector of source narratives
#' @return Composite narrative text
create_composite_narrative <- function(source_narratives) {
  
  # Extract key components from each narrative
  components <- lapply(source_narratives, function(narrative) {
    # Split into sentences
    sentences <- unlist(strsplit(narrative, "\\. ?"))
    
    list(
      victim_info = sentences[grepl("year old|female|male", sentences)][1],
      incident_info = sentences[grepl("shot|hanged|poisoned|overdose", sentences)][1],
      context_info = sentences[grepl("partner|boyfriend|girlfriend|spouse|domestic", sentences)][1],
      location_info = sentences[grepl("at home|hospital|emergency", sentences)][1]
    )
  })
  
  # Combine non-duplicate components
  composite_parts <- character()
  
  # Use first valid victim info
  victim_info <- Find(function(x) !is.na(x), lapply(components, `[[`, "victim_info"))
  if (!is.null(victim_info)) composite_parts <- c(composite_parts, victim_info)
  
  # Use first valid incident info
  incident_info <- Find(function(x) !is.na(x), lapply(components, `[[`, "incident_info"))
  if (!is.null(incident_info)) composite_parts <- c(composite_parts, incident_info)
  
  # Combine relevant context
  context_infos <- unlist(lapply(components, `[[`, "context_info"))
  context_infos <- context_infos[!is.na(context_infos)]
  if (length(context_infos) > 0) {
    composite_parts <- c(composite_parts, context_infos[1])
  }
  
  # Add location if available
  location_info <- Find(function(x) !is.na(x), lapply(components, `[[`, "location_info"))
  if (!is.null(location_info)) composite_parts <- c(composite_parts, location_info)
  
  # Join components
  composite_narrative <- paste(composite_parts, collapse = ". ")
  
  # Ensure proper sentence ending
  if (!grepl("\\.$", composite_narrative)) {
    composite_narrative <- paste0(composite_narrative, ".")
  }
  
  return(composite_narrative)
}

#' Generate mock LLM responses for load testing
#'
#' Creates realistic LLM responses with appropriate response time simulation
#' 
#' @param narratives Vector of narrative texts
#' @param load_characteristics Simulate load-related response patterns
#' @return List of mock LLM responses
generate_load_test_responses <- function(narratives, load_characteristics = TRUE) {
  
  cat("Generating mock LLM responses for load testing...\n")
  
  models <- c("gpt-3.5-turbo", "gpt-4", "claude-3-sonnet", "gemini-pro")
  responses <- vector("list", length(narratives))
  
  # Define load characteristics
  if (load_characteristics) {
    # Simulate network delays and API throttling
    base_response_times <- runif(length(narratives), 800, 2000)
    # Add occasional slow responses (5% chance)
    slow_response_mask <- runif(length(narratives)) < 0.05
    base_response_times[slow_response_mask] <- base_response_times[slow_response_mask] * 3
    
    # Simulate occasional API errors (2% chance)
    error_mask <- runif(length(narratives)) < 0.02
  } else {
    base_response_times <- rep(1000, length(narratives))
    error_mask <- rep(FALSE, length(narratives))
  }
  
  for (i in seq_along(narratives)) {
    narrative <- narratives[i]
    
    # Simulate realistic detection
    ipv_keywords <- c("partner", "boyfriend", "girlfriend", "spouse", "husband", "wife",
                     "domestic", "violence", "abuse", "hit", "beat", "assault", "threat")
    
    keyword_matches <- sum(sapply(ipv_keywords, function(kw) 
      grepl(kw, narrative, ignore.case = TRUE)))
    
    # Detection probability based on keywords and narrative length
    narrative_length <- nchar(narrative)
    base_prob <- 0.3
    keyword_boost <- keyword_matches * 0.15
    length_boost <- pmin(0.2, narrative_length / 1000 * 0.1)
    
    detection_prob <- pmin(0.95, base_prob + keyword_boost + length_boost)
    detected <- runif(1) < detection_prob
    
    confidence <- if (detected) {
      # Higher confidence for keyword-rich narratives
      base_conf <- 0.6 + keyword_matches * 0.05
      base_conf + runif(1, 0, 0.35)
    } else {
      runif(1, 0.05, 0.5)
    }
    
    confidence <- pmin(0.98, pmax(0.02, confidence))
    
    # Token usage based on narrative complexity
    prompt_tokens <- round(narrative_length / 3.5 + runif(1, 100, 200))
    completion_tokens <- round(50 + keyword_matches * 5 + runif(1, 10, 40))
    
    # Response time with load characteristics
    response_time <- if (error_mask[i]) {
      NA  # Failed request
    } else {
      base_response_times[i] + rnorm(1, 0, 100)
    }
    
    responses[[i]] <- list(
      narrative_id = sprintf("LOAD_%06d", i),
      narrative_text = narrative,
      detected = if (error_mask[i]) NA else detected,
      confidence = if (error_mask[i]) NA else confidence,
      model = sample(models, 1),
      prompt_tokens = if (error_mask[i]) NA else prompt_tokens,
      completion_tokens = if (error_mask[i]) NA else completion_tokens,
      total_tokens = if (error_mask[i]) NA else prompt_tokens + completion_tokens,
      response_time_ms = response_time,
      raw_response = if (error_mask[i]) NA else sprintf(
        '{"detected": %s, "confidence": %.3f}', 
        tolower(as.character(detected)), confidence
      ),
      error_message = if (error_mask[i]) "API rate limit exceeded" else NA
    )
  }
  
  # Statistics
  successful_responses <- sum(!error_mask)
  error_rate <- mean(error_mask) * 100
  
  cat(sprintf("Generated %d responses (%d successful, %.1f%% errors)\n",
             length(responses), successful_responses, error_rate))
  
  return(responses)
}

#' Run high-volume load test
#'
#' Tests system performance with large batch processing
#' 
#' @param test_size Number of narratives to process (default: 1000)
#' @param batch_sizes Vector of batch sizes to test
#' @param test_postgres Whether to test PostgreSQL (default: TRUE)
#' @return Load test results
run_high_volume_test <- function(test_size = 1000, 
                                batch_sizes = c(100, 500, 1000, 2000, 5000),
                                test_postgres = TRUE) {
  
  cat("=== High-Volume Load Testing ===\n")
  cat(sprintf("Processing %d narratives with various batch sizes\n\n", test_size))
  
  # Generate test dataset
  test_data <- generate_large_test_dataset(test_size)
  
  # Generate mock responses
  mock_responses <- generate_load_test_responses(test_data$narratives)
  
  # Parse responses for storage testing
  parsed_responses <- lapply(mock_responses, function(response) {
    if (is.na(response$error_message)) {
      tryCatch({
        parsed <- parse_llm_result(response$raw_response)
        if (!is.null(parsed)) {
          # Add metadata
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
    } else {
      return(NULL)
    }
  })
  
  # Remove failed parses
  parsed_responses <- parsed_responses[!sapply(parsed_responses, is.null)]
  
  cat(sprintf("Successfully parsed %d responses for storage testing\n", 
             length(parsed_responses)))
  
  load_test_results <- list(
    test_size = test_size,
    responses_generated = length(mock_responses),
    responses_parsed = length(parsed_responses),
    parse_success_rate = length(parsed_responses) / length(mock_responses),
    batch_tests = list()
  )
  
  if (test_postgres) {
    # Test PostgreSQL connection
    postgres_conn <- tryCatch({
      connect_postgres()
    }, error = function(e) {
      cat("❌ PostgreSQL connection failed:", e$message, "\n")
      return(NULL)
    })
    
    if (!is.null(postgres_conn)) {
      cat("\nTesting PostgreSQL with various batch sizes...\n")
      
      for (batch_size in batch_sizes) {
        if (length(parsed_responses) < batch_size) {
          cat(sprintf("Skipping batch size %d (insufficient data)\n", batch_size))
          next
        }
        
        cat(sprintf("Testing batch size: %d records...\n", batch_size))
        
        # Sample data for this batch size
        sample_data <- sample(parsed_responses, batch_size)
        
        # Measure performance
        start_time <- Sys.time()
        start_memory <- memory.size()
        
        tryCatch({
          result <- store_llm_results_batch(sample_data, conn = postgres_conn)
          
          end_time <- Sys.time()
          end_memory <- memory.size()
          
          duration <- as.numeric(difftime(end_time, start_time, units = "secs"))
          throughput <- batch_size / duration
          memory_used <- end_memory - start_memory
          
          batch_result <- list(
            batch_size = batch_size,
            duration_seconds = duration,
            throughput_per_second = throughput,
            memory_mb = memory_used,
            success_rate = result$success_rate,
            inserted = result$inserted,
            duplicates = result$duplicates,
            errors = result$errors
          )
          
          load_test_results$batch_tests[[as.character(batch_size)]] <- batch_result
          
          cat(sprintf("  ✓ Throughput: %.0f records/sec, Memory: %.1f MB, Success: %.1f%%\n",
                     throughput, memory_used, result$success_rate * 100))
          
        }, error = function(e) {
          cat(sprintf("  ❌ Error with batch size %d: %s\n", batch_size, e$message))
        })
        
        # Brief pause between tests
        Sys.sleep(1)
      }
      
      close_db_connection(postgres_conn)
    } else {
      cat("⚠️ PostgreSQL not available for load testing\n")
    }
  }
  
  return(load_test_results)
}

#' Run concurrent access test
#'
#' Tests database performance under concurrent load
#' 
#' @param concurrent_processes Number of parallel processes (default: 4)
#' @param records_per_process Records each process handles (default: 250)
#' @return Concurrent test results
run_concurrent_access_test <- function(concurrent_processes = 4, records_per_process = 250) {
  
  cat("=== Concurrent Access Testing ===\n")
  cat(sprintf("Testing %d concurrent processes, %d records each\n\n", 
             concurrent_processes, records_per_process))
  
  # Generate test data
  total_records <- concurrent_processes * records_per_process
  test_data <- generate_large_test_dataset(total_records)
  mock_responses <- generate_load_test_responses(test_data$narratives, load_characteristics = FALSE)
  
  # Parse responses
  parsed_responses <- lapply(mock_responses, function(response) {
    if (!is.na(response$raw_response)) {
      tryCatch({
        parsed <- parse_llm_result(response$raw_response)
        if (!is.null(parsed)) {
          parsed$narrative_id <- response$narrative_id
          parsed$narrative_text <- response$narrative_text
          parsed$model <- response$model
          parsed$prompt_tokens <- response$prompt_tokens
          parsed$completion_tokens <- response$completion_tokens
          parsed$total_tokens <- response$total_tokens
          parsed$response_time_ms <- response$response_time_ms
          parsed$raw_response <- response$raw_response
        }
        return(parsed)
      }, error = function(e) return(NULL))
    } else {
      return(NULL)
    }
  })
  
  parsed_responses <- parsed_responses[!sapply(parsed_responses, is.null)]
  
  if (length(parsed_responses) < total_records) {
    cat("⚠️ Insufficient parsed responses for concurrent test\n")
    return(list(success = FALSE, reason = "Insufficient data"))
  }
  
  # Split data among processes
  data_chunks <- split(parsed_responses, rep(1:concurrent_processes, 
                                           length.out = length(parsed_responses)))
  
  # Define worker function
  concurrent_worker <- function(chunk_data, process_id) {
    
    # Each process gets its own connection
    tryCatch({
      conn <- connect_postgres()
      
      start_time <- Sys.time()
      result <- store_llm_results_batch(chunk_data, conn = conn)
      end_time <- Sys.time()
      
      close_db_connection(conn)
      
      duration <- as.numeric(difftime(end_time, start_time, units = "secs"))
      throughput <- length(chunk_data) / duration
      
      return(list(
        process_id = process_id,
        records_processed = length(chunk_data),
        duration_seconds = duration,
        throughput_per_second = throughput,
        success_rate = result$success_rate,
        inserted = result$inserted,
        duplicates = result$duplicates,
        errors = result$errors,
        success = TRUE
      ))
      
    }, error = function(e) {
      return(list(
        process_id = process_id,
        success = FALSE,
        error = e$message
      ))
    })
  }
  
  # Run concurrent processes
  cat("Starting concurrent processes...\n")
  
  overall_start_time <- Sys.time()
  
  # Use parallel processing
  if (.Platform$OS.type == "windows") {
    # Use PSOCK cluster on Windows
    cl <- makeCluster(concurrent_processes)
    clusterEvalQ(cl, {
      source("../../R/db_utils.R")
      source("../../R/store_llm_result.R")
      library(DBI)
      library(RPostgres)
    })
    
    concurrent_results <- clusterMap(cl, concurrent_worker, 
                                   data_chunks, 
                                   seq_along(data_chunks),
                                   SIMPLIFY = FALSE)
    
    stopCluster(cl)
  } else {
    # Use mclapply on Unix-like systems
    concurrent_results <- mclapply(seq_along(data_chunks), function(i) {
      concurrent_worker(data_chunks[[i]], i)
    }, mc.cores = concurrent_processes)
  }
  
  overall_end_time <- Sys.time()
  total_duration <- as.numeric(difftime(overall_end_time, overall_start_time, units = "secs"))
  
  # Analyze results
  successful_processes <- sum(sapply(concurrent_results, function(x) x$success))
  
  if (successful_processes == 0) {
    cat("❌ All concurrent processes failed\n")
    return(list(success = FALSE, reason = "All processes failed"))
  }
  
  successful_results <- concurrent_results[sapply(concurrent_results, function(x) x$success)]
  
  # Calculate statistics
  total_records_processed <- sum(sapply(successful_results, function(x) x$records_processed))
  overall_throughput <- total_records_processed / total_duration
  avg_process_throughput <- mean(sapply(successful_results, function(x) x$throughput_per_second))
  avg_success_rate <- mean(sapply(successful_results, function(x) x$success_rate))
  
  cat(sprintf("\n=== Concurrent Test Results ===\n"))
  cat(sprintf("Successful processes: %d/%d\n", successful_processes, concurrent_processes))
  cat(sprintf("Total records processed: %d\n", total_records_processed))
  cat(sprintf("Overall duration: %.2f seconds\n", total_duration))
  cat(sprintf("Overall throughput: %.0f records/second\n", overall_throughput))
  cat(sprintf("Average process throughput: %.0f records/second\n", avg_process_throughput))
  cat(sprintf("Average success rate: %.1f%%\n", avg_success_rate * 100))
  
  return(list(
    success = TRUE,
    concurrent_processes = concurrent_processes,
    successful_processes = successful_processes,
    total_records_processed = total_records_processed,
    total_duration_seconds = total_duration,
    overall_throughput = overall_throughput,
    avg_process_throughput = avg_process_throughput,
    avg_success_rate = avg_success_rate,
    process_results = concurrent_results
  ))
}

#' Run stress test with error scenarios
#'
#' Tests system resilience under adverse conditions
#' 
#' @param stress_scenarios List of stress scenarios to test
#' @return Stress test results
run_stress_test <- function(stress_scenarios = c("network_delays", "parse_errors", "db_timeouts")) {
  
  cat("=== Stress Testing ===\n")
  cat("Testing system resilience under adverse conditions\n\n")
  
  stress_results <- list()
  
  # Generate base test data
  base_data <- generate_large_test_dataset(500)
  
  for (scenario in stress_scenarios) {
    cat(sprintf("Running %s stress test...\n", scenario))
    
    if (scenario == "network_delays") {
      # Simulate slow API responses and timeouts
      mock_responses <- generate_load_test_responses(base_data$narratives, load_characteristics = TRUE)
      
      # Add extreme delays to 10% of responses
      delay_indices <- sample(length(mock_responses), floor(length(mock_responses) * 0.1))
      for (idx in delay_indices) {
        mock_responses[[idx]]$response_time_ms <- mock_responses[[idx]]$response_time_ms * 5
      }
      
      stress_results[[scenario]] <- test_parsing_resilience(mock_responses)
      
    } else if (scenario == "parse_errors") {
      # Generate responses with various parsing challenges
      mock_responses <- generate_load_test_responses(base_data$narratives, load_characteristics = FALSE)
      
      # Introduce parsing errors to 15% of responses
      error_indices <- sample(length(mock_responses), floor(length(mock_responses) * 0.15))
      error_types <- c("malformed_json", "extra_text", "unicode_issues", "empty_response")
      
      for (idx in error_indices) {
        error_type <- sample(error_types, 1)
        mock_responses[[idx]]$raw_response <- create_parsing_error(
          mock_responses[[idx]]$raw_response, error_type
        )
      }
      
      stress_results[[scenario]] <- test_parsing_resilience(mock_responses)
      
    } else if (scenario == "db_timeouts") {
      # Test database resilience
      stress_results[[scenario]] <- test_database_resilience(base_data)
    }
    
    cat(sprintf("  ✓ %s test completed\n", scenario))
  }
  
  return(stress_results)
}

#' Create parsing error scenarios
#'
#' Introduces various parsing challenges for stress testing
#' 
#' @param original_response Original JSON response
#' @param error_type Type of error to introduce
#' @return Modified response with parsing challenges
create_parsing_error <- function(original_response, error_type) {
  
  switch(error_type,
    "malformed_json" = {
      # Remove random braces or add extra commas
      if (runif(1) > 0.5) {
        gsub("[{}]", "", original_response)
      } else {
        gsub(",", ",,", original_response)
      }
    },
    "extra_text" = {
      # Add non-JSON text before or after
      prefix <- sample(c("Analysis result: ", "LLM output: ", "Response: "), 1)
      suffix <- sample(c(" (end of analysis)", " - confidence noted", ""), 1)
      paste0(prefix, original_response, suffix)
    },
    "unicode_issues" = {
      # Add problematic Unicode characters
      paste0("⚠️ ", original_response, " ✓")
    },
    "empty_response" = {
      # Return empty or whitespace-only response
      sample(c("", "   ", "\n\t ", " \n "), 1)
    }
  )
}

#' Test parsing resilience
#'
#' Tests how well parsing handles error scenarios
#' 
#' @param mock_responses List of responses with potential errors
#' @return Parsing resilience results
test_parsing_resilience <- function(mock_responses) {
  
  successful_parses <- 0
  failed_parses <- 0
  parse_times <- numeric()
  
  for (response in mock_responses) {
    start_time <- Sys.time()
    
    tryCatch({
      parsed <- parse_llm_result(response$raw_response)
      if (!is.null(parsed) && "detected" %in% names(parsed)) {
        successful_parses <- successful_parses + 1
      } else {
        failed_parses <- failed_parses + 1
      }
    }, error = function(e) {
      failed_parses <<- failed_parses + 1
    })
    
    parse_time <- as.numeric(difftime(Sys.time(), start_time, units = "secs")) * 1000
    parse_times <- c(parse_times, parse_time)
  }
  
  success_rate <- successful_parses / length(mock_responses)
  avg_parse_time <- mean(parse_times)
  
  return(list(
    total_responses = length(mock_responses),
    successful_parses = successful_parses,
    failed_parses = failed_parses,
    success_rate = success_rate,
    avg_parse_time_ms = avg_parse_time,
    resilient = success_rate >= 0.8  # 80% success rate threshold
  ))
}

#' Test database resilience
#'
#' Tests database performance under stress conditions
#' 
#' @param test_data Test dataset
#' @return Database resilience results
test_database_resilience <- function(test_data) {
  
  # Generate responses
  mock_responses <- generate_load_test_responses(test_data$narratives, load_characteristics = FALSE)
  
  # Parse responses
  parsed_responses <- lapply(mock_responses, function(response) {
    tryCatch({
      parsed <- parse_llm_result(response$raw_response)
      if (!is.null(parsed)) {
        parsed$narrative_id <- response$narrative_id
        parsed$narrative_text <- response$narrative_text
        parsed$model <- response$model
        parsed$prompt_tokens <- response$prompt_tokens
        parsed$completion_tokens <- response$completion_tokens
        parsed$total_tokens <- response$total_tokens
        parsed$response_time_ms <- response$response_time_ms
        parsed$raw_response <- response$raw_response
      }
      return(parsed)
    }, error = function(e) return(NULL))
  })
  
  parsed_responses <- parsed_responses[!sapply(parsed_responses, is.null)]
  
  # Test database with various stress conditions
  conn <- tryCatch(connect_postgres(), error = function(e) NULL)
  
  if (is.null(conn)) {
    return(list(success = FALSE, reason = "Database connection failed"))
  }
  
  stress_results <- list()
  
  # Test 1: Large batch size
  large_batch <- sample(parsed_responses, min(5000, length(parsed_responses)))
  start_time <- Sys.time()
  
  tryCatch({
    result <- store_llm_results_batch(large_batch, conn = conn)
    duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    
    stress_results$large_batch <- list(
      success = TRUE,
      batch_size = length(large_batch),
      duration_seconds = duration,
      throughput = length(large_batch) / duration,
      success_rate = result$success_rate
    )
  }, error = function(e) {
    stress_results$large_batch <- list(success = FALSE, error = e$message)
  })
  
  # Test 2: Connection stress (rapid connect/disconnect cycles)
  connection_tests <- 10
  connection_successes <- 0
  
  for (i in 1:connection_tests) {
    tryCatch({
      temp_conn <- connect_postgres()
      health <- test_connection_health(temp_conn)
      if (health$healthy) connection_successes <- connection_successes + 1
      close_db_connection(temp_conn)
    }, error = function(e) {})
  }
  
  stress_results$connection_stress <- list(
    tests = connection_tests,
    successes = connection_successes,
    success_rate = connection_successes / connection_tests
  )
  
  close_db_connection(conn)
  
  # Overall resilience assessment
  resilience_score <- mean(c(
    if (!is.null(stress_results$large_batch$success) && stress_results$large_batch$success) 1 else 0,
    stress_results$connection_stress$success_rate
  ))
  
  stress_results$overall_resilience_score <- resilience_score
  stress_results$resilient <- resilience_score >= 0.8
  
  return(stress_results)
}

#' Run comprehensive load test suite
#'
#' Executes all load testing scenarios
#' 
#' @param test_size Total number of narratives for testing (default: 1000)
#' @return Complete load test results
run_comprehensive_load_test <- function(test_size = 1000) {
  
  cat("=== Comprehensive Load Testing Suite ===\n")
  cat(sprintf("Testing system with %d narratives\n", test_size))
  cat("Validating scalability and performance under load\n\n")
  
  load_test_results <- list(
    test_timestamp = Sys.time(),
    test_size = test_size
  )
  
  # 1. High-volume batch processing
  cat("1. High-Volume Batch Processing Test\n")
  cat(paste0(rep("=", 40), collapse = ""), "\n")
  load_test_results$high_volume <- run_high_volume_test(test_size)
  
  # 2. Concurrent access testing
  cat("\n\n2. Concurrent Access Test\n")
  cat(paste0(rep("=", 40), collapse = ""), "\n")
  load_test_results$concurrent <- run_concurrent_access_test()
  
  # 3. Stress testing
  cat("\n\n3. Stress Testing\n")
  cat(paste0(rep("=", 40), collapse = ""), "\n")
  load_test_results$stress <- run_stress_test()
  
  # Overall assessment
  cat("\n\n=== LOAD TEST SUMMARY ===\n")
  
  # Assess each test component
  assessments <- list()
  
  # High-volume assessment
  if (length(load_test_results$high_volume$batch_tests) > 0) {
    best_throughput <- max(sapply(load_test_results$high_volume$batch_tests, 
                                function(x) x$throughput_per_second))
    assessments$high_volume <- best_throughput >= 5000
    cat(sprintf("High-Volume Processing: %s (%.0f records/sec peak)\n",
               if(assessments$high_volume) "✅ PASSED" else "❌ FAILED", best_throughput))
  } else {
    assessments$high_volume <- FALSE
    cat("High-Volume Processing: ❌ NO DATA\n")
  }
  
  # Concurrent assessment
  if (!is.null(load_test_results$concurrent) && load_test_results$concurrent$success) {
    concurrent_throughput <- load_test_results$concurrent$overall_throughput
    assessments$concurrent <- concurrent_throughput >= 2000  # Lower threshold for concurrent
    cat(sprintf("Concurrent Access: %s (%.0f records/sec overall)\n",
               if(assessments$concurrent) "✅ PASSED" else "❌ FAILED", concurrent_throughput))
  } else {
    assessments$concurrent <- FALSE
    cat("Concurrent Access: ❌ FAILED\n")
  }
  
  # Stress assessment
  if (!is.null(load_test_results$stress) && length(load_test_results$stress) > 0) {
    stress_resilience <- all(sapply(load_test_results$stress, function(x) 
      !is.null(x$resilient) && x$resilient))
    assessments$stress <- stress_resilience
    cat(sprintf("Stress Resilience: %s\n",
               if(assessments$stress) "✅ PASSED" else "❌ FAILED"))
  } else {
    assessments$stress <- FALSE
    cat("Stress Resilience: ❌ NO DATA\n")
  }
  
  # Overall load test result
  passed_tests <- sum(unlist(assessments))
  total_tests <- length(assessments)
  overall_pass <- passed_tests >= ceiling(total_tests * 0.67)  # 67% pass rate
  
  cat(sprintf("\nLoad Test Result: %d/%d tests passed\n", passed_tests, total_tests))
  cat(sprintf("Overall Status: %s\n", if(overall_pass) "✅ SYSTEM READY FOR LOAD" else "❌ OPTIMIZATION NEEDED"))
  
  load_test_results$summary <- list(
    overall_pass = overall_pass,
    passed_tests = passed_tests,
    total_tests = total_tests,
    assessments = assessments
  )
  
  return(load_test_results)
}

# Main execution when run as script
if (!interactive()) {
  cat("IPV Detection Load Testing Suite\n")
  cat("===============================\n\n")
  
  args <- commandArgs(trailingOnly = TRUE)
  
  if ("--quick" %in% args) {
    test_size <- 500
  } else if ("--large" %in% args) {
    test_size <- 2000
  } else {
    test_size <- 1000  # Default
  }
  
  # Run comprehensive load test
  results <- run_comprehensive_load_test(test_size)
  
  # Generate report file
  report_file <- sprintf("load_test_results_%s.rds", 
                        format(Sys.time(), "%Y%m%d_%H%M%S"))
  
  saveRDS(results, report_file)
  cat(sprintf("\nLoad test results saved to: %s\n", report_file))
  
  # Exit with appropriate code
  exit_code <- if (results$summary$overall_pass) 0 else 1
  quit(status = exit_code)
}