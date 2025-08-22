#' Read and Validate CSV
#'
#' @description Functions for reading and validating NVDRS data
#' @keywords internal
NULL

#' Read NVDRS Data
#'
#' @param file_path Path to CSV file
#' @return Data frame with narratives
#' @export
read_nvdrs_data <- function(file_path) {
  if (!file.exists(file_path)) {
    stop("File not found: ", file_path)
  }
  
  # Read CSV
  data <- read.csv(file_path, stringsAsFactors = FALSE)
  
  # Validate required columns
  required_cols <- c("IncidentID", "NarrativeLE", "NarrativeCME")
  missing_cols <- setdiff(required_cols, names(data))
  
  if (length(missing_cols) > 0) {
    stop("Missing required columns: ", paste(missing_cols, collapse = ", "))
  }
  
  # Clean narratives with trimws
  data$NarrativeLE <- trimws(data$NarrativeLE)
  data$NarrativeCME <- trimws(data$NarrativeCME)
  
  # Handle empty strings as NA
  data$NarrativeLE[data$NarrativeLE == ""] <- NA
  data$NarrativeCME[data$NarrativeCME == ""] <- NA
  
  # Check for duplicate IncidentIDs
  if (any(duplicated(data$IncidentID))) {
    warning("Duplicate IncidentIDs found, keeping first occurrence")
    data <- data[!duplicated(data$IncidentID), ]
  }
  
  cli::cli_alert_success(glue::glue("Loaded {nrow(data)} records"))
  
  return(data)
}

#' Validate Input Data
#'
#' @param data Data frame to validate
#' @return Validated data frame
#' @export
validate_input_data <- function(data) {
  # Remove rows with no narratives
  has_narrative <- !is.na(data$NarrativeLE) | !is.na(data$NarrativeCME)
  n_removed <- sum(!has_narrative)
  
  if (n_removed > 0) {
    cli::cli_alert_warning(glue::glue("Removed {n_removed} records with no narratives"))
    data <- data[has_narrative, ]
  }
  
  # Report summary
  n_both <- sum(!is.na(data$NarrativeLE) & !is.na(data$NarrativeCME))
  n_le_only <- sum(!is.na(data$NarrativeLE) & is.na(data$NarrativeCME))
  n_cme_only <- sum(is.na(data$NarrativeLE) & !is.na(data$NarrativeCME))
  
  cli::cli_alert_info(glue::glue("Both narratives: {n_both}, LE only: {n_le_only}, CME only: {n_cme_only}"))
  
  return(data)
}

#' Split Data into Batches
#'
#' @param data Data frame
#' @param batch_size Size of each batch
#' @return List of data frames
#' @export
split_into_batches <- function(data, batch_size = 50) {
  n_batches <- ceiling(nrow(data) / batch_size)
  batches <- vector("list", n_batches)
  
  for (i in seq_len(n_batches)) {
    start_idx <- (i - 1) * batch_size + 1
    end_idx <- min(i * batch_size, nrow(data))
    batches[[i]] <- data[start_idx:end_idx, ]
  }
  
  return(batches)
}