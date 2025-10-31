#!/usr/bin/env Rscript

# Extract clear examples of placeholder text in narratives

library(readxl)
library(dplyr)
library(here)
library(stringr)

# Load the data
cat("Loading data...\n")
data_path <- here("data-raw", "all_suicide_nar.xlsx")
df <- read_excel(data_path)

# Common placeholder patterns
placeholder_patterns <- c(
  "Record not available",
  "No report on file", 
  "Report not on file",
  "Not on file",
  "No report available",
  "Unavailable",
  "Not available",
  "See CME",
  "See LE",
  "Refer to CME",
  "Refer to LE",
  "Autopsy.*unavailable",
  "Toxicology.*unavailable",
  "Death certificate.*only",
  "Certificate.*checked",
  "Medic.*only.*call",
  "Medical.*call.*available"
)

# Find clear placeholder examples
cat("Finding clear placeholder examples...\n\n")

placeholders_found <- list()

# Search CME narratives
for (pattern in placeholder_patterns) {
  matches <- df %>%
    filter(grepl(pattern, NarrativeCME, ignore.case = TRUE)) %>%
    mutate(match_type = "CME", pattern_matched = pattern) %>%
    select(IncidentID, IncidentYear, SiteID, match_type, pattern_matched, NarrativeCME)
  
  if (nrow(matches) > 0) {
    placeholders_found[[paste0("CME_", pattern)]] <- matches
  }
}

# Search LE narratives  
for (pattern in placeholder_patterns) {
  matches <- df %>%
    filter(grepl(pattern, NarrativeLE, ignore.case = TRUE)) %>%
    mutate(match_type = "LE", pattern_matched = pattern) %>%
    select(IncidentID, IncidentYear, SiteID, match_type, pattern_matched, NarrativeLE)
  
  if (nrow(matches) > 0) {
    placeholders_found[[paste0("LE_", pattern)]] <- matches
  }
}

# Display unique placeholder examples
cat("=== UNIQUE PLACEHOLDER EXAMPLES FOUND ===\n\n")

# CME placeholders
cme_examples <- df %>%
  filter(NarrativeCME != "" & !is.na(NarrativeCME)) %>%
  mutate(CME_clean = trimws(NarrativeCME)) %>%
  filter(
    grepl(paste(placeholder_patterns, collapse = "|"), CME_clean, ignore.case = TRUE) |
    CME_clean %in% c("No report", "None", "N/A", "NA", "Unknown", "Blank")
  ) %>%
  select(CME_clean) %>%
  unique() %>%
  arrange(CME_clean)

if (nrow(cme_examples) > 0) {
  cat("CME Placeholder Examples (", nrow(cme_examples), " unique types):\n")
  cat(paste(rep("-", 60), collapse = ""), "\n")
  for (i in 1:min(20, nrow(cme_examples))) {
    cat(sprintf("%2d. \"%s\"\n", i, cme_examples$CME_clean[i]))
  }
  if (nrow(cme_examples) > 20) {
    cat("... and", nrow(cme_examples) - 20, "more\n")
  }
  cat("\n")
}

# LE placeholders
le_examples <- df %>%
  filter(NarrativeLE != "" & !is.na(NarrativeLE)) %>%
  mutate(LE_clean = trimws(NarrativeLE)) %>%
  filter(
    grepl(paste(placeholder_patterns, collapse = "|"), LE_clean, ignore.case = TRUE) |
    LE_clean %in% c("No report", "None", "N/A", "NA", "Unknown", "Blank")
  ) %>%
  select(LE_clean) %>%
  unique() %>%
  arrange(LE_clean)

if (nrow(le_examples) > 0) {
  cat("LE Placeholder Examples (", nrow(le_examples), " unique types):\n")
  cat(paste(rep("-", 60), collapse = ""), "\n")
  for (i in 1:min(20, nrow(le_examples))) {
    cat(sprintf("%2d. \"%s\"\n", i, le_examples$LE_clean[i]))
  }
  if (nrow(le_examples) > 20) {
    cat("... and", nrow(le_examples) - 20, "more\n")
  }
  cat("\n")
}

# Count occurrences
cat("=== PLACEHOLDER COUNTS ===\n\n")

# Get counts for each pattern
pattern_counts <- data.frame(
  pattern = character(),
  cme_count = integer(),
  le_count = integer(),
  total_count = integer(),
  stringsAsFactors = FALSE
)

for (pattern in placeholder_patterns) {
  cme_count <- sum(grepl(pattern, df$NarrativeCME, ignore.case = TRUE), na.rm = TRUE)
  le_count <- sum(grepl(pattern, df$NarrativeLE, ignore.case = TRUE), na.rm = TRUE)
  
  if (cme_count > 0 || le_count > 0) {
    pattern_counts <- rbind(pattern_counts, data.frame(
      pattern = pattern,
      cme_count = cme_count,
      le_count = le_count,
      total_count = cme_count + le_count,
      stringsAsFactors = FALSE
    ))
  }
}

if (nrow(pattern_counts) > 0) {
  pattern_counts <- pattern_counts %>%
    arrange(desc(total_count))
  
  print(pattern_counts)
}

cat("\n=== ANALYSIS COMPLETE ===\n")
