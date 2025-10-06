#' Load Source Data into Database
#'
#' Loads Excel file into source_narratives table for efficient querying
#'
#' @param conn Database connection
#' @param excel_path Path to Excel file
#' @param force_reload If TRUE, delete existing data and reload
#' @return Number of narratives loaded
#' @export
#' @examples
#' \dontrun{
#' # Load NVDRS data from Excel file
#' conn <- get_db_connection()
#' n_loaded <- load_source_data(conn, "data/nvdrs_narratives.xlsx")
#' cat("Loaded", n_loaded, "narratives\n")
#'
#' # Check if data already loaded
#' if (!check_data_loaded(conn, "data/nvdrs_narratives.xlsx")) {
#'   load_source_data(conn, "data/nvdrs_narratives.xlsx")
#' }
#'
#' # Force reload existing data
#' n_reloaded <- load_source_data(conn, "data/nvdrs_narratives.xlsx", force_reload = TRUE)
#' dbDisconnect(conn)
#' }
load_source_data <- function(conn, excel_path, force_reload = FALSE) {
  if (!file.exists(excel_path)) {
    stop("Data file not found: ", excel_path)
  }

  # Check if already loaded
  existing <- DBI::dbGetQuery(conn,
    "SELECT COUNT(*) as n FROM source_narratives WHERE data_source = ?",
    params = list(excel_path)
  )

  if (existing$n > 0 && !force_reload) {
    cat("Data already loaded from:", excel_path, "(", existing$n, "narratives)\n")
    cat("Use force_reload=TRUE to reload\n")
    return(existing$n)
  }

  if (existing$n > 0 && force_reload) {
    cat("Removing existing data from:", excel_path, "\n")
    DBI::dbExecute(conn,
      "DELETE FROM source_narratives WHERE data_source = ?",
      params = list(excel_path)
    )
  }

  # Load Excel file
  cat("Loading data from:", excel_path, "\n")
  data <- readxl::read_excel(excel_path)

  # Ensure incident IDs are treated as character strings
  data <- dplyr::mutate(
    data,
    IncidentID = dplyr::if_else(
      is.na(IncidentID),
      NA_character_,
      as.character(IncidentID)
    )
  )

  # Transform to long format (avoid %>% pipe issues)
  data_long <- tidyr::pivot_longer(
    data,
    cols = c(NarrativeCME, NarrativeLE),
    names_to = "Type",
    values_to = "Narrative"
  )

  data_long <- dplyr::mutate(
    data_long,
    narrative_type = tolower(gsub("Narrative", "", Type)),
    manual_flag_ind = dplyr::case_when(
      narrative_type == "cme" ~ as.integer(as.logical(ipv_manualCME)),
      narrative_type == "le" ~ as.integer(as.logical(ipv_manualLE))
    ),
    manual_flag = as.integer(as.logical(ipv_manual))
  )

  data_long <- dplyr::select(
    data_long,
    incident_id = IncidentID,
    narrative_type,
    narrative_text = Narrative,
    manual_flag_ind,
    manual_flag
  )

  data_long <- dplyr::filter(data_long, !is.na(narrative_text), trimws(narrative_text) != "")
  data_long <- dplyr::mutate(
    data_long,
    incident_id = dplyr::if_else(
      is.na(incident_id),
      NA_character_,
      as.character(incident_id)
    )
  )

  # Insert into database
  data_long$data_source <- excel_path
  data_long$loaded_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

  # Convert to data frame for dbWriteTable
  data_df <- as.data.frame(data_long)

  DBI::dbWriteTable(conn, "source_narratives", data_df, append = TRUE)

  n_loaded <- nrow(data_long)
  cat("Loaded", n_loaded, "narratives into database\n")

  # Show summary
  summary <- dplyr::summarise(
    dplyr::group_by(data_long, narrative_type),
    n = dplyr::n(),
    n_positive = sum(manual_flag_ind, na.rm = TRUE),
    .groups = "drop"
  )

  cat("\nSummary by narrative type:\n")
  print(summary)

  return(n_loaded)
}

#' Get Source Narratives for Experiment
#'
#' Query narratives from source_narratives table
#'
#' @param conn Database connection
#' @param data_source Optional: filter by data source file
#' @param max_narratives Optional limit (for testing)
#' @return Tibble with narratives
#' @export
#' @examples
#' \dontrun{
#' # Get all narratives
#' conn <- get_db_connection()
#' narratives <- get_source_narratives(conn)
#' print(nrow(narratives))
#'
#' # Filter by data source
#' csv_narratives <- get_source_narratives(conn, data_source = "nvdrs_data.csv")
#'
#' # Limit for testing
#' sample <- get_source_narratives(conn, max_narratives = 10)
#' }
get_source_narratives <- function(conn, data_source = NULL, max_narratives = NULL) {
  query <- "SELECT * FROM source_narratives"
  params <- list()

  if (!is.null(data_source)) {
    query <- paste(query, "WHERE data_source = ?")
    params <- list(data_source)
  }

  query <- paste(query, "ORDER BY narrative_id")

  if (!is.null(max_narratives)) {
    query <- paste(query, "LIMIT", max_narratives)
  }

  if (length(params) > 0) {
    result <- DBI::dbGetQuery(conn, query, params = params)
  } else {
    result <- DBI::dbGetQuery(conn, query)
  }

  tibble::as_tibble(result)
}

#' Check if Data Already Loaded
#'
#' @param conn Database connection
#' @param data_source Path to data file
#' @return Logical
#' @export
#' @examples
#' \dontrun{
#' # Check if data is already loaded
#' conn <- get_db_connection()
#' is_loaded <- check_data_loaded(conn, "nvdrs_data.csv")
#' if (is_loaded) {
#'   cat("Data already loaded\n")
#' } else {
#'   cat("Need to load data\n")
#'   load_source_data(conn, "nvdrs_data.csv")
#' }
#' }
check_data_loaded <- function(conn, data_source) {
  result <- DBI::dbGetQuery(conn,
    "SELECT COUNT(*) as n FROM source_narratives WHERE data_source = ?",
    params = list(data_source)
  )
  return(result$n > 0)
}
