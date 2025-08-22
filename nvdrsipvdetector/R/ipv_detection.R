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
load_config <- function(config_path = "config/settings.yml") {
  if (!file.exists(config_path)) {
    stop("Configuration file not found: ", config_path)
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
#' @param narrative Narrative text
#' @param type "LE" or "CME"
#' @param config Configuration
#' @param conn Database connection
#' @return Detection result
#' @export
detect_ipv <- function(narrative, type = "LE", config, conn = NULL) {
  # Handle empty narratives
  if (is.na(narrative) || trimws(narrative) == "") {
    return(list(
      ipv_detected = NA,
      confidence = NA,
      indicators = character(),
      rationale = "No narrative available"
    ))
  }
  
  # Build prompt
  prompt <- build_prompt(narrative, type)
  
  # Send to LLM
  start_time <- Sys.time()
  result <- send_to_llm(prompt, config)
  response_time_ms <- as.numeric(difftime(Sys.time(), start_time, units = "secs")) * 1000
  
  # Log if connection provided
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
nvdrs_process_batch <- function(data, config = "config/settings.yml", validate = FALSE) {
  # Load config if path provided
  if (is.character(config)) {
    config <- load_config(config)
  }
  
  # Read data if path provided
  if (is.character(data)) {
    data <- read_nvdrs_data(data)
    data <- validate_input_data(data)
  }
  
  # Initialize database
  conn <- init_database(config$database$path)
  on.exit(DBI::dbDisconnect(conn))
  
  # Process in batches
  batches <- split_into_batches(data, config$processing$batch_size)
  results <- vector("list", length(batches))
  
  pb <- cli::cli_progress_bar("Processing", total = nrow(data))
  
  for (i in seq_along(batches)) {
    batch <- batches[[i]]
    batch_results <- batch
    
    # Process each record
    for (j in seq_len(nrow(batch))) {
      # LE narrative
      if (!is.na(batch$NarrativeLE[j])) {
        le_result <- detect_ipv(batch$NarrativeLE[j], "LE", config, conn)
        batch_results$le_ipv[j] <- le_result$ipv_detected
        batch_results$le_confidence[j] <- le_result$confidence
      } else {
        batch_results$le_ipv[j] <- NA
        batch_results$le_confidence[j] <- NA
      }
      
      # CME narrative
      if (!is.na(batch$NarrativeCME[j])) {
        cme_result <- detect_ipv(batch$NarrativeCME[j], "CME", config, conn)
        batch_results$cme_ipv[j] <- cme_result$ipv_detected
        batch_results$cme_confidence[j] <- cme_result$confidence
      } else {
        batch_results$cme_ipv[j] <- NA
        batch_results$cme_confidence[j] <- NA
      }
      
      cli::cli_progress_update(inc = 1, id = pb)
    }
    
    results[[i]] <- batch_results
    
    # Checkpoint every N records
    if ((i * config$processing$batch_size) %% config$processing$checkpoint_every == 0) {
      saveRDS(do.call(rbind, results), paste0("checkpoint_", Sys.Date(), ".rds"))
    }
  }
  
  # Combine results
  final_results <- do.call(rbind, results)
  
  # Reconcile LE and CME
  final_results <- reconcile_results(final_results, config)
  
  # Validate if requested
  if (validate && "ManualIPVFlag" %in% names(final_results)) {
    validation <- validate_results(final_results)
    print(validation)
  }
  
  return(final_results)
}

#' Reconcile LE and CME Results
#'
#' @param results Data frame with le_ipv and cme_ipv columns
#' @param config Configuration with weights
#' @return Data frame with reconciled results
reconcile_results <- function(results, config) {
  for (i in seq_len(nrow(results))) {
    # Get weights
    le_weight <- config$weights$le
    cme_weight <- config$weights$cme
    
    # Handle missing values
    if (is.na(results$le_ipv[i]) && is.na(results$cme_ipv[i])) {
      results$ipv_detected[i] <- NA
      results$confidence[i] <- NA
    } else if (is.na(results$le_ipv[i])) {
      results$ipv_detected[i] <- results$cme_ipv[i]
      results$confidence[i] <- results$cme_confidence[i]
    } else if (is.na(results$cme_ipv[i])) {
      results$ipv_detected[i] <- results$le_ipv[i]
      results$confidence[i] <- results$le_confidence[i]
    } else {
      # Weighted average
      results$confidence[i] <- results$le_confidence[i] * le_weight + 
                               results$cme_confidence[i] * cme_weight
      results$ipv_detected[i] <- results$confidence[i] >= config$weights$threshold
    }
  }
  
  return(results)
}

#' Validate Results
#'
#' @param results Data frame with predictions and ManualIPVFlag
#' @return Validation metrics
validate_results <- function(results) {
  # Remove NA values
  valid <- results[!is.na(results$ipv_detected) & !is.na(results$ManualIPVFlag), ]
  
  # Calculate metrics
  tp <- sum(valid$ipv_detected & valid$ManualIPVFlag)
  tn <- sum(!valid$ipv_detected & !valid$ManualIPVFlag)
  fp <- sum(valid$ipv_detected & !valid$ManualIPVFlag)
  fn <- sum(!valid$ipv_detected & valid$ManualIPVFlag)
  
  accuracy <- (tp + tn) / nrow(valid)
  precision <- if (tp + fp > 0) tp / (tp + fp) else NA
  recall <- if (tp + fn > 0) tp / (tp + fn) else NA
  f1 <- if (!is.na(precision) && !is.na(recall)) {
    2 * (precision * recall) / (precision + recall)
  } else NA
  
  list(
    n = nrow(valid),
    accuracy = accuracy,
    precision = precision,
    recall = recall,
    f1_score = f1,
    confusion_matrix = matrix(c(tn, fp, fn, tp), nrow = 2,
                             dimnames = list(Predicted = c("No", "Yes"),
                                           Actual = c("No", "Yes")))
  )
}