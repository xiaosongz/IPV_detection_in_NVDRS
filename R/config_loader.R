#' Load Experiment Configuration from YAML
#'
#' Loads and parses YAML configuration file with environment variable expansion
#'
#' @param config_path Path to YAML config file
#' @return List with experiment configuration
#'
#' @examples
#' \dontrun{
#' # Load experiment configuration
#' config <- load_experiment_config("configs/experiments/exp_037_baseline_v4_t00_medium.yaml")
#'
#' # Access configuration sections
#' cat("Experiment name:", config$experiment$name, "\n")
#' cat("Model:", config$model$name, "\n")
#' cat("Temperature:", config$model$temperature, "\n")
#'
#' # Validate configuration
#' validate_config(config)
#' }
#'
#' @export
load_experiment_config <- function(config_path) {
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("Package 'yaml' is required but not installed.")
  }

  if (!file.exists(config_path)) {
    stop("Config file not found: ", config_path)
  }

  cat("Loading configuration from:", config_path, "\n")
  config <- yaml::read_yaml(config_path)

  # Expand environment variables in strings
  config <- expand_env_vars_recursive(config)

  # Store config path for reference
  config$config_path <- config_path

  return(config)
}

#' Validate Experiment Configuration
#'
#' Checks required fields and validates parameter ranges
#'
#' @param config Configuration list from load_experiment_config()
#' @return TRUE if valid, stops with error otherwise
#'
#' @examples
#' \dontrun{
#' # Load and validate configuration
#' config <- load_experiment_config("configs/experiments/exp_037_baseline_v4_t00_medium.yaml")
#' validate_config(config) # Will stop if invalid
#'
#' # Check specific validation rules
#' # - Temperature must be between 0.0 and 2.0
#' # - Model name must be specified
#' # - Data file must exist
#' # - Required sections must be present
#' }
#'
#' @export
validate_config <- function(config) {
  # Check required top-level sections
  required_sections <- c("experiment", "model", "prompt", "data", "run")
  missing_sections <- setdiff(required_sections, names(config))
  if (length(missing_sections) > 0) {
    stop("Missing required config sections: ", paste(missing_sections, collapse = ", "))
  }

  # Check experiment section
  if (is.null(config$experiment$name) || config$experiment$name == "") {
    stop("experiment.name is required")
  }

  # Check model section
  if (is.null(config$model$name) || config$model$name == "") {
    stop("model.name is required")
  }

  if (is.null(config$model$temperature)) {
    stop("model.temperature is required")
  }

  temp <- config$model$temperature
  if (!is.numeric(temp) || temp < 0 || temp > 2) {
    stop("model.temperature must be numeric between 0.0 and 2.0, got: ", temp)
  }

  # Check prompt section
  if (is.null(config$prompt$version) || config$prompt$version == "") {
    stop("prompt.version is required")
  }

  # Check for prompt content (either embedded or file references)
  has_system <- !is.null(config$prompt$system_prompt) && config$prompt$system_prompt != ""
  has_system_file <- !is.null(config$prompt$system_prompt_file) && config$prompt$system_prompt_file != ""

  if (!has_system && !has_system_file) {
    stop("Either prompt.system_prompt or prompt.system_prompt_file is required")
  }

  has_user <- !is.null(config$prompt$user_template) && config$prompt$user_template != ""
  has_user_file <- !is.null(config$prompt$user_template_file) && config$prompt$user_template_file != ""

  if (!has_user && !has_user_file) {
    stop("Either prompt.user_template or prompt.user_template_file is required")
  }

  # Load prompt files if specified
  if (has_system_file) {
    prompt_file_path <- config$prompt$system_prompt_file
    if (!file.exists(prompt_file_path)) {
      # Try relative to project root
      prompt_file_path <- here::here(config$prompt$system_prompt_file)
    }
    if (!file.exists(prompt_file_path)) {
      stop("system_prompt_file not found: ", config$prompt$system_prompt_file)
    }
    config$prompt$system_prompt <- paste(readLines(prompt_file_path), collapse = "\n")
  }

  if (has_user_file) {
    prompt_file_path <- config$prompt$user_template_file
    if (!file.exists(prompt_file_path)) {
      # Try relative to project root
      prompt_file_path <- here::here(config$prompt$user_template_file)
    }
    if (!file.exists(prompt_file_path)) {
      stop("user_template_file not found: ", config$prompt$user_template_file)
    }
    config$prompt$user_template <- paste(readLines(prompt_file_path), collapse = "\n")
  }

  # Check data section
  if (is.null(config$data$file) || config$data$file == "") {
    stop("data.file is required")
  }

  # Use here() to resolve file paths from project root
  if (!requireNamespace("here", quietly = TRUE)) {
    stop("Package 'here' is required but not installed.")
  }

  data_file_path <- config$data$file
  if (!file.exists(data_file_path)) {
    # Try relative to project root
    data_file_path <- here::here(config$data$file)
  }

  if (!file.exists(data_file_path)) {
    stop("data.file not found: ", config$data$file)
  }

  # Update config with absolute path
  config$data$file <- data_file_path

  # Check run section (optional fields, set defaults)
  if (is.null(config$run$seed)) {
    config$run$seed <- 123
  }

  if (is.null(config$run$save_incremental)) {
    config$run$save_incremental <- TRUE
  }

  if (is.null(config$run$save_csv_json)) {
    config$run$save_csv_json <- TRUE
  }

  cat("✓ Configuration validated successfully\n")
  return(TRUE)
}

#' Expand Environment Variables in String
#'
#' Replaces ${VAR} or $VAR with environment variable values
#'
#' @param text Character string potentially containing env vars
#' @return String with expanded variables
expand_env_vars <- function(text) {
  if (!is.character(text) || length(text) == 0) {
    return(text)
  }

  # Replace ${VAR} style
  while (grepl("\\$\\{[^}]+\\}", text, perl = TRUE)) {
    match <- regmatches(text, regexpr("\\$\\{[^}]+\\}", text, perl = TRUE))
    if (length(match) == 0) break
    var_name <- gsub("\\$\\{|\\}", "", match)
    replacement <- Sys.getenv(var_name, unset = "")
    text <- sub(match, replacement, text, fixed = TRUE)
  }

  # Replace $VAR style (word boundary after variable name)
  while (grepl("\\$([A-Za-z_][A-Za-z0-9_]*)", text, perl = TRUE)) {
    match <- regmatches(text, regexpr("\\$([A-Za-z_][A-Za-z0-9_]*)", text, perl = TRUE))
    if (length(match) == 0) break
    var_name <- gsub("\\$", "", match)
    replacement <- Sys.getenv(var_name, unset = "")
    text <- sub(match, replacement, text, fixed = TRUE)
  }

  return(text)
}

#' Recursively Expand Environment Variables in Config
#'
#' @param obj Any R object (list, vector, etc.)
#' @return Object with expanded environment variables
expand_env_vars_recursive <- function(obj) {
  if (is.list(obj)) {
    lapply(obj, expand_env_vars_recursive)
  } else if (is.character(obj)) {
    sapply(obj, expand_env_vars, USE.NAMES = FALSE)
  } else {
    obj
  }
}

#' Substitute Template Placeholder
#'
#' Replaces <<TEXT>> placeholder with actual narrative text
#'
#' @param template User prompt template string
#' @param text Narrative text to insert
#' @return String with substituted text
#' @export
substitute_template <- function(template, text) {
  gsub("<<TEXT>>", text, template, fixed = TRUE)
}
