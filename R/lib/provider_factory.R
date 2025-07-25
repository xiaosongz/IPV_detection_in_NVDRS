# Provider Factory
# Creates and manages AI provider instances

library(R6)
library(glue)

# Source provider implementations
source("R/lib/providers/openai_provider.R")
source("R/lib/providers/ollama_provider.R")

#' Provider Factory for creating AI provider instances
#' @export
ProviderFactory <- R6::R6Class("ProviderFactory",
  public = list(
    #' @field providers Registry of available providers
    providers = NULL,
    
    #' @field logger Logger instance
    logger = NULL,
    
    #' Initialize Provider Factory
    #' @param logger Logger instance
    initialize = function(logger = NULL) {
      self$logger <- logger %||% Logger$new()
      
      # Register available providers
      self$providers <- list(
        openai = OpenAIProvider,
        ollama = OllamaProvider
      )
      
      self$logger$info("Provider factory initialized", 
                      available_providers = names(self$providers))
    },
    
    #' Create a provider instance
    #' @param provider_name Name of the provider
    #' @param config Provider configuration
    #' @param cache_manager Cache manager instance
    #' @return Provider instance
    create = function(provider_name, config, cache_manager = NULL) {
      # Normalize provider name
      provider_name <- tolower(provider_name)
      
      # Check if provider exists
      if (!provider_name %in% names(self$providers)) {
        available <- paste(names(self$providers), collapse = ", ")
        stop(glue("Unknown provider: {provider_name}. Available providers: {available}"))
      }
      
      # Get provider class
      provider_class <- self$providers[[provider_name]]
      
      # Create instance
      self$logger$info("Creating provider", provider = provider_name)
      
      tryCatch({
        provider <- provider_class$new(
          config = config,
          logger = self$logger,
          cache_manager = cache_manager
        )
        
        # Check if provider is available
        status <- provider$get_status()
        if (!status$available) {
          self$logger$warning("Provider created but may not be fully available", 
                            provider = provider_name)
        }
        
        return(provider)
        
      }, error = function(e) {
        self$logger$error("Failed to create provider", 
                         provider = provider_name,
                         error = e$message)
        stop(e)
      })
    },
    
    #' Register a new provider type
    #' @param name Provider name
    #' @param provider_class R6 class for the provider
    register_provider = function(name, provider_class) {
      name <- tolower(name)
      
      # Validate provider class
      if (!inherits(provider_class, "R6ClassGenerator")) {
        stop("Provider class must be an R6 class generator")
      }
      
      # Check if it inherits from AIProvider
      # Note: This is a simple check, might need enhancement
      
      self$providers[[name]] <- provider_class
      self$logger$info("Registered new provider", provider = name)
    },
    
    #' List available providers
    #' @return Character vector of provider names
    list_providers = function() {
      names(self$providers)
    }
  )
)

#' Create a provider instance using factory
#' @param provider_name Name of the provider
#' @param config Configuration object or list
#' @param logger Logger instance
#' @param cache_manager Cache manager instance
#' @return Provider instance
#' @export
create_provider <- function(provider_name, config, logger = NULL, cache_manager = NULL) {
  factory <- ProviderFactory$new(logger)
  
  # If config is a ConfigManager, extract the provider config
  if (inherits(config, "ConfigManager")) {
    provider_config <- config$get(glue("api.{provider_name}"))
    if (is.null(provider_config)) {
      stop(glue("No configuration found for provider: {provider_name}"))
    }
  } else if (is.list(config)) {
    provider_config <- config[[provider_name]] %||% config
  } else {
    stop("Config must be a ConfigManager instance or a list")
  }
  
  factory$create(provider_name, provider_config, cache_manager)
}

#' Auto-detect and create appropriate provider
#' @param config Configuration object
#' @param logger Logger instance
#' @param cache_manager Cache manager instance
#' @return Provider instance
#' @export
auto_create_provider <- function(config, logger = NULL, cache_manager = NULL) {
  logger <- logger %||% Logger$new()
  
  # Get API configuration
  if (inherits(config, "ConfigManager")) {
    api_config <- config$get("api")
  } else {
    api_config <- config$api
  }
  
  if (is.null(api_config)) {
    stop("No API configuration found")
  }
  
  # Try providers in order of preference
  preference_order <- c("openai", "ollama")
  
  for (provider_name in preference_order) {
    if (!is.null(api_config[[provider_name]])) {
      logger$info("Auto-detected provider", provider = provider_name)
      
      tryCatch({
        provider <- create_provider(provider_name, config, logger, cache_manager)
        
        # Test if provider is actually available
        if (provider$get_status()$available) {
          return(provider)
        } else {
          logger$warning("Provider not available, trying next", 
                        provider = provider_name)
        }
      }, error = function(e) {
        logger$warning("Failed to create provider, trying next", 
                      provider = provider_name,
                      error = e$message)
      })
    }
  }
  
  stop("No available provider found. Please check your configuration.")
}