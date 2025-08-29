# Tests for parse_llm_result function

# Source the function
source(here::here("R", "parse_llm_result.R"))

test_that("parse_llm_result handles successful responses", {
  # Mock a successful response
  response <- list(
    id = "test-123",
    model = "test-model",
    created = 1234567890,
    choices = list(
      list(
        message = list(
          content = '{"detected": true, "confidence": 0.85}'
        )
      )
    ),
    usage = list(
      total_tokens = 100,
      prompt_tokens = 50,
      completion_tokens = 50
    )
  )
  
  result <- parse_llm_result(response)
  
  expect_false(result$parse_error)
  expect_true(result$detected)
  expect_equal(result$confidence, 0.85)
  expect_equal(result$tokens_used, 100)
})

test_that("parse_llm_result handles responses with special tokens", {
  # Mock response with special tokens
  response <- list(
    id = "test-123",
    model = "test-model",
    created = 1234567890,
    choices = list(
      list(
        message = list(
          content = '<|channel|>final <|constrain|>JSON<|message|>{"detected": true, "confidence": 0.85}'
        )
      )
    ),
    usage = list(
      total_tokens = 100,
      prompt_tokens = 50,
      completion_tokens = 50
    )
  )
  
  result <- parse_llm_result(response)
  
  expect_false(result$parse_error)
  expect_true(result$detected)
  expect_equal(result$confidence, 0.85)
  expect_equal(result$tokens_used, 100)
})

test_that("parse_llm_result handles malformed JSON", {
  response <- list(
    id = "test-456",
    model = "test-model",
    choices = list(
      list(
        message = list(
          content = "This is not JSON at all, just plain text response"
        )
      )
    )
  )
  
  result <- parse_llm_result(response)
  
  expect_true(result$parse_error)
  expect_true(is.na(result$detected))
  expect_equal(result$error_message, "Failed to parse JSON from response content")
  expect_equal(result$raw_response, "This is not JSON at all, just plain text response")
})

test_that("parse_llm_result handles partial JSON extraction", {
  response <- list(
    choices = list(
      list(
        message = list(
          content = "The analysis shows: {\"detected\": false, \"confidence\": 0.2} based on the narrative."
        )
      )
    )
  )
  
  result <- parse_llm_result(response)
  
  expect_false(result$parse_error)
  expect_false(result$detected)
  expect_equal(result$confidence, 0.2)
})

test_that("parse_llm_result handles NULL and empty responses", {
  # NULL response
  result_null <- parse_llm_result(NULL)
  expect_true(result_null$parse_error)
  expect_equal(result_null$error_message, "Response is NULL")
  
  # Not a list
  result_string <- parse_llm_result("not a list")
  expect_true(result_string$parse_error)
  expect_equal(result_string$error_message, "Response is not a list")
  
  # Empty content
  response_empty <- list(
    choices = list(
      list(
        message = list(
          content = ""
        )
      )
    )
  )
  result_empty <- parse_llm_result(response_empty)
  expect_true(result_empty$parse_error)
  expect_equal(result_empty$error_message, "No content in response")
})

test_that("parse_llm_result handles API error responses", {
  response <- list(
    error = TRUE,
    error_message = "API rate limit exceeded"
  )
  
  result <- parse_llm_result(response)
  
  expect_true(result$parse_error)
  expect_equal(result$error_message, "API rate limit exceeded")
})

test_that("parse_llm_result includes narrative_id and metadata", {
  response <- list(
    choices = list(
      list(
        message = list(
          content = '{"detected": true, "confidence": 0.9}'
        )
      )
    )
  )
  
  result <- parse_llm_result(
    response,
    narrative_id = "case_123",
    metadata = list(batch = "2025-01", source = "test")
  )
  
  expect_equal(result$narrative_id, "case_123")
  expect_equal(result$metadata$batch, "2025-01")
  expect_equal(result$metadata$source, "test")
})

test_that("parse_llm_result extracts extended fields", {
  response <- list(
    choices = list(
      list(
        message = list(
          content = '{"detected": true, "confidence": 0.95, "severity": "high", "weapon": "firearm"}'
        )
      )
    )
  )
  
  result <- parse_llm_result(response)
  
  expect_false(result$parse_error)
  expect_true(result$detected)
  expect_equal(result$confidence, 0.95)
  expect_equal(result$metadata$llm_severity, "high")
  expect_equal(result$metadata$llm_weapon, "firearm")
})

test_that("parse_llm_result handles timestamp conversion", {
  response <- list(
    created = 1234567890,
    choices = list(
      list(
        message = list(
          content = '{"detected": false, "confidence": 0.1}'
        )
      )
    )
  )
  
  result <- parse_llm_result(response)
  
  expect_false(is.na(result$created_at))
  expect_true(grepl("^\\d{4}-\\d{2}-\\d{2}T", result$created_at))
})

test_that("parse_llm_result handles whitespace and line breaks", {
  response <- list(
    choices = list(
      list(
        message = list(
          content = "\n\n   {\"detected\": true,\n   \"confidence\": 0.75}   \n\n"
        )
      )
    )
  )
  
  result <- parse_llm_result(response)
  
  expect_false(result$parse_error)
  expect_true(result$detected)
  expect_equal(result$confidence, 0.75)
})

test_that("parse_llm_result extracts test metadata", {
  response <- list(
    choices = list(
      list(
        message = list(
          content = '{"detected": false, "confidence": 0.3}'
        )
      )
    ),
    test_metadata = list(
      elapsed_seconds = 1.5,
      prompt_length = 250
    )
  )
  
  result <- parse_llm_result(response)
  
  expect_equal(result$response_time_ms, 1500)
  expect_equal(result$narrative_length, 250)
})

test_that("parse_llm_result handles confidence out of range", {
  response <- list(
    choices = list(
      list(
        message = list(
          content = '{"detected": true, "confidence": 1.5}'  # Invalid confidence
        )
      )
    )
  )
  
  result <- parse_llm_result(response)
  
  expect_true(result$detected)
  expect_true(is.na(result$confidence))  # Should reject invalid confidence
})

test_that("parse_llm_result fallback extraction from text", {
  response <- list(
    choices = list(
      list(
        message = list(
          content = "The result is \"detected\": true with \"confidence\": 0.88 but JSON is broken"
        )
      )
    )
  )
  
  result <- parse_llm_result(response)
  
  expect_true(result$parse_error)  # JSON parsing failed
  expect_true(result$detected)     # But extracted from text
  expect_equal(result$confidence, 0.88)  # Also extracted from text
})

test_that("parse_llm_result handles nested response structures", {
  response <- list(
    id = "nested-test",
    model = "gpt-4",
    created = 1234567890,
    choices = list(
      list(
        index = 0,
        message = list(
          role = "assistant",
          content = '{"detected": false, "confidence": 0.05}',
          reasoning = "No IPV indicators found"
        ),
        finish_reason = "stop"
      )
    ),
    usage = list(
      prompt_tokens = 100,
      completion_tokens = 50,
      total_tokens = 150
    ),
    system_fingerprint = "fp_123"
  )
  
  result <- parse_llm_result(response)
  
  expect_false(result$parse_error)
  expect_false(result$detected)
  expect_equal(result$confidence, 0.05)
  expect_equal(result$model, "gpt-4")
  expect_equal(result$tokens_used, 150)
  expect_equal(result$prompt_tokens, 100)
  expect_equal(result$completion_tokens, 50)
})

# Performance test
test_that("parse_llm_result meets performance target", {
  response <- list(
    choices = list(
      list(
        message = list(
          content = '{"detected": true, "confidence": 0.5}'
        )
      )
    )
  )
  
  # Measure parsing speed
  start_time <- Sys.time()
  for (i in 1:100) {
    result <- parse_llm_result(response)
  }
  elapsed <- as.numeric(Sys.time() - start_time)
  
  # Should parse >500 per second, so 100 should take <0.2 seconds
  expect_lt(elapsed, 0.2)
})

