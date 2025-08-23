#' Forensic IPV Analysis Functions
#'
#' @description Advanced forensic analysis for IPV directionality assessment
#' @keywords internal
NULL

#' Load Forensic Prompt Configuration
#'
#' @param config Main configuration object
#' @return Forensic prompt configuration
#' @export
load_forensic_prompt <- function(config) {
  if (is.null(config$processing$forensic_prompt_file)) {
    forensic_file <- "forensic_prompt.yml"
  } else {
    forensic_file <- config$processing$forensic_prompt_file
  }
  
  # Find forensic prompt file
  forensic_path <- system.file(forensic_file, package = "nvdrsipvdetector")
  if (forensic_path == "") {
    forensic_path <- file.path("inst", forensic_file)
    if (!file.exists(forensic_path)) {
      stop("Forensic prompt configuration not found: ", forensic_file)
    }
  }
  
  # Load and return forensic config
  yaml::yaml.load_file(forensic_path)
}

#' Build Forensic Prompt
#'
#' @param narrative Narrative text to analyze
#' @param type "LE" or "CME"
#' @param config Configuration object
#' @return Formatted forensic prompt
#' @export
build_forensic_prompt <- function(narrative, type = "LE", config = NULL) {
  # Load forensic configuration
  forensic_config <- load_forensic_prompt(config)
  
  # Clean narrative
  narrative <- stringr::str_trim(narrative)
  
  # Check token limits
  if (!is.null(config$processing$max_narrative_tokens)) {
    # Simple token estimation (4 chars per token)
    estimated_tokens <- nchar(narrative) / 4
    if (estimated_tokens > config$processing$max_narrative_tokens) {
      # Truncate narrative to fit token budget
      max_chars <- config$processing$max_narrative_tokens * 4
      narrative <- substr(narrative, 1, max_chars)
      cli::cli_alert_warning("Narrative truncated to fit token budget")
    }
  }
  
  # Get forensic template
  template <- forensic_config$forensic_template
  
  # Replace placeholders
  narrative_type <- if (type == "LE") "Law enforcement" else "Medical examiner"
  prompt <- stringr::str_replace_all(template, "\\{narrative_type\\}", narrative_type)
  prompt <- stringr::str_replace_all(prompt, "\\{narrative\\}", narrative)
  
  return(prompt)
}

#' Parse Forensic LLM Response
#'
#' @param response Raw LLM response
#' @return Parsed forensic analysis structure
#' @export
parse_forensic_response <- function(response) {
  tryCatch({
    # Extract JSON from response
    json_text <- response
    if (is.character(response)) {
      # Find JSON block if wrapped in markdown
      json_match <- stringr::str_extract(response, "\\{[\\s\\S]*\\}")
      if (!is.na(json_match)) {
        json_text <- json_match
      }
    }
    
    # Parse JSON
    parsed <- jsonlite::parse_json(json_text)
    
    # Validate required fields
    required_fields <- c("death_classification", "directionality", 
                        "suicide_analysis", "evidence_matrix", 
                        "temporal_patterns", "quality_metrics")
    
    missing_fields <- setdiff(required_fields, names(parsed))
    if (length(missing_fields) > 0) {
      cli::cli_alert_warning("Missing forensic fields: {missing_fields}")
    }
    
    return(parsed)
    
  }, error = function(e) {
    cli::cli_alert_danger("Failed to parse forensic response: {e$message}")
    return(create_forensic_error_response(e$message))
  })
}

#' Create Forensic Error Response
#'
#' @param error_message Error description
#' @return Default forensic structure with error
#' @export
create_forensic_error_response <- function(error_message) {
  list(
    death_classification = list(
      type = "undetermined",
      mechanism = "undetermined",
      confidence = 0
    ),
    directionality = list(
      primary_direction = "undetermined",
      confidence = 0,
      perpetrator_indicators = list(
        coercive_threats = FALSE,
        control_patterns = FALSE,
        power_advantages = FALSE,
        murder_suicide_attempt = FALSE,
        evidence = list()
      ),
      victim_indicators = list(
        defensive_patterns = FALSE,
        help_seeking = FALSE,
        mental_decline = FALSE,
        escape_suicide = FALSE,
        evidence = list()
      ),
      bidirectional_score = 0
    ),
    suicide_analysis = list(
      intent = "undetermined",
      method = "not_applicable",
      precipitating_factors = list(),
      behavioral_precursors = list()
    ),
    evidence_matrix = list(
      physical = list(items = list(), weight = 0.9),
      behavioral = list(items = list(), weight = 0.7),
      contextual = list(items = list(), weight = 0.5),
      circumstantial = list(items = list(), weight = 0.3)
    ),
    temporal_patterns = list(
      pattern_type = "undetermined",
      escalation_indicators = list(),
      timeline_events = list(),
      critical_period = NA
    ),
    quality_metrics = list(
      data_completeness = 0,
      analysis_confidence = 0,
      missing_information = list("Analysis failed"),
      alternative_hypotheses = list()
    ),
    error = error_message
  )
}

#' Detect IPV with Forensic Analysis
#'
#' @description 
#' Performs advanced forensic IPV analysis with directionality assessment,
#' suicide intent classification, and evidence weighting.
#'
#' @param narrative Narrative text to analyze
#' @param type "LE" for law enforcement or "CME" for medical examiner
#' @param config Configuration object or path
#' @param conn Database connection (optional)
#' @param log_to_db Whether to log to database
#' @return Forensic IPV analysis results
#' @export
#' @examples
#' \dontrun{
#' # Perform forensic analysis
#' result <- detect_ipv_forensic(
#'   narrative = "Detailed death investigation narrative...",
#'   type = "LE"
#' )
#' 
#' # Check directionality
#' print(result$directionality$primary_direction)
#' 
#' # Check suicide intent
#' print(result$suicide_analysis$method)
#' }
detect_ipv_forensic <- function(narrative, 
                               type = "LE", 
                               config = NULL,
                               conn = NULL,
                               log_to_db = TRUE) {
  
  # Handle empty narratives
  if (is.na(narrative) || trimws(narrative) == "") {
    cli::cli_alert_warning("Empty narrative provided")
    return(create_forensic_error_response("Empty narrative"))
  }
  
  # Load configuration
  if (is.null(config)) {
    config <- load_config()
  } else if (is.character(config)) {
    config <- load_config(config)
  }
  
  # Check if forensic analysis is enabled
  if (!isTRUE(config$processing$use_forensic_analysis)) {
    cli::cli_alert_info("Forensic analysis not enabled. Set use_forensic_analysis: true in config")
    # Fall back to simple detection
    return(detect_ipv(narrative, type, config, conn, log_to_db))
  }
  
  # Initialize database if needed
  if (log_to_db && is.null(conn)) {
    db_path <- config$database$path %||% "logs/api_logs.sqlite"
    conn <- init_database(db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)
  }
  
  # Build forensic prompt
  prompt <- build_forensic_prompt(narrative, type, config)
  
  # Track timing
  start_time <- Sys.time()
  
  # Send to LLM
  cli::cli_alert_info("Performing forensic IPV analysis...")
  response <- send_to_llm(prompt, config)
  
  # Calculate response time
  response_time_ms <- as.numeric(difftime(Sys.time(), start_time, units = "secs")) * 1000
  
  # Parse forensic response
  if (!is.null(response$success) && response$success) {
    # For compatibility, check if response is already parsed
    if (!is.null(response$death_classification)) {
      forensic_result <- response
    } else {
      # Parse the raw response
      forensic_result <- parse_forensic_response(response)
    }
  } else {
    forensic_result <- create_forensic_error_response(
      response$error %||% "LLM request failed"
    )
  }
  
  # Log to database if enabled
  if (log_to_db && !is.null(conn)) {
    log_forensic_request(
      conn = conn,
      narrative_type = type,
      prompt = prompt,
      response = forensic_result,
      response_time_ms = response_time_ms
    )
  }
  
  # Add metadata
  forensic_result$metadata <- list(
    narrative_type = type,
    analysis_timestamp = Sys.time(),
    response_time_ms = response_time_ms,
    model = config$api$model
  )
  
  return(forensic_result)
}

#' Log Forensic API Request
#'
#' @param conn Database connection
#' @param narrative_type "LE" or "CME"
#' @param prompt Full prompt sent
#' @param response Forensic response
#' @param response_time_ms Response time
#' @keywords internal
log_forensic_request <- function(conn, narrative_type, prompt, 
                                response, response_time_ms) {
  # Generate unique request ID
  request_id <- paste0("forensic_", narrative_type, "_", 
                      format(Sys.time(), "%Y%m%d%H%M%S"))
  
  # Prepare forensic-specific fields
  forensic_data <- jsonlite::toJSON(list(
    death_type = response$death_classification$type,
    directionality = response$directionality$primary_direction,
    suicide_intent = response$suicide_analysis$intent,
    confidence = response$directionality$confidence
  ), auto_unbox = TRUE)
  
  # Insert into database
  DBI::dbExecute(conn, "
    INSERT INTO api_logs (
      request_id, incident_id, timestamp, prompt_type, 
      prompt_text, raw_response, parsed_response, 
      response_time_ms, error
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  ", params = list(
    request_id,
    "forensic_analysis",
    as.integer(Sys.time()),
    paste0(narrative_type, "_forensic"),
    prompt,
    jsonlite::toJSON(response, auto_unbox = TRUE),
    forensic_data,
    response_time_ms,
    response$error %||% NA
  ))
}

#' Process Batch with Forensic Analysis
#'
#' @param data Data frame with narratives
#' @param config Configuration object
#' @param validate Whether to validate against manual flags
#' @return Data frame with forensic analysis results
#' @export
nvdrs_process_batch_forensic <- function(data, 
                                        config = NULL, 
                                        validate = FALSE) {
  
  # Validate input data
  required_cols <- c("IncidentID", "NarrativeLE", "NarrativeCME")
  if (!all(required_cols %in% names(data))) {
    stop("Data must contain: ", paste(required_cols, collapse = ", "))
  }
  
  # Load config
  if (is.null(config)) {
    config <- load_config()
  }
  
  # Enable forensic analysis
  config$processing$use_forensic_analysis <- TRUE
  
  # Initialize results
  results <- list()
  
  # Process each incident
  cli::cli_progress_bar("Processing forensic analysis", total = nrow(data))
  
  for (i in seq_len(nrow(data))) {
    incident <- data[i, ]
    
    # Analyze LE narrative
    le_result <- NULL
    if (!is.na(incident$NarrativeLE) && trimws(incident$NarrativeLE) != "") {
      le_result <- detect_ipv_forensic(
        narrative = incident$NarrativeLE,
        type = "LE",
        config = config
      )
    }
    
    # Analyze CME narrative
    cme_result <- NULL
    if (!is.na(incident$NarrativeCME) && trimws(incident$NarrativeCME) != "") {
      cme_result <- detect_ipv_forensic(
        narrative = incident$NarrativeCME,
        type = "CME",
        config = config
      )
    }
    
    # Combine results
    combined <- reconcile_forensic_results(
      le_result = le_result,
      cme_result = cme_result,
      weights = config$weights
    )
    
    # Add incident ID
    combined$IncidentID <- incident$IncidentID
    
    # Store result
    results[[i]] <- combined
    
    cli::cli_progress_update()
  }
  
  cli::cli_progress_done()
  
  # Convert to data frame
  results_df <- dplyr::bind_rows(results)
  
  # Add validation if requested
  if (validate && "ManualIPVFlag" %in% names(data)) {
    results_df <- results_df %>%
      dplyr::left_join(
        data %>% dplyr::select(IncidentID, ManualIPVFlag),
        by = "IncidentID"
      ) %>%
      dplyr::mutate(
        agreement = (directionality_primary != "undetermined") == ManualIPVFlag
      )
  }
  
  return(results_df)
}

#' Reconcile Forensic Results
#'
#' @param le_result LE forensic analysis
#' @param cme_result CME forensic analysis  
#' @param weights Weights for combining
#' @return Combined forensic assessment
#' @export
reconcile_forensic_results <- function(le_result, cme_result, weights) {
  
  # Handle missing results
  if (is.null(le_result) && is.null(cme_result)) {
    return(create_forensic_error_response("No narratives analyzed"))
  }
  
  if (is.null(le_result)) {
    return(flatten_forensic_result(cme_result))
  }
  
  if (is.null(cme_result)) {
    return(flatten_forensic_result(le_result))
  }
  
  # Both results available - combine with weights
  le_weight <- weights$le %||% 0.4
  cme_weight <- weights$cme %||% 0.6
  
  # Combine directionality with weights
  combined_direction <- if (le_result$directionality$primary_direction == 
                           cme_result$directionality$primary_direction) {
    le_result$directionality$primary_direction
  } else if (cme_result$directionality$confidence * cme_weight > 
            le_result$directionality$confidence * le_weight) {
    cme_result$directionality$primary_direction
  } else {
    le_result$directionality$primary_direction
  }
  
  # Combine confidence scores
  combined_confidence <- (le_result$directionality$confidence * le_weight +
                         cme_result$directionality$confidence * cme_weight)
  
  # Create flattened result for data frame
  list(
    death_type = cme_result$death_classification$type,
    death_mechanism = cme_result$death_classification$mechanism,
    directionality_primary = combined_direction,
    directionality_confidence = combined_confidence,
    suicide_intent = coalesce(cme_result$suicide_analysis$intent,
                              le_result$suicide_analysis$intent),
    suicide_method = coalesce(cme_result$suicide_analysis$method,
                              le_result$suicide_analysis$method),
    temporal_pattern = coalesce(cme_result$temporal_patterns$pattern_type,
                                le_result$temporal_patterns$pattern_type),
    data_completeness = max(le_result$quality_metrics$data_completeness,
                           cme_result$quality_metrics$data_completeness),
    analysis_confidence = combined_confidence
  )
}

#' Flatten Forensic Result for Data Frame
#'
#' @param result Forensic analysis result
#' @return Flattened list for data frame row
#' @keywords internal
flatten_forensic_result <- function(result) {
  list(
    death_type = result$death_classification$type %||% NA,
    death_mechanism = result$death_classification$mechanism %||% NA,
    directionality_primary = result$directionality$primary_direction %||% NA,
    directionality_confidence = result$directionality$confidence %||% 0,
    suicide_intent = result$suicide_analysis$intent %||% NA,
    suicide_method = result$suicide_analysis$method %||% NA,
    temporal_pattern = result$temporal_patterns$pattern_type %||% NA,
    data_completeness = result$quality_metrics$data_completeness %||% 0,
    analysis_confidence = result$quality_metrics$analysis_confidence %||% 0
  )
}

#' Helper to coalesce values
#' @keywords internal
coalesce <- function(...) {
  values <- list(...)
  for (val in values) {
    if (!is.null(val) && !is.na(val)) {
      return(val)
    }
  }
  return(NA)
}