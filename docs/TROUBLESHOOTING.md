# Troubleshooting Guide

## Philosophy

This system follows Unix principles: simple tools that do one thing well. Most issues stem from configuration, network connectivity, or data format problems. This guide provides evidence-based solutions for common scenarios.

## Quick Diagnostics

### System Health Check

```r
# Load the package
library(IPVdetection)

# Test LLM connection
test_result <- tryCatch({
  call_llm("test", "test")
}, error = function(e) e)

# Test database connection (SQLite)
db_result <- tryCatch({
  conn <- get_db_connection("test.db")
  DBI::dbDisconnect(conn)
  unlink("test.db")
  "OK"
}, error = function(e) e)

# Test database connection (PostgreSQL)
pg_result <- tryCatch({
  conn <- connect_postgres()
  test_connection_health(conn)
}, error = function(e) e)

cat("LLM API:", if(inherits(test_result, "error")) "FAILED" else "OK", "\n")
cat("SQLite:", if(inherits(db_result, "error")) "FAILED" else "OK", "\n")
cat("PostgreSQL:", if(inherits(pg_result, "error")) "FAILED" else "OK", "\n")
```

## LLM Connection Issues

### Problem: Connection Timeout or Refused

**Symptoms:**
- `Error: Failed to perform HTTP request: Timeout was reached`
- `Error: Failed to connect to host`
- `Error: Connection refused`

**Solutions:**

1. **Check LLM Server Status**
   ```r
   # Test basic connectivity
   api_url <- Sys.getenv("LLM_API_URL", "http://192.168.10.22:1234/v1/chat/completions")
   httr2::request(gsub("/v1/chat/completions", "/v1/models", api_url)) |>
     httr2::req_perform()
   ```

2. **Verify Environment Variables**
   ```r
   cat("API URL:", Sys.getenv("LLM_API_URL", "default: http://192.168.10.22:1234/v1/chat/completions"), "\n")
   cat("Model:", Sys.getenv("LLM_MODEL", "default: openai/gpt-oss-120b"), "\n")
   ```

3. **Network Connectivity**
   ```bash
   # Test basic connectivity
   curl -I http://192.168.10.22:1234/v1/models
   
   # Check if port is open
   telnet 192.168.10.22 1234
   ```

4. **Increase Timeout**
   ```r
   # Custom timeout in call_llm
   response <- httr2::request(api_url) |>
     httr2::req_body_json(request_body) |>
     httr2::req_timeout(60) |>  # Increase to 60 seconds
     httr2::req_perform() |>
     httr2::resp_body_json()
   ```

### Problem: Authentication/Authorization Errors

**Symptoms:**
- `Error: HTTP 401 Unauthorized`
- `Error: HTTP 403 Forbidden`
- `Error: API key required`

**Solutions:**

1. **Check API Key Configuration**
   ```r
   # If your LLM requires authentication
   headers <- list("Authorization" = paste("Bearer", Sys.getenv("LLM_API_KEY")))
   
   response <- httr2::request(api_url) |>
     httr2::req_headers(!!!headers) |>
     httr2::req_body_json(request_body) |>
     httr2::req_perform()
   ```

2. **Verify Model Access**
   ```r
   # List available models
   models <- httr2::request(gsub("/v1/chat/completions", "/v1/models", api_url)) |>
     httr2::req_perform() |>
     httr2::resp_body_json()
   cat("Available models:", paste(sapply(models$data, function(x) x$id), collapse = ", "))
   ```

### Problem: Malformed Response/Parsing Errors

**Symptoms:**
- `Error: lexical error: invalid char in json text`
- `detected = NA, confidence = 0`
- `parse_error = TRUE`

**Solutions:**

1. **Check Response Format**
   ```r
   # Debug the raw response
   response <- call_llm("Analyze text", "Return JSON with detected and confidence")
   cat("Raw response:", response$choices[[1]]$message$content, "\n")
   
   # Parse and check
   parsed <- parse_llm_result(response)
   if (parsed$parse_error) {
     cat("Parse error:", parsed$error_message, "\n")
     cat("Raw content:", parsed$raw_response, "\n")
   }
   ```

2. **Improve Prompt Structure**
   ```r
   # More specific JSON instruction
   system_prompt <- "You are an IPV detector. Respond ONLY with valid JSON in this exact format: {\"detected\": true/false, \"confidence\": 0.0-1.0}"
   user_prompt <- "Analyze this narrative for intimate partner violence indicators: [text]"
   ```

3. **Handle Common Format Issues**
   ```r
   # The parser handles these automatically, but you can debug:
   test_cases <- c(
     '{"detected": true, "confidence": 0.8}',  # Standard
     '```json\n{"detected": true, "confidence": 0.8}\n```',  # Markdown wrapped
     'The analysis shows: {"detected": true, "confidence": 0.8}',  # Text + JSON
     'detected: true\nconfidence: 0.8'  # YAML-like
   )
   
   for (case in test_cases) {
     result <- parse_llm_result(list(choices = list(list(message = list(content = case)))))
     cat("Detected:", result$detected, "Confidence:", result$confidence, "\n")
   }
   ```

## Database Connection Issues

### SQLite Problems

**Problem: File Permission Errors**

**Symptoms:**
- `Error: unable to open database file`
- `Error: database is locked`
- `Error: disk I/O error`

**Solutions:**

1. **Check File Permissions**
   ```bash
   # Check if directory is writable
   ls -la llm_results.db
   
   # Fix permissions if needed
   chmod 664 llm_results.db
   chmod 775 $(dirname llm_results.db)
   ```

2. **Handle Locked Database**
   ```r
   # Close all connections
   lapply(dbListConnections(drv = RSQLite::SQLite()), DBI::dbDisconnect)
   
   # Use WAL mode for better concurrency
   conn <- get_db_connection("llm_results.db")
   DBI::dbExecute(conn, "PRAGMA journal_mode = WAL")
   DBI::dbDisconnect(conn)
   ```

3. **Database Corruption**
   ```r
   # Check database integrity
   conn <- get_db_connection("llm_results.db")
   integrity <- DBI::dbGetQuery(conn, "PRAGMA integrity_check")
   print(integrity)
   DBI::dbDisconnect(conn)
   
   # Backup and repair if needed
   file.copy("llm_results.db", "llm_results_backup.db")
   # If integrity check fails, restore from backup or recreate
   ```

**Problem: Performance Issues with Large Datasets**

**Solutions:**

1. **Add Indexes**
   ```r
   conn <- get_db_connection("llm_results.db")
   DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_narrative_id ON llm_results(narrative_id)")
   DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_created_at ON llm_results(created_at)")
   DBI::dbExecute(conn, "ANALYZE")  # Update statistics
   DBI::dbDisconnect(conn)
   ```

2. **Use Batch Operations**
   ```r
   # Instead of individual inserts
   # Use store_llm_results_batch() for better performance
   results_batch <- store_llm_results_batch(parsed_results, chunk_size = 1000)
   ```

### PostgreSQL Problems

**Problem: Connection Failures**

**Symptoms:**
- `Error: could not connect to server`
- `Error: FATAL: password authentication failed`
- `Error: FATAL: database does not exist`

**Solutions:**

1. **Check Environment Configuration**
   ```r
   # Verify all required variables are set
   required_vars <- c("POSTGRES_HOST", "POSTGRES_DB", "POSTGRES_USER", "POSTGRES_PASSWORD")
   missing <- required_vars[sapply(required_vars, function(x) Sys.getenv(x) == "")]
   
   if (length(missing) > 0) {
     cat("Missing environment variables:", paste(missing, collapse = ", "), "\n")
     cat("Create .env file with:\n")
     for (var in missing) {
       cat(paste0(var, "=your_value\n"))
     }
   }
   ```

2. **Test Network Connectivity**
   ```bash
   # Test if PostgreSQL port is accessible
   telnet your-postgres-host 5432
   
   # Test with psql if available
   psql -h your-postgres-host -U your-user -d your-database -c "SELECT 1"
   ```

3. **Connection Pool Exhaustion**
   ```r
   # Check active connections
   conn <- connect_postgres()
   active_conns <- DBI::dbGetQuery(conn, 
     "SELECT count(*) as active FROM pg_stat_activity WHERE datname = current_database()")
   print(active_conns)
   
   # Clean up connections properly
   close_db_connection(conn)
   
   # Or use cleanup utility
   cleanup_connections(force = TRUE)
   ```

**Problem: Performance Issues**

**Solutions:**

1. **Connection Health Check**
   ```r
   conn <- connect_postgres()
   health <- test_connection_health(conn, detailed = TRUE)
   
   if (health$response_time_ms > 100) {
     cat("WARNING: High latency connection (", health$response_time_ms, "ms)\n")
     cat("Consider using local PostgreSQL or optimizing network\n")
   }
   ```

2. **Query Performance**
   ```r
   # Check for slow queries (requires logging enabled in postgresql.conf)
   conn <- connect_postgres()
   slow_queries <- DBI::dbGetQuery(conn, 
     "SELECT query, mean_time FROM pg_stat_statements WHERE mean_time > 1000")
   print(slow_queries)
   ```

3. **Optimize Batch Size**
   ```r
   # Adjust chunk_size based on network latency
   # High latency: use larger chunks (5000-10000)
   # Low latency: use smaller chunks (1000-2000)
   result <- store_llm_results_batch(parsed_results, chunk_size = 5000)
   ```

## Data Format Issues

### Problem: Text Encoding Issues

**Symptoms:**
- Special characters display as `?` or `ÄÖÜ`
- `Error: input string is not valid UTF-8`
- Parsing fails with Unicode characters

**Solutions:**

1. **Ensure UTF-8 Encoding**
   ```r
   # Check and fix encoding
   text <- "Your narrative text with special chars"
   
   # Force UTF-8 encoding
   text_utf8 <- iconv(text, to = "UTF-8", sub = "")
   
   # Check for valid UTF-8
   if (is.na(text_utf8)) {
     cat("Invalid UTF-8 detected, converting...\n")
     text_utf8 <- iconv(text, to = "UTF-8", sub = "?")
   }
   ```

2. **Handle Database Encoding**
   ```r
   # For PostgreSQL, ensure UTF-8 database
   conn <- connect_postgres()
   encoding <- DBI::dbGetQuery(conn, "SHOW server_encoding")
   print(encoding)  # Should be UTF8
   
   # For SQLite, UTF-8 is default
   ```

### Problem: Large Text Handling

**Symptoms:**
- `Error: string is too long`
- Truncated responses
- Memory issues with large narratives

**Solutions:**

1. **Check Text Limits**
   ```r
   # Check narrative length
   narrative_length <- nchar(your_text)
   cat("Narrative length:", narrative_length, "characters\n")
   
   # Most LLMs have context limits (e.g., 4K, 8K, 32K tokens)
   # Rough estimate: 1 token ≈ 4 characters
   estimated_tokens <- ceiling(narrative_length / 4)
   cat("Estimated tokens:", estimated_tokens, "\n")
   ```

2. **Truncate if Necessary**
   ```r
   # Truncate to maximum safe length (e.g., 16K chars ≈ 4K tokens)
   max_length <- 16000
   if (nchar(your_text) > max_length) {
     truncated <- substr(your_text, 1, max_length)
     cat("WARNING: Text truncated from", nchar(your_text), "to", max_length, "characters\n")
     your_text <- truncated
   }
   ```

### Problem: Empty or NULL Data

**Symptoms:**
- `detected = NA, confidence = 0`
- Empty results for valid-looking data
- Inconsistent results

**Solutions:**

1. **Check for Empty Inputs**
   ```r
   # The system handles these automatically, but you can check:
   test_inputs <- c(
     "",           # Empty string
     "   ",        # Whitespace only
     NA,           # NA value
     NULL          # NULL value
   )
   
   for (input in test_inputs) {
     result <- detect_ipv(input)
     cat("Input:", deparse(input), "-> Detected:", result$detected, "\n")
   }
   ```

2. **Data Validation**
   ```r
   # Validate your data before processing
   validate_narrative <- function(text) {
     if (is.null(text) || is.na(text)) return("NULL/NA")
     if (!is.character(text)) return("Not character")
     if (length(text) != 1) return("Not single string")
     if (nchar(trimws(text)) == 0) return("Empty after trimming")
     return("Valid")
   }
   
   # Check a batch
   validation_results <- sapply(your_narratives, validate_narrative)
   invalid_count <- sum(validation_results != "Valid")
   if (invalid_count > 0) {
     cat("WARNING:", invalid_count, "invalid narratives detected\n")
     print(table(validation_results))
   }
   ```

## Performance Problems

### Problem: Slow Processing Speed

**Typical Performance Targets:**
- SQLite local: 10-50 records/second
- PostgreSQL local: 50-200 records/second  
- PostgreSQL network: 25-100 records/second
- LLM API calls: 1-10 calls/second (varies by model/hardware)

**Solutions:**

1. **Profile Your Bottleneck**
   ```r
   library(tictoc)
   
   # Time LLM calls
   tic("LLM call")
   llm_response <- call_llm(user_prompt, system_prompt)
   toc()
   
   # Time parsing
   tic("Parsing")
   parsed <- parse_llm_result(llm_response)
   toc()
   
   # Time database storage
   tic("Database storage")
   conn <- connect_db()
   store_llm_result(parsed, conn)
   toc()
   ```

2. **Optimize LLM Calls**
   ```r
   # Reduce temperature for faster processing
   response <- call_llm(user_prompt, system_prompt, temperature = 0)
   
   # Use shorter, more direct prompts
   system_prompt <- "Detect IPV. Respond: {\"detected\": boolean, \"confidence\": number}"
   ```

3. **Optimize Database Operations**
   ```r
   # Use batch operations
   batch_size <- 100  # Adjust based on memory
   results <- store_llm_results_batch(parsed_results, chunk_size = batch_size)
   
   # Keep connections open for multiple operations
   conn <- connect_db()
   for (batch in batches) {
     store_llm_result(batch, conn)
   }
   close_db_connection(conn)
   ```

4. **Parallel Processing (Advanced)**
   ```r
   library(parallel)
   
   # Process in parallel (be careful with database connections)
   cl <- makeCluster(detectCores() - 1)
   clusterEvalQ(cl, library(IPVdetection))
   
   # Split data and process
   chunks <- split(your_narratives, ceiling(seq_along(your_narratives)/100))
   results <- parLapply(cl, chunks, function(chunk) {
     # Each worker creates its own database connection
     conn <- connect_db(paste0("results_", Sys.getpid(), ".db"))
     on.exit(close_db_connection(conn))
     
     lapply(chunk, function(narrative) {
       response <- call_llm(narrative, system_prompt)
       parsed <- parse_llm_result(response)
       store_llm_result(parsed, conn)
       parsed
     })
   })
   stopCluster(cl)
   ```

### Problem: Memory Issues

**Symptoms:**
- `Error: cannot allocate vector of size`
- R session crashes
- System becomes unresponsive

**Solutions:**

1. **Process in Smaller Batches**
   ```r
   # Instead of loading everything into memory
   batch_size <- 100
   total_records <- length(your_narratives)
   
   for (i in seq(1, total_records, batch_size)) {
     end_idx <- min(i + batch_size - 1, total_records)
     batch <- your_narratives[i:end_idx]
     
     # Process batch
     results <- lapply(batch, process_narrative)
     
     # Clear intermediate results
     rm(results)
     gc()  # Force garbage collection
   }
   ```

2. **Monitor Memory Usage**
   ```r
   # Check memory usage
   cat("Memory usage:", format(object.size(your_data), units = "MB"), "\n")
   
   # Profile memory during processing
   library(profvis)
   profvis({
     your_processing_code()
   })
   ```

## Error Recovery Patterns

### Robust Batch Processing

```r
process_narratives_robust <- function(narratives, output_file = "results.rds") {
  results <- list()
  errors <- list()
  processed <- 0
  
  # Resume from previous run if exists
  if (file.exists(output_file)) {
    existing <- readRDS(output_file)
    results <- existing$results
    processed <- existing$processed
    cat("Resuming from record", processed + 1, "\n")
  }
  
  conn <- tryCatch(connect_db(), error = function(e) NULL)
  if (is.null(conn)) {
    stop("Cannot connect to database")
  }
  on.exit(close_db_connection(conn))
  
  for (i in (processed + 1):length(narratives)) {
    tryCatch({
      # Process single narrative
      response <- call_llm(narratives[[i]], system_prompt)
      parsed <- parse_llm_result(response, narrative_id = names(narratives)[i])
      store_llm_result(parsed, conn)
      
      results[[length(results) + 1]] <- parsed
      processed <- i
      
      # Save progress every 10 records
      if (i %% 10 == 0) {
        saveRDS(list(results = results, processed = processed, errors = errors), output_file)
        cat("Progress:", i, "/", length(narratives), "\n")
      }
      
    }, error = function(e) {
      errors[[length(errors) + 1]] <- list(
        index = i,
        narrative_id = names(narratives)[i],
        error = e$message,
        timestamp = Sys.time()
      )
      cat("Error at", i, ":", e$message, "\n")
    })
  }
  
  # Save final results
  final_results <- list(results = results, processed = processed, errors = errors)
  saveRDS(final_results, output_file)
  
  # Summary
  cat("Processing complete:\n")
  cat("  Processed:", length(results), "records\n")
  cat("  Errors:", length(errors), "records\n")
  cat("  Success rate:", round(length(results)/(length(results) + length(errors)) * 100, 1), "%\n")
  
  return(final_results)
}
```

## Getting Help

### Debug Information Collection

When reporting issues, include this debug information:

```r
# System information
cat("R version:", R.version.string, "\n")
cat("Platform:", R.version$platform, "\n")
cat("OS:", Sys.info()["sysname"], Sys.info()["release"], "\n")

# Package versions
packages <- c("DBI", "RSQLite", "RPostgres", "httr2", "jsonlite", "dotenv")
for (pkg in packages) {
  if (requireNamespace(pkg, quietly = TRUE)) {
    cat(pkg, ":", as.character(packageVersion(pkg)), "\n")
  } else {
    cat(pkg, ": NOT INSTALLED\n")
  }
}

# Configuration
cat("LLM_API_URL:", Sys.getenv("LLM_API_URL", "not set"), "\n")
cat("LLM_MODEL:", Sys.getenv("LLM_MODEL", "not set"), "\n")
cat("POSTGRES_HOST:", Sys.getenv("POSTGRES_HOST", "not set"), "\n")
cat("Working directory:", getwd(), "\n")

# Test basic functionality
cat("Basic function test:\n")
tryCatch({
  test_result <- detect_ipv("test narrative")
  cat("  detect_ipv() result:", names(test_result), "\n")
}, error = function(e) {
  cat("  detect_ipv() failed:", e$message, "\n")
})
```

### Common Solutions Summary

| Problem Type | Quick Fix | Command |
|--------------|-----------|---------|
| LLM timeout | Increase timeout | `httr2::req_timeout(60)` |
| Database locked | Close connections | `lapply(dbListConnections(SQLite()), dbDisconnect)` |
| Parse error | Check raw response | `cat(response$choices[[1]]$message$content)` |
| Memory issues | Process in batches | `for (i in seq(1, n, 100)) { ... }` |
| Encoding issues | Force UTF-8 | `iconv(text, to = "UTF-8")` |
| Connection failed | Check environment | `Sys.getenv("POSTGRES_HOST")` |

### Philosophy on Error Handling

This system follows the Unix philosophy: 

1. **Fail fast and explicitly** - Errors are not hidden
2. **Provide useful error messages** - Include context for debugging  
3. **Let users decide recovery** - Don't implement complex retry logic
4. **Keep it simple** - Most issues are configuration problems

The system is designed to be debuggable and transparent. When something fails, you should be able to understand why and fix it yourself.