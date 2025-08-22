# tests/testthat/fixtures/mock_responses.R

#' Standard Mock LLM Response
mock_llm_response <- function(ipv_detected = TRUE, confidence = 0.85) {
  list(
    ipv_detected = ipv_detected,
    confidence = confidence,
    indicators = if(ipv_detected) c("domestic", "ex-boyfriend") else character(0),
    rationale = "Mock response for testing",
    success = TRUE
  )
}

#' Mock Malformed JSON Response
mock_malformed_json <- function() {
  list(
    ipv_detected = NA,
    confidence = NA,
    indicators = character(0),
    rationale = "Parse error: malformed JSON",
    success = FALSE
  )
}

#' Mock API Timeout Response
mock_timeout_response <- function() {
  list(
    ipv_detected = NA,
    confidence = NA,
    indicators = character(0),
    rationale = "Request timeout after 30 seconds",
    success = FALSE
  )
}

#' Mock Empty Response
mock_empty_response <- function() {
  list(
    ipv_detected = NA,
    confidence = NA,
    indicators = character(0),
    rationale = "Empty response from API",
    success = FALSE
  )
}

#' Mock High Confidence IPV Detection
mock_high_confidence_ipv <- function() {
  list(
    ipv_detected = TRUE,
    confidence = 0.95,
    indicators = c("domestic violence", "strangulation", "controlling behavior"),
    rationale = "Strong indicators of intimate partner violence present",
    success = TRUE
  )
}

#' Mock Low Confidence Non-IPV
mock_low_confidence_non_ipv <- function() {
  list(
    ipv_detected = FALSE,
    confidence = 0.15,
    indicators = character(0),
    rationale = "No clear indicators of IPV in narrative",
    success = TRUE
  )
}

#' Mock Conflicting LE/CME Results
mock_conflicting_results <- function() {
  list(
    le = list(
      ipv_detected = TRUE,
      confidence = 0.8,
      indicators = c("domestic dispute"),
      rationale = "LE narrative suggests IPV",
      success = TRUE
    ),
    cme = list(
      ipv_detected = FALSE,
      confidence = 0.6,
      indicators = character(0),
      rationale = "CME findings inconclusive for IPV",
      success = TRUE
    )
  )
}

#' Mock Database Connection Error
mock_db_error <- function() {
  structure(
    list(message = "database is locked"),
    class = c("simpleError", "error", "condition")
  )
}

#' Mock Network Connection Error
mock_network_error <- function() {
  structure(
    list(message = "Could not resolve host: 192.168.10.22"),
    class = c("simpleError", "error", "condition")
  )
}