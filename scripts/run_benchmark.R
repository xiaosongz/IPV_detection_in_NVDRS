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
OUTPUT_FILE <- paste0("benchmark_results_", format(Sys.(), "%Y%m%d_%H%M%S"), ".csv")

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


system_prompt <- '/think. ROLE: You identify intimate partner violence (IPV) evidence in death investigation narratives.

SCOPE: Use ONLY the narrative text. Do not infer beyond stated facts. If evidence is insufficient, say so via low confidence.

INDICATOR VOCAB (use EXACT tokens; all lowercase):
- behavioral/social: "domestic violence history","restraining order","stalking","jealousy/control","recent separation","threats between partners","custody dispute","financial control","women’s shelter"
- physical/medical: "multiple-stage injuries","defensive wounds","strangulation marks","pattern injury","genital trauma","prior unexplained injuries","injury inconsistent with stated cause"
- contextual: "partner’s weapon","shared residence scene","witness conflict reports","note mentions partner","police DV report","prior DV arrest"

DETECTION POLICY (when to set detected=true):
A. Explicit abuse or assault by a current/former partner, OR
B. Legal/procedural evidence (e.g., restraining order, police DV report, prior DV arrest), OR
C. Credible threats/stalking/jealousy/control/separation tied to the partner, OR
D. Corroborating non-legal indicators that plausibly link the partner to coercion/violence (e.g., recent separation + threats + witness reports).
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
- No extra keys, no prose, no code fences.'

user_template <- 'Analyze the following death investigation narrative for intimate partner violence (IPV).

Narrative:
<<TEXT>>

Respond ONLY with a single valid JSON object matching:
{
  "detected": <true|false>,
  "confidence": <number between 0 and 1>,
  "indicators": ["<tokens from the indicator vocab>"],
  "rationale": "<≤200 chars, concise justification using facts from the narrative>"
}
Do not include chain-of-thought, explanations, or extra text. If no indicators are supported by the narrative, use [] and set a low confidence per the calibration.'

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

# Initialize results storage
results <- list()
request <- list()
# # testing parameter
row_num = 18

request$type = data_long$Type[row_num]
request$narrative_text = data_long$Narrative[row_num]
request$m_flag_ind = data_long$M_flag_ind[row_num]
request$m_flag = data_long$M_flag[row_num]

request$system_prompt = system_prompt
request$incident_id = data_long$IncidentID[row_num]
request$user_prompt <- glue::glue(user_prompt, TEXT = request$narrative_text, .open = '<<', .close = '>>')
request$model = MODELS[1]

#  the llm call
tic()
# Call LLM
response <- tryCatch({
  call_llm(
    system_prompt = request$system_prompt,
    user_prompt = request$user_prompt,
    api_url = API_URL,
    model = request$model,
    temperature = 0.2
  )
}, error = function(e) {
  list(error = TRUE, error_message = as.character(e))
})
# save the r results
r_result <- toc(quiet = TRUE)
request$response__sec <- as.numeric(r_result$toc - r_result$tic)
response
# str(response)
result_tibble <- parse_llm_result(response, narrative_id = request$incident_id)

# Add request metadata to the result
result_tibble <- result_tibble |> 
  dplyr::mutate(
    incident_id = request$incident_id,
    narrative_type = request$type,
    manual_flag_ind = request$m_flag_ind,
    manual_flag = request$m_flag,
    response__sec = request$response__sec
  )

result_tibble
View(result_tibble)

result_tibble |> select(raw_response) |> pull() 
