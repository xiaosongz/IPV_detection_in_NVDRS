#' LLM API Wrapper
#'
#' @description Functions for interacting with LLM API
#' @keywords internal
NULL

#' Send to LLM (Modernized with Functional Error Handling)
#'
#' @param prompt Prompt text
#' @param config Configuration list
#' @return Parsed LLM response
#' @export
send_to_llm <- function(prompt, config) {
  # Validate configuration early
  validate_llm_config(config)
  
  # Use purrr::safely for functional error handling
  safe_llm_call <- purrr::safely(perform_llm_request)
  
  # Build and send request
  result <- safe_llm_call(prompt, config)
  
  if (is.null(result$error)) {
    result$result
  } else {
    cli::cli_alert_warning(
      glue::glue("LLM API error: {result$error$message}")
    )
    create_error_response(result$error)
  }
}

#' Validate LLM Configuration (Helper)
#'
#' @param config Configuration list
validate_llm_config <- function(config) {
  required_fields <- list(
    "prompts.system" = config$prompts$system,
    "api.temperature" = config$api$temperature,
    "api.max_tokens" = config$api$max_tokens,
    "api.base_url" = config$api$base_url,
    "api.model" = config$api$model,
    "api.timeout" = config$api$timeout,
    "api.max_retries" = config$api$max_retries
  )
  
  missing <- names(required_fields)[purrr::map_lgl(required_fields, is.null)]
  
  if (length(missing) > 0) {
    stop(
      "Missing required configuration fields: ",
      paste(missing, collapse = ", "),
      ". Please check inst/settings.yml"
    )
  }
}

#' Perform LLM Request (Helper)
#'
#' @param prompt Prompt text
#' @param config Configuration list
#' @return Parsed response
perform_llm_request <- function(prompt, config) {
  # Build request using pipeline
  resp <- httr2::request(paste0(config$api$base_url, "/chat/completions")) %>%
    httr2::req_body_json(list(
      model = config$api$model,
      messages = list(
        list(role = "system", content = config$prompts$system),
        list(role = "user", content = prompt)
      ),
      temperature = config$api$temperature,
      max_tokens = config$api$max_tokens
    )) %>%
    httr2::req_timeout(config$api$timeout) %>%
    httr2::req_retry(max_tries = config$api$max_retries + 1) %>%
    httr2::req_perform()
  
  # Parse response
  body <- httr2::resp_body_json(resp)
  content <- body$choices[[1]]$message$content
  parsed <- jsonlite::parse_json(content)
  
  # Return structured response
  list(
    ipv_detected = as.logical(parsed$ipv_detected),
    confidence = as.numeric(parsed$confidence),
    indicators = unlist(parsed$indicators),
    rationale = parsed$rationale,
    success = TRUE
  )
}

#' Create Error Response (Helper)
#'
#' @param error Error object
#' @return Error response structure
create_error_response <- function(error) {
  list(
    ipv_detected = NA,
    confidence = NA,
    indicators = character(),
    rationale = as.character(error),
    success = FALSE
  )
}

#' Build Prompt (Modernized)
#'
#' @param narrative Narrative text
#' @param type "LE" or "CME"
#' @param config Required config object with prompt templates from settings.yml
#' @return Formatted prompt
#' @export
build_prompt <- function(narrative, type = "LE", config = NULL) {
  # Input validation using tidyverse style
  if (is.null(config)) {
    stop("Configuration required for build_prompt. Please pass the config object loaded from settings.yml")
  }
  
  if (is.null(config$prompts)) {
    stop("Prompts section not found in configuration. Please check inst/settings.yml has a 'prompts' section.")
  }
  
  # Clean narrative text
  narrative <- stringr::str_trim(narrative)
  
  # Get template using case_when logic
  template <- dplyr::case_when(
    type == "LE" & !is.null(config$prompts$le_template) ~ config$prompts$le_template,
    type == "CME" & !is.null(config$prompts$cme_template) ~ config$prompts$cme_template,
    type == "LE" ~ stop("LE template not found in configuration. Please add 'le_template' to the 'prompts' section in inst/settings.yml"),
    type == "CME" ~ stop("CME template not found in configuration. Please add 'cme_template' to the 'prompts' section in inst/settings.yml"),
    TRUE ~ stop(paste("Invalid narrative type:", type, ". Must be 'LE' or 'CME'"))
  )
  
  # Replace placeholder with actual narrative using stringr
  stringr::str_replace_all(template, "\\{narrative\\}", narrative)
}