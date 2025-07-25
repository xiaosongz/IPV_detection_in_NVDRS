#!/usr/bin/env Rscript

# IPV Detection Main Script
# Unified script for detecting IPV in NVDRS narratives

# Load required libraries
library(readxl)
library(writexl)
library(tidyverse)
library(glue)
library(optparse)

# Source library components
source("R/lib/config.R")
source("R/lib/logger.R")
source("R/lib/core.R")
source("R/lib/validators.R")
source("R/lib/provider_factory.R")

#' Load and validate input data
#' @param file_path Path to input Excel file
#' @param logger Logger instance
#' @return Validated data frame
load_and_validate_data <- function(file_path, logger) {
  logger$info("Loading data", file = file_path)
  
  # Check file exists
  if (!file.exists(file_path)) {
    stop(glue("Input file not found: {file_path}"))
  }
  
  # Load data
  data <- tryCatch({
    read_excel(file_path)
  }, error = function(e) {
    logger$error("Failed to read Excel file", error = e$message)
    stop(e)
  })
  
  # Add row ID if not present
  if (!"row_id" %in% names(data)) {
    data$row_id <- seq_len(nrow(data))
  }
  
  # Validate required columns
  validate_narrative_data(data, required_cols = c("IncidentID"))
  
  # Check for narrative columns
  narrative_cols <- grep("^Narrative", names(data), value = TRUE)
  logger$info("Found narrative columns", columns = paste(narrative_cols, collapse = ", "))
  
  # Validate narratives
  all_narratives <- unlist(data[narrative_cols])
  validation <- validate_narratives(all_narratives)
  
  logger$info("Data validation complete", 
             total_narratives = validation$stats$total,
             valid = validation$stats$valid,
             empty = validation$stats$empty)
  
  if (validation$stats$valid == 0) {
    stop("No valid narratives found in input file")
  }
  
  return(data)
}

#' Save results to output files
#' @param results Data frame with results
#' @param output_dir Output directory
#' @param config Configuration object
#' @param logger Logger instance
#' @return List of output file paths
save_results <- function(results, output_dir, config, logger) {
  # Create output directory
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  
  # Generate timestamp
  timestamp <- format(Sys.time(), config$get("output.timestamp_format", "%Y%m%d_%H%M%S"))
  
  # Get output formats
  formats <- config$get("output.formats", c("csv", "xlsx"))
  output_files <- list()
  
  # Save in each format
  for (format in formats) {
    if (config$get("output.include_timestamp", TRUE)) {
      filename <- glue("ipv_detection_results_{timestamp}.{format}")
    } else {
      filename <- glue("ipv_detection_results.{format}")
    }
    
    filepath <- file.path(output_dir, filename)
    
    if (format == "csv") {
      write.csv(results, filepath, row.names = FALSE)
    } else if (format == "xlsx") {
      write_xlsx(results, filepath)
    }
    
    output_files[[format]] <- filepath
    logger$info("Results saved", format = format, file = filepath)
  }
  
  # Create validation report if configured
  if (config$get("quality.audit_trail", TRUE)) {
    validation_results <- list(
      output = validate_output_quality(results, config$get("quality"))
    )
    
    report_file <- file.path(output_dir, glue("validation_report_{timestamp}.txt"))
    create_validation_report(validation_results, report_file)
    logger$info("Validation report saved", file = report_file)
  }
  
  return(output_files)
}

#' Main processing function
#' @param input_file Path to input Excel file
#' @param output_dir Output directory
#' @param provider_name Provider to use (optional)
#' @param config_file Configuration file path
#' @param verbose Enable verbose output
main <- function(input_file, 
                output_dir = "output",
                provider_name = NULL,
                config_file = "config/settings.yml",
                verbose = FALSE) {
  
  # Load configuration
  config <- load_config(config_file)
  
  # Set up logging
  log_config <- config$get("logging")
  if (verbose) {
    log_config$level <- "DEBUG"
  }
  logger <- create_logger(log_config)
  
  logger$info("IPV Detection System starting", 
             version = "2.0.0",
             config_file = config_file)
  
  tryCatch({
    # Load and validate data
    data <- load_and_validate_data(input_file, logger)
    
    # Create provider
    if (is.null(provider_name)) {
      provider <- auto_create_provider(config, logger)
    } else {
      provider <- create_provider(provider_name, config, logger)
    }
    
    logger$info("Using provider", provider = provider$name)
    
    # Create batch processor
    processor <- BatchProcessor$new(
      provider = provider,
      config = config$get("processing"),
      logger = logger
    )
    
    # Process data
    logger$info("Starting batch processing")
    results <- processor$process_all(data)
    
    # Save results
    output_files <- save_results(results, output_dir, config, logger)
    
    # Log summary
    summary <- processor$progress_tracker$get_summary()
    logger$info("Processing completed", 
               total_batches = summary$total,
               completed = summary$completed,
               failed = summary$failed)
    
    # Performance metrics
    if (config$get("monitoring.enabled", TRUE)) {
      # Log performance metrics
      logger$performance("ipv_detection", list(
        total_rows = nrow(results),
        total_batches = summary$total,
        completed_batches = summary$completed,
        failed_batches = summary$failed,
        processing_time = as.numeric(Sys.time() - start_time, units = "secs")
      ))
    }
    
    return(invisible(results))
    
  }, error = function(e) {
    logger$error("Processing failed", error = e$message)
    
    # Print traceback in debug mode
    if (verbose) {
      traceback()
    }
    
    stop(e)
  })
}

# Command line interface
if (!interactive()) {
  # Define command line options
  option_list <- list(
    make_option(c("-i", "--input"), 
                type = "character",
                help = "Input Excel file path",
                metavar = "FILE"),
    
    make_option(c("-o", "--output"), 
                type = "character",
                default = "output",
                help = "Output directory [default: %default]",
                metavar = "DIR"),
    
    make_option(c("-p", "--provider"), 
                type = "character",
                default = NULL,
                help = "AI provider to use (openai, ollama) [default: auto-detect]",
                metavar = "PROVIDER"),
    
    make_option(c("-c", "--config"), 
                type = "character",
                default = "config/settings.yml",
                help = "Configuration file path [default: %default]",
                metavar = "FILE"),
    
    make_option(c("-v", "--verbose"), 
                action = "store_true",
                default = FALSE,
                help = "Enable verbose output"),
    
    make_option(c("-d", "--dry-run"), 
                action = "store_true",
                default = FALSE,
                help = "Validate configuration without processing")
  )
  
  # Parse arguments
  parser <- OptionParser(
    usage = "%prog [options]",
    option_list = option_list,
    description = "IPV Detection System - Analyzes NVDRS narratives for IPV indicators",
    epilogue = "Examples:\n  %prog -i data/narratives.xlsx\n  %prog -i data/narratives.xlsx -p openai -v"
  )
  
  args <- parse_args(parser)
  
  # Check required arguments
  if (is.null(args$input)) {
    print_help(parser)
    stop("Input file is required", call. = FALSE)
  }
  
  # Dry run mode
  if (args$`dry-run`) {
    cat("Configuration validation mode\n")
    config <- load_config(args$config)
    config$print()
    
    # Try to create provider
    tryCatch({
      provider <- auto_create_provider(config)
      cat("\nProvider status:\n")
      print(provider$get_status())
    }, error = function(e) {
      cat("\nProvider initialization failed:", e$message, "\n")
    })
    
    quit(status = 0)
  }
  
  # Record start time
  start_time <- Sys.time()
  
  # Run main processing
  main(
    input_file = args$input,
    output_dir = args$output,
    provider_name = args$provider,
    config_file = args$config,
    verbose = args$verbose
  )
  
  # Print completion message
  duration <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))
  cat(glue("\nProcessing completed in {round(duration, 2)} minutes\n"))
}