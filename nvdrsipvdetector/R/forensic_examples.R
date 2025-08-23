#' Example Functions for IPV Forensic Analysis
#'
#' @description
#' Demonstration functions showing how to use the advanced IPV forensic
#' analysis data structure for comprehensive case analysis.
#'
#' @name forensic_examples
#' @keywords internal
NULL

#' Create Example Forensic Analysis
#'
#' @description
#' Creates a comprehensive example of IPV forensic analysis to demonstrate
#' the full capabilities of the data structure.
#'
#' @param incident_id Optional incident ID (generates one if NULL)
#' @return IPVForensicResult with complete example analysis
#' @export
#' @examples
#' # Create comprehensive example analysis
#' example <- create_example_forensic_analysis("EXAMPLE_2024_001")
#'
#' # View summary
#' summary <- example$get_summary()
#' print(summary)
#'
#' # Export to tibble for analysis
#' data <- example$to_tibble()
#' print(data)
#'
#' # Validate analysis completeness
#' validation <- example$validate_analysis()
#' print(validation)
create_example_forensic_analysis <- function(incident_id = NULL) {

  if (is.null(incident_id)) {
    incident_id <- paste0("EXAMPLE_", format(Sys.time(), "%Y%m%d_%H%M%S"))
  }

  # Create forensic result with example narratives
  le_narrative <- paste(
    "Officers responded to a domestic disturbance call at 1430 Main St.",
    "Upon arrival, found female victim, age 32, deceased from apparent",
    "gunshot wound to the chest. Male suspect, age 35, also deceased",
    "from self-inflicted gunshot wound to head. Neighbors reported",
    "history of domestic violence between the couple. Recent restraining",
    "order filed by victim against suspect. Weapon belonged to suspect.",
    "Evidence of escalating threats over past month. Witness statements",
    "indicate victim was attempting to leave relationship."
  )

  cme_narrative <- paste(
    "Autopsy findings: 32-year-old female with single gunshot wound",
    "to chest, through-and-through injury causing massive cardiac damage.",
    "No defensive wounds noted. Toxicology negative for alcohol/drugs.",
    "Male decedent, age 35, contact gunshot wound to right temporal area,",
    "consistent with self-inflicted injury. GSR positive on right hand.",
    "Both injuries consistent with .38 caliber revolver found at scene.",
    "Female victim had evidence of prior blunt force trauma in various",
    "stages of healing, suggesting pattern of abuse."
  )

  result <- ipv_forensic_result$new(
    incident_id = incident_id,
    le_narrative = le_narrative,
    cme_narrative = cme_narrative
  )

  # Update death classification
  result$update_death_classification(
    classification = "ipv_homicide_suicide",
    confidence = 0.92,
    evidence = list(
      "gunshot_wound_pattern",
      "domestic_violence_history",
      "restraining_order",
      "weapon_ownership",
      "witness_statements"
    ),
    rationale = paste(
      "Clear evidence of intimate partner homicide followed by suicide.",
      "Pattern consistent with separation-precipitated IPV escalation.",
      "Physical evidence, witness testimony, and legal documentation",
      "all support IPV classification with high confidence."
    )
  )

  # Update directionality assessment
  result$update_directionality(
    perpetrator_evidence = list(
      "weapon_ownership",
      "history_of_threats",
      "restraining_order_violation",
      "escalating_behavior",
      "control_patterns"
    ),
    victim_evidence = list(
      "defensive_posture",
      "help_seeking_behavior",
      "restraining_order_filing",
      "separation_attempt",
      "fear_expression"
    ),
    bidirectional_score = 0.1,
    primary_direction = "perpetrator_to_victim",
    confidence = 0.88
  )

  # Update perpetrator profile
  result$perpetrator_profile <- list(
    role = "perpetrator",
    demographic_indicators = list(
      age = 35,
      gender = "male",
      relationship = "intimate_partner"
    ),
    behavioral_indicators = list(
      "controlling_behavior",
      "threatening_communications",
      "violation_of_legal_orders",
      "escalating_aggression",
      "separation_violence_risk"
    ),
    weapon_access = list(
      "legal_firearm_ownership",
      "handgun_available",
      "familiarity_with_weapon"
    ),
    prior_violence_history = list(
      "domestic_violence_calls",
      "neighbor_reports",
      "victim_statements",
      "physical_evidence_prior_abuse"
    ),
    risk_factors = list(
      "separation_trigger",
      "legal_intervention",
      "loss_of_control",
      "weapon_access",
      "escalation_pattern"
    )
  )

  # Update victim profile
  result$victim_profile <- list(
    role = "victim",
    demographic_indicators = list(
      age = 32,
      gender = "female",
      relationship = "intimate_partner"
    ),
    behavioral_indicators = list(
      "help_seeking_behavior",
      "legal_protection_seeking",
      "separation_attempt",
      "fear_expression",
      "safety_planning"
    ),
    injury_patterns = list(
      "fatal_gunshot_chest",
      "prior_blunt_force_trauma",
      "various_healing_stages",
      "pattern_consistent_abuse"
    ),
    protective_factors = list(
      "legal_system_engagement",
      "community_support",
      "separation_planning"
    ),
    risk_factors = list(
      "separation_period",
      "prior_violence_exposure",
      "perpetrator_weapon_access",
      "escalating_threats"
    )
  )

  # Update suicide analysis
  result$update_suicide_analysis(
    intent_classification = "clear_intent",
    weapon_vs_escape = "weapon_against_partner",
    precipitating_factors = list(
      "victim_separation_attempt",
      "restraining_order_filing",
      "loss_of_control",
      "legal_consequences",
      "relationship_termination"
    ),
    confidence = 0.85
  )

  # Add comprehensive evidence
  evidence_items <- list(
    list(
      type = "physical_evidence",
      item = "gunshot_wound_patterns",
      weight = 0.95,
      source = "autopsy_findings",
      reliability = 0.9
    ),
    list(
      type = "physical_evidence",
      item = "weapon_ballistics_match",
      weight = 0.95,
      source = "forensic_analysis",
      reliability = 0.95
    ),
    list(
      type = "physical_evidence",
      item = "GSR_evidence",
      weight = 0.9,
      source = "forensic_testing",
      reliability = 0.9
    ),
    list(
      type = "physical_evidence",
      item = "prior_injury_patterns",
      weight = 0.85,
      source = "autopsy_findings",
      reliability = 0.8
    ),
    list(
      type = "behavioral_evidence",
      item = "domestic_violence_history",
      weight = 0.8,
      source = "witness_statements",
      reliability = 0.75
    ),
    list(
      type = "behavioral_evidence",
      item = "escalating_threats",
      weight = 0.75,
      source = "victim_statements",
      reliability = 0.7
    ),
    list(
      type = "contextual_evidence",
      item = "restraining_order",
      weight = 0.8,
      source = "court_records",
      reliability = 0.9
    ),
    list(
      type = "contextual_evidence",
      item = "police_calls_history",
      weight = 0.7,
      source = "police_records",
      reliability = 0.8
    ),
    list(
      type = "contextual_evidence",
      item = "witness_testimony",
      weight = 0.65,
      source = "neighbor_statements",
      reliability = 0.6
    ),
    list(
      type = "circumstantial_evidence",
      item = "separation_timing",
      weight = 0.4,
      source = "timeline_analysis",
      reliability = 0.5
    )
  )

  # Add all evidence items
  for (evidence in evidence_items) {
    result$add_evidence(
      evidence_type = evidence$type,
      evidence_item = evidence$item,
      weight = evidence$weight,
      source = evidence$source,
      reliability = evidence$reliability
    )
  }

  # Update temporal patterns
  result$update_temporal_patterns(
    escalation_indicators = list(
      "increasing_threat_frequency",
      "restraining_order_filing",
      "separation_attempt",
      "recent_legal_action",
      "weapon_access_threat"
    ),
    timeline_events = list(
      list(
        event = "relationship_onset",
        timeframe = "3_years_prior",
        description = "Beginning of intimate relationship"
      ),
      list(
        event = "first_violence_incident",
        timeframe = "2_years_prior",
        description = "First documented domestic violence incident"
      ),
      list(
        event = "escalation_period",
        timeframe = "6_months_prior",
        description = "Increasing frequency and severity of abuse"
      ),
      list(
        event = "separation_decision",
        timeframe = "1_month_prior",
        description = "Victim decides to leave relationship"
      ),
      list(
        event = "restraining_order",
        timeframe = "2_weeks_prior",
        description = "Victim files for restraining order"
      ),
      list(
        event = "final_incident",
        timeframe = "incident_date",
        description = "Homicide-suicide event"
      )
    ),
    pattern_type = "acute_escalation",
    confidence = 0.9
  )

  # Update quality metrics
  result$quality_metrics <- list(
    overall_confidence = 0.9,
    data_completeness = 0.95,
    source_reliability = 0.85,
    analysis_flags = list(),
    validation_issues = list(),
    is_complete = TRUE,
    reviewer_notes = list(
      "Comprehensive multi-source analysis",
      "High confidence in IPV classification",
      "Clear perpetrator-to-victim directionality",
      "Typical separation-precipitated violence pattern"
    )
  )

  result
}

#' Create Example Collection
#'
#' @description
#' Creates a collection of example forensic analyses representing different
#' types of IPV cases for demonstration and testing purposes.
#'
#' @param n_cases Number of example cases to create (default: 5)
#' @return IPVForensicCollection with example analyses
#' @export
#' @examples
#' # Create example collection
#' collection <- create_example_collection(3)
#'
#' # Get summary data
#' summary_data <- collection$get_summary_tibble()
#' print(summary_data)
#'
#' # Validate collection
#' validation <- collection$validate_collection()
#' print(validation)
create_example_collection <- function(n_cases = 5) {

  case_templates <- list(
    list(
      id = "IPV_HOMICIDE_001",
      type = "ipv_homicide",
      direction = "perpetrator_to_victim",
      confidence = 0.9
    ),
    list(
      id = "IPV_SUICIDE_001",
      type = "ipv_suicide",
      direction = "victim_to_perpetrator",
      confidence = 0.8
    ),
    list(
      id = "IPV_UNDETERMINED_001",
      type = "ipv_undetermined",
      direction = "bidirectional",
      confidence = 0.6
    ),
    list(
      id = "NON_IPV_001",
      type = "non_ipv",
      direction = "undetermined",
      confidence = 0.3
    ),
    list(
      id = "IPV_COMPLEX_001",
      type = "ipv_homicide_suicide",
      direction = "perpetrator_to_victim",
      confidence = 0.85
    )
  )

  # Select templates based on requested number
  selected_templates <- case_templates[seq_len(min(n_cases, length(case_templates)))]
  incident_ids <- sapply(selected_templates, function(x) x$id)

  # Create collection
  collection <- create_forensic_collection(incident_ids)

  # Create detailed analysis for each case
  for (i in seq_along(selected_templates)) {
    template <- selected_templates[[i]]

    result <- ipv_forensic_result$new(
      incident_id = template$id,
      le_narrative = paste("Example LE narrative for", template$type),
      cme_narrative = paste("Example CME narrative for", template$type)
    )

    # Basic classification
    result$update_death_classification(
      classification = template$type,
      confidence = template$confidence,
      rationale = paste("Example", template$type, "case")
    )

    # Directionality
    result$update_directionality(
      primary_direction = template$direction,
      confidence = template$confidence * 0.9
    )

    # Add some evidence
    result$add_evidence(
      evidence_type = "physical_evidence",
      evidence_item = paste("evidence_for", template$type),
      weight = 0.8,
      source = "example_source",
      reliability = 0.75
    )

    # Temporal pattern
    pattern_type <- switch(template$type,
                          "ipv_homicide" = "acute_escalation",
                          "ipv_suicide" = "chronic_pattern",
                          "ipv_undetermined" = "isolated_incident",
                          "non_ipv" = "none",
                          "ipv_homicide_suicide" = "acute_escalation")

    result$update_temporal_patterns(
      pattern_type = pattern_type,
      confidence = template$confidence * 0.8
    )

    # Add to collection
    collection$add_analysis(result)
  }

  collection
}

#' Demonstrate Forensic Analysis Workflow
#'
#' @description
#' Demonstrates a complete forensic analysis workflow from data input
#' through final reporting.
#'
#' @param narrative_text Optional narrative text (uses example if NULL)
#' @param show_steps Whether to print workflow steps (default: TRUE)
#' @return List with all workflow outputs
#' @export
#' @examples
#' # Run complete demonstration
#' demo_results <- demonstrate_forensic_workflow()
#'
#' # Access different components
#' forensic_analysis <- demo_results$forensic_result
#' summary_data <- demo_results$summary
#' validation_report <- demo_results$validation
demonstrate_forensic_workflow <- function(narrative_text = NULL,
                                          show_steps = TRUE) {

  if (show_steps) {
    cli::cli_h1("IPV Forensic Analysis Workflow Demonstration")
  }

  # Step 1: Initialize forensic analysis
  if (show_steps) {
    cli::cli_h2("Step 1: Initialize Forensic Analysis")
    cli::cli_text("Creating IPVForensicResult object...")
  }

  if (is.null(narrative_text)) {
    narrative_text <- paste(
      "Domestic violence incident resulting in death.",
      "Male perpetrator used weapon against female victim.",
      "History of controlling behavior and prior threats.",
      "Recent separation attempt by victim.",
      "Evidence of escalating pattern over recent months."
    )
  }

  forensic_result <- ipv_forensic_result$new(
    incident_id = "DEMO_WORKFLOW_001",
    le_narrative = narrative_text,
    cme_narrative = paste("Medical findings consistent with", narrative_text)
  )

  if (show_steps) {
    cli::cli_alert_success("Forensic analysis object created")
  }

  # Step 2: Perform comprehensive analysis
  if (show_steps) {
    cli::cli_h2("Step 2: Perform Comprehensive Analysis")
  }

  # Death classification
  if (show_steps) {
    cli::cli_text("- Analyzing death classification...")
  }
  forensic_result$update_death_classification(
    classification = "ipv_homicide",
    confidence = 0.85,
    evidence = list("weapon_evidence", "domestic_violence_history"),
    rationale = "Clear evidence of intimate partner violence homicide"
  )

  # Directionality assessment
  if (show_steps) {
    cli::cli_text("- Assessing violence directionality...")
  }
  forensic_result <- analyze_directionality_patterns(
    forensic_result, narrative_text, "LE"
  )

  # Suicide analysis
  if (show_steps) {
    cli::cli_text("- Analyzing suicide-related factors...")
  }
  forensic_result <- analyze_suicide_intent(
    forensic_result, narrative_text, "LE"
  )

  # Temporal patterns
  if (show_steps) {
    cli::cli_text("- Identifying temporal patterns...")
  }
  forensic_result <- analyze_temporal_patterns(
    forensic_result, narrative_text
  )

  # Evidence hierarchy
  if (show_steps) {
    cli::cli_text("- Building evidence hierarchy...")
  }
  forensic_result <- analyze_evidence_hierarchy(
    forensic_result, narrative_text, "LE"
  )

  if (show_steps) {
    cli::cli_alert_success("Comprehensive analysis completed")
  }

  # Step 3: Generate summary and reports
  if (show_steps) {
    cli::cli_h2("Step 3: Generate Summary and Reports")
  }

  summary <- forensic_result$get_summary()
  tibble_data <- forensic_result$to_tibble()
  validation <- forensic_result$validate_analysis()

  if (show_steps) {
    cli::cli_text("Analysis Summary:")
    cli::cli_text("- Death Classification: {summary$death_classification$type}")
    cli::cli_text("- Classification Confidence: {scales::percent(summary$death_classification$confidence)}")
    cli::cli_text("- Primary Direction: {summary$directionality$primary_direction}")
    cli::cli_text("- Evidence Items: {summary$evidence_summary$total_items}")
    cli::cli_text("- Temporal Pattern: {summary$temporal_assessment$pattern_type}")
  }

  # Step 4: Validation report
  if (show_steps) {
    cli::cli_h2("Step 4: Validation Report")
    cli::cli_text("Analysis Valid: {ifelse(validation$is_valid, 'Yes', 'No')}")
    cli::cli_text("Completeness Score: {scales::percent(validation$completeness_score)}")

    if (length(validation$issues) > 0) {
      cli::cli_text("Issues Found:")
      for (issue in validation$issues) {
        cli::cli_text("- {issue}")
      }
    } else {
      cli::cli_alert_success("No validation issues found")
    }
  }

  # Step 5: Export for further analysis
  if (show_steps) {
    cli::cli_h2("Step 5: Export for Analysis")
    cli::cli_text("Data exported to tibble format for statistical analysis")
    cli::cli_text("Columns available: {paste(names(tibble_data), collapse = ', ')}")
  }

  # Return all results
  list(
    forensic_result = forensic_result,
    summary = summary,
    tibble_data = tibble_data,
    validation = validation,
    narrative_used = narrative_text
  )
}