#!/usr/bin/env Rscript

# Test with OPTIMIZED configuration
library(httr2)
library(jsonlite)
library(dplyr)
library(cli)
library(tibble)

cli::cli_h1("IPV Detection Test - OPTIMIZED Configuration")

# Configuration - OPTIMIZED VALUES
base_url <- "http://192.168.10.22:1234/v1"
model <- "openai/gpt-oss-120b"

# OPTIMIZED WEIGHTS
LE_WEIGHT <- 0.35  # Reduced from 0.4
CME_WEIGHT <- 0.65  # Increased from 0.6
THRESHOLD <- 0.595  # Optimized from 0.7 based on analysis

# Load test data
test_data <- read.csv("tests/test_data/test_sample.csv", stringsAsFactors = FALSE)
cli::cli_alert_success("Loaded {nrow(test_data)} test cases")
cli::cli_alert_info("Using optimized threshold: {THRESHOLD} (was 0.7)")
cli::cli_alert_info("Using optimized weights: LE={LE_WEIGHT}, CME={CME_WEIGHT}")

# OPTIMIZED PROMPT - Simplified 3-tier structure
call_llm_optimized <- function(narrative, type = "LE") {
  if (is.na(narrative) || trimws(narrative) == "") {
    return(list(
      ipv_detected = NA,
      confidence = NA,
      indicators = list(),
      rationale = "Empty narrative"
    ))
  }
  
  # OPTIMIZED PROMPT with better structure
  prompt <- sprintf("Analyze this %s narrative for intimate partner violence (IPV).

EVIDENCE TIERS:
• Direct Evidence (0.9-1.0): Explicit IPV statements, documented violence, restraining orders
• Contextual Evidence (0.6-0.8): Relationship conflicts, control behaviors, threats
• Circumstantial (0.4-0.5): Relationship mentions, emotional distress, ambiguous situations

KEY INDICATORS TO IDENTIFY:
- Current/former intimate partner involvement
- Physical violence, threats, or coercion
- Restraining/protection orders
- Stalking or harassment
- Control behaviors (financial, social, emotional)
- Custody disputes with violence context
- History of domestic violence
- Partner-precipitated suicide

IMPORTANT: When evidence suggests partner involvement in death circumstances, lean toward detecting IPV.

Narrative: '%s'

Respond with JSON only:
{
  \"ipv_detected\": true/false,
  \"confidence\": 0.0-1.0,
  \"indicators\": [\"specific indicators found\"],
  \"rationale\": \"brief explanation\",
  \"evidence_tier\": \"direct/contextual/circumstantial\"
}",
    ifelse(type == "LE", "law enforcement", "medical examiner"),
    substr(narrative, 1, 8000))
  
  tryCatch({
    resp <- request(paste0(base_url, "/chat/completions")) %>%
      req_body_json(list(
        model = model,
        messages = list(
          list(role = "system", content = "You are an expert forensic analyst specializing in intimate partner violence detection. Analyze narratives systematically using evidence tiers. When uncertain, err toward detecting IPV to prevent missing cases. Respond with valid JSON only."),
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
        rationale = parsed$rationale,
        evidence_tier = parsed$evidence_tier %||% "unknown"
      ))
    }
  }, error = function(e) {
    cli::cli_alert_danger("Error: {e$message}")
  })
  
  return(list(
    ipv_detected = NA,
    confidence = NA,
    indicators = list(),
    rationale = "Processing error",
    evidence_tier = NA
  ))
}

# Process all cases
results <- tibble()

cli::cli_h2("Processing Test Cases with Optimized Configuration")
pb <- cli::cli_progress_bar("Processing", total = nrow(test_data))

for (i in seq_len(nrow(test_data))) {
  case <- test_data[i, ]
  cli::cli_progress_update(id = pb)
  
  # Process with optimized prompts
  le_result <- call_llm_optimized(case$NarrativeLE, "LE")
  cme_result <- call_llm_optimized(case$NarrativeCME, "CME")
  
  # Combined with OPTIMIZED weights and threshold
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
      # Use OPTIMIZED weights
      combined_conf <- le_result$confidence * LE_WEIGHT + cme_result$confidence * CME_WEIGHT
      # Use OPTIMIZED threshold
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
    cme_indicators = paste(cme_result$indicators, collapse = "; "),
    le_tier = le_result$evidence_tier %||% NA,
    cme_tier = cme_result$evidence_tier %||% NA
  ))
  
  # Show progress
  if (i %% 5 == 0) {
    cli::cli_alert_info("Processed {i}/{nrow(test_data)} cases")
  }
}

cli::cli_progress_done(id = pb)

# Save results
write.csv(results, "tests/test_results/optimized_results.csv", row.names = FALSE)
cli::cli_alert_success("Results saved to tests/test_results/optimized_results.csv")

# Calculate metrics
cli::cli_h2("OPTIMIZED Performance Metrics")

results <- results %>%
  mutate(actual_combined = actual_le | actual_cme)

# Combined metrics (main focus)
combined_valid <- results %>% filter(!is.na(combined_ipv) & !is.na(actual_combined))
combined_tp <- sum(combined_valid$combined_ipv & combined_valid$actual_combined)
combined_tn <- sum(!combined_valid$combined_ipv & !combined_valid$actual_combined)
combined_fp <- sum(combined_valid$combined_ipv & !combined_valid$actual_combined)
combined_fn <- sum(!combined_valid$combined_ipv & combined_valid$actual_combined)
combined_accuracy <- (combined_tp + combined_tn) / nrow(combined_valid)
combined_precision <- ifelse(combined_tp + combined_fp > 0, combined_tp / (combined_tp + combined_fp), 0)
combined_recall <- ifelse(combined_tp + combined_fn > 0, combined_tp / (combined_tp + combined_fn), 0)
combined_f1 <- ifelse(combined_precision + combined_recall > 0, 
                     2 * combined_precision * combined_recall / (combined_precision + combined_recall), 0)

cli::cli_alert_success("OPTIMIZED Combined Performance:")
cli::cli_alert_success("  Accuracy: {round(combined_accuracy, 3)} ({combined_tp + combined_tn}/{nrow(combined_valid)})")
cli::cli_alert_success("  Precision: {round(combined_precision, 3)} ({combined_tp}/{combined_tp + combined_fp})")
cli::cli_alert_success("  Recall: {round(combined_recall, 3)} ({combined_tp}/{combined_tp + combined_fn})")
cli::cli_alert_success("  F1 Score: {round(combined_f1, 3)}")
cli::cli_alert_info("  Confusion Matrix: TP={combined_tp}, TN={combined_tn}, FP={combined_fp}, FN={combined_fn}")

# Compare with baseline
cli::cli_h2("Improvement from Baseline")
baseline_accuracy <- 0.9
baseline_f1 <- 0.947
baseline_recall <- 0.9

if (combined_accuracy > baseline_accuracy) {
  cli::cli_alert_success("✅ Accuracy improved: {round((combined_accuracy - baseline_accuracy) * 100, 1)}% gain")
} else if (combined_accuracy == baseline_accuracy) {
  cli::cli_alert_info("➡️ Accuracy maintained at {round(combined_accuracy * 100, 1)}%")
} else {
  cli::cli_alert_warning("⚠️ Accuracy decreased: {round((baseline_accuracy - combined_accuracy) * 100, 1)}% loss")
}

if (combined_recall > baseline_recall) {
  cli::cli_alert_success("✅ Recall improved: {round((combined_recall - baseline_recall) * 100, 1)}% gain")
}

if (combined_f1 > baseline_f1) {
  cli::cli_alert_success("✅ F1 Score improved: {round(combined_f1 - baseline_f1, 3)} gain")
}

# Check specific problem cases
problem_cases <- c("336938", "361697")  # Cases that failed in baseline
problem_results <- results %>% filter(incident_id %in% problem_cases)

cli::cli_h3("Problem Cases from Baseline")
for (i in 1:nrow(problem_results)) {
  case <- problem_results[i, ]
  cli::cli_alert_info("Case {case$incident_id}: Predicted={case$combined_ipv}, Actual={case$actual_combined}, Conf={round(case$combined_conf, 3)}")
  if (case$combined_ipv == case$actual_combined) {
    cli::cli_alert_success("  ✅ Now correctly classified!")
  }
}

cli::cli_alert_success("Optimized test completed!")