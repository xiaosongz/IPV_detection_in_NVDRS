library(readxl)
library(writexl)
library(tidyverse)
library(httr2)
library(jsonlite)
library(dotenv)
library(ratelimitr)

load_dot_env()                      # pulls OPENAI_API_KEY from .env
key <- Sys.getenv("OPENAI_API_KEY")
stopifnot(nzchar(key))

## ---------- helpers --------------------------------------------------
system_prompt <- paste(
  "You are a forensic reviewer trained to classify fatality review narratives.",
  "IMPORTANT: Return a SINGLE JSON object (not an array) with these 5 fields:",
  "{",
  "  \"family_friend_mentioned\": \"yes\" or \"no\"",
  "  \"intimate_partner_mentioned\": \"yes\" or \"no\"",
  "  \"violence_mentioned\": \"yes\" or \"no\"",
  "  \"substance_abuse_mentioned\": \"yes\" or \"no\"",
  "  \"ipv_between_intimate_partners\": \"yes\" or \"no\"",
  "}",
  "Respond based on *any* relevant detail you can infer from the narrative. Do NOT default to 'unclear'.",
  "'unclear' should ONLY be used when no relevant clue is present, or when the subject of a phrase cannot be reasonably determined.",
  "CRITICAL: Return ONLY a single JSON object—NOT an array, NOT wrapped in anything, just the object itself.",
  "Example of correct response:",
  "{",
  "  \"family_friend_mentioned\": \"yes\",",
  "  \"intimate_partner_mentioned\": \"yes\",",
  "  \"violence_mentioned\": \"yes\",",
  "  \"substance_abuse_mentioned\": \"no\",",
  "  \"ipv_between_intimate_partners\": \"yes\"",
  "}"
)

# Create cache directory if it doesn't exist
dir.create("output/cache", showWarnings = FALSE)

# Function to process a single narrative with caching
openai_chat <- function(narrative, row_id, narrative_type, model = "gpt-4o-mini") {
  # Create cache filename
  cache_file <- sprintf("output/cache/%s_%d_%s.json", 
                       narrative_type, row_id, format(Sys.time(), "%Y%m%d_%H%M%S"))
  
  # Create user prompt
  user_prompt <- paste(
    "Analyze this narrative and return a SINGLE JSON object (not an array):",
    narrative,
    "Remember: Return ONLY a single JSON object, not an array.",
    sep = "\n"
  )
  
  # Make API request
  resp <- request("https://api.openai.com/v1/chat/completions") |>
    req_headers(
      "Authorization" = paste("Bearer", key),
      "Content-Type"  = "application/json"
    ) |>
    req_body_json(list(
      model       = model,
      temperature = 0,
      messages    = list(
        list(role = "system", content = system_prompt),
        list(role = "user", content = user_prompt)
      )
    )) |>
    req_perform() |>
    resp_body_json()
  
  # Get raw response
  response_text <- resp$choices[[1]]$message$content
  
  # Save raw response to cache
  cache_data <- list(
    row_id = row_id,
    narrative_type = narrative_type,
    narrative = narrative,
    system_prompt = system_prompt,
    user_prompt = user_prompt,
    raw_response = response_text,
    timestamp = Sys.time()
  )
  write_json(cache_data, cache_file, pretty = TRUE)
  
  # Try to parse and validate
  tryCatch({
    # Remove any markdown code block markers
    response_text <- gsub("```json\\s*|```\\s*$", "", response_text)
    
    # Parse JSON
    result <- fromJSON(response_text)
    
    # Validate structure
    valid_keys <- c("family_friend_mentioned", "intimate_partner_mentioned", 
                   "violence_mentioned", "substance_abuse_mentioned", 
                   "ipv_between_intimate_partners")
    valid_values <- c("yes", "no", "unclear")
    
    # Check for missing keys
    missing_keys <- setdiff(valid_keys, names(result))
    if (length(missing_keys) > 0) {
      for (key in missing_keys) {
        result[[key]] <- "unclear"
      }
    }
    
    # Check for extra keys
    extra_keys <- setdiff(names(result), valid_keys)
    if (length(extra_keys) > 0) {
      result <- result[valid_keys]
    }
    
    # Validate values
    invalid_values <- sapply(result, function(v) !v %in% valid_values)
    if (any(invalid_values)) {
      result[invalid_values] <- "unclear"
    }
    
    # Convert to data frame and return
    as.data.frame(result)
  }, error = function(e) {
    # Log error to cache
    cache_data$error <- e$message
    write_json(cache_data, cache_file, pretty = TRUE)
    
    data.frame(
      family_friend_mentioned = "unclear",
      intimate_partner_mentioned = "unclear",
      violence_mentioned = "unclear",
      substance_abuse_mentioned = "unclear",
      ipv_between_intimate_partners = "unclear"
    )
  })
}

## Rate limit of 2 requests per second
rl_chat <- limit_rate(openai_chat, rate(n=2, period=1))

## ---------- run on file ---------------------------------------------
df <- read_excel("data/sui_all_flagged.xlsx") |>
  mutate(row_id = row_number()) |>          # keep original order
  select(row_id,IncidentID, NarrativeCME, NarrativeLE) |>
  head(10)

# Process CME narratives
results_cme <- data.frame()
for (i in 1:nrow(df)) {
  cat(sprintf("\rProcessing CME narrative %d of %d", i, nrow(df)))
  result <- openai_chat(df$NarrativeCME[i], df$row_id[i], "CME")
  result$row_id <- df$row_id[i]
  result$IncidentID <- df$IncidentID[i]
  result$narrative_type <- "CME"
  results_cme <- rbind(results_cme, result)
  Sys.sleep(0.02)  # Rate limit: ~50 requests per second (5,000 RPM)
}
cat("\n")

# Process LE narratives
results_le <- data.frame()
for (i in 1:nrow(df)) {
  cat(sprintf("\rProcessing LE narrative %d of %d", i, nrow(df)))
  result <- openai_chat(df$NarrativeLE[i], df$row_id[i], "LE")
  result$row_id <- df$row_id[i]
  result$IncidentID <- df$IncidentID[i]
  result$narrative_type <- "LE"
  results_le <- rbind(results_le, result)
  Sys.sleep(0.02)  # Rate limit: ~50 requests per second (5,000 RPM)
}
cat("\n")

# Combine results
results <- rbind(results_cme, results_le)

# Reorder columns to put incident_id first
results <- results |>
  pivot_wider(
    names_from = narrative_type,
    values_from = c(family_friend_mentioned, intimate_partner_mentioned, 
                   violence_mentioned, substance_abuse_mentioned, 
                   ipv_between_intimate_partners),
    names_prefix = ""
  ) |>
  left_join(df, by = c("IncidentID", "row_id"))

# Save results
write.csv(results, "output/ipv_detection_results.csv", row.names = FALSE)
