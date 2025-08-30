#!/usr/bin/env Rscript

#' Database Setup Example
#'
#' Demonstrates how to set up database connections for both SQLite and PostgreSQL.
#' Shows basic operations, validation, and troubleshooting.
#' Follows Unix philosophy: simple, composable functions.

# Load required functions
source("R/db_utils.R")

cat("=== Database Setup Example ===\n")

# Example 1: SQLite Setup (Local Development)
cat("\n=== Example 1: SQLite Setup ===\n")

# Simple SQLite connection
sqlite_path <- "example_results.db"
cat(sprintf("Setting up SQLite database: %s\n", sqlite_path))

# Validate configuration first
config_validation <- validate_db_config(sqlite_path, type = "sqlite")
if (!config_validation$valid) {
  cat("❌ Configuration validation failed:\n")
  for (error in config_validation$errors) {
    cat(sprintf("  - %s\n", error))
  }
} else {
  cat("✓ SQLite configuration valid\n")
  for (warning in config_validation$warnings) {
    cat(sprintf("  ⚠️ %s\n", warning))
  }
}

# Create connection
sqlite_conn <- tryCatch({
  conn <- get_db_connection(sqlite_path, create = TRUE)
  ensure_schema(conn)
  conn
}, error = function(e) {
  cat(sprintf("❌ Failed to connect: %s\n", e$message))
  NULL
})

if (!is.null(sqlite_conn)) {
  cat("✓ SQLite connection established\n")
  
  # Test connection health
  health <- test_connection_health(sqlite_conn, detailed = TRUE)
  cat(sprintf("  Database type: %s\n", health$db_type))
  cat(sprintf("  Response time: %.1f ms\n", health$response_time_ms))
  cat(sprintf("  Healthy: %s\n", health$healthy))
  
  if (health$healthy && !is.null(health$query_result)) {
    cat(sprintf("  SQLite version: %s\n", health$query_result$`sqlite_version()`))
  }
  
  # Show schema version
  schema_version <- get_schema_version(sqlite_conn)
  cat(sprintf("  Schema version: %d\n", schema_version))
  
  # Close connection
  close_db_connection(sqlite_conn)
  cat("✓ SQLite connection closed\n")
} else {
  cat("❌ SQLite setup failed\n")
}

# Example 2: PostgreSQL Setup (Production)
cat("\n=== Example 2: PostgreSQL Setup ===\n")

# Check if .env file exists for PostgreSQL
if (file.exists(".env")) {
  cat("✓ Found .env file for PostgreSQL credentials\n")
  
  # Validate PostgreSQL configuration
  pg_validation <- validate_db_config(list(), type = "postgresql")
  if (!pg_validation$valid) {
    cat("❌ PostgreSQL configuration validation failed:\n")
    for (error in pg_validation$errors) {
      cat(sprintf("  - %s\n", error))
    }
    cat("\nCreate .env file with:\n")
    cat("POSTGRES_HOST=localhost\n")
    cat("POSTGRES_PORT=5432\n")
    cat("POSTGRES_DB=your_database\n")
    cat("POSTGRES_USER=your_username\n")
    cat("POSTGRES_PASSWORD=your_password\n")
  } else {
    cat("✓ PostgreSQL configuration valid\n")
    for (warning in pg_validation$warnings) {
      cat(sprintf("  ⚠️ %s\n", warning))
    }
    
    # Try to connect to PostgreSQL
    postgres_conn <- tryCatch({
      conn <- connect_postgres()
      ensure_schema(conn)
      conn
    }, error = function(e) {
      cat(sprintf("❌ PostgreSQL connection failed: %s\n", e$message))
      cat("Common issues:\n")
      cat("  - PostgreSQL server not running\n")
      cat("  - Wrong credentials in .env file\n")
      cat("  - Database doesn't exist\n")
      cat("  - Network connectivity issues\n")
      NULL
    })
    
    if (!is.null(postgres_conn)) {
      cat("✓ PostgreSQL connection established\n")
      
      # Test connection health
      health <- test_connection_health(postgres_conn, detailed = TRUE)
      cat(sprintf("  Database type: %s\n", health$db_type))
      cat(sprintf("  Response time: %.1f ms\n", health$response_time_ms))
      cat(sprintf("  Healthy: %s\n", health$healthy))
      
      if (health$healthy && !is.null(health$query_result)) {
        cat(sprintf("  PostgreSQL version: %s\n", health$query_result$version))
        cat(sprintf("  Current database: %s\n", health$query_result$current_database))
        cat(sprintf("  Current user: %s\n", health$query_result$current_user))
      }
      
      # Show schema version
      schema_version <- get_schema_version(postgres_conn)
      cat(sprintf("  Schema version: %d\n", schema_version))
      
      # Close connection
      close_db_connection(postgres_conn)
      cat("✓ PostgreSQL connection closed\n")
    }
  }
} else {
  cat("⚠️ No .env file found\n")
  cat("For PostgreSQL setup, create .env file with:\n")
  cat("POSTGRES_HOST=localhost\n")
  cat("POSTGRES_PORT=5432\n")
  cat("POSTGRES_DB=your_database\n")
  cat("POSTGRES_USER=your_username\n")
  cat("POSTGRES_PASSWORD=your_password\n")
}

# Example 3: Unified Connection (Auto-Detection)
cat("\n=== Example 3: Unified Connection ===\n")

# Auto-detect and connect
auto_conn <- tryCatch({
  # This will auto-detect based on available configuration
  if (file.exists(".env")) {
    cat("Auto-detected PostgreSQL configuration\n")
    conn <- get_unified_connection(type = "auto")
  } else {
    cat("Auto-detected SQLite configuration\n")
    conn <- get_unified_connection("auto_example.db")
  }
  ensure_schema(conn)
  conn
}, error = function(e) {
  cat(sprintf("❌ Auto-connection failed: %s\n", e$message))
  NULL
})

if (!is.null(auto_conn)) {
  db_type <- detect_db_type(auto_conn)
  cat(sprintf("✓ Auto-connected to: %s\n", db_type))
  close_db_connection(auto_conn)
  cat("✓ Auto-connection closed\n")
}

# Example 4: Connection Pool Management
cat("\n=== Example 4: Connection Cleanup ===\n")

# Create multiple connections for demonstration
connections <- list()
for (i in 1:3) {
  conn <- tryCatch({
    get_db_connection(sprintf("test_%d.db", i))
  }, error = function(e) NULL)
  if (!is.null(conn)) {
    connections[[i]] <- conn
  }
}

cat(sprintf("Created %d test connections\n", length(connections)))

# Clean up all connections
closed_count <- cleanup_connections(connections)
cat(sprintf("✓ Cleaned up %d connections\n", closed_count))

# Example 5: Transaction Example
cat("\n=== Example 5: Transaction Safety ===\n")

# Demonstrate safe transaction handling
test_conn <- get_db_connection("transaction_test.db")
ensure_schema(test_conn)

# Example of successful transaction
transaction_result <- tryCatch({
  execute_with_transaction(test_conn, {
    # Simulate some database operations
    DBI::dbExecute(test_conn, "
      INSERT INTO llm_results (narrative_id, detected, confidence, model)
      VALUES ('tx_test_1', TRUE, 0.95, 'test-model')
    ")
    
    DBI::dbExecute(test_conn, "
      INSERT INTO llm_results (narrative_id, detected, confidence, model) 
      VALUES ('tx_test_2', FALSE, 0.85, 'test-model')
    ")
    
    # Return summary
    DBI::dbGetQuery(test_conn, "SELECT COUNT(*) as count FROM llm_results")
  })
}, error = function(e) {
  cat(sprintf("❌ Transaction failed: %s\n", e$message))
  NULL
})

if (!is.null(transaction_result)) {
  cat(sprintf("✓ Transaction completed. Total records: %d\n", transaction_result$count))
} else {
  cat("❌ Transaction example failed\n")
}

close_db_connection(test_conn)

# Clean up test databases
test_files <- c("example_results.db", "auto_example.db", 
               "test_1.db", "test_2.db", "test_3.db", "transaction_test.db")
for (file in test_files) {
  if (file.exists(file)) {
    file.remove(file)
    cat(sprintf("Cleaned up: %s\n", file))
  }
}

cat("\n✓ Database setup examples completed!\n")
cat("\nKey takeaways:\n")
cat("1. Always validate configuration before connecting\n")
cat("2. Use get_unified_connection() for automatic backend selection\n")
cat("3. Test connection health for production deployments\n")
cat("4. Use transactions for multi-operation safety\n")
cat("5. Clean up connections properly to avoid resource leaks\n")