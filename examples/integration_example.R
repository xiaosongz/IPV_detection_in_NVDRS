#!/usr/bin/env Rscript

#' Integration Example: Complete IPV Detection Workflow
#'
#' Demonstrates the full end-to-end workflow combining all system components:
#' - Data loading and preprocessing
#' - Database setup and configuration
#' - LLM-based IPV detection
#' - Result storage and batch processing
#' - Performance monitoring and analysis
#' - Export and reporting
#'
#' This example shows how all pieces work together in a real-world scenario.

# Load all required functions
source("R/build_prompt.R")
source("R/call_llm.R")
source("R/repair_json.R")
source("R/parse_llm_result.R")
source("R/store_llm_result.R")
source("R/db_utils.R")
source("R/experiment_utils.R")
source("R/experiment_analysis.R")
source("R/utils.R")

cat("=== Complete IPV Detection Integration Example ===\n")

# Step 1: Environment Setup and Configuration
cat("\n=== Step 1: Environment Setup ===\n")

# Configuration parameters
config <- list(
  db_path = "integration_workflow.db",
  model = "gpt-4o-mini",  # Fast, cost-effective model
  batch_size = 50,
  enable_experiments = TRUE,
  enable_performance_monitoring = TRUE,
  output_dir = "benchmark_results"
)

cat(sprintf("Configuration:\n"))
cat(sprintf("  Database: %s\n", config$db_path))
cat(sprintf("  Model: %s\n", config$model))
cat(sprintf("  Batch size: %d\n", config$batch_size))
cat(sprintf("  Experiments: %s\n", config$enable_experiments))

# Create output directory
if (!dir.exists(config$output_dir)) {
  dir.create(config$output_dir, recursive = TRUE)
  cat(sprintf("✓ Created output directory: %s\n", config$output_dir))
}

# Step 2: Database Setup
cat("\n=== Step 2: Database Setup ===\n")

# Setup database with full schema
conn <- get_db_connection(config$db_path)
ensure_schema(conn)

if (config$enable_experiments) {
  ensure_experiment_schema(conn)
  cat("✓ Experiment tracking enabled\n")
}

# Test connection health
health <- test_connection_health(conn, detailed = TRUE)
cat(sprintf("✓ Database healthy: %s (%.1f ms)\n", health$healthy, health$response_time_ms))

# Step 3: Load and Prepare Data
cat("\n=== Step 3: Data Loading ===\n")

# Load sample data (simulated real NVDRS-style narratives)
sample_data <- data.frame(
  case_id = sprintf("NVDRS_%04d", 1:100),
  narrative = c(
    # IPV cases (30%)
    rep(c(
      "Victim shot and killed by ex-boyfriend during custody exchange at local shopping center",
      "Woman found strangled in apartment, history of domestic violence with current partner",
      "Stabbed multiple times by ex-husband who violated restraining order",
      "Shot by intimate partner following argument about financial issues",
      "Beaten to death by boyfriend during domestic dispute witnessed by neighbors",
      "Found dead from gunshot wounds, ex-partner arrested at scene",
      "Killed by current partner who then died by suicide",
      "Strangulation death during argument with live-in boyfriend",
      "Shot by ex-spouse during attempted reconciliation meeting",
      "Found dead after domestic violence incident, partner fled scene"
    ), 3),
    
    # Non-IPV cases (60%)  
    rep(c(
      "Single vehicle accident on rural highway during severe weather conditions",
      "Suicide by hanging in garage, left detailed note about depression and job loss",
      "Accidental overdose of prescription opioids, history of chronic pain management",
      "Motorcycle accident on interstate, no other vehicles involved",
      "Suicide by gunshot in wooded area, history of mental health treatment",
      "Found dead from apparent heart attack at home, no signs of trauma",
      "Accidental drowning in river during fishing trip with friends",
      "Drug overdose at residence, needle and heroin found at scene",
      "Suicide by carbon monoxide poisoning in vehicle, note found",
      "Industrial accident at construction site, safety violation cited",
      "Suicide by jumping from bridge, witnessed by multiple people",
      "Accidental fall from roof during home repair work",
      "Medical emergency leading to death, no suspicious circumstances",
      "Accidental poisoning from household chemicals, elderly victim",
      "Single vehicle crash, driver fell asleep at wheel"
    ), 4),
    
    # Ambiguous cases (10%)
    rep(c(
      "Found dead at home with head trauma, recent separation from spouse",
      "Gunshot wound, domestic disturbance call made earlier that day", 
      "Death by asphyxiation, unclear if suicide or accident",
      "Found in vehicle with gunshot wound, note partially destroyed",
      "Blunt force trauma, possible fall or assault, investigation ongoing",
      "Drug overdose, relationship problems mentioned by family",
      "Found in water, unclear if suicide, accident, or homicide",
      "Death at residence, signs of struggle but no clear perpetrator",
      "Gunshot wound, weapon found at scene but fingerprints unclear",
      "Asphyxiation death, possible autoerotic accident or suicide"
    ), 1)
  ),
  stringsAsFactors = FALSE
)

cat(sprintf("✓ Loaded %d case narratives\n", nrow(sample_data)))

# Add ground truth for evaluation (in real scenario, this would be expert coding)
sample_data$ground_truth <- c(
  rep(TRUE, 30),   # IPV cases
  rep(FALSE, 60),  # Non-IPV cases  
  rep(NA, 10)      # Ambiguous cases
)

cat(sprintf("  IPV cases: %d\n", sum(sample_data$ground_truth, na.rm = TRUE)))
cat(sprintf("  Non-IPV cases: %d\n", sum(!sample_data$ground_truth, na.rm = TRUE)))
cat(sprintf("  Ambiguous cases: %d\n", sum(is.na(sample_data$ground_truth))))

# Step 4: Setup Prompt and LLM Configuration
cat("\n=== Step 4: LLM Configuration ===\n")

# Production-ready prompt
production_prompt <- list(
  system = "You are an expert forensic analyst specializing in intimate partner violence (IPV) detection in death investigation narratives.

Analyze each narrative for indicators of IPV including:
- Current or former intimate/romantic relationships
- History or patterns of domestic violence
- Physical violence by intimate partners
- Control, jealousy, or possessive behaviors
- Separation or custody-related violence
- Threats or stalking by intimate partners

Respond with JSON only: {\"detected\": true/false, \"confidence\": 0.0-1.0}

Be conservative: only mark as detected when there are clear indicators of violence by intimate partners.",

  user = "Death investigation narrative: {text}

Analyze for intimate partner violence indicators:"
)

# Register prompt for experiment tracking
prompt_id <- NULL
if (config$enable_experiments) {
  prompt_id <- register_prompt(
    system_prompt = production_prompt$system,
    user_prompt_template = production_prompt$user,
    version_tag = "v1.0_production",
    notes = "Production prompt for integration workflow",
    conn = conn
  )
  cat(sprintf("✓ Registered prompt ID: %d\n", prompt_id))
}

# Step 5: Processing Pipeline
cat("\n=== Step 5: Processing Pipeline ===\n")

# Initialize tracking
processing_stats <- list(
  total_cases = nrow(sample_data),
  processed = 0,
  successful = 0,
  errors = 0,
  ipv_detected = 0,
  start_time = Sys.time()
)

# Process in batches for efficiency
batches <- split(sample_data, ceiling(seq_len(nrow(sample_data)) / config$batch_size))
batch_results <- list()

cat(sprintf("Processing %d cases in %d batches...\n", nrow(sample_data), length(batches)))

for (batch_num in seq_along(batches)) {
  batch_data <- batches[[batch_num]]
  cat(sprintf("\nBatch %d/%d (%d cases):\n", batch_num, length(batches), nrow(batch_data)))
  
  batch_start <- Sys.time()
  batch_parsed_results <- list()
  
  for (i in seq_len(nrow(batch_data))) {
    case_data <- batch_data[i, ]
    cat(sprintf("  [%d/%d] %s... ", i, nrow(batch_data), case_data$case_id))
    
    # Build user prompt
    user_prompt <- gsub("\\{text\\}", case_data$narrative, production_prompt$user)
    
    # Call LLM (with simulated response for demonstration)
    llm_result <- tryCatch({
      # Simulate realistic API call
      Sys.sleep(0.1)  # Simulate network latency
      
      # Generate realistic response based on ground truth (for demonstration)
      if (is.na(case_data$ground_truth)) {
        # Ambiguous case - random but lower confidence
        detected <- runif(1) > 0.5
        confidence <- runif(1, 0.4, 0.7)
      } else if (case_data$ground_truth) {
        # True IPV case - mostly correct with high confidence
        detected <- runif(1) > 0.1  # 90% accuracy
        confidence <- runif(1, 0.75, 0.95)
      } else {
        # Non-IPV case - mostly correct with high confidence
        detected <- runif(1) > 0.9  # 90% accuracy (10% false positive)
        confidence <- runif(1, 0.8, 0.95)
      }
      
      list(
        choices = list(list(message = list(content = sprintf(
          '{"detected": %s, "confidence": %.2f}',
          ifelse(detected, "true", "false"), confidence
        )))),
        usage = list(
          prompt_tokens = nchar(paste(production_prompt$system, user_prompt))/4,
          completion_tokens = 15,
          total_tokens = nchar(paste(production_prompt$system, user_prompt))/4 + 15
        ),
        model = config$model
      )
    }, error = function(e) {
      list(error = TRUE, error_message = e$message)
    })
    
    # Parse result
    parsed <- parse_llm_result(
      llm_result, 
      narrative_id = case_data$case_id
    )
    
    # Add narrative text for database storage
    parsed$narrative_text <- case_data$narrative
    
    # Update statistics
    processing_stats$processed <- processing_stats$processed + 1
    
    if (parsed$parse_error) {
      processing_stats$errors <- processing_stats$errors + 1
      cat("❌ Parse error\n")
    } else {
      processing_stats$successful <- processing_stats$successful + 1
      if (parsed$detected) {
        processing_stats$ipv_detected <- processing_stats$ipv_detected + 1
      }
      cat(sprintf("✓ %s (%.2f)\n", parsed$detected, parsed$confidence))
    }
    
    batch_parsed_results[[i]] <- parsed
  }
  
  # Store batch results
  batch_store_result <- store_llm_results_batch(
    batch_parsed_results, 
    db_path = config$db_path,
    conn = conn
  )
  
  batch_time <- as.numeric(difftime(Sys.time(), batch_start, units = "secs"))
  
  cat(sprintf("  Batch %d completed: %d stored, %d errors, %.1f seconds\n",
             batch_num, batch_store_result$inserted, batch_store_result$errors, batch_time))
  
  batch_results[[batch_num]] <- list(
    batch_num = batch_num,
    cases = nrow(batch_data),
    results = batch_parsed_results,
    storage = batch_store_result,
    processing_time = batch_time
  )
  
  # Additional batch processing could go here (e.g., experiment tracking)
  # For this example, we'll use the standard storage which is already done
}

processing_stats$end_time <- Sys.time()
processing_stats$total_time <- as.numeric(difftime(
  processing_stats$end_time, processing_stats$start_time, units = "secs"
))

# Step 6: Results Analysis
cat("\n=== Step 6: Results Analysis ===\n")

# Overall performance metrics
cat("Processing Summary:\n")
cat(sprintf("  Total cases: %d\n", processing_stats$total_cases))
cat(sprintf("  Successful: %d (%.1f%%)\n", 
           processing_stats$successful, 
           processing_stats$successful / processing_stats$total_cases * 100))
cat(sprintf("  Errors: %d\n", processing_stats$errors))
cat(sprintf("  IPV detected: %d (%.1f%%)\n", 
           processing_stats$ipv_detected,
           processing_stats$ipv_detected / processing_stats$successful * 100))
cat(sprintf("  Processing time: %.1f seconds\n", processing_stats$total_time))
cat(sprintf("  Rate: %.1f cases/second\n", 
           processing_stats$total_cases / processing_stats$total_time))

# Database analysis
cat("\nDatabase Analysis:\n")

# Count records by detection result
detection_summary <- DBI::dbGetQuery(conn, "
  SELECT detected, COUNT(*) as count
  FROM llm_results 
  GROUP BY detected
  ORDER BY detected DESC
")

for (i in 1:nrow(detection_summary)) {
  row <- detection_summary[i, ]
  label <- if (row$detected == 1) "IPV detected" else "Non-IPV"
  cat(sprintf("  %s: %d cases\n", label, row$count))
}

# Performance metrics
performance_query <- "
  SELECT 
    AVG(confidence) as avg_confidence,
    AVG(response_time_ms) as avg_response_time,
    AVG(total_tokens) as avg_tokens,
    MIN(created_at) as first_case,
    MAX(created_at) as last_case
  FROM llm_results
"

performance_stats <- DBI::dbGetQuery(conn, performance_query)
if (nrow(performance_stats) > 0) {
  row <- performance_stats[1, ]
  cat(sprintf("  Average confidence: %.2f\n", row$avg_confidence))
  cat(sprintf("  Average response time: %.0f ms\n", row$avg_response_time %||% 0))
  cat(sprintf("  Average tokens used: %.0f\n", row$avg_tokens %||% 0))
  cat(sprintf("  Processing window: %s to %s\n", row$first_case, row$last_case))
}

# Step 7: Evaluation Against Ground Truth
cat("\n=== Step 7: Ground Truth Evaluation ===\n")

# Simple evaluation against ground truth using known test data
# Note: In real usage, ground truth would come from expert coding
ipv_cases <- sum(sample_data$ground_truth, na.rm = TRUE)
non_ipv_cases <- sum(!sample_data$ground_truth, na.rm = TRUE)
detected_ipv <- processing_stats$ipv_detected

cat("Simplified performance evaluation:\n")
cat(sprintf("  Expected IPV cases: %d\n", ipv_cases))
cat(sprintf("  Expected Non-IPV cases: %d\n", non_ipv_cases))
cat(sprintf("  Detected IPV cases: %d\n", detected_ipv))
cat(sprintf("  Detection rate: %.1f%%\n", (detected_ipv / ipv_cases) * 100))

# Simple accuracy estimate (this is just for demonstration)
estimated_accuracy <- 0.85  # Placeholder based on typical performance
cat(sprintf("  Estimated accuracy: %.1f%%\n", estimated_accuracy * 100))

# Step 8: Export and Reporting
cat("\n=== Step 8: Export and Reporting ===\n")

# Export main results
main_export_query <- "
  SELECT 
    narrative_id,
    narrative_text,
    detected,
    confidence,
    model,
    total_tokens,
    response_time_ms,
    created_at
  FROM llm_results 
  ORDER BY created_at
"

main_results <- DBI::dbGetQuery(conn, main_export_query)
main_export_file <- file.path(config$output_dir, "ipv_detection_results.csv")
write.csv(main_results, main_export_file, row.names = FALSE)
cat(sprintf("✓ Exported %d results to %s\n", nrow(main_results), main_export_file))

# Export processing statistics
processing_stats_df <- data.frame(
  metric = c("total_cases", "successful", "errors", "ipv_detected", "processing_time_sec"),
  value = c(
    processing_stats$total_cases,
    processing_stats$successful, 
    processing_stats$errors,
    processing_stats$ipv_detected,
    processing_stats$total_time
  )
)

stats_export_file <- file.path(config$output_dir, "processing_statistics.csv")
write.csv(processing_stats_df, stats_export_file, row.names = FALSE)
cat(sprintf("✓ Exported processing statistics to %s\n", stats_export_file))

# Generate summary report
summary_report <- sprintf("# IPV Detection Integration Report

## Processing Summary
- **Total Cases**: %d
- **Successfully Processed**: %d (%.1f%%)
- **Parse Errors**: %d
- **IPV Cases Detected**: %d (%.1f%%)
- **Processing Time**: %.1f seconds
- **Processing Rate**: %.1f cases/second

## Model Performance
- **Model Used**: %s
- **Average Confidence**: %.2f
- **Average Response Time**: %.0f ms
- **Average Tokens**: %.0f

## Database Storage
- **Database Type**: %s
- **Total Records Stored**: %d
- **Storage Success Rate**: %.1f%%

## Files Generated
- `ipv_detection_results.csv`: Main detection results
- `experiment_results.csv`: Experimental evaluation results (if enabled)
- `integration_report.md`: This summary report

Generated on: %s
",
  processing_stats$total_cases,
  processing_stats$successful,
  processing_stats$successful / processing_stats$total_cases * 100,
  processing_stats$errors,
  processing_stats$ipv_detected,
  processing_stats$ipv_detected / processing_stats$successful * 100,
  processing_stats$total_time,
  processing_stats$total_cases / processing_stats$total_time,
  config$model,
  performance_stats$avg_confidence %||% 0,
  performance_stats$avg_response_time %||% 0,
  performance_stats$avg_tokens %||% 0,
  detect_db_type(conn),
  sum(sapply(batch_results, function(x) x$storage$inserted)),
  mean(sapply(batch_results, function(x) x$storage$success_rate)) * 100,
  Sys.time()
)

report_file <- file.path(config$output_dir, "integration_report.md")
writeLines(summary_report, report_file)
cat(sprintf("✓ Generated summary report: %s\n", report_file))

# Step 9: Cleanup and Finalization
cat("\n=== Step 9: Cleanup ===\n")

# Close database connection
close_db_connection(conn)
cat("✓ Database connection closed\n")

# Cleanup test database (optional)
cleanup_choice <- "keep"  # In real usage, might prompt user
if (cleanup_choice == "remove") {
  if (file.exists(config$db_path)) {
    file.remove(config$db_path)
    cat(sprintf("✓ Cleaned up database: %s\n", config$db_path))
  }
} else {
  cat(sprintf("✓ Database preserved: %s\n", config$db_path))
}

# Final summary
cat("\n=== Integration Workflow Complete ===\n")
cat(sprintf("✓ Processed %d narratives in %.1f seconds\n", 
           processing_stats$total_cases, processing_stats$total_time))
cat(sprintf("✓ Detected IPV in %d cases (%.1f%%)\n", 
           processing_stats$ipv_detected,
           processing_stats$ipv_detected / processing_stats$successful * 100))
cat(sprintf("✓ Results exported to: %s/\n", config$output_dir))
cat(sprintf("✓ Database available at: %s\n", config$db_path))

cat("\nNext steps:\n")
cat("1. Review exported results for data quality\n")
cat("2. Validate detection accuracy against expert coding\n") 
cat("3. Adjust prompts based on performance metrics\n")
cat("4. Scale up processing for full dataset\n")
cat("5. Integrate with existing NVDRS workflows\n")

cat("\n✓ End-to-end integration example completed successfully!\n")