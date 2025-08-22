# IPV Detection with mall - Model Auto-detection for LM Studio
# This version checks available models first before processing

library(tidyverse)
library(mall)
library(httr2)
library(jsonlite)
library(readxl)
library(glue)

# ============================================================================
# LM Studio API Helper Functions
# ============================================================================

# Check LM Studio server status and get available models
check_lm_studio <- function(base_url = "http://192.168.10.22:1234") {
  cat("Checking LM Studio server...\n")
  cat(glue("Server URL: {base_url}\n\n"))
  
  # Check if server is running
  server_check <- tryCatch({
    response <- request(paste0(base_url, "/v1/models")) |>
      req_headers("Content-Type" = "application/json") |>
      req_perform() |>
      resp_body_json()
    
    if (!is.null(response$data) && length(response$data) > 0) {
      cat("✓ LM Studio server is running\n\n")
      cat("Available models:\n")
      cat("─────────────────\n")
      
      models <- map_chr(response$data, ~ .x$id)
      for (i in seq_along(models)) {
        cat(glue("{i}. {models[i]}\n"))
      }
      cat("\n")
      
      return(list(
        status = "connected",
        models = models,
        base_url = base_url
      ))
    } else {
      cat("⚠ Server is running but no models are loaded\n")
      cat("Please load a model in LM Studio first\n")
      return(list(
        status = "no_models",
        models = character(0),
        base_url = base_url
      ))
    }
  }, error = function(e) {
    cat("✗ Cannot connect to LM Studio server\n")
    cat(glue("Error: {e$message}\n\n"))
    cat("Please ensure:\n")
    cat("1. LM Studio is running\n")
    cat("2. Server is started (not just the app)\n")
    cat(glue("3. Server is accessible at {base_url}\n"))
    return(list(
      status = "disconnected",
      models = character(0),
      base_url = base_url
    ))
  })
  
  return(server_check)
}

# Select model interactively or automatically
select_model <- function(server_info) {
  if (server_info$status != "connected") {
    stop("Cannot select model: LM Studio not connected or no models available")
  }
  
  models <- server_info$models
  
  # Check for exact matches first
  if ("qwen3-30b-2507" %in% models) {
    cat("Found preferred model: qwen3-30b-2507\n")
    return("qwen3-30b-2507")
  }
  
  # Check for qwen3-30b variations
  qwen30b_models <- models[grepl("qwen.*30b", models, ignore.case = TRUE)]
  if (length(qwen30b_models) > 0) {
    # Prefer models with "2507" in the name
    model_2507 <- qwen30b_models[grepl("2507", qwen30b_models)]
    if (length(model_2507) > 0) {
      cat(glue("Found Qwen 30B 2507 model: {model_2507[1]}\n"))
      return(model_2507[1])
    }
    cat(glue("Found Qwen 30B model: {qwen30b_models[1]}\n"))
    return(qwen30b_models[1])
  }
  
  # Check for qwen3-coder models (text generation capable)
  qwen_coder <- models[grepl("qwen.*coder", models, ignore.case = TRUE)]
  if (length(qwen_coder) > 0) {
    cat(glue("Found Qwen Coder model: {qwen_coder[1]}\n"))
    return(qwen_coder[1])
  }
  
  # Check for any qwen text models (avoiding image models)
  qwen_models <- models[grepl("qwen", models, ignore.case = TRUE) & 
                        !grepl("image|vision|flux", models, ignore.case = TRUE)]
  if (length(qwen_models) > 0) {
    cat(glue("Found Qwen model: {qwen_models[1]}\n"))
    return(qwen_models[1])
  }
  
  # If only one model available, use it
  if (length(models) == 1) {
    cat(glue("Using the only available model: {models[1]}\n"))
    return(models[1])
  }
  
  # Otherwise, prompt user to select
  cat("\nMultiple models available. Please select one:\n")
  for (i in seq_along(models)) {
    cat(glue("{i}. {models[i]}\n"))
  }
  
  # For automated scripts, just use the first model
  # In interactive mode, you could use readline() to get user input
  cat(glue("\nAuto-selecting first model: {models[1]}\n"))
  return(models[1])
}

# Test the connection with a simple prompt
test_model_connection <- function(base_url, model_name) {
  cat(glue("\nTesting model: {model_name}\n"))
  
  test_result <- tryCatch({
    response <- request(paste0(base_url, "/v1/chat/completions")) |>
      req_headers(
        "Content-Type" = "application/json"
      ) |>
      req_body_json(list(
        model = model_name,
        messages = list(
          list(role = "user", content = "Say 'Connection successful' and nothing else.")
        ),
        temperature = 0.1,
        max_tokens = 50
      )) |>
      req_perform() |>
      resp_body_json()
    
    if (!is.null(response$choices)) {
      cat("✓ Model connection successful\n")
      return(TRUE)
    } else {
      cat("⚠ Unexpected response format\n")
      return(FALSE)
    }
  }, error = function(e) {
    cat(glue("✗ Model test failed: {e$message}\n"))
    return(FALSE)
  })
  
  return(test_result)
}

# ============================================================================
# Configure mall with LM Studio
# ============================================================================

setup_mall_with_lm_studio <- function(base_url = "http://192.168.10.22:1234") {
  
  # Check server and get available models
  server_info <- check_lm_studio(base_url)
  
  if (server_info$status != "connected") {
    stop("Cannot proceed: LM Studio server not available")
  }
  
  # Select model
  model_name <- select_model(server_info)
  
  # Test the model
  if (!test_model_connection(base_url, model_name)) {
    stop(glue("Cannot proceed: Model {model_name} not responding"))
  }
  
  # Since mall 0.1.0 doesn't support ellmer directly, 
  # we'll use a workaround with custom functions
  
  cat("\nNote: mall 0.1.0 doesn't support ellmer chat objects directly.\n")
  cat("Using direct API calls for LM Studio integration.\n")
  
  # Store configuration globally for our custom functions
  .lm_studio_config <<- list(
    base_url = base_url,
    model = model_name
  )
  
  cat(glue("\n✓ Mall configured with model: {model_name}\n"))
  
  return(list(
    model = model_name,
    base_url = base_url,
    status = "ready"
  ))
}

# ============================================================================
# IPV Detection Functions (same as before)
# ============================================================================

create_ipv_prompt <- function() {
  paste(
    "You are analyzing a death investigation narrative for intimate partner violence indicators.",
    "Provide a structured analysis in JSON format.",
    "",
    "Return ONLY a valid JSON object with these fields:",
    "{",
    '  "ipv_detected": "yes/no/unclear",',
    '  "confidence": "high/medium/low",',
    '  "intimate_partner": "yes/no/unclear",',
    '  "violence_indicators": "yes/no/unclear",',
    '  "substance_abuse": "yes/no/unclear",',
    '  "key_evidence": "Brief quote or description from text",',
    '  "risk_factors": "List any IPV risk factors found"',
    "}",
    "",
    "Base all answers on explicit text evidence only.",
    "Return ONLY the JSON, no other text.",
    "",
    "Narrative:"
  )
}

# Custom function to call LM Studio directly
call_lm_studio <- function(prompt_text) {
  if (!exists(".lm_studio_config")) {
    stop("LM Studio not configured. Run setup_mall_with_lm_studio() first.")
  }
  
  response <- request(paste0(.lm_studio_config$base_url, "/v1/chat/completions")) |>
    req_headers("Content-Type" = "application/json") |>
    req_body_json(list(
      model = .lm_studio_config$model,
      messages = list(
        list(role = "system", content = "You are a helpful assistant."),
        list(role = "user", content = prompt_text)
      ),
      temperature = 0.1,
      max_tokens = 1000
    )) |>
    req_perform() |>
    resp_body_json()
  
  return(response$choices[[1]]$message$content)
}

process_single_narrative <- function(narrative_text, case_id = NA) {
  
  if (is.na(narrative_text) || nchar(trimws(narrative_text)) == 0) {
    return(tibble(
      case_id = case_id,
      ipv_detected = "skipped",
      confidence = "NA",
      intimate_partner = "skipped",
      violence_indicators = "skipped",
      substance_abuse = "skipped",
      key_evidence = "Empty narrative",
      risk_factors = "None",
      processing_status = "skipped_empty"
    ))
  }
  
  # Combine prompt and narrative
  full_prompt <- paste(create_ipv_prompt(), narrative_text)
  
  # Call LM Studio directly
  result <- tryCatch({
    call_lm_studio(full_prompt)
  }, error = function(e) {
    paste("Error:", e$message)
  })
  
  # Parse the response
  parsed <- tryCatch({
    # Clean the response
    response <- gsub("```json\\s*|```\\s*", "", result)
    response <- trimws(response)
    
    # Check if response looks like an error
    if (grepl("^Error:", response)) {
      stop(response)
    }
    
    # Try to parse JSON
    json_data <- fromJSON(response, flatten = TRUE)
    
    tibble(
      case_id = case_id,
      ipv_detected = if(!is.null(json_data$ipv_detected)) json_data$ipv_detected else "parse_error",
      confidence = if(!is.null(json_data$confidence)) json_data$confidence else "parse_error",
      intimate_partner = if(!is.null(json_data$intimate_partner)) json_data$intimate_partner else "parse_error",
      violence_indicators = if(!is.null(json_data$violence_indicators)) json_data$violence_indicators else "parse_error",
      substance_abuse = if(!is.null(json_data$substance_abuse)) json_data$substance_abuse else "parse_error",
      key_evidence = if(!is.null(json_data$key_evidence)) json_data$key_evidence else "parse_error",
      risk_factors = if(!is.null(json_data$risk_factors)) json_data$risk_factors else "parse_error",
      processing_status = "success"
    )
  }, error = function(e) {
    tibble(
      case_id = case_id,
      ipv_detected = "error",
      confidence = "error",
      intimate_partner = "error",
      violence_indicators = "error",
      substance_abuse = "error",
      key_evidence = paste("Parse error:", e$message),
      risk_factors = "error",
      processing_status = "parse_error"
    )
  })
  
  return(parsed)
}

analyze_narratives <- function(data, text_column, id_column = NULL) {
  
  if (is.null(id_column)) {
    data <- data |> mutate(.temp_id = row_number())
    id_column <- ".temp_id"
  }
  
  n_total <- nrow(data)
  cat(glue("\nProcessing {n_total} narratives individually\n\n"))
  
  results <- map2_dfr(
    data[[text_column]], 
    data[[id_column]],
    function(text, id) {
      cat(glue("\rProcessing case: {id}    "))
      result <- process_single_narrative(text, id)
      Sys.sleep(0.2)
      return(result)
    }
  )
  
  cat("\n\nProcessing complete!\n")
  
  final_data <- data |>
    left_join(results, by = setNames("case_id", id_column))
  
  cat("\n=== Summary ===\n")
  results |>
    count(ipv_detected) |>
    print()
  
  return(final_data)
}

# ============================================================================
# Main Execution
# ============================================================================

cat("╔══════════════════════════════════════════╗\n")
cat("║   IPV Detection with LM Studio & mall   ║\n")
cat("╚══════════════════════════════════════════╝\n\n")

# Setup connection with auto-detection
lm_config <- setup_mall_with_lm_studio("http://192.168.10.22:1234")

if (lm_config$status == "ready") {
  
  # Create sample data
  demo_data <- tibble(
    case_number = c("2024-IPV-001", "2024-ACC-002", "2024-IPV-003"),
    narrative_text = c(
      "The victim, a 34-year-old woman, was found deceased in her bedroom. Her estranged husband was arrested at the scene after neighbors reported hearing arguing. The victim had an active restraining order against her husband.",
      
      "A 45-year-old male driver lost control of his vehicle on Interstate 95 during heavy rain. The vehicle hydroplaned and struck the median barrier.",
      
      "The decedent was discovered unresponsive by her boyfriend. Friends reported she had recently tried to leave him due to controlling behavior."
    )
  )
  
  cat("\n=== Running Demo Analysis ===\n")
  
  analyzed_data <- analyze_narratives(
    demo_data,
    text_column = "narrative_text",
    id_column = "case_number"
  )
  
  cat("\n=== Detailed Results ===\n")
  analyzed_data |>
    select(case_number, ipv_detected, confidence, key_evidence) |>
    print(width = Inf)
  
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  output_path <- glue("output/ipv_analysis_mall_{timestamp}.csv")
  write_csv(analyzed_data, output_path)
  cat(glue("\nResults saved to: {output_path}\n"))
  
} else {
  cat("\nSetup failed. Please check LM Studio configuration.\n")
}

# ============================================================================
# Helper function to process actual NVDRS data
# ============================================================================

process_nvdrs_with_mall <- function(file_path, narrative_col = "narrative") {
  
  # Ensure connection is ready
  if (!exists("lm_config") || lm_config$status != "ready") {
    cat("Setting up LM Studio connection first...\n")
    lm_config <<- setup_mall_with_lm_studio("http://192.168.10.22:1234")
  }
  
  cat("\nLoading NVDRS data...\n")
  data <- read_excel(file_path)
  
  cat(glue("Found {nrow(data)} records\n\n"))
  
  results <- analyze_narratives(
    data,
    text_column = narrative_col,
    id_column = if("case_id" %in% names(data)) "case_id" else NULL
  )
  
  output_file <- glue("output/nvdrs_ipv_mall_{Sys.Date()}.csv")
  write_csv(results, output_file)
  
  cat(glue("\nResults saved to: {output_file}\n"))
  
  return(results)
}

cat("\n─────────────────────────────────────────\n")
cat("To process your actual data, run:\n")
cat("  results <- process_nvdrs_with_mall('path/to/data.xlsx', 'narrative_column')\n")
cat("─────────────────────────────────────────\n")