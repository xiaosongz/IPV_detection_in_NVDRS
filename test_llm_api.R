#!/usr/bin/env Rscript

# Test script for actual LLM API integration
# Tests the nvdrs_ipv_detector package with real LM Studio API calls

library(httr2)
library(jsonlite)
library(readxl)
library(yaml)
library(cli)

# Load package functions
devtools::load_all("nvdrsipvdetector")

# Configuration
LM_STUDIO_URL <- "http://192.168.10.22:1234/v1"
MODEL <- "openai/gpt-oss-120b"  # Back to original model after draft model removed

cli_alert_info("Testing LLM API Connection to {LM_STUDIO_URL}")

# Test 1: Basic API connectivity
test_api_connection <- function() {
  cli_h2("Test 1: API Connection")
  
  tryCatch({
    # Test with a simple prompt
    response <- request(paste0(LM_STUDIO_URL, "/chat/completions")) |>
      req_headers(
        "Content-Type" = "application/json"
      ) |>
      req_body_json(list(
        model = MODEL,
        messages = list(
          list(role = "system", content = "You are a helpful assistant."),
          list(role = "user", content = "Say 'API Connected' if you receive this.")
        ),
        temperature = 0.1,
        max_tokens = 50
      )) |>
      req_timeout(10) |>
      req_perform()
    
    result <- resp_body_json(response)
    cli_alert_success("API Connection Successful!")
    cli_alert_info("Response: {result$choices[[1]]$message$content}")
    return(TRUE)
  }, error = function(e) {
    cli_alert_danger("API Connection Failed: {e$message}")
    return(FALSE)
  })
}

# Test 2: IPV Detection with real narratives
test_ipv_detection <- function() {
  cli_h2("Test 2: IPV Detection with Real Narratives")
  
  # Load test data
  test_data <- read_excel("nvdrsipvdetector/data-raw/sui_all_flagged.xlsx")
  cli_alert_info("Loaded {nrow(test_data)} test records")
  
  # Load prompts
  prompts <- yaml::read_yaml("nvdrsipvdetector/inst/prompts/ipv_prompts.yml")
  
  # Test with first 5 narratives that have manual flags
  test_cases <- test_data[1:5, ]
  
  results <- list()
  
  for (i in 1:nrow(test_cases)) {
    case <- test_cases[i, ]
    cli_alert_info("Testing IncidentID: {case$IncidentID}")
    
    # Test LE narrative if present
    if (!is.na(case$NarrativeLE) && nchar(trimws(case$NarrativeLE)) > 0) {
      cli_alert("Processing LE narrative...")
      
      prompt <- gsub("\\{narrative\\}", case$NarrativeLE, prompts$le_prompt_template)
      
      tryCatch({
        response <- request(paste0(LM_STUDIO_URL, "/chat/completions")) |>
          req_headers("Content-Type" = "application/json") |>
          req_body_json(list(
            model = MODEL,
            messages = list(
              list(role = "system", content = prompts$system_prompt),
              list(role = "user", content = prompt)
            ),
            temperature = 0.3,
            max_tokens = 500
          )) |>
          req_timeout(30) |>
          req_perform()
        
        result <- resp_body_json(response)
        content <- result$choices[[1]]$message$content
        
        # Try to parse JSON response
        parsed <- tryCatch(
          fromJSON(content),
          error = function(e) {
            cli_alert_warning("Failed to parse JSON, raw response: {substr(content, 1, 100)}...")
            list(ipv_detected = NA, confidence = NA, parse_error = TRUE)
          }
        )
        
        results[[paste0("LE_", case$IncidentID)]] <- list(
          incident_id = case$IncidentID,
          type = "LE",
          manual_flag = case$ipv_flag_LE,
          llm_detection = parsed$ipv_detected,
          confidence = parsed$confidence,
          indicators = parsed$indicators,
          rationale = parsed$rationale,
          match = identical(as.logical(parsed$ipv_detected), as.logical(case$ipv_flag_LE))
        )
        
        cli_alert_success("LE: Manual={case$ipv_flag_LE}, LLM={parsed$ipv_detected}, Match={results[[paste0('LE_', case$IncidentID)]]$match}")
        
      }, error = function(e) {
        cli_alert_danger("Error processing LE narrative: {e$message}")
        results[[paste0("LE_", case$IncidentID)]] <- list(
          incident_id = case$IncidentID,
          type = "LE",
          error = e$message
        )
      })
    }
    
    # Test CME narrative if present
    if (!is.na(case$NarrativeCME) && nchar(trimws(case$NarrativeCME)) > 0) {
      cli_alert("Processing CME narrative...")
      
      prompt <- gsub("\\{narrative\\}", case$NarrativeCME, prompts$cme_prompt_template)
      
      tryCatch({
        response <- request(paste0(LM_STUDIO_URL, "/chat/completions")) |>
          req_headers("Content-Type" = "application/json") |>
          req_body_json(list(
            model = MODEL,
            messages = list(
              list(role = "system", content = prompts$system_prompt),
              list(role = "user", content = prompt)
            ),
            temperature = 0.3,
            max_tokens = 500
          )) |>
          req_timeout(30) |>
          req_perform()
        
        result <- resp_body_json(response)
        content <- result$choices[[1]]$message$content
        
        # Try to parse JSON response
        parsed <- tryCatch(
          fromJSON(content),
          error = function(e) {
            cli_alert_warning("Failed to parse JSON, raw response: {substr(content, 1, 100)}...")
            list(ipv_detected = NA, confidence = NA, parse_error = TRUE)
          }
        )
        
        results[[paste0("CME_", case$IncidentID)]] <- list(
          incident_id = case$IncidentID,
          type = "CME",
          manual_flag = case$ipv_flag_CME,
          llm_detection = parsed$ipv_detected,
          confidence = parsed$confidence,
          indicators = parsed$indicators,
          rationale = parsed$rationale,
          match = identical(as.logical(parsed$ipv_detected), as.logical(case$ipv_flag_CME))
        )
        
        cli_alert_success("CME: Manual={case$ipv_flag_CME}, LLM={parsed$ipv_detected}, Match={results[[paste0('CME_', case$IncidentID)]]$match}")
        
      }, error = function(e) {
        cli_alert_danger("Error processing CME narrative: {e$message}")
        results[[paste0("CME_", case$IncidentID)]] <- list(
          incident_id = case$IncidentID,
          type = "CME",
          error = e$message
        )
      })
    }
    
    # Small delay to avoid overwhelming the API
    Sys.sleep(1)
  }
  
  return(results)
}

# Test 3: Batch processing through package functions
test_batch_processing <- function() {
  cli_h2("Test 3: Batch Processing via Package Functions")
  
  # Create a small test CSV
  test_data <- read_excel("nvdrsipvdetector/data-raw/sui_all_flagged.xlsx")
  small_test <- test_data[1:3, c("IncidentID", "NarrativeLE", "NarrativeCME")]
  
  # Save as CSV for package function
  temp_csv <- tempfile(fileext = ".csv")
  write.csv(small_test, temp_csv, row.names = FALSE)
  
  cli_alert_info("Testing nvdrs_process_batch() with 3 records...")
  
  tryCatch({
    # Set environment variables for config
    Sys.setenv(LM_STUDIO_URL = LM_STUDIO_URL)
    Sys.setenv(LLM_MODEL = MODEL)
    
    # Run batch processing
    results <- nvdrs_process_batch(
      input_file = temp_csv,
      config_file = "nvdrsipvdetector/config/settings.yml",
      validate = FALSE
    )
    
    cli_alert_success("Batch processing completed!")
    cli_alert_info("Processed {nrow(results)} records")
    
    # Show results
    print(results)
    
    unlink(temp_csv)
    return(results)
    
  }, error = function(e) {
    cli_alert_danger("Batch processing failed: {e$message}")
    unlink(temp_csv)
    return(NULL)
  })
}

# Main execution
cli_h1("LLM API Integration Tests")
cli_alert_info("Testing nvdrs_ipv_detector with LM Studio at {LM_STUDIO_URL}")
cli_rule()

# Run tests
api_connected <- test_api_connection()

if (api_connected) {
  cli_rule()
  detection_results <- test_ipv_detection()
  
  # Calculate accuracy
  if (length(detection_results) > 0) {
    cli_rule()
    cli_h2("Accuracy Summary")
    
    matches <- sapply(detection_results, function(x) !is.null(x$match) && x$match)
    total <- sum(sapply(detection_results, function(x) !is.null(x$match)))
    
    if (total > 0) {
      accuracy <- sum(matches) / total * 100
      cli_alert_success("Accuracy: {round(accuracy, 1)}% ({sum(matches)}/{total} matches)")
    }
    
    # Show confidence scores
    confidences <- sapply(detection_results, function(x) x$confidence)
    confidences <- confidences[!is.na(confidences)]
    if (length(confidences) > 0) {
      cli_alert_info("Average confidence: {round(mean(confidences), 3)}")
      cli_alert_info("Confidence range: {round(min(confidences), 3)} - {round(max(confidences), 3)}")
    }
  }
  
  cli_rule()
  batch_results <- test_batch_processing()
  
} else {
  cli_alert_warning("Skipping detection tests due to API connection failure")
  cli_alert_info("Please ensure LM Studio is running at {LM_STUDIO_URL}")
  cli_alert_info("You can start it with: lms server start --cors=true")
}

cli_rule()
cli_alert_success("Testing complete!")