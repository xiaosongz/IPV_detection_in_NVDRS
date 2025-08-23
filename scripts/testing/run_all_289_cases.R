#!/usr/bin/env Rscript

# Run IPV Detection on ALL 289 cases from Excel
library(readxl)
library(httr2)
library(jsonlite)
library(dplyr)
library(cli)
library(tibble)
library(stringr)

cli::cli_h1("IPV Detection - ALL 289 Cases from sui_all_flagged.xlsx")
cli::cli_alert_info("Starting at {Sys.time()}")

# Load the Excel file
excel_path <- "nvdrsipvdetector/inst/extdata/sui_all_flagged.xlsx"
full_data <- read_excel(excel_path)
cli::cli_alert_success("Loaded {nrow(full_data)} cases from Excel file")

# Configuration - OPTIMAL VALUES
base_url <- "http://192.168.10.22:1234/v1"
model <- "openai/gpt-oss-120b"
THRESHOLD <- 0.595  # Optimal threshold
LE_WEIGHT <- 0.4
CME_WEIGHT <- 0.6

cli::cli_alert_info("Using optimal threshold: {THRESHOLD}")
cli::cli_alert_info("Processing will take approximately {round(nrow(full_data) * 6 / 60, 1)} minutes")

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
    substr(narrative, 1, 8000))
  
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
    json_match <- str_extract(content, "\\{[\\s\\S]*\\}")
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
    cli::cli_alert_warning("Error processing narrative: {e$message}")
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

# Process all 289 cases
results <- tibble()
total_cases <- nrow(full_data)

cli::cli_h2("Processing {total_cases} Cases")
pb <- cli::cli_progress_bar("Processing cases", total = total_cases)

start_time <- Sys.time()

for (i in 1:total_cases) {
  case <- full_data[i, ]
  cli::cli_progress_update(id = pb)
  
  # Process LE narrative
  le_result <- if (!is.na(case$NarrativeLE)) {
    call_llm(case$NarrativeLE, "LE")
  } else {
    list(ipv_detected = NA, confidence = NA, indicators = list(), rationale = "No LE narrative")
  }
  
  # Process CME narrative
  cme_result <- if (!is.na(case$NarrativeCME)) {
    call_llm(case$NarrativeCME, "CME")
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
      combined_conf <- le_result$confidence * LE_WEIGHT + cme_result$confidence * CME_WEIGHT
      combined_ipv <- combined_conf >= THRESHOLD
    }
  }
  
  # Store result
  results <- bind_rows(results, tibble(
    incident_id = case$IncidentID,
    actual_le = case$ipv_flag_LE,
    actual_cme = case$ipv_flag_CME,
    predicted_le = le_result$ipv_detected,
    predicted_cme = cme_result$ipv_detected,
    confidence_le = le_result$confidence,
    confidence_cme = cme_result$confidence,
    combined_ipv = combined_ipv,
    combined_conf = combined_conf,
    le_indicators = paste(le_result$indicators, collapse = "; "),
    cme_indicators = paste(cme_result$indicators, collapse = "; ")
  ))
  
  # Progress update every 10 cases
  if (i %% 10 == 0) {
    elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))
    rate <- i / elapsed
    remaining <- (total_cases - i) / rate
    cli::cli_alert_info("Processed {i}/{total_cases} cases. ETA: {round(remaining, 1)} minutes")
  }
  
  # Save intermediate results every 50 cases
  if (i %% 50 == 0) {
    write.csv(results, "tests/test_results/all_289_intermediate.csv", row.names = FALSE)
    cli::cli_alert_info("Saved intermediate results")
  }
}

cli::cli_progress_done(id = pb)

# Save final results
output_file <- paste0("tests/test_results/all_289_cases_results_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".csv")
write.csv(results, output_file, row.names = FALSE)
cli::cli_alert_success("Results saved to {output_file}")

# Calculate performance metrics
cli::cli_h2("Performance Metrics")

# Combined ground truth (either LE or CME flagged as IPV)
results <- results %>%
  mutate(actual_combined = actual_le | actual_cme)

# Overall metrics
valid_results <- results %>% filter(!is.na(combined_ipv) & !is.na(actual_combined))

if (nrow(valid_results) > 0) {
  tp <- sum(valid_results$combined_ipv & valid_results$actual_combined)
  tn <- sum(!valid_results$combined_ipv & !valid_results$actual_combined)
  fp <- sum(valid_results$combined_ipv & !valid_results$actual_combined)
  fn <- sum(!valid_results$combined_ipv & valid_results$actual_combined)
  
  accuracy <- (tp + tn) / nrow(valid_results)
  precision <- ifelse(tp + fp > 0, tp / (tp + fp), 0)
  recall <- ifelse(tp + fn > 0, tp / (tp + fn), 0)
  f1 <- ifelse(precision + recall > 0, 2 * precision * recall / (precision + recall), 0)
  
  cli::cli_alert_success("Overall Performance (n={nrow(valid_results)}):")
  cli::cli_alert_info("  Accuracy: {round(accuracy * 100, 1)}% ({tp + tn}/{nrow(valid_results)})")
  cli::cli_alert_info("  Precision: {round(precision * 100, 1)}% ({tp}/{tp + fp})")
  cli::cli_alert_info("  Recall: {round(recall * 100, 1)}% ({tp}/{tp + fn})")
  cli::cli_alert_info("  F1 Score: {round(f1, 3)}")
  cli::cli_alert_info("  Confusion Matrix: TP={tp}, TN={tn}, FP={fp}, FN={fn}")
}

# LE-specific metrics
le_valid <- results %>% filter(!is.na(predicted_le) & !is.na(actual_le))
if (nrow(le_valid) > 0) {
  le_acc <- mean(le_valid$predicted_le == le_valid$actual_le)
  cli::cli_alert_info("LE Accuracy: {round(le_acc * 100, 1)}% (n={nrow(le_valid)})")
}

# CME-specific metrics
cme_valid <- results %>% filter(!is.na(predicted_cme) & !is.na(actual_cme))
if (nrow(cme_valid) > 0) {
  cme_acc <- mean(cme_valid$predicted_cme == cme_valid$actual_cme)
  cli::cli_alert_info("CME Accuracy: {round(cme_acc * 100, 1)}% (n={nrow(cme_valid)})")
}

# Summary statistics
cli::cli_h2("Summary Statistics")
cli::cli_alert_info("Total cases processed: {nrow(results)}")
cli::cli_alert_info("Cases with IPV detected: {sum(results$combined_ipv, na.rm = TRUE)}")
cli::cli_alert_info("Detection rate: {round(mean(results$combined_ipv, na.rm = TRUE) * 100, 1)}%")
cli::cli_alert_info("Average confidence: {round(mean(results$combined_conf, na.rm = TRUE), 3)}")

# Processing time
total_time <- difftime(Sys.time(), start_time, units = "mins")
cli::cli_alert_success("Completed processing {total_cases} cases in {round(total_time, 1)} minutes")
cli::cli_alert_info("Average time per case: {round(total_time * 60 / total_cases, 1)} seconds")

cli::cli_alert_success("ALL 289 cases have been processed!")

# Return results
results