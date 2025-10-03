#!/usr/bin/env Rscript

#' Updated IPV Detection Benchmark Script
#' 
#' Uses the new batch processing function to run through all narratives

library(readxl)
library(here)
library(glue)
library(tidyr)
library(dplyr)
library(tibble)

# Source existing functions
source(here::here("R", "build_prompt.R"))
source(here::here("R", "call_llm.R"))
source(here::here("R", "parse_llm_result.R"))
source(here::here("R", "db_utils.R"))
source(here::here("R", "store_llm_result.R"))
source(here::here("R", "run_ipv_detection_batch.R"))

# =============================================================================
# CONFIGURATION
# =============================================================================

MODELS <- c("openai/gpt-oss-120b", "qwen/qwen3-30b-a3b-2507", "qwen3-30b-a3b-thinking-2507-mlx")
API_URL <- Sys.getenv("LLM_API_URL", "http://localhost:1234/v1/chat/completions")
DATA_FILE <- here::here("data-raw", "suicide_IPV_manuallyflagged.xlsx")
OUTPUT_FILE <- paste0("benchmark_results_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".csv")

# =============================================================================
# LOAD DATA
# =============================================================================

cat("Loading data from", basename(DATA_FILE), "\n")
data <- read_excel(DATA_FILE)

# Transform data to long format
data_long <- data %>%
  pivot_longer(
    cols = c(NarrativeCME, NarrativeLE),
    names_to = "Type",
    values_to = "Narrative"
  ) %>%
  mutate(
    Type = tolower(gsub("Narrative", "", Type)),
    M_flag_ind = case_when(
      Type == "cme" ~ ipv_manualCME,
      Type == "le" ~ ipv_manualLE
    ),
    M_flag = ipv_manual
  ) %>%
  select(IncidentID, Type, Narrative, M_flag_ind, M_flag) |> 
  mutate(
    M_flag_ind = as.logical(M_flag_ind),
    M_flag = as.logical(M_flag)
  ) |> 
  mutate(row_num = row_number()) |> 
  relocate(row_num, .before = IncidentID)

# Count valid narratives
n_valid <- sum(!is.na(data_long$Narrative) & nchar(trimws(data_long$Narrative)) > 0)
n_ipv <- sum(data_long$M_flag_ind, na.rm = TRUE)

cat("Found", nrow(data_long), "total narratives\n")
cat("  Valid narratives:", n_valid, "\n")
cat("  IPV positive:", n_ipv, "\n\n")

# =============================================================================
# DEFINE PROMPTS
# =============================================================================

system_prompt <- r"(
/think. ROLE: You identify intimate partner violence (IPV) evidence in death investigation narratives. 
We want to know if the death could be related to IPV, not necessarily caused by IPV.

SCOPE: Use ONLY the narrative text. Do not infer beyond stated facts. If evidence is insufficient, say so via low confidence.

INDICATOR VOCAB:
- behavioral/social: "domestic violence history","restraining order","stalking","jealousy/control","recent separation","sexual exploitation","threats between partners","custody dispute","financial control"
- physical/medical: "multiple-stage injuries","defensive wounds","strangulation marks","pattern injury","genital trauma","prior unexplained injuries","injury inconsistent with stated cause"
- contextual: "partner's weapon","shared residence scene","witness conflict reports","note mentions partner","police DV report","prior DV arrest"

DETECTION POLICY (when to set detected=true):
A. Explicit abuse or assault by a current/former partner, OR
B. Legal/procedural evidence (e.g., restraining order, police DV report, prior DV arrest), OR
C. Credible threats/stalking/jealousy/control/separation/sexual exploitation tied to the partner, OR
D. Evidence of non-legal indicators that plausibly link the partner to coercion/violence (e.g., recent separation + threats + witness reports).
Note: "recent separation" alone is NOT sufficient.

CONFIDENCE CALIBRATION:
- 0.90–1.00: direct DV evidence (A/B) or multiple strong C/D signals.
- 0.70–0.89: strong but indirect signals; likely IPV.
- 0.40–0.69: one moderate signal (e.g., threats) with weak support.
- 0.05–0.39: weak/ambiguous context only (e.g., breakup without abuse).
- 0.00: narrative negates IPV.

OUTPUT RULES:
- Return ONE JSON object with keys: detected:boolean, confidence:number (0–1), indicators:array[string], rationale:string (≤200 chars).
- indicators must be a subset of the VOCAB (dedupe; 0–5 items).
- rationale: concise, cites narrative facts; no chain-of-thought; no quotes >10 words.
- No extra keys, no prose, no code fences.
)"

user_template <- r"(
Analyze the following death investigation narrative for intimate partner violence (IPV).

Narrative:
<<TEXT>>
Respond ONLY with a single valid JSON object matching:
{
  "detected": <true|false>,
  "confidence": <number between 0 and 1>,
  "indicators": ["<tokens from the indicator vocab>"],
  "rationale": "<≤200 chars, concise justification using facts from the narrative>"
}
Do not include chain-of-thought, explanations, or extra text. If no indicators are supported by the narrative, use [] and set a low confidence per the calibration.
)"

# =============================================================================
# RUN BENCHMARK FOR EACH MODEL
# =============================================================================

all_results <- list()

for (model in MODELS) {
  cat("\n", paste(rep("=", 70), collapse = ""), "\n")
  cat("Testing model:", model, "\n")
  cat(paste(rep("=", 70), collapse = ""), "\n\n")
  
  # Run detection on all narratives
  start_time <- Sys.time()
  
  results <- run_ipv_detection_batch(
    data_long = data_long,
    system_prompt = system_prompt,
    user_template = user_template,
    model = model,
    api_url = API_URL,
    temperature = 0.5,
    verbose = TRUE
  )
  
  end_time <- Sys.time()
  total_time <- difftime(end_time, start_time, units = "secs")
  
  # Add model info to results
  results$model_tested <- model
  results$batch_run_time <- as.numeric(total_time)
  
  # Store results
  all_results[[model]] <- results
  
  # Calculate and display metrics
  if (nrow(results) > 0) {
    valid_results <- results %>%
      filter(!is.na(detected) & !is.na(manual_flag_ind))
    
    if (nrow(valid_results) > 0) {
      accuracy <- mean(valid_results$detected == valid_results$manual_flag_ind)
      sensitivity <- mean(valid_results$detected[valid_results$manual_flag_ind == TRUE])
      specificity <- mean(!valid_results$detected[valid_results$manual_flag_ind == FALSE])
      
      cat("\nModel Performance:\n")
      cat("  Processed:", nrow(results), "narratives\n")
      cat("  Valid results:", nrow(valid_results), "\n")
      cat("  Accuracy:", sprintf("%.2f%%", accuracy * 100), "\n")
      cat("  Sensitivity:", sprintf("%.2f%%", sensitivity * 100), "\n")
      cat("  Specificity:", sprintf("%.2f%%", specificity * 100), "\n")
      cat("  Total time:", sprintf("%.1f seconds", total_time), "\n")
      cat("  Avg time per narrative:", sprintf("%.2f seconds", total_time / nrow(results)), "\n")
    }
  }
}

# =============================================================================
# COMBINE AND SAVE RESULTS
# =============================================================================

final_results <- bind_rows(all_results)

# Save to CSV
write.csv(final_results, OUTPUT_FILE, row.names = FALSE)
cat("\n\nResults saved to:", OUTPUT_FILE, "\n")

# Store in database if available
if (exists("store_llm_result")) {
  cat("Storing results in database...\n")
  for (i in seq_len(nrow(final_results))) {
    tryCatch({
      store_llm_result(final_results[i, ])
    }, error = function(e) {
      cat("  Error storing row", i, ":", e$message, "\n")
    })
  }
  cat("Database storage complete\n")
}

# =============================================================================
# SUMMARY COMPARISON
# =============================================================================

cat("\n", paste(rep("=", 70), collapse = ""), "\n")
cat("SUMMARY COMPARISON\n")
cat(paste(rep("=", 70), collapse = ""), "\n\n")

for (model in names(all_results)) {
  results <- all_results[[model]]
  valid_results <- results %>%
    filter(!is.na(detected) & !is.na(manual_flag_ind))
  
  if (nrow(valid_results) > 0) {
    accuracy <- mean(valid_results$detected == valid_results$manual_flag_ind)
    cat(sprintf("%-40s: %.2f%% accuracy\n", model, accuracy * 100))
  }
}

cat("\nBenchmark complete!\n")