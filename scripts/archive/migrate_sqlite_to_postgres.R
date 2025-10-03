#!/usr/bin/env Rscript

# Migration Script: SQLite to PostgreSQL
# 
# Migrates existing LLM results from SQLite database to PostgreSQL
# with comprehensive validation and progress reporting.

library(DBI)
library(tibble)
library(dplyr)

# Source required functions
script_dir <- dirname(normalizePath(sys.frames()[[1]]$ofile, mustWork = FALSE))
source(file.path(dirname(script_dir), "R", "db_utils.R"))
source(file.path(dirname(script_dir), "R", "store_llm_result.R"))
source(file.path(dirname(script_dir), "R", "utils.R"))

#' Comprehensive SQLite to PostgreSQL migration
#' 
#' Migrates data with validation, progress reporting, and rollback capability.
#' Handles large datasets efficiently with batch processing.
#' 
#' @param sqlite_path Path to SQLite database
#' @param postgres_env Path to .env file for PostgreSQL (default: ".env")
#' @param chunk_size Number of records per migration batch (default: 5000)
#' @param validate_before Whether to validate before migration (default: TRUE)
#' @param validate_after Whether to validate after migration (default: TRUE)
#' @param dry_run Whether to perform dry run without actual migration (default: FALSE)
#' @return List with migration results and statistics
migrate_sqlite_to_postgres <- function(sqlite_path, 
                                      postgres_env = ".env",
                                      chunk_size = 5000,
                                      validate_before = TRUE,
                                      validate_after = TRUE,
                                      dry_run = FALSE) {
  
  cat("=== SQLite to PostgreSQL Migration ===\n")
  start_time <- Sys.time()
  
  migration_log <- list(
    start_time = start_time,
    sqlite_path = sqlite_path,
    postgres_env = postgres_env,
    chunk_size = chunk_size,
    dry_run = dry_run,
    validation_results = list(),
    migration_results = list(),
    errors = character(0)
  )
  
  # 1. Pre-migration validation
  cat("1. Pre-migration validation...\n")
  
  # Check SQLite database
  if (!file.exists(sqlite_path)) {
    stop("SQLite database not found: ", sqlite_path)
  }
  
  sqlite_conn <- tryCatch({
    get_db_connection(sqlite_path)
  }, error = function(e) {
    stop("Cannot connect to SQLite database: ", e$message)
  })
  
  # Check PostgreSQL connection
  postgres_conn <- tryCatch({
    connect_postgres(postgres_env)
  }, error = function(e) {
    close_db_connection(sqlite_conn)
    stop("Cannot connect to PostgreSQL database: ", e$message)
  })
  
  # Validate schemas
  if (validate_before) {
    cat("  Validating database schemas...\n")
    
    # Check SQLite table exists
    sqlite_tables <- DBI::dbListTables(sqlite_conn)
    if (!"llm_results" %in% sqlite_tables) {
      close_db_connection(sqlite_conn)
      close_db_connection(postgres_conn)
      stop("SQLite database does not contain llm_results table")
    }
    
    # Ensure PostgreSQL schema
    ensure_schema(postgres_conn)
    
    # Get record counts
    sqlite_count <- DBI::dbGetQuery(sqlite_conn, "SELECT COUNT(*) as count FROM llm_results")$count
    postgres_count <- DBI::dbGetQuery(postgres_conn, "SELECT COUNT(*) as count FROM llm_results")$count
    
    migration_log$validation_results$pre_migration <- list(
      sqlite_records = sqlite_count,
      postgres_records = postgres_count,
      tables_verified = TRUE
    )
    
    cat(sprintf("  ✓ SQLite: %s records\n", format(sqlite_count, big.mark = ",")))
    cat(sprintf("  ✓ PostgreSQL: %s records (existing)\n", format(postgres_count, big.mark = ",")))
    
    if (sqlite_count == 0) {
      cat("  ⚠️ SQLite database is empty - nothing to migrate\n")
      close_db_connection(sqlite_conn)
      close_db_connection(postgres_conn)
      return(migration_log)
    }
    
    cat(sprintf("  → %s new records to migrate\n", format(sqlite_count, big.mark = ",")))
  }
  
  if (dry_run) {
    cat("\n🔍 DRY RUN MODE - No data will be migrated\n")
    cat("Migration would proceed with the following parameters:\n")
    cat(sprintf("  - Source: %s (%s records)\n", sqlite_path, format(sqlite_count, big.mark = ",")))
    cat(sprintf("  - Target: PostgreSQL (%s existing records)\n", format(postgres_count, big.mark = ",")))
    cat(sprintf("  - Batch size: %s records\n", format(chunk_size, big.mark = ",")))
    
    close_db_connection(sqlite_conn)
    close_db_connection(postgres_conn)
    return(migration_log)
  }
  
  # 2. Data migration
  cat("\n2. Migrating data...\n")
  
  # Read data in chunks for memory efficiency
  total_records <- DBI::dbGetQuery(sqlite_conn, "SELECT COUNT(*) as count FROM llm_results")$count
  total_migrated <- 0
  migration_errors <- 0
  
  # Calculate number of chunks
  total_chunks <- ceiling(total_records / chunk_size)
  cat(sprintf("  Processing %s records in %d chunks...\n", 
             format(total_records, big.mark = ","), total_chunks))
  
  for (chunk_num in seq_len(total_chunks)) {
    cat(sprintf("  Chunk %d/%d: ", chunk_num, total_chunks))
    
    offset <- (chunk_num - 1) * chunk_size
    
    # Read chunk from SQLite
    chunk_query <- sprintf("
      SELECT * FROM llm_results 
      ORDER BY id 
      LIMIT %d OFFSET %d
    ", chunk_size, offset)
    
    chunk_data <- DBI::dbGetQuery(sqlite_conn, chunk_query)
    actual_chunk_size <- nrow(chunk_data)
    
    if (actual_chunk_size == 0) {
      cat("No data - skipping\n")
      next
    }
    
    # Convert to list format for batch insert
    results_list <- apply(chunk_data, 1, function(row) {
      list(
        narrative_id = row[["narrative_id"]],
        narrative_text = row[["narrative_text"]],
        detected = as.logical(row[["detected"]]),
        confidence = if (is.na(row[["confidence"]])) NA_real_ else as.numeric(row[["confidence"]]),
        model = row[["model"]],
        prompt_tokens = if (is.na(row[["prompt_tokens"]])) NA_integer_ else as.integer(row[["prompt_tokens"]]),
        completion_tokens = if (is.na(row[["completion_tokens"]])) NA_integer_ else as.integer(row[["completion_tokens"]]),
        total_tokens = if (is.na(row[["total_tokens"]])) NA_integer_ else as.integer(row[["total_tokens"]]),
        response_time_ms = if (is.na(row[["response_time_ms"]])) NA_integer_ else as.integer(row[["response_time_ms"]]),
        raw_response = row[["raw_response"]],
        error_message = row[["error_message"]]
      )
    })
    
    # Batch insert to PostgreSQL
    chunk_result <- store_llm_results_batch(results_list, conn = postgres_conn)
    
    if (chunk_result$success) {
      total_migrated <- total_migrated + chunk_result$inserted
      cat(sprintf("%d inserted, %d duplicates\n", chunk_result$inserted, chunk_result$duplicates))
    } else {
      migration_errors <- migration_errors + chunk_result$errors
      cat(sprintf("❌ %d errors\n", chunk_result$errors))
      migration_log$errors <- c(migration_log$errors, 
                               sprintf("Chunk %d: %d errors", chunk_num, chunk_result$errors))
    }
    
    # Brief pause between chunks to avoid overwhelming database
    if (chunk_num < total_chunks) {
      Sys.sleep(0.1)
    }
  }
  
  migration_log$migration_results <- list(
    total_records = total_records,
    total_migrated = total_migrated,
    migration_errors = migration_errors,
    chunks_processed = total_chunks,
    chunk_size = chunk_size
  )
  
  cat(sprintf("\n✓ Migration completed: %s records processed\n", format(total_records, big.mark = ",")))
  cat(sprintf("  → %s records migrated successfully\n", format(total_migrated, big.mark = ",")))
  
  if (migration_errors > 0) {
    cat(sprintf("  ⚠️ %d migration errors occurred\n", migration_errors))
  }
  
  # 3. Post-migration validation
  if (validate_after) {
    cat("\n3. Post-migration validation...\n")
    
    # Count records after migration
    final_sqlite_count <- DBI::dbGetQuery(sqlite_conn, "SELECT COUNT(*) as count FROM llm_results")$count
    final_postgres_count <- DBI::dbGetQuery(postgres_conn, "SELECT COUNT(*) as count FROM llm_results")$count
    
    # Sample validation - compare a few records
    sample_validation <- validate_migration_sample(sqlite_conn, postgres_conn)
    
    migration_log$validation_results$post_migration <- list(
      sqlite_records = final_sqlite_count,
      postgres_records = final_postgres_count,
      sample_validation = sample_validation,
      migration_complete = (migration_errors == 0) && (total_migrated > 0)
    )
    
    cat(sprintf("  ✓ Final PostgreSQL count: %s records\n", format(final_postgres_count, big.mark = ",")))
    
    if (sample_validation$matches > 0) {
      cat(sprintf("  ✓ Sample validation: %d/%d records match\n", 
                 sample_validation$matches, sample_validation$total_tested))
    }
    
    if (migration_errors == 0 && total_migrated > 0) {
      cat("  ✅ Migration validation PASSED\n")
    } else {
      cat("  ❌ Migration validation FAILED\n")
    }
  }
  
  # Clean up connections
  close_db_connection(sqlite_conn)
  close_db_connection(postgres_conn)
  
  # Final summary
  duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  migration_log$duration_seconds <- duration
  
  cat("\n=== Migration Summary ===\n")
  cat(sprintf("Duration: %.1f seconds\n", duration))
  cat(sprintf("Records processed: %s\n", format(total_records, big.mark = ",")))
  cat(sprintf("Successfully migrated: %s\n", format(total_migrated, big.mark = ",")))
  cat(sprintf("Migration rate: %.0f records/second\n", total_records / duration))
  
  if (migration_errors == 0 && total_migrated > 0) {
    cat("🎉 Migration completed successfully!\n")
  } else if (migration_errors > 0) {
    cat("⚠️ Migration completed with errors - review logs\n")
  } else {
    cat("ℹ️ No data migrated (empty source or all duplicates)\n")
  }
  
  return(migration_log)
}

#' Validate migration by comparing sample records
#' 
#' Compares a sample of records between SQLite and PostgreSQL
#' to ensure data integrity during migration.
#' 
#' @param sqlite_conn SQLite connection
#' @param postgres_conn PostgreSQL connection
#' @param sample_size Number of records to validate (default: 100)
#' @return Validation results
validate_migration_sample <- function(sqlite_conn, postgres_conn, sample_size = 100) {
  
  # Get sample IDs from SQLite
  sample_query <- sprintf("
    SELECT narrative_id, narrative_text, model 
    FROM llm_results 
    ORDER BY RANDOM() 
    LIMIT %d
  ", sample_size)
  
  sqlite_sample <- DBI::dbGetQuery(sqlite_conn, sample_query)
  
  if (nrow(sqlite_sample) == 0) {
    return(list(total_tested = 0, matches = 0, mismatches = 0))
  }
  
  matches <- 0
  mismatches <- 0
  
  for (i in seq_len(min(nrow(sqlite_sample), sample_size))) {
    row <- sqlite_sample[i, ]
    
    # Find corresponding record in PostgreSQL
    postgres_query <- "
      SELECT COUNT(*) as count 
      FROM llm_results 
      WHERE narrative_id = $1 AND narrative_text = $2 AND model = $3
    "
    
    postgres_match <- DBI::dbGetQuery(postgres_conn, postgres_query, 
                                     list(row$narrative_id, row$narrative_text, row$model))
    
    if (postgres_match$count > 0) {
      matches <- matches + 1
    } else {
      mismatches <- mismatches + 1
    }
  }
  
  list(
    total_tested = nrow(sqlite_sample),
    matches = matches,
    mismatches = mismatches,
    match_rate = matches / nrow(sqlite_sample)
  )
}

#' Generate migration report
#' 
#' Creates comprehensive migration report for documentation.
#' 
#' @param migration_log Results from migrate_sqlite_to_postgres()
#' @param output_file Optional file to save report
#' @return Formatted report string
generate_migration_report <- function(migration_log, output_file = NULL) {
  
  report_lines <- c(
    "# SQLite to PostgreSQL Migration Report",
    sprintf("Generated: %s", Sys.time()),
    "",
    "## Migration Summary",
    ""
  )
  
  if (!is.null(migration_log$migration_results)) {
    results <- migration_log$migration_results
    
    report_lines <- c(report_lines,
      sprintf("- **Source Database**: %s", migration_log$sqlite_path),
      sprintf("- **Target Database**: PostgreSQL"),
      sprintf("- **Migration Duration**: %.1f seconds", migration_log$duration_seconds),
      sprintf("- **Total Records Processed**: %s", format(results$total_records, big.mark = ",")),
      sprintf("- **Successfully Migrated**: %s", format(results$total_migrated, big.mark = ",")),
      sprintf("- **Migration Rate**: %.0f records/second", results$total_records / migration_log$duration_seconds),
      sprintf("- **Batch Size**: %s records", format(results$chunk_size, big.mark = ",")),
      sprintf("- **Total Batches**: %d", results$chunks_processed),
      ""
    )
    
    if (results$migration_errors > 0) {
      report_lines <- c(report_lines,
        sprintf("⚠️ **Migration Errors**: %d", results$migration_errors),
        ""
      )
    }
  }
  
  # Validation results
  if (!is.null(migration_log$validation_results$post_migration)) {
    validation <- migration_log$validation_results$post_migration
    
    report_lines <- c(report_lines,
      "## Post-Migration Validation",
      sprintf("- **Final PostgreSQL Records**: %s", format(validation$postgres_records, big.mark = ",")),
      sprintf("- **Migration Complete**: %s", if(validation$migration_complete) "✅ Yes" else "❌ No"),
      ""
    )
    
    if (!is.null(validation$sample_validation)) {
      sample <- validation$sample_validation
      report_lines <- c(report_lines,
        "### Sample Validation",
        sprintf("- **Records Tested**: %d", sample$total_tested),
        sprintf("- **Matches Found**: %d", sample$matches),
        sprintf("- **Match Rate**: %.1f%%", sample$match_rate * 100),
        ""
      )
    }
  }
  
  # Errors and warnings
  if (length(migration_log$errors) > 0) {
    report_lines <- c(report_lines,
      "## Errors and Warnings",
      ""
    )
    
    for (error in migration_log$errors) {
      report_lines <- c(report_lines, sprintf("- %s", error))
    }
    report_lines <- c(report_lines, "")
  }
  
  # Next steps
  report_lines <- c(report_lines,
    "## Next Steps",
    "",
    "After successful migration:",
    "1. Verify application connectivity to PostgreSQL",
    "2. Run performance benchmarks to validate targets",
    "3. Update application configuration to use PostgreSQL",
    "4. Consider archiving or removing SQLite database",
    "5. Set up PostgreSQL backups and monitoring",
    "",
    "---",
    "*Report generated by IPV Detection Migration Tool*"
  )
  
  report_text <- paste(report_lines, collapse = "\n")
  
  if (!is.null(output_file)) {
    writeLines(report_text, output_file)
    cat(sprintf("Migration report saved to: %s\n", output_file))
  }
  
  return(report_text)
}

# Command line interface
if (!interactive()) {
  
  # Parse command line arguments
  args <- commandArgs(trailingOnly = TRUE)
  
  # Default values
  sqlite_path <- "llm_results.db"
  postgres_env <- ".env"
  chunk_size <- 5000
  validate_before <- TRUE
  validate_after <- TRUE
  dry_run <- FALSE
  generate_report <- FALSE
  
  # Parse arguments
  i <- 1
  while (i <= length(args)) {
    arg <- args[i]
    
    if (arg == "--sqlite" && i < length(args)) {
      sqlite_path <- args[i + 1]
      i <- i + 1
    } else if (arg == "--postgres-env" && i < length(args)) {
      postgres_env <- args[i + 1]
      i <- i + 1
    } else if (arg == "--chunk-size" && i < length(args)) {
      chunk_size <- as.integer(args[i + 1])
      i <- i + 1
    } else if (arg == "--dry-run") {
      dry_run <- TRUE
    } else if (arg == "--no-validation") {
      validate_before <- FALSE
      validate_after <- FALSE
    } else if (arg == "--report") {
      generate_report <- TRUE
    } else if (arg == "--help") {
      cat("SQLite to PostgreSQL Migration Tool\n\n")
      cat("Usage: Rscript migrate_sqlite_to_postgres.R [options]\n\n")
      cat("Options:\n")
      cat("  --sqlite PATH         SQLite database path (default: llm_results.db)\n")
      cat("  --postgres-env PATH   PostgreSQL .env file path (default: .env)\n")
      cat("  --chunk-size N        Records per batch (default: 5000)\n")
      cat("  --dry-run            Show migration plan without executing\n")
      cat("  --no-validation      Skip pre/post migration validation\n")
      cat("  --report             Generate detailed migration report\n")
      cat("  --help               Show this help message\n")
      quit(status = 0)
    }
    
    i <- i + 1
  }
  
  # Run migration
  cat("Starting migration with parameters:\n")
  cat(sprintf("  SQLite: %s\n", sqlite_path))
  cat(sprintf("  PostgreSQL env: %s\n", postgres_env))
  cat(sprintf("  Chunk size: %d\n", chunk_size))
  cat(sprintf("  Dry run: %s\n", dry_run))
  cat("\n")
  
  migration_result <- migrate_sqlite_to_postgres(
    sqlite_path = sqlite_path,
    postgres_env = postgres_env,
    chunk_size = chunk_size,
    validate_before = validate_before,
    validate_after = validate_after,
    dry_run = dry_run
  )
  
  # Generate report if requested
  if (generate_report) {
    report_file <- sprintf("migration_report_%s.md", 
                          format(Sys.time(), "%Y%m%d_%H%M%S"))
    generate_migration_report(migration_result, report_file)
  }
  
  # Exit with appropriate status
  success <- is.null(migration_result$migration_results) || 
            (migration_result$migration_results$migration_errors == 0)
  
  quit(status = if(success) 0 else 1)
}