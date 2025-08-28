# Comprehensive tests for build_prompt function

test_that("build_prompt creates correct message structure with valid inputs", {
  # Basic valid inputs
  result <- build_prompt("You are helpful.", "Hello world")
  
  expect_type(result, "list")
  expect_length(result, 2)
  
  # Check system message
  expect_equal(result[[1]]$role, "system")
  expect_equal(result[[1]]$content, "You are helpful.")
  
  # Check user message
  expect_equal(result[[2]]$role, "user")
  expect_equal(result[[2]]$content, "Hello world")
})

test_that("build_prompt handles edge cases with special content", {
  # Empty strings (valid edge case)
  result <- build_prompt("", "")
  expect_equal(result[[1]]$content, "")
  expect_equal(result[[2]]$content, "")
  
  # Very long strings
  long_text <- paste(rep("a", 10000), collapse = "")
  result <- build_prompt(long_text, long_text)
  expect_equal(nchar(result[[1]]$content), 10000)
  expect_equal(nchar(result[[2]]$content), 10000)
  
  # Strings with newlines and tabs
  result <- build_prompt("Line1\nLine2\tTabbed", "User\nMultiline\tContent")
  expect_equal(result[[1]]$content, "Line1\nLine2\tTabbed")
  expect_equal(result[[2]]$content, "User\nMultiline\tContent")
  
  # Strings with quotes and escaping
  result <- build_prompt('She said "Hello"', "It's a test with 'quotes'")
  expect_equal(result[[1]]$content, 'She said "Hello"')
  expect_equal(result[[2]]$content, "It's a test with 'quotes'")
  
  # JSON-like content
  json_sys <- '{"key": "value", "nested": {"array": [1, 2, 3]}}'
  json_user <- '{"ipv_detected": true, "confidence": 0.95}'
  result <- build_prompt(json_sys, json_user)
  expect_equal(result[[1]]$content, json_sys)
  expect_equal(result[[2]]$content, json_user)
  
  # Unicode and special characters
  result <- build_prompt("System: 你好 🚀 ñ €", "User: مرحبا 😊 ® ™")
  expect_equal(result[[1]]$content, "System: 你好 🚀 ñ €")
  expect_equal(result[[2]]$content, "User: مرحبا 😊 ® ™")
  
  # Whitespace-only strings
  result <- build_prompt("   ", "\t\n  ")
  expect_equal(result[[1]]$content, "   ")
  expect_equal(result[[2]]$content, "\t\n  ")
  
  # HTML/XML content
  html_content <- "<div class='test'>Hello <b>world</b></div>"
  xml_content <- "<?xml version='1.0'?><root><item>Test</item></root>"
  result <- build_prompt(html_content, xml_content)
  expect_equal(result[[1]]$content, html_content)
  expect_equal(result[[2]]$content, xml_content)
  
  # SQL injection-like content (should pass through safely)
  sql_like <- "'; DROP TABLE users; --"
  result <- build_prompt(sql_like, sql_like)
  expect_equal(result[[1]]$content, sql_like)
  expect_equal(result[[2]]$content, sql_like)
  
  # Path traversal-like content
  path_like <- "../../../etc/passwd"
  result <- build_prompt(path_like, path_like)
  expect_equal(result[[1]]$content, path_like)
  expect_equal(result[[2]]$content, path_like)
})

test_that("build_prompt rejects invalid system_prompt inputs", {
  # NULL
  expect_error(
    build_prompt(NULL, "valid"),
    "'system_prompt' must be a single character string"
  )
  
  # Numeric
  expect_error(
    build_prompt(123, "valid"),
    "'system_prompt' must be a single character string"
  )
  
  # Logical
  expect_error(
    build_prompt(TRUE, "valid"),
    "'system_prompt' must be a single character string"
  )
  
  # List
  expect_error(
    build_prompt(list(a = 1), "valid"),
    "'system_prompt' must be a single character string"
  )
  
  # Data frame
  expect_error(
    build_prompt(data.frame(x = 1), "valid"),
    "'system_prompt' must be a single character string"
  )
  
  # Multiple element vector
  expect_error(
    build_prompt(c("prompt1", "prompt2"), "valid"),
    "'system_prompt' must be a single character string"
  )
  
  # Character vector with length 0
  expect_error(
    build_prompt(character(0), "valid"),
    "'system_prompt' must be a single character string"
  )
  
  # NA value (NA_character_ is still character type with length 1, just NA content)
  # The function only checks is.character() and length, not NA content
  # So NA_character_ actually passes - let's test this correctly
  result <- build_prompt(NA_character_, "valid")
  expect_true(is.na(result[[1]]$content))
  expect_equal(result[[2]]$content, "valid")
  
  # Factor (common R gotcha)
  expect_error(
    build_prompt(factor("test"), "valid"),
    "'system_prompt' must be a single character string"
  )
})

test_that("build_prompt rejects invalid user_prompt inputs", {
  # NULL
  expect_error(
    build_prompt("valid", NULL),
    "'user_prompt' must be a single character string"
  )
  
  # Numeric
  expect_error(
    build_prompt("valid", 456),
    "'user_prompt' must be a single character string"
  )
  
  # Logical
  expect_error(
    build_prompt("valid", FALSE),
    "'user_prompt' must be a single character string"
  )
  
  # List
  expect_error(
    build_prompt("valid", list(b = 2)),
    "'user_prompt' must be a single character string"
  )
  
  # Data frame
  expect_error(
    build_prompt("valid", data.frame(y = 2)),
    "'user_prompt' must be a single character string"
  )
  
  # Multiple element vector
  expect_error(
    build_prompt("valid", c("user1", "user2", "user3")),
    "'user_prompt' must be a single character string"
  )
  
  # Character vector with length 0
  expect_error(
    build_prompt("valid", character(0)),
    "'user_prompt' must be a single character string"
  )
  
  # NA value
  expect_error(
    build_prompt("valid", NA),
    "'user_prompt' must be a single character string"
  )
  
  # Complex numbers
  expect_error(
    build_prompt("valid", complex(real = 1, imaginary = 2)),
    "'user_prompt' must be a single character string"
  )
})

test_that("build_prompt handles missing arguments", {
  # Missing both arguments
  expect_error(
    build_prompt(),
    "argument \"system_prompt\" is missing"
  )
  
  # Missing user_prompt
  expect_error(
    build_prompt("system"),
    "argument \"user_prompt\" is missing"
  )
  
  # Missing system_prompt (using named argument)
  expect_error(
    build_prompt(user_prompt = "user"),
    "argument \"system_prompt\" is missing"
  )
})

test_that("build_prompt preserves exact content without modification", {
  # Test that no trimming occurs
  spaces <- "  text with spaces  "
  result <- build_prompt(spaces, spaces)
  expect_equal(result[[1]]$content, spaces)
  expect_equal(result[[2]]$content, spaces)
  
  # Test that no escaping is added
  special <- "Line1\nLine2\t'quoted'\""
  result <- build_prompt(special, special)
  expect_equal(result[[1]]$content, special)
  expect_equal(result[[2]]$content, special)
  
  # Test exact byte preservation
  exact_text <- "Test\r\nWindows\nUnix\rOld"
  result <- build_prompt(exact_text, exact_text)
  expect_equal(result[[1]]$content, exact_text)
  expect_equal(result[[2]]$content, exact_text)
})

test_that("build_prompt output structure is consistent", {
  result <- build_prompt("sys", "usr")
  
  # Check structure consistency
  expect_true(is.list(result))
  expect_equal(length(result), 2)
  expect_true(is.list(result[[1]]))
  expect_true(is.list(result[[2]]))
  expect_equal(names(result[[1]]), c("role", "content"))
  expect_equal(names(result[[2]]), c("role", "content"))
  expect_equal(class(result[[1]]$role), "character")
  expect_equal(class(result[[1]]$content), "character")
  expect_equal(class(result[[2]]$role), "character")
  expect_equal(class(result[[2]]$content), "character")
})

test_that("build_prompt integrates correctly with JSON serialization", {
  # Test that output can be serialized to JSON
  result <- build_prompt("System prompt", "User prompt")
  
  # Should serialize without error
  json_output <- jsonlite::toJSON(result, auto_unbox = TRUE)
  expect_type(json_output, "character")
  
  # Should deserialize back correctly (use simplifyVector = FALSE to preserve structure)
  deserialized <- jsonlite::fromJSON(as.character(json_output), simplifyVector = FALSE)
  expect_equal(deserialized[[1]]$role, "system")
  expect_equal(deserialized[[1]]$content, "System prompt")
  expect_equal(deserialized[[2]]$role, "user")
  expect_equal(deserialized[[2]]$content, "User prompt")
})

test_that("build_prompt handles R-specific edge cases", {
  # Infinity and NaN in strings (valid strings)
  result <- build_prompt("Inf", "NaN")
  expect_equal(result[[1]]$content, "Inf")
  expect_equal(result[[2]]$content, "NaN")
  
  # String representations of NA (valid string, not NA value)
  result <- build_prompt("NA", "NA")
  expect_equal(result[[1]]$content, "NA")
  expect_equal(result[[2]]$content, "NA")
  
  # Backslashes (common in Windows paths)
  windows_path <- "C:\\Users\\Name\\Documents"
  result <- build_prompt(windows_path, windows_path)
  expect_equal(result[[1]]$content, windows_path)
  expect_equal(result[[2]]$content, windows_path)
  
  # R code as strings
  r_code <- "df %>% filter(x > 10) %>% mutate(y = x^2)"
  result <- build_prompt(r_code, r_code)
  expect_equal(result[[1]]$content, r_code)
  expect_equal(result[[2]]$content, r_code)
})