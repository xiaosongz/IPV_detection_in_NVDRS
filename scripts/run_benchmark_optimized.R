#!/usr/bin/env Rscript

#' Optimized IPV Detection Benchmark with Batch Processing
#' 
#' This script demonstrates significant performance improvements through:
#' - Batch processing of multiple narratives
#' - Parallel execution with multiple workers
#' - Token usage optimization
#' - Efficient error handling and retries

library(readxl)
library(here)
library(glue)
library(tictoc)
library(tidyr)
library(dplyr)
library(tibble)
library(jsonlite)

# Source functions
source(here::here("R", "build_prompt.R"))
source(here::here("R", "call_llm.R"))
source(here::here("R", "call_llm_batch.R"))  # New batch processing functions
source(here::here("R", "parse_llm_result.R"))
source(here::here("R", "db_utils.R"))
source(here::here("R", "store_llm_result.R"))

# =============================================================================
# CONFIGURATION
# =============================================================================

# Optimization settings
OPTIMIZATION_CONFIG <- list(
  use_batching = TRUE,           # Enable batch processing
  batch_size = 5,                # Narratives per batch
  use_parallel = FALSE,          # Enable parallel processing (requires future package)
  n_workers = 4,                 # Number of parallel workers
  show_savings = TRUE            # Display token/cost savings
)

MODELS <- c("openai/gpt-oss-120b")
API_URL <- Sys.getenv("LLM_API_URL", "http://localhost:1234/v1/chat/completions")
DATA_FILE <- here::here("data-raw", "suicide_IPV_manuallyflagged.xlsx")

# =============================================================================
# LOAD DATA
# =============================================================================

cat("=== OPTIMIZED IPV DETECTION BENCHMARK ===\n\n")
cat("Loading data from", basename(DATA_FILE), "\n")
data <- read_excel(DATA_FILE)

# Transform to long format
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
  mutate(M_flag_ind = as.logical(M_flag_ind),
         M_flag = as.logical(M_flag)) |> 
  mutate(row_num = row_number()) |> 
  relocate(row_num, .before = IncidentID) |>
  filter(!is.na(Narrative) & nchar(trimws(Narrative)) > 0)  # Remove empty narratives

cat("Found", nrow(data_long), "valid narratives\n")
cat("  IPV positive:", sum(data_long$M_flag_ind, na.rm = TRUE), "\n")
cat("  IPV negative:", sum(!data_long$M_flag_ind, na.rm = TRUE), "\n\n")

# =============================================================================
# PROMPTS
# =============================================================================

system_prompt <- r"(
ROLE: You identify intimate partner violence (IPV) evidence in death investigation narratives. 
We want to know if the death could be related to IPV, not necessarily caused by IPV.

SCOPE: Use ONLY the narrative text. Do not infer beyond stated facts. If evidence is insufficient, say so via low confidence.

INDICATOR VOCAB:
- behavioral/social: "domestic violence history","restraining order","stalking","jealousy/control","recent separation","sexual exploitation","threats between partners","custody dispute","financial control"
- physical/medical: "multiple-stage injuries","defensive wounds","strangulation marks","pattern injury","genital trauma","prior unexplained injuries","injury inconsistent with stated cause"
- contextual: "partner weapon","shared residence scene","witness conflict reports","note mentions partner","police DV report","prior DV arrest"

DETECTION POLICY (when to set detected=true):
A. Explicit abuse or assault by a current/former partner, OR
B. Legal/procedural evidence (e.g., restraining order, police DV report, prior DV arrest), OR
C. Credible threats/stalking/jealousy/control/separation/sexual exploitation tied to the partner, OR
D. 2 or more signals of non-legal indicators that plausibly link the partner to coercion/violence.

CONFIDENCE CALIBRATION:
- 0.90–1.00: direct DV evidence (A/B) or multiple strong C/D signals.
- 0.70–0.89: strong but indirect signals; likely IPV.
- 0.40–0.69: one moderate signal with weak support.
- 0.05–0.39: weak/ambiguous context only.
- 0.00: narrative negates IPV.

OUTPUT RULES:
Return ONE JSON object with keys: detected:boolean, confidence:number (0–1), indicators:array[string], rationale:string (≤200 chars).
)"

user_template <- r"(
Analyze the following death investigation narrative for intimate partner violence (IPV).

Narrative:
<<TEXT>>

Respond ONLY with a single valid JSON object:
{
  "detected": <true|false>,
  "confidence": <number between 0 and 1>,
  "indicators": ["<tokens from the indicator vocab>"],
  "rationale": "<≤200 chars, concise justification>"
}
)"

# =============================================================================
# CALCULATE POTENTIAL SAVINGS
# =============================================================================

if (OPTIMIZATION_CONFIG$show_savings) {
  cat("=== EFFICIENCY ANALYSIS ===\n")
  
  # Calculate token savings
  savings <- calculate_batch_savings(
    n_narratives = nrow(data_long),
    system_prompt_tokens = nchar(system_prompt) / 4,  # Rough estimate
    avg_narrative_tokens = mean(nchar(data_long$Narrative)) / 4,
    batch_size = OPTIMIZATION_CONFIG$batch_size,
    cost_per_million_tokens = 1  # Adjust based on your model
  )
  
  cat("\nToken Usage Comparison:\n")
  cat(sprintf("  Sequential: %s tokens\n", format(savings$sequential_tokens, big.mark = ",")))
  cat(sprintf("  Batched:    %s tokens\n", format(savings$batch_tokens, big.mark = ",")))
  cat(sprintf("  Savings:    %s tokens (%.1f%% reduction)\n", 
             format(savings$tokens_saved, big.mark = ","), 
             savings$reduction_percent))
  
  cat("\nCost Comparison (at $1/M tokens):\n")
  cat(sprintf("  Sequential: $%.4f\n", savings$sequential_cost))
  cat(sprintf("  Batched:    $%.4f\n", savings$batch_cost))
  cat(sprintf("  Savings:    $%.4f\n", savings$cost_saved))
  
  cat(sprintf("\nEfficiency multiplier: %.2fx\n\n", savings$efficiency_multiplier))
}

# =============================================================================
# RUN OPTIMIZED BENCHMARK
# =============================================================================

run_optimized_benchmark <- function(data_long, system_prompt, user_template, 
                                   model, api_url, optimization_config) {
  
  # Prepare narratives
  narratives <- data_long$Narrative
  user_prompts <- sapply(narratives, function(text) {
    glue::glue(user_template, TEXT = text, .open = "<<", .close = ">>")
  })
  
  # Create output filename
  safe_model_name <- gsub("[/:*?\"<>|\\s]", "_", model)
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  output_dir <- here::here("benchmark_results")
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  
  method_suffix <- ifelse(optimization_config$use_batching, 
                          paste0("_batch", optimization_config$batch_size), 
                          "_sequential")
  if (optimization_config$use_parallel) {
    method_suffix <- paste0(method_suffix, "_parallel", optimization_config$n_workers)
  }
  
  csv_file <- file.path(output_dir, paste0("benchmark_optimized_", safe_model_name, 
                                           method_suffix, "_", timestamp, ".csv"))
  json_file <- file.path(output_dir, paste0("benchmark_optimized_", safe_model_name,
                                            method_suffix, "_", timestamp, ".json"))
  
  cat("=== PROCESSING CONFIGURATION ===\n")
  cat(sprintf("Model: %s\n", model))
  cat(sprintf("Method: %s\n", ifelse(optimization_config$use_batching, "Batch", "Sequential")))
  if (optimization_config$use_batching) {
    cat(sprintf("Batch size: %d\n", optimization_config$batch_size))
  }
  if (optimization_config$use_parallel) {
    cat(sprintf("Parallel workers: %d\n", optimization_config$n_workers))
  }
  cat(sprintf("Total narratives: %d\n", length(narratives)))
  cat("\nOutput files:\n")
  cat(sprintf("  CSV: %s\n", basename(csv_file)))
  cat(sprintf("  JSON: %s\n", basename(json_file)))
  cat("\n")
  
  # Start processing
  cat("=== PROCESSING NARRATIVES ===\n")
  tic()
  
  if (optimization_config$use_batching) {
    if (optimization_config$use_parallel) {
      # Parallel batch processing
      cat("Using PARALLEL BATCH processing...\n")
      results <- call_llm_parallel(
        user_prompts,
        system_prompt,
        n_workers = optimization_config$n_workers,
        batch_size = optimization_config$batch_size,
        api_url = api_url,
        model = model,
        temperature = 0.5
      )
    } else {
      # Sequential batch processing
      cat("Using SEQUENTIAL BATCH processing...\n")
      results <- call_llm_batch(
        user_prompts,
        system_prompt,
        batch_size = optimization_config$batch_size,
        api_url = api_url,
        model = model,
        temperature = 0.5
      )
    }
  } else {
    # Traditional sequential processing (for comparison)
    cat("Using TRADITIONAL SEQUENTIAL processing...\n")
    results <- list()
    pb <- txtProgressBar(min = 0, max = length(user_prompts), style = 3)
    
    for (i in seq_along(user_prompts)) {
      response <- tryCatch({
        call_llm(
          user_prompts[i],
          system_prompt,
          api_url = api_url,
          model = model,
          temperature = 0.5
        )
      }, error = function(e) {
        list(error = TRUE, error_message = as.character(e))
      })
      
      if (!is.null(response$choices)) {
        content <- response$choices[[1]]$message$content
        results[[i]] <- jsonlite::fromJSON(content, simplifyVector = FALSE)
        results[[i]]$tokens_used <- response$usage$total_tokens
      } else {
        results[[i]] <- list(
          detected = NA,
          confidence = NA,
          error = response$error_message
        )
      }
      
      setTxtProgressBar(pb, i)
    }
    close(pb)
    cat("\n")
  }
  
  processing_time <- toc(quiet = TRUE)
  total_seconds <- as.numeric(processing_time$toc - processing_time$tic)
  
  # Compile results
  results_df <- tibble(
    row_num = data_long$row_num,
    incident_id = data_long$IncidentID,
    narrative_type = data_long$Type,
    narrative = data_long$Narrative,
    manual_flag_ind = data_long$M_flag_ind,
    manual_flag = data_long$M_flag,
    detected = sapply(results, function(x) x$detected %||% NA),
    confidence = sapply(results, function(x) x$confidence %||% NA),
    indicators = sapply(results, function(x) {
      if (!is.null(x$indicators) && length(x$indicators) > 0) {
        paste(x$indicators, collapse = "; ")
      } else ""
    }),
    rationale = sapply(results, function(x) x$rationale %||% ""),
    tokens_used = sapply(results, function(x) x$tokens_used %||% NA),
    batch_id = sapply(results, function(x) x$batch_id %||% NA),
    error = sapply(results, function(x) x$error %||% ""),
    model = model,
    processing_method = ifelse(optimization_config$use_batching, 
                              paste0("batch_", optimization_config$batch_size),
                              "sequential"),
    total_processing_seconds = total_seconds,
    processed_at = Sys.time()
  )
  
  # Save results
  write.csv(results_df, csv_file, row.names = FALSE)
  jsonlite::write_json(results_df, json_file, pretty = TRUE, auto_unbox = TRUE, na = "null")
  
  # Calculate metrics
  valid_results <- results_df %>% filter(!is.na(detected) & !is.na(manual_flag_ind))
  
  metrics <- list(
    total_narratives = nrow(results_df),
    successful = sum(!is.na(results_df$detected)),
    errors = sum(is.na(results_df$detected)),
    processing_time_seconds = total_seconds,
    narratives_per_second = nrow(results_df) / total_seconds,
    avg_tokens_per_narrative = mean(results_df$tokens_used, na.rm = TRUE)
  )
  
  if (nrow(valid_results) > 0) {
    metrics$accuracy <- mean(valid_results$detected == valid_results$manual_flag_ind)
    metrics$sensitivity <- mean(valid_results$detected[valid_results$manual_flag_ind == TRUE])
    metrics$specificity <- mean(!valid_results$detected[valid_results$manual_flag_ind == FALSE])
  }
  
  # Display results
  cat("\n=== PROCESSING COMPLETE ===\n")
  cat(sprintf("Total time: %.1f seconds\n", metrics$processing_time_seconds))
  cat(sprintf("Processing rate: %.2f narratives/second\n", metrics$narratives_per_second))
  cat(sprintf("Average tokens per narrative: %.0f\n", metrics$avg_tokens_per_narrative))
  
  if (!is.null(metrics$accuracy)) {
    cat("\n=== MODEL PERFORMANCE ===\n")
    cat(sprintf("Accuracy: %.2f%%\n", metrics$accuracy * 100))
    cat(sprintf("Sensitivity: %.2f%%\n", metrics$sensitivity * 100))
    cat(sprintf("Specificity: %.2f%%\n", metrics$specificity * 100))
  }
  
  cat("\n=== FILES SAVED ===\n")
  cat(sprintf("CSV: %s\n", csv_file))
  cat(sprintf("JSON: %s\n", json_file))
  
  return(list(
    results = results_df,
    metrics = metrics,
    files = list(csv = csv_file, json = json_file)
  ))
}

# =============================================================================
# EXECUTE BENCHMARK
# =============================================================================

benchmark_results <- run_optimized_benchmark(
  data_long = data_long,
  system_prompt = system_prompt,
  user_template = user_template,
  model = MODELS[1],
  api_url = API_URL,
  optimization_config = OPTIMIZATION_CONFIG
)

# =============================================================================
# COMPARISON (Optional: Run both methods)
# =============================================================================

if (FALSE) {  # Set to TRUE to run comparison
  cat("\n\n=== RUNNING COMPARISON ===\n")
  
  # Test subset for comparison
  test_subset <- data_long[1:20, ]
  
  # Sequential
  OPTIMIZATION_CONFIG$use_batching <- FALSE
  cat("\n--- Testing SEQUENTIAL processing ---\n")
  seq_results <- run_optimized_benchmark(
    test_subset, system_prompt, user_template,
    MODELS[1], API_URL, OPTIMIZATION_CONFIG
  )
  
  # Batched
  OPTIMIZATION_CONFIG$use_batching <- TRUE
  OPTIMIZATION_CONFIG$batch_size <- 5
  cat("\n--- Testing BATCH processing ---\n")
  batch_results <- run_optimized_benchmark(
    test_subset, system_prompt, user_template,
    MODELS[1], API_URL, OPTIMIZATION_CONFIG
  )
  
  # Compare
  cat("\n=== PERFORMANCE COMPARISON ===\n")
  cat(sprintf("Sequential: %.1f seconds (%.2f narratives/sec)\n",
             seq_results$metrics$processing_time_seconds,
             seq_results$metrics$narratives_per_second))
  cat(sprintf("Batched:    %.1f seconds (%.2f narratives/sec)\n",
             batch_results$metrics$processing_time_seconds,
             batch_results$metrics$narratives_per_second))
  cat(sprintf("Speed improvement: %.2fx faster\n",
             batch_results$metrics$narratives_per_second / 
             seq_results$metrics$narratives_per_second))
}

cat("\n✓ Optimized benchmark complete!\n")