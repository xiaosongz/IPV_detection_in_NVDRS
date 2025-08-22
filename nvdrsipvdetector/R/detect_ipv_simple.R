#' Simple IPV Detection Wrapper (Deprecated)
#'
#' @description 
#' This function is deprecated. Please use \code{\link{detect_ipv}} instead,
#' which now handles configuration and database connections automatically.
#' 
#' @param narrative Narrative text to analyze
#' @param narrative_type "LE" or "CME" 
#' @param log_to_db Whether to log API calls to database (default TRUE)
#' @return List with ipv_detected, confidence, indicators, and rationale
#' @export
#' @examples
#' \dontrun{
#' # Old way (deprecated):
#' result <- detect_ipv_simple("Domestic violence incident", "LE")
#' 
#' # New way (recommended):
#' result <- detect_ipv("Domestic violence incident", type = "LE")
#' }
detect_ipv_simple <- function(narrative, narrative_type = "LE", log_to_db = TRUE) {
  .Deprecated("detect_ipv", 
              package = "nvdrsipvdetector",
              msg = paste("detect_ipv_simple() is deprecated.",
                         "Please use detect_ipv() instead,",
                         "which now handles configuration automatically."))
  
  # Call the new unified function
  detect_ipv(narrative = narrative,
             type = narrative_type,
             config = NULL,  # Will auto-load
             conn = NULL,    # Will auto-create if needed
             log_to_db = log_to_db)
}