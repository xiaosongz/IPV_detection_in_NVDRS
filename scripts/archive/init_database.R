#!/usr/bin/env Rscript

#' Initialize Experiment Tracking Database
#'
#' Usage: Rscript scripts/init_database.R [db_path]
#' 
#' If db_path is not provided, creates experiments.db in project root

library(here)

# Source required functions
source(here("R", "db_schema.R"))

# Parse command line args
args <- commandArgs(trailingOnly = TRUE)

db_path <- if (length(args) > 0) {
  args[1]
} else {
  here("experiments.db")
}

cat("Initializing experiment tracking database\n")
cat("Database path:", db_path, "\n\n")

# Check if database already exists
if (file.exists(db_path)) {
  cat("⚠️  Database already exists at:", db_path, "\n")
  cat("Do you want to recreate it? (y/N): ")
  response <- readLines(con = "stdin", n = 1)
  
  if (tolower(trimws(response)) != "y") {
    cat("Aborted. Database not modified.\n")
    quit(save = "no", status = 0)
  }
  
  cat("Removing existing database...\n")
  file.remove(db_path)
}

# Initialize database
conn <- init_experiment_db(db_path)

# Verify tables created
tables <- DBI::dbListTables(conn)
cat("\n✓ Database initialized successfully!\n")
cat("Tables created:\n")
for (table in tables) {
  cat("  -", table, "\n")
}

# Show table schemas
cat("\nTable schemas:\n")
for (table in tables) {
  cat("\n", table, ":\n", sep = "")
  schema <- DBI::dbGetQuery(conn, paste("PRAGMA table_info(", table, ")"))
  print(schema[, c("name", "type")])
}

DBI::dbDisconnect(conn)

cat("\n✓ Database ready for use!\n")
cat("\nNext steps:\n")
cat("  1. Load source data: source('R/data_loader.R'); load_source_data(conn, 'data-raw/file.xlsx')\n")
cat("  2. Create experiment config: configs/experiments/exp_001.yaml\n")
cat("  3. Run experiment: Rscript scripts/run_experiment.R configs/experiments/exp_001.yaml\n")
