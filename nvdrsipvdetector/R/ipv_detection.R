#' Core Detection Logic
#'
#' @description Main IPV detection functions
#' @name ipv_detection
#' @keywords internal
NULL

#' Initialize Database
#'
#' @param db_path Path to SQLite database
#' @return Database connection
#' @export
init_database <- function(db_path = "logs/api_logs.sqlite") {
  dir.create(dirname(db_path), recursive = TRUE, showWarnings = FALSE)
  conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  
  # Create schema as specified in CLAUDE.md
  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS api_logs (
      request_id TEXT PRIMARY KEY,
      incident_id TEXT NOT NULL,
      timestamp INTEGER NOT NULL,
      prompt_type TEXT CHECK(prompt_type IN ('LE', 'CME')),
      prompt_text TEXT NOT NULL,
      raw_response TEXT,
      parsed_response TEXT,
      response_time_ms INTEGER,
      error TEXT
    )
  ")
  
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_incident ON api_logs(incident_id)")
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_timestamp ON api_logs(timestamp)")
  
  return(conn)
}

#' Log API Request
#'
#' @param conn Database connection
#' @param incident_id Incident ID
#' @param prompt_type "LE" or "CME"
#' @param prompt_text Full prompt
#' @param response Response from LLM
#' @param response_time_ms Response time
#' @export
log_api_request <- function(conn, incident_id, prompt_type, prompt_text, 
                           response = NULL, response_time_ms = NULL) {
  request_id <- paste0(incident_id, "_", prompt_type, "_", as.integer(Sys.time()))
  
  DBI::dbExecute(conn, "
    INSERT INTO api_logs (request_id, incident_id, timestamp, prompt_type, prompt_text,
                         raw_response, parsed_response, response_time_ms, error)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  ", params = list(
    request_id,
    incident_id,
    as.integer(Sys.time()),
    prompt_type,
    prompt_text,
    ifelse(is.null(response), NA, jsonlite::toJSON(response, auto_unbox = TRUE)),
    ifelse(is.null(response$parsed), NA, jsonlite::toJSON(response$parsed, auto_unbox = TRUE)),
    response_time_ms,
    ifelse(is.null(response$error), NA, response$error)
  ))
}

#' Load Configuration
#'
#' @description 
#' Loads configuration from various locations with intelligent search.
#' Searches in order: explicit path, current directory, user home, package defaults.
#'
#' @param config_path Optional path to settings.yml. If NULL, searches standard locations.
#' @return Configuration list with processed environment variables
#' @export
#' @examples
#' \dontrun{
#' # Use default search
#' config <- load_config()
#' 
#' # Specify custom config
#' config <- load_config("my_settings.yml")
#' }
load_config <- function(config_path = NULL) {
  # Define search paths in priority order
  search_paths <- c(
    config_path,                     # User specified
    "settings.yml",                  # Current directory
    "config/settings.yml",           # Config subdirectory
    ".nvdrs/settings.yml",          # Hidden config
    file.path(Sys.getenv("HOME"), ".nvdrs", "settings.yml")  # User home
  )
  
  # Remove NULLs and search for first existing file
  search_paths <- search_paths[!sapply(search_paths, is.null)]
  
  config_found <- FALSE
  for (path in search_paths) {
    if (file.exists(path)) {
      config_path <- path
      config_found <- TRUE
      cli::cli_alert_success("Using configuration: {.file {path}}")
      break
    }
  }
  
  # If no user config found, use package defaults
  if (!config_found) {
    # Try package installation location
    config_path <- system.file("settings.yml", package = "nvdrsipvdetector")
    
    # If not installed, try development locations
    if (config_path == "") {
      if (file.exists("inst/settings.yml")) {
        config_path <- "inst/settings.yml"
      } else if (file.exists("nvdrsipvdetector/inst/settings.yml")) {
        config_path <- "nvdrsipvdetector/inst/settings.yml"
      }
    }
    
    if (!file.exists(config_path)) {
      cli::cli_alert_danger("No configuration found")
      cli::cli_alert_info("Run {.code init_config()} to create a settings.yml file")
      stop("Configuration file not found. Run init_config() to get started.")
    }
    
    cli::cli_alert_warning("Using default package configuration (read-only)")
    cli::cli_alert_info("Run {.code init_config()} to create your own settings.yml")
  }
  
  # Read and parse YAML
  config_text <- readLines(config_path, warn = FALSE)
  
  # Replace environment variables
  for (i in seq_along(config_text)) {
    if (grepl("\\$\\{.*\\}", config_text[i])) {
      # Extract variable name and default
      matches <- regmatches(config_text[i], 
                           gregexpr("\\$\\{([^:]+):-([^}]+)\\}", config_text[i]))[[1]]
      for (match in matches) {
        parts <- strsplit(gsub("\\$\\{|\\}", "", match), ":-")[[1]]
        var_name <- parts[1]
        default_val <- parts[2]
        value <- Sys.getenv(var_name, default_val)
        config_text[i] <- gsub(match, value, config_text[i], fixed = TRUE)
      }
    }
  }
  
  config <- yaml::yaml.load(paste(config_text, collapse = "\n"))
  return(config)
}

#' Initialize User Configuration
#'
#' @description 
#' Creates a user-editable configuration file by copying the package template
#' to your project directory. This allows you to customize settings without
#' modifying the package installation.
#'
#' @param path Where to create the configuration file (default: "settings.yml")
#' @param force Overwrite existing file without prompting (default: FALSE)
#' @return Path to created configuration file (invisibly)
#' @export
#' @examples
#' \dontrun{
#' # Create settings.yml in current directory
#' init_config()
#' 
#' # Create in specific location
#' init_config("config/my_settings.yml")
#' 
#' # Force overwrite
#' init_config(force = TRUE)
#' }
init_config <- function(path = "settings.yml", force = FALSE) {
  # Find template file
  template <- system.file("settings.yml", package = "nvdrsipvdetector")
  
  # If package not installed, try development locations
  if (template == "") {
    if (file.exists("inst/settings.yml")) {
      template <- "inst/settings.yml"
    } else if (file.exists("nvdrsipvdetector/inst/settings.yml")) {
      template <- "nvdrsipvdetector/inst/settings.yml"
    } else {
      stop("Cannot find template configuration. Is the package installed correctly?")
    }
  }
  
  # Check if target exists
  if (file.exists(path) && !force) {
    cli::cli_alert_warning("Configuration file already exists: {.file {path}}")
    
    if (interactive()) {
      response <- readline("Overwrite? (y/N): ")
      if (tolower(response) != "y") {
        cli::cli_alert_info("Configuration initialization cancelled")
        return(invisible(NULL))
      }
    } else {
      cli::cli_alert_info("Use {.code force = TRUE} to overwrite")
      return(invisible(NULL))
    }
  }
  
  # Create directory if needed
  dir_path <- dirname(path)
  if (dir_path != "." && !dir.exists(dir_path)) {
    dir.create(dir_path, recursive = TRUE)
    cli::cli_alert_success("Created directory: {.path {dir_path}}")
  }
  
  # Copy template
  file.copy(template, path, overwrite = TRUE)
  cli::cli_alert_success("Created configuration file: {.file {path}}")
  
  # Provide helpful next steps
  cli::cli_h2("Next steps:")
  cli::cli_alert_info("1. Edit {.file {path}} to configure your LLM server")
  cli::cli_alert_info("2. Set {.code base_url} to your LM Studio/Ollama server address")
  cli::cli_alert_info("3. Set {.code model} to your preferred model")
  cli::cli_alert_info("4. Adjust {.code temperature} and {.code max_tokens} as needed")
  
  # Open in editor if possible
  if (interactive() && requireNamespace("rstudioapi", quietly = TRUE)) {
    if (rstudioapi::isAvailable()) {
      rstudioapi::navigateToFile(path)
      cli::cli_alert_success("Opened configuration file in editor")
    }
  }
  
  return(invisible(path))
}

#' Detect IPV in Narrative
#'
#' @description 
#' Main function for detecting intimate partner violence in narratives.
#' Automatically handles configuration and database connections.
#'
#' @param narrative Narrative text to analyze
#' @param type "LE" for law enforcement or "CME" for medical examiner
#' @param config Configuration object, path to config file, or NULL (uses default)
#' @param conn Database connection or NULL (auto-creates if logging enabled)
#' @param log_to_db Whether to log API calls to database (default TRUE)
#' @return List with ipv_detected, confidence, indicators, and rationale
#' @export
#' @examples
#' \dontrun{
#' # Simple usage - everything automatic
#' result <- detect_ipv("Domestic violence incident")
#' 
#' # Specify narrative type
#' result <- detect_ipv("Victim injuries", type = "CME")
#' 
#' # Use custom config file
#' result <- detect_ipv("Narrative text", config = "custom_config.yml")
#' 
#' # Advanced usage with explicit config and connection
#' my_config <- load_config("my_settings.yml")
#' my_conn <- init_database("my_logs.sqlite")
#' result <- detect_ipv("Narrative", config = my_config, conn = my_conn)
#' }
detect_ipv <- function(narrative, 
                      type = "LE", 
                      config = NULL, 
                      conn = NULL, 
                      log_to_db = TRUE) {
  
  # Handle empty narratives first
  if (is.na(narrative) || trimws(narrative) == "") {
    return(list(
      ipv_detected = NA,
      confidence = NA,
      indicators = character(),
      rationale = "No narrative available"
    ))
  }
  
  # Smart config handling
  if (is.null(config)) {
    # Load default config
    config <- load_config()
  } else if (is.character(config)) {
    # Assume it's a path to config file
    config <- load_config(config)
  }
  # If config is already a list, use as-is
  
  # Smart connection handling
  manage_conn <- FALSE
  if (is.null(conn) && log_to_db && !is.null(config$database$path)) {
    conn <- init_database(config$database$path)
    manage_conn <- TRUE  # Track that we created it
    on.exit({
      if (manage_conn && !is.null(conn)) {
        DBI::dbDisconnect(conn)
      }
    }, add = TRUE)
  }
  
  # Build prompt with config for templates
  prompt <- build_prompt(narrative, type, config)
  
  # Send to LLM
  start_time <- Sys.time()
  result <- send_to_llm(prompt, config)
  response_time_ms <- as.numeric(difftime(Sys.time(), start_time, units = "secs")) * 1000
  
  # Log if connection available (either provided or created)
  if (!is.null(conn)) {
    log_api_request(conn, "unknown", type, prompt, result, response_time_ms)
  }
  
  return(result)
}

#' Reconcile Results (for backward compatibility)
#'
#' @param results Results list or data frame
#' @param config Configuration list
#' @return Reconciled results
#' @export
reconcile_results <- function(results, config) {
  # Just delegate to reconcile_batch_results for backward compatibility
  reconcile_batch_results(results, config)
}

#' Process NVDRS Batch
#'
#' @param data Tibble with columns: IncidentID, NarrativeLE, NarrativeCME
#' @param config Path to config.yml file or config list
#' @param validate Logical; compare against manual flags if present
#' @return Tibble with IPV detection results
#' @export
#' @examples
#' \dontrun{
#' results <- nvdrs_process_batch("data.csv", "config.yml")
#' }
nvdrs_process_batch <- function(data, config = NULL, validate = FALSE) {
  # Load config if path provided
  if (is.character(config)) {
    config <- load_config(config)
  }
  
  # Read data if path provided
  if (is.character(data)) {
    data <- read_nvdrs_data(data)
    data <- validate_input_data(data)
  }
  
  # Convert to tibble
  data <- tibble::as_tibble(data)
  
  # Initialize database
  conn <- init_database(config$database$path)
  on.exit(DBI::dbDisconnect(conn))
  
  # Split data into batches
  data_with_batch <- data %>%
    dplyr::mutate(
      batch_id = ceiling(dplyr::row_number() / config$processing$batch_size)
    )
  
  batches <- data_with_batch %>%
    dplyr::group_split(batch_id)
  
  pb <- cli::cli_progress_bar("Processing", total = nrow(data))
  
  # Process batches using purrr::map
  batch_results <- purrr::map(
    batches, 
    ~ process_single_batch(.x, config, conn, pb)
  )
  
  # Combine all batch results
  final_results <- dplyr::bind_rows(batch_results)
  
  # Reconcile LE and CME using modernized function
  final_results <- reconcile_batch_results(final_results, config)
  
  # Validate if requested
  if (validate && "ManualIPVFlag" %in% names(final_results)) {
    validation <- calculate_metrics(final_results)
    print_validation_report(validation)
  }
  
  return(final_results)
}

#' Process Single Batch (Helper Function)
#'
#' @param batch Batch of data to process
#' @param config Configuration object
#' @param conn Database connection
#' @param pb Progress bar
#' @return Processed batch with results
process_single_batch <- function(batch, config, conn, pb) {
  result <- batch %>%
    dplyr::mutate(
      le_result = purrr::map(
        NarrativeLE, 
        ~ process_narrative(.x, "LE", config, conn)
      ),
      cme_result = purrr::map(
        NarrativeCME, 
        ~ process_narrative(.x, "CME", config, conn)
      ),
      le_ipv = purrr::map_lgl(
        le_result, 
        ~ .x$ipv_detected %||% NA
      ),
      le_confidence = purrr::map_dbl(
        le_result, 
        ~ .x$confidence %||% NA
      ),
      cme_ipv = purrr::map_lgl(
        cme_result, 
        ~ .x$ipv_detected %||% NA
      ),
      cme_confidence = purrr::map_dbl(
        cme_result, 
        ~ .x$confidence %||% NA
      )
    ) %>%
    dplyr::select(-le_result, -cme_result)
    
  # Update progress bar for each record
  cli::cli_progress_update(inc = nrow(result), id = pb)
  
  return(result)
}

#' Process Single Narrative (Helper Function)
#'
#' @param narrative Single narrative text
#' @param type "LE" or "CME"
#' @param config Configuration object
#' @param conn Database connection
#' @return Detection result
process_narrative <- function(narrative, type, config, conn) {
  if (is.na(narrative)) {
    return(list(ipv_detected = NA, confidence = NA))
  }
  
  detect_ipv(narrative, type, config, conn, log_to_db = TRUE)
}

#' Reconcile Batch Results (Modernized)
#'
#' @param results Tibble with le_ipv and cme_ipv columns
#' @param config Configuration with weights
#' @return Tibble with reconciled results
reconcile_batch_results <- function(results, config) {
  results %>%
    dplyr::mutate(
      confidence = dplyr::case_when(
        is.na(le_ipv) & is.na(cme_ipv) ~ NA_real_,
        is.na(le_ipv) ~ cme_confidence,
        is.na(cme_ipv) ~ le_confidence,
        TRUE ~ le_confidence * config$weights$le + 
                cme_confidence * config$weights$cme
      ),
      ipv_detected = dplyr::case_when(
        is.na(le_ipv) & is.na(cme_ipv) ~ NA,
        is.na(le_ipv) ~ cme_ipv,
        is.na(cme_ipv) ~ le_ipv,
        TRUE ~ confidence >= config$weights$threshold
      )
    )
}

#' Detect IPV with Forensic Analysis
#'
#' @description
#' Advanced IPV detection using comprehensive forensic analysis framework.
#' Provides systematic analysis through 6 phases: death classification,
#' directionality assessment, suicide analysis, evidence hierarchy,
#' temporal patterns, and quality control.
#'
#' @param narrative Narrative text to analyze
#' @param type "LE" for law enforcement or "CME" for medical examiner
#' @param incident_id Unique incident identifier (auto-generated if NULL)
#' @param config Configuration object or path (uses forensic template)
#' @param conn Database connection for logging
#' @param log_to_db Whether to log the API request
#' @return IPVForensicResult object with comprehensive analysis
#' @export
#' @examples
#' \dontrun{
#' # Basic forensic analysis
#' result <- detect_ipv_forensic(
#'   narrative = "Law enforcement narrative text...",
#'   type = "LE"
#' )
#'
#' # Access comprehensive analysis
#' summary <- result$get_summary()
#' tibble_data <- result$to_tibble()
#'
#' # Advanced usage with custom config and connection
#' config <- load_config("forensic_settings.yml")
#' conn <- init_database("forensic_logs.sqlite")
#' result <- detect_ipv_forensic(
#'   narrative = narrative,
#'   type = "CME",
#'   incident_id = "2024-001",
#'   config = config,
#'   conn = conn
#' )
#' }
detect_ipv_forensic <- function(narrative,
                               type = "LE",
                               incident_id = NULL,
                               config = NULL,
                               conn = NULL,
                               log_to_db = TRUE) {

  # Generate incident ID if not provided
  if (is.null(incident_id)) {
    incident_id <- paste0("forensic_", format(Sys.time(), "%Y%m%d_%H%M%S"))
  }

  # Handle empty narratives
  if (is.null(narrative) || is.na(narrative) || trimws(narrative) == "") {
    cli::cli_alert_warning("Empty narrative provided for incident {incident_id}")
    
    # Create forensic result with minimal data
    forensic_result <- ipv_forensic_result$new(
      incident_id = incident_id,
      le_narrative = if (type == "LE") "[Empty]" else NULL,
      cme_narrative = if (type == "CME") "[Empty]" else NULL
    )
    
    # Set error state
    forensic_result$update_death_classification(
      classification = "insufficient_data",
      confidence = 0,
      rationale = "No narrative text available"
    )
    
    forensic_result$quality_metrics$analysis_flags <- c("EMPTY_NARRATIVE")
    forensic_result$quality_metrics$data_completeness <- 0
    
    return(forensic_result)
  }

  # Smart config handling - enable forensic analysis
  if (is.null(config)) {
    config <- load_config()
  } else if (is.character(config)) {
    config <- load_config(config)
  }
  
  # Ensure forensic analysis is enabled
  if (is.null(config$processing$use_forensic_analysis)) {
    config$processing$use_forensic_analysis <- TRUE
  }

  # Smart connection handling
  manage_conn <- FALSE
  if (is.null(conn) && log_to_db && !is.null(config$database$path)) {
    conn <- init_database(config$database$path)
    manage_conn <- TRUE
    on.exit({
      if (manage_conn && !is.null(conn)) {
        DBI::dbDisconnect(conn)
      }
    }, add = TRUE)
  }

  # Create forensic result object
  forensic_result <- ipv_forensic_result$new(
    incident_id = incident_id,
    le_narrative = if (type == "LE") narrative else NULL,
    cme_narrative = if (type == "CME") narrative else NULL
  )

  # Build forensic prompt with token management
  max_narrative_tokens <- config$processing$max_narrative_tokens %||% 6000
  prompt <- build_forensic_prompt(
    narrative = narrative,
    type = type,
    config = config,
    max_narrative_tokens = max_narrative_tokens
  )

  # Send to LLM with forensic mode
  start_time <- Sys.time()
  result <- send_to_llm(prompt, config, forensic_mode = TRUE)
  end_time <- Sys.time()
  response_time_ms <- as.numeric(difftime(end_time, start_time, units = "secs")) * 1000

  # Log the API request if database available
  if (log_to_db && !is.null(conn)) {
    log_api_request(
      conn = conn,
      incident_id = incident_id,
      prompt_type = paste0(type, "_FORENSIC"),
      prompt_text = prompt,
      response = result,
      response_time_ms = response_time_ms
    )
  }

  # Check if request was successful
  if (!result$success) {
    cli::cli_alert_danger("Forensic analysis failed for incident {incident_id}")
    forensic_result$quality_metrics$analysis_flags <- c("API_ERROR")
    forensic_result$quality_metrics$overall_confidence <- 0
    return(forensic_result)
  }

  # Populate forensic result with LLM analysis
  forensic_result <- populate_forensic_result_from_llm(
    forensic_result,
    result,
    type
  )

  # Perform additional validation and quality checks
  validation <- forensic_result$validate_analysis()
  if (!validation$is_valid) {
    cli::cli_alert_warning(
      "Validation issues for incident {incident_id}: {paste(validation$issues, collapse = ', ')}"
    )
  }

  forensic_result
}

#' Populate Forensic Result from LLM Response
#'
#' @description
#' Transfers structured LLM forensic analysis to IPVForensicResult object.
#'
#' @param forensic_result IPVForensicResult object
#' @param llm_result LLM response with forensic analysis
#' @param narrative_type "LE" or "CME"
#' @return Updated forensic result
populate_forensic_result_from_llm <- function(forensic_result, llm_result, narrative_type) {
  
  # Update death classification
  if (!is.null(llm_result$death_classification)) {
    forensic_result$update_death_classification(
      classification = llm_result$death_classification$primary %||% "undetermined",
      confidence = llm_result$death_classification$confidence %||% 0,
      evidence = llm_result$death_classification$supporting_evidence %||% character(),
      rationale = llm_result$death_classification$rationale %||% ""
    )
  }

  # Update directionality assessment
  if (!is.null(llm_result$directionality)) {
    forensic_result$update_directionality(
      perpetrator_evidence = llm_result$directionality$perpetrator_indicators %||% character(),
      victim_evidence = llm_result$directionality$victim_indicators %||% character(),
      bidirectional_score = llm_result$directionality$bidirectional_score %||% 0,
      primary_direction = llm_result$directionality$primary_direction %||% "undetermined",
      confidence = llm_result$directionality$confidence %||% 0
    )
  }

  # Update suicide analysis
  if (!is.null(llm_result$suicide_analysis)) {
    forensic_result$update_suicide_analysis(
      intent_classification = llm_result$suicide_analysis$intent_classification %||% "undetermined",
      weapon_vs_escape = llm_result$suicide_analysis$weapon_vs_escape %||% "undetermined",
      precipitating_factors = llm_result$suicide_analysis$precipitating_factors %||% character(),
      confidence = llm_result$suicide_analysis$confidence %||% 0
    )
  }

  # Add evidence items from matrix
  if (!is.null(llm_result$evidence_matrix)) {
    # Add physical evidence
    if (!is.null(llm_result$evidence_matrix$physical_evidence)) {
      for (evidence_item in llm_result$evidence_matrix$physical_evidence) {
        forensic_result$add_evidence(
          evidence_type = "physical_evidence",
          evidence_item = evidence_item$item %||% "unknown",
          weight = evidence_item$weight %||% 0.9,
          source = paste0(narrative_type, "_forensic_analysis"),
          reliability = evidence_item$reliability %||% 0.8
        )
      }
    }

    # Add behavioral evidence
    if (!is.null(llm_result$evidence_matrix$behavioral_evidence)) {
      for (evidence_item in llm_result$evidence_matrix$behavioral_evidence) {
        forensic_result$add_evidence(
          evidence_type = "behavioral_evidence",
          evidence_item = evidence_item$item %||% "unknown",
          weight = evidence_item$weight %||% 0.7,
          source = paste0(narrative_type, "_forensic_analysis"),
          reliability = evidence_item$reliability %||% 0.6
        )
      }
    }

    # Add contextual evidence
    if (!is.null(llm_result$evidence_matrix$contextual_evidence)) {
      for (evidence_item in llm_result$evidence_matrix$contextual_evidence) {
        forensic_result$add_evidence(
          evidence_type = "contextual_evidence",
          evidence_item = evidence_item$item %||% "unknown",
          weight = evidence_item$weight %||% 0.5,
          source = paste0(narrative_type, "_forensic_analysis"),
          reliability = evidence_item$reliability %||% 0.7
        )
      }
    }
  }

  # Update temporal patterns
  if (!is.null(llm_result$temporal_patterns)) {
    forensic_result$update_temporal_patterns(
      escalation_indicators = llm_result$temporal_patterns$escalation_indicators %||% character(),
      timeline_events = llm_result$temporal_patterns$timeline_events %||% character(),
      pattern_type = llm_result$temporal_patterns$pattern_type %||% "none",
      confidence = llm_result$temporal_patterns$confidence %||% 0
    )
  }

  # Update quality metrics
  if (!is.null(llm_result$quality_metrics)) {
    forensic_result$quality_metrics$data_completeness <- 
      llm_result$quality_metrics$data_completeness %||% 0
    forensic_result$quality_metrics$analysis_flags <- 
      llm_result$quality_metrics$analysis_flags %||% character()
    forensic_result$quality_metrics$overall_confidence <- 
      llm_result$quality_metrics$overall_confidence %||% 0
    forensic_result$quality_metrics$reviewer_notes <- list(
      paste0(narrative_type, "_forensic: ", 
             llm_result$quality_metrics$reviewer_notes %||% "")
    )
  }

  forensic_result
}

