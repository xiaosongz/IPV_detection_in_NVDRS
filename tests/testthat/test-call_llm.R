test_that("call_llm validates input parameters", {
  # Test invalid prompt types
  expect_error(
    call_llm(123),
    "'prompt' must be a single character string"
  )
  
  expect_error(
    call_llm(c("prompt1", "prompt2")),
    "'prompt' must be a single character string"
  )
  
  expect_error(
    call_llm(NULL),
    "'prompt' must be a single character string"
  )
  
  # Test invalid temperature values
  expect_error(
    call_llm("test", temperature = -0.1),
    "'temperature' must be a number between 0 and 1"
  )
  
  expect_error(
    call_llm("test", temperature = 1.5),
    "'temperature' must be a number between 0 and 1"
  )
  
  expect_error(
    call_llm("test", temperature = "high"),
    "'temperature' must be a number between 0 and 1"
  )
})

test_that("call_llm builds correct request structure", {
  # Mock the httr2 functions to test request building
  # This test would require httptest2 or mockery for proper mocking
  skip_if_not_installed("mockery")
  
  # Example of what the test would look like with mocking:
  # mock_response <- list(
  #   choices = list(list(message = list(content = "test response"))),
  #   usage = list(total_tokens = 100)
  # )
  # 
  # mockery::stub(call_llm, "httr2::req_perform", mock_response)
  # result <- call_llm("test prompt")
  # expect_equal(result$choices[[1]]$message$content, "test response")
})

test_that("call_llm works with test prompt file", {
  skip_if_not(file.exists("tests/test_promt.txt"), 
              "Test prompt file not found")
  
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
  
  # Read test prompt
  prompt <- readLines(here::here("tests", "test_promt.txt"), 
                     warn = FALSE) |> 
    paste(collapse = "\n")
  
  # Call the function
  result <- call_llm(prompt, temperature = 0.1)
  
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
  prompt <- "What is 2+2? Answer with just the number."
  
  result1 <- call_llm(prompt, temperature = 0)
  result2 <- call_llm(prompt, temperature = 0)
  
  # With temperature 0, responses should be identical
  # (though some models may still have minimal variation)
  expect_equal(
    result1$choices[[1]]$message$content,
    result2$choices[[1]]$message$content
  )
})