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
  # Require system prompt from config
  if (is.null(config$prompts) || is.null(config$prompts$system)) {
    stop("System prompt not found in configuration. Please check inst/settings.yml has a 'prompts:system' section.")
  }
  system_prompt <- config$prompts$system
  
  # Require temperature and max_tokens from config
  if (is.null(config$api$temperature)) {
    stop("Temperature not found in configuration. Please add 'temperature' to the 'api' section in inst/settings.yml")
  }
  if (is.null(config$api$max_tokens)) {
    stop("Max tokens not found in configuration. Please add 'max_tokens' to the 'api' section in inst/settings.yml")
  }
  temperature <- config$api$temperature
  max_tokens <- config$api$max_tokens
  
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
#' @param config Required config object with prompt templates from settings.yml
#' @return Formatted prompt
#' @export
build_prompt <- function(narrative, type = "LE", config = NULL) {
  narrative <- trimws(narrative)
  
  # Require config with templates
  if (is.null(config)) {
    stop("Configuration required for build_prompt. Please pass the config object loaded from settings.yml")
  }
  
  if (is.null(config$prompts)) {
    stop("Prompts section not found in configuration. Please check inst/settings.yml has a 'prompts' section.")
  }
  
  # Get the appropriate template
  if (type == "LE") {
    if (is.null(config$prompts$le_template)) {
      stop("LE template not found in configuration. Please add 'le_template' to the 'prompts' section in inst/settings.yml")
    }
    template <- config$prompts$le_template
  } else if (type == "CME") {
    if (is.null(config$prompts$cme_template)) {
      stop("CME template not found in configuration. Please add 'cme_template' to the 'prompts' section in inst/settings.yml")
    }
    template <- config$prompts$cme_template
  } else {
    stop(paste("Invalid narrative type:", type, ". Must be 'LE' or 'CME'"))
  }
  
  # Replace {narrative} placeholder with actual narrative
  prompt <- gsub("\\{narrative\\}", narrative, template)
  
  return(prompt)
}