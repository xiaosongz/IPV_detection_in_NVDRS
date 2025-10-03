# Setup LLM Configuration
# This script sets environment variables for LLM API connection.
# Source this file at the beginning of your session to configure the API.

# Set default values for LLM API
api_url <- "http://192.168.10.22:1234/v1/chat/completions"
model <- "openai/gpt-oss-120b"

# Set environment variables
Sys.setenv(LLM_API_URL = api_url)
Sys.setenv(LLM_MODEL = model)

# Print configuration
cat("LLM configuration set:\n")
cat("- API URL:", api_url, "\n")
cat("- Model:", model, "\n")