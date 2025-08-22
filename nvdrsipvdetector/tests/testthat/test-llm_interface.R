test_that("build_prompt creates correct LE prompt", {
  prompt <- build_prompt("Test narrative", "LE")
  expect_true(grepl("law enforcement", prompt))
  expect_true(grepl("Test narrative", prompt))
})

test_that("build_prompt creates correct CME prompt", {
  prompt <- build_prompt("Test narrative", "CME")
  expect_true(grepl("medical examiner", prompt))
  expect_true(grepl("Test narrative", prompt))
})

test_that("send_to_llm handles errors gracefully", {
  config <- list(
    api = list(
      base_url = "http://invalid-url",
      model = "test",
      timeout = 1,
      max_retries = 0
    )
  )
  
  result <- send_to_llm("test prompt", config)
  expect_false(result$success)
  expect_true(is.na(result$ipv_detected))
})

test_that("malformed JSON is handled", {
  # Mock a malformed response
  with_mocked_bindings(
    req_perform = function(...) {
      list(body = '{"invalid": json}')
    },
    resp_body_json = function(...) {
      stop("Malformed JSON")
    },
    .package = "httr2",
    {
      config <- list(api = list(base_url = "http://test", timeout = 1, max_retries = 0))
      result <- send_to_llm("test", config)
      expect_false(result$success)
    }
  )
})