#!/usr/bin/env Rscript

#' Simple, Direct IPV Detection Benchmark
#' 
#' This script actually runs the benchmark. No abstractions, no complexity.
#' Just loads data, tests models, calculates metrics, saves results.

library(readxl)
library(here)
library(glue)
library(tictoc)
library(tidyr)
library(dplyr)
library(tibble)
library(jsonlite)

# Source existing functions (the ones that actually do work)
source(here::here("R", "build_prompt.R"))
source(here::here("R", "call_llm.R"))
source(here::here("R", "parse_llm_result.R"))
source(here::here("R", "db_utils.R"))
source(here::here("R", "store_llm_result.R"))

# =============================================================================
# CONFIGURATION (change these as needed)
# =============================================================================

MODELS <- c("openai/gpt-oss-120b", "qwen/qwen3-30b-a3b-2507","qwen3-30b-a3b-thinking-2507-mlx")
API_URL <- Sys.getenv("LLM_API_URL", 
                      "http://localhost:1234/v1/chat/completions")
DATA_FILE <- here::here("data-raw", "suicide_IPV_manuallyflagged.xlsx")
# OUTPUT_FILE <- paste0("benchmark_results_", format(Sys.(), "%Y%m%d_%H%M%S"), ".csv")

# =============================================================================
# LOAD DATA
# =============================================================================

cat("Loading data from", basename(DATA_FILE), "\n")
data <- read_excel(DATA_FILE)

# Get narratives and manual flags
narratives <- list(
  cme = data$NarrativeCME,
  le = data$NarrativeLE
)

manual_flags <- list(
  cme = as.logical(data$ipv_manualCME),
  le = as.logical(data$ipv_manualLE)
)

incident_ids <- data$IncidentID

# Count valid narratives
n_cme <- sum(!is.na(narratives$cme) & nchar(trimws(narratives$cme)) > 0)
n_le <- sum(!is.na(narratives$le) & nchar(trimws(narratives$le)) > 0)

cat("Found", nrow(data), "records\n")
cat("  CME narratives:", n_cme, "\n")
cat("  LE narratives:", n_le, "\n")
cat("  IPV positive (CME):", sum(manual_flags$cme, na.rm = TRUE), "\n")
cat("  IPV positive (LE):", sum(manual_flags$le, na.rm = TRUE), "\n\n")


system_prompt <- r"(
/think.
ROLE: Identify if the deceased was the VICTIM of intimate partner violence (IPV), instead of perpetrator of IPV.

SCOPE: 
- IPV from: current/former partner, boyfriend/girlfriend, spouse, ex, father of victim's children
- NOT from: victim's parents or family members
- Use ONLY narrative facts
- Women's shelter = strong IPV evidence
- "domestic issues" = IPV (unless deceased was the perpetrator of IPV)

INDICATORS (use exact tokens):
  - behavioral: "domestic violence history", "domestic issues", "women's shelter", "restraining order", "stalking", "jealousy/control", "recent separation", "threats", "custody dispute", "financial control", "sexual exploitation"
 - physical: "multiple-stage injuries", "defensive wounds", "strangulation marks", "pattern injury", "genital trauma", "prior injuries"
 - contextual: "partner's weapon", "shared residence", "witness reports", "note mentions partner", "police DV report", "prior DV arrest"

DETECTION (detected=true when):
  A. Any abuse/assault BY partner against deceased OR
  B. Women's shelter stay OR legal evidence (restraining order, DV report/arrest) OR
  C. "Domestic issues" where deceased wasn't perpetrator OR
  D. 2 or more other indicators suggesting deceased was IPV victim

CONFIDENCE:
  - HIGH (0.70-1.00): Women's shelter, legal evidence, explicit abuse, or 2+ strong indicators
  - MODERATE (0.30-0.69): Single indicator or ambiguous evidence
  - LOW (0.00-0.29): No indicators or deceased was perpetrator

OUTPUT: Single JSON with detected:boolean, confidence:number, indicators:array (0-5 items from vocab), rationale:string (≤200 chars)
)"

user_template <- r"(
Analyze if the deceased was VICTIM of IPV from intimate partner (NOT from parents/family, NOT as perpetrator).

Narrative:
<<TEXT>>

Return ONLY this JSON:
{
  "detected": true/false,
  "confidence": 0.00-1.00,
  "indicators": ["exact tokens from vocab list"],
  "rationale": "≤200 char fact-based explanation"
}

Remember: women's shelter or "domestic issues" (when deceased wasn't perpetrator) = detected=true, confidence≥0.70
)"

# =============================================================================
# RUN BENCHMARK
# =============================================================================

# Transform data to long format

data_long <- data %>%
  pivot_longer(
    cols = c(NarrativeCME, NarrativeLE),
    names_to = "Type",
    values_to = "Narrative"
  ) %>%
  mutate(
    # Clean up Type column to just "cme" or "le"
    Type = tolower(gsub("Narrative", "", Type)),
    # Individual manual flag for current narrative type
    M_flag_ind = case_when(
      Type == "cme" ~ ipv_manualCME,
      Type == "le" ~ ipv_manualLE
    ),
    # Overall manual flag for the case (considering both CME and LE)
    M_flag = ipv_manual
  ) %>%
  select(IncidentID, Type, Narrative, M_flag_ind, M_flag) |> 
  # make the flags boolean, it was a numeric 0/1
  mutate(M_flag_ind = as.logical(M_flag_ind),
         M_flag = as.logical(M_flag)) |> 
  # add row number
  mutate(row_num = row_number()) |> 
  relocate(row_num, .before = IncidentID)

data_long |> filter(M_flag_ind == TRUE)

# 
# # # testing parameter
# 
# row_num = 18
# 
# # Initialize results storage
# results <- list()
# request <- list()
# 
# # now we will run the benchmark for each row
# request$type = data_long$Type[row_num]
# request$narrative_text = data_long$Narrative[row_num] 
# request$m_flag_ind = data_long$M_flag_ind[row_num]
# request$m_flag = data_long$M_flag[row_num]
# 
# request$system_prompt = system_prompt
# request$incident_id = data_long$IncidentID[row_num]
# request$narrative_text 
# request$user_prompt <- glue::glue(user_template, TEXT = request$narrative_text, .open = '<<', .close = '>>')
# request$user_prompt
# request$model = MODELS[1]
# request$temperature = 0.5
# #  the llm call
# tic()
# # Call LLM
# response <- tryCatch({
#   call_llm(
#     system_prompt = request$system_prompt,
#     user_prompt = request$user_prompt,
#     api_url = API_URL,
#     model = request$model,
#     temperature = request$temperature
#   )
# }, error = function(e) {
#   list(error = TRUE, error_message = as.character(e))
# })
# # save the r results
# r_result <- toc(quiet = TRUE)
# request$response_sec <- as.numeric(r_result$toc - r_result$tic)
# response
# # str(response)
# result_tibble <- parse_llm_result(response, narrative_id = request$incident_id)
# 
# # Add request metadata to the result
# result_tibble <- result_tibble |> 
#   dplyr::mutate(
#     incident_id = request$incident_id,
#     narrative_type = request$type,
#     manual_flag_ind = request$m_flag_ind,
#     manual_flag = request$m_flag,
#     response_sec = request$response_sec,
#     user_prompt = request$user_prompt,
#     system_prompt = request$system_prompt,
#     temperature = request$temperature
# 
#   )
# 
# result_tibble 

# =============================================================================
# RUN BATCH PROCESSING FOR ALL NARRATIVES
# =============================================================================

# Function to process all narratives with incremental saving
run_all_narratives <- function(data_long, system_prompt, user_template, 
                               model, api_url, temperature = 0.5) {
  
  # Initialize cumulative results tibble
  all_results <- tibble::tibble()
  n_rows <- nrow(data_long)
  processed_count <- 0
  
  # Create output filenames with timestamp in benchmark_results folder
  # Replace all special characters in model name
  safe_model_name <- gsub("[/:*?\"<>|\\s]", "_", model)
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  
  # Ensure benchmark_results directory exists
  output_dir <- here::here("benchmark_results")
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  
  csv_file <- file.path(output_dir, paste0("benchmark_results_", safe_model_name, "_", timestamp, ".csv"))
  json_file <- file.path(output_dir, paste0("benchmark_results_", safe_model_name, "_", timestamp, ".json"))
  
  cat("Results will be saved to:\n")
  cat("  CSV:", csv_file, "\n")
  cat("  JSON:", json_file, "\n")
  cat("Processing", n_rows, "narratives with model:", model, "\n\n")
  
  for (row_num in seq_len(n_rows)) {
    
    # Progress indicator
    if (row_num %% 10 == 0) {
      cat("  Processing row", row_num, "of", n_rows, "\n")
    }
    
    # Skip if narrative is NA or empty
    narrative_text <- data_long$Narrative[row_num]
    if (is.na(narrative_text) || trimws(narrative_text) == "") {
      cat("  Skipping row", row_num, "- empty narrative\n")
      next
    }
    
    # Build request
    request <- list()
    request$type <- data_long$Type[row_num]
    request$narrative_text <- narrative_text
    request$m_flag_ind <- data_long$M_flag_ind[row_num]
    request$m_flag <- data_long$M_flag[row_num]
    request$system_prompt <- system_prompt
    request$incident_id <- data_long$IncidentID[row_num]
    request$user_prompt <- glue::glue(
      user_template, 
      TEXT = request$narrative_text, 
      .open = "<<", 
      .close = ">>"
    )
    request$model <- model
    request$temperature <- temperature
    
    # Call LLM with timing
    tic()
    response <- tryCatch({
      call_llm(
        system_prompt = request$system_prompt,
        user_prompt = request$user_prompt,
        api_url = api_url,
        model = request$model,
        temperature = request$temperature
      )
    }, error = function(e) {
      list(error = TRUE, error_message = as.character(e))
    })
    r_result <- toc(quiet = TRUE)
    request$response_sec <- as.numeric(r_result$toc - r_result$tic)
    
    # Parse the response
    result_tibble <- parse_llm_result(
      response, 
      narrative_id = request$incident_id
    )
    
    # Add request metadata to the result
    result_tibble <- result_tibble |>
      dplyr::mutate(
        row_num = row_num,
        incident_id = request$incident_id,
        narrative_type = request$type,
        manual_flag_ind = request$m_flag_ind,
        manual_flag = request$m_flag,
        response_sec = request$response_sec,
        user_prompt = request$user_prompt,
        system_prompt = request$system_prompt,
        temperature = request$temperature,
        processed_at = Sys.time()
      )
    
    # Append to cumulative results
    all_results <- dplyr::bind_rows(all_results, result_tibble)
    processed_count <- processed_count + 1
    
    # Save as JSON (preserves all data types including lists)
    jsonlite::write_json(
      all_results, 
      json_file, 
      pretty = TRUE,
      auto_unbox = TRUE,
      na = "null"
    )
    
    # Prepare for CSV (flatten list columns)
    csv_results <- all_results
    
    # Convert indicators list to string for CSV
    if ("indicators" %in% names(csv_results)) {
      csv_results$indicators <- sapply(csv_results$indicators, function(x) {
        if (is.null(x) || length(x) == 0) {
          return("")
        } else {
          return(paste(x, collapse = "; "))
        }
      })
    }
    
    # Convert any other list columns to strings
    list_cols <- sapply(csv_results, is.list)
    if (any(list_cols)) {
      for (col in names(csv_results)[list_cols]) {
        if (col != "indicators") {  # Already handled
          csv_results[[col]] <- as.character(csv_results[[col]])
        }
      }
    }
    
    # Save as CSV (overwrite with complete results each time)
    write.csv(csv_results, csv_file, row.names = FALSE)
    
    # Progress update
    if (processed_count %% 5 == 0) {
      cat(sprintf("    [%d/%d processed, %d skipped]\n", 
                  processed_count, row_num, row_num - processed_count))
    }
  }
  
  # Final summary
  cat("\n", paste(rep("-", 60), collapse = ""), "\n")
  cat("Completed processing:\n")
  cat("  Total rows:", n_rows, "\n")
  cat("  Processed:", processed_count, "\n")
  cat("  Skipped:", n_rows - processed_count, "\n")
  cat("  Results saved to:\n")
  cat("    CSV:", csv_file, "\n")
  cat("    JSON:", json_file, "\n")
  
  return(all_results)
}

# =============================================================================
# RUN THE BATCH PROCESSING
# =============================================================================

# Run for first model
all_results_1 <- run_all_narratives(
  data_long = data_long,
  system_prompt = system_prompt,
  user_template = user_template,
  model = MODELS[1],
  api_url = API_URL,
  temperature = 0.1
)

# Run for second model
all_results_2 <- run_all_narratives(
  data_long = data_long,
  system_prompt = system_prompt,
  user_template = user_template,
  model = MODELS[1],
  api_url = API_URL,
  temperature = 0.2
)

# Run for third model
all_results_3 <- run_all_narratives(
  data_long = data_long,
  system_prompt = system_prompt,
  user_template = user_template,
  model = MODELS[1],
  api_url = API_URL,
  temperature = 0.0
)

all_results = all_results_3
# Calculate metrics
if (nrow(all_results) > 0) {
  valid_results <- all_results %>%
    filter(!is.na(detected) & !is.na(manual_flag_ind))
  
  if (nrow(valid_results) > 0) {
    accuracy <- mean(valid_results$detected == valid_results$manual_flag_ind)
    sensitivity <- mean(valid_results$detected[valid_results$manual_flag_ind == TRUE])
    specificity <- mean(!valid_results$detected[valid_results$manual_flag_ind == FALSE])
    
    cat("\nModel Performance:\n")
    cat("  Processed:", nrow(all_results), "narratives\n")
    cat("  Valid results:", nrow(valid_results), "\n")
    cat("  Accuracy:", sprintf("%.2f%%", accuracy * 100), "\n")
    cat("  Sensitivity:", sprintf("%.2f%%", sensitivity * 100), "\n")
    cat("  Specificity:", sprintf("%.2f%%", specificity * 100), "\n")
  }
}

# Run for second model
all_results <- run_all_narratives(
  data_long = data_long,
  system_prompt = system_prompt,
  user_template = user_template,
  model = MODELS[1],
  api_url = API_URL,
  temperature = 0.2
)

# Calculate metrics
if (nrow(all_results) > 0) {
  valid_results <- all_results %>%
    filter(!is.na(detected) & !is.na(manual_flag_ind))
  
  if (nrow(valid_results) > 0) {
    accuracy <- mean(valid_results$detected == valid_results$manual_flag_ind)
    sensitivity <- mean(valid_results$detected[valid_results$manual_flag_ind == TRUE])
    specificity <- mean(!valid_results$detected[valid_results$manual_flag_ind == FALSE])
    
    cat("\nModel Performance:\n")
    cat("  Processed:", nrow(all_results), "narratives\n")
    cat("  Valid results:", nrow(valid_results), "\n")
    cat("  Accuracy:", sprintf("%.2f%%", accuracy * 100), "\n")
    cat("  Sensitivity:", sprintf("%.2f%%", sensitivity * 100), "\n")
    cat("  Specificity:", sprintf("%.2f%%", specificity * 100), "\n")
  }
}

# Results are already saved incrementally by the function
# The final combined results are in the all_results variable
cat("\nBenchmark complete! Results saved incrementally during processing.\n")

