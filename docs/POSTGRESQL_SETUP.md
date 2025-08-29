# PostgreSQL Production Setup Guide

## Overview

This guide covers production deployment of the IPV detection system with PostgreSQL backend. The PostgreSQL implementation provides enhanced performance (>5000 inserts/second), connection pooling, and concurrent access support for large-scale deployments.

## Prerequisites

### Required R Packages

```r
install.packages(c(
  "DBI",           # Database interface
  "RPostgres",     # PostgreSQL driver
  "dotenv",        # Environment variable management
  "tibble",        # Data frames
  "dplyr"          # Data manipulation
))
```

### PostgreSQL Server Requirements

- PostgreSQL 12+ (recommended: PostgreSQL 15+)
- Minimum 4GB RAM for production workloads
- SSD storage for optimal performance
- Network access configured for application servers

## Quick Start

### 1. Environment Configuration

Create a `.env` file in your project root:

```bash
# PostgreSQL Connection Settings
POSTGRES_HOST=your-postgres-host
POSTGRES_PORT=5432
POSTGRES_DB=ipv_detection
POSTGRES_USER=ipv_user
POSTGRES_PASSWORD=your-secure-password
```

### 2. Basic Connection Test

```r
# Load the package
library(IPVdetection)

# Test connection
conn <- connect_postgres()
health <- test_connection_health(conn, detailed = TRUE)
print(health)

# Clean up
close_db_connection(conn)
```

### 3. Schema Setup

The schema is automatically created when you first store results:

```r
# First store operation creates schema
result <- store_llm_result(your_parsed_result)
```

## Production Deployment

### Database Server Setup

#### 1. Create Database and User

```sql
-- Connect as superuser (postgres)
CREATE DATABASE ipv_detection;
CREATE USER ipv_user WITH PASSWORD 'your-secure-password';

-- Grant permissions
GRANT ALL PRIVILEGES ON DATABASE ipv_detection TO ipv_user;
\c ipv_detection
GRANT ALL ON SCHEMA public TO ipv_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ipv_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ipv_user;
```

#### 2. Performance Optimizations

Add these settings to `postgresql.conf`:

```conf
# Memory settings
shared_buffers = 256MB              # 25% of system RAM
effective_cache_size = 1GB          # 75% of system RAM
work_mem = 16MB                     # Per connection sort memory

# Connection settings
max_connections = 200               # Adjust based on load
connection_limit = 100              # Per user limit

# Performance settings
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1              # For SSD storage

# Logging for monitoring
log_statement = 'mod'               # Log modifications
log_duration = on
log_min_duration_statement = 1000ms # Log slow queries
```

#### 3. Security Configuration

Update `pg_hba.conf`:

```conf
# Type  Database        User            Address                 Method
host    ipv_detection   ipv_user        10.0.0.0/8             scram-sha-256
host    ipv_detection   ipv_user        192.168.0.0/16         scram-sha-256
hostssl ipv_detection   ipv_user        0.0.0.0/0              scram-sha-256
```

### Application Server Setup

#### 1. Environment Variables

For production, use environment variables instead of `.env` files:

```bash
export POSTGRES_HOST=prod-postgres-host
export POSTGRES_PORT=5432
export POSTGRES_DB=ipv_detection
export POSTGRES_USER=ipv_user
export POSTGRES_PASSWORD=your-secure-password
```

#### 2. Connection Validation

```r
# Validate configuration before deployment
library(IPVdetection)

config_check <- validate_db_config(NULL, "postgresql")
if (!config_check$valid) {
  stop("Invalid database configuration: ", paste(config_check$errors, collapse = "; "))
}
```

#### 3. Health Monitoring

```r
# Production health check script
monitor_db_health <- function() {
  conn <- tryCatch(connect_postgres(), error = function(e) NULL)
  
  if (is.null(conn)) {
    return(list(status = "ERROR", message = "Connection failed"))
  }
  
  health <- test_connection_health(conn, detailed = TRUE)
  close_db_connection(conn)
  
  if (health$healthy && health$response_time_ms < 100) {
    return(list(status = "OK", response_time = health$response_time_ms))
  } else {
    return(list(status = "WARNING", health = health))
  }
}
```

## Performance Tuning

### Expected Performance Metrics

- **Single inserts**: 100-500 inserts/second
- **Batch inserts**: >5000 inserts/second
- **Connection time**: <100ms
- **Query response**: <50ms for simple operations

### Batch Processing Optimization

```r
# Optimal batch processing
results <- your_llm_results  # List of parsed results

# Use batch function for maximum performance
batch_result <- store_llm_results_batch(
  results, 
  db_path = NULL,     # Uses environment config
  chunk_size = 5000   # Optimal for PostgreSQL
)

# Check performance
cat(sprintf("Processed %d records: %d inserted, %d duplicates, %d errors\n",
    batch_result$total, batch_result$inserted, 
    batch_result$duplicates, batch_result$errors))
cat(sprintf("Success rate: %.1f%%\n", batch_result$success_rate * 100))
```

### Connection Pooling

For high-concurrency applications, consider using connection pooling:

```r
# Example with manual connection management
conn <- connect_postgres()
ensure_schema(conn)

# Process multiple batches with same connection
for (batch in your_batches) {
  result <- store_llm_results_batch(batch, conn = conn)
  # Connection stays open between batches
}

# Close when done
close_db_connection(conn)
```

## Migration from SQLite

### Data Migration Script

```r
migrate_sqlite_to_postgres <- function(sqlite_path, postgres_env = ".env") {
  # Connect to both databases
  sqlite_conn <- get_db_connection(sqlite_path)
  postgres_conn <- connect_postgres(postgres_env)
  
  # Ensure PostgreSQL schema exists
  ensure_schema(postgres_conn)
  
  # Read all data from SQLite
  data <- DBI::dbReadTable(sqlite_conn, "llm_results")
  
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
  
  # Batch insert to PostgreSQL
  migration_result <- store_llm_results_batch(results_list, conn = postgres_conn)
  
  # Clean up
  close_db_connection(sqlite_conn)
  close_db_connection(postgres_conn)
  
  migration_result
}

# Usage
result <- migrate_sqlite_to_postgres("llm_results.db")
print(result)
```

### Verification

```r
# Verify migration completed successfully
verify_migration <- function(sqlite_path, postgres_env = ".env") {
  sqlite_conn <- get_db_connection(sqlite_path)
  postgres_conn <- connect_postgres(postgres_env)
  
  # Count records in both databases
  sqlite_count <- DBI::dbGetQuery(sqlite_conn, "SELECT COUNT(*) as count FROM llm_results")$count
  postgres_count <- DBI::dbGetQuery(postgres_conn, "SELECT COUNT(*) as count FROM llm_results")$count
  
  close_db_connection(sqlite_conn)
  close_db_connection(postgres_conn)
  
  list(
    sqlite_records = sqlite_count,
    postgres_records = postgres_count,
    migration_complete = sqlite_count == postgres_count
  )
}
```

## Troubleshooting

### Common Issues

#### Connection Timeouts

```r
# Increase timeout for slow networks
conn <- connect_postgres(timeout = 30, retry_attempts = 5)
```

#### Performance Issues

```r
# Check connection health
health <- test_connection_health(conn, detailed = TRUE)
print(health$response_time_ms)  # Should be < 100ms

# Enable query logging in PostgreSQL to identify slow queries
```

#### Memory Issues

```r
# Use smaller chunk sizes for limited memory
result <- store_llm_results_batch(results, chunk_size = 1000)
```

### Monitoring Queries

```sql
-- Check active connections
SELECT count(*) FROM pg_stat_activity WHERE datname = 'ipv_detection';

-- Monitor table size
SELECT 
  schemaname, tablename, 
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables 
WHERE tablename = 'llm_results';

-- Check recent activity
SELECT 
  query_start, state, query
FROM pg_stat_activity 
WHERE datname = 'ipv_detection' AND state = 'active';
```

## Security Considerations

### Connection Security

1. **Use SSL/TLS** for production connections
2. **Limit network access** via firewall rules
3. **Use strong passwords** and rotate regularly
4. **Monitor connection logs** for suspicious activity

### Application Security

```r
# Example secure connection with SSL
conn <- DBI::dbConnect(
  RPostgres::Postgres(),
  host = Sys.getenv("POSTGRES_HOST"),
  port = as.integer(Sys.getenv("POSTGRES_PORT")),
  dbname = Sys.getenv("POSTGRES_DB"),
  user = Sys.getenv("POSTGRES_USER"),
  password = Sys.getenv("POSTGRES_PASSWORD"),
  sslmode = "require"  # Force SSL
)
```

## Backup and Recovery

### Automated Backup Script

```bash
#!/bin/bash
# backup_ipv_db.sh

DB_NAME="ipv_detection"
BACKUP_DIR="/backups"
DATE=$(date +%Y%m%d_%H%M%S)

pg_dump -h $POSTGRES_HOST -U $POSTGRES_USER -d $DB_NAME \
  | gzip > $BACKUP_DIR/ipv_detection_$DATE.sql.gz

# Keep only last 7 days
find $BACKUP_DIR -name "ipv_detection_*.sql.gz" -mtime +7 -delete
```

### Recovery

```bash
# Restore from backup
gunzip -c /backups/ipv_detection_YYYYMMDD_HHMMSS.sql.gz | \
  psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $DB_NAME
```

## API Reference

### Connection Functions

- `connect_postgres(env_file, timeout, retry_attempts)`: Connect with retry logic
- `get_unified_connection(db_config, type, env_file)`: Auto-detect connection type
- `close_db_connection(conn)`: Safe connection cleanup
- `test_connection_health(conn, detailed)`: Health check with metrics

### Storage Functions

- `store_llm_result(parsed_result, conn, db_path, auto_close)`: Single record storage
- `store_llm_results_batch(parsed_results, db_path, chunk_size, conn)`: Batch storage
- `ensure_schema(conn)`: Create tables and indexes
- `detect_db_type(conn)`: Identify database backend

### Utility Functions

- `validate_db_config(config, type)`: Pre-connection validation
- `execute_with_transaction(conn, code)`: Transaction wrapper
- `cleanup_connections(connections, force)`: Mass cleanup

## Support

For issues with this setup:

1. Check the troubleshooting section above
2. Verify environment variables are set correctly
3. Ensure PostgreSQL server is accessible and configured properly
4. Review PostgreSQL logs for detailed error messages

The system is designed to be simple and robust - most issues stem from environment configuration or network connectivity.