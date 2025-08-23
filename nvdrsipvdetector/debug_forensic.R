#!/usr/bin/env Rscript

# DEBUG SCRIPT - See what's actually happening with the API

library(nvdrsipvdetector)
library(httr2)
library(jsonlite)

cat("=== FORENSIC API DEBUG ===\n\n")

# Load config
config <- load_config()
config$processing$use_forensic_analysis <- TRUE

# Simple test narrative
narrative <- "The victim was shot by her ex-boyfriend after she obtained a restraining order. He had previously strangled her and threatened to kill her if she left him."

# Build the forensic prompt
cat("1. Building forensic prompt...\n")

# Check if forensic prompt file exists
forensic_path <- system.file("forensic_prompt.yml", package = "nvdrsipvdetector")
if (forensic_path == "") {
  cat("✗ forensic_prompt.yml not found in package\n")
  cat("Looking in inst/...\n")
  if (file.exists("inst/forensic_prompt.yml")) {
    cat("✓ Found in inst/forensic_prompt.yml\n")
    forensic_config <- yaml::yaml.load_file("inst/forensic_prompt.yml")
  } else {
    stop("Cannot find forensic_prompt.yml")
  }
} else {
  forensic_config <- yaml::yaml.load_file(forensic_path)
}

# Build prompt manually to see what it looks like
template <- forensic_config$forensic_template
prompt <- stringr::str_replace_all(template, "\\{narrative_type\\}", "Law enforcement")
prompt <- stringr::str_replace_all(prompt, "\\{narrative\\}", narrative)

cat("\n2. PROMPT BEING SENT (first 500 chars):\n")
cat(substr(prompt, 1, 500), "...\n\n")

# Send to API directly
cat("3. Sending to API...\n")
base_url <- Sys.getenv("LM_STUDIO_URL", "http://192.168.10.22:1234/v1")

request_body <- list(
  model = config$api$model,
  messages = list(
    list(
      role = "system",
      content = forensic_config$system_prompt
    ),
    list(
      role = "user", 
      content = prompt
    )
  ),
  temperature = 0.1,
  max_tokens = 4000
)

cat("Model:", config$api$model, "\n")
cat("API URL:", base_url, "\n\n")

response <- tryCatch({
  resp <- httr2::request(paste0(base_url, "/chat/completions")) %>%
    httr2::req_body_json(request_body) %>%
    httr2::req_timeout(60) %>%
    httr2::req_perform()
  
  httr2::resp_body_json(resp)
}, error = function(e) {
  cat("✗ API Error:", e$message, "\n")
  NULL
})

if (!is.null(response)) {
  cat("4. RAW RESPONSE RECEIVED\n")
  
  # Get the actual text response
  response_text <- response$choices[[1]]$message$content
  
  cat("Response length:", nchar(response_text), "characters\n")
  cat("\n5. RESPONSE CONTENT (first 1000 chars):\n")
  cat(substr(response_text, 1, 1000), "...\n\n")
  
  # Try to extract JSON
  cat("6. Attempting JSON extraction...\n")
  
  # Method 1: Look for JSON block
  json_match <- stringr::str_extract(response_text, "\\{[\\s\\S]*\\}")
  
  if (!is.na(json_match)) {
    cat("✓ Found JSON block\n")
    cat("JSON length:", nchar(json_match), "characters\n\n")
    
    # Try to parse it
    tryCatch({
      parsed <- jsonlite::parse_json(json_match)
      cat("✓ JSON parsed successfully!\n")
      
      # Check for required fields
      required <- c("death_classification", "directionality", "suicide_analysis")
      present <- required %in% names(parsed)
      
      cat("\nRequired fields present:\n")
      for (i in seq_along(required)) {
        cat("  -", required[i], ":", ifelse(present[i], "✓", "✗"), "\n")
      }
      
      if (!is.null(parsed$directionality)) {
        cat("\nDirectionality Result:\n")
        cat("  Primary Direction:", parsed$directionality$primary_direction, "\n")
        cat("  Confidence:", parsed$directionality$confidence, "\n")
      }
      
      if (!is.null(parsed$suicide_analysis)) {
        cat("\nSuicide Analysis:\n")
        cat("  Intent:", parsed$suicide_analysis$intent, "\n")
        cat("  Method:", parsed$suicide_analysis$method, "\n")
      }
      
    }, error = function(e) {
      cat("✗ JSON parse error:", e$message, "\n")
      cat("\nTrying to show what went wrong...\n")
      cat("First 200 chars of extracted JSON:\n")
      cat(substr(json_match, 1, 200), "\n")
    })
  } else {
    cat("✗ No JSON block found in response\n")
    cat("Response might be in wrong format\n")
  }
} else {
  cat("✗ No response received from API\n")
}

cat("\n=== END DEBUG ===\n")