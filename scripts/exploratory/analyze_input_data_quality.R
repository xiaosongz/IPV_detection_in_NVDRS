#!/usr/bin/env Rscript

# Analyze input data quality for all_suicide_nar.xlsx
# Focus on duplicates and missing narratives

library(readxl)
library(dplyr)
library(here)

# Load the data
cat("Loading data from data-raw/all_suicide_nar.xlsx...\n")
data_path <- here("data-raw", "all_suicide_nar.xlsx")

if (!file.exists(data_path)) {
  stop("Data file not found: ", data_path)
}

# Read the Excel file
df <- read_excel(data_path)

cat("Data loaded successfully.\n")
cat("Dimensions:", nrow(df), "rows,", ncol(df), "columns\n\n")

# Basic info about columns
cat("Column names:\n")
print(names(df))
cat("\n")

# Check for incident_id column (case-insensitive)
incident_id_col <- names(df)[grepl("(incident.*id|id.*incident)", names(df), ignore.case = TRUE)][1]
if (is.na(incident_id_col)) {
  stop("incident_id column not found in the data")
}
cat("Using incident_id column:", incident_id_col, "\n\n")

# 1. Check for duplicates
cat("=== DUPLICATE ANALYSIS ===\n")
total_records <- nrow(df)
unique_incidents <- length(unique(df[[incident_id_col]]))
duplicate_records <- total_records - unique_incidents

cat("Total records:", total_records, "\n")
cat("Unique incident_id:", unique_incidents, "\n")
cat("Duplicate records:", duplicate_records, "\n")
cat("Duplicate percentage:", round(duplicate_records / total_records * 100, 2), "%\n\n")

if (duplicate_records > 0) {
  cat("Finding duplicates...\n")
  duplicates <- df %>%
    group_by_at(vars(all_of(incident_id_col))) %>%
    filter(n() > 1) %>%
    arrange_at(vars(all_of(incident_id_col)))
  
  cat("Number of incident_id with duplicates:", length(unique(duplicates[[incident_id_col]])), "\n")
  
  # Show first few duplicates
  cat("\nFirst 10 duplicate incident_id:\n")
  print(head(duplicates[[incident_id_col]], 10))
  cat("\n")
}

# 2. Check for missing narratives
cat("=== MISSING NARRATIVES ANALYSIS ===\n")

# Identify narrative columns
narrative_cols <- names(df)[grepl("(narrative|nar|LE|CME)", names(df), ignore.case = TRUE)]
cat("Potential narrative columns found:\n")
print(narrative_cols)
cat("\n")

# Common column names for narratives
le_cols <- names(df)[grepl("LE", names(df), ignore.case = TRUE)]
cme_cols <- names(df)[grepl("CME", names(df), ignore.case = TRUE)]

cat("\nLE-related columns:\n")
print(le_cols)
cat("\nCME-related columns:\n")
print(cme_cols)
cat("\n")

# Analyze missing data for each narrative column
missing_summary <- data.frame(
  column = character(),
  missing_count = integer(),
  missing_percentage = numeric(),
  stringsAsFactors = FALSE
)

for (col in narrative_cols) {
  if (col %in% names(df)) {
    missing_count <- sum(is.na(df[[col]]) | df[[col]] == "" | trimws(df[[col]]) == "")
    missing_pct <- missing_count / total_records * 100
    
    missing_summary <- rbind(missing_summary, data.frame(
      column = col,
      missing_count = missing_count,
      missing_percentage = round(missing_pct, 2),
      stringsAsFactors = FALSE
    ))
  }
}

cat("Missing data summary for narrative columns:\n")
print(missing_summary[order(-missing_summary$missing_percentage), ])
cat("\n")

# 3. Specific analysis for cases with ANY missing narrative
cat("=== CASES WITH MISSING NARRATIVES ===\n")

# Based on the actual column names found, use NarrativeLE and NarrativeCME
le_narrative_col <- "NarrativeLE"
cme_narrative_col <- "NarrativeCME"

cat("Using columns:\n")
cat("LE narrative:", if(is.null(le_narrative_col)) "NOT FOUND" else le_narrative_col, "\n")
cat("CME narrative:", if(is.null(cme_narrative_col)) "NOT FOUND" else cme_narrative_col, "\n\n")

if (!is.null(le_narrative_col) && !is.null(cme_narrative_col)) {
  # Check missing for each
  le_missing <- sum(is.na(df[[le_narrative_col]]) | df[[le_narrative_col]] == "" | trimws(df[[le_narrative_col]]) == "")
  cme_missing <- sum(is.na(df[[cme_narrative_col]]) | df[[cme_narrative_col]] == "" | trimws(df[[cme_narrative_col]]) == "")
  
  # Both missing
  both_missing <- sum(
    (is.na(df[[le_narrative_col]]) | df[[le_narrative_col]] == "" | trimws(df[[le_narrative_col]]) == "") &
    (is.na(df[[cme_narrative_col]]) | df[[cme_narrative_col]] == "" | trimws(df[[cme_narrative_col]]) == "")
  )
  
  # At least one missing
  either_missing <- sum(
    (is.na(df[[le_narrative_col]]) | df[[le_narrative_col]] == "" | trimws(df[[le_narrative_col]]) == "") |
    (is.na(df[[cme_narrative_col]]) | df[[cme_narrative_col]] == "" | trimws(df[[cme_narrative_col]]) == "")
  )
  
  cat("Cases missing LE narrative:", le_missing, "(", round(le_missing/total_records*100, 2), "%)\n")
  cat("Cases missing CME narrative:", cme_missing, "(", round(cme_missing/total_records*100, 2), "%)\n")
  cat("Cases missing BOTH narratives:", both_missing, "(", round(both_missing/total_records*100, 2), "%)\n")
  cat("Cases missing at least one narrative:", either_missing, "(", round(either_missing/total_records*100, 2), "%)\n")
  cat("Cases with both narratives present:", total_records - either_missing, "(", round((total_records-either_missing)/total_records*100, 2), "%)\n\n")
}

# 4. Data quality summary
cat("=== DATA QUALITY SUMMARY ===\n")
cat("1. Total records:", total_records, "\n")
cat("2. Unique incidents:", unique_incidents, "\n")
cat("3. Duplicate records:", duplicate_records, "(", round(duplicate_records/total_records*100, 2), "%)\n")

if (!is.null(le_narrative_col) && !is.null(cme_narrative_col) && 
    le_narrative_col %in% names(df) && cme_narrative_col %in% names(df)) {
  cat("4. Cases missing LE narrative:", le_missing, "(", round(le_missing/total_records*100, 2), "%)\n")
  cat("5. Cases missing CME narrative:", cme_missing, "(", round(cme_missing/total_records*100, 2), "%)\n")
  cat("6. Cases missing BOTH narratives:", both_missing, "(", round(both_missing/total_records*100, 2), "%)\n")
  cat("7. Usable cases (both narratives present):", total_records - either_missing, "(", round((total_records-either_missing)/total_records*100, 2), "%)\n")
} else {
  cat("4. Narrative columns not found or not properly identified\n")
}

cat("\n=== ANALYSIS COMPLETE ===\n")
