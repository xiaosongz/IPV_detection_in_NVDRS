#' Advanced IPV Forensic Analysis Data Structure
#'
#' @description
#' Comprehensive R6 class for advanced intimate partner violence forensic
#' analysis. Supports directionality, suicide intent, evidence hierarchy, and
#' temporal patterns.
#'
#' @name forensic_data_structure
#' @keywords internal
NULL

#' IPV Forensic Analysis Result Class
#'
#' @description
#' R6 class that encapsulates comprehensive IPV forensic analysis including
#' directionality assessment, suicide intent classification, evidence weighting,
#' and temporal pattern analysis.
#'
#' @field incident_id Unique incident identifier
#' @field analysis_timestamp Timestamp when analysis was created
#' @field analysis_version Version of analysis framework
#' @field death_classification Death classification structure
#' @field directionality Violence directionality assessment
#' @field perpetrator_profile Perpetrator profile and indicators
#' @field victim_profile Victim profile and indicators
#' @field suicide_analysis Suicide intent and method analysis
#' @field evidence_matrix Evidence hierarchy and weighting
#' @field temporal_patterns Temporal pattern analysis
#' @field quality_metrics Quality and validation metrics
#' @field source_narratives Source narrative texts
#'
#' @export
ipv_forensic_result <- R6::R6Class(
  "IPVForensicResult",

  public = list(
    # Core identification
    incident_id = NULL,
    analysis_timestamp = NULL,
    analysis_version = "1.0.0",

    # Death classification
    death_classification = NULL,

    # Directionality assessment
    directionality = NULL,

    # Perpetrator/victim indicators
    perpetrator_profile = NULL,
    victim_profile = NULL,

    # Suicide framework
    suicide_analysis = NULL,

    # Evidence hierarchy
    evidence_matrix = NULL,

    # Temporal analysis
    temporal_patterns = NULL,

    # Quality and validation
    quality_metrics = NULL,

    # Data sources
    source_narratives = NULL,

    #' Initialize IPV Forensic Result
    #'
    #' @param incident_id Unique incident identifier
    #' @param le_narrative Law enforcement narrative
    #' @param cme_narrative Medical examiner narrative
    #' @param additional_sources List of additional data sources
    #'
    initialize = function(incident_id,
                          le_narrative = NULL,
                          cme_narrative = NULL,
                          additional_sources = NULL) {

      self$incident_id <- incident_id
      self$analysis_timestamp <- Sys.time()

      # Initialize core structures
      self$death_classification <- private$init_death_classification()
      self$directionality <- private$init_directionality_assessment()
      self$perpetrator_profile <- private$init_person_profile("perpetrator")
      self$victim_profile <- private$init_person_profile("victim")
      self$suicide_analysis <- private$init_suicide_framework()
      self$evidence_matrix <- private$init_evidence_matrix()
      self$temporal_patterns <- private$init_temporal_analysis()
      self$quality_metrics <- private$init_quality_metrics()

      # Store source data
      self$source_narratives <- list(
        le = le_narrative,
        cme = cme_narrative,
        additional = additional_sources
      )

      invisible(self)
    },

    #' Update Death Classification
    #'
    #' @param classification Primary death classification
    #' @param confidence Confidence score (0-1)
    #' @param evidence Supporting evidence
    #' @param rationale Analysis rationale
    #'
    update_death_classification = function(classification,
                                           confidence,
                                           evidence = NULL,
                                           rationale = NULL) {
      self$death_classification$primary <- classification
      self$death_classification$confidence <- confidence
      self$death_classification$supporting_evidence <- evidence
      self$death_classification$rationale <- rationale
      self$death_classification$last_updated <- Sys.time()

      invisible(self)
    },

    #' Update Directionality Assessment
    #'
    #' @param perpetrator_evidence List of perpetrator indicators
    #' @param victim_evidence List of victim indicators
    #' @param bidirectional_score Bidirectional violence score
    #' @param primary_direction Primary direction assessment
    #' @param confidence Overall confidence
    #'
    update_directionality = function(perpetrator_evidence = NULL,
                                     victim_evidence = NULL,
                                     bidirectional_score = 0,
                                     primary_direction = "undetermined",
                                     confidence = 0) {

      self$directionality$perpetrator_indicators <- perpetrator_evidence
      self$directionality$victim_indicators <- victim_evidence
      self$directionality$bidirectional_score <- bidirectional_score
      self$directionality$primary_direction <- primary_direction
      self$directionality$confidence <- confidence
      self$directionality$last_updated <- Sys.time()

      invisible(self)
    },

    #' Update Suicide Analysis
    #'
    #' @param intent_classification Intent classification
    #' @param weapon_vs_escape Weapon vs escape method classification
    #' @param precipitating_factors List of precipitating factors
    #' @param confidence Confidence score
    #'
    update_suicide_analysis = function(intent_classification = "undetermined",
                                       weapon_vs_escape = "undetermined",
                                       precipitating_factors = NULL,
                                       confidence = 0) {

      self$suicide_analysis$intent_classification <- intent_classification
      self$suicide_analysis$weapon_vs_escape <- weapon_vs_escape
      self$suicide_analysis$precipitating_factors <- precipitating_factors
      self$suicide_analysis$confidence <- confidence
      self$suicide_analysis$last_updated <- Sys.time()

      invisible(self)
    },

    #' Add Evidence to Matrix
    #'
    #' @param evidence_type Type of evidence
    #' @param evidence_item Specific evidence item
    #' @param weight Evidence weight (0-1)
    #' @param source Evidence source
    #' @param reliability Reliability score (0-1)
    #'
    add_evidence = function(evidence_type,
                            evidence_item,
                            weight = 0.5,
                            source = "narrative",
                            reliability = 0.5) {

      new_evidence <- list(
        type = evidence_type,
        item = evidence_item,
        weight = weight,
        source = source,
        reliability = reliability,
        timestamp = Sys.time()
      )

      if (is.null(self$evidence_matrix$items)) {
        self$evidence_matrix$items <- list()
      }

      idx <- length(self$evidence_matrix$items) + 1
      self$evidence_matrix$items[[idx]] <- new_evidence

      # Update summary statistics
      private$recalculate_evidence_summary()

      invisible(self)
    },

    #' Update Temporal Patterns
    #'
    #' @param escalation_indicators List of escalation indicators
    #' @param timeline_events Chronological events
    #' @param pattern_type Type of temporal pattern
    #' @param confidence Confidence in pattern
    #'
    update_temporal_patterns = function(escalation_indicators = NULL,
                                        timeline_events = NULL,
                                        pattern_type = "none",
                                        confidence = 0) {

      self$temporal_patterns$escalation_indicators <- escalation_indicators
      self$temporal_patterns$timeline_events <- timeline_events
      self$temporal_patterns$pattern_type <- pattern_type
      self$temporal_patterns$confidence <- confidence
      self$temporal_patterns$last_updated <- Sys.time()

      invisible(self)
    },

    #' Generate Summary Report
    #'
    #' @return Comprehensive summary list
    #'
    get_summary = function() {
      list(
        incident_id = self$incident_id,
        analysis_timestamp = self$analysis_timestamp,

        # Primary findings
        death_classification = list(
          type = self$death_classification$primary,
          confidence = self$death_classification$confidence
        ),

        directionality = list(
          primary_direction = self$directionality$primary_direction,
          bidirectional_score = self$directionality$bidirectional_score,
          confidence = self$directionality$confidence
        ),

        suicide_analysis = list(
          intent = self$suicide_analysis$intent_classification,
          method_type = self$suicide_analysis$weapon_vs_escape,
          confidence = self$suicide_analysis$confidence
        ),

        # Evidence summary
        evidence_summary = self$evidence_matrix$summary,

        # Temporal assessment
        temporal_assessment = list(
          pattern_type = self$temporal_patterns$pattern_type,
          escalation_detected = length(
            self$temporal_patterns$escalation_indicators
          ) > 0
        ),

        # Quality metrics
        overall_confidence = self$quality_metrics$overall_confidence,
        data_completeness = self$quality_metrics$data_completeness,
        analysis_flags = self$quality_metrics$analysis_flags
      )
    },

    #' Export to Tibble
    #'
    #' @return Flattened tibble for analysis
    #'
    to_tibble = function() {
      summary <- self$get_summary()

      tibble::tibble(
        incident_id = self$incident_id,
        analysis_timestamp = self$analysis_timestamp,

        # Death classification
        death_type = summary$death_classification$type,
        death_confidence = summary$death_classification$confidence,

        # Directionality
        primary_direction = summary$directionality$primary_direction,
        bidirectional_score = summary$directionality$bidirectional_score,
        direction_confidence = summary$directionality$confidence,

        # Suicide analysis
        suicide_intent = summary$suicide_analysis$intent,
        suicide_method_type = summary$suicide_analysis$method_type,
        suicide_confidence = summary$suicide_analysis$confidence,

        # Evidence metrics
        total_evidence_items = summary$evidence_summary$total_items,
        high_weight_evidence = summary$evidence_summary$high_weight_items,
        evidence_diversity = summary$evidence_summary$type_diversity,

        # Temporal patterns
        temporal_pattern_type = summary$temporal_assessment$pattern_type,
        escalation_detected = summary$temporal_assessment$escalation_detected,

        # Quality metrics
        overall_confidence = summary$overall_confidence,
        data_completeness = summary$data_completeness,
        has_analysis_flags = length(summary$analysis_flags) > 0
      )
    },

    #' Validate Analysis Completeness
    #'
    #' @return Validation results
    #'
    validate_analysis = function() {
      issues <- character()

      # Check required classifications
      if (is.null(self$death_classification$primary)) {
        issues <- c(issues, "Missing death classification")
      }

      if (is.null(self$directionality$primary_direction)) {
        issues <- c(issues, "Missing directionality assessment")
      }

      # Check evidence completeness
      if (length(self$evidence_matrix$items) == 0) {
        issues <- c(issues, "No evidence items recorded")
      }

      # Check source data
      if (is.null(self$source_narratives$le) &&
            is.null(self$source_narratives$cme)) {
        issues <- c(issues, "No source narratives available")
      }

      # Update quality metrics
      self$quality_metrics$validation_issues <- issues
      self$quality_metrics$is_complete <- length(issues) == 0

      list(
        is_valid = length(issues) == 0,
        issues = issues,
        completeness_score = private$calculate_completeness_score()
      )
    }
  ),

  private = list(

    #' Initialize Death Classification Structure
    init_death_classification = function() {
      list(
        # "ipv_homicide", "ipv_suicide", "ipv_undetermined", "non_ipv"
        primary = NULL,
        secondary = NULL,  # Additional classifications
        confidence = 0,
        supporting_evidence = list(),
        alternative_hypotheses = list(),
        rationale = NULL,
        last_updated = NULL
      )
    },

    #' Initialize Directionality Assessment Structure
    init_directionality_assessment = function() {
      list(
        # "perpetrator_to_victim", "victim_to_perpetrator",
        # "bidirectional", "undetermined"
        primary_direction = "undetermined",
        perpetrator_indicators = list(),
        victim_indicators = list(),
        bidirectional_score = 0,  # 0-1 score for mutual violence
        confidence = 0,
        analysis_method = "narrative_based",
        last_updated = NULL
      )
    },

    #' Initialize Person Profile Structure
    init_person_profile = function(role) {
      list(
        role = role,  # "perpetrator" or "victim"
        demographic_indicators = list(),
        behavioral_indicators = list(),
        injury_patterns = list(),
        weapon_access = list(),
        prior_violence_history = list(),
        relationship_factors = list(),
        risk_factors = list(),
        protective_factors = list()
      )
    },

    #' Initialize Suicide Framework Structure
    init_suicide_framework = function() {
      list(
        # "clear_intent", "ambiguous_intent", "no_intent", "undetermined"
        intent_classification = "undetermined",
        # "weapon_against_partner", "escape_from_violence",
        # "combination", "undetermined"
        weapon_vs_escape = "undetermined",
        precipitating_factors = list(),
        method_analysis = list(),
        note_analysis = list(),
        behavioral_precursors = list(),
        confidence = 0,
        last_updated = NULL
      )
    },

    #' Initialize Evidence Matrix Structure
    init_evidence_matrix = function() {
      list(
        items = list(),
        summary = list(
          total_items = 0,
          high_weight_items = 0,
          type_diversity = 0,
          source_reliability = 0,
          last_calculated = NULL
        ),
        weighting_scheme = "default",
        hierarchy_rules = list(
          physical_evidence = 0.9,
          behavioral_evidence = 0.7,
          contextual_evidence = 0.5,
          circumstantial_evidence = 0.3
        )
      )
    },

    #' Initialize Temporal Analysis Structure
    init_temporal_analysis = function() {
      list(
        escalation_indicators = list(),
        timeline_events = list(),
        # "acute_escalation", "chronic_pattern", "isolated_incident", "none"
        pattern_type = "none",
        time_to_death = NULL,
        critical_periods = list(),
        intervention_opportunities = list(),
        confidence = 0,
        last_updated = NULL
      )
    },

    #' Initialize Quality Metrics Structure
    init_quality_metrics = function() {
      list(
        overall_confidence = 0,
        data_completeness = 0,
        source_reliability = 0,
        analysis_flags = list(),
        validation_issues = list(),
        is_complete = FALSE,
        reviewer_notes = list()
      )
    },

    #' Recalculate Evidence Summary Statistics
    recalculate_evidence_summary = function() {
      if (length(self$evidence_matrix$items) == 0) {
        return(invisible(NULL))
      }

      items <- self$evidence_matrix$items
      weights <- vapply(items, function(x) x$weight, numeric(1))
      types <- vapply(items, function(x) x$type, character(1))

      self$evidence_matrix$summary <- list(
        total_items = length(items),
        high_weight_items = sum(weights > 0.7),
        type_diversity = length(unique(types)),
        average_weight = mean(weights),
        average_reliability = mean(vapply(items,
                                          function(x) x$reliability,
                                          numeric(1))),
        last_calculated = Sys.time()
      )

      invisible(self)
    },

    #' Calculate Overall Completeness Score
    calculate_completeness_score = function() {
      scores <- c(
        death_classification = ifelse(
          is.null(self$death_classification$primary), 0, 1
        ),
        directionality = ifelse(
          is.null(self$directionality$primary_direction), 0, 1
        ),
        evidence_items = min(1, length(self$evidence_matrix$items) / 5),
        source_data = ifelse(
          is.null(self$source_narratives$le) &&
            is.null(self$source_narratives$cme), 0, 1
        )
      )

      mean(scores)
    }
  )
)

#' Create IPV Forensic Analysis Collection
#'
#' @description
#' Factory function to create and manage multiple IPVForensicResult instances
#' for batch analysis operations.
#'
#' @param incident_ids Vector of incident IDs
#' @param data_source Data source (tibble or data.frame) with narratives
#' @return IPVForensicCollection object
#' @export
create_forensic_collection <- function(incident_ids, data_source = NULL) {

  # Validate inputs
  if (length(incident_ids) == 0) {
    stop("No incident IDs provided")
  }

  # Create collection environment for proper method binding
  collection_env <- new.env(parent = emptyenv())
  
  # Initialize collection data
  collection_env$incidents <- list()
  collection_env$metadata <- list(
    created = Sys.time(),
    total_incidents = length(incident_ids),
    completed_analyses = 0,
    version = "1.0.0"
  )
  
  # Create collection object with methods
  collection <- list(
    incidents = collection_env$incidents,
    metadata = collection_env$metadata,

    # Collection methods
    add_analysis = function(forensic_result) {
      incident_id <- forensic_result$incident_id
      collection_env$incidents[[incident_id]] <- forensic_result
      collection_env$metadata$completed_analyses <- length(collection_env$incidents)
      # Update references
      collection$incidents <<- collection_env$incidents
      collection$metadata <<- collection_env$metadata
      invisible(collection)
    },

    get_analysis = function(incident_id) {
      collection_env$incidents[[incident_id]]
    },

    get_summary_tibble = function() {
      if (length(collection_env$incidents) == 0) {
        return(tibble::tibble())
      }

      summary_list <- lapply(collection_env$incidents, function(x) x$to_tibble())
      dplyr::bind_rows(summary_list)
    },

    validate_collection = function() {
      validation_results <- lapply(
        collection_env$incidents, function(x) x$validate_analysis()
      )

      list(
        total_incidents = length(collection_env$incidents),
        valid_incidents = sum(vapply(validation_results,
                                     function(x) x$is_valid, logical(1))),
        average_completeness = mean(vapply(validation_results,
                                           function(x) x$completeness_score,
                                           numeric(1))),
        common_issues = table(unlist(lapply(validation_results,
                                            function(x) x$issues)))
      )
    },

    export_for_analysis = function() {
      summary_tibble <- collection$get_summary_tibble()

      list(
        data = summary_tibble,
        metadata = collection_env$metadata,
        validation = collection$validate_collection()
      )
    }
  )

  # Initialize individual analyses if data source provided
  if (!is.null(data_source)) {
    for (id in incident_ids) {
      row_data <- data_source[data_source$IncidentID == id, ]
      if (nrow(row_data) > 0) {
        le_narrative <- if (is.na(row_data$NarrativeLE[1])) NULL else row_data$NarrativeLE[1]
        cme_narrative <- if (is.na(row_data$NarrativeCME[1])) NULL else row_data$NarrativeCME[1]
        
        forensic_result <- ipv_forensic_result$new(
          incident_id = id,
          le_narrative = le_narrative,
          cme_narrative = cme_narrative
        )
        collection$add_analysis(forensic_result)
      }
    }
  }

  class(collection) <- c("IPVForensicCollection", "list")
  collection
}

#' Print Method for IPV Forensic Result
#' @export
print.IPVForensicResult <- function(x, ...) {
  cat("IPV Forensic Analysis Result\n")
  cat("============================\n")
  cat("Incident ID:", x$incident_id, "\n")
  cat("Analysis Time:", as.character(x$analysis_timestamp), "\n")
  cat("Death Classification:", x$death_classification$primary %||%
        "Not determined", "\n")
  cat("Primary Direction:", x$directionality$primary_direction, "\n")
  cat("Evidence Items:", length(x$evidence_matrix$items), "\n")

  validation <- x$validate_analysis()
  cat("Analysis Complete:", ifelse(validation$is_valid, "Yes", "No"), "\n")

  if (!validation$is_valid && length(validation$issues) > 0) {
    cat("Issues:", paste(validation$issues, collapse = ", "), "\n")
  }
}

#' Print Method for IPV Forensic Collection
#' @export
print.IPVForensicCollection <- function(x, ...) {
  cat("IPV Forensic Analysis Collection\n")
  cat("================================\n")
  cat("Total Incidents:", x$metadata$total_incidents, "\n")
  cat("Completed Analyses:", x$metadata$completed_analyses, "\n")
  cat("Created:", as.character(x$metadata$created), "\n")

  if (x$metadata$completed_analyses > 0) {
    validation <- x$validate_collection()
    cat("Valid Analyses:", validation$valid_incidents, "/",
        validation$total_incidents, "\n")
    cat("Average Completeness:", sprintf("%.2f",
                                         validation$average_completeness), "\n")
  }
}