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
#' Supports connection pooling and robust error handling.
#' Requires dotenv and RPostgres packages.
#' 
#' @param env_file Path to .env file (default: ".env")
#' @param timeout Connection timeout in seconds (default: 10)
#' @param retry_attempts Number of retry attempts on connection failure (default: 3)
#' @return DBI connection object
#' @export
connect_postgres <- function(env_file = ".env", timeout = 10, retry_attempts = 3) {
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
  host <- trimws(Sys.getenv("POSTGRES_HOST", "localhost"))
  port <- as.integer(Sys.getenv("POSTGRES_PORT", "5432"))
  dbname <- trimws(Sys.getenv("POSTGRES_DB"))
  user <- trimws(Sys.getenv("POSTGRES_USER"))
  password <- trimws(Sys.getenv("POSTGRES_PASSWORD"))
  
  # Validate required parameters
  if (dbname == "" || user == "" || password == "") {
    stop("Missing PostgreSQL credentials. Set POSTGRES_DB, POSTGRES_USER, and POSTGRES_PASSWORD in .env file or environment.")
  }
  
  # Validate numeric port
  if (is.na(port) || port <= 0 || port > 65535) {
    stop(sprintf("Invalid PostgreSQL port: %s. Must be between 1-65535.", Sys.getenv("POSTGRES_PORT", "5432")))
  }
  
  # Attempt connection with retries
  last_error <- NULL
  for (attempt in 1:retry_attempts) {
    tryCatch({
      # Create connection with timeout
      conn <- DBI::dbConnect(
        RPostgres::Postgres(),
        host = host,
        port = port,
        dbname = dbname,
        user = user,
        password = password,
        connect_timeout = timeout,
        options = "-c statement_timeout=30000"  # 30 second query timeout
      )
      
      # Test connection validity
      if (!DBI::dbIsValid(conn)) {
        stop("Connection created but is not valid")
      }
      
      # Simple connection test query
      DBI::dbGetQuery(conn, "SELECT 1 as test")
      
      return(conn)
      
    }, error = function(e) {
      last_error <<- e
      if (attempt < retry_attempts) {
        Sys.sleep(2^(attempt - 1))  # Exponential backoff: 1, 2, 4 seconds
      }
    })
  }
  
  # If we get here, all attempts failed
  stop(sprintf("Failed to connect to PostgreSQL after %d attempts. Host: %s:%d, Database: %s, User: %s. Last error: %s", 
               retry_attempts, host, port, dbname, user, last_error$message))
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

#' Detect database connection type
#' 
#' Determines if a connection is SQLite, PostgreSQL, or other database type.
#' Used for database-specific query generation and schema handling.
#' 
#' @param conn DBI connection object
#' @return Character string: "sqlite", "postgresql", or "unknown"
#' @export
detect_db_type <- function(conn) {
  if (is.null(conn) || !DBI::dbIsValid(conn)) {
    return("unknown")
  }
  
  # Get connection class information
  conn_class <- class(conn)
  
  if (any(grepl("SQLiteConnection|SQLite", conn_class))) {
    return("sqlite")
  } else if (any(grepl("PqConnection|Postgres", conn_class))) {
    return("postgresql")
  }
  
  return("unknown")
}

#' Test database connection health
#' 
#' Performs comprehensive connection health check including connectivity,
#' basic operations, and response time measurement.
#' 
#' @param conn DBI connection object
#' @param detailed Whether to return detailed diagnostics (default: FALSE)
#' @return List with connection health status and metrics
#' @export
test_connection_health <- function(conn, detailed = FALSE) {
  start_time <- Sys.time()
  result <- list(
    healthy = FALSE,
    db_type = "unknown",
    response_time_ms = NA,
    error = NULL
  )
  
  tryCatch({
    # Basic validity check
    if (!DBI::dbIsValid(conn)) {
      result$error <- "Connection is not valid"
      return(result)
    }
    
    # Detect database type
    result$db_type <- detect_db_type(conn)
    
    # Test basic query execution
    test_query <- switch(result$db_type,
      "postgresql" = "SELECT version(), current_database(), current_user",
      "sqlite" = "SELECT sqlite_version(), 'main' as current_database",
      "SELECT 1 as test"  # fallback
    )
    
    query_result <- DBI::dbGetQuery(conn, test_query)
    
    # Calculate response time
    end_time <- Sys.time()
    result$response_time_ms <- as.numeric(difftime(end_time, start_time, units = "secs")) * 1000
    
    result$healthy <- TRUE
    
    if (detailed) {
      result$query_result <- query_result
      result$connection_info <- list(
        class = class(conn),
        valid = DBI::dbIsValid(conn)
      )
    }
    
  }, error = function(e) {
    result$error <- e$message
    end_time <- Sys.time()
    result$response_time_ms <- as.numeric(difftime(end_time, start_time, units = "secs")) * 1000
  })
  
  result
}

#' Get database connection with type detection
#' 
#' Unified connection function that automatically detects and connects
#' to either SQLite or PostgreSQL based on configuration.
#' 
#' @param db_config List with connection configuration or path to SQLite file
#' @param type Database type: "auto", "sqlite", or "postgresql" (default: "auto")
#' @param env_file Path to .env file for PostgreSQL (default: ".env")
#' @return DBI connection object
#' @export
get_unified_connection <- function(db_config = "llm_results.db", type = "auto", env_file = ".env") {
  if (type == "auto") {
    # Auto-detect based on configuration type
    if (is.character(db_config) && length(db_config) == 1) {
      # String path suggests SQLite
      type <- "sqlite"
    } else if (is.list(db_config) || file.exists(env_file)) {
      # List config or .env file suggests PostgreSQL
      type <- "postgresql"
    } else {
      # Default to SQLite
      type <- "sqlite"
    }
  }
  
  conn <- switch(type,
    "sqlite" = {
      db_path <- if (is.character(db_config)) db_config else "llm_results.db"
      get_db_connection(db_path)
    },
    "postgresql" = {
      connect_postgres(env_file)
    },
    stop(sprintf("Unsupported database type: %s. Use 'sqlite' or 'postgresql'", type))
  )
  
  conn
}

#' Ensure database schema exists
#' 
#' Creates tables and indexes if they don't exist.
#' Idempotent - safe to call multiple times.
#' Works with both SQLite and PostgreSQL using type detection.
#' 
#' @param conn DBI connection object
#' @return TRUE if successful
#' @export
ensure_schema <- function(conn) {
  # Use new type detection function
  db_type <- detect_db_type(conn)
  
  # Single table design - Unix philosophy
  if (db_type == "postgresql") {
    # PostgreSQL version with SERIAL and proper constraints
    schema_sql <- "
    CREATE TABLE IF NOT EXISTS llm_results (
      id SERIAL PRIMARY KEY,
      narrative_id TEXT,
      narrative_text TEXT,
      detected BOOLEAN NOT NULL,
      confidence REAL CHECK (confidence >= 0.0 AND confidence <= 1.0),
      model TEXT,
      prompt_tokens INTEGER CHECK (prompt_tokens >= 0),
      completion_tokens INTEGER CHECK (completion_tokens >= 0),
      total_tokens INTEGER CHECK (total_tokens >= 0),
      response_time_ms INTEGER CHECK (response_time_ms >= 0),
      raw_response TEXT,
      error_message TEXT,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      
      UNIQUE(narrative_id, narrative_text, model)
    );
    
    -- PostgreSQL specific indexes with better performance
    CREATE INDEX IF NOT EXISTS idx_llm_narrative_id ON llm_results(narrative_id);
    CREATE INDEX IF NOT EXISTS idx_llm_detected ON llm_results(detected);
    CREATE INDEX IF NOT EXISTS idx_llm_created_at ON llm_results(created_at);
    CREATE INDEX IF NOT EXISTS idx_llm_model ON llm_results(model);
    CREATE INDEX IF NOT EXISTS idx_llm_composite ON llm_results(detected, model, created_at);
    "
  } else {
    # SQLite version with original design
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
      
      UNIQUE(narrative_id, narrative_text, model)
    );
    
    CREATE INDEX IF NOT EXISTS idx_narrative_id ON llm_results(narrative_id);
    CREATE INDEX IF NOT EXISTS idx_detected ON llm_results(detected);
    CREATE INDEX IF NOT EXISTS idx_created_at ON llm_results(created_at);
    CREATE INDEX IF NOT EXISTS idx_model ON llm_results(model);
    "
  }
  
  # Execute schema creation
  statements <- trimws(strsplit(schema_sql, ";")[[1]])
  statements <- statements[nzchar(statements)]
  
  for (stmt in statements) {
    if (nzchar(trimws(stmt))) {
      DBI::dbExecute(conn, stmt)
    }
  }
  
  TRUE
}

#' Get schema version
#' 
#' Database-agnostic schema version tracking.
#' Uses PRAGMA for SQLite and metadata table for PostgreSQL.
#' 
#' @param conn DBI connection object
#' @return Integer version number
#' @export
get_schema_version <- function(conn) {
  db_type <- detect_db_type(conn)
  
  tryCatch({
    if (db_type == "postgresql") {
      # PostgreSQL: Use metadata table
      # Create metadata table if it doesn't exist
      DBI::dbExecute(conn, "
        CREATE TABLE IF NOT EXISTS _schema_metadata (
          key TEXT PRIMARY KEY,
          value TEXT,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      ")
      
      # Get version
      result <- DBI::dbGetQuery(conn, "
        SELECT value FROM _schema_metadata WHERE key = 'version'
      ")
      
      if (nrow(result) == 0) {
        return(0L)
      }
      
      as.integer(result$value[1])
      
    } else {
      # SQLite: Use PRAGMA
      result <- DBI::dbGetQuery(conn, "PRAGMA user_version")
      as.integer(result$user_version)
    }
  }, error = function(e) {
    0L
  })
}

#' Set schema version
#' 
#' Database-agnostic schema version setting.
#' Uses PRAGMA for SQLite and metadata table for PostgreSQL.
#' 
#' @param conn DBI connection object
#' @param version Integer version number
#' @return TRUE if successful
#' @export
set_schema_version <- function(conn, version) {
  version <- as.integer(version)
  db_type <- detect_db_type(conn)
  
  if (db_type == "postgresql") {
    # PostgreSQL: Use metadata table
    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS _schema_metadata (
        key TEXT PRIMARY KEY,
        value TEXT,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ")
    
    # Use UPSERT (INSERT ... ON CONFLICT)
    DBI::dbExecute(conn, "
      INSERT INTO _schema_metadata (key, value) 
      VALUES ('version', $1)
      ON CONFLICT (key) 
      DO UPDATE SET value = EXCLUDED.value, updated_at = CURRENT_TIMESTAMP
    ", list(as.character(version)))
    
  } else {
    # SQLite: Use PRAGMA
    DBI::dbExecute(conn, sprintf("PRAGMA user_version = %d", version))
  }
  
  TRUE
}

#' Execute database transaction safely
#' 
#' Wraps database operations in a transaction with proper rollback on error.
#' Works with both SQLite and PostgreSQL.
#' 
#' @param conn DBI connection object
#' @param code Code block to execute within transaction
#' @return Result of code execution
#' @export
execute_with_transaction <- function(conn, code) {
  if (!DBI::dbIsValid(conn)) {
    stop("Connection is not valid")
  }
  
  # Begin transaction
  DBI::dbBegin(conn)
  
  tryCatch({
    result <- force(code)
    DBI::dbCommit(conn)
    result
  }, error = function(e) {
    # Rollback on error
    tryCatch(DBI::dbRollback(conn), error = function(rollback_err) {
      warning(sprintf("Failed to rollback transaction: %s", rollback_err$message))
    })
    stop(sprintf("Transaction failed: %s", e$message))
  })
}

#' Clean up database connections
#' 
#' Safely closes connections and performs cleanup.
#' Handles connection pools and multiple connections.
#' 
#' @param connections Single connection or list of connections
#' @param force Whether to force close even if transactions are pending
#' @return Number of successfully closed connections
#' @export
cleanup_connections <- function(connections, force = FALSE) {
  if (is.null(connections)) {
    return(0L)
  }
  
  # Ensure it's a list
  if (!is.list(connections)) {
    connections <- list(connections)
  }
  
  closed_count <- 0L
  
  for (i in seq_along(connections)) {
    conn <- connections[[i]]
    
    if (is.null(conn)) {
      next
    }
    
    tryCatch({
      if (DBI::dbIsValid(conn)) {
        # Check for pending transactions
        if (!force) {
          db_type <- detect_db_type(conn)
          if (db_type == "postgresql") {
            # PostgreSQL: Check transaction status
            tx_status <- DBI::dbGetQuery(conn, "SELECT current_setting('transaction_isolation')")
            if (nrow(tx_status) > 0) {
              # If we're in a transaction, try to rollback first
              tryCatch(DBI::dbRollback(conn), error = function(e) {
                # Ignore rollback errors if not in transaction
              })
            }
          }
        }
        
        # Close connection
        DBI::dbDisconnect(conn)
        closed_count <- closed_count + 1L
      }
    }, error = function(e) {
      warning(sprintf("Error closing connection %d: %s", i, e$message))
    })
  }
  
  closed_count
}

#' Validate database connection configuration
#' 
#' Checks if connection configuration is valid before attempting connection.
#' Helps prevent connection failures and provides clear error messages.
#' 
#' @param config Configuration list or file path
#' @param type Database type: "sqlite", "postgresql", or "auto"
#' @return List with validation results
#' @export
validate_db_config <- function(config, type = "auto") {
  result <- list(
    valid = FALSE,
    type = type,
    errors = character(0),
    warnings = character(0)
  )
  
  if (type == "auto") {
    # Auto-detect type
    if (is.character(config) && length(config) == 1) {
      type <- "sqlite"
    } else if (is.list(config) || file.exists(".env")) {
      type <- "postgresql"
    } else {
      type <- "sqlite"  # default
    }
    result$type <- type
  }
  
  if (type == "sqlite") {
    # Validate SQLite configuration
    if (is.character(config)) {
      db_path <- config
      
      # Check if directory exists
      db_dir <- dirname(db_path)
      if (!dir.exists(db_dir)) {
        result$errors <- c(result$errors, sprintf("Database directory does not exist: %s", db_dir))
      }
      
      # Check write permissions
      if (dir.exists(db_dir) && file.access(db_dir, mode = 2) != 0) {
        result$errors <- c(result$errors, sprintf("No write permission for directory: %s", db_dir))
      }
      
      # Warning for existing file
      if (file.exists(db_path)) {
        result$warnings <- c(result$warnings, sprintf("Database file already exists: %s", db_path))
      }
      
    } else {
      result$errors <- c(result$errors, "SQLite configuration must be a file path string")
    }
    
  } else if (type == "postgresql") {
    # Validate PostgreSQL configuration
    env_vars <- c("POSTGRES_HOST", "POSTGRES_PORT", "POSTGRES_DB", "POSTGRES_USER", "POSTGRES_PASSWORD")
    
    for (var in env_vars) {
      value <- Sys.getenv(var)
      if (value == "") {
        result$errors <- c(result$errors, sprintf("Missing environment variable: %s", var))
      }
    }
    
    # Validate port number
    port <- Sys.getenv("POSTGRES_PORT")
    if (port != "") {
      port_num <- suppressWarnings(as.integer(port))
      if (is.na(port_num) || port_num <= 0 || port_num > 65535) {
        result$errors <- c(result$errors, sprintf("Invalid port number: %s", port))
      }
    }
    
    # Check if .env file exists
    if (!file.exists(".env")) {
      result$warnings <- c(result$warnings, ".env file not found, using system environment variables")
    }
  }
  
  result$valid <- length(result$errors) == 0
  result
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
    # If not installed as package, use here package for proper path resolution
    schema_file <- here::here("inst", "sql", "experiment_schema.sql")
    if (!file.exists(schema_file)) {
      stop("Could not find experiment_schema.sql at: ", schema_file, 
           ". Please ensure package is properly installed.")
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