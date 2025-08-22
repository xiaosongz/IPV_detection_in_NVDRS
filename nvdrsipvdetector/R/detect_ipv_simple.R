#' Simple IPV Detection Wrapper
#'
#' @description Simplified function that handles config and database automatically
#' @param narrative Narrative text to analyze
#' @param narrative_type "LE" or "CME" 
#' @param log_to_db Whether to log API calls to database (default TRUE)
#' @return List with ipv_detected, confidence, indicators, and rationale
#' @export
#' @examples
#' \dontrun{
#' result <- detect_ipv_simple("Domestic violence incident", "LE")
#' }
detect_ipv_simple <- function(narrative, narrative_type = "LE", log_to_db = TRUE) {
  # Load config from default location
  config_path <- system.file("settings.yml", package = "nvdrsipvdetector")
  if (config_path == "") {
    config_path <- "nvdrsipvdetector/config/settings.yml"
  }
  if (!file.exists(config_path)) {
    config_path <- "config/settings.yml"
  }
  
  config <- load_config(config_path)
  
  # Initialize database connection if logging
  conn <- NULL
  if (log_to_db) {
    conn <- init_database(config$database$path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)
  }
  
  # Detect IPV
  result <- detect_ipv(
    narrative = narrative,
    type = narrative_type,
    config = config,
    conn = conn
  )
  
  return(result)
}