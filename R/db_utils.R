#' Database connection utilities for SQLite
#' 
#' Simple, zero-configuration SQLite utilities following Unix philosophy.
#' One function, one purpose. No abstractions, no complexity.

#' Get SQLite database connection
#' 
#' @param db_path Path to SQLite database file (default: "llm_results.db")
#' @param create Whether to create database if it doesn't exist (default: TRUE)
#' @return DBI connection object
#' @export
get_db_connection <- function(db_path = "llm_results.db", create = TRUE) {
  if (!requireNamespace("DBI", quietly = TRUE)) {
    stop("Package 'DBI' required. Install with: install.packages('DBI')")
  }
  if (!requireNamespace("RSQLite", quietly = TRUE)) {
    stop("Package 'RSQLite' required. Install with: install.packages('RSQLite')")
  }
  
  # Simple connection, no complexity
  conn <- DBI::dbConnect(
    RSQLite::SQLite(),
    dbname = db_path,
    create = create
  )
  
  # Enable foreign keys for data integrity
  DBI::dbExecute(conn, "PRAGMA foreign_keys = ON")
  
  conn
}

#' Close database connection safely
#' 
#' @param conn DBI connection object
#' @return TRUE if successful, FALSE otherwise
#' @export
close_db_connection <- function(conn) {
  if (!is.null(conn) && DBI::dbIsValid(conn)) {
    DBI::dbDisconnect(conn)
    return(TRUE)
  }
  FALSE
}

#' Ensure database schema exists
#' 
#' Creates tables and indexes if they don't exist.
#' Idempotent - safe to call multiple times.
#' 
#' @param conn DBI connection object
#' @return TRUE if successful
#' @export
ensure_schema <- function(conn) {
  # Single table design - Unix philosophy
  schema_sql <- "
  CREATE TABLE IF NOT EXISTS llm_results (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    narrative_id TEXT,
    narrative_text TEXT,
    detected BOOLEAN NOT NULL,
    confidence REAL,
    model TEXT,
    prompt_tokens INTEGER,
    completion_tokens INTEGER,
    total_tokens INTEGER,
    response_time_ms INTEGER,
    raw_response TEXT,
    error_message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- Prevent exact duplicates
    UNIQUE(narrative_id, narrative_text, model)
  );
  
  -- Indexes for performance
  CREATE INDEX IF NOT EXISTS idx_narrative_id ON llm_results(narrative_id);
  CREATE INDEX IF NOT EXISTS idx_detected ON llm_results(detected);
  CREATE INDEX IF NOT EXISTS idx_created_at ON llm_results(created_at);
  CREATE INDEX IF NOT EXISTS idx_model ON llm_results(model);
  "
  
  # Execute schema creation
  statements <- trimws(strsplit(schema_sql, ";")[[1]])
  statements <- statements[nzchar(statements)]
  
  for (stmt in statements) {
    DBI::dbExecute(conn, stmt)
  }
  
  TRUE
}

#' Get schema version
#' 
#' @param conn DBI connection object
#' @return Integer version number
#' @export
get_schema_version <- function(conn) {
  # Simple version tracking
  tryCatch({
    result <- DBI::dbGetQuery(conn, "PRAGMA user_version")
    as.integer(result$user_version)
  }, error = function(e) {
    0L
  })
}

#' Set schema version
#' 
#' @param conn DBI connection object
#' @param version Integer version number
#' @return TRUE if successful
#' @export
set_schema_version <- function(conn, version) {
  version <- as.integer(version)
  DBI::dbExecute(conn, sprintf("PRAGMA user_version = %d", version))
  TRUE
}

#' Ensure experiment tracking schema exists
#' 
#' Creates experiment tracking tables for R&D phase.
#' This is optional - only needed for experiment mode.
#' Does not affect the basic llm_results table.
#' 
#' @param conn DBI connection object
#' @return TRUE if successful
#' @export
ensure_experiment_schema <- function(conn) {
  # Read the experiment schema SQL
  schema_file <- system.file("sql", "experiment_schema.sql", package = "IPVdetection")
  
  if (schema_file == "") {
    # If not installed as package, try local path
    schema_file <- "inst/sql/experiment_schema.sql"
    if (!file.exists(schema_file)) {
      stop("Could not find experiment_schema.sql. Please ensure package is properly installed.")
    }
  }
  
  schema_sql <- readLines(schema_file, warn = FALSE)
  schema_sql <- paste(schema_sql, collapse = "\n")
  
  # Split into individual statements (handling multi-line statements)
  # Remove comments first
  schema_sql <- gsub("--[^\n]*", "", schema_sql)
  
  # Split by semicolon but keep CREATE VIEW statements intact
  statements <- strsplit(schema_sql, ";\\s*\n")[[1]]
  statements <- trimws(statements)
  statements <- statements[nzchar(statements)]
  
  # Execute each statement
  for (stmt in statements) {
    if (nzchar(trimws(stmt))) {
      tryCatch({
        DBI::dbExecute(conn, stmt)
      }, error = function(e) {
        # Ignore errors for views that might already exist
        if (!grepl("already exists", e$message, ignore.case = TRUE)) {
          warning(sprintf("Error executing statement: %s", e$message))
        }
      })
    }
  }
  
  TRUE
}