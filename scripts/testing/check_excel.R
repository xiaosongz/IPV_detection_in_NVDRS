#!/usr/bin/env Rscript

# Quick check of Excel file structure
library(readxl)
library(cli)

excel_path <- "nvdrsipvdetector/inst/extdata/sui_all_flagged.xlsx"
cli::cli_alert_info("Checking Excel file: {excel_path}")

# Read Excel file
data <- read_excel(excel_path)
cli::cli_alert_success("Successfully read {nrow(data)} rows")

# Show structure
cli::cli_h2("Dataset Structure")
cli::cli_alert_info("Dimensions: {nrow(data)} rows x {ncol(data)} columns")

cli::cli_h3("Column Names:")
print(names(data))

# Check for narrative columns
cli::cli_h3("Checking for narrative columns:")
for (col in names(data)) {
  if (grepl("narr", tolower(col))) {
    cli::cli_alert_success("Found narrative column: {col}")
    # Check if it has data
    non_na <- sum(!is.na(data[[col]]))
    cli::cli_alert_info("  Non-empty values: {non_na}/{nrow(data)}")
  }
}

# Check for ID columns
cli::cli_h3("Checking for ID columns:")
for (col in names(data)) {
  if (grepl("id|ID", col)) {
    cli::cli_alert_success("Found ID column: {col}")
  }
}

# Check for IPV flag columns
cli::cli_h3("Checking for IPV flag columns:")
for (col in names(data)) {
  if (grepl("ipv|flag", tolower(col))) {
    cli::cli_alert_success("Found flag column: {col}")
    # Show unique values
    unique_vals <- unique(data[[col]])
    cli::cli_alert_info("  Unique values: {paste(head(unique_vals, 10), collapse=', ')}")
  }
}

# Show first few rows of key columns
cli::cli_h3("Sample data (first 3 rows):")
key_cols <- names(data)[1:min(5, ncol(data))]
print(data[1:3, key_cols])