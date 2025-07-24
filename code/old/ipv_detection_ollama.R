library(readxl)
library(writexl)
library(tidyverse)
library(httr2)
library(jsonlite)
library(ratelimitr)
library(glue)
library(fs)

# Configuration
batch_size <- 10  # <<< YOU CAN CHANGE THIS LATER
cache_dir <- glue("cache/cache_{format(Sys.time(), '%Y%m%d_%H%M%S')}")
dir_create(cache_dir)

# Rate limiting: 3 requests per minute
rate_limited_request <- limit_rate(
  function(req) req_perform(req),
  rate(n = 5000, period = 60)
)

## ---------- system prompt (ADVANCED, with Rationale) -----------------------
batch_system_prompt <- paste(
  "You are a meticulous forensic pathologist and data analyst.",
  "Your task is to review fatality review narratives and extract specific, objective information.",
  "Your classifications will be audited against evaluations by human experts, so every answer must be based *only* on explicit evidence within the provided text.",
  "First, think step-by-step to form a rationale for your classifications, then provide the final JSON object.",
  "",
  "For each narrative provided, you MUST return a single JSON object with the following fields in EXACTLY this order:",
  "{",
  "  \"sequence\": <integer>,",
  "  \"rationale\": \"A brief explanation of why you made each yes/no/unclear choice, citing evidence from the text.\",",
  "  \"key_facts_summary\": \"A 1-2 sentence objective summary of the key events and circumstances described.\",",
  "  \"family_friend_mentioned\": \"yes\", \"no\", or \"unclear\",",
  "  \"intimate_partner_mentioned\": \"yes\", \"no\", or \"unclear\",",
  "  \"violence_mentioned\": \"yes\", \"no\", or \"unclear\",",
  "  \"substance_abuse_mentioned\": \"yes\", \"no\", or \"unclear\",",
  "  \"ipv_between_intimate_partners\": \"yes\", \"no\", or \"unclear\"",
  "}",
  "",
  "Respond with a single, valid JSON array containing one object for each narrative.",
  "Do not include markdown formatting (like ```json), commentary, or any other text outside of the JSON array."
)

## ---------- API request and caching function ----------------------------
make_api_request <- function(valid_narratives, model, batch_id) {
  cache_key <- digest::digest(paste(valid_narratives, collapse = "|"))
  cache_file <- path(cache_dir, glue("batch_{batch_id}_{cache_key}.rds"))
  
  if (file_exists(cache_file)) {
    message(glue("Using cached results for batch {batch_id}"))
    return(readRDS(cache_file))
  }
  
  prompt_file <- path(cache_dir, glue("batch_{batch_id}_prompt.txt"))
  user_prompt <- paste(
    "Analyze the following narratives and return a JSON array of results:",
    paste0(sprintf("Narrative %03d: %s", seq_along(valid_narratives), valid_narratives), collapse = "\n\n")
  )
  writeLines(user_prompt, prompt_file)
  
  # Construct the full prompt for Ollama
  full_prompt <- paste(
    batch_system_prompt,
    "\n\n",
    user_prompt
  )
  
  resp <- request("http://localhost:11434/api/generate") |>
    req_headers("Content-Type" = "application/json") |>
    req_body_json(list(
      model = model,
      prompt = full_prompt,
      stream = FALSE,
      temperature = 0
    )) |>
    rate_limited_request() |>
    resp_body_json()
  
  response_text <- resp$response
  response_text <- gsub("```json\\s*|```\\s*$", "", response_text)
  
  response_file <- path(cache_dir, glue("batch_{batch_id}_response.txt"))
  writeLines(response_text, response_file)
  
  parsed <- fromJSON(response_text, flatten = TRUE)
  if (!is.data.frame(parsed)) parsed <- bind_rows(parsed)
  
  saveRDS(parsed, cache_file)
  return(parsed)
}

## ---------- batched ollama call (CORRECTED FOR NA VALUES) ------------------
ollama_chat_batch <- function(narratives, model = "mistral", batch_id) {
  # 1. Identify which narratives are valid and which are NA or empty.
  is_invalid <- is.na(narratives) | narratives == ""
  valid_narratives <- narratives[!is_invalid]
  
  # 2. If the entire batch is invalid, skip the API call entirely.
  if (length(valid_narratives) == 0) {
    message(glue("\nSkipping empty batch {batch_id}"))
    return(tibble(
      sequence = seq_along(narratives),
      rationale = "Narrative was NA or empty.",
      key_facts_summary = "skipped_na",
      family_friend_mentioned = "skipped_na",
      intimate_partner_mentioned = "skipped_na",
      violence_mentioned = "skipped_na",
      substance_abuse_mentioned = "skipped_na",
      ipv_between_intimate_partners = "skipped_na"
    ))
  }
  
  # 3. Make API request or use cached results
  api_result <- tryCatch({
    make_api_request(valid_narratives, model, batch_id)
  }, error = function(e) {
    warning(glue("Request or parsing failed for batch {batch_id}: {e$message}"))
    tibble(
      sequence = seq_along(valid_narratives),
      rationale = "Narrative was NA or empty.",
      key_facts_summary = "skipped_na",
      family_friend_mentioned = "api_or_parse_error",
      intimate_partner_mentioned = "api_or_parse_error",
      violence_mentioned = "api_or_parse_error",
      substance_abuse_mentioned = "api_or_parse_error",
      ipv_between_intimate_partners = "api_or_parse_error"
    )
  })
  
  # 4. Create a full result template for the entire original batch.
  full_result <- tibble(
    sequence = seq_along(narratives),
    rationale = "Narrative was NA or empty.",
    key_facts_summary = "skipped_na",
    family_friend_mentioned = "skipped_na",
    intimate_partner_mentioned = "skipped_na",
    violence_mentioned = "skipped_na",
    substance_abuse_mentioned = "skipped_na",
    ipv_between_intimate_partners = "skipped_na"
  )
  
  # 5. Place the results from the API call into the correct rows of the template.
  if (nrow(api_result) == sum(!is_invalid)) {
    full_result[!is_invalid, ] <- api_result
  } else {
    warning(glue("API response length mismatch even after filtering NAs in batch {batch_id}"))
    full_result[!is_invalid, "rationale"] <- "API response length mismatch"
  }
  
  return(full_result)
}

## ---------- process narrative column in batches ----------------------------
process_batched <- function(df, col, narrative_type) {
  results <- list()
  chunks <- split(df, (seq_len(nrow(df)) - 1) %/% batch_size)
  
  for (i in seq_along(chunks)) {
    start_time <- Sys.time()
    cat(sprintf("\rProcessing batch %d of %d (%s)", i, length(chunks), narrative_type))
    
    chunk <- chunks[[i]]
    batch_id <- glue("{narrative_type}_{i}")
    
    out <- ollama_chat_batch(chunk[[col]], batch_id = batch_id)
    
    # Ensure we have the correct number of rows
    if (nrow(out) != nrow(chunk)) {
      warning(glue("Row count mismatch in batch {batch_id}: got {nrow(out)}, expected {nrow(chunk)}"))
      # Adjust the output to match chunk size
      out <- out[1:nrow(chunk),]
    }
    
    # Add metadata columns
    out$row_id <- chunk$row_id
    out$IncidentID <- chunk$IncidentID
    out$narrative_type <- narrative_type
    out$batch_number <- i  # Add batch number
    
    results[[i]] <- out
    
    # Log timing
    end_time <- Sys.time()
    duration <- as.numeric(difftime(end_time, start_time, units = "secs"))
    message(glue("\nBatch {batch_id} completed in {round(duration, 2)} seconds"))
  }

  cat("\n")
  bind_rows(results)
}

## ---------- main -----------------------------------------------------------
df <- read_excel("data/sui_all_flagged.xlsx") |>
  mutate(row_id = row_number()) |>
  select(row_id, IncidentID, NarrativeCME, NarrativeLE)

# Process narratives
results_cme <- process_batched(df, "NarrativeCME", "CME")
results_le  <- process_batched(df, "NarrativeLE",  "LE")

# Combine and reshape with explicit column ordering
results <- bind_rows(results_cme, results_le) |>
  pivot_wider(
    names_from = narrative_type,
    values_from = c(sequence, rationale, key_facts_summary,
                   family_friend_mentioned, intimate_partner_mentioned, 
                   violence_mentioned, substance_abuse_mentioned, 
                   ipv_between_intimate_partners),
    names_prefix = ""
  ) |>
  left_join(df, by = c("IncidentID", "row_id")) |>
  select(
    # Metadata columns first
    row_id, IncidentID,
    # CME results in specified order
    sequence_CME, rationale_CME, key_facts_summary_CME,
    family_friend_mentioned_CME, intimate_partner_mentioned_CME,
    violence_mentioned_CME, substance_abuse_mentioned_CME,
    ipv_between_intimate_partners_CME,
    # LE results in specified order
    sequence_LE, rationale_LE, key_facts_summary_LE,
    family_friend_mentioned_LE, intimate_partner_mentioned_LE,
    violence_mentioned_LE, substance_abuse_mentioned_LE,
    ipv_between_intimate_partners_LE,
    # Original narratives
    NarrativeCME, NarrativeLE
  )

# Save results with timestamp
output_file <- glue("output/ipv_detection_results_batch_{format(Sys.time(), '%Y%m%d_%H%M%S')}.csv")
write.csv(results, output_file, row.names = FALSE) 