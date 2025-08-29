# Tests for call_llm function

# Source the function
source(here::here("R", "call_llm.R"))

test_that("call_llm validates input parameters", {
  # Test invalid prompt types
  expect_error(
    call_llm(123, "system"),
    "'user_prompt' must be a single character string"
  )
  
  expect_error(
    call_llm("user", 123),
    "'system_prompt' must be a single character string"
  )
  
  expect_error(
    call_llm(c("prompt1", "prompt2"), "system"),
    "'user_prompt' must be a single character string"
  )
  
  expect_error(
    call_llm("user", c("sys1", "sys2")),
    "'system_prompt' must be a single character string"
  )
  
  # Test invalid temperature values
  expect_error(
    call_llm("test", "system", temperature = -0.1),
    "'temperature' must be a number between 0 and 1"
  )
  
  expect_error(
    call_llm("test", "system", temperature = 1.5),
    "'temperature' must be a number between 0 and 1"
  )
  
  expect_error(
    call_llm("test", "system", temperature = "high"),
    "'temperature' must be a number between 0 and 1"
  )
})


test_that("call_llm works with API when available", {
  # Check if LLM API is available
  api_url <- Sys.getenv("LLM_API_URL", 
                        "http://192.168.10.22:1234/v1/chat/completions")
  
  skip_if_not(
    tryCatch({
      httr2::request(api_url) |>
        httr2::req_timeout(5) |>
        httr2::req_perform()
      TRUE
    }, error = function(e) FALSE),
    "LLM API not available"
  )
  
  # Call the function with simple prompts
  result <- call_llm(
    "Test message", 
    "You are a test assistant", 
    temperature = 0.1
  )
  
  # Check response structure
  expect_type(result, "list")
  expect_true("choices" %in% names(result))
  
  # Check content exists
  content <- result$choices[[1]]$message$content
  expect_type(content, "character")
  expect_gt(nchar(content), 0)
})