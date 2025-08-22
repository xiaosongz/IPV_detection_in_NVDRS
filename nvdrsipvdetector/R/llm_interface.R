#' LLM API Wrapper
#'
#' @description Functions for interacting with LLM API
#' @keywords internal
NULL

#' Send to LLM
#'
#' @param prompt Prompt text
#' @param config Configuration list
#' @return Parsed LLM response
#' @export
send_to_llm <- function(prompt, config) {
  # Build request
  req <- httr2::request(paste0(config$api$base_url, "/chat/completions"))
  req <- httr2::req_body_json(req, list(
    model = config$api$model,
    messages = list(
      list(role = "system", content = "You are an expert at analyzing text for intimate partner violence. Respond only with valid JSON."),
      list(role = "user", content = prompt)
    ),
    temperature = 0.1,
    max_tokens = 1000
  ))
  
  # Add timeout and retry
  req <- httr2::req_timeout(req, config$api$timeout)
  req <- httr2::req_retry(req, max_tries = config$api$max_retries + 1)
  
  # Perform request with error handling
  tryCatch({
    resp <- httr2::req_perform(req)
    body <- httr2::resp_body_json(resp)
    
    # Extract and parse response
    content <- body$choices[[1]]$message$content
    parsed <- jsonlite::parse_json(content)
    
    return(list(
      ipv_detected = as.logical(parsed$ipv_detected),
      confidence = as.numeric(parsed$confidence),
      indicators = unlist(parsed$indicators),
      rationale = parsed$rationale,
      success = TRUE
    ))
  }, error = function(e) {
    cli::cli_alert_warning(glue::glue("LLM API error: {e$message}"))
    return(list(
      ipv_detected = NA,
      confidence = NA,
      indicators = character(),
      rationale = as.character(e),
      success = FALSE
    ))
  })
}

#' Build Prompt
#'
#' @param narrative Narrative text
#' @param type "LE" or "CME"
#' @return Formatted prompt
#' @export
build_prompt <- function(narrative, type = "LE") {
  narrative <- trimws(narrative)
  
  if (type == "LE") {
    prompt <- glue::glue("
Analyze this law enforcement narrative for intimate partner violence indicators.

Look for: domestic violence, current/former partners, restraining orders, 
jealousy, control, separation, threats between partners.

Narrative: '{narrative}'

Respond with JSON:
{{
  'ipv_detected': boolean,
  'confidence': 0-1,
  'indicators': [...],
  'rationale': '...'
}}
")
  } else {
    prompt <- glue::glue("
Analyze this medical examiner narrative for intimate partner violence indicators.

Look for: multiple injuries in various stages, defensive wounds, 
strangulation, pattern injuries, history of prior injuries.

Narrative: '{narrative}'

Respond with JSON:
{{
  'ipv_detected': boolean,
  'confidence': 0-1,
  'indicators': [...],
  'rationale': '...'
}}
")
  }
  
  return(prompt)
}