#' Repair Common JSON Errors in LLM Responses
#'
#' Fixes common JSON formatting errors that LLMs make, particularly
#' spelling out decimal numbers like "0. nine" instead of "0.9".
#' This is a safety net to catch responses that would otherwise fail parsing.
#'
#' @param json_text Character string containing potentially malformed JSON.
#'
#' @return Character string with repaired JSON.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Fix spelled-out decimal
#' repair_json('{"confidence": 0. nine}')
#' # Returns: '{"confidence": 0.9}'
#'
#' # Fix multiple errors
#' repair_json('{"detected": true, "confidence": 0. eight}')
#' # Returns: '{"detected": true, "confidence": 0.8}'
#' }
#'
repair_json <- function(json_text) {
  json_text |>
    stringr::str_replace_all("0\\.\\s*nine", "0.9") |>
    stringr::str_replace_all("0\\.\\s*eight", "0.8") |>
    stringr::str_replace_all("0\\.\\s*seven", "0.7") |>
    stringr::str_replace_all("0\\.\\s*six", "0.6") |>
    stringr::str_replace_all("0\\.\\s*five", "0.5") |>
    stringr::str_replace_all("0\\.\\s*four", "0.4") |>
    stringr::str_replace_all("0\\.\\s*three", "0.3") |>
    stringr::str_replace_all("0\\.\\s*two", "0.2") |>
    stringr::str_replace_all("0\\.\\s*one", "0.1") |>
    stringr::str_replace_all("0\\.\\s*zero", "0.0")
}
