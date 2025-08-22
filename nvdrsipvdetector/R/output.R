#' Export Functions
#'
#' @description Functions for exporting detection results
#' @keywords internal
NULL

#' Export Results
#'
#' @param results Data frame with detection results
#' @param file_path Path to output file
#' @param format Output format ("csv", "rds", "json")
#' @export
export_results <- function(results, file_path, format = "csv") {
  dir.create(dirname(file_path), recursive = TRUE, showWarnings = FALSE)
  
  if (format == "csv") {
    write.csv(results, file_path, row.names = FALSE)
  } else if (format == "rds") {
    saveRDS(results, file_path)
  } else if (format == "json") {
    json_output <- jsonlite::toJSON(results, pretty = TRUE, auto_unbox = TRUE)
    writeLines(json_output, file_path)
  } else {
    stop("Unsupported format: ", format)
  }
  
  cli::cli_alert_success(glue::glue("Exported {nrow(results)} results to {file_path}"))
}

#' Print Summary
#'
#' @param results Data frame with results
#' @export
print_summary <- function(results) {
  n_total <- nrow(results)
  n_ipv <- sum(results$ipv_detected, na.rm = TRUE)
  n_no_ipv <- sum(!results$ipv_detected, na.rm = TRUE)
  n_na <- sum(is.na(results$ipv_detected))
  
  cat("\n=== IPV Detection Summary ===\n")
  cat(sprintf("Total records: %d\n", n_total))
  cat(sprintf("IPV detected: %d (%.1f%%)\n", n_ipv, n_ipv/n_total * 100))
  cat(sprintf("IPV not detected: %d (%.1f%%)\n", n_no_ipv, n_no_ipv/n_total * 100))
  cat(sprintf("Unable to determine: %d (%.1f%%)\n", n_na, n_na/n_total * 100))
  
  if ("confidence" %in% names(results)) {
    mean_conf <- mean(results$confidence, na.rm = TRUE)
    cat(sprintf("Mean confidence: %.1f%%\n", mean_conf * 100))
  }
}