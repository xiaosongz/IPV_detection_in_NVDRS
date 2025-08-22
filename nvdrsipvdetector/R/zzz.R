# R/zzz.R - Package initialization
#' @import DBI
#' @importFrom httr2 request req_body_json req_perform resp_body_json
#' @importFrom jsonlite parse_json toJSON
#' @importFrom cli cli_progress_bar cli_alert_warning
#' @importFrom utils read.csv write.csv
NULL

# NEVER use library() calls
# ALWAYS use pkg::function() or @importFrom