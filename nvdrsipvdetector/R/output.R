#' Export Functions
#'
#' @description Functions for exporting detection results
#' @keywords internal
NULL

#' Export Results (Modernized)
#'
#' @param results Tibble with detection results
#' @param file_path Path to output file
#' @param format Output format ("csv", "rds", "json")
#' @export
export_results <- function(results, file_path, format = "csv") {
  # Ensure results is a tibble
  results <- tibble::as_tibble(results)
  
  # Create directory if needed
  dir.create(dirname(file_path), recursive = TRUE, showWarnings = FALSE)
  
  # Export using pipeline approach
  export_func <- dplyr::case_when(
    format == "csv" ~ function(data, path) readr::write_csv(data, path),
    format == "rds" ~ function(data, path) saveRDS(data, path),
    format == "json" ~ function(data, path) {
      jsonlite::toJSON(data, pretty = TRUE, auto_unbox = TRUE) %>%
        writeLines(path)
    },
    TRUE ~ stop("Unsupported format: ", format)
  )
  
  # Perform export
  export_func(results, file_path)
  
  # Success message
  cli::cli_alert_success(
    "Exported {nrow(results)} results to {file_path} as {format}"
  )
  
  invisible(results)
}

#' Print Summary (Modernized)
#'
#' @param results Tibble with results
#' @export
print_summary <- function(results) {
  # Calculate summary statistics using dplyr
  summary_stats <- results %>%
    tibble::as_tibble() %>%
    dplyr::summarise(
      n_total = dplyr::n(),
      n_ipv = sum(ipv_detected, na.rm = TRUE),
      n_no_ipv = sum(!ipv_detected, na.rm = TRUE),
      n_na = sum(is.na(ipv_detected)),
      mean_confidence = if ("confidence" %in% names(results)) {
        mean(confidence, na.rm = TRUE)
      } else {
        NA_real_
      },
      .groups = "drop"
    )
  
  # Display using cli for better formatting
  cli::cli_h1("IPV Detection Summary")
  
  with(summary_stats, {
    cli::cli_alert_info("Total records: {n_total}")
    
    cli::cli_alert_success(
      "IPV detected: {n_ipv} ({scales::percent(n_ipv/n_total, accuracy = 0.1)})"
    )
    
    cli::cli_alert_info(
      "IPV not detected: {n_no_ipv} ({scales::percent(n_no_ipv/n_total, accuracy = 0.1)})"
    )
    
    if (n_na > 0) {
      cli::cli_alert_warning(
        "Unable to determine: {n_na} ({scales::percent(n_na/n_total, accuracy = 0.1)})"
      )
    }
    
    if (!is.na(mean_confidence)) {
      cli::cli_alert_info(
        "Mean confidence: {scales::percent(mean_confidence, accuracy = 0.1)}"
      )
    }
  })
  
  invisible(summary_stats)
}