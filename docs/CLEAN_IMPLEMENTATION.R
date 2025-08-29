# Clean IPV Detection Implementation
# "Good taste" version - by Linus standards
# Extended implementation with batching support

# ============================================================
# CONFIG - Externalize all variables
# ============================================================
load_config <- function(path = Sys.getenv("CONFIG_PATH", "config.yml")) {
  config <- yaml::read_yaml(path)
  
  # Environment variable overrides
  config$api$url <- Sys.getenv("LLM_API_URL", config$api$url)
  config$api$model <- Sys.getenv("LLM_MODEL", config$api$model)
  
  config
}

# ============================================================
# CORE - The only important function
# ============================================================
detect_ipv <- function(narrative, 
                      type = c("LE", "CME"), 
                      config = NULL) {
  
  # Parameter handling - no special cases
  if (is.null(config)) config <- load_config()
  type <- match.arg(type)
  narrative <- trimws(narrative)
  
  # Empty value returns directly - not a special case, normal flow
  if (is.na(narrative) || narrative == "") {
    return(list(detected = NA, confidence = 0, reason = "empty"))
  }
  
  # Build request - simple and direct
  prompt <- sprintf(
    "Analyze this %s narrative for intimate partner violence indicators: %s\n
    Respond with JSON: {detected: boolean, confidence: 0-1, indicators: []}",
    type, narrative
  )
  
  # API call - succeed or fail once
  response <- tryCatch({
    httr2::request(config$api$url) |>
      httr2::req_body_json(list(
        model = config$api$model,
        messages = list(list(role = "user", content = prompt)),
        temperature = 0.1
      )) |>
      httr2::req_timeout(30) |>
      httr2::req_perform() |>
      httr2::resp_body_json()
  }, error = function(e) {
    list(error = e$message)
  })
  
  # Parse response - no branching
  if (!is.null(response$error)) {
    return(list(detected = NA, confidence = 0, error = response$error))
  }
  
  # Extract results
  content <- response$choices[[1]]$message$content
  if (is.character(content)) {
    content <- jsonlite::fromJSON(content, simplifyVector = FALSE)
  }
  
  list(
    detected = content$detected %||% NA,
    confidence = content$confidence %||% 0,
    indicators = content$indicators %||% character(0)
  )
}

# ============================================================
# BATCH - Vectorized processing
# ============================================================
process_narratives <- function(data, config = NULL) {
  if (is.null(config)) config <- load_config()
  
  # Simple vectorization - R's strength
  data$ipv_le <- lapply(data$NarrativeLE, detect_ipv, type = "LE", config = config)
  data$ipv_cme <- lapply(data$NarrativeCME, detect_ipv, type = "CME", config = config)
  
  # Combine results - one line
  data$ipv_final <- mapply(function(le, cme) {
    w <- config$weights %||% c(le = 0.4, cme = 0.6)
    score <- le$confidence * w["le"] + cme$confidence * w["cme"]
    list(
      detected = score > (config$threshold %||% 0.7),
      confidence = score,
      source = if(le$confidence > cme$confidence) "LE" else "CME"
    )
  }, data$ipv_le, data$ipv_cme, SIMPLIFY = FALSE)
  
  data
}

# ============================================================
# UTILS - Minimal helpers
# ============================================================

# NULL coalescing operator - eliminates if-else
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

# Simple progress display
with_progress <- function(x, fn, ...) {
  pb <- txtProgressBar(min = 0, max = length(x), style = 3)
  on.exit(close(pb))
  
  lapply(seq_along(x), function(i) {
    setTxtProgressBar(pb, i)
    fn(x[[i]], ...)
  })
}

# ============================================================
# MAIN - User interface
# ============================================================
analyze_ipv <- function(input_file, output_file = NULL) {
  # Read
  data <- read.csv(input_file, stringsAsFactors = FALSE)
  
  # Process
  results <- process_narratives(data)
  
  # Output
  if (!is.null(output_file)) {
    # Flatten nested lists for CSV output
    results$ipv_le_detected <- sapply(results$ipv_le, `[[`, "detected")
    results$ipv_cme_detected <- sapply(results$ipv_cme, `[[`, "detected")
    results$ipv_final_detected <- sapply(results$ipv_final, `[[`, "detected")
    results$ipv_final_confidence <- sapply(results$ipv_final, `[[`, "confidence")
    
    # Remove list columns
    results$ipv_le <- results$ipv_cme <- results$ipv_final <- NULL
    
    write.csv(results, output_file, row.names = FALSE)
  }
  
  invisible(results)
}

# ============================================================
# That's all. Nothing more.
# ============================================================

# Usage example:
# results <- analyze_ipv("data.csv", "results.csv")

# That's all. Solves everything in minimal lines.
# No R6 classes, no S4 methods, no complex inheritance.
# Just functions, data, and clear flow.