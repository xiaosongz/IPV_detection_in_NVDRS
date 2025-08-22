#' Combine LE/CME Results
#'
#' @description Functions for reconciling LE and CME detection results
#' @keywords internal
NULL

#' Reconcile LE and CME
#'
#' @param le_result LE detection result
#' @param cme_result CME detection result
#' @param weights List with le and cme weight values
#' @param threshold Decision threshold (default 0.7)
#' @return Reconciled result
#' @export
reconcile_le_cme <- function(le_result, cme_result, weights, threshold = 0.7) {
  # Handle missing results
  if (is.na(le_result$ipv_detected) && is.na(cme_result$ipv_detected)) {
    return(list(
      ipv_detected = NA,
      confidence = NA,
      rationale = "No narratives available"
    ))
  }
  
  if (is.na(le_result$ipv_detected)) {
    return(cme_result)
  }
  
  if (is.na(cme_result$ipv_detected)) {
    return(le_result)
  }
  
  # Both available - weighted average
  combined_confidence <- le_result$confidence * weights$le + 
                        cme_result$confidence * weights$cme
  
  ipv_detected <- combined_confidence >= threshold
  
  return(list(
    ipv_detected = ipv_detected,
    confidence = combined_confidence,
    final_decision = ipv_detected,  # Add expected field name
    confidence_score = combined_confidence,  # Add expected field name
    le_ipv = le_result$ipv_detected,
    le_confidence = le_result$confidence,
    cme_ipv = cme_result$ipv_detected,
    cme_confidence = cme_result$confidence,
    rationale = sprintf("LE: %.0f%%, CME: %.0f%%, Combined: %.0f%%",
                       le_result$confidence * 100,
                       cme_result$confidence * 100,
                       combined_confidence * 100)
  ))
}

#' Calculate Agreement (Modernized)
#'
#' @param results Tibble with le_ipv and cme_ipv columns
#' @return Agreement statistics tibble
#' @export
calculate_agreement <- function(results) {
  # Convert to tibble and filter valid records
  valid_results <- results %>%
    tibble::as_tibble() %>%
    dplyr::filter(!is.na(le_ipv) & !is.na(cme_ipv))
  
  if (nrow(valid_results) == 0) {
    return(tibble::tibble(
      n = 0L,
      agreement_rate = NA_real_,
      both_positive = 0L,
      both_negative = 0L,
      le_only = 0L,
      cme_only = 0L
    ))
  }
  
  # Calculate agreement statistics using dplyr
  valid_results %>%
    dplyr::summarise(
      n = dplyr::n(),
      agreement_rate = mean(le_ipv == cme_ipv),
      both_positive = sum(le_ipv & cme_ipv),
      both_negative = sum(!le_ipv & !cme_ipv),
      le_only = sum(le_ipv & !cme_ipv),
      cme_only = sum(!le_ipv & cme_ipv),
      .groups = "drop"
    )
}