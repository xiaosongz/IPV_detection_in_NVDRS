#!/usr/bin/env Rscript

# Test with mock API for rapid iteration
library(httr2)
library(jsonlite)
library(dplyr)
library(cli)
library(tibble)

cli::cli_h1("IPV Detection Test - Direct API Calls")

# Configuration
base_url <- "http://192.168.10.22:1234/v1"
model <- "openai/gpt-oss-120b"

# Load test data
test_data <- read.csv("tests/test_data/test_sample.csv", stringsAsFactors = FALSE)
cli::cli_alert_success("Loaded {nrow(test_data)} test cases")

# Function to call LLM
call_llm <- function(narrative, type = "LE") {
  if (is.na(narrative) || trimws(narrative) == "") {
    return(list(
      ipv_detected = NA,
      confidence = NA,
      indicators = list(),
      rationale = "Empty narrative"
    ))
  }
  
  prompt <- sprintf("Analyze this %s narrative for intimate partner violence indicators.
Look for: domestic violence, current/former partners, restraining orders, stalking, 
jealousy, control, threats, custody disputes, history of abuse.

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
    cli::cli_alert_danger("Error: {e$message}")
  })
  
  return(list(
    ipv_detected = NA,
    confidence = NA,
    indicators = list(),
    rationale = "Processing error"
  ))
}

# Process all cases
results <- tibble()

cli::cli_h2("Processing Test Cases")
pb <- cli::cli_progress_bar("Processing", total = nrow(test_data))

for (i in seq_len(nrow(test_data))) {
  case <- test_data[i, ]
  cli::cli_progress_update(id = pb)
  
  # Process LE
  le_result <- call_llm(case$NarrativeLE, "LE")
  
  # Process CME
  cme_result <- call_llm(case$NarrativeCME, "CME")
  
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
      combined_conf <- le_result$confidence * 0.4 + cme_result$confidence * 0.6
      combined_ipv <- combined_conf >= 0.7
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
  
  # Show progress
  if (i %% 5 == 0) {
    cli::cli_alert_info("Processed {i}/{nrow(test_data)} cases")
  }
}

cli::cli_progress_done(id = pb)

# Save results
write.csv(results, "tests/test_results/baseline_results.csv", row.names = FALSE)
cli::cli_alert_success("Results saved to tests/test_results/baseline_results.csv")

# Calculate metrics
cli::cli_h2("Performance Metrics")

# LE metrics
le_valid <- results %>% filter(!is.na(predicted_le) & !is.na(actual_le))
if (nrow(le_valid) > 0) {
  le_accuracy <- mean(le_valid$predicted_le == le_valid$actual_le)
  le_tp <- sum(le_valid$predicted_le & le_valid$actual_le)
  le_fp <- sum(le_valid$predicted_le & !le_valid$actual_le)
  le_fn <- sum(!le_valid$predicted_le & le_valid$actual_le)
  le_precision <- ifelse(le_tp + le_fp > 0, le_tp / (le_tp + le_fp), 0)
  le_recall <- ifelse(le_tp + le_fn > 0, le_tp / (le_tp + le_fn), 0)
  
  cli::cli_alert_info("LE: Acc={round(le_accuracy, 3)}, Prec={round(le_precision, 3)}, Rec={round(le_recall, 3)}")
}

# CME metrics
cme_valid <- results %>% filter(!is.na(predicted_cme) & !is.na(actual_cme))
if (nrow(cme_valid) > 0) {
  cme_accuracy <- mean(cme_valid$predicted_cme == cme_valid$actual_cme)
  cme_tp <- sum(cme_valid$predicted_cme & cme_valid$actual_cme)
  cme_fp <- sum(cme_valid$predicted_cme & !cme_valid$actual_cme)
  cme_fn <- sum(!cme_valid$predicted_cme & cme_valid$actual_cme)
  cme_precision <- ifelse(cme_tp + cme_fp > 0, cme_tp / (cme_tp + cme_fp), 0)
  cme_recall <- ifelse(cme_tp + cme_fn > 0, cme_tp / (cme_tp + cme_fn), 0)
  
  cli::cli_alert_info("CME: Acc={round(cme_accuracy, 3)}, Prec={round(cme_precision, 3)}, Rec={round(cme_recall, 3)}")
}

# Combined metrics
combined_valid <- results %>% 
  mutate(actual_combined = actual_le | actual_cme) %>%
  filter(!is.na(combined_ipv) & !is.na(actual_combined))

if (nrow(combined_valid) > 0) {
  combined_accuracy <- mean(combined_valid$combined_ipv == combined_valid$actual_combined)
  combined_tp <- sum(combined_valid$combined_ipv & combined_valid$actual_combined)
  combined_fp <- sum(combined_valid$combined_ipv & !combined_valid$actual_combined)
  combined_fn <- sum(!combined_valid$combined_ipv & combined_valid$actual_combined)
  combined_precision <- ifelse(combined_tp + combined_fp > 0, combined_tp / (combined_tp + combined_fp), 0)
  combined_recall <- ifelse(combined_tp + combined_fn > 0, combined_tp / (combined_tp + combined_fn), 0)
  combined_f1 <- ifelse(combined_precision + combined_recall > 0, 
                        2 * combined_precision * combined_recall / (combined_precision + combined_recall), 0)
  
  cli::cli_alert_success("COMBINED: Acc={round(combined_accuracy, 3)}, Prec={round(combined_precision, 3)}, Rec={round(combined_recall, 3)}, F1={round(combined_f1, 3)}")
}

# Show misclassifications
errors <- results %>%
  mutate(actual_combined = actual_le | actual_cme) %>%
  filter(combined_ipv != actual_combined)

if (nrow(errors) > 0) {
  cli::cli_alert_warning("{nrow(errors)} misclassified cases:")
  for (i in 1:min(5, nrow(errors))) {
    cli::cli_alert_info("  Case {errors$incident_id[i]}: Predicted={errors$combined_ipv[i]}, Actual={errors$actual_combined[i]}")
  }
}

cli::cli_alert_success("Test completed!")
results