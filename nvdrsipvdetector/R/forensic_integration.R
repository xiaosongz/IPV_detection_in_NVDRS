#' Integration Functions for Advanced Forensic Analysis
#'
#' @description
#' Functions to integrate simple IPV detection with comprehensive forensic
#' analysis structure. Provides migration path from basic detection to
#' advanced analysis framework.
#'
#' @name forensic_integration
#' @keywords internal
NULL

#' Enhanced IPV Detection with Forensic Analysis
#'
#' @description
#' Legacy wrapper function for backward compatibility. 
#' Uses the comprehensive forensic detection from ipv_detection.R.
#' For new code, use detect_ipv_forensic() directly from ipv_detection.R.
#'
#' @param narrative Narrative text to analyze
#' @param type "LE" for law enforcement or "CME" for medical examiner
#' @param incident_id Unique incident identifier
#' @param config Configuration object or path
#' @param conn Database connection
#' @param enable_forensic Enable advanced forensic analysis (default: TRUE)
#' @return IPVForensicResult object or basic result based on enable_forensic
#' @export
#' @examples
#' \dontrun{
#' # Enhanced detection with forensic analysis
#' result <- detect_ipv_enhanced(
#'   narrative = "Domestic violence incident with injury patterns",
#'   type = "CME",
#'   incident_id = "2024-001"
#' )
#'
#' # Access comprehensive analysis
#' summary <- result$get_summary()
#' tibble_data <- result$to_tibble()
#' }
detect_ipv_enhanced <- function(narrative,
                               type = "LE",
                               incident_id = NULL,
                               config = NULL,
                               conn = NULL,
                               enable_forensic = TRUE) {

  if (!enable_forensic) {
    # Return basic IPV detection for backward compatibility
    return(detect_ipv(
      narrative = narrative,
      type = type,
      config = config,
      conn = conn,
      log_to_db = !is.null(conn)
    ))
  }

  # Use comprehensive forensic analysis from ipv_detection.R
  # This function is defined in ipv_detection.R with the name detect_ipv_forensic
  detect_ipv_forensic(
    narrative = narrative,
    type = type,
    incident_id = incident_id,
    config = config,
    conn = conn,
    log_to_db = !is.null(conn)
  )
}

#' Process NVDRS Batch with Forensic Analysis
#'
#' @description
#' Enhanced batch processing that creates comprehensive forensic analysis
#' for each incident while maintaining compatibility with existing workflow.
#'
#' @param data Input data (path or tibble)
#' @param config Configuration object or path
#' @param enable_forensic Enable forensic analysis (default: TRUE)
#' @param validate Run validation against manual flags
#' @return IPVForensicCollection or tibble based on enable_forensic
#' @export
#' @examples
#' \dontrun{
#' # Process with forensic analysis
#' collection <- nvdrs_process_batch_forensic("data.csv", enable_forensic = TRUE)
#'
#' # Get summary data for analysis
#' summary_data <- collection$get_summary_tibble()
#'
#' # Export for external analysis
#' export_data <- collection$export_for_analysis()
#' }
nvdrs_process_batch_forensic <- function(data,
                                         config = NULL,
                                         enable_forensic = TRUE,
                                         validate = FALSE) {

  if (!enable_forensic) {
    # Return basic batch processing
    return(nvdrs_process_batch(
      data = data,
      config = config,
      validate = validate
    ))
  }

  # Load config if needed
  if (is.character(config)) {
    config <- load_config(config)
  }

  # Load data if needed
  if (is.character(data)) {
    data <- read_nvdrs_data(data)
    data <- validate_input_data(data)
  }

  # Create forensic collection
  incident_ids <- unique(data$IncidentID)
  collection <- create_forensic_collection(incident_ids, data)

  # Process each incident with comprehensive forensic analysis
  pb <- cli::cli_progress_bar(
    "Processing forensic analyses",
    total = length(incident_ids)
  )

  for (id in incident_ids) {
    row_data <- data[data$IncidentID == id, ]
    
    if (nrow(row_data) > 0) {
      # Process LE narrative if available
      if (!is.null(row_data$NarrativeLE[1]) && !is.na(row_data$NarrativeLE[1])) {
        le_result <- ipv_detection::detect_ipv_forensic(
          narrative = row_data$NarrativeLE[1],
          type = "LE",
          incident_id = id,
          config = config
        )
        
        # Update collection with LE results
        existing_result <- collection$get_analysis(id)
        if (!is.null(existing_result)) {
          existing_result$source_narratives$le <- row_data$NarrativeLE[1]
          merge_forensic_results(existing_result, le_result, "LE")
        }
      }
      
      # Process CME narrative if available
      if (!is.null(row_data$NarrativeCME[1]) && !is.na(row_data$NarrativeCME[1])) {
        cme_result <- ipv_detection::detect_ipv_forensic(
          narrative = row_data$NarrativeCME[1],
          type = "CME",
          incident_id = id,
          config = config
        )
        
        # Update collection with CME results
        existing_result <- collection$get_analysis(id)
        if (!is.null(existing_result)) {
          existing_result$source_narratives$cme <- row_data$NarrativeCME[1]
          merge_forensic_results(existing_result, cme_result, "CME")
        }
      }
    }

    cli::cli_progress_update(id = pb)
  }

  cli::cli_progress_done(id = pb)
  
  # Perform cross-narrative consistency analysis
  for (id in incident_ids) {
    forensic_result <- collection$get_analysis(id)
    if (!is.null(forensic_result)) {
      row_data <- data[data$IncidentID == id, ]
      if (nrow(row_data) > 0) {
        forensic_result <- analyze_narrative_consistency(forensic_result, row_data[1, ])
      }
    }
  }
  
  collection
}

#' Populate Forensic Result from Basic Detection
#'
#' @description
#' Transfers results from basic IPV detection to forensic analysis structure.
#'
#' @param forensic_result IPVForensicResult object
#' @param basic_result Basic detection result
#' @param narrative_type "LE" or "CME"
#' @return Updated forensic result
populate_from_basic_detection <- function(forensic_result,
                                          basic_result,
                                          narrative_type) {

  # Update death classification based on basic result
  if (!is.null(basic_result$ipv_detected) && !is.na(basic_result$ipv_detected)) {
    classification <- if (basic_result$ipv_detected) "ipv_detected" else "non_ipv"
    forensic_result$update_death_classification(
      classification = classification,
      confidence = basic_result$confidence %||% 0,
      rationale = basic_result$rationale %||% "Basic LLM analysis"
    )
  }

  # Add evidence from basic indicators
  if (!is.null(basic_result$indicators) && length(basic_result$indicators) > 0) {
    for (indicator in basic_result$indicators) {
      forensic_result$add_evidence(
        evidence_type = "behavioral_evidence",
        evidence_item = indicator,
        weight = 0.6,
        source = paste0(narrative_type, "_narrative"),
        reliability = 0.7
      )
    }
  }

  # Update quality metrics
  forensic_result$quality_metrics$data_completeness <- 0.3
  forensic_result$quality_metrics$overall_confidence <-
    basic_result$confidence %||% 0

  forensic_result
}

#' Populate from Batch Results
#'
#' @description
#' Populates forensic result with data from batch processing results.
#'
#' @param forensic_result IPVForensicResult object
#' @param basic_row Row from basic batch results
#' @param data_row Row from original data
#' @return Updated forensic result
populate_from_batch_results <- function(forensic_result,
                                         basic_row,
                                         data_row) {

  # Update with reconciled results
  if (!is.null(basic_row$ipv_detected) && !is.na(basic_row$ipv_detected)) {
    classification <- if (basic_row$ipv_detected) "ipv_detected" else "non_ipv"
    forensic_result$update_death_classification(
      classification = classification,
      confidence = basic_row$confidence %||% 0,
      rationale = "Reconciled LE/CME analysis"
    )
  }

  # Add directionality assessment if available
  if (!is.null(basic_row$le_ipv) && !is.null(basic_row$cme_ipv)) {
    # Simple heuristic for directionality based on LE vs CME agreement
    if (!is.na(basic_row$le_ipv) && !is.na(basic_row$cme_ipv)) {
      direction <- if (basic_row$le_ipv && basic_row$cme_ipv) {
        "perpetrator_to_victim"
      } else if (basic_row$le_ipv && !basic_row$cme_ipv) {
        "behavioral_evidence_primary"
      } else if (!basic_row$le_ipv && basic_row$cme_ipv) {
        "physical_evidence_primary"
      } else {
        "undetermined"
      }

      forensic_result$update_directionality(
        primary_direction = direction,
        confidence = abs(basic_row$le_confidence - basic_row$cme_confidence)
      )
    }
  }

  forensic_result
}

#' Perform Advanced Analysis
#'
#' @description
#' Conducts advanced forensic analysis on narrative text to populate
#' detailed forensic structure.
#'
#' @param forensic_result IPVForensicResult object
#' @param narrative Text to analyze
#' @param type Narrative type ("LE" or "CME")
#' @param config Configuration object
#' @return Updated forensic result
perform_advanced_analysis <- function(forensic_result,
                                      narrative,
                                      type,
                                      config) {

  # Advanced pattern analysis for directionality
  forensic_result <- analyze_directionality_patterns(
    forensic_result,
    narrative,
    type
  )

  # Suicide intent analysis
  forensic_result <- analyze_suicide_intent(
    forensic_result,
    narrative,
    type
  )

  # Temporal pattern detection
  forensic_result <- analyze_temporal_patterns(
    forensic_result,
    narrative
  )

  # Evidence hierarchy analysis
  forensic_result <- analyze_evidence_hierarchy(
    forensic_result,
    narrative,
    type
  )

  # Update quality metrics
  forensic_result$quality_metrics$data_completeness <- calculate_data_completeness(
    forensic_result
  )

  forensic_result
}

#' Perform Comprehensive Analysis
#'
#' @description
#' Performs comprehensive analysis using both LE and CME narratives
#' for maximum forensic insight.
#'
#' @param forensic_result IPVForensicResult object
#' @param data_row Data row with both narratives
#' @param config Configuration object
#' @return Updated forensic result
perform_comprehensive_analysis <- function(forensic_result,
                                           data_row,
                                           config) {

  # Analyze LE narrative
  if (!is.null(data_row$NarrativeLE) && !is.na(data_row$NarrativeLE)) {
    forensic_result <- perform_advanced_analysis(
      forensic_result,
      data_row$NarrativeLE,
      "LE",
      config
    )
  }

  # Analyze CME narrative
  if (!is.null(data_row$NarrativeCME) && !is.na(data_row$NarrativeCME)) {
    forensic_result <- perform_advanced_analysis(
      forensic_result,
      data_row$NarrativeCME,
      "CME",
      config
    )
  }

  # Cross-narrative consistency analysis
  forensic_result <- analyze_narrative_consistency(
    forensic_result,
    data_row
  )

  forensic_result
}

#' Analyze Directionality Patterns
#'
#' @description
#' Pattern-based analysis for determining violence directionality.
#'
#' @param forensic_result IPVForensicResult object
#' @param narrative Text to analyze
#' @param type Narrative type
#' @return Updated forensic result
analyze_directionality_patterns <- function(forensic_result,
                                             narrative,
                                             type) {

  # Handle NULL or empty narratives
  if (is.null(narrative) || is.na(narrative) || nchar(trimws(narrative)) == 0) {
    forensic_result$update_directionality(
      primary_direction = "undetermined",
      confidence = 0
    )
    return(forensic_result)
  }

  # Simple pattern matching for directionality indicators
  perpetrator_patterns <- c(
    "perpetrator", "suspect", "defendant", "accused",
    "he struck", "he hit", "he shot", "he stabbed",
    "male subject", "boyfriend", "husband"
  )

  victim_patterns <- c(
    "victim", "deceased", "decedent",
    "she was struck", "she was shot", "injuries to",
    "defensive wounds", "multiple injuries"
  )

  # Count pattern matches
  perp_matches <- sum(stringr::str_count(
    tolower(narrative), perpetrator_patterns
  ))
  victim_matches <- sum(stringr::str_count(
    tolower(narrative), victim_patterns
  ))

  # Determine primary direction
  if (perp_matches > victim_matches * 1.5) {
    direction <- "perpetrator_to_victim"
    confidence <- min(0.8, perp_matches / (perp_matches + victim_matches + 1))
  } else if (victim_matches > perp_matches * 1.5) {
    direction <- "victim_focused_evidence"
    confidence <- min(0.8, victim_matches / (perp_matches + victim_matches + 1))
  } else {
    direction <- "undetermined"
    confidence <- 0.3
  }

  forensic_result$update_directionality(
    primary_direction = direction,
    confidence = confidence
  )

  forensic_result
}

#' Analyze Suicide Intent
#'
#' @description
#' Analyzes narrative for suicide intent indicators and weapon vs escape
#' classification.
#'
#' @param forensic_result IPVForensicResult object
#' @param narrative Text to analyze
#' @param type Narrative type
#' @return Updated forensic result
analyze_suicide_intent <- function(forensic_result,
                                   narrative,
                                   type) {

  # Suicide intent indicators
  intent_patterns <- c(
    "suicide", "took own life", "self-inflicted",
    "suicide note", "expressed intent", "previous attempts"
  )

  # Weapon vs escape indicators
  weapon_patterns <- c(
    "gun", "firearm", "weapon", "knife", "sharp object"
  )

  escape_patterns <- c(
    "escape", "flee", "run away", "overdose", "pills",
    "domestic violence", "abuse", "threatened"
  )

  intent_matches <- sum(stringr::str_count(
    tolower(narrative), intent_patterns
  ))
  weapon_matches <- sum(stringr::str_count(
    tolower(narrative), weapon_patterns
  ))
  escape_matches <- sum(stringr::str_count(
    tolower(narrative), escape_patterns
  ))

  # Classify intent
  intent_classification <- if (intent_matches >= 2) {
    "clear_intent"
  } else if (intent_matches == 1) {
    "ambiguous_intent"
  } else {
    "undetermined"
  }

  # Classify method
  weapon_vs_escape <- if (weapon_matches > escape_matches) {
    "weapon_against_partner"
  } else if (escape_matches > weapon_matches) {
    "escape_from_violence"
  } else {
    "undetermined"
  }

  confidence <- min(0.7, (intent_matches + weapon_matches + escape_matches) / 10)

  forensic_result$update_suicide_analysis(
    intent_classification = intent_classification,
    weapon_vs_escape = weapon_vs_escape,
    confidence = confidence
  )

  forensic_result
}

#' Analyze Temporal Patterns
#'
#' @description
#' Identifies temporal patterns and escalation indicators in narrative.
#'
#' @param forensic_result IPVForensicResult object
#' @param narrative Text to analyze
#' @return Updated forensic result
analyze_temporal_patterns <- function(forensic_result, narrative) {

  # Handle NULL or empty narratives
  if (is.null(narrative) || is.na(narrative) || nchar(trimws(narrative)) == 0) {
    forensic_result$update_temporal_patterns(
      pattern_type = "none",
      confidence = 0
    )
    return(forensic_result)
  }

  # Escalation indicators
  escalation_patterns <- c(
    "escalating", "increasing", "more frequent",
    "recent separation", "custody", "divorce",
    "restraining order", "protection order"
  )

  # Temporal markers
  temporal_patterns <- c(
    "recently", "last week", "yesterday", "that morning",
    "previous incidents", "history of", "pattern of"
  )

  escalation_matches <- stringr::str_extract_all(
    tolower(narrative), paste(escalation_patterns, collapse = "|")
  )[[1]]

  temporal_matches <- stringr::str_extract_all(
    tolower(narrative), paste(temporal_patterns, collapse = "|")
  )[[1]]

  # Determine pattern type
  pattern_type <- if (length(escalation_matches) >= 2) {
    "acute_escalation"
  } else if (length(temporal_matches) >= 3) {
    "chronic_pattern"
  } else if (length(temporal_matches) >= 1) {
    "isolated_incident"
  } else {
    "none"
  }

  confidence <- min(0.6, (length(escalation_matches) + length(temporal_matches)) / 5)

  forensic_result$update_temporal_patterns(
    escalation_indicators = escalation_matches,
    pattern_type = pattern_type,
    confidence = confidence
  )

  forensic_result
}

#' Analyze Evidence Hierarchy
#'
#' @description
#' Categorizes and weights evidence based on type and reliability.
#'
#' @param forensic_result IPVForensicResult object
#' @param narrative Text to analyze
#' @param type Narrative type
#' @return Updated forensic result
analyze_evidence_hierarchy <- function(forensic_result, narrative, type) {

  # Physical evidence patterns
  physical_patterns <- c(
    "injury", "wound", "bruise", "fracture", "laceration",
    "defensive wounds", "strangulation", "blunt force"
  )

  # Behavioral evidence patterns
  behavioral_patterns <- c(
    "threatened", "stalking", "controlling", "jealous",
    "history of violence", "domestic violence", "restraining order"
  )

  # Contextual evidence patterns
  contextual_patterns <- c(
    "witness", "neighbor", "family member", "friend",
    "police report", "previous call", "documentation"
  )

  # Add evidence items with appropriate weights
  physical_evidence <- stringr::str_extract_all(
    tolower(narrative), paste(physical_patterns, collapse = "|")
  )[[1]]

  behavioral_evidence <- stringr::str_extract_all(
    tolower(narrative), paste(behavioral_patterns, collapse = "|")
  )[[1]]

  contextual_evidence <- stringr::str_extract_all(
    tolower(narrative), paste(contextual_patterns, collapse = "|")
  )[[1]]

  # Add physical evidence (highest weight)
  for (evidence in physical_evidence) {
    forensic_result$add_evidence(
      evidence_type = "physical_evidence",
      evidence_item = evidence,
      weight = 0.9,
      source = paste0(type, "_narrative"),
      reliability = 0.8
    )
  }

  # Add behavioral evidence
  for (evidence in behavioral_evidence) {
    forensic_result$add_evidence(
      evidence_type = "behavioral_evidence",
      evidence_item = evidence,
      weight = 0.7,
      source = paste0(type, "_narrative"),
      reliability = 0.6
    )
  }

  # Add contextual evidence
  for (evidence in contextual_evidence) {
    forensic_result$add_evidence(
      evidence_type = "contextual_evidence",
      evidence_item = evidence,
      weight = 0.5,
      source = paste0(type, "_narrative"),
      reliability = 0.7
    )
  }

  forensic_result
}

#' Analyze Narrative Consistency
#'
#' @description
#' Analyzes consistency between LE and CME narratives.
#'
#' @param forensic_result IPVForensicResult object
#' @param data_row Data row with both narratives
#' @return Updated forensic result
analyze_narrative_consistency <- function(forensic_result, data_row) {

  # Check if both narratives are available
  le_available <- !is.null(data_row$NarrativeLE) &&
    !is.na(data_row$NarrativeLE) &&
    nchar(trimws(data_row$NarrativeLE)) > 0

  cme_available <- !is.null(data_row$NarrativeCME) &&
    !is.na(data_row$NarrativeCME) &&
    nchar(trimws(data_row$NarrativeCME)) > 0

  if (le_available && cme_available) {
    # Simple consistency check based on common terms
    le_terms <- unique(unlist(strsplit(tolower(data_row$NarrativeLE), "\\W+")))
    cme_terms <- unique(unlist(strsplit(tolower(data_row$NarrativeCME), "\\W+")))

    common_terms <- intersect(le_terms, cme_terms)
    consistency_score <- length(common_terms) /
      (length(union(le_terms, cme_terms)) + 1)

    # Update quality metrics
    forensic_result$quality_metrics$source_reliability <- consistency_score
    forensic_result$quality_metrics$data_completeness <- 0.8
  } else {
    forensic_result$quality_metrics$data_completeness <- 0.4
  }

  forensic_result
}

#' Calculate Data Completeness
#'
#' @description
#' Calculates overall data completeness score for forensic analysis.
#'
#' @param forensic_result IPVForensicResult object
#' @return Completeness score (0-1)
calculate_data_completeness <- function(forensic_result) {

  components <- c(
    death_classification = !is.null(forensic_result$death_classification$primary),
    directionality = !is.null(forensic_result$directionality$primary_direction),
    evidence_items = length(forensic_result$evidence_matrix$items) > 0,
    source_narratives = !is.null(forensic_result$source_narratives$le) ||
      !is.null(forensic_result$source_narratives$cme),
    suicide_analysis = !is.null(forensic_result$suicide_analysis$intent_classification),
    temporal_patterns = !is.null(forensic_result$temporal_patterns$pattern_type)
  )

  mean(components)
}

#' Merge Forensic Results
#'
#' @description
#' Merges results from LE and CME forensic analyses into a single result.
#'
#' @param target_result Target IPVForensicResult to merge into  
#' @param source_result Source IPVForensicResult to merge from
#' @param source_type "LE" or "CME" indicating source type
#' @return Updated target result
merge_forensic_results <- function(target_result, source_result, source_type) {
  
  # Merge death classifications (use highest confidence)
  if (source_result$death_classification$confidence > 
      target_result$death_classification$confidence) {
    target_result$update_death_classification(
      classification = source_result$death_classification$primary,
      confidence = source_result$death_classification$confidence,
      evidence = source_result$death_classification$supporting_evidence,
      rationale = paste0(source_type, ": ", source_result$death_classification$rationale)
    )
  }
  
  # Merge directionality (weighted average)
  new_confidence <- (target_result$directionality$confidence + 
                    source_result$directionality$confidence) / 2
  
  target_result$update_directionality(
    perpetrator_evidence = c(target_result$directionality$perpetrator_indicators,
                            source_result$directionality$perpetrator_indicators),
    victim_evidence = c(target_result$directionality$victim_indicators,
                       source_result$directionality$victim_indicators),
    bidirectional_score = max(target_result$directionality$bidirectional_score,
                             source_result$directionality$bidirectional_score),
    primary_direction = if (new_confidence > 0.5) {
      source_result$directionality$primary_direction
    } else {
      target_result$directionality$primary_direction
    },
    confidence = new_confidence
  )
  
  # Copy evidence items from source
  for (evidence_item in source_result$evidence_matrix$items) {
    target_result$add_evidence(
      evidence_type = evidence_item$type,
      evidence_item = evidence_item$item,
      weight = evidence_item$weight,
      source = paste0(source_type, "_", evidence_item$source),
      reliability = evidence_item$reliability
    )
  }
  
  # Merge temporal patterns
  combined_escalation <- c(
    target_result$temporal_patterns$escalation_indicators,
    source_result$temporal_patterns$escalation_indicators
  )
  
  target_result$update_temporal_patterns(
    escalation_indicators = unique(combined_escalation),
    timeline_events = c(target_result$temporal_patterns$timeline_events,
                       source_result$temporal_patterns$timeline_events),
    pattern_type = if (source_result$temporal_patterns$confidence > 
                      target_result$temporal_patterns$confidence) {
      source_result$temporal_patterns$pattern_type
    } else {
      target_result$temporal_patterns$pattern_type
    },
    confidence = max(target_result$temporal_patterns$confidence,
                    source_result$temporal_patterns$confidence)
  )
  
  # Update quality metrics
  target_result$quality_metrics$overall_confidence <- 
    max(target_result$quality_metrics$overall_confidence,
        source_result$quality_metrics$overall_confidence)
  
  target_result$quality_metrics$analysis_flags <- 
    c(target_result$quality_metrics$analysis_flags,
      source_result$quality_metrics$analysis_flags)
  
  target_result
}