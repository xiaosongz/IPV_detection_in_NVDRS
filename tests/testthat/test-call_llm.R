# Load test prompts from JSON file
test_prompts <- jsonlite::fromJSON(here::here("tests", "test_prompt.json"))
sample_ipv_system_prompt <- test_prompts$system_prompt
sample_ipv_user_prompt <- test_prompts$user_prompt

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


test_that("call_llm works with test prompt JSON", {
  skip_if_not(file.exists(here::here("tests", "test_prompt.json")), 
              "Test prompt JSON file not found")
  
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
  
  # Call the function with sample IPV prompts from JSON
  result <- call_llm(
    sample_ipv_user_prompt, 
    sample_ipv_system_prompt, 
    temperature = 0.1
  )
  
  # Check response structure
  expect_type(result, "list")
  expect_true("choices" %in% names(result))
  expect_true("usage" %in% names(result))
  expect_true("model" %in% names(result))
  
  # Check content exists
  content <- result$choices[[1]]$message$content
  expect_type(content, "character")
  expect_gt(nchar(content), 0)
  
  # If it's JSON, it should parse
  if (grepl("^\\{", trimws(content))) {
    parsed <- jsonlite::fromJSON(content)
    expect_type(parsed, "list")
    
    # For IPV detection prompt, check expected fields
    expect_true("ipv_detected" %in% names(parsed))
    expect_true("confidence" %in% names(parsed))
  }
})

test_that("call_llm respects temperature parameter", {
  skip_if_not(
    Sys.getenv("LLM_API_URL") != "",
    "LLM API URL not configured"
  )
  
  # Temperature 0 should give consistent results
  user_prompt <- "What is 2+2? Answer with just the number."
  system_prompt <- "You are a helpful assistant."
  
  result1 <- call_llm(user_prompt, system_prompt, temperature = 0)
  result2 <- call_llm(user_prompt, system_prompt, temperature = 0)
  
  # With temperature 0, responses should be identical
  # (though some models may still have minimal variation)
  expect_equal(
    result1$choices[[1]]$message$content,
    result2$choices[[1]]$message$content
  )
})