#' Core Detection Logic
#'
#' @description Main IPV detection functions
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
#' @param config_path Path to settings.yml
#' @return Configuration list
#' @export
load_config <- function(config_path = NULL) {
  # If no path provided, try to find settings.yml
  if (is.null(config_path)) {
    # First try package installation location
    config_path <- system.file("settings.yml", package = "nvdrsipvdetector")
    
    # If not installed, try development location
    if (config_path == "") {
      config_path <- "inst/settings.yml"
      if (!file.exists(config_path)) {
        config_path <- "nvdrsipvdetector/inst/settings.yml"
      }
    }
  }
  
  if (!file.exists(config_path)) {
    stop("Configuration file not found. Tried: ", config_path)
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

