#' Parse LLM API Response
#'
#' Extracts structured data from the raw response returned by \code{call_llm()}.
#' Handles various response formats including malformed JSON, special tokens,
#' and error responses. Returns a standardized list structure suitable for
#' database storage and analysis.
#'
#' @param llm_response A list containing the raw response from \code{call_llm()}.
#'   Expected to have structure with choices, usage, model, etc.
#' @param narrative_id Optional character string. An identifier for the narrative
#'   being analyzed. Used for tracking and database storage.
#' @param metadata Optional list. Additional metadata to include in the parsed
#'   result (e.g., batch_id, user_id, processing_date).
#'
#' @return A list with standardized structure containing:
#'   \describe{
#'     \item{detected}{Logical. TRUE if IPV detected, FALSE if not, NA if parsing failed}
#'     \item{confidence}{Numeric. Confidence score 0.0-1.0, NA if not available}
#'     \item{model}{Character. The model used for generation}
#'     \item{created_at}{Character. ISO timestamp from the response}
#'     \item{response_id}{Character. Unique identifier for this completion}
#'     \item{tokens_used}{Integer. Total tokens consumed}
#'     \item{prompt_tokens}{Integer. Tokens in the prompt}
#'     \item{completion_tokens}{Integer. Tokens in the completion}
#'     \item{response_time_ms}{Numeric. Response time if available}
#'     \item{narrative_id}{Character. User-provided narrative identifier}
#'     \item{narrative_length}{Integer. Length of input narrative if available}
#'     \item{parse_error}{Logical. TRUE if JSON parsing failed}
#'     \item{error_message}{Character. Error details if any}
#'     \item{raw_response}{Character. Original response content for debugging}
#'     \item{metadata}{List. Additional user-provided metadata}
#'   }
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Parse a successful response
#' response <- call_llm("Analyze this text", "System prompt")
#' parsed <- parse_llm_result(response)
#' 
#' # With narrative ID and metadata
#' parsed <- parse_llm_result(
#'   response, 
#'   narrative_id = "case_123",
#'   metadata = list(batch = "2025-01", source = "NVDRS")
#' )
#' 
#' # Check for errors
#' if (parsed$parse_error) {
#'   warning(paste("Parse failed:", parsed$error_message))
#' }
#' }
#'
#' @seealso \code{\link{call_llm}} for making API calls
#'
parse_llm_result <- function(llm_response, narrative_id = NULL, metadata = NULL) {
  
  # Initialize result structure with defaults
  result <- list(
    detected = NA,
    confidence = NA_real_,
    model = NA_character_,
    created_at = NA_character_,
    response_id = NA_character_,
    tokens_used = NA_integer_,
    prompt_tokens = NA_integer_,
    completion_tokens = NA_integer_,
    response_time_ms = NA_real_,
    narrative_id = narrative_id,
    narrative_length = NA_integer_,
    parse_error = FALSE,
    error_message = NA_character_,
    raw_response = NA_character_,
    metadata = metadata
  )
  
  # Validate input
  if (is.null(llm_response)) {
    result$parse_error <- TRUE
    result$error_message <- "Response is NULL"
    return(result)
  }
  
  if (!is.list(llm_response)) {
    result$parse_error <- TRUE
    result$error_message <- "Response is not a list"
    return(result)
  }
  
  # Check for API error response
  if (!is.null(llm_response$error)) {
    result$parse_error <- TRUE
    result$error_message <- if (is.character(llm_response$error_message)) {
      llm_response$error_message
    } else {
      "API error occurred"
    }
    return(result)
  }
  
  # Extract basic metadata
  if (!is.null(llm_response$model)) {
    result$model <- as.character(llm_response$model)
  }
  
  if (!is.null(llm_response$id)) {
    result$response_id <- as.character(llm_response$id)
  }
  
  if (!is.null(llm_response$created)) {
    # Convert Unix timestamp to ISO format
    if (is.numeric(llm_response$created)) {
      result$created_at <- format(
        as.POSIXct(llm_response$created, origin = "1970-01-01", tz = "UTC"),
        "%Y-%m-%dT%H:%M:%SZ"
      )
    } else {
      result$created_at <- as.character(llm_response$created)
    }
  }
  
  # Extract token usage
  if (!is.null(llm_response$usage)) {
    if (!is.null(llm_response$usage$total_tokens)) {
      result$tokens_used <- as.integer(llm_response$usage$total_tokens)
    }
    if (!is.null(llm_response$usage$prompt_tokens)) {
      result$prompt_tokens <- as.integer(llm_response$usage$prompt_tokens)
    }
    if (!is.null(llm_response$usage$completion_tokens)) {
      result$completion_tokens <- as.integer(llm_response$usage$completion_tokens)
    }
  }
  
  # Extract response time if available in test metadata
  if (!is.null(llm_response$test_metadata)) {
    if (!is.null(llm_response$test_metadata$elapsed_seconds)) {
      result$response_time_ms <- llm_response$test_metadata$elapsed_seconds * 1000
    }
    if (!is.null(llm_response$test_metadata$prompt_length)) {
      result$narrative_length <- as.integer(llm_response$test_metadata$prompt_length)
    }
  }
  
  # Extract and parse the actual response content
  content <- NULL
  
  # Navigate to the message content
  if (!is.null(llm_response$choices) && length(llm_response$choices) > 0) {
    first_choice <- llm_response$choices[[1]]
    if (!is.null(first_choice$message) && !is.null(first_choice$message$content)) {
      content <- first_choice$message$content
      result$raw_response <- content
    }
  }
  
  # If no content found, mark as error
  if (is.null(content) || content == "") {
    result$parse_error <- TRUE
    result$error_message <- "No content in response"
    return(result)
  }
  
  # Clean content from special tokens used by some models
  # Remove tokens like <|channel|>, <|constrain|>, <|message|>
  cleaned_content <- gsub("<\\|[^|]+\\|>", "", content)
  cleaned_content <- trimws(cleaned_content)
  
  # Try to parse as JSON
  parsed_json <- NULL
  
  # First attempt: direct JSON parsing
  if (!result$parse_error) {
    parsed_json <- tryCatch({
      jsonlite::fromJSON(cleaned_content, simplifyVector = FALSE)
    }, error = function(e) {
      # Try to extract JSON from mixed content
      # Look for JSON-like structure {...}
      json_match <- regmatches(
        cleaned_content,
        regexpr("\\{[^{}]*\\}", cleaned_content, perl = TRUE)
      )
      
      if (length(json_match) > 0) {
        tryCatch({
          jsonlite::fromJSON(json_match[1], simplifyVector = FALSE)
        }, error = function(e2) {
          NULL
        })
      } else {
        NULL
      }
    })
  }
  
  # Extract IPV detection results if JSON was parsed
  if (!is.null(parsed_json)) {
    # Check for detected field
    if (!is.null(parsed_json$detected)) {
      result$detected <- as.logical(parsed_json$detected)
    }
    
    # Check for confidence field
    if (!is.null(parsed_json$confidence)) {
      conf_value <- as.numeric(parsed_json$confidence)
      if (!is.na(conf_value) && conf_value >= 0 && conf_value <= 1) {
        result$confidence <- conf_value
      }
    }
    
    # Store any additional fields in metadata if not already provided
    extra_fields <- setdiff(names(parsed_json), c("detected", "confidence"))
    if (length(extra_fields) > 0) {
      if (is.null(result$metadata)) {
        result$metadata <- list()
      }
      for (field in extra_fields) {
        result$metadata[[paste0("llm_", field)]] <- parsed_json[[field]]
      }
    }
  } else {
    # JSON parsing failed
    result$parse_error <- TRUE
    result$error_message <- "Failed to parse JSON from response content"
    
    # Try to extract detection result from text patterns as fallback
    content_lower <- tolower(cleaned_content)
    
    # Check for clear positive/negative indicators
    if (grepl("\"detected\"\\s*:\\s*true", content_lower)) {
      result$detected <- TRUE
    } else if (grepl("\"detected\"\\s*:\\s*false", content_lower)) {
      result$detected <- FALSE
    }
    
    # Try to extract confidence
    conf_match <- regmatches(
      content_lower,
      regexpr("\"confidence\"\\s*:\\s*[0-9.]+", content_lower)
    )
    if (length(conf_match) > 0) {
      conf_value <- as.numeric(gsub("[^0-9.]", "", conf_match[1]))
      if (!is.na(conf_value) && conf_value >= 0 && conf_value <= 1) {
        result$confidence <- conf_value
      }
    }
  }
  
  return(result)
}