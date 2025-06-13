library(readxl)
library(writexl)
library(tidyverse)
library(httr2)
library(jsonlite)
library(dotenv)
library(ratelimitr)
library(glue)
library(fs)

load_dot_env()
key <- Sys.getenv("OPENAI_API_KEY")
stopifnot(nzchar(key))

# Configuration
batch_size <- 20  # <<< YOU CAN CHANGE THIS LATER
cache_dir <- glue("cache_{format(Sys.time(), '%Y%m%d_%H%M%S')}")
dir_create(cache_dir)

# Rate limiting: 3 requests per minute
rate_limited_request <- limit_rate(
  function(req) req_perform(req),
  rate(n = 5000, period = 60)
)

## ---------- system prompt --------------------------------------------------
batch_system_prompt <- paste(
  "You are a forensic reviewer trained to classify fatality review narratives.",
  "IMPORTANT: For each narrative below, return a JSON object with these 6 fields, please remember you have to review every narrative and respond to all of them. If there are multiple related incidents in one narrative, please respond if you find evidence in any of then:",
  "{",
  "  \"sequence\": <sequence number>,",
  "  \"family_friend_mentioned\": \"yes\" or \"no\",",
  "  \"intimate_partner_mentioned\": \"yes\" or \"no\",",
  "  \"violence_mentioned\": \"yes\" or \"no\",",
  "  \"substance_abuse_mentioned\": \"yes\" or \"no\",",
  "  \"ipv_between_intimate_partners\": \"yes\" or \"no\"",
  "}",
  "Return a **JSON array**, with one object per narrative, in the same order.",
  "Only use \"unclear\" if the information is missing or ambiguous.",
  "No markdown, no text—just the JSON array."
)

## ---------- batched openai call --------------------------------------------
openai_chat_batch <- function(narratives, model = "gpt-4o-mini", batch_id) {
  # Create cache key
  cache_key <- digest::digest(paste(narratives, collapse = "|"))
  cache_file <- path(cache_dir, glue("batch_{batch_id}_{cache_key}.rds"))
  
  # Check cache
  if (file_exists(cache_file)) {
    message(glue("Using cached results for batch {batch_id}"))
    return(readRDS(cache_file))
  }
  
  # Save prompt for inspection
  prompt_file <- path(cache_dir, glue("batch_{batch_id}_prompt.txt"))
  user_prompt <- paste(
    "Analyze the following narratives and return a JSON array of results:",
    paste0(sprintf("Narrative %03d: %s", seq_along(narratives), narratives), collapse = "\n\n")
  )
  writeLines(user_prompt, prompt_file)
  
  # Make API request
  resp <- request("https://api.openai.com/v1/chat/completions") |>
    req_headers(
      "Authorization" = paste("Bearer", key),
      "Content-Type"  = "application/json"
    ) |>
    req_body_json(list(
      model = model,
      temperature = 0,
      messages = list(
        list(role = "system", content = batch_system_prompt),
        list(role = "user", content = user_prompt)
      )
    )) |>
    rate_limited_request() |>
    resp_body_json()

  # Parse response
  response_text <- resp$choices[[1]]$message$content
  response_text <- gsub("```json\\s*|```\\s*$", "", response_text)
  
  # Save response for inspection
  response_file <- path(cache_dir, glue("batch_{batch_id}_response.txt"))
  writeLines(response_text, response_file)
  
  result <- tryCatch({
    parsed <- fromJSON(response_text)
    if (!is.data.frame(parsed)) parsed <- bind_rows(parsed)
    parsed
  }, error = function(e) {
    warning(glue("Failed to parse response for batch {batch_id}: {e$message}"))
    tibble(
      family_friend_mentioned = rep("unclear", length(narratives)),
      intimate_partner_mentioned = rep("unclear", length(narratives)),
      violence_mentioned = rep("unclear", length(narratives)),
      substance_abuse_mentioned = rep("unclear", length(narratives)),
      ipv_between_intimate_partners = rep("unclear", length(narratives))
    )
  })
  
  # Cache the result
  saveRDS(result, cache_file)
  result
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
    
    out <- openai_chat_batch(chunk[[col]], batch_id = batch_id)
    
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

# Combine and reshape
results <- bind_rows(results_cme, results_le) |>
  pivot_wider(
    names_from = narrative_type,
    values_from = c(family_friend_mentioned, intimate_partner_mentioned, 
                    violence_mentioned, substance_abuse_mentioned, 
                    ipv_between_intimate_partners, sequence),
    names_prefix = ""
  ) |>
  left_join(df, by = c("IncidentID", "row_id"))

# Save results with timestamp
output_file <- glue("output/ipv_detection_results_batch_{format(Sys.time(), '%Y%m%d_%H%M%S')}.csv")
write.csv(results, output_file, row.names = FALSE)
