#' Database connection utilities for SQLite and PostgreSQL
#' 
#' Simple database utilities supporting both SQLite (local) and PostgreSQL (scalable).
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

#' Get PostgreSQL database connection
#' 
#' Connects to PostgreSQL using environment variables from .env file.
#' Requires dotenv and RPostgres packages.
#' 
#' @param env_file Path to .env file (default: ".env")
#' @return DBI connection object
#' @export
connect_postgres <- function(env_file = ".env") {
  # Check required packages
  if (!requireNamespace("DBI", quietly = TRUE)) {
    stop("Package 'DBI' required. Install with: install.packages('DBI')")
  }
  if (!requireNamespace("RPostgres", quietly = TRUE)) {
    stop("Package 'RPostgres' required. Install with: install.packages('RPostgres')")
  }
  
  # Load environment variables if dotenv available
  if (requireNamespace("dotenv", quietly = TRUE) && file.exists(env_file)) {
    dotenv::load_dot_env(env_file)
  }
  
  # Get connection parameters from environment
  host <- Sys.getenv("POSTGRES_HOST", "localhost")
  port <- as.integer(Sys.getenv("POSTGRES_PORT", "5432"))
  dbname <- Sys.getenv("POSTGRES_DB")
  user <- Sys.getenv("POSTGRES_USER")
  password <- Sys.getenv("POSTGRES_PASSWORD")
  
  # Validate required parameters
  if (dbname == "" || user == "" || password == "") {
    stop("Missing PostgreSQL credentials. Set POSTGRES_DB, POSTGRES_USER, and POSTGRES_PASSWORD in .env file or environment.")
  }
  
  # Create connection
  conn <- DBI::dbConnect(
    RPostgres::Postgres(),
    host = host,
    port = port,
    dbname = dbname,
    user = user,
    password = password
  )
  
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
#' Works with both SQLite and PostgreSQL.
#' 
#' @param conn DBI connection object
#' @return TRUE if successful
#' @export
ensure_schema <- function(conn) {
  # Detect database type
  db_type <- class(conn@ptr)[1]
  is_postgres <- grepl("PostgreSQL|Postgres", db_type, ignore.case = TRUE)
  
  # Single table design - Unix philosophy
  if (is_postgres) {
    # PostgreSQL version with SERIAL instead of AUTOINCREMENT
    schema_sql <- "
    CREATE TABLE IF NOT EXISTS llm_results (
      id SERIAL PRIMARY KEY,"
  } else {
    # SQLite version
    schema_sql <- "
    CREATE TABLE IF NOT EXISTS llm_results (
      id INTEGER PRIMARY KEY AUTOINCREMENT,"
  }
  
  # Common schema for both databases
  schema_sql <- paste0(schema_sql, "
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
    
    UNIQUE(narrative_id, narrative_text, model)
  );
  
  CREATE INDEX IF NOT EXISTS idx_narrative_id ON llm_results(narrative_id);
  CREATE INDEX IF NOT EXISTS idx_detected ON llm_results(detected);
  CREATE INDEX IF NOT EXISTS idx_created_at ON llm_results(created_at);
  CREATE INDEX IF NOT EXISTS idx_model ON llm_results(model);
  ")
  
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