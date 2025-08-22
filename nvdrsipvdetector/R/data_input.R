#' Read and Validate CSV
#'
#' @description Functions for reading and validating NVDRS data
#' @keywords internal
NULL

#' Read NVDRS Data
#'
#' @param file_path Path to CSV file
#' @return Tibble with narratives
#' @export
read_nvdrs_data <- function(file_path) {
  if (!file.exists(file_path)) {
    stop("File not found: ", file_path)
  }
  
  # Read CSV using readr
  data <- readr::read_csv(file_path, show_col_types = FALSE)
  
  # Validate required columns
  required_cols <- c("IncidentID", "NarrativeLE", "NarrativeCME")
  missing_cols <- setdiff(required_cols, names(data))
  
  if (length(missing_cols) > 0) {
    stop("Missing required columns: ", paste(missing_cols, collapse = ", "))
  }
  
  # Clean and process data using tidyverse pipeline
  data <- data %>%
    # Clean narratives using stringr
    mutate(
      across(c(NarrativeLE, NarrativeCME), ~ stringr::str_trim(.x))
    ) %>%
    # Handle empty strings as NA
    mutate(
      across(c(NarrativeLE, NarrativeCME), ~ ifelse(.x == "", NA_character_, .x))
    ) %>%
    # Remove duplicate IncidentIDs, keeping first occurrence
    {if(any(duplicated(.$IncidentID))) {
      warning("Duplicate IncidentIDs found, keeping first occurrence")
      distinct(., IncidentID, .keep_all = TRUE)
    } else .}
  
  cli::cli_alert_success(glue::glue("Loaded {nrow(data)} records"))
  
  return(data)
}

#' Validate Input Data
#'
#' @param data Tibble to validate
#' @return Validated tibble
#' @export
validate_input_data <- function(data) {
  # Count records with no narratives before filtering
  n_removed <- data %>%
    filter(is.na(NarrativeLE) & is.na(NarrativeCME)) %>%
    nrow()
  
  # Remove rows with no narratives using tidyverse
  data <- data %>%
    filter(!is.na(NarrativeLE) | !is.na(NarrativeCME))
  
  if (n_removed > 0) {
    cli::cli_alert_warning(glue::glue("Removed {n_removed} records with no narratives"))
  }
  
  # Calculate summary statistics using dplyr
  summary_stats <- data %>%
    summarise(
      n_both = sum(!is.na(NarrativeLE) & !is.na(NarrativeCME)),
      n_le_only = sum(!is.na(NarrativeLE) & is.na(NarrativeCME)),
      n_cme_only = sum(is.na(NarrativeLE) & !is.na(NarrativeCME))
    )
  
  cli::cli_alert_info(glue::glue(
    "Both narratives: {summary_stats$n_both}, LE only: {summary_stats$n_le_only}, CME only: {summary_stats$n_cme_only}"
  ))
  
  return(data)
}

#' Split Data into Batches
#'
#' @param data Tibble to split
#' @param batch_size Size of each batch
#' @return List of tibbles
#' @export
split_into_batches <- function(data, batch_size = 50) {
  # Add batch numbers using dplyr and split using purrr
  data %>%
    mutate(
      batch_id = ceiling(row_number() / batch_size)
    ) %>%
    group_split(batch_id) %>%
    map(~ select(.x, -batch_id))
}