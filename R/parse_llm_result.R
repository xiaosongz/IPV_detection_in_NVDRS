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
#' @return A single-row tibble with standardized structure containing:
#'   \describe{
#'     \item{detected}{Logical. TRUE if IPV detected, FALSE if not, NA if parsing failed}
#'     \item{confidence}{Numeric. Confidence score 0.0-1.0, NA if not available}
#'     \item{indicators}{List. Array of indicator tokens from the vocabulary}
#'     \item{rationale}{Character. Concise justification for the detection}
#'     \item{reasoning}{Character. Model's reasoning/thinking process if available}
#'     \item{model}{Character. The model used for generation}
#'     \item{created_at}{Character. ISO timestamp from the response}
#'     \item{response_id}{Character. Unique identifier for this completion}
#'     \item{tokens_used}{Integer. Total tokens consumed}
#'     \item{prompt_tokens}{Integer. Tokens in the prompt}
#'     \item{completion_tokens}{Integer. Tokens in the completion}
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
  # Define NULL-safe extraction operator
  `%||%` <- function(x, y) if (is.null(x)) y else x

  # Initialize result structure
  result <- initialize_parse_result(narrative_id, metadata)

  # Validate input
  validation_error <- validate_llm_response(llm_response)
  if (!is.null(validation_error)) {
    result <- set_parse_error(result, validation_error)
    return(convert_to_tibble_row(result))
  }

  # Extract all metadata components
  result <- result |>
    extract_response_metadata(llm_response) |>
    extract_usage_metadata(llm_response)

  # Extract reasoning if present
  reasoning <- extract_reasoning(llm_response)
  if (!is.null(reasoning)) {
    result$reasoning <- reasoning
  }

  # Extract and parse content
  content <- extract_response_content(llm_response)
  if (is.null(content)) {
    result <- set_parse_error(result, "No content in response")
    return(convert_to_tibble_row(result))
  }

  result$raw_response <- content

  # Parse IPV detection results
  result <- parse_ipv_content(result, content)
  
  # Convert to single-row tibble
  convert_to_tibble_row(result)
}

# Helper: Initialize result structure
initialize_parse_result <- function(narrative_id, metadata) {
  list(
    detected = NA,
    confidence = NA_real_,
    indicators = list(NULL),  # List column for array of indicators
    rationale = NA_character_,
    reasoning = NA_character_,  # Reasoning field right after rationale
    model = NA_character_,
    created_at = NA_character_,
    response_id = NA_character_,
    tokens_used = NA_integer_,
    prompt_tokens = NA_integer_,
    completion_tokens = NA_integer_,
    narrative_id = if (is.null(narrative_id)) NA_character_ else as.character(narrative_id),
    parse_error = FALSE,
    error_message = NA_character_,
    raw_response = NA_character_
  )
}

# Helper: Validate response structure
validate_llm_response <- function(response) {
  if (is.null(response)) {
    return("Response is NULL")
  }

  if (!is.list(response)) {
    return("Response is not a list")
  }

  if (!is.null(response$error)) {
    return(response$error_message %||% "API error occurred")
  }

  NULL
}

# Helper: Set parse error
set_parse_error <- function(result, message) {
  result$parse_error <- TRUE
  result$error_message <- message
  result
}

# Helper: Safe field extraction with type conversion
safe_extract <- function(obj, path, converter = as.character, default = NA) {
  value <- obj
  for (key in path) {
    value <- value[[key]]
    if (is.null(value)) return(default)
  }
  tryCatch(converter(value), error = function(e) default)
}

# Helper: Extract response metadata
extract_response_metadata <- function(result, response) {
  result$model <- safe_extract(response, "model")
  result$response_id <- safe_extract(response, "id")

  # Handle created timestamp
  created <- response$created
  if (!is.null(created)) {
    result$created_at <- if (is.numeric(created)) {
      format(
        as.POSIXct(created, origin = "1970-01-01", tz = "UTC"),
        "%Y-%m-%dT%H:%M:%SZ"
      )
    } else {
      as.character(created)
    }
  }

  result
}

# Helper: Extract usage metadata
extract_usage_metadata <- function(result, response) {
  usage <- response$usage
  if (!is.null(usage)) {
    result$tokens_used <- safe_extract(
      usage, "total_tokens", as.integer, NA_integer_
    )
    result$prompt_tokens <- safe_extract(
      usage, "prompt_tokens", as.integer, NA_integer_
    )
    result$completion_tokens <- safe_extract(
      usage, "completion_tokens", as.integer, NA_integer_
    )
  }
  result
}

# Helper: Extract response content
extract_response_content <- function(response) {
  # Navigate to message content
  choices <- response$choices
  if (is.null(choices) || length(choices) == 0) {
    return(NULL)
  }

  first_choice <- choices[[1]]
  message <- first_choice$message
  if (is.null(message)) {
    return(NULL)
  }

  content <- message$content
  if (is.null(content) || content == "") {
    return(NULL)
  }

  content
}

# Helper: Extract reasoning from response
extract_reasoning <- function(response) {
  choices <- response$choices
  if (is.null(choices) || length(choices) == 0) {
    return(NULL)
  }
  
  first_choice <- choices[[1]]
  message <- first_choice$message
  if (is.null(message)) {
    return(NULL)
  }
  
  reasoning <- message$reasoning
  if (is.null(reasoning) || reasoning == "") {
    return(NULL)
  }
  
  trimws(reasoning)
}

# Helper: Clean content from special tokens
clean_llm_content <- function(content) {
  content |>
    stringr::str_remove_all("<\\|[^|]+\\|>") |>
    trimws()
}

# Helper: Extract JSON from content
extract_json_from_content <- function(content) {
  # Repair common LLM JSON errors before parsing
  repaired_content <- repair_json(content)
  
  # First try: direct parsing
  json_result <- tryCatch(
    jsonlite::fromJSON(repaired_content, simplifyVector = FALSE),
    error = function(e) NULL
  )

  if (!is.null(json_result)) {
    return(json_result)
  }

  # Second try: extract JSON objects from mixed content
  json_patterns <- stringr::str_extract_all(
    repaired_content,
    "\\{(?:[^{}]|\\{[^{}]*\\})*\\}"
  )[[1]]

  for (pattern in json_patterns) {
    json_result <- tryCatch(
      jsonlite::fromJSON(pattern, simplifyVector = FALSE),
      error = function(e) NULL
    )
    if (!is.null(json_result)) {
      return(json_result)
    }
  }

  NULL
}

# Helper: Extract IPV from text patterns (fallback)
extract_ipv_from_text <- function(content) {
  content_lower <- tolower(content)

  list(
    detected = dplyr::case_when(
      stringr::str_detect(content_lower, "\"detected\"\\s*:\\s*true") ~ TRUE,
      stringr::str_detect(content_lower, "\"detected\"\\s*:\\s*false") ~ FALSE,
      TRUE ~ NA
    ),
    confidence = extract_confidence_from_text(content_lower)
  )
}

# Helper: Extract confidence from text
extract_confidence_from_text <- function(content_lower) {
  conf_match <- stringr::str_extract(
    content_lower,
    "\"confidence\"\\s*:\\s*[0-9.]+"
  )

  if (is.na(conf_match)) {
    return(NA_real_)
  }

  conf_value <- as.numeric(
    stringr::str_extract(conf_match, "[0-9.]+")
  )

  if (!is.na(conf_value) && conf_value >= 0 && conf_value <= 1) {
    return(conf_value)
  }

  NA_real_
}

# Helper: Parse IPV content
parse_ipv_content <- function(result, content) {
  cleaned_content <- clean_llm_content(content)
  parsed_json <- extract_json_from_content(cleaned_content)

  if (!is.null(parsed_json)) {
    # Successfully parsed JSON
    result <- extract_ipv_from_json(result, parsed_json)
  } else {
    # Fallback to text pattern extraction
    result$parse_error <- TRUE
    result$error_message <- "Failed to parse JSON from response content"

    text_extraction <- extract_ipv_from_text(cleaned_content)
    result$detected <- text_extraction$detected
    result$confidence <- text_extraction$confidence
  }

  result
}

# Helper: Extract IPV data from parsed JSON
extract_ipv_from_json <- function(result, parsed_json) {
  # Extract core fields
  if (!is.null(parsed_json$detected)) {
    result$detected <- as.logical(parsed_json$detected)
  }

  if (!is.null(parsed_json$confidence)) {
    conf_value <- as.numeric(parsed_json$confidence)
    if (!is.na(conf_value) && conf_value >= 0 && conf_value <= 1) {
      result$confidence <- conf_value
    }
  }

  # Extract indicators array
  if (!is.null(parsed_json$indicators)) {
    result$indicators <- list(parsed_json$indicators)
  }

  # Extract rationale
  if (!is.null(parsed_json$rationale)) {
    result$rationale <- as.character(parsed_json$rationale)
  }

  result
}

# Helper: Convert result to tibble row
convert_to_tibble_row <- function(result) {
  # Ensure list columns are properly wrapped
  if (!is.null(result$indicators) && !is.list(result$indicators)) {
    result$indicators <- list(result$indicators)
  }

  tibble::as_tibble_row(result)
}
