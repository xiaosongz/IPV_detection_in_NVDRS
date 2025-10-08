# Excel Fixtures for Testing
# Creates temporary Excel files for testing edge cases

#' Create Excel test fixtures
#'
#' Creates temporary Excel files for testing data loading edge cases
#' @param env Environment for cleanup (default: parent.frame())
#' @return Named list of file paths
#' @export
local_excel_fixtures <- function(env = parent.frame()) {
  temp_dir <- tempdir(check = FALSE)
  # Don't clean up immediately - let withr handle it
  withr::defer(unlink(list.files(temp_dir, full.names = TRUE, pattern = "\\.xlsx$"), force = TRUE), env)
  
  # Check if writexl is available
  if (!requireNamespace("writexl", quietly = TRUE)) {
    skip("writexl package not available for Excel fixture creation")
  }
  
  # Empty Excel file
  empty_path <- file.path(temp_dir, "empty.xlsx")
  writexl::write_xlsx(data.frame(), empty_path)
  
  # Malformed Excel (corrupted)
  malformed_path <- file.path(temp_dir, "malformed.xlsx")
  writeLines("This is not valid Excel content", malformed_path)
  
  # Valid test data
  valid_path <- file.path(temp_dir, "valid.xlsx")
  test_data <- data.frame(
    IncidentID = c("INC001", "INC002", "INC003"),
    NarrativeCME = c(
      "CME narrative 1: No IPV mentioned",
      "CME narrative 2: Evidence of partner abuse",
      "CME narrative 3: Complex relationship dynamics"
    ),
    NarrativeLE = c(
      "LE narrative 1: Clear IPV indicators present",
      "LE narrative 2: No abuse detected",
      "LE narrative 3: Multiple forms of violence"
    ),
    ipv_manualCME = c(0, 1, 0),
    ipv_manualLE = c(1, 0, 1),
    ipv_manual = c(1, 1, 1),
    stringsAsFactors = FALSE
  )
  writexl::write_xlsx(test_data, valid_path)
  
  # Edge case: Missing required columns
  missing_cols_path <- file.path(temp_dir, "missing_cols.xlsx")
  incomplete_data <- data.frame(
    incident_id = c("INC001", "INC002"),
    narrative = c("Test 1", "Test 2")
    # Missing narrative_type and manual_flag_ind
  )
  writexl::write_xlsx(incomplete_data, missing_cols_path)
  
  # Edge case: Wrong data types
  wrong_types_path <- file.path(temp_dir, "wrong_types.xlsx")
  wrong_data <- data.frame(
    incident_id = c(1, 2, 3),  # Numeric instead of character
    narrative = c("Text 1", "Text 2", "Text 3"),
    narrative_type = c("LE", "CME", "LE"),
    manual_flag_ind = c("TRUE", "FALSE", "TRUE"),  # Character instead of numeric
    stringsAsFactors = FALSE
  )
  writexl::write_xlsx(wrong_data, wrong_types_path)
  
  # File paths are absolute, should be accessible
  
  list(
    empty = empty_path,
    malformed = malformed_path,
    valid = valid_path,
    missing_cols = missing_cols_path,
    wrong_types = wrong_types_path
  )
}

#' Create empty Excel fixture for testing
#' @param env Environment for cleanup
#' @return Path to empty Excel file
#' @export
local_empty_excel <- function(env = parent.frame()) {
  fixtures <- local_excel_fixtures(env)
  fixtures$empty
}

#' Create valid Excel fixture for testing
#' @param env Environment for cleanup
#' @return Path to valid Excel file
#' @export
local_valid_excel <- function(env = parent.frame()) {
  fixtures <- local_excel_fixtures(env)
  fixtures$valid
}

#' Create malformed Excel fixture for testing
#' @param env Environment for cleanup
#' @return Path to malformed Excel file
#' @export
local_malformed_excel <- function(env = parent.frame()) {
  fixtures <- local_excel_fixtures(env)
  fixtures$malformed
}
