test_that("populate_from_basic_detection works", {
  # Create mock basic result
  basic_result <- list(
    ipv_detected = TRUE,
    confidence = 0.85,
    indicators = c("domestic violence", "controlling behavior"),
    rationale = "Clear IPV indicators"
  )

  # Create forensic result
  forensic_result <- ipv_forensic_result$new("integration_test_001")

  # Populate from basic result
  updated_result <- populate_from_basic_detection(
    forensic_result,
    basic_result,
    "LE"
  )

  # Check that death classification was updated
  expect_equal(updated_result$death_classification$primary, "ipv_detected")
  expect_equal(updated_result$death_classification$confidence, 0.85)
  expect_equal(updated_result$death_classification$rationale,
               "Basic LLM analysis")

  # Check that evidence was added
  expect_equal(length(updated_result$evidence_matrix$items), 2)
  evidence_items <- sapply(
    updated_result$evidence_matrix$items,
    function(x) x$item
  )
  expect_true("domestic violence" %in% evidence_items)
  expect_true("controlling behavior" %in% evidence_items)

  # Check evidence properties
  first_evidence <- updated_result$evidence_matrix$items[[1]]
  expect_equal(first_evidence$type, "behavioral_evidence")
  expect_equal(first_evidence$weight, 0.6)
  expect_equal(first_evidence$source, "LE_narrative")
  expect_equal(first_evidence$reliability, 0.7)
})

test_that("populate_from_basic_detection handles NA values", {
  basic_result <- list(
    ipv_detected = NA,
    confidence = NA,
    indicators = NULL,
    rationale = NULL
  )

  forensic_result <- ipv_forensic_result$new("integration_test_002")
  updated_result <- populate_from_basic_detection(
    forensic_result,
    basic_result,
    "CME"
  )

  # Should not update death classification with NA
  expect_null(updated_result$death_classification$primary)

  # Should not add evidence for NULL indicators
  expect_equal(length(updated_result$evidence_matrix$items), 0)
})

test_that("populate_from_batch_results works", {
  # Create mock batch result row
  basic_row <- tibble::tibble(
    IncidentID = "batch_test_001",
    ipv_detected = TRUE,
    confidence = 0.75,
    le_ipv = TRUE,
    cme_ipv = FALSE,
    le_confidence = 0.8,
    cme_confidence = 0.4
  )

  data_row <- tibble::tibble(
    IncidentID = "batch_test_001",
    NarrativeLE = "LE narrative text",
    NarrativeCME = "CME narrative text"
  )

  forensic_result <- ipv_forensic_result$new("batch_test_001")
  updated_result <- populate_from_batch_results(
    forensic_result,
    basic_row,
    data_row
  )

  # Check death classification
  expect_equal(updated_result$death_classification$primary, "ipv_detected")
  expect_equal(updated_result$death_classification$confidence, 0.75)
  expect_equal(updated_result$death_classification$rationale,
               "Reconciled LE/CME analysis")

  # Check directionality (should be "behavioral_evidence_primary" since LE=TRUE, CME=FALSE)
  expect_equal(
    updated_result$directionality$primary_direction,
    "behavioral_evidence_primary"
  )
})

test_that("analyze_directionality_patterns works", {
  forensic_result <- ipv_forensic_result$new("directionality_test")

  # Test narrative with perpetrator indicators
  narrative <- "The suspect struck the victim multiple times. He was the perpetrator."
  updated_result <- analyze_directionality_patterns(
    forensic_result,
    narrative,
    "LE"
  )

  expect_equal(
    updated_result$directionality$primary_direction,
    "perpetrator_to_victim"
  )
  expect_true(updated_result$directionality$confidence > 0.3)

  # Test narrative with victim indicators
  narrative2 <- "The deceased had multiple defensive wounds. Victim showed injuries."
  updated_result2 <- analyze_directionality_patterns(
    ipv_forensic_result$new("directionality_test_2"),
    narrative2,
    "CME"
  )

  expect_equal(
    updated_result2$directionality$primary_direction,
    "victim_focused_evidence"
  )
})

test_that("analyze_suicide_intent works", {
  forensic_result <- ipv_forensic_result$new("suicide_test")

  # Test narrative with clear suicide intent
  narrative <- "Suicide note found. Previous suicide attempts documented. Gun used."
  updated_result <- analyze_suicide_intent(forensic_result, narrative, "LE")

  expect_equal(
    updated_result$suicide_analysis$intent_classification,
    "clear_intent"
  )
  expect_equal(
    updated_result$suicide_analysis$weapon_vs_escape,
    "weapon_against_partner"
  )
  expect_true(updated_result$suicide_analysis$confidence > 0)

  # Test narrative with escape indicators
  narrative2 <- "Domestic violence history. Overdose with pills. Threatened by partner."
  updated_result2 <- analyze_suicide_intent(
    ipv_forensic_result$new("suicide_test_2"),
    narrative2,
    "CME"
  )

  expect_equal(
    updated_result2$suicide_analysis$weapon_vs_escape,
    "escape_from_violence"
  )
})

test_that("analyze_temporal_patterns works", {
  forensic_result <- ipv_forensic_result$new("temporal_test")

  # Test narrative with escalation indicators
  narrative <- "Escalating violence. Recent separation. Restraining order filed recently."
  updated_result <- analyze_temporal_patterns(forensic_result, narrative)

  expect_equal(
    updated_result$temporal_patterns$pattern_type,
    "acute_escalation"
  )
  expect_true(length(updated_result$temporal_patterns$escalation_indicators) > 0)
  expect_true(updated_result$temporal_patterns$confidence > 0)

  # Test narrative with chronic pattern
  narrative2 <- "History of violence. Previous incidents documented. Pattern of abuse."
  updated_result2 <- analyze_temporal_patterns(
    ipv_forensic_result$new("temporal_test_2"),
    narrative2
  )

  expect_equal(
    updated_result2$temporal_patterns$pattern_type,
    "chronic_pattern"
  )
})

test_that("analyze_evidence_hierarchy works", {
  forensic_result <- ipv_forensic_result$new("evidence_test")

  # Test narrative with different types of evidence
  narrative <- paste(
    "Multiple bruises and fractures found.",
    "History of domestic violence and controlling behavior.",
    "Witness statements and police reports available."
  )

  updated_result <- analyze_evidence_hierarchy(
    forensic_result,
    narrative,
    "CME"
  )

  # Check that evidence was added
  expect_true(length(updated_result$evidence_matrix$items) > 0)

  # Check that different evidence types were identified
  evidence_types <- sapply(
    updated_result$evidence_matrix$items,
    function(x) x$type
  )

  expect_true("physical_evidence" %in% evidence_types)
  expect_true("behavioral_evidence" %in% evidence_types)
  expect_true("contextual_evidence" %in% evidence_types)

  # Check that weights are appropriate (physical should be highest)
  physical_items <- updated_result$evidence_matrix$items[
    evidence_types == "physical_evidence"
  ]
  if (length(physical_items) > 0) {
    expect_equal(physical_items[[1]]$weight, 0.9)
  }
})

test_that("analyze_narrative_consistency works", {
  forensic_result <- ipv_forensic_result$new("consistency_test")

  # Test with both narratives available and some common terms
  data_row <- tibble::tibble(
    IncidentID = "consistency_test",
    NarrativeLE = "domestic violence incident with gun",
    NarrativeCME = "gunshot wound from domestic violence"
  )

  updated_result <- analyze_narrative_consistency(forensic_result, data_row)

  # Should have higher data completeness when both narratives available
  expect_true(updated_result$quality_metrics$data_completeness >= 0.4)
  expect_true(updated_result$quality_metrics$source_reliability > 0)

  # Test with only one narrative
  data_row_partial <- tibble::tibble(
    IncidentID = "consistency_test",
    NarrativeLE = "domestic violence incident",
    NarrativeCME = NA
  )

  updated_result2 <- analyze_narrative_consistency(
    ipv_forensic_result$new("consistency_test_2"),
    data_row_partial
  )

  expect_equal(updated_result2$quality_metrics$data_completeness, 0.4)
})

test_that("calculate_data_completeness works", {
  forensic_result <- ipv_forensic_result$new("completeness_test")

  # Empty result should have low completeness
  initial_score <- calculate_data_completeness(forensic_result)
  expect_true(initial_score < 0.5)

  # Add components and check score increases
  forensic_result$update_death_classification("ipv_homicide", 0.8)
  score1 <- calculate_data_completeness(forensic_result)
  expect_true(score1 > initial_score)

  forensic_result$update_directionality(primary_direction = "perpetrator_to_victim", confidence = 0.7)
  score2 <- calculate_data_completeness(forensic_result)
  expect_true(score2 > score1)

  forensic_result$add_evidence("physical", "injury", 0.9)
  final_score <- calculate_data_completeness(forensic_result)
  expect_true(final_score > score2)
  expect_true(final_score <= 1.0)
})

test_that("perform_advanced_analysis integration works", {
  forensic_result <- ipv_forensic_result$new("advanced_test")
  
  narrative <- paste(
    "The perpetrator struck the victim causing multiple injuries.",
    "Suicide note found indicating domestic violence as reason.",
    "Escalating pattern of violence over recent months.",
    "Witness statements corroborate history of abuse."
  )

  updated_result <- perform_advanced_analysis(
    forensic_result,
    narrative,
    "LE",
    NULL  # config not needed for pattern analysis
  )

  # Check that all analysis types were performed
  expect_true(!is.null(updated_result$directionality$primary_direction))
  expect_true(!is.null(updated_result$suicide_analysis$intent_classification))
  expect_true(!is.null(updated_result$temporal_patterns$pattern_type))
  expect_true(length(updated_result$evidence_matrix$items) > 0)
  expect_true(updated_result$quality_metrics$data_completeness > 0)
})

test_that("Error handling in integration functions", {
  # Test with NULL inputs
  forensic_result <- ipv_forensic_result$new("error_test")
  
  # Should handle NULL narrative gracefully
  result <- analyze_directionality_patterns(forensic_result, NULL, "LE")
  expect_s3_class(result, "IPVForensicResult")
  
  result2 <- analyze_temporal_patterns(forensic_result, "")
  expect_s3_class(result2, "IPVForensicResult")
  
  # Test with invalid narrative type
  result3 <- analyze_evidence_hierarchy(forensic_result, "test", "INVALID")
  expect_s3_class(result3, "IPVForensicResult")
})