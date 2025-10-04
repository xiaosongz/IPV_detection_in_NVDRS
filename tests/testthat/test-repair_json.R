test_that("repair_json fixes spelled-out decimal numbers", {
  # Test 0.9
  input <- '{"confidence": 0. nine}'
  expected <- '{"confidence": 0.9}'
  expect_equal(repair_json(input), expected)
  
  # Test 0.8
  input <- '{"confidence": 0. eight}'
  expected <- '{"confidence": 0.8}'
  expect_equal(repair_json(input), expected)
  
  # Test 0.7
  input <- '{"confidence": 0. seven}'
  expected <- '{"confidence": 0.7}'
  expect_equal(repair_json(input), expected)
})

test_that("repair_json handles no spaces", {
  input <- '{"confidence": 0.nine}'
  expected <- '{"confidence": 0.9}'
  expect_equal(repair_json(input), expected)
})

test_that("repair_json handles multiple spaces", {
  input <- '{"confidence": 0.  nine}'
  expected <- '{"confidence": 0.9}'
  expect_equal(repair_json(input), expected)
})

test_that("repair_json handles complete JSON response", {
  input <- '{"detected": true, "confidence": 0. eight, "rationale": "test"}'
  result <- repair_json(input)
  expect_true(grepl("0\\.8", result))
  expect_false(grepl("0\\.\\s*eight", result))
  
  # Verify it can be parsed after repair
  parsed <- jsonlite::fromJSON(result)
  expect_equal(parsed$confidence, 0.8)
  expect_equal(parsed$detected, TRUE)
})

test_that("repair_json handles multiple errors in same response", {
  input <- '{"a": 0. nine, "b": 0. five, "c": 0. eight}'
  result <- repair_json(input)
  expect_true(grepl("0\\.9", result))
  expect_true(grepl("0\\.5", result))
  expect_true(grepl("0\\.8", result))
  expect_false(grepl("nine|five|eight", result))
})

test_that("repair_json leaves valid JSON unchanged", {
  input <- '{"detected": true, "confidence": 0.85, "rationale": "test"}'
  expect_equal(repair_json(input), input)
})

test_that("repair_json handles all decimal mappings", {
  test_cases <- list(
    c("0. zero", "0.0"),
    c("0. one", "0.1"),
    c("0. two", "0.2"),
    c("0. three", "0.3"),
    c("0. four", "0.4"),
    c("0. five", "0.5"),
    c("0. six", "0.6"),
    c("0. seven", "0.7"),
    c("0. eight", "0.8"),
    c("0. nine", "0.9")
  )
  
  for (test_case in test_cases) {
    input <- paste0('{"confidence": ', test_case[1], '}')
    result <- repair_json(input)
    expect_true(grepl(test_case[2], result), 
                info = paste("Failed for", test_case[1]))
  }
})
