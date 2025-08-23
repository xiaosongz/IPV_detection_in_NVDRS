#' LLM API Wrapper
#'
#' @description Functions for interacting with LLM API
#' @name llm_interface
#' @keywords internal
NULL

#' Send to LLM (Modernized with Functional Error Handling)
#'
#' @param prompt Prompt text
#' @param config Configuration list
#' @param forensic_mode Use forensic analysis mode
#' @return Parsed LLM response
#' @export
send_to_llm <- function(prompt, config, forensic_mode = FALSE) {
  # Validate configuration early if API fields are needed
  if (!is.null(config$api)) {
    validate_llm_config(config)
  }
  
  # Use purrr::safely for functional error handling
  safe_llm_call <- purrr::safely(
    function(p, c, fm) perform_llm_request(p, c, forensic_mode = fm)
  )
  
  # Build and send request
  result <- safe_llm_call(prompt, config, forensic_mode)
  
  if (is.null(result$error)) {
    result$result
  } else {
    cli::cli_alert_warning(
      glue::glue("LLM API error: {result$error$message}")
    )
    if (forensic_mode) {
      create_forensic_error_response(result$error)
    } else {
      create_error_response(result$error)
    }
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
#' @param forensic_mode Use forensic response parsing
#' @return Parsed response
perform_llm_request <- function(prompt, config, forensic_mode = FALSE) {
  # Adjust max_tokens for forensic analysis
  max_tokens <- if (forensic_mode) {
    config$processing$max_response_tokens %||% 4000
  } else {
    config$api$max_tokens
  }
  
  # Build request using pipeline
  resp <- httr2::request(paste0(config$api$base_url, "/chat/completions")) %>%
    httr2::req_body_json(list(
      model = config$api$model,
      messages = list(
        list(role = "system", content = config$prompts$system),
        list(role = "user", content = prompt)
      ),
      temperature = config$api$temperature,
      max_tokens = max_tokens
    )) %>%
    httr2::req_timeout(config$api$timeout) %>%
    httr2::req_retry(max_tries = config$api$max_retries + 1) %>%
    httr2::req_perform()
  
  # Parse response
  body <- httr2::resp_body_json(resp)
  content <- body$choices[[1]]$message$content
  
  # Clean JSON content (remove any markdown formatting)
  # Use [\\s\\S]* to match across multiple lines
  content <- stringr::str_extract(content, "\\{[\\s\\S]*\\}")
  if (is.na(content)) {
    stop("No valid JSON found in LLM response")
  }
  
  parsed <- jsonlite::parse_json(content)
  
  # Return response based on mode
  if (forensic_mode) {
    parse_forensic_response(parsed)
  } else {
    parse_basic_response(parsed)
  }
}

#' Parse Basic Response
#'
#' @param parsed Parsed JSON from LLM
#' @return Basic response structure
parse_basic_response <- function(parsed) {
  list(
    ipv_detected = as.logical(parsed$ipv_detected),
    confidence = as.numeric(parsed$confidence),
    indicators = unlist(parsed$indicators),
    rationale = parsed$rationale,
    success = TRUE
  )
}

#' Parse Forensic Response
#'
#' @description
#' Parses complex forensic JSON response into structured format
#' compatible with IPVForensicResult data structure.
#'
#' @param parsed Parsed JSON from LLM
#' @return Forensic response structure
parse_forensic_response <- function(parsed) {
  # Validate required top-level fields
  required_fields <- c("death_classification", "directionality", "suicide_analysis",
                      "evidence_matrix", "temporal_patterns", "quality_metrics")
  
  missing_fields <- setdiff(required_fields, names(parsed))
  if (length(missing_fields) > 0) {
    cli::cli_alert_warning(
      paste("Missing forensic fields:", paste(missing_fields, collapse = ", "))
    )
  }
  
  # Safe extraction with defaults
  safe_extract <- function(obj, field, default = NULL) {
    if (is.null(obj) || is.null(obj[[field]])) default else obj[[field]]
  }
  
  # Parse each section - match actual JSON structure from forensic prompt
  forensic_result <- list(
    # Death classification
    death_classification = list(
      type = safe_extract(parsed$death_classification, "type", "undetermined"),
      mechanism = safe_extract(parsed$death_classification, "mechanism", "undetermined"),
      confidence = as.numeric(safe_extract(parsed$death_classification, "confidence", 0))
    ),
    
    # Directionality assessment  
    directionality = list(
      primary_direction = safe_extract(parsed$directionality, "primary_direction", "undetermined"),
      confidence = as.numeric(safe_extract(parsed$directionality, "confidence", 0)),
      perpetrator_indicators = parsed$directionality$perpetrator_indicators,
      victim_indicators = parsed$directionality$victim_indicators,
      bidirectional_score = as.numeric(safe_extract(parsed$directionality, "bidirectional_score", 0))
    ),
    
    # Suicide analysis
    suicide_analysis = list(
      intent = safe_extract(parsed$suicide_analysis, "intent", "undetermined"),
      method = safe_extract(parsed$suicide_analysis, "method", "not_applicable"),
      precipitating_factors = safe_extract(parsed$suicide_analysis, "precipitating_factors", list()),
      behavioral_precursors = safe_extract(parsed$suicide_analysis, "behavioral_precursors", list())
    ),
    
    # Evidence matrix - match actual JSON structure
    evidence_matrix = safe_extract(parsed, "evidence_matrix", list(
      physical = list(items = list(), weight = 0.9),
      behavioral = list(items = list(), weight = 0.7),
      contextual = list(items = list(), weight = 0.5),
      circumstantial = list(items = list(), weight = 0.3)
    )),
    
    # Temporal patterns
    temporal_patterns = list(
      pattern_type = safe_extract(parsed$temporal_patterns, "pattern_type", "undetermined"),
      escalation_indicators = safe_extract(parsed$temporal_patterns, "escalation_indicators", list()),
      timeline_events = safe_extract(parsed$temporal_patterns, "timeline_events", list()),
      critical_period = safe_extract(parsed$temporal_patterns, "critical_period", NA)
    ),
    
    # Quality metrics
    quality_metrics = list(
      data_completeness = as.numeric(safe_extract(parsed$quality_metrics, "data_completeness", 0)),
      analysis_confidence = as.numeric(safe_extract(parsed$quality_metrics, "analysis_confidence", 0)),
      missing_information = safe_extract(parsed$quality_metrics, "missing_information", list()),
      alternative_hypotheses = safe_extract(parsed$quality_metrics, "alternative_hypotheses", list())
    ),
    
    success = TRUE,
    forensic_mode = TRUE
  )
  
  forensic_result
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

#' Create Forensic Error Response
#'
#' @param error Error object
#' @return Forensic error response structure
create_forensic_error_response <- function(error) {
  list(
    death_classification = list(
      primary = "error",
      confidence = 0,
      supporting_evidence = character(),
      rationale = as.character(error)
    ),
    directionality = list(
      primary_direction = "undetermined",
      perpetrator_indicators = character(),
      victim_indicators = character(), 
      bidirectional_score = 0,
      confidence = 0
    ),
    suicide_analysis = list(
      intent_classification = "undetermined",
      weapon_vs_escape = "undetermined",
      precipitating_factors = character(),
      confidence = 0
    ),
    evidence_matrix = list(
      physical_evidence = list(),
      behavioral_evidence = list(),
      contextual_evidence = list(),
      total_weight_score = 0
    ),
    temporal_patterns = list(
      pattern_type = "none",
      escalation_indicators = character(),
      timeline_events = character(),
      confidence = 0
    ),
    quality_metrics = list(
      data_completeness = 0,
      analysis_flags = c("API_ERROR"),
      overall_confidence = 0,
      reviewer_notes = paste("Error occurred:", as.character(error))
    ),
    success = FALSE,
    forensic_mode = TRUE
  )
}

#' Build Prompt (Modernized)
#'
#' @param narrative Narrative text
#' @param type "LE" or "CME"
#' @param config Required config object with prompt templates from settings.yml
#' @param use_forensic Use forensic template for advanced analysis
#' @return Formatted prompt
#' @export
build_prompt <- function(narrative, type = "LE", config = NULL, use_forensic = FALSE) {
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
  
  # Check if forensic mode is enabled (from config or parameter)
  use_forensic <- use_forensic || isTRUE(config$processing$use_forensic_analysis)
  
  # Choose template based on analysis type
  if (use_forensic) {
    # Load forensic prompt if needed
    if (requireNamespace("nvdrsipvdetector", quietly = TRUE)) {
      # Call forensic prompt builder if available
      if (exists("build_forensic_prompt")) {
        return(build_forensic_prompt(narrative, type, config))
      }
    }
    # Fallback to inline forensic template if available
    if (!is.null(config$prompts$forensic_template)) {
      template <- config$prompts$forensic_template
    } else {
      cli::cli_alert_warning("Forensic mode requested but forensic template not found")
      template <- config$prompts$unified_template
    }
  } else {
    template <- config$prompts$unified_template
  }
  
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
    # Use template - replace narrative type placeholder
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

#' Build Forensic Prompt
#'
#' @description
#' Builds comprehensive forensic analysis prompt using the forensic template.
#' Handles token budget management and narrative truncation if needed.
#'
#' @param narrative Narrative text
#' @param type "LE" or "CME"
#' @param config Configuration object
#' @param max_narrative_tokens Maximum tokens to use for narrative (default 6000)
#' @return Formatted forensic prompt
#' @export
build_forensic_prompt <- function(narrative, 
                                  type = "LE", 
                                  config = NULL,
                                  max_narrative_tokens = 6000) {
  
  if (is.null(config) || is.null(config$prompts$forensic_template)) {
    stop("Forensic template not found in configuration. Please ensure inst/settings.yml contains forensic_template.")
  }
  
  # Clean and validate narrative
  narrative <- stringr::str_trim(narrative)
  if (is.null(narrative) || is.na(narrative) || nchar(narrative) == 0) {
    narrative <- "[No narrative text available]"
  }
  
  # Estimate token count and truncate if necessary
  # Rough estimate: 1 token ≈ 4 characters
  estimated_tokens <- nchar(narrative) / 4
  if (estimated_tokens > max_narrative_tokens) {
    truncate_chars <- max_narrative_tokens * 4
    narrative <- paste0(substr(narrative, 1, truncate_chars), "\n[TRUNCATED FOR LENGTH]")
    cli::cli_alert_warning("Narrative truncated to fit token budget")
  }
  
  # Get template and replace placeholders
  template <- config$prompts$forensic_template
  narrative_type <- if (type == "LE") "law enforcement" else "medical examiner"
  
  # Replace placeholders
  prompt <- template %>%
    stringr::str_replace_all("\\{narrative_type\\}", narrative_type) %>%
    stringr::str_replace_all("\\{narrative\\}", narrative)
  
  prompt
}