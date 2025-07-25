# IPV Detection System - Architecture Design

## Overview

This document outlines the improved architecture for the IPV Detection system, addressing code duplication, scalability, and maintainability concerns identified in the analysis.

## System Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Data Input    │     │  Configuration   │     │    Logging      │
│   (Excel/CSV)   │     │   Management     │     │   Framework     │
└────────┬────────┘     └────────┬─────────┘     └────────┬────────┘
         │                       │                          │
         v                       v                          v
┌────────────────────────────────────────────────────────────────┐
│                      Orchestration Layer                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐    │
│  │ Job Manager  │  │ Progress     │  │ Error Recovery   │    │
│  │              │  │ Tracker      │  │                  │    │
│  └──────────────┘  └──────────────┘  └──────────────────┘    │
└────────────────────────────┬───────────────────────────────────┘
                             │
                             v
┌────────────────────────────────────────────────────────────────┐
│                      Processing Pipeline                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐    │
│  │   Validator  │->│ Batch Builder│->│ Parallel Executor│    │
│  │              │  │              │  │                  │    │
│  └──────────────┘  └──────────────┘  └──────────────────┘    │
└────────────────────────────┬───────────────────────────────────┘
                             │
                             v
┌────────────────────────────────────────────────────────────────┐
│                    AI Provider Abstraction                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐    │
│  │OpenAI Client │  │Ollama Client │  │ Future Provider  │    │
│  │              │  │              │  │                  │    │
│  └──────────────┘  └──────────────┘  └──────────────────┘    │
└────────────────────────────┬───────────────────────────────────┘
                             │
                             v
┌────────────────────────────────────────────────────────────────┐
│                        Data Layer                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐    │
│  │Cache Manager │  │Result Store  │  │ Checkpoint Store │    │
│  │              │  │              │  │                  │    │
│  └──────────────┘  └──────────────┘  └──────────────────┘    │
└────────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. Configuration Management
```yaml
# config/settings.yml
api:
  openai:
    key_env: "OPENAI_API_KEY"
    endpoint: "https://api.openai.com/v1/chat/completions"
    model: "gpt-4o-mini"
    rate_limit: 
      requests_per_minute: 90
      tokens_per_minute: 90000
  
  ollama:
    endpoint: "http://192.168.10.21:11434/api/generate"
    model: "llama3.1:8b"
    timeout: 300

processing:
  batch_size: 20
  max_retries: 3
  retry_delay: 60
  parallel_workers: 4

cache:
  enabled: true
  ttl_days: 30
  compression: true
```

### 2. Shared Core Library
```R
# R/lib/core.R

#' Base class for AI providers
AIProvider <- R6::R6Class("AIProvider",
  public = list(
    name = NULL,
    config = NULL,
    
    initialize = function(name, config) {
      self$name <- name
      self$config <- config
    },
    
    process_batch = function(narratives, batch_id) {
      stop("Must implement process_batch method")
    },
    
    validate_response = function(response) {
      # Common validation logic
    }
  )
)

#' Batch processor with parallel execution
BatchProcessor <- R6::R6Class("BatchProcessor",
  public = list(
    provider = NULL,
    config = NULL,
    progress_tracker = NULL,
    
    initialize = function(provider, config) {
      self$provider <- provider
      self$config <- config
      self$progress_tracker <- ProgressTracker$new()
    },
    
    process = function(data, narrative_type) {
      # Parallel batch processing logic
    }
  )
)
```

### 3. API Provider Implementations
```R
# R/lib/providers/openai_provider.R

OpenAIProvider <- R6::R6Class("OpenAIProvider",
  inherit = AIProvider,
  
  public = list(
    initialize = function(config) {
      super$initialize("openai", config)
      private$validate_api_key()
    },
    
    process_batch = function(narratives, batch_id) {
      # OpenAI-specific implementation
      private$rate_limited_request(narratives, batch_id)
    }
  ),
  
  private = list(
    validate_api_key = function() {
      key <- Sys.getenv(self$config$key_env)
      if (!nzchar(key)) {
        stop("OpenAI API key not found in environment")
      }
    },
    
    rate_limited_request = function(narratives, batch_id) {
      # Rate-limited API call implementation
    }
  )
)
```

### 4. Progress Tracking and Recovery
```R
# R/lib/progress_tracker.R

ProgressTracker <- R6::R6Class("ProgressTracker",
  public = list(
    checkpoint_file = NULL,
    state = NULL,
    
    initialize = function(checkpoint_file = "checkpoints/progress.rds") {
      self$checkpoint_file <- checkpoint_file
      self$load_state()
    },
    
    update = function(batch_id, status, result = NULL) {
      self$state[[batch_id]] <- list(
        status = status,
        timestamp = Sys.time(),
        result = result
      )
      self$save_state()
    },
    
    get_pending_batches = function() {
      # Return list of incomplete batches
    },
    
    load_state = function() {
      if (file.exists(self$checkpoint_file)) {
        self$state <- readRDS(self$checkpoint_file)
      } else {
        self$state <- list()
      }
    },
    
    save_state = function() {
      saveRDS(self$state, self$checkpoint_file)
    }
  )
)
```

### 5. Logging Framework
```R
# R/lib/logger.R

Logger <- R6::R6Class("Logger",
  public = list(
    log_file = NULL,
    log_level = NULL,
    
    initialize = function(log_file = NULL, level = "INFO") {
      self$log_file <- log_file %||% glue("logs/ipv_detection_{Sys.Date()}.log")
      self$log_level <- level
      private$setup_logger()
    },
    
    info = function(message, ...) {
      private$log("INFO", message, ...)
    },
    
    error = function(message, ...) {
      private$log("ERROR", message, ...)
    },
    
    debug = function(message, ...) {
      if (self$log_level == "DEBUG") {
        private$log("DEBUG", message, ...)
      }
    }
  ),
  
  private = list(
    setup_logger = function() {
      dir.create(dirname(self$log_file), recursive = TRUE, showWarnings = FALSE)
    },
    
    log = function(level, message, ...) {
      timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      formatted_message <- glue("[{timestamp}] [{level}] {message}", ...)
      
      cat(formatted_message, "\n")
      cat(formatted_message, "\n", file = self$log_file, append = TRUE)
    }
  )
)
```

## Implementation Guide

### Phase 1: Core Infrastructure (Week 1)
1. Set up configuration management system
2. Implement base classes and shared utilities
3. Create logging framework
4. Set up testing infrastructure

### Phase 2: Provider Abstraction (Week 2)
1. Implement AIProvider base class
2. Migrate OpenAI functionality to provider class
3. Migrate Ollama functionality to provider class
4. Create provider factory for dynamic selection

### Phase 3: Pipeline Enhancement (Week 3)
1. Implement parallel batch processing
2. Add progress tracking and recovery
3. Enhance error handling and retry logic
4. Add comprehensive validation

### Phase 4: Testing and Documentation (Week 4)
1. Create unit tests for all components
2. Add integration tests
3. Performance testing and optimization
4. Complete documentation

## New Main Script Structure
```R
# R/detect_ipv.R

library(tidyverse)
library(R6)
source("R/lib/core.R")
source("R/lib/config.R")
source("R/lib/logger.R")

# Initialize components
config <- load_config("config/settings.yml")
logger <- Logger$new(level = config$logging$level)
provider <- create_provider(config$provider, config$api)
processor <- BatchProcessor$new(provider, config$processing)

# Main execution
main <- function(input_file, output_dir = "output") {
  logger$info("Starting IPV detection for {input_file}")
  
  tryCatch({
    # Load and validate data
    data <- load_and_validate_data(input_file)
    logger$info("Loaded {nrow(data)} records")
    
    # Process narratives
    results <- processor$process_all(data)
    
    # Save results
    output_file <- save_results(results, output_dir)
    logger$info("Results saved to {output_file}")
    
  }, error = function(e) {
    logger$error("Processing failed: {e$message}")
    stop(e)
  })
}

# CLI interface
if (!interactive()) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) < 1) {
    stop("Usage: Rscript detect_ipv.R <input_file> [output_dir]")
  }
  
  main(args[1], args[2] %||% "output")
}
```

## Benefits of New Architecture

1. **Modularity**: Clear separation of concerns with reusable components
2. **Extensibility**: Easy to add new AI providers or processing strategies
3. **Maintainability**: DRY principle eliminates code duplication
4. **Reliability**: Comprehensive error handling and recovery mechanisms
5. **Performance**: Parallel processing and optimized batching
6. **Observability**: Built-in logging and monitoring capabilities
7. **Testability**: Modular design enables comprehensive testing

## Migration Strategy

1. **Incremental Migration**: Implement new components alongside existing code
2. **Backward Compatibility**: Maintain existing interfaces during transition
3. **Parallel Testing**: Run new and old systems in parallel to validate results
4. **Gradual Cutover**: Switch to new system component by component

## Future Enhancements

1. **Web API**: REST API for real-time processing
2. **Dashboard**: Monitoring and analytics dashboard
3. **Model Management**: A/B testing and model versioning
4. **Distributed Processing**: Scale across multiple machines
5. **Advanced Caching**: Redis-based distributed cache