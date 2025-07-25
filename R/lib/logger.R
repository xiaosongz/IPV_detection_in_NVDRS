# Logging Framework
# Provides structured logging with multiple levels and output targets

library(R6)
library(glue)
library(jsonlite)

#' Logger Class
#' 
#' @description Comprehensive logging framework with levels, rotation, and formatting
#' @export
Logger <- R6::R6Class("Logger",
  public = list(
    #' @field log_dir Directory for log files
    log_dir = NULL,
    
    #' @field log_level Current logging level
    log_level = NULL,
    
    #' @field log_files Named list of log file paths
    log_files = NULL,
    
    #' @field include_context Whether to include context information
    include_context = NULL,
    
    #' @field json_format Whether to use JSON formatting
    json_format = NULL,
    
    #' Initialize Logger
    #' @param config Configuration object or list
    #' @param name Logger name for identification
    initialize = function(config = NULL, name = "IPVDetection") {
      private$name <- name
      
      # Set defaults
      self$log_dir <- "logs"
      self$log_level <- "INFO"
      self$include_context <- TRUE
      self$json_format <- FALSE
      
      # Apply configuration if provided
      if (!is.null(config)) {
        if (!is.null(config$directory)) self$log_dir <- config$directory
        if (!is.null(config$level)) self$log_level <- config$level
        if (!is.null(config$include_context)) self$include_context <- config$include_context
        if (!is.null(config$json_format)) self$json_format <- config$json_format
      }
      
      # Create log directory
      if (!dir.exists(self$log_dir)) {
        dir.create(self$log_dir, recursive = TRUE)
      }
      
      # Initialize log files
      private$init_log_files(config)
      
      # Set log level
      private$set_log_level(self$log_level)
      
      # Log initialization
      self$info("Logger initialized", name = private$name, level = self$log_level)
    },
    
    #' Log debug message
    #' @param message Message to log
    #' @param ... Additional context fields
    debug = function(message, ...) {
      if (private$should_log("DEBUG")) {
        private$log("DEBUG", message, ...)
      }
    },
    
    #' Log info message
    #' @param message Message to log
    #' @param ... Additional context fields
    info = function(message, ...) {
      if (private$should_log("INFO")) {
        private$log("INFO", message, ...)
      }
    },
    
    #' Log warning message
    #' @param message Message to log
    #' @param ... Additional context fields
    warn = function(message, ...) {
      if (private$should_log("WARN")) {
        private$log("WARN", message, ...)
      }
    },
    
    #' Log error message
    #' @param message Message to log
    #' @param ... Additional context fields
    error = function(message, ...) {
      if (private$should_log("ERROR")) {
        private$log("ERROR", message, ...)
      }
    },
    
    #' Log with timing
    #' @param message Message to log
    #' @param expr Expression to time
    #' @param ... Additional context fields
    time = function(message, expr, ...) {
      start_time <- Sys.time()
      self$info(glue("{message} - Starting"), ...)
      
      result <- tryCatch({
        expr
      }, error = function(e) {
        self$error(glue("{message} - Failed"), error = e$message, ...)
        stop(e)
      })
      
      duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
      self$info(glue("{message} - Completed"), duration_seconds = round(duration, 3), ...)
      
      return(result)
    },
    
    #' Log performance metrics
    #' @param operation Operation name
    #' @param metrics Named list of metrics
    performance = function(operation, metrics) {
      if (!private$should_log("INFO")) return()
      
      # Always log to performance file
      log_entry <- private$format_log_entry("PERF", operation, metrics)
      private$write_to_file(log_entry, "performance")
      
      # Also log to main if debug
      if (private$should_log("DEBUG")) {
        private$log("DEBUG", glue("Performance: {operation}"), metrics = metrics)
      }
    },
    
    #' Create a child logger with additional context
    #' @param context Additional context to add to all messages
    #' @return New Logger instance
    with_context = function(context) {
      child <- Logger$new(
        list(
          directory = self$log_dir,
          level = self$log_level,
          include_context = self$include_context,
          json_format = self$json_format
        ),
        name = private$name
      )
      child$context <- context
      return(child)
    },
    
    #' Rotate log files
    rotate = function() {
      for (file_name in names(self$log_files)) {
        file_path <- self$log_files[[file_name]]
        if (file.exists(file_path)) {
          # Check file size
          info <- file.info(file_path)
          max_size <- private$get_max_file_size()
          
          if (info$size > max_size) {
            # Rotate file
            timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
            rotated_path <- gsub("\\.log$", glue("_{timestamp}.log"), file_path)
            file.rename(file_path, rotated_path)
            self$info("Rotated log file", file = file_name, size_mb = round(info$size / 1024^2, 2))
            
            # Clean up old files
            private$cleanup_old_logs(file_name)
          }
        }
      }
    }
  ),
  
  private = list(
    #' @field name Logger name
    name = NULL,
    
    #' @field log_level_num Numeric log level for comparison
    log_level_num = NULL,
    
    #' @field context Additional context for child loggers
    context = NULL,
    
    #' Initialize log files
    init_log_files = function(config) {
      self$log_files <- list(
        main = file.path(self$log_dir, config$main_log %||% "ipv_detection.log"),
        error = file.path(self$log_dir, config$error_log %||% "errors.log"),
        performance = file.path(self$log_dir, config$performance_log %||% "performance.log")
      )
    },
    
    #' Set numeric log level
    set_log_level = function(level) {
      levels <- c(DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4)
      private$log_level_num <- levels[[level]]
      if (is.null(private$log_level_num)) {
        stop(glue("Invalid log level: {level}"))
      }
    },
    
    #' Check if should log at given level
    should_log = function(level) {
      levels <- c(DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4, PERF = 2)
      level_num <- levels[[level]]
      return(level_num >= private$log_level_num)
    },
    
    #' Main logging function
    log = function(level, message, ...) {
      # Format log entry
      log_entry <- private$format_log_entry(level, message, list(...))
      
      # Write to console
      private$write_to_console(level, log_entry)
      
      # Write to appropriate file(s)
      private$write_to_file(log_entry, "main")
      
      if (level == "ERROR") {
        private$write_to_file(log_entry, "error")
      }
      
      # Check for rotation
      if (runif(1) < 0.01) {  # 1% chance to check
        self$rotate()
      }
    },
    
    #' Format log entry
    format_log_entry = function(level, message, fields = list()) {
      timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S.%OS3")
      
      # Add context if available
      if (!is.null(private$context)) {
        fields <- c(private$context, fields)
      }
      
      if (self$json_format) {
        # JSON format
        entry <- list(
          timestamp = timestamp,
          level = level,
          logger = private$name,
          message = message
        )
        
        if (self$include_context && length(fields) > 0) {
          entry$context <- fields
        }
        
        return(toJSON(entry, auto_unbox = TRUE, null = "null"))
      } else {
        # Text format
        entry <- glue("[{timestamp}] [{level}] {message}")
        
        if (self$include_context && length(fields) > 0) {
          context_str <- paste(
            mapply(function(k, v) glue("{k}={v}"), 
                   names(fields), fields, 
                   USE.NAMES = FALSE),
            collapse = " "
          )
          entry <- glue("{entry} | {context_str}")
        }
        
        return(as.character(entry))
      }
    },
    
    #' Write to console with color
    write_to_console = function(level, entry) {
      # Color codes for different levels
      colors <- list(
        DEBUG = "\033[90m",    # Gray
        INFO = "\033[0m",      # Default
        WARN = "\033[33m",     # Yellow
        ERROR = "\033[31m",    # Red
        PERF = "\033[36m"      # Cyan
      )
      
      reset <- "\033[0m"
      color <- colors[[level]] %||% ""
      
      if (interactive()) {
        cat(color, entry, reset, "\n", sep = "")
      } else {
        cat(entry, "\n")
      }
    },
    
    #' Write to log file
    write_to_file = function(entry, file_type) {
      file_path <- self$log_files[[file_type]]
      if (!is.null(file_path)) {
        cat(entry, "\n", file = file_path, append = TRUE)
      }
    },
    
    #' Get maximum file size from config
    get_max_file_size = function() {
      # Default 100MB
      100 * 1024^2
    },
    
    #' Clean up old rotated logs
    cleanup_old_logs = function(file_type) {
      base_path <- self$log_files[[file_type]]
      pattern <- gsub("\\.log$", "_\\d{8}_\\d{6}\\.log$", basename(base_path))
      
      old_files <- list.files(
        self$log_dir, 
        pattern = pattern, 
        full.names = TRUE
      )
      
      if (length(old_files) > 10) {  # Keep only 10 rotated files
        # Sort by modification time and remove oldest
        file_info <- file.info(old_files)
        oldest <- old_files[order(file_info$mtime)][1:(length(old_files) - 10)]
        file.remove(oldest)
      }
    }
  )
)

#' Create a global logger instance
#' @param config Logger configuration
#' @return Logger instance
#' @export
create_logger <- function(config = NULL) {
  Logger$new(config)
}

#' Get a logger with specific context
#' @param logger Base logger instance
#' @param ... Context fields
#' @return Logger with context
#' @export
with_context <- function(logger, ...) {
  logger$with_context(list(...))
}