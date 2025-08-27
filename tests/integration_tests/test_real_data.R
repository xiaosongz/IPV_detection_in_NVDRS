#!/usr/bin/env Rscript

# Test script for nvdrsipvdetector package with real data
# This script tests the refactored package with actual NVDRS data

library(cli)
library(dplyr)
library(readr)
library(tibble)

cli::cli_h1("Testing nvdrsipvdetector Package with Real Data")

# Load the package
cli::cli_alert_info("Loading nvdrsipvdetector package...")
tryCatch({
  devtools::load_all("nvdrsipvdetector")
  cli::cli_alert_success("Package loaded successfully")
}, error = function(e) {
  cli::cli_alert_danger("Failed to load package: {e$message}")
  stop(e)
})

# Set up test configuration
cli::cli_h2("Configuration Setup")

# Create a minimal test configuration
test_config <- list(
  api = list(
    base_url = Sys.getenv("LM_STUDIO_URL", "http://192.168.10.22:1234/v1"),
    model = Sys.getenv("LLM_MODEL", "openai/gpt-oss-120b"),
    timeout = 30,
    max_retries = 3
  ),
  processing = list(
    batch_size = 10,  # Small batch for testing
    checkpoint_every = 20
  ),
  weights = list(
    cme = 0.6,
    le = 0.4,
    threshold = 0.7
  ),
  database = list(
    path = "test_api_logs.sqlite"
  ),
  prompts = list(
    system = "You are an AI assistant trained to detect intimate partner violence (IPV) in death investigation narratives. Provide your response as a JSON object with the following fields: ipv_detected (boolean), confidence (number 0-1), indicators (array of strings), and rationale (string).",
    unified_template = "Based on the following {narrative_type} narrative, determine if there are indicators of intimate partner violence (IPV). Analyze for patterns of domestic violence, controlling behavior, threats, or history of abuse. Respond with JSON format only. Narrative: {narrative}"
  )
)

# Save test configuration
config_path <- "test_config.yml"
cli::cli_alert_info("Writing test configuration to {config_path}")
yaml::write_yaml(test_config, config_path)

# Read the real data
cli::cli_h2("Loading Test Data")
data_path <- "nvdrsipvdetector/inst/extdata/sui_all_flagged.xlsx"

if (!file.exists(data_path)) {
  cli::cli_alert_danger("Data file not found: {data_path}")
  stop("Test data file not found")
}

cli::cli_alert_info("Reading Excel file: {data_path}")

# Load Excel data
tryCatch({
  # Try to load with readxl if available
  if (requireNamespace("readxl", quietly = TRUE)) {
    test_data <- readxl::read_excel(data_path)
    cli::cli_alert_success("Loaded {nrow(test_data)} records from Excel file")
  } else {
    cli::cli_alert_warning("readxl package not available, trying openxlsx...")
    if (requireNamespace("openxlsx", quietly = TRUE)) {
      test_data <- openxlsx::read.xlsx(data_path)
      cli::cli_alert_success("Loaded {nrow(test_data)} records from Excel file")
    } else {
      stop("Neither readxl nor openxlsx package is available to read Excel files")
    }
  }
}, error = function(e) {
  cli::cli_alert_danger("Failed to read Excel file: {e$message}")
  stop(e)
})

# Display data summary
cli::cli_h2("Data Summary")
cli::cli_text("Total records: {nrow(test_data)}")
cli::cli_text("Columns: {paste(names(test_data), collapse = ', ')}")

# Check for required columns
required_cols <- c("IncidentID", "NarrativeLE", "NarrativeCME")
missing_cols <- setdiff(required_cols, names(test_data))

if (length(missing_cols) > 0) {
  cli::cli_alert_warning("Missing columns: {paste(missing_cols, collapse = ', ')}")
  
  # Try to identify similar column names
  cli::cli_alert_info("Available columns that might match:")
  for (col in names(test_data)) {
    cli::cli_text("  - {col}")
  }
  
  # Attempt to map columns
  if (!"IncidentID" %in% names(test_data) && "incident_id" %in% tolower(names(test_data))) {
    col_idx <- which(tolower(names(test_data)) == "incident_id")
    names(test_data)[col_idx] <- "IncidentID"
    cli::cli_alert_info("Mapped column to IncidentID")
  }
}

# Check for manual IPV flags if present
manual_flag_cols <- grep("ManualIPV|manual.*ipv|ipv.*flag", names(test_data), 
                         ignore.case = TRUE, value = TRUE)
if (length(manual_flag_cols) > 0) {
  cli::cli_alert_info("Found manual IPV flag column(s): {paste(manual_flag_cols, collapse = ', ')}")
  validation_available <- TRUE
} else {
  cli::cli_alert_info("No manual IPV flag columns found - validation will not be performed")
  validation_available <- FALSE
}

# Take a sample for testing (first 20 records or all if less)
sample_size <- min(20, nrow(test_data))
cli::cli_alert_info("Using first {sample_size} records for testing")
test_sample <- test_data[1:sample_size, ]

# Save sample as CSV for the package to read
sample_csv_path <- "test_sample.csv"
readr::write_csv(test_sample, sample_csv_path)
cli::cli_alert_success("Test sample saved to {sample_csv_path}")

# Run the detection with actual API calls
cli::cli_h2("Running IPV Detection with Real API")

# Ensure API configuration is properly set
if (is.null(test_config$api$base_url) || test_config$api$base_url == "") {
  cli::cli_alert_warning("API base URL not configured, using environment variable or default")
  test_config$api$base_url <- Sys.getenv("LM_STUDIO_URL", "http://192.168.10.22:1234/v1")
}

cli::cli_alert_info("Using API endpoint: {test_config$api$base_url}")
cli::cli_alert_info("Using model: {test_config$api$model}")

# Test API connection first
cli::cli_alert_info("Testing API connection...")
test_prompt <- build_prompt("Test connection", type = "LE", config = test_config)
test_response <- tryCatch({
  send_to_llm(test_prompt, test_config)
}, error = function(e) {
  cli::cli_alert_danger("Failed to connect to API: {e$message}")
  cli::cli_alert_info("Please ensure the LLM API is running at {test_config$api$base_url}")
  stop("API connection failed")
})

if (!is.null(test_response$success) && test_response$success) {
  cli::cli_alert_success("API connection successful!")
} else {
  cli::cli_alert_warning("API connection returned unexpected response")
}

# Run detection on sample
cli::cli_alert_info("Processing narratives with real API...")

results <- tibble::tibble()
errors <- character()

pb <- cli::cli_progress_bar("Processing records", total = sample_size)

for (i in 1:sample_size) {
  cli::cli_progress_update(id = pb)
  
  row <- test_sample[i, ]
  
  # Skip if both narratives are missing
  if (is.na(row$NarrativeLE) && is.na(row$NarrativeCME)) {
    cli::cli_alert_warning("Skipping IncidentID {row$IncidentID}: No narratives available")
    next
  }
  
  # Process LE narrative
  le_result <- NULL
  if (!is.na(row$NarrativeLE) && nchar(trimws(row$NarrativeLE)) > 0) {
    cli::cli_alert_info("Processing LE narrative for IncidentID {row$IncidentID}")
    tryCatch({
      le_prompt <- build_prompt(row$NarrativeLE, type = "LE", config = test_config)
      le_result <- send_to_llm(le_prompt, test_config)
    }, error = function(e) {
      cli::cli_alert_warning("Failed to process LE narrative for {row$IncidentID}: {e$message}")
      errors <- c(errors, paste("LE", row$IncidentID, e$message))
    })
  }
  
  # Process CME narrative  
  cme_result <- NULL
  if (!is.na(row$NarrativeCME) && nchar(trimws(row$NarrativeCME)) > 0) {
    cli::cli_alert_info("Processing CME narrative for IncidentID {row$IncidentID}")
    tryCatch({
      cme_prompt <- build_prompt(row$NarrativeCME, type = "CME", config = test_config)
      cme_result <- send_to_llm(cme_prompt, test_config)
    }, error = function(e) {
      cli::cli_alert_warning("Failed to process CME narrative for {row$IncidentID}: {e$message}")
      errors <- c(errors, paste("CME", row$IncidentID, e$message))
    })
  }
  
  # Reconcile results
  if (!is.null(le_result) && !is.null(cme_result)) {
    # Weighted average
    final_confidence <- (le_result$confidence * test_config$weights$le + 
                        cme_result$confidence * test_config$weights$cme)
    final_decision <- final_confidence >= test_config$weights$threshold
    source <- "both"
  } else if (!is.null(le_result)) {
    final_confidence <- le_result$confidence
    final_decision <- le_result$ipv_detected
    source <- "LE"
  } else if (!is.null(cme_result)) {
    final_confidence <- cme_result$confidence
    final_decision <- cme_result$ipv_detected
    source <- "CME"
  } else {
    final_confidence <- NA
    final_decision <- NA
    source <- "none"
  }
  
  # Add to results
  results <- bind_rows(results, tibble::tibble(
    IncidentID = row$IncidentID,
    ipv_detected = final_decision,
    confidence = final_confidence,
    source = source,
    le_ipv = if(!is.null(le_result)) le_result$ipv_detected else NA,
    le_confidence = if(!is.null(le_result)) le_result$confidence else NA,
    cme_ipv = if(!is.null(cme_result)) cme_result$ipv_detected else NA,
    cme_confidence = if(!is.null(cme_result)) cme_result$confidence else NA
  ))
}

cli::cli_progress_done(id = pb)
cli::cli_alert_success("Processed {nrow(results)} records")

# Report any errors
if (length(errors) > 0) {
  cli::cli_alert_warning("Encountered {length(errors)} errors during processing")
  # Ensure logs directory exists
  if (!dir.exists("logs")) {
    dir.create("logs", showWarnings = FALSE)
  }
  cli::cli_text("Error details saved to logs/test_errors.log")
  writeLines(errors, "logs/test_errors.log")
}

# Display results summary
cli::cli_h2("Results Summary")

results_summary <- results %>%
  summarise(
    total_records = n(),
    ipv_detected_count = sum(ipv_detected, na.rm = TRUE),
    ipv_detected_pct = mean(ipv_detected, na.rm = TRUE) * 100,
    avg_confidence = mean(confidence, na.rm = TRUE),
    both_narratives = sum(source == "both"),
    le_only = sum(source == "LE"),
    cme_only = sum(source == "CME"),
    no_narratives = sum(source == "none")
  )

cli::cli_text("Total records processed: {results_summary$total_records}")
cli::cli_text("IPV detected: {results_summary$ipv_detected_count} ({round(results_summary$ipv_detected_pct, 1)}%)")
cli::cli_text("Average confidence: {round(results_summary$avg_confidence, 3)}")
cli::cli_text("Records with both narratives: {results_summary$both_narratives}")
cli::cli_text("Records with LE narrative only: {results_summary$le_only}")
cli::cli_text("Records with CME narrative only: {results_summary$cme_only}")
cli::cli_text("Records with no narratives: {results_summary$no_narratives}")

# Validation if manual flags are available
if (validation_available && length(manual_flag_cols) > 0) {
  cli::cli_h2("Validation Against Manual Flags")
  
  # Get the first manual flag column
  manual_col <- manual_flag_cols[1]
  
  # Join results with manual flags
  validation_data <- results %>%
    left_join(test_sample %>% select(IncidentID, manual_flag = !!manual_col), 
              by = "IncidentID")
  
  # Calculate metrics
  validation_metrics <- validation_data %>%
    filter(!is.na(ipv_detected) & !is.na(manual_flag)) %>%
    summarise(
      true_positive = sum(ipv_detected & manual_flag),
      true_negative = sum(!ipv_detected & !manual_flag),
      false_positive = sum(ipv_detected & !manual_flag),
      false_negative = sum(!ipv_detected & manual_flag),
      accuracy = (true_positive + true_negative) / n(),
      precision = true_positive / (true_positive + false_positive),
      recall = true_positive / (true_positive + false_negative)
    )
  
  cli::cli_text("Accuracy: {round(validation_metrics$accuracy * 100, 1)}%")
  cli::cli_text("Precision: {round(validation_metrics$precision * 100, 1)}%")
  cli::cli_text("Recall: {round(validation_metrics$recall * 100, 1)}%")
}

# Save results
cli::cli_h2("Saving Results")

# Ensure results directory exists
if (!dir.exists("results")) {
  dir.create("results", showWarnings = FALSE)
}

output_path <- "results/test_results.csv"
readr::write_csv(results, output_path)
cli::cli_alert_success("Results saved to {output_path}")

# Save detailed report
# Ensure docs/reports directory exists
if (!dir.exists("docs")) {
  dir.create("docs", showWarnings = FALSE)
}
if (!dir.exists("docs/reports")) {
  dir.create("docs/reports", showWarnings = FALSE)
}
report_path <- "docs/reports/test_report.txt"
sink(report_path)
cat("NVDRS IPV Detector Test Report\n")
cat("===============================\n\n")
cat("Test Date:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("Package Version: 0.1.0 (Refactored)\n")
cat("Data File:", data_path, "\n")
cat("Sample Size:", sample_size, "\n\n")

cat("Results Summary\n")
cat("---------------\n")
print(results_summary)
cat("\n")

if (validation_available) {
  cat("Validation Metrics\n")
  cat("-----------------\n")
  print(validation_metrics)
}

cat("\n\nDetailed Results\n")
cat("----------------\n")
print(results)
sink()

cli::cli_alert_success("Detailed report saved to {report_path}")

cli::cli_h1("Test Complete")
cli::cli_alert_success("All tests completed successfully!")
cli::cli_text("Results files:")
cli::cli_text("  - {output_path}: Detection results in CSV format")
cli::cli_text("  - {report_path}: Detailed text report")
cli::cli_text("  - {sample_csv_path}: Test sample data")
cli::cli_text("  - {config_path}: Test configuration")
if (length(errors) > 0) {
  cli::cli_text("  - logs/test_errors.log: Error details")
}
