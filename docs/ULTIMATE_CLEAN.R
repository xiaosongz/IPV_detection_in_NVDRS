# Ultimate Clean IPV Detection
# "Do ONE thing well" - Unix Philosophy
# Minimal implementation focused on simplicity

# ============================================================
# THE ONLY FUNCTION YOU NEED
# ============================================================
detect_ipv <- function(text, config = NULL) {
  # Default config - simple list
  if (is.null(config)) {
    config <- list(
      api_url = Sys.getenv("LLM_API_URL", "http://192.168.10.22:1234/v1/chat/completions"),
      model = Sys.getenv("LLM_MODEL", "openai/gpt-oss-120b"),
      prompt_template = Sys.getenv("IPV_PROMPT", 
        "Analyze for intimate partner violence: %s\nReturn JSON: {detected: bool, confidence: 0-1}")
    )
  }
  
  # Empty input = empty output
  if (is.null(text) || is.na(text) || trimws(text) == "") {
    return(list(detected = NA, confidence = 0, error = "empty input"))
  }
  
  # Build prompt
  prompt <- sprintf(config$prompt_template, trimws(text))
  
  # Call API and return
  tryCatch({
    response <- httr2::request(config$api_url) |>
      httr2::req_body_json(list(
        model = config$model,
        messages = list(list(role = "user", content = prompt))
      )) |>
      httr2::req_perform() |>
      httr2::resp_body_json()
    
    # Return parsed result
    jsonlite::fromJSON(response$choices[[1]]$message$content)
    
  }, error = function(e) {
    list(detected = NA, confidence = 0, error = e$message)
  })
}

# ============================================================
# That's it. One function. Clean and simple. Done.
# ============================================================

# Users decide how to use it:
# 
# Single detection:
#   result <- detect_ipv("narrative text here")
#
# Batch processing (user writes):
#   df$ipv_result <- lapply(df$narrative, detect_ipv)
#
# Custom prompt:
#   my_config <- list(
#     api_url = "http://my-llm:8080/v1/chat/completions",
#     model = "llama-70b",
#     prompt_template = "My custom prompt: %s"
#   )
#   result <- detect_ipv(text, my_config)
#
# It's that simple.