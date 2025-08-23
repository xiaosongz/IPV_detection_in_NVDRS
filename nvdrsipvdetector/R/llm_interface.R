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
  # Validate configuration early if API fields are needed
  if (!is.null(config$api)) {
    validate_llm_config(config)
  }
  
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
  # Only base_url is truly required
  if (is.null(config$api$base_url)) {
    stop("Missing required configuration field: api.base_url. Please check inst/settings.yml")
  }
  
  # Set defaults for optional fields if missing
  if (is.null(config$api$timeout)) config$api$timeout <- 30
  if (is.null(config$api$max_retries)) config$api$max_retries <- 3
  if (is.null(config$api$temperature)) config$api$temperature <- 0.7
  if (is.null(config$api$max_tokens)) config$api$max_tokens <- 500
  if (is.null(config$api$model)) config$api$model <- "default"
  if (is.null(config$prompts$system)) {
    config$prompts <- list(system = "You are an AI assistant trained to detect intimate partner violence.")
  }
  
  invisible(config)
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
  # Input validation
  if (is.null(config)) {
    # Use default test prompt for backward compatibility
    config <- list(
      prompts = list(
        unified_template = "Analyze this {narrative_type} narrative for intimate partner violence indicators. Narrative: {narrative}"
      )
    )
  }
  
  if (is.null(config$prompts)) {
    stop("Prompts section not found in configuration. Please check inst/settings.yml has a 'prompts' section.")
  }
  
  # Clean narrative text
  narrative <- stringr::str_trim(narrative)
  
  # Get unified template
  template <- config$prompts$unified_template
  
  # Check for backward compatibility - if old templates exist but no unified
  if (is.null(template)) {
    # Try old style templates for backward compatibility
    if (type == "LE" && !is.null(config$prompts$le_template)) {
      template <- config$prompts$le_template
    } else if (type == "CME" && !is.null(config$prompts$cme_template)) {
      template <- config$prompts$cme_template
    } else {
      stop("No unified_template found in configuration. Please update inst/settings.yml")
    }
  } else {
    # Use unified template - replace narrative type placeholder
    narrative_type <- if (type == "LE") "law enforcement" else "medical examiner"
    template <- stringr::str_replace_all(template, "\\{narrative_type\\}", narrative_type)
  }
  
  # Validate narrative type
  if (!type %in% c("LE", "CME")) {
    stop(paste("Invalid narrative type:", type, ". Must be 'LE' or 'CME'"))
  }
  
  # Replace narrative placeholder
  stringr::str_replace_all(template, "\\{narrative\\}", narrative)
}