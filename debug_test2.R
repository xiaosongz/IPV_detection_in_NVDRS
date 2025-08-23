#!/usr/bin/env Rscript

# Debug test script - direct API call
library(httr2)
library(jsonlite)
library(cli)

# Configuration
base_url <- "http://192.168.10.22:1234/v1"
model <- "openai/gpt-oss-120b"

# Simple prompt
prompt <- "Analyze this narrative for intimate partner violence indicators: 
'The victim had been in an abusive relationship with her boyfriend who had told her to kill herself.'

Respond with JSON:
{
  'ipv_detected': true or false,
  'confidence': 0.0 to 1.0,
  'indicators': ['list', 'of', 'indicators'],
  'rationale': 'explanation'
}"

cli::cli_alert_info("Sending request to LLM...")

# Make request
resp <- tryCatch({
  request(paste0(base_url, "/chat/completions")) %>%
    req_body_json(list(
      model = model,
      messages = list(
        list(role = "system", content = "You are an AI assistant trained to detect intimate partner violence."),
        list(role = "user", content = prompt)
      ),
      temperature = 0.1,
      max_tokens = 500
    )) %>%
    req_timeout(30) %>%
    req_perform()
}, error = function(e) {
  cli::cli_alert_danger("Request error: {e$message}")
  NULL
})

if (!is.null(resp)) {
  cli::cli_alert_success("Response received")
  
  # Parse response
  body <- resp_body_json(resp)
  content <- body$choices[[1]]$message$content
  
  cli::cli_alert_info("Raw response:")
  cat(content, "\n")
  
  # Try to extract JSON
  json_match <- stringr::str_extract(content, "\\{[\\s\\S]*\\}")
  if (!is.na(json_match)) {
    cli::cli_alert_info("Extracted JSON:")
    cat(json_match, "\n")
    
    parsed <- tryCatch({
      parse_json(json_match)
    }, error = function(e) {
      cli::cli_alert_danger("JSON parse error: {e$message}")
      NULL
    })
    
    if (!is.null(parsed)) {
      cli::cli_alert_success("Parsed successfully:")
      cli::cli_alert_info("IPV Detected: {parsed$ipv_detected}")
      cli::cli_alert_info("Confidence: {parsed$confidence}")
    }
  }
}