# Tests for db_config.R
# Database configuration management

test_that("get_experiments_db_path returns default path", {
  # Clear environment variable
  withr::local_envvar(c(IPV_DB_PATH = NA_character_))

  path <- get_experiments_db_path()

  expect_type(path, "character")
  expect_true(grepl("experiments\\.db$", path))
})

test_that("get_experiments_db_path respects environment variable", {
  custom_path <- "/tmp/custom_experiments.db"
  withr::local_envvar(c(EXPERIMENTS_DB = custom_path))

  path <- get_experiments_db_path()

  expect_equal(path, custom_path)
})

test_that("get_test_db_path returns test database path", {
  path <- get_test_db_path()

  expect_type(path, "character")
  expect_true(grepl("test.*\\.db$", path))
})

test_that("get_all_db_paths returns both paths", {
  paths <- get_all_db_paths()

  expect_type(paths, "list")
  expect_named(paths, c("experiments", "test"))
  expect_type(paths$experiments, "character")
  expect_type(paths$test, "character")
})

test_that("validate_db_path accepts valid paths", {
  with_temp_dir({
    # Create a temp DB file
    temp_db <- file.path(getwd(), "test.db")
    file.create(temp_db)

    result <- validate_db_path(temp_db)

    expect_true(result)
  })
})

test_that("validate_db_path creates missing parent directories when requested", {
  with_temp_dir({
    new_db <- file.path(getwd(), "new_dir", "test.db")

    result <- validate_db_path(new_db, create_if_missing = TRUE)

    expect_true(dir.exists(dirname(new_db)))
    expect_true(result)
  })
})

test_that("validate_db_path errors on missing path without create flag", {
  expect_error(
    validate_db_path("/nonexistent/path/test.db", create_if_missing = FALSE),
    "does not exist"
  )
})

test_that("print_db_config displays configuration", {
  output <- capture.output(print_db_config())

  expect_true(any(grepl("Database Configuration", output)))
  expect_true(any(grepl("Experiments DB", output)))
})
