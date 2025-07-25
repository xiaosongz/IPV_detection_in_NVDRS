# Configuration Management System
# Handles loading, validation, and access to system configuration

library(yaml)
library(R6)
library(glue)

#' Configuration Manager Class
#' 
#' @description Manages application configuration with validation and environment support
#' @export
ConfigManager <- R6::R6Class("ConfigManager",
  public = list(
    #' @field config_file Path to configuration file
    config_file = NULL,
    
    #' @field config Loaded configuration object
    config = NULL,
    
    #' @field environment Current environment (dev, test, prod)
    environment = NULL,
    
    #' Initialize Configuration Manager
    #' @param config_file Path to YAML configuration file
    #' @param environment Environment name (defaults to IPVD_ENV or "dev")
    initialize = function(config_file = "config/settings.yml", 
                         environment = Sys.getenv("IPVD_ENV", "dev")) {
      self$config_file <- config_file
      self$environment <- environment
      self$load_config()
    },
    
    #' Load configuration from file
    load_config = function() {
      if (!file.exists(self$config_file)) {
        # Try example file
        example_file <- paste0(self$config_file, ".example")
        if (file.exists(example_file)) {
          stop(glue("Configuration file {self$config_file} not found. ",
                   "Please copy {example_file} to {self$config_file} and configure."))
        }
        stop(glue("Configuration file {self$config_file} not found."))
      }
      
      tryCatch({
        self$config <- yaml::read_yaml(self$config_file)
        private$validate_config()
        private$apply_environment_overrides()
        message(glue("Configuration loaded successfully from {self$config_file}"))
      }, error = function(e) {
        stop(glue("Failed to load configuration: {e$message}"))
      })
    },
    
    #' Get configuration value
    #' @param path Dot-separated path to configuration value
    #' @param default Default value if path not found
    #' @return Configuration value
    get = function(path, default = NULL) {
      parts <- strsplit(path, "\\.")[[1]]
      value <- self$config
      
      for (part in parts) {
        if (is.null(value[[part]])) {
          return(default)
        }
        value <- value[[part]]
      }
      
      return(value)
    },
    
    #' Set configuration value
    #' @param path Dot-separated path to configuration value
    #' @param value Value to set
    set = function(path, value) {
      parts <- strsplit(path, "\\.")[[1]]
      
      # Navigate to parent
      parent <- self$config
      for (i in seq_len(length(parts) - 1)) {
        if (is.null(parent[[parts[i]]])) {
          parent[[parts[i]]] <- list()
        }
        parent <- parent[[parts[i]]]
      }
      
      # Set value
      parent[[parts[length(parts)]]] <- value
    },
    
    #' Get all configuration as list
    #' @return Complete configuration list
    get_all = function() {
      self$config
    },
    
    #' Validate specific configuration section
    #' @param section Section name to validate
    #' @return TRUE if valid, error otherwise
    validate_section = function(section) {
      if (is.null(self$config[[section]])) {
        stop(glue("Configuration section '{section}' not found"))
      }
      
      # Section-specific validation
      switch(section,
        "api" = private$validate_api_config(),
        "processing" = private$validate_processing_config(),
        "cache" = private$validate_cache_config(),
        "logging" = private$validate_logging_config(),
        TRUE
      )
    },
    
    #' Print configuration summary
    print = function() {
      cat("IPV Detection Configuration\n")
      cat(rep("=", 40), "\n", sep = "")
      cat("Environment:", self$environment, "\n")
      cat("Config file:", self$config_file, "\n")
      cat("\nMain sections:\n")
      for (section in names(self$config)) {
        cat("  -", section, "\n")
      }
    }
  ),
  
  private = list(
    #' Validate entire configuration
    validate_config = function() {
      required_sections <- c("api", "processing", "cache", "logging", "output")
      
      for (section in required_sections) {
        if (is.null(self$config[[section]])) {
          stop(glue("Required configuration section '{section}' not found"))
        }
      }
      
      # Validate individual sections
      private$validate_api_config()
      private$validate_processing_config()
      private$validate_cache_config()
      private$validate_logging_config()
    },
    
    #' Validate API configuration
    validate_api_config = function() {
      api_config <- self$config$api
      
      # Check for at least one provider
      if (length(api_config) == 0) {
        stop("At least one API provider must be configured")
      }
      
      # Validate OpenAI config if present
      if (!is.null(api_config$openai)) {
        required_fields <- c("key_env", "endpoint", "model")
        for (field in required_fields) {
          if (is.null(api_config$openai[[field]])) {
            stop(glue("OpenAI configuration missing required field: {field}"))
          }
        }
      }
      
      # Validate Ollama config if present
      if (!is.null(api_config$ollama)) {
        required_fields <- c("endpoint", "model")
        for (field in required_fields) {
          if (is.null(api_config$ollama[[field]])) {
            stop(glue("Ollama configuration missing required field: {field}"))
          }
        }
      }
      
      TRUE
    },
    
    #' Validate processing configuration
    validate_processing_config = function() {
      proc_config <- self$config$processing
      
      # Validate batch size
      if (!is.null(proc_config$batch_size)) {
        if (proc_config$batch_size < 1 || proc_config$batch_size > 100) {
          warning("Batch size should be between 1 and 100")
        }
      }
      
      # Validate parallel settings
      if (!is.null(proc_config$max_parallel_batches)) {
        if (proc_config$max_parallel_batches < 1) {
          stop("max_parallel_batches must be at least 1")
        }
      }
      
      TRUE
    },
    
    #' Validate cache configuration
    validate_cache_config = function() {
      cache_config <- self$config$cache
      
      # Validate cache directory
      if (!is.null(cache_config$directory)) {
        # Create directory if it doesn't exist
        if (!dir.exists(cache_config$directory)) {
          dir.create(cache_config$directory, recursive = TRUE)
        }
      }
      
      # Validate TTL
      if (!is.null(cache_config$ttl_days)) {
        if (cache_config$ttl_days < 0) {
          stop("Cache TTL must be non-negative")
        }
      }
      
      TRUE
    },
    
    #' Validate logging configuration
    validate_logging_config = function() {
      log_config <- self$config$logging
      
      # Validate log level
      valid_levels <- c("DEBUG", "INFO", "WARN", "ERROR")
      if (!is.null(log_config$level)) {
        if (!(log_config$level %in% valid_levels)) {
          stop(glue("Invalid log level: {log_config$level}. ",
                   "Must be one of: {paste(valid_levels, collapse = ', ')}"))
        }
      }
      
      # Create log directory if needed
      if (!is.null(log_config$directory)) {
        if (!dir.exists(log_config$directory)) {
          dir.create(log_config$directory, recursive = TRUE)
        }
      }
      
      TRUE
    },
    
    #' Apply environment-specific overrides
    apply_environment_overrides = function() {
      # Look for environment-specific config file
      env_config_file <- glue("config/settings.{self$environment}.yml")
      
      if (file.exists(env_config_file)) {
        env_config <- yaml::read_yaml(env_config_file)
        self$config <- private$merge_configs(self$config, env_config)
        message(glue("Applied {self$environment} environment overrides"))
      }
    },
    
    #' Recursively merge two configurations
    #' @param base Base configuration
    #' @param override Override configuration
    #' @return Merged configuration
    merge_configs = function(base, override) {
      if (is.null(override)) return(base)
      if (is.null(base)) return(override)
      
      if (!is.list(base) || !is.list(override)) {
        return(override)
      }
      
      result <- base
      for (key in names(override)) {
        if (key %in% names(base) && is.list(base[[key]]) && is.list(override[[key]])) {
          result[[key]] <- private$merge_configs(base[[key]], override[[key]])
        } else {
          result[[key]] <- override[[key]]
        }
      }
      
      return(result)
    }
  )
)

#' Load configuration helper function
#' @param config_file Path to configuration file
#' @param environment Environment name
#' @return ConfigManager instance
#' @export
load_config <- function(config_file = "config/settings.yml", 
                       environment = Sys.getenv("IPVD_ENV", "dev")) {
  ConfigManager$new(config_file, environment)
}