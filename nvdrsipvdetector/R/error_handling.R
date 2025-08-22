#' Comprehensive Error Handling Utilities
#'
#' @description Functions for consistent error handling across the package
#' @keywords internal

#' Safe execution wrapper
#' 
#' @param expr Expression to execute safely
#' @param default Default value to return on error
#' @param quiet Whether to suppress error messages
#' @return Result or default value
#' @keywords internal
safe_execute <- function(expr, default = NULL, quiet = FALSE) {
  tryCatch(
    expr,
    error = function(e) {
      if (!quiet) {
        cli::cli_alert_warning("Error: {e$message}")
      }
      default
    },
    warning = function(w) {
      if (!quiet) {
        cli::cli_alert_info("Warning: {w$message}")
      }
      suppressWarnings(expr)
    }
  )
}

#' Validate required fields in data
#' 
#' @param data Data frame or tibble to validate
#' @param required_fields Character vector of required field names
#' @param context Context for error message
#' @return TRUE if valid, stops with error otherwise
#' @keywords internal
validate_required_fields <- function(data, required_fields, context = "data") {
  missing_fields <- setdiff(required_fields, names(data))
  if (length(missing_fields) > 0) {
    stop(
      cli::format_error(c(
        "Missing required fields in {context}",
        "x" = "Missing: {missing_fields}",
        "i" = "Required: {required_fields}"
      )),
      call. = FALSE
    )
  }
  TRUE
}

#' Retry operation with exponential backoff
#' 
#' @param expr Expression to retry
#' @param max_attempts Maximum number of attempts
#' @param initial_delay Initial delay in seconds
#' @param max_delay Maximum delay in seconds
#' @return Result of expression or error
#' @keywords internal
retry_with_backoff <- function(expr, max_attempts = 3, initial_delay = 1, max_delay = 30) {
  delay <- initial_delay
  
  for (attempt in seq_len(max_attempts)) {
    result <- tryCatch(
      {
        return(expr)
      },
      error = function(e) {
        if (attempt == max_attempts) {
          stop(e)
        }
        cli::cli_alert_info("Attempt {attempt}/{max_attempts} failed, retrying in {delay} seconds...")
        Sys.sleep(delay)
        delay <- min(delay * 2, max_delay)
        NULL
      }
    )
    
    if (!is.null(result)) {
      return(result)
    }
  }
}

#' Validate configuration structure
#' 
#' @param config Configuration list
#' @return TRUE if valid, stops with error otherwise
#' @keywords internal
validate_config <- function(config) {
  if (!is.list(config)) {
    stop("Configuration must be a list", call. = FALSE)
  }
  
  # Check API configuration
  if (is.null(config$api)) {
    stop("Configuration missing 'api' section", call. = FALSE)
  }
  
  if (is.null(config$api$base_url)) {
    stop("Configuration missing 'api.base_url'", call. = FALSE)
  }
  
  # Check processing configuration
  if (!is.null(config$processing)) {
    if (!is.null(config$processing$batch_size)) {
      if (!is.numeric(config$processing$batch_size) || config$processing$batch_size < 1) {
        stop("Invalid batch_size in configuration", call. = FALSE)
      }
    }
  }
  
  # Check weights configuration
  if (!is.null(config$weights)) {
    if (!is.null(config$weights$cme) && !is.null(config$weights$le)) {
      total_weight <- config$weights$cme + config$weights$le
      if (abs(total_weight - 1.0) > 0.001) {
        cli::cli_alert_warning("CME and LE weights sum to {total_weight}, expected 1.0")
      }
    }
  }
  
  TRUE
}

#' Create error response for API failures
#' 
#' @param error_message Error message
#' @param incident_id Optional incident ID
#' @param narrative_type Optional narrative type (LE/CME)
#' @return Standardized error response tibble
#' @keywords internal
create_error_response <- function(error_message, incident_id = NA, narrative_type = NA) {
  tibble::tibble(
    incident_id = incident_id,
    narrative_type = narrative_type,
    ipv_detected = NA,
    confidence = NA,
    indicators = list(character()),
    rationale = error_message,
    error = TRUE,
    timestamp = Sys.time()
  )
}

#' Log error with context
#' 
#' @param error Error object or message
#' @param context Context information
#' @param level Log level (error, warning, info)
#' @keywords internal
log_error <- function(error, context = NULL, level = "error") {
  error_msg <- if (inherits(error, "error")) error$message else as.character(error)
  
  if (!is.null(context)) {
    error_msg <- paste0(error_msg, " [Context: ", context, "]")
  }
  
  switch(level,
    error = cli::cli_alert_danger(error_msg),
    warning = cli::cli_alert_warning(error_msg),
    info = cli::cli_alert_info(error_msg),
    cli::cli_alert(error_msg)
  )
  
  # Also write to a log file if configured
  log_file <- Sys.getenv("NVDRS_LOG_FILE", "")
  if (nzchar(log_file)) {
    log_entry <- sprintf(
      "[%s] %s: %s\n",
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      toupper(level),
      error_msg
    )
    cat(log_entry, file = log_file, append = TRUE)
  }
}

#' Handle NA values consistently
#' 
#' @param value Value to check
#' @param default Default value if NA
#' @return Value or default
#' @keywords internal
handle_na <- function(value, default = NA) {
  if (is.null(value) || length(value) == 0 || all(is.na(value))) {
    return(default)
  }
  value
}