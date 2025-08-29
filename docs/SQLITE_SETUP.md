# SQLite Local Setup Guide

## Overview

This guide covers local deployment of the IPV detection system with SQLite backend. SQLite provides zero-configuration setup, perfect for development, small-scale deployments, and data analysis workflows. Performance is excellent for single-user scenarios (~50-200 records/second locally).

## Prerequisites

### Required R Packages

```r
install.packages(c(
  "DBI",           # Database interface
  "RSQLite",       # SQLite driver  
  "tibble",        # Data frames
  "dplyr"          # Data manipulation
))
```

### System Requirements

- SQLite 3.6+ (included with RSQLite package)
- Local disk space for database file
- R 4.0+ recommended
- No server setup required

## Quick Start

### 1. Basic Connection Test

```r
# Load the package
library(IPVdetection)

# Test connection (creates database if it doesn't exist)
conn <- get_db_connection("test.db")
health <- test_connection_health(conn, detailed = TRUE)
print(health)

# Clean up
close_db_connection(conn)
unlink("test.db")  # Remove test database
```

### 2. Default Database Setup

```r
# Uses default database "llm_results.db" in current directory
conn <- get_db_connection()

# Schema is automatically created when you first store results
result <- store_llm_result(your_parsed_result)

# Check that everything is working
tables <- DBI::dbListTables(conn)
print(tables)  # Should show "llm_results"

close_db_connection(conn)
```

### 3. Custom Database Path

```r
# Use custom database location
db_path <- "data/ipv_analysis.db"
dir.create(dirname(db_path), showWarnings = FALSE, recursive = TRUE)

conn <- get_db_connection(db_path)
result <- store_llm_result(your_parsed_result)
close_db_connection(conn)
```

## Development Deployment

### Project Structure Setup

```r
# Recommended project structure
project_setup <- function(project_name) {
  dirs <- c(
    file.path(project_name, "data"),
    file.path(project_name, "results"),
    file.path(project_name, "scripts"),
    file.path(project_name, "config")
  )
  
  lapply(dirs, dir.create, showWarnings = FALSE, recursive = TRUE)
  
  # Create default database in data/
  db_path <- file.path(project_name, "data", "llm_results.db")
  conn <- get_db_connection(db_path)
  close_db_connection(conn)
  
  cat("Project structure created:\n")
  cat("Database:", db_path, "\n")
  cat("Use: conn <- get_db_connection('", db_path, "')\n", sep = "")
}

# Usage
project_setup("my_ipv_analysis")
```

### Configuration Management

```r
# config/db_config.R
DB_CONFIG <- list(
  development = list(
    path = "data/dev_results.db",
    backup_dir = "backups/dev"
  ),
  testing = list(
    path = "data/test_results.db", 
    backup_dir = "backups/test"
  ),
  production = list(
    path = "data/prod_results.db",
    backup_dir = "backups/prod"
  )
)

# Helper function to get environment-specific database
get_env_db <- function(env = "development") {
  config <- DB_CONFIG[[env]]
  if (is.null(config)) {
    stop("Invalid environment: ", env)
  }
  
  # Ensure directories exist
  dir.create(dirname(config$path), showWarnings = FALSE, recursive = TRUE)
  dir.create(config$backup_dir, showWarnings = FALSE, recursive = TRUE)
  
  get_db_connection(config$path)
}

# Usage
conn <- get_env_db("development")
```

## Production-Ready SQLite Setup

### Database Optimization

```r
# Optimize SQLite for better performance
optimize_sqlite <- function(conn) {
  # Performance settings
  DBI::dbExecute(conn, "PRAGMA journal_mode = WAL")          # Better concurrency
  DBI::dbExecute(conn, "PRAGMA synchronous = NORMAL")       # Faster writes
  DBI::dbExecute(conn, "PRAGMA cache_size = 10000")         # 40MB cache
  DBI::dbExecute(conn, "PRAGMA temp_store = memory")        # Use RAM for temp
  DBI::dbExecute(conn, "PRAGMA mmap_size = 268435456")      # 256MB memory map
  
  # Create performance indexes
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_narrative_id ON llm_results(narrative_id)")
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_created_at ON llm_results(created_at)")  
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_model ON llm_results(model)")
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_detected ON llm_results(detected)")
  
  # Update statistics
  DBI::dbExecute(conn, "ANALYZE")
  
  cat("SQLite database optimized\n")
}

# Apply optimizations
conn <- get_db_connection("llm_results.db")
optimize_sqlite(conn)
close_db_connection(conn)
```

### Database Maintenance

```r
# Regular maintenance script
maintain_sqlite <- function(db_path = "llm_results.db") {
  conn <- get_db_connection(db_path)
  
  # Check database integrity
  integrity <- DBI::dbGetQuery(conn, "PRAGMA integrity_check")
  if (integrity$integrity_check[1] != "ok") {
    warning("Database integrity issues detected: ", paste(integrity$integrity_check, collapse = "; "))
  }
  
  # Get database statistics
  stats <- list(
    size_mb = file.size(db_path) / (1024^2),
    record_count = DBI::dbGetQuery(conn, "SELECT COUNT(*) as count FROM llm_results")$count,
    fragmentation = DBI::dbGetQuery(conn, "PRAGMA freelist_count")$freelist_count
  )
  
  # Vacuum if fragmented (> 1000 free pages)
  if (stats$fragmentation > 1000) {
    cat("Vacuuming database (", stats$fragmentation, "free pages)...\n")
    DBI::dbExecute(conn, "VACUUM")
  }
  
  # Update statistics
  DBI::dbExecute(conn, "ANALYZE")
  
  close_db_connection(conn)
  
  cat("Database maintenance complete:\n")
  cat("  Size:", round(stats$size_mb, 2), "MB\n")
  cat("  Records:", stats$record_count, "\n")
  cat("  Free pages:", stats$fragmentation, "\n")
  
  return(stats)
}

# Run maintenance
maintain_sqlite("llm_results.db")
```

## Data Management

### Backup and Restore

```r
# Automated backup function
backup_sqlite <- function(db_path = "llm_results.db", backup_dir = "backups") {
  if (!file.exists(db_path)) {
    stop("Database file not found: ", db_path)
  }
  
  # Create backup directory
  dir.create(backup_dir, showWarnings = FALSE, recursive = TRUE)
  
  # Generate backup filename with timestamp
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  backup_name <- paste0(tools::file_path_sans_ext(basename(db_path)), "_", timestamp, ".db")
  backup_path <- file.path(backup_dir, backup_name)
  
  # Copy database file
  success <- file.copy(db_path, backup_path, overwrite = FALSE)
  
  if (success) {
    # Compress backup to save space
    if (requireNamespace("R.utils", quietly = TRUE)) {
      R.utils::gzip(backup_path, remove = TRUE)
      backup_path <- paste0(backup_path, ".gz")
    }
    
    cat("Backup created:", backup_path, "\n")
    cat("Backup size:", round(file.size(backup_path) / (1024^2), 2), "MB\n")
    
    # Clean old backups (keep last 7 days)
    cleanup_old_backups(backup_dir, days = 7)
    
    return(backup_path)
  } else {
    stop("Failed to create backup")
  }
}

# Cleanup old backups
cleanup_old_backups <- function(backup_dir, days = 7) {
  if (!dir.exists(backup_dir)) return()
  
  files <- list.files(backup_dir, pattern = "\\.db(\\.gz)?$", full.names = TRUE)
  if (length(files) == 0) return()
  
  file_info <- file.info(files)
  old_files <- files[file_info$mtime < (Sys.time() - days * 24 * 3600)]
  
  if (length(old_files) > 0) {
    unlink(old_files)
    cat("Cleaned up", length(old_files), "old backup files\n")
  }
}

# Usage
backup_path <- backup_sqlite("llm_results.db")
```

```r
# Restore from backup
restore_sqlite <- function(backup_path, restore_path = "llm_results_restored.db") {
  if (!file.exists(backup_path)) {
    stop("Backup file not found: ", backup_path)
  }
  
  # Handle compressed backups
  if (grepl("\\.gz$", backup_path)) {
    if (!requireNamespace("R.utils", quietly = TRUE)) {
      stop("R.utils package required to restore compressed backups")
    }
    
    temp_path <- tempfile(fileext = ".db")
    R.utils::gunzip(backup_path, temp_path, remove = FALSE)
    backup_path <- temp_path
    on.exit(unlink(temp_path))
  }
  
  # Copy backup to restore location
  success <- file.copy(backup_path, restore_path, overwrite = TRUE)
  
  if (success) {
    # Verify restored database
    conn <- tryCatch(get_db_connection(restore_path), error = function(e) NULL)
    if (is.null(conn)) {
      stop("Restored database is corrupted or invalid")
    }
    
    record_count <- DBI::dbGetQuery(conn, "SELECT COUNT(*) as count FROM llm_results")$count
    close_db_connection(conn)
    
    cat("Database restored successfully:\n")
    cat("  File:", restore_path, "\n") 
    cat("  Records:", record_count, "\n")
    
    return(restore_path)
  } else {
    stop("Failed to restore database")
  }
}

# Usage
restored_path <- restore_sqlite("backups/llm_results_20250829_143022.db.gz")
```

### Data Export and Import

```r
# Export data to CSV
export_to_csv <- function(db_path = "llm_results.db", output_file = "ipv_results.csv") {
  conn <- get_db_connection(db_path)
  
  data <- DBI::dbReadTable(conn, "llm_results")
  close_db_connection(conn)
  
  write.csv(data, output_file, row.names = FALSE)
  
  cat("Data exported to:", output_file, "\n")
  cat("Records:", nrow(data), "\n")
  cat("File size:", round(file.size(output_file) / (1024^2), 2), "MB\n")
  
  return(output_file)
}

# Import from CSV
import_from_csv <- function(csv_file, db_path = "llm_results.db") {
  if (!file.exists(csv_file)) {
    stop("CSV file not found: ", csv_file)
  }
  
  # Read CSV data
  data <- read.csv(csv_file, stringsAsFactors = FALSE)
  
  # Validate required columns
  required_cols <- c("narrative_id", "detected", "confidence")
  missing_cols <- required_cols[!required_cols %in% colnames(data)]
  
  if (length(missing_cols) > 0) {
    stop("Missing required columns: ", paste(missing_cols, collapse = ", "))
  }
  
  # Convert to list format for batch insert
  results_list <- apply(data, 1, function(row) {
    list(
      narrative_id = row[["narrative_id"]],
      narrative_text = row[["narrative_text"]],
      detected = as.logical(row[["detected"]]),
      confidence = as.numeric(row[["confidence"]]),
      model = row[["model"]],
      prompt_tokens = as.integer(row[["prompt_tokens"]]),
      completion_tokens = as.integer(row[["completion_tokens"]]),
      total_tokens = as.integer(row[["total_tokens"]]),
      response_time_ms = as.integer(row[["response_time_ms"]]),
      raw_response = row[["raw_response"]],
      error_message = row[["error_message"]]
    )
  })
  
  # Batch insert
  result <- store_llm_results_batch(results_list, db_path = db_path)
  
  cat("Import complete:\n")
  cat("  Total:", result$total, "records\n")
  cat("  Inserted:", result$inserted, "new records\n")
  cat("  Duplicates:", result$duplicates, "records\n")
  cat("  Errors:", result$errors, "records\n")
  
  return(result)
}

# Usage
export_to_csv("llm_results.db", "backup_data.csv")
import_result <- import_from_csv("backup_data.csv", "restored.db")
```

## Performance Tuning

### Expected Performance Metrics

- **Single inserts**: 50-200 records/second (local SSD)
- **Batch inserts**: 500-2000 records/second (local SSD)  
- **Connection time**: <10ms (local file)
- **Query response**: <5ms for simple operations
- **Database size**: ~1KB per record (varies by narrative length)

**Note**: Performance is highly dependent on disk speed. SSD provides 5-10x better performance than traditional HDD.

### Batch Processing Optimization

```r
# Optimal batch processing for SQLite
process_narratives_optimized <- function(narratives, db_path = "llm_results.db") {
  conn <- get_db_connection(db_path)
  
  # Apply optimizations
  optimize_sqlite(conn)
  
  # Process in optimal batch sizes
  batch_size <- 500  # Optimal for SQLite
  total <- length(narratives)
  batches <- split(narratives, ceiling(seq_along(narratives) / batch_size))
  
  results <- list()
  
  for (i in seq_along(batches)) {
    cat("Processing batch", i, "of", length(batches), "\n")
    
    # Process batch
    batch_results <- lapply(batches[[i]], function(narrative) {
      response <- call_llm(narrative, system_prompt)
      parse_llm_result(response)
    })
    
    # Store batch
    batch_result <- store_llm_results_batch(
      batch_results, 
      conn = conn,
      chunk_size = batch_size
    )
    
    results[[i]] <- batch_result
    
    cat("Batch", i, "complete:", batch_result$inserted, "inserted,", 
        batch_result$errors, "errors\n")
  }
  
  close_db_connection(conn)
  
  # Summary
  total_inserted <- sum(sapply(results, function(x) x$inserted))
  total_errors <- sum(sapply(results, function(x) x$errors))
  
  cat("\nProcessing complete:\n")
  cat("  Total processed:", total, "\n")
  cat("  Successfully inserted:", total_inserted, "\n") 
  cat("  Errors:", total_errors, "\n")
  cat("  Success rate:", round(total_inserted/total * 100, 1), "%\n")
  
  return(results)
}

# Usage
results <- process_narratives_optimized(your_narratives)
```

### Memory Optimization

```r
# Process large datasets without loading everything into memory
process_large_dataset <- function(input_file, db_path = "llm_results.db", chunk_size = 100) {
  # Read data in chunks to avoid memory issues
  if (grepl("\\.xlsx?$", input_file)) {
    if (!requireNamespace("readxl", quietly = TRUE)) {
      stop("readxl package required for Excel files")
    }
    
    # For Excel, read in chunks (Excel doesn't support streaming)
    total_data <- readxl::read_excel(input_file)
    total_rows <- nrow(total_data)
    
    conn <- get_db_connection(db_path)
    optimize_sqlite(conn)
    
    for (start_row in seq(1, total_rows, chunk_size)) {
      end_row <- min(start_row + chunk_size - 1, total_rows)
      chunk <- total_data[start_row:end_row, ]
      
      cat("Processing rows", start_row, "to", end_row, "\n")
      
      # Process chunk
      batch_results <- lapply(chunk$narrative, function(narrative) {
        response <- call_llm(narrative, system_prompt)
        parse_llm_result(response, narrative_id = as.character(runif(1)))
      })
      
      # Store immediately and clear from memory
      store_llm_results_batch(batch_results, conn = conn)
      rm(batch_results, chunk)
      gc()  # Force garbage collection
    }
    
    close_db_connection(conn)
    rm(total_data)
    
  } else if (grepl("\\.csv$", input_file)) {
    # For CSV, can read in chunks
    conn <- get_db_connection(db_path)
    optimize_sqlite(conn)
    
    # Read CSV header
    header <- read.csv(input_file, nrows = 1)
    
    # Process in chunks
    chunk_start <- 1
    repeat {
      chunk <- read.csv(input_file, skip = chunk_start, nrows = chunk_size, header = FALSE)
      colnames(chunk) <- colnames(header)
      
      if (nrow(chunk) == 0) break
      
      cat("Processing chunk starting at row", chunk_start, "\n")
      
      # Process and store chunk
      batch_results <- lapply(chunk$narrative, function(narrative) {
        response <- call_llm(narrative, system_prompt)
        parse_llm_result(response)
      })
      
      store_llm_results_batch(batch_results, conn = conn)
      
      chunk_start <- chunk_start + chunk_size
      rm(batch_results, chunk)
      gc()
    }
    
    close_db_connection(conn)
  }
}

# Usage  
process_large_dataset("large_dataset.xlsx", chunk_size = 50)
```

## Migration to PostgreSQL

### When to Migrate

Consider migrating from SQLite to PostgreSQL when you experience:

- **Concurrent access needs**: Multiple users/processes accessing the database
- **High write volume**: >1000 records/second sustained throughput needed
- **Complex queries**: Advanced analytics requiring better query optimization
- **Remote access**: Database needs to be accessed over network
- **Team collaboration**: Multiple researchers need shared access

### Migration Process

```r
# Migrate SQLite data to PostgreSQL
migrate_to_postgres <- function(sqlite_path = "llm_results.db", 
                               postgres_env = ".env") {
  # Connect to both databases
  sqlite_conn <- get_db_connection(sqlite_path)
  postgres_conn <- connect_postgres(postgres_env)
  
  # Ensure PostgreSQL schema exists
  ensure_schema(postgres_conn)
  
  # Get record count for progress tracking
  total_records <- DBI::dbGetQuery(sqlite_conn, "SELECT COUNT(*) as count FROM llm_results")$count
  cat("Migrating", total_records, "records from SQLite to PostgreSQL\n")
  
  # Read data in chunks to avoid memory issues
  chunk_size <- 1000
  migrated <- 0
  
  for (offset in seq(0, total_records - 1, chunk_size)) {
    # Read chunk from SQLite
    query <- sprintf("SELECT * FROM llm_results LIMIT %d OFFSET %d", chunk_size, offset)
    chunk_data <- DBI::dbGetQuery(sqlite_conn, query)
    
    if (nrow(chunk_data) == 0) break
    
    # Convert to list format for batch insert
    results_list <- apply(chunk_data, 1, function(row) {
      list(
        narrative_id = row[["narrative_id"]],
        narrative_text = row[["narrative_text"]],
        detected = as.logical(row[["detected"]]),
        confidence = as.numeric(row[["confidence"]]),
        model = row[["model"]],
        prompt_tokens = as.integer(row[["prompt_tokens"]]),
        completion_tokens = as.integer(row[["completion_tokens"]]),
        total_tokens = as.integer(row[["total_tokens"]]),
        response_time_ms = as.integer(row[["response_time_ms"]]),
        raw_response = row[["raw_response"]],
        error_message = row[["error_message"]]
      )
    })
    
    # Insert into PostgreSQL
    batch_result <- store_llm_results_batch(results_list, conn = postgres_conn)
    migrated <- migrated + batch_result$inserted
    
    cat("Progress:", migrated, "/", total_records, "records migrated\n")
  }
  
  # Verify migration
  postgres_count <- DBI::dbGetQuery(postgres_conn, "SELECT COUNT(*) as count FROM llm_results")$count
  
  # Clean up
  close_db_connection(sqlite_conn)
  close_db_connection(postgres_conn)
  
  # Results
  result <- list(
    sqlite_records = total_records,
    postgres_records = postgres_count,
    migration_complete = total_records == postgres_count,
    migrated_records = migrated
  )
  
  cat("Migration complete:\n")
  cat("  Source (SQLite):", result$sqlite_records, "records\n")
  cat("  Target (PostgreSQL):", result$postgres_records, "records\n")
  cat("  Success:", if(result$migration_complete) "YES" else "PARTIAL", "\n")
  
  return(result)
}

# Usage
migration_result <- migrate_to_postgres("llm_results.db")
```

## Analysis and Reporting

### Built-in Analysis Functions

```r
# Analyze IPV detection results
analyze_results <- function(db_path = "llm_results.db") {
  conn <- get_db_connection(db_path)
  
  # Basic statistics
  total_records <- DBI::dbGetQuery(conn, "SELECT COUNT(*) as count FROM llm_results")$count
  
  detected_stats <- DBI::dbGetQuery(conn, "
    SELECT 
      detected,
      COUNT(*) as count,
      AVG(confidence) as avg_confidence,
      MIN(confidence) as min_confidence,
      MAX(confidence) as max_confidence
    FROM llm_results 
    WHERE detected IS NOT NULL
    GROUP BY detected
  ")
  
  # Model performance  
  model_stats <- DBI::dbGetQuery(conn, "
    SELECT 
      model,
      COUNT(*) as count,
      AVG(CAST(detected as INTEGER)) as detection_rate,
      AVG(confidence) as avg_confidence,
      AVG(response_time_ms) as avg_response_time_ms
    FROM llm_results 
    WHERE model IS NOT NULL
    GROUP BY model
  ")
  
  close_db_connection(conn)
  
  # Summary report
  cat("IPV Detection Analysis\n")
  cat("=====================\n\n")
  cat("Total Records:", total_records, "\n\n")
  
  cat("Detection Results:\n")
  print(detected_stats)
  cat("\n")
  
  cat("Model Performance:\n")  
  print(model_stats)
  
  return(list(
    total_records = total_records,
    detected_stats = detected_stats,
    model_stats = model_stats
  ))
}

# Usage
analysis <- analyze_results("llm_results.db")
```

## Troubleshooting SQLite Issues

### Common Problems

1. **Database Locked**
   - Cause: Another process has the database open
   - Solution: Close all connections, use WAL mode

2. **Disk Full**  
   - Cause: No space for database growth
   - Solution: Free disk space, vacuum database

3. **Corruption**
   - Cause: Improper shutdown, hardware issues
   - Solution: Restore from backup, check integrity

4. **Slow Performance**
   - Cause: Missing indexes, large database, fragmentation
   - Solution: Add indexes, vacuum, optimize settings

See `docs/TROUBLESHOOTING.md` for detailed solutions.

## API Reference

### Connection Functions

- `get_db_connection(db_path, create)`: Connect to SQLite database
- `close_db_connection(conn)`: Safe connection cleanup  
- `test_connection_health(conn, detailed)`: Health check with metrics

### Storage Functions

- `store_llm_result(parsed_result, conn, db_path, auto_close)`: Single record storage
- `store_llm_results_batch(parsed_results, db_path, chunk_size, conn)`: Batch storage  
- `ensure_schema(conn)`: Create tables and indexes
- `detect_db_type(conn)`: Identify database backend (returns "sqlite")

### Utility Functions

- `validate_db_config(config, type)`: Pre-connection validation
- `execute_with_transaction(conn, code)`: Transaction wrapper
- `cleanup_connections(connections, force)`: Mass cleanup

## Best Practices

### Development Workflow

1. **Use separate databases for different stages**:
   - `dev_results.db` for development
   - `test_results.db` for testing  
   - `prod_results.db` for production analysis

2. **Regular backups**: Automate with `backup_sqlite()`

3. **Optimize early**: Apply `optimize_sqlite()` when creating new databases

4. **Monitor size**: Large databases (>1GB) may benefit from PostgreSQL

5. **Use transactions**: Batch operations are much faster

### Security Considerations

- SQLite files are readable by anyone with file access
- Store sensitive data in encrypted volumes if needed
- Use file permissions to restrict access (chmod 600)
- Consider SQLCipher for encryption if required

## Support

SQLite is zero-configuration and highly reliable. Most issues are related to:

1. File permissions (fix with chmod)
2. Disk space (monitor free space)  
3. Missing indexes (use optimize_sqlite())
4. Database locks (close connections properly)

The system is designed to be simple and robust. SQLite is an excellent choice for single-user research workflows and development.