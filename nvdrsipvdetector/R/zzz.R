# R/zzz.R - Package initialization
#' @import DBI
#' @importFrom dplyr %>% mutate select case_when group_split bind_rows row_number summarise filter count n across distinct
#' @importFrom purrr map map_lgl map_dbl safely
#' @importFrom tidyr everything pivot_wider
#' @importFrom tibble as_tibble tibble
#' @importFrom httr2 request req_body_json req_perform resp_body_json req_timeout req_retry
#' @importFrom jsonlite parse_json toJSON
#' @importFrom cli cli_progress_bar cli_alert_warning cli_alert_success cli_alert_info cli_progress_update cli_h1 cli_h2 cli_text cli_alert_danger format_error
#' @importFrom readr read_csv write_csv
#' @importFrom stringr str_trim str_replace_all
#' @importFrom glue glue
#' @importFrom yaml yaml.load
#' @importFrom rlang %||%
#' @importFrom scales percent
NULL

# Global variables to avoid R CMD check NOTEs
utils::globalVariables(c(
  "batch_id", "NarrativeLE", "NarrativeCME", 
  "le_result", "cme_result", "le_ipv", "cme_ipv",
  "le_confidence", "cme_confidence", "confidence", "ipv_detected",
  "predicted", "actual", "true_positive", "true_negative", "false_positive", "false_negative",
  "IncidentID", ".", "across", "distinct"
))

# NEVER use library() calls
# ALWAYS use pkg::function() or @importFrom

.onLoad <- function(libname, pkgname) {
  # Package startup message
  invisible()
}