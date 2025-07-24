library(readxl)
library(writexl)
library(tidyverse)
library(httr)
library(jsonlite)
library(ratelimitr)
library(glue)
library(fs)

# --- Configuration ---
default_url <- "http://192.168.10.21:11434"
api_url <- default_url  # Initialize with default URL

# Clean and validate URL
api_url <- sub("/+$", "", trimws(api_url))
if (!grepl("^https?://", api_url)) {
  api_url <- paste0("http://", api_url)
}

# Test connection and get available models
message(glue("\nTesting connection to Ollama server at: {api_url}"))
tryCatch({
  # Make the initial request
  resp <- GET(paste0(api_url, "/api/tags"), timeout(5))
  
  # Check HTTP status
  if (status_code(resp) != 200) {
    stop(glue("Server responded with HTTP status {status_code(resp)}"))
  }
  
  # Parse the response content
  content <- rawToChar(resp$content)
  message("Raw response from server:")
  print(content)
  
  # Try to parse the JSON response
  parsed <- tryCatch({
    fromJSON(content, simplifyVector = TRUE)
  }, error = function(e) {
    stop(glue("Failed to parse server response as JSON: {e$message}"))
  })
  
  # Extract model names - handle both list and data frame formats
  if (is.list(parsed) && !is.null(parsed$models)) {
    if (is.data.frame(parsed$models)) {
      model_names <- parsed$models$name
    } else if (is.list(parsed$models)) {
      model_names <- sapply(parsed$models, function(x) x$name)
    } else {
      stop("Unexpected format for models in response")
    }
    
    message("✓ Successfully connected to Ollama server")
    message("\nAvailable models:")
    for (model in model_names) {
      message(glue("  - {model}"))
    }
    
    # Set the model to use
    model_to_use <- "deepseek-r1:8b"
    if (!model_to_use %in% model_names) {
      stop(glue("Model '{model_to_use}' is not available. Please choose from the list above."))
    }
    message(glue("\nUsing model: {model_to_use}"))
  } else {
    stop("Invalid response format from server: models list not found")
  }
}, error = function(e) {
  stop(glue(
    "\n✗ Failed to connect to the Ollama server.\n\n",
    "  Error details: {trimws(e$message)}\n\n",
    "  Troubleshooting tips:\n",
    "  1. Ensure the Ollama application is running\n",
    "  2. Verify the URL is correct: '{api_url}'\n",
    "  3. Check if the server is responding to /api/tags endpoint\n",
    "  4. Try accessing the URL in your browser: {api_url}/api/tags"
  ))
})

# Ask user if this is a new run
#is_new_run <- readline(prompt = "Is this a new run? (y/n): ") == "y"
is_new_run <- TRUE
# Configuration
batch_size <- 10  # Set to 1 case per batch as requested
if (is_new_run) {
  cache_dir <- glue("cache/cache_{format(Sys.time(), '%Y%m%d_%H%M%S')}")
  dir_create(cache_dir)
  checkpoint_file <- path(cache_dir, "checkpoint.rds")
  # Initialize checkpoint
  checkpoint <- list(
    last_completed_batch = 0,
    total_batches = 0,
    narrative_type = NULL,
    start_time = Sys.time()
  )
  saveRDS(checkpoint, checkpoint_file)
} else {
  # Find the most recent cache directory
  cache_dirs <- dir_ls("cache", type = "directory", regexp = "cache_\\d{8}_\\d{6}$")
  if (length(cache_dirs) == 0) {
    stop("No existing cache directory found. Please start a new run.")
  }
  cache_dir <- max(cache_dirs)
  checkpoint_file <- path(cache_dir, "checkpoint.rds")
  if (!file_exists(checkpoint_file)) {
    stop("No checkpoint file found in the most recent cache directory.")
  }
  checkpoint <- readRDS(checkpoint_file)
  message(glue("Continuing from batch {checkpoint$last_completed_batch + 1} of {checkpoint$total_batches}"))
}

# Rate limiting: 3 requests per minute
rate_limited_request <- limit_rate(
  function(url, body) {
    message(glue("\nMaking API request to: {url}"))
    message("Request body:")
    print(body)
    
    resp <- POST(
      url,
      body = body,
      content_type_json(),
      timeout(30)
    )
    
    message(glue("Response status: {status_code(resp)}"))
    if (status_code(resp) != 200) {
      stop(glue("Server responded with HTTP status {status_code(resp)}"))
    }
    
    content <- rawToChar(resp$content)
    message("Response content:")
    print(content)
    
    parsed <- fromJSON(content)
    if (is.null(parsed$response)) {
      stop("Invalid response format: 'response' field not found")
    }
    parsed
  },
  rate(n = 3, period = 60)
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
  "  \"rationale\": \"A brief explanation of why you made each yes/no/unclear choice, citing evidence from the text.\",",
  "  \"key_facts_summary\": \"A 1-2 sentence objective summary of the key events and circumstances described.\",",
  "  \"family_friend_mentioned\": \"yes\", \"no\", or \"unclear\",",
  "  \"intimate_partner_mentioned\": \"yes\", \"no\", or \"unclear\",",
  "  \"violence_mentioned\": \"yes\", \"no\", or \"unclear\",",
  "  \"substance_abuse_mentioned\": \"yes\", \"no\", or \"unclear\",",
  "  \"ipv_between_intimate_partners\": \"yes\", \"no\", or \"unclear\"",
  "}",
  "",
  "Respond with ONLY the JSON object. Do not include any other text, markdown formatting, or commentary.",
  "The response should be a single, valid JSON object that can be parsed directly."
)

## ---------- API request and caching function ----------------------------
make_api_request <- function(valid_narratives, model = model_to_use, batch_id) {
  cache_key <- digest::digest(paste(valid_narratives, collapse = "|"))
  cache_file <- path(cache_dir, glue("batch_{batch_id}_{cache_key}.rds"))
  
  if (file_exists(cache_file)) {
    message(glue("Using cached results for batch {batch_id}"))
    return(readRDS(cache_file))
  }
  
  # Process each narrative individually
  results <- list()
  for (i in seq_along(valid_narratives)) {
    narrative <- valid_narratives[i]
    message(glue("\nProcessing narrative {i} of {length(valid_narratives)}"))
    
    prompt_file <- path(cache_dir, glue("batch_{batch_id}_narrative_{i}_prompt.txt"))
    user_prompt <- paste(
      "Analyze the following narrative and return a JSON object:",
      sprintf("Narrative: %s", narrative)
    )
    writeLines(user_prompt, prompt_file)
    
    # Construct the full prompt for Ollama
    full_prompt <- paste(
      batch_system_prompt,
      "\n\n",
      user_prompt
    )
    
    # Make the API request with rate limiting
    tryCatch({
      request_body <- list(
        model = model,
        prompt = full_prompt,
        stream = FALSE,
        temperature = 0,
        format = "json"  # Explicitly request JSON format
      )
      
      message(glue("\nMaking request for narrative {i}"))
      message("Using model: ", model)
      
      resp <- rate_limited_request(
        paste0(api_url, "/api/generate"),
        toJSON(request_body, auto_unbox = TRUE)
      )
      
      response_text <- resp$response
      message("Raw response:")
      print(response_text)
      
      # Clean up the response text
      response_text <- gsub("```json\\s*|```\\s*$", "", response_text)
      response_text <- trimws(response_text)
      
      response_file <- path(cache_dir, glue("batch_{batch_id}_narrative_{i}_response.txt"))
      writeLines(response_text, response_file)
      
      # Try to parse the response
      message("Attempting to parse response as JSON...")
      parsed <- fromJSON(response_text, flatten = TRUE)
      message("Successfully parsed JSON response")
      
      # Add sequence number as metadata, not in the response
      results[[i]] <- c(parsed, list(sequence = i))
      
    }, error = function(e) {
      warning(glue("API request failed for narrative {i}: {e$message}"))
      results[[i]] <- list(
        rationale = "API request failed",
        key_facts_summary = "api_error",
        family_friend_mentioned = "api_error",
        intimate_partner_mentioned = "api_error",
        violence_mentioned = "api_error",
        substance_abuse_mentioned = "api_error",
        ipv_between_intimate_partners = "api_error",
        sequence = i  # Add sequence as metadata
      )
    })
    
    # Add a small delay between requests to avoid overwhelming the server
    Sys.sleep(1)
  }
  
  # Combine all results into a data frame
  combined_results <- bind_rows(results)
  saveRDS(combined_results, cache_file)
  return(combined_results)
}

## ---------- batched ollama call (CORRECTED FOR NA VALUES) ------------------
ollama_chat_batch <- function(narratives, model = model_to_use, batch_id) {
  # 1. Identify which narratives are valid and which are NA or empty.
  is_invalid <- is.na(narratives) | narratives == ""
  valid_narratives <- narratives[!is_invalid]
  
  message(glue("\nProcessing batch {batch_id}"))
  message(glue("Total narratives: {length(narratives)}"))
  message(glue("Valid narratives: {length(valid_narratives)}"))
  
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
  api_result <- make_api_request(valid_narratives, model, batch_id)
  
  if (is.null(api_result)) {
    message(glue("API request failed for batch {batch_id}"))
    return(tibble(
      sequence = seq_along(valid_narratives),
      rationale = "API request failed",
      key_facts_summary = "api_error",
      family_friend_mentioned = "api_error",
      intimate_partner_mentioned = "api_error",
      violence_mentioned = "api_error",
      substance_abuse_mentioned = "api_error",
      ipv_between_intimate_partners = "api_error"
    ))
  }
  
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
    message(glue("Successfully processed {nrow(api_result)} narratives in batch {batch_id}"))
    full_result[!is_invalid, ] <- api_result
  } else {
    warning(glue("API response length mismatch in batch {batch_id}: got {nrow(api_result)}, expected {sum(!is_invalid)}"))
    full_result[!is_invalid, "rationale"] <- "API response length mismatch"
  }
  
  return(full_result)
}

## ---------- process narrative column in batches ----------------------------
process_batched <- function(df, col, narrative_type) {
  results <- list()
  chunks <- split(df, (seq_len(nrow(df)) - 1) %/% batch_size)
  
  # Update checkpoint with total batches if this is a new run
  if (is_new_run) {
    checkpoint$total_batches <- length(chunks)
    checkpoint$narrative_type <- narrative_type
    saveRDS(checkpoint, checkpoint_file)
  }
  
  # Determine start batch based on checkpoint
  start_batch <- if (is_new_run) 1 else checkpoint$last_completed_batch + 1
  
  for (i in start_batch:length(chunks)) {
    start_time <- Sys.time()
    cat(sprintf("\rProcessing batch %d of %d (%s)", i, length(chunks), narrative_type))
    
    chunk <- chunks[[i]]
    batch_id <- glue("{narrative_type}_{i}")
    
    # Check if this batch was previously completed
    batch_cache_file <- path(cache_dir, glue("batch_{batch_id}_*.rds"))
    if (!is_new_run && length(dir_ls(batch_cache_file)) > 0) {
      message(glue("\nSkipping already completed batch {batch_id}"))
      next
    }
    
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
    out$batch_number <- i
    
    results[[i]] <- out
    
    # Update checkpoint
    checkpoint$last_completed_batch <- i
    saveRDS(checkpoint, checkpoint_file)
    
    # Log timing
    end_time <- Sys.time()
    duration <- as.numeric(difftime(end_time, start_time, units = "secs"))
    message(glue("\nBatch {batch_id} completed in {round(duration, 2)} seconds"))
  }

  cat("\n")
  # Combine results, filtering out NULL entries
  bind_rows(Filter(Negate(is.null), results))
}

## ---------- main -----------------------------------------------------------
# Create output directory if it doesn't exist
dir_create("output")

df <- read_excel("data/sui_all_flagged.xlsx") |>
  mutate(row_id = row_number()) |>
  select(row_id, IncidentID, NarrativeCME, NarrativeLE)

# Process narratives
if (is_new_run || checkpoint$narrative_type == "CME") {
  results_cme <- process_batched(df, "NarrativeCME", "CME")
} else {
  # Load existing CME results
  cme_files <- dir_ls(cache_dir, regexp = "batch_CME_.*\\.rds$")
  results_cme <- bind_rows(lapply(cme_files, readRDS))
}

if (is_new_run || checkpoint$narrative_type == "LE") {
  results_le <- process_batched(df, "NarrativeLE", "LE")
} else {
  # Load existing LE results
  le_files <- dir_ls(cache_dir, regexp = "batch_LE_.*\\.rds$")
  results_le <- bind_rows(lapply(le_files, readRDS))
}

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