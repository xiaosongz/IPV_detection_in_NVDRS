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
  # Get system prompt from config, with fallback
  system_prompt <- if (!is.null(config$prompts$system)) {
    config$prompts$system
  } else {
    "You are an expert at analyzing text for intimate partner violence. Respond only with valid JSON."
  }
  
  # Get temperature and max_tokens from config, with defaults
  temperature <- if (!is.null(config$api$temperature)) config$api$temperature else 0.1
  max_tokens <- if (!is.null(config$api$max_tokens)) config$api$max_tokens else 1000
  
  # Build request
  req <- httr2::request(paste0(config$api$base_url, "/chat/completions"))
  req <- httr2::req_body_json(req, list(
    model = config$api$model,
    messages = list(
      list(role = "system", content = system_prompt),
      list(role = "user", content = prompt)
    ),
    temperature = temperature,
    max_tokens = max_tokens
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
#' @param config Optional config with prompt templates
#' @return Formatted prompt
#' @export
build_prompt <- function(narrative, type = "LE", config = NULL) {
  narrative <- trimws(narrative)
  
  # If config provided with templates, use them
  if (!is.null(config) && !is.null(config$prompts)) {
    template <- if (type == "LE" && !is.null(config$prompts$le_template)) {
      config$prompts$le_template
    } else if (type == "CME" && !is.null(config$prompts$cme_template)) {
      config$prompts$cme_template
    } else {
      NULL
    }
    
    if (!is.null(template)) {
      # Replace {narrative} placeholder with actual narrative
      # Use fixed = FALSE for proper pattern matching
      prompt <- gsub("\\{narrative\\}", narrative, template)
      return(prompt)
    }
  }
  
  # Fallback to default prompts if no config
  if (type == "LE") {
    prompt <- glue::glue("
Analyze this law enforcement narrative for IPV indicators.
Look for: domestic violence, partners, restraining orders, threats.
Narrative: '{narrative}'
Respond with JSON: {{'ipv_detected': bool, 'confidence': 0-1, 
'indicators': [...], 'rationale': '...'}}
")
  } else {
    prompt <- glue::glue("
Analyze this medical examiner narrative for IPV indicators.
Look for: injuries, defensive wounds, strangulation, pattern injuries.
Narrative: '{narrative}'
Respond with JSON: {{'ipv_detected': bool, 'confidence': 0-1,
'indicators': [...], 'rationale': '...'}}
")
  }
  
  return(prompt)
}