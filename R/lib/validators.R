# Validation Helpers
# Input validation, output validation, and data quality checks

library(glue)

#' Validate input narratives
#' @param narratives Vector of narrative texts
#' @param min_length Minimum narrative length
#' @param max_length Maximum narrative length
#' @return List with validation results
#' @export
validate_narratives <- function(narratives, 
                              min_length = 10, 
                              max_length = 10000) {
  results <- list(
    valid = TRUE,
    issues = list(),
    stats = list(
      total = length(narratives),
      valid = 0,
      empty = 0,
      too_short = 0,
      too_long = 0
    )
  )
  
  # Check each narrative
  for (i in seq_along(narratives)) {
    narrative <- narratives[i]
    
    # Check for NA or empty
    if (is.na(narrative) || narrative == "") {
      results$stats$empty <- results$stats$empty + 1
      results$issues[[length(results$issues) + 1]] <- list(
        index = i,
        type = "empty",
        message = "Narrative is NA or empty"
      )
      next
    }
    
    # Check length
    char_count <- nchar(narrative)
    
    if (char_count < min_length) {
      results$stats$too_short <- results$stats$too_short + 1
      results$issues[[length(results$issues) + 1]] <- list(
        index = i,
        type = "too_short",
        message = glue("Narrative too short ({char_count} chars, min {min_length})")
      )
    } else if (char_count > max_length) {
      results$stats$too_long <- results$stats$too_long + 1
      results$issues[[length(results$issues) + 1]] <- list(
        index = i,
        type = "too_long",
        message = glue("Narrative too long ({char_count} chars, max {max_length})")
      )
    } else {
      results$stats$valid <- results$stats$valid + 1
    }
  }
  
  # Set overall validity
  results$valid <- length(results$issues) == 0
  
  return(results)
}

#' Validate API response structure
#' @param response Response data frame
#' @param expected_count Expected number of results
#' @return List with validation results
#' @export
validate_api_response <- function(response, expected_count = NULL) {
  results <- list(
    valid = TRUE,
    errors = character()
  )
  
  # Check if response is a data frame
  if (!is.data.frame(response)) {
    results$valid <- FALSE
    results$errors <- c(results$errors, "Response is not a data frame")
    return(results)
  }
  
  # Check required fields
  required_fields <- c(
    "sequence", "rationale", "key_facts_summary",
    "family_friend_mentioned", "intimate_partner_mentioned",
    "violence_mentioned", "substance_abuse_mentioned",
    "ipv_between_intimate_partners"
  )
  
  missing_fields <- setdiff(required_fields, names(response))
  if (length(missing_fields) > 0) {
    results$valid <- FALSE
    results$errors <- c(results$errors, 
                       glue("Missing required fields: {paste(missing_fields, collapse = ', ')}"))
  }
  
  # Check row count
  if (!is.null(expected_count) && nrow(response) != expected_count) {
    results$valid <- FALSE
    results$errors <- c(results$errors,
                       glue("Expected {expected_count} rows, got {nrow(response)}"))
  }
  
  # Validate field values
  if ("sequence" %in% names(response)) {
    if (!all(is.numeric(response$sequence) | is.integer(response$sequence))) {
      results$valid <- FALSE
      results$errors <- c(results$errors, "Sequence field must be numeric")
    }
  }
  
  # Validate categorical fields
  categorical_fields <- c(
    "family_friend_mentioned", "intimate_partner_mentioned",
    "violence_mentioned", "substance_abuse_mentioned",
    "ipv_between_intimate_partners"
  )
  
  valid_values <- c("yes", "no", "unclear", "skipped_na", "api_or_parse_error")
  
  for (field in categorical_fields) {
    if (field %in% names(response)) {
      invalid_values <- unique(response[[field]][!(response[[field]] %in% valid_values)])
      if (length(invalid_values) > 0) {
        results$valid <- FALSE
        results$errors <- c(results$errors,
                           glue("Invalid values in {field}: {paste(invalid_values, collapse = ', ')}"))
      }
    }
  }
  
  return(results)
}

#' Validate output data quality
#' @param data Output data frame
#' @param config Quality configuration
#' @return List with validation results and quality metrics
#' @export
validate_output_quality <- function(data, config = list()) {
  results <- list(
    valid = TRUE,
    warnings = character(),
    metrics = list()
  )
  
  # Check for required output fields
  required_fields <- config$required_fields %||% c("IncidentID")
  missing_fields <- setdiff(required_fields, names(data))
  
  if (length(missing_fields) > 0) {
    results$valid <- FALSE
    results$warnings <- c(results$warnings,
                         glue("Missing required output fields: {paste(missing_fields, collapse = ', ')}"))
  }
  
  # Calculate completeness metrics
  ipv_fields <- grep("ipv_between_intimate_partners", names(data), value = TRUE)
  
  for (field in ipv_fields) {
    if (field %in% names(data)) {
      total <- nrow(data)
      valid_responses <- sum(data[[field]] %in% c("yes", "no", "unclear"))
      completeness <- valid_responses / total
      
      results$metrics[[paste0(field, "_completeness")]] <- completeness
      
      if (completeness < 0.95) {
        results$warnings <- c(results$warnings,
                             glue("{field} completeness is {round(completeness * 100, 1)}%"))
      }
    }
  }
  
  # Check for consistency between CME and LE
  if (all(c("ipv_between_intimate_partners_CME", "ipv_between_intimate_partners_LE") %in% names(data))) {
    consistent <- sum(
      data$ipv_between_intimate_partners_CME == data$ipv_between_intimate_partners_LE,
      na.rm = TRUE
    )
    total_comparable <- sum(
      !is.na(data$ipv_between_intimate_partners_CME) & 
      !is.na(data$ipv_between_intimate_partners_LE)
    )
    
    if (total_comparable > 0) {
      consistency_rate <- consistent / total_comparable
      results$metrics$cme_le_consistency <- consistency_rate
      
      if (consistency_rate < 0.8) {
        results$warnings <- c(results$warnings,
                             glue("CME/LE consistency is {round(consistency_rate * 100, 1)}%"))
      }
    }
  }
  
  # Flag low confidence results
  if (config$flag_low_confidence %||% TRUE) {
    unclear_cols <- grep("_between_intimate_partners", names(data), value = TRUE)
    
    for (col in unclear_cols) {
      unclear_rate <- sum(data[[col]] == "unclear", na.rm = TRUE) / nrow(data)
      results$metrics[[paste0(col, "_unclear_rate")]] <- unclear_rate
      
      if (unclear_rate > 0.2) {
        results$warnings <- c(results$warnings,
                             glue("{col} has {round(unclear_rate * 100, 1)}% unclear responses"))
      }
    }
  }
  
  return(results)
}

#' Validate configuration object
#' @param config Configuration list
#' @param schema Expected schema (optional)
#' @return TRUE if valid, error otherwise
#' @export
validate_config <- function(config, schema = NULL) {
  if (!is.list(config)) {
    stop("Configuration must be a list")
  }
  
  # If no schema provided, do basic validation
  if (is.null(schema)) {
    # Check for main sections
    expected_sections <- c("api", "processing", "cache", "logging")
    missing_sections <- setdiff(expected_sections, names(config))
    
    if (length(missing_sections) > 0) {
      warning(glue("Configuration missing sections: {paste(missing_sections, collapse = ', ')}"))
    }
    
    return(TRUE)
  }
  
  # Validate against schema
  # TODO: Implement schema validation
  
  return(TRUE)
}

#' Create validation report
#' @param validation_results List of validation results
#' @param output_file Optional file path to save report
#' @return Formatted validation report
#' @export
create_validation_report <- function(validation_results, output_file = NULL) {
  report <- character()
  
  report <- c(report, "IPV Detection Validation Report")
  report <- c(report, paste(rep("=", 50), collapse = ""))
  report <- c(report, paste("Generated:", Sys.time()))
  report <- c(report, "")
  
  # Input validation
  if (!is.null(validation_results$input)) {
    report <- c(report, "Input Validation")
    report <- c(report, paste(rep("-", 30), collapse = ""))
    
    stats <- validation_results$input$stats
    report <- c(report, glue("Total narratives: {stats$total}"))
    report <- c(report, glue("Valid: {stats$valid} ({round(stats$valid/stats$total*100, 1)}%)"))
    report <- c(report, glue("Empty: {stats$empty}"))
    report <- c(report, glue("Too short: {stats$too_short}"))
    report <- c(report, glue("Too long: {stats$too_long}"))
    report <- c(report, "")
  }
  
  # Output validation
  if (!is.null(validation_results$output)) {
    report <- c(report, "Output Quality")
    report <- c(report, paste(rep("-", 30), collapse = ""))
    
    metrics <- validation_results$output$metrics
    for (metric in names(metrics)) {
      value <- metrics[[metric]]
      if (is.numeric(value)) {
        report <- c(report, glue("{metric}: {round(value * 100, 1)}%"))
      }
    }
    
    if (length(validation_results$output$warnings) > 0) {
      report <- c(report, "")
      report <- c(report, "Warnings:")
      for (warning in validation_results$output$warnings) {
        report <- c(report, paste("  -", warning))
      }
    }
    report <- c(report, "")
  }
  
  # Join report lines
  report_text <- paste(report, collapse = "\n")
  
  # Save if output file specified
  if (!is.null(output_file)) {
    writeLines(report_text, output_file)
  }
  
  return(report_text)
}