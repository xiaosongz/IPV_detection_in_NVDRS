test_that("unified prompt template works for both LE and CME", {
  # Load config with unified template
  config <- list(
    prompts = list(
      unified_template = "Analyze this {narrative_type} narrative for IPV. Narrative: {narrative}"
    )
  )
  
  # Test LE narrative
  le_prompt <- build_prompt(
    narrative = "Domestic violence incident",
    type = "LE",
    config = config
  )
  expect_true(grepl("law enforcement", le_prompt))
  expect_true(grepl("Domestic violence incident", le_prompt))
  expect_false(grepl("\\{narrative_type\\}", le_prompt))  # No unreplaced placeholders
  expect_false(grepl("\\{narrative\\}", le_prompt))
  
  # Test CME narrative
  cme_prompt <- build_prompt(
    narrative = "Multiple injuries observed",
    type = "CME",
    config = config
  )
  expect_true(grepl("medical examiner", cme_prompt))
  expect_true(grepl("Multiple injuries observed", cme_prompt))
  expect_false(grepl("\\{narrative_type\\}", cme_prompt))
  expect_false(grepl("\\{narrative\\}", cme_prompt))
})

test_that("build_prompt handles backward compatibility", {
  # Old style config with separate templates
  old_config <- list(
    prompts = list(
      le_template = "LE: {narrative}",
      cme_template = "CME: {narrative}"
    )
  )
  
  # Should still work with old templates if no unified template
  le_prompt <- build_prompt("Test LE", "LE", old_config)
  expect_equal(le_prompt, "LE: Test LE")
  
  cme_prompt <- build_prompt("Test CME", "CME", old_config)
  expect_equal(cme_prompt, "CME: Test CME")
})

test_that("build_prompt validates narrative type", {
  config <- list(
    prompts = list(
      unified_template = "Test: {narrative_type} - {narrative}"
    )
  )
  
  expect_error(
    build_prompt("Test", "INVALID", config),
    "Invalid narrative type"
  )
})

test_that("unified template from actual settings.yml works", {
  skip_if_not(file.exists("../../inst/settings.yml"))
  
  # Load actual config
  config <- load_config("../../inst/settings.yml")
  
  # Test with real config
  le_prompt <- build_prompt(
    narrative = "The victim was shot by her ex-boyfriend",
    type = "LE",
    config = config
  )
  
  # Check it contains expected elements
  expect_true(grepl("law enforcement", le_prompt))
  expect_true(grepl("ex-boyfriend", le_prompt))
  expect_true(grepl("IPV indicators", le_prompt, ignore.case = TRUE))
  
  # Test CME
  cme_prompt <- build_prompt(
    narrative = "Strangulation marks observed",
    type = "CME",
    config = config
  )
  
  expect_true(grepl("medical examiner", cme_prompt))
  expect_true(grepl("Strangulation marks", cme_prompt))
})