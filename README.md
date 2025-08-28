# IPV Detection in NVDRS

A 30-line function that detects intimate partner violence in death narratives. That's it.

## What This Is

One function (`detect_ipv`) that sends text to an LLM and gets back IPV detection results. No magic, no complexity, just a simple API call wrapped in error handling.

## What This Is NOT

- NOT a complex R package with 50 dependencies
- NOT an abstraction layer that hides what's happening
- NOT a framework that dictates your workflow
- NOT a solution looking for a problem

## The Entire Implementation

```r
detect_ipv <- function(text, config = NULL) {
  # Default config
  if (is.null(config)) {
    config <- list(
      api_url = Sys.getenv("LLM_API_URL", "http://192.168.10.22:1234/v1/chat/completions"),
      model = Sys.getenv("LLM_MODEL", "openai/gpt-oss-120b")
    )
  }
  
  # Empty input = empty output
  if (is.null(text) || is.na(text) || trimws(text) == "") {
    return(list(detected = NA, confidence = 0))
  }
  
  # Call API
  tryCatch({
    response <- httr2::request(config$api_url) |>
      httr2::req_body_json(list(
        model = config$model,
        messages = list(list(role = "user", content = text))
      )) |>
      httr2::req_perform() |>
      httr2::resp_body_json()
    
    jsonlite::fromJSON(response$choices[[1]]$message$content)
  }, error = function(e) {
    list(detected = NA, confidence = 0, error = e$message)
  })
}
```

That's the whole thing. 30 lines. Done.

## Installation? Copy the Function

```r
# Step 1: Copy the detect_ipv function from above
# Step 2: Install dependencies
install.packages(c("httr2", "jsonlite"))
# Step 3: There is no step 3
```

## Setup

```r
# Point to your LLM
Sys.setenv(LLM_API_URL = "http://192.168.10.22:1234/v1/chat/completions")
Sys.setenv(LLM_MODEL = "openai/gpt-oss-120b")
```

## Usage

```r
# Single narrative
result <- detect_ipv("Husband shot wife during argument")
print(result$detected)  # TRUE or FALSE

# Batch processing (YOU control the loop)
data <- readxl::read_excel("your_data.xlsx")
data$ipv <- lapply(data$narrative, detect_ipv)

# Parallel? Your choice
library(parallel)
results <- mclapply(narratives, detect_ipv, mc.cores = 4)

# Custom prompt? Pass config
my_config <- list(
  api_url = "http://your-llm/v1/chat/completions",
  model = "your-model"
)
result <- detect_ipv(text, my_config)
```

That's it. No frameworks. No abstractions. Just a function call.

## Input/Output

You give it text. It returns:
```r
list(
  detected = TRUE/FALSE,
  confidence = 0.0-1.0,
  error = "message if failed"
)
```

## Optional: Storage & Experiments

If you want to store results or track prompt experiments:

```r
# Store results (optional)
source("R/0_setup.R")
parsed <- parse_llm_result(response)
conn <- connect_db()
store_llm_result(parsed, conn)

# Track experiments (for R&D)
prompt_id <- register_prompt(conn, system_prompt, user_prompt)
results <- ab_test_prompts(conn, prompt_v1, prompt_v2, test_data)
```

See `docs/RESULT_STORAGE_GUIDE.md` for details. Or don't. The 30-line function works fine without it.

## The Real Implementation Files

- `docs/ULTIMATE_CLEAN.R` - The 30-line version. Use this.
- `docs/CLEAN_IMPLEMENTATION.R` - 100-line version with batching if you need it.
- `docs/RESULT_STORAGE_GUIDE.md` - Storage and experiment tracking (optional).
- `docs/EXPERIMENT_MODE_GUIDE.md` - R&D prompt optimization (optional).
- Everything else - Legacy complexity. Ignore it.

## Why This Approach?

Because 99% of "data science" code is just:
1. Read data
2. Call an API
3. Write results

The other 10,000 lines? Abstractions that make simple things complicated. 

This project rejects that. One function. Clear purpose. You control everything else.

## License

MIT. Do whatever you want with it.