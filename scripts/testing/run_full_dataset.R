#!/usr/bin/env Rscript

# Run IPV Detection on FULL Dataset from Excel file
library(readxl)
library(httr2)
library(jsonlite)
library(dplyr)
library(cli)
library(tibble)

cli::cli_h1("IPV Detection - FULL DATASET from sui_all_flagged.xlsx")
cli::cli_alert_info("Starting at {Sys.time()}")

# Load the Excel file
excel_path <- "nvdrsipvdetector/inst/extdata/sui_all_flagged.xlsx"
cli::cli_alert_info("Loading data from: {excel_path}")

# Read Excel file
full_data <- read_excel(excel_path)
cli::cli_alert_success("Loaded {nrow(full_data)} cases from Excel file")

# Display column names to understand structure
cli::cli_alert_info("Columns in dataset:")
print(names(full_data))

# Check first few rows
cli::cli_alert_info("First 3 rows of data:")
print(head(full_data, 3))

# Configuration
base_url <- "http://192.168.10.22:1234/v1"
model <- "openai/gpt-oss-120b"

# OPTIMAL CONFIGURATION based on testing
THRESHOLD <- 0.595  # Optimal threshold from analysis
LE_WEIGHT <- 0.4
CME_WEIGHT <- 0.6

cli::cli_alert_success("Using optimal threshold: {THRESHOLD}")

# Function to call LLM
call_llm <- function(narrative, type = "LE") {
  if (is.null(narrative) || is.na(narrative) || trimws(as.character(narrative)) == "") {
    return(list(
      ipv_detected = NA,
      confidence = NA,
      indicators = list(),
      rationale = "Empty narrative"
    ))
  }
  
  narrative <- as.character(narrative)
  
  prompt <- sprintf("Analyze this %s narrative for intimate partner violence indicators.
Look for: domestic violence, current/former partners, restraining orders, stalking, 
jealousy, control, threats, custody disputes, history of abuse, partner-precipitated suicide.

Narrative: '%s'

Respond with JSON:
{
  \"ipv_detected\": true or false,
  \"confidence\": 0.0 to 1.0,
  \"indicators\": [\"list of specific indicators found\"],
  \"rationale\": \"brief explanation\"
}",
    ifelse(type == "LE", "law enforcement", "medical examiner"),
    substr(narrative, 1, 8000))  # Truncate if too long
  
  tryCatch({
    resp <- request(paste0(base_url, "/chat/completions")) %>%
      req_body_json(list(
        model = model,
        messages = list(
          list(role = "system", content = "You are an AI trained to detect intimate partner violence in death investigation narratives. Respond only with valid JSON."),
          list(role = "user", content = prompt)
        ),
        temperature = 0.1,
        max_tokens = 500
      )) %>%
      req_timeout(30) %>%
      req_perform()
    
    body <- resp_body_json(resp)
    content <- body$choices[[1]]$message$content
    
    # Extract JSON
    json_match <- stringr::str_extract(content, "\\{[\\s\\S]*\\}")
    if (!is.na(json_match)) {
      parsed <- parse_json(json_match)
      return(list(
        ipv_detected = as.logical(parsed$ipv_detected),
        confidence = as.numeric(parsed$confidence),
        indicators = unlist(parsed$indicators),
        rationale = parsed$rationale
      ))
    }
  }, error = function(e) {
    return(list(
      ipv_detected = NA,
      confidence = NA,
      indicators = list(),
      rationale = paste("Error:", e$message)
    ))
  })
  
  return(list(
    ipv_detected = NA,
    confidence = NA,
    indicators = list(),
    rationale = "Processing error"
  ))
}

# Identify narrative columns
le_col <- NULL
cme_col <- NULL
incident_col <- NULL
flag_col <- NULL

# Try to identify columns
col_names_lower <- tolower(names(full_data))
if (any(grepl("narrativele", col_names_lower))) {
  le_col <- names(full_data)[grepl("narrativele", col_names_lower)][1]
}
if (any(grepl("narrativecme", col_names_lower))) {
  cme_col <- names(full_data)[grepl("narrativecme", col_names_lower)][1]
}
if (any(grepl("incidentid", col_names_lower))) {
  incident_col <- names(full_data)[grepl("incidentid", col_names_lower)][1]
}
if (any(grepl("ipv", col_names_lower))) {
  flag_col <- names(full_data)[grepl("ipv", col_names_lower)][1]
}

cli::cli_alert_info("Identified columns:")
cli::cli_alert_info("  LE narrative: {le_col %||% 'NOT FOUND'}")
cli::cli_alert_info("  CME narrative: {cme_col %||% 'NOT FOUND'}")
cli::cli_alert_info("  Incident ID: {incident_col %||% 'NOT FOUND'}")
cli::cli_alert_info("  IPV flag: {flag_col %||% 'NOT FOUND'}")

# Process all cases
results <- tibble()
total_cases <- nrow(full_data)

cli::cli_h2("Processing {total_cases} Cases")
cli::cli_alert_warning("This will take approximately {round(total_cases * 6 / 60, 1)} minutes")

# Create progress bar
pb <- cli::cli_progress_bar("Processing cases", total = total_cases)

# Process in batches to show progress
batch_size <- 10
num_batches <- ceiling(total_cases / batch_size)

for (batch_num in 1:num_batches) {
  start_idx <- (batch_num - 1) * batch_size + 1
  end_idx <- min(batch_num * batch_size, total_cases)
  
  cli::cli_alert_info("Processing batch {batch_num}/{num_batches} (cases {start_idx}-{end_idx})")
  
  for (i in start_idx:end_idx) {
    case <- full_data[i, ]
    cli::cli_progress_update(id = pb)
    
    # Get incident ID
    incident_id <- if (!is.null(incident_col)) {
      as.character(case[[incident_col]])
    } else {
      paste0("case_", i)
    }
    
    # Process LE narrative if exists
    le_result <- if (!is.null(le_col) && !is.na(case[[le_col]])) {
      call_llm(case[[le_col]], "LE")
    } else {
      list(ipv_detected = NA, confidence = NA, indicators = list(), rationale = "No LE narrative")
    }
    
    # Process CME narrative if exists  
    cme_result <- if (!is.null(cme_col) && !is.na(case[[cme_col]])) {
      call_llm(case[[cme_col]], "CME")
    } else {
      list(ipv_detected = NA, confidence = NA, indicators = list(), rationale = "No CME narrative")
    }
    
    # Combined result
    combined_conf <- NA
    combined_ipv <- NA
    
    if (!is.na(le_result$confidence) || !is.na(cme_result$confidence)) {
      if (is.na(le_result$confidence)) {
        combined_conf <- cme_result$confidence
        combined_ipv <- cme_result$ipv_detected
      } else if (is.na(cme_result$confidence)) {
        combined_conf <- le_result$confidence
        combined_ipv <- le_result$ipv_detected
      } else {
        # Weighted average
        combined_conf <- le_result$confidence * LE_WEIGHT + cme_result$confidence * CME_WEIGHT
        combined_ipv <- combined_conf >= THRESHOLD
      }
    }
    
    # Get actual flag if exists
    actual_ipv <- if (!is.null(flag_col)) {
      as.logical(case[[flag_col]])
    } else {
      NA
    }
    
    # Store result
    results <- bind_rows(results, tibble(
      incident_id = incident_id,
      actual_ipv = actual_ipv,
      predicted_le = le_result$ipv_detected,
      predicted_cme = cme_result$ipv_detected,
      confidence_le = le_result$confidence,
      confidence_cme = cme_result$confidence,
      combined_ipv = combined_ipv,
      combined_conf = combined_conf,
      le_indicators = paste(le_result$indicators, collapse = "; "),
      cme_indicators = paste(cme_result$indicators, collapse = "; ")
    ))
    
    # Save intermediate results every 50 cases
    if (nrow(results) %% 50 == 0) {
      write.csv(results, "tests/test_results/full_dataset_intermediate.csv", row.names = FALSE)
      cli::cli_alert_info("Saved intermediate results ({nrow(results)} cases)")
    }
  }
  
  # Add small delay between batches to avoid overwhelming API
  if (batch_num < num_batches) {
    Sys.sleep(2)
  }
}

cli::cli_progress_done(id = pb)

# Save final results
output_file <- paste0("tests/test_results/full_dataset_results_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".csv")
write.csv(results, output_file, row.names = FALSE)
cli::cli_alert_success("Results saved to {output_file}")

# Calculate metrics if ground truth exists
if (!is.null(flag_col)) {
  cli::cli_h2("Performance Metrics")
  
  valid_results <- results %>% filter(!is.na(combined_ipv) & !is.na(actual_ipv))
  
  if (nrow(valid_results) > 0) {
    tp <- sum(valid_results$combined_ipv & valid_results$actual_ipv)
    tn <- sum(!valid_results$combined_ipv & !valid_results$actual_ipv)
    fp <- sum(valid_results$combined_ipv & !valid_results$actual_ipv)
    fn <- sum(!valid_results$combined_ipv & valid_results$actual_ipv)
    
    accuracy <- (tp + tn) / nrow(valid_results)
    precision <- ifelse(tp + fp > 0, tp / (tp + fp), 0)
    recall <- ifelse(tp + fn > 0, tp / (tp + fn), 0)
    f1 <- ifelse(precision + recall > 0, 2 * precision * recall / (precision + recall), 0)
    
    cli::cli_alert_success("Performance on {nrow(valid_results)} cases with ground truth:")
    cli::cli_alert_info("  Accuracy: {round(accuracy * 100, 1)}% ({tp + tn}/{nrow(valid_results)})")
    cli::cli_alert_info("  Precision: {round(precision * 100, 1)}% ({tp}/{tp + fp})")
    cli::cli_alert_info("  Recall: {round(recall * 100, 1)}% ({tp}/{tp + fn})")
    cli::cli_alert_info("  F1 Score: {round(f1, 3)}")
    cli::cli_alert_info("  Confusion Matrix: TP={tp}, TN={tn}, FP={fp}, FN={fn}")
  }
}

# Summary statistics
cli::cli_h2("Summary Statistics")
cli::cli_alert_info("Total cases processed: {nrow(results)}")
cli::cli_alert_info("Cases with IPV detected: {sum(results$combined_ipv, na.rm = TRUE)}")
cli::cli_alert_info("Detection rate: {round(mean(results$combined_ipv, na.rm = TRUE) * 100, 1)}%")
cli::cli_alert_info("Average confidence: {round(mean(results$combined_conf, na.rm = TRUE), 3)}")

# Show confidence distribution
conf_breaks <- cut(results$combined_conf, breaks = c(0, 0.3, 0.5, 0.7, 0.9, 1.0), include.lowest = TRUE)
cli::cli_alert_info("Confidence distribution:")
print(table(conf_breaks))

cli::cli_alert_success("Full dataset processing completed at {Sys.time()}")

# Return results for further analysis
results