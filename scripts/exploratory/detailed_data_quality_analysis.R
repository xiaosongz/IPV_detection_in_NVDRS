#!/usr/bin/env Rscript

# Detailed analysis of input data quality for all_suicide_nar.xlsx
# Includes duplicate analysis, missing narratives, and additional quality checks

library(readxl)
library(dplyr)
library(here)

# Load the data
cat("Loading data from data-raw/all_suicide_nar.xlsx...\n")
data_path <- here("data-raw", "all_suicide_nar.xlsx")
df <- read_excel(data_path)

cat("Data loaded successfully.\n")
cat("Dimensions:", nrow(df), "rows,", ncol(df), "columns\n\n")

# === DETAILED DUPLICATE ANALYSIS ===
cat("=== DETAILED DUPLICATE ANALYSIS ===\n")

duplicates <- df %>%
  group_by(IncidentID) %>%
  filter(n() > 1) %>%
  arrange(IncidentID, .by_group = TRUE)

if (nrow(duplicates) > 0) {
  cat("Duplicate records by IncidentID:\n\n")
  for (id in unique(duplicates$IncidentID)) {
    dup_records <- duplicates %>% filter(IncidentID == id)
    cat("IncidentID:", id, "- Duplicated", nrow(dup_records), "times\n")
    for (i in 1:nrow(dup_records)) {
      cat("  Record", i, "- Year:", dup_records$IncidentYear[i], 
          ", Site:", dup_records$SiteID[i], "\n")
      cat("    CME length:", nchar(as.character(dup_records$NarrativeCME[i])),
          ", LE length:", nchar(as.character(dup_records$NarrativeLE[i])), "\n")
    }
    cat("\n")
  }
}

# === NARRATIVE LENGTH ANALYSIS ===
cat("=== NARRATIVE LENGTH ANALYSIS ===\n")

# Calculate narrative lengths
df <- df %>%
  mutate(
    CME_length = nchar(as.character(NarrativeCME)),
    LE_length = nchar(as.character(NarrativeLE)),
    total_length = CME_length + LE_length
  )

# Summary statistics
cat("CME Narrative Length Statistics:\n")
summary(df$CME_length)
cat("\n")

cat("LE Narrative Length Statistics:\n")
summary(df$LE_length)
cat("\n")

cat("Total Narrative Length Statistics:\n")
summary(df$total_length)
cat("\n")

# Check for very short narratives (likely missing data)
cat("Very short narratives (< 50 characters):\n")
short_cme <- sum(df$CME_length > 0 & df$CME_length < 50)
short_le <- sum(df$LE_length > 0 & df$LE_length < 50)
cat("CME narratives with < 50 chars:", short_cme, "\n")
cat("LE narratives with < 50 chars:", short_le, "\n\n")

# === SITE AND YEAR DISTRIBUTION ===
cat("=== SITE AND YEAR DISTRIBUTION ===\n")

cat("Incident Year Distribution:\n")
year_counts <- df %>% count(IncidentYear, sort = TRUE)
print(year_counts)
cat("\n")

cat("Site ID Distribution (top 10):\n")
site_counts <- df %>% count(SiteID, sort = TRUE) %>% head(10)
print(site_counts)
cat("\n")

# === CROSS-ANALYSIS OF MISSING DATA ===
cat("=== CROSS-ANALYSIS OF MISSING DATA ===\n")

# Create missing flags
df <- df %>%
  mutate(
    CME_missing = is.na(NarrativeCME) | NarrativeCME == "" | trimws(NarrativeCME) == "",
    LE_missing = is.na(NarrativeLE) | NarrativeLE == "" | trimws(NarrativeLE) == ""
  )

# Missing by year
cat("Missing narratives by year:\n")
missing_by_year <- df %>%
  group_by(IncidentYear) %>%
  summarise(
    total = n(),
    CME_missing = sum(CME_missing),
    LE_missing = sum(LE_missing),
    both_missing = sum(CME_missing & LE_missing),
    CME_missing_pct = round(CME_missing / total * 100, 2),
    LE_missing_pct = round(LE_missing / total * 100, 2),
    both_missing_pct = round(both_missing / total * 100, 2)
  )
print(missing_by_year)
cat("\n")

# Missing by site (top 10)
cat("Missing narratives by site (top 10):\n")
missing_by_site <- df %>%
  group_by(SiteID) %>%
  summarise(
    total = n(),
    CME_missing = sum(CME_missing),
    LE_missing = sum(LE_missing),
    both_missing = sum(CME_missing & LE_missing),
    .groups = "drop"
  ) %>%
  arrange(desc(total)) %>%
  head(10)
print(missing_by_site)
cat("\n")

# === POTENTIAL QUALITY ISSUES ===
cat("=== POTENTIAL QUALITY ISSUES ===\n")

# Check for identical narratives across different incidents
cat("Checking for identical narratives across different incidents...\n")

# Extract non-empty narratives
cme_texts <- df %>% filter(!CME_missing) %>% select(IncidentID, NarrativeCME)
le_texts <- df %>% filter(!LE_missing) %>% select(IncidentID, NarrativeLE)

# Find duplicates CME narratives
cme_duplicates <- cme_texts %>%
  group_by(NarrativeCME) %>%
  filter(n() > 1) %>%
  summarise(count = n(), incidents = paste(unique(IncidentID), collapse = ", "), .groups = "drop")

if (nrow(cme_duplicates) > 0) {
  cat("Found", nrow(cme_duplicates), "identical CME narratives across different incidents\n")
  cat("Top 5 most duplicated CME narratives:\n")
  for (i in 1:min(5, nrow(cme_duplicates))) {
    cat("  Duplicated", cme_duplicates$count[i], "times\n")
    cat("  Incidents:", cme_duplicates$incidents[i], "\n")
    cat("  Text preview:", substr(cme_duplicates$NarrativeCME[i], 1, 100), "...\n\n")
  }
}

# Find duplicates LE narratives
le_duplicates <- le_texts %>%
  group_by(NarrativeLE) %>%
  filter(n() > 1) %>%
  summarise(count = n(), incidents = paste(unique(IncidentID), collapse = ", "), .groups = "drop")

if (nrow(le_duplicates) > 0) {
  cat("Found", nrow(le_duplicates), "identical LE narratives across different incidents\n")
  cat("Top 5 most duplicated LE narratives:\n")
  for (i in 1:min(5, nrow(le_duplicates))) {
    cat("  Duplicated", le_duplicates$count[i], "times\n")
    cat("  Incidents:", le_duplicates$incidents[i], "\n")
    cat("  Text preview:", substr(le_duplicates$NarrativeLE[i], 1, 100), "...\n\n")
  }
}

# === FINAL DATA QUALITY SUMMARY ===
cat("=== FINAL DATA QUALITY SUMMARY ===\n")
cat("Total records:", nrow(df), "\n")
cat("Unique incidents:", length(unique(df$IncidentID)), "\n")
cat("Years covered:", min(df$IncidentYear, na.rm = TRUE), "to", max(df$IncidentYear, na.rm = TRUE), "\n")
cat("Number of sites:", length(unique(df$SiteID)), "\n")
cat("Cases with both narratives:", sum(!df$CME_missing & !df$LE_missing), "\n")
cat("Cases with at least one narrative:", sum(!df$CME_missing | !df$LE_missing), "\n")
cat("Cases with no narratives:", sum(df$CME_missing & df$LE_missing), "\n")

cat("\n=== ANALYSIS COMPLETE ===\n")
