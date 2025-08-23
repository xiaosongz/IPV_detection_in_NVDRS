test_that("IPV Forensic Result creation works", {
  # Create basic forensic result
  result <- ipv_forensic_result$new(
    incident_id = "test_001",
    le_narrative = "Test LE narrative",
    cme_narrative = "Test CME narrative"
  )

  expect_s3_class(result, "IPVForensicResult")
  expect_equal(result$incident_id, "test_001")
  expect_equal(result$analysis_version, "1.0.0")
  expect_equal(result$source_narratives$le, "Test LE narrative")
  expect_equal(result$source_narratives$cme, "Test CME narrative")

  # Check initialization of core structures
  expect_true(is.list(result$death_classification))
  expect_true(is.list(result$directionality))
  expect_true(is.list(result$evidence_matrix))
  expect_true(is.list(result$quality_metrics))
})

test_that("Death classification updates work", {
  result <- ipv_forensic_result$new("test_002")

  result$update_death_classification(
    classification = "ipv_homicide",
    confidence = 0.85,
    evidence = list("weapon found", "history of violence"),
    rationale = "Clear evidence of IPV"
  )

  expect_equal(result$death_classification$primary, "ipv_homicide")
  expect_equal(result$death_classification$confidence, 0.85)
  expect_equal(length(result$death_classification$supporting_evidence), 2)
  expect_equal(result$death_classification$rationale, "Clear evidence of IPV")
  expect_true(!is.null(result$death_classification$last_updated))
})

test_that("Directionality assessment works", {
  result <- ipv_forensic_result$new("test_003")

  result$update_directionality(
    perpetrator_evidence = list("threatening behavior", "weapon possession"),
    victim_evidence = list("defensive wounds", "fear expression"),
    bidirectional_score = 0.2,
    primary_direction = "perpetrator_to_victim",
    confidence = 0.7
  )

  expect_equal(result$directionality$primary_direction, "perpetrator_to_victim")
  expect_equal(result$directionality$bidirectional_score, 0.2)
  expect_equal(result$directionality$confidence, 0.7)
  expect_equal(length(result$directionality$perpetrator_indicators), 2)
  expect_equal(length(result$directionality$victim_indicators), 2)
})

test_that("Suicide analysis works", {
  result <- ipv_forensic_result$new("test_004")

  result$update_suicide_analysis(
    intent_classification = "clear_intent",
    weapon_vs_escape = "escape_from_violence",
    precipitating_factors = list("recent separation", "custody dispute"),
    confidence = 0.6
  )

  expect_equal(result$suicide_analysis$intent_classification, "clear_intent")
  expect_equal(result$suicide_analysis$weapon_vs_escape, "escape_from_violence")
  expect_equal(length(result$suicide_analysis$precipitating_factors), 2)
  expect_equal(result$suicide_analysis$confidence, 0.6)
})

test_that("Evidence matrix works", {
  result <- ipv_forensic_result$new("test_005")

  # Add multiple evidence items
  result$add_evidence(
    evidence_type = "physical_evidence",
    evidence_item = "bruising pattern",
    weight = 0.9,
    source = "CME_narrative",
    reliability = 0.8
  )

  result$add_evidence(
    evidence_type = "behavioral_evidence",
    evidence_item = "controlling behavior",
    weight = 0.7,
    source = "LE_narrative",
    reliability = 0.6
  )

  result$add_evidence(
    evidence_type = "contextual_evidence",
    evidence_item = "witness statement",
    weight = 0.5,
    source = "police_report",
    reliability = 0.7
  )

  expect_equal(length(result$evidence_matrix$items), 3)
  expect_equal(result$evidence_matrix$summary$total_items, 3)
  expect_equal(result$evidence_matrix$summary$high_weight_items, 1)
  expect_equal(result$evidence_matrix$summary$type_diversity, 3)
  expect_true(result$evidence_matrix$summary$average_weight > 0)
})

test_that("Temporal patterns work", {
  result <- ipv_forensic_result$new("test_006")

  result$update_temporal_patterns(
    escalation_indicators = list("increasing frequency", "recent threats"),
    timeline_events = list("initial_incident", "escalation", "death"),
    pattern_type = "acute_escalation",
    confidence = 0.8
  )

  expect_equal(result$temporal_patterns$pattern_type, "acute_escalation")
  expect_equal(length(result$temporal_patterns$escalation_indicators), 2)
  expect_equal(length(result$temporal_patterns$timeline_events), 3)
  expect_equal(result$temporal_patterns$confidence, 0.8)
})

test_that("Summary generation works", {
  result <- ipv_forensic_result$new("test_007")

  result$update_death_classification("ipv_homicide", 0.85)
  result$update_directionality(primary_direction = "perpetrator_to_victim", confidence = 0.7)
  result$add_evidence("physical_evidence", "injury pattern", 0.9)

  summary <- result$get_summary()

  expect_equal(summary$incident_id, "test_007")
  expect_equal(summary$death_classification$type, "ipv_homicide")
  expect_equal(summary$death_classification$confidence, 0.85)
  expect_equal(summary$directionality$primary_direction, "perpetrator_to_victim")
  expect_equal(summary$directionality$confidence, 0.7)
  expect_equal(summary$evidence_summary$total_items, 1)
})

test_that("Tibble conversion works", {
  result <- ipv_forensic_result$new("test_008")

  result$update_death_classification("ipv_suicide", 0.6)
  result$update_suicide_analysis("clear_intent", "escape_from_violence", confidence = 0.7)
  result$add_evidence("behavioral_evidence", "domestic violence", 0.8)
  result$update_temporal_patterns(pattern_type = "chronic_pattern", confidence = 0.5)

  tibble_data <- result$to_tibble()

  expect_s3_class(tibble_data, "tbl_df")
  expect_equal(tibble_data$incident_id, "test_008")
  expect_equal(tibble_data$death_type, "ipv_suicide")
  expect_equal(tibble_data$suicide_intent, "clear_intent")
  expect_equal(tibble_data$suicide_method_type, "escape_from_violence")
  expect_equal(tibble_data$total_evidence_items, 1)
  expect_equal(tibble_data$temporal_pattern_type, "chronic_pattern")
})

test_that("Validation works", {
  # Empty result should have validation issues
  result <- ipv_forensic_result$new("test_009")
  validation <- result$validate_analysis()

  expect_false(validation$is_valid)
  expect_true(length(validation$issues) > 0)
  expect_true("Missing death classification" %in% validation$issues)
  expect_true("No evidence items recorded" %in% validation$issues)

  # Complete result should be valid  
  result <- ipv_forensic_result$new("test_009_complete", 
                                    le_narrative = "Test narrative",
                                    cme_narrative = "Test narrative")
  result$update_death_classification("ipv_homicide", 0.8)
  result$update_directionality(primary_direction = "perpetrator_to_victim", confidence = 0.7)
  result$add_evidence("physical_evidence", "injury", 0.9)

  validation <- result$validate_analysis()

  expect_true(validation$is_valid)
  expect_equal(length(validation$issues), 0)
  expect_true(validation$completeness_score > 0.5)
})

test_that("Forensic collection creation works", {
  # Create test data
  test_data <- tibble::tibble(
    IncidentID = c("001", "002", "003"),
    NarrativeLE = c("LE narrative 1", "LE narrative 2", "LE narrative 3"),
    NarrativeCME = c("CME narrative 1", NA, "CME narrative 3")
  )

  collection <- create_forensic_collection(
    incident_ids = c("001", "002", "003"),
    data_source = test_data
  )

  expect_s3_class(collection, "IPVForensicCollection")
  expect_equal(collection$metadata$total_incidents, 3)
  expect_equal(collection$metadata$completed_analyses, 3)

  # Test collection methods
  analysis <- collection$get_analysis("001")
  expect_s3_class(analysis, "IPVForensicResult")
  expect_equal(analysis$incident_id, "001")

  summary_tibble <- collection$get_summary_tibble()
  expect_s3_class(summary_tibble, "tbl_df")
  expect_equal(nrow(summary_tibble), 3)
})

test_that("Collection validation works", {
  collection <- create_forensic_collection(c("001", "002"))

  # Add one complete and one incomplete analysis
  complete_result <- ipv_forensic_result$new("001")
  complete_result$update_death_classification("ipv_homicide", 0.8)
  complete_result$update_directionality(primary_direction = "perpetrator_to_victim", confidence = 0.7)
  complete_result$add_evidence("physical", "injury", 0.9)

  incomplete_result <- ipv_forensic_result$new("002")

  collection$add_analysis(complete_result)
  collection$add_analysis(incomplete_result)

  validation <- collection$validate_collection()

  expect_equal(validation$total_incidents, 2)
  expect_equal(validation$valid_incidents, 1)
  expect_true(validation$average_completeness > 0)
  expect_true(validation$average_completeness < 1)
})

test_that("Collection export works", {
  test_data <- tibble::tibble(
    IncidentID = c("001", "002"),
    NarrativeLE = c("LE text", "LE text 2"),
    NarrativeCME = c("CME text", "CME text 2")
  )

  collection <- create_forensic_collection(c("001", "002"), test_data)

  export_data <- collection$export_for_analysis()

  expect_true(is.list(export_data))
  expect_true("data" %in% names(export_data))
  expect_true("metadata" %in% names(export_data))
  expect_true("validation" %in% names(export_data))

  expect_s3_class(export_data$data, "tbl_df")
  expect_equal(nrow(export_data$data), 2)
})

test_that("Print methods work", {
  result <- ipv_forensic_result$new("print_test")
  result$update_death_classification("ipv_homicide", 0.8)

  # Test that print doesn't error
  expect_output(print(result), "IPV Forensic Analysis Result")
  expect_output(print(result), "print_test")

  collection <- create_forensic_collection("collection_test")
  expect_output(print(collection), "IPV Forensic Analysis Collection")
  expect_output(print(collection), "Total Incidents: 1")
})

test_that("Error handling works", {
  # Test with empty incident IDs
  expect_error(
    create_forensic_collection(c()),
    "No incident IDs provided"
  )

  # Test with invalid data
  result <- ipv_forensic_result$new("error_test")
  expect_error(
    result$update_death_classification(),
    "argument.*missing"
  )
})