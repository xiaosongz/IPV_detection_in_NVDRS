#!/usr/bin/env Rscript

# Find examples of cases missing both LE and CME narratives

library(readxl)
library(dplyr)
library(here)

# Load the data
cat("Loading data...\n")
data_path <- here("data-raw", "all_suicide_nar.xlsx")
df <- read_excel(data_path)

# Find cases missing both narratives
cat("Finding cases missing both narratives...\n\n")

missing_both <- df %>%
  mutate(
    CME_missing = is.na(NarrativeCME) | NarrativeCME == "" | trimws(NarrativeCME) == "",
    LE_missing = is.na(NarrativeLE) | NarrativeLE == "" | trimws(NarrativeLE) == ""
  ) %>%
  filter(CME_missing & LE_missing) %>%
  select(IncidentID, IncidentYear, SiteID)

cat("Total cases missing both narratives:", nrow(missing_both), "\n\n")

# Display first 10 examples
cat("First 10 examples of cases missing both narratives:\n")
cat(paste(rep("=", 60), collapse = ""), "\n")

for (i in 1:min(10, nrow(missing_both))) {
  cat(sprintf("%d. Incident ID: %s\n", i, missing_both$IncidentID[i]))
  cat(sprintf("   Year: %d\n", missing_both$IncidentYear[i]))
  cat(sprintf("   Site: %s\n", missing_both$SiteID[i]))
  cat("\n")
}

# Additional context about missing both cases
cat(paste(rep("=", 60), collapse = ""), "\n")
cat("Distribution by year:\n")
missing_both %>%
  count(IncidentYear, sort = TRUE) %>%
  rename(Cases = n) %>%
  print()

cat("\nDistribution by site (top 10):\n")
missing_both %>%
  count(SiteID, sort = TRUE) %>%
  head(10) %>%
  rename(Cases = n) %>%
  print()
