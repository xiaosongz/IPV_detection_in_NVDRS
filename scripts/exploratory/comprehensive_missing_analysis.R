#!/usr/bin/env Rscript

# Comprehensive analysis of missing data including placeholder text

library(readxl)
library(dplyr)
library(here)
library(stringr)

# Load the data
cat("Loading data...\n")
data_path <- here("data-raw", "all_suicide_nar.xlsx")
df <- read_excel(data_path)

cat("Data loaded successfully.\n\n")

# Define patterns that indicate missing/placeholder content
missing_patterns <- c(
  # Exact matches (case insensitive)
  "(?i)^no report$",
  "(?i)^no report on file$",
  "(?i)^report not on file$",
  "(?i)^not on file$",
  "(?i)^no report available$",
  "(?i)^unavailable$",
  "(?i)^not available$",
  "(?i)^none$",
  "(?i)^n/a$",
  "(?i)^na$",
  "(?i)^see cme$",
  "(?i)^see le$",
  "(?i)^refer to cme$",
  "(?i)^refer to le$",
  "(?i)^unknown$",
  "(?i)^blank$",
  # Partial matches
  "(?i)no report.*file",
  "(?i)report.*not.*available",
  "(?i)not.*available",
  "(?i)autopsy.*unavailable",
  "(?i)toxicology.*unavailable",
  "(?i)see.*cme",
  "(?i)see.*le",
  "(?i)refer.*cme",
  "(?i)refer.*le",
  "(?i)death certificate.*only",
  "(?i)certificate.*checked",
  "(?i)medic.*only.*call",
  "(?i)medical.*call.*available",
  # Very short texts (likely placeholders)
  "^[.:;-]{1,3}$",
  "^.{1,5}$"
)

# Function to check if text is missing or placeholder (vectorized)
is_missing_content <- function(text) {
  # Handle NA and empty strings
  result <- is.na(text) | text == "" | trimws(text) == ""
  
  # For non-empty text, check against patterns
  non_empty <- !result
  if (any(non_empty)) {
    for (pattern in missing_patterns) {
      result <- result | (non_empty & grepl(pattern, trimws(text)))
    }
  }
  
  return(result)
}

# Apply the missing content check
cat("Identifying missing and placeholder narratives...\n\n")
df <- df %>%
  mutate(
    CME_missing = is_missing_content(NarrativeCME),
    LE_missing = is_missing_content(NarrativeLE)
  )

# === RECALCULATED MISSING DATA STATISTICS ===
cat("=== UPDATED MISSING DATA STATISTICS ===\n")
cat("(Including placeholder text as missing)\n\n")

total_records <- nrow(df)

cme_missing_new <- sum(df$CME_missing)
le_missing_new <- sum(df$LE_missing)
both_missing_new <- sum(df$CME_missing & df$LE_missing)
either_missing_new <- sum(df$CME_missing | df$LE_missing)

cat("Total records:", total_records, "\n")
cat("CME narratives missing (including placeholders):", cme_missing_new, 
    "(", round(cme_missing_new/total_records*100, 2), "%)\n")
cat("LE narratives missing (including placeholders):", le_missing_new, 
    "(", round(le_missing_new/total_records*100, 2), "%)\n")
cat("Both narratives missing:", both_missing_new, 
    "(", round(both_missing_new/total_records*100, 2), "%)\n")
cat("At least one narrative missing:", either_missing_new, 
    "(", round(either_missing_new/total_records*100, 2), "%)\n")
cat("Both narratives present:", total_records - either_missing_new, 
    "(", round((total_records-either_missing_new)/total_records*100, 2), "%)\n\n")

# === EXAMPLES OF PLACEHOLDER TEXT ===
cat("=== EXAMPLES OF PLACEHOLDER TEXT FOUND ===\n\n")

# Find CME placeholders
cme_placeholders <- df %>%
  filter(CME_missing, !is.na(NarrativeCME), NarrativeCME != "", trimws(NarrativeCME) != "") %>%
  select(NarrativeCME) %>%
  unique() %>%
  head(20)

if (nrow(cme_placeholders) > 0) {
  cat("CME placeholder examples (up to 20):\n")
  for (i in 1:nrow(cme_placeholders)) {
    cat(sprintf("%d. \"%s\"\n", i, cme_placeholders$NarrativeCME[i]))
  }
  cat("\n")
}

# Find LE placeholders
le_placeholders <- df %>%
  filter(LE_missing, !is.na(NarrativeLE), NarrativeLE != "", trimws(NarrativeLE) == "") %>%
  select(NarrativeLE) %>%
  unique() %>%
  head(20)

if (nrow(le_placeholders) > 0) {
  cat("LE placeholder examples (up to 20):\n")
  for (i in 1:nrow(le_placeholders)) {
    cat(sprintf("%d. \"%s\"\n", i, le_placeholders$NarrativeLE[i]))
  }
  cat("\n")
}

# === UPDATED DUPLICATE ANALYSIS ===
cat("=== UPDATED DUPLICATE ANALYSIS ===\n")

duplicates <- df %>%
  group_by(IncidentID) %>%
  filter(n() > 1) %>%
  arrange(IncidentID, .by_group = TRUE)

if (nrow(duplicates) > 0) {
  cat("Duplicate records (including placeholders):\n\n")
  for (id in unique(duplicates$IncidentID)) {
    dup_records <- duplicates %>% filter(IncidentID == id)
    cat("IncidentID:", id, "- Duplicated", nrow(dup_records), "times\n")
    for (i in 1:nrow(dup_records)) {
      cat("  Record", i, "- Year:", dup_records$IncidentYear[i], 
          ", Site:", dup_records$SiteID[i], "\n")
      cat("    CME present:", !dup_records$CME_missing[i],
          ", LE present:", !dup_records$LE_missing[i], "\n")
    }
    cat("\n")
  }
}

# === EXAMPLES OF CASES WITH PLACEHOLDER TEXT ===
cat("=== EXAMPLES OF CASES WITH PLACEHOLDER TEXT ===\n\n")

# Find cases with placeholder text (not completely empty)
placeholder_cases <- df %>%
  filter(
    (CME_missing & !is.na(NarrativeCME) & NarrativeCME != "" & trimws(NarrativeCME) != "") |
    (LE_missing & !is.na(NarrativeLE) & NarrativeLE != "" & trimws(NarrativeLE) != "")
  ) %>%
  select(IncidentID, IncidentYear, SiteID, NarrativeCME, NarrativeLE) %>%
  head(10)

if (nrow(placeholder_cases) > 0) {
  cat("First 10 cases with placeholder text:\n")
  cat(paste(rep("=", 80), collapse = ""), "\n")
  
  for (i in 1:nrow(placeholder_cases)) {
    cat(sprintf("Case %d: Incident ID %s (%d, %s)\n", 
                i, placeholder_cases$IncidentID[i], 
                placeholder_cases$IncidentYear[i], 
                placeholder_cases$SiteID[i]))
    
    if (!is.na(placeholder_cases$NarrativeCME[i]) && 
        trimws(placeholder_cases$NarrativeCME[i]) != "") {
      cat(sprintf("  CME (placeholder): \"%s\"\n", 
                  substr(placeholder_cases$NarrativeCME[i], 1, 100)))
    }
    
    if (!is.na(placeholder_cases$NarrativeLE[i]) && 
        trimws(placeholder_cases$NarrativeLE[i]) != "") {
      cat(sprintf("  LE (placeholder): \"%s\"\n", 
                  substr(placeholder_cases$NarrativeLE[i], 1, 100)))
    }
    cat("\n")
  }
}

# === FINAL SUMMARY ===
cat("=== FINAL UPDATED SUMMARY ===\n")
cat("After accounting for placeholder text:\n")
cat("- Total records:", total_records, "\n")
cat("- CME narratives truly missing:", cme_missing_new, "(", round(cme_missing_new/total_records*100, 2), "%)\n")
cat("- LE narratives truly missing:", le_missing_new, "(", round(le_missing_new/total_records*100, 2), "%)\n")
cat("- Usable cases (both narratives present):", total_records - either_missing_new, "(", round((total_records-either_missing_new)/total_records*100, 2), "%)\n")

cat("\n=== ANALYSIS COMPLETE ===\n")
