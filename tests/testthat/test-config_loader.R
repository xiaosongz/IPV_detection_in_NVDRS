# Tests for config_loader.R
# Configuration loading and validation

test_that("load_experiment_config loads valid minimal config", {
  config_path <- fixture_path("configs", "valid_minimal.yaml")

  config <- load_experiment_config(config_path)

  # Use the actual validate_config function from the codebase
  expect_true(validate_config(config))
  expect_equal(config$experiment$name, "test_minimal")
  expect_equal(config$model$name, "test-model")
  expect_equal(config$model$temperature, 0.0)
})

test_that("load_experiment_config loads complete config", {
  config_path <- fixture_path("configs", "valid_complete.yaml")

  config <- load_experiment_config(config_path)

  expect_true(validate_config(config))
  expect_equal(config$experiment$name, "test_complete")
  expect_equal(config$run$seed, 42)
  expect_true("run" %in% names(config))
})

test_that("load_experiment_config expands environment variables", {
  withr::local_envvar(c(TEST_VAR = "test_value"))

  # Create temp config with env var
  with_temp_dir({
    config_file <- "test_env.yaml"
    writeLines(c(
      "experiment:",
      "  name: '${TEST_VAR}'",
      "model:",
      "  name: 'model'",
      "  temperature: 0.0",
      "prompt:",
      "  version: 'test-v1'",
      "  system_prompt: 'test'",
      "  user_template: 'test <<TEXT>>'",
      "data:",
      "  file: 'tests/fixtures/data/test_data.csv'",
      "run:",
      "  seed: 123"
    ), config_file)

    config <- load_experiment_config(config_file)

    expect_equal(config$experiment$name, "test_value")
  })
})

test_that("load_experiment_config errors on missing file", {
  expect_error(
    load_experiment_config("/nonexistent/config.yaml"),
    "not found|does not exist"
  )
})

test_that("validate_config accepts valid configuration", {
  config <- mock_config()

  result <- validate_config(config)

  expect_true(result)
})

test_that("validate_config rejects missing model_name", {
  config <- mock_config()
  config$model$name <- NULL

  expect_error(
    validate_config(config),
    "model.name"
  )
})

test_that("validate_config rejects invalid temperature", {
  config <- mock_config()
  config$model$temperature <- 5.0 # Too high

  expect_error(
    validate_config(config),
    "temperature"
  )
})

test_that("validate_config rejects missing system prompt", {
  config <- mock_config()
  config$prompt$system_prompt <- NULL

  expect_error(
    validate_config(config),
    "system.*prompt"
  )
})

test_that("validate_config rejects invalid user_template", {
  config <- mock_config()
  config$prompt$user_template <- "" # Empty template

  expect_error(
    validate_config(config),
    "user_template"
  )
})

test_that("substitute_template replaces placeholders", {
  template <- "Analyze this: <<TEXT>>"
  text <- "Sample narrative"

  result <- substitute_template(template, text)

  expect_equal(result, "Analyze this: Sample narrative")
  expect_false(grepl("<<TEXT>>", result))
})

test_that("substitute_template handles multiple occurrences", {
  template <- "Start: <<TEXT>> End: <<TEXT>>"
  text <- "TEST"

  result <- substitute_template(template, text)

  expect_equal(result, "Start: TEST End: TEST")
})

test_that("substitute_template handles empty text", {
  template <- "Analyze: <<TEXT>>"
  text <- ""

  result <- substitute_template(template, text)

  expect_equal(result, "Analyze: ")
})

test_that("expand_env_vars expands environment variables", {
  withr::local_envvar(c(TEST_VAR = "expanded"))

  text <- "Value is ${TEST_VAR}"

  result <- expand_env_vars(text)

  expect_equal(result, "Value is expanded")
})

test_that("expand_env_vars handles missing variables", {
  text <- "Value is ${NONEXISTENT_VAR}"

  result <- expand_env_vars(text)

  # Should either leave as-is or replace with empty
  expect_true(result == text || result == "Value is ")
})

test_that("expand_env_vars_recursive works on lists", {
  withr::local_envvar(c(TEST_VAR = "value"))

  obj <- list(
    field1 = "${TEST_VAR}",
    field2 = "no_var",
    nested = list(
      field3 = "${TEST_VAR}"
    )
  )

  result <- expand_env_vars_recursive(obj)

  expect_equal(result$field1, "value")
  expect_equal(result$field2, "no_var")
  expect_equal(result$nested$field3, "value")
})
