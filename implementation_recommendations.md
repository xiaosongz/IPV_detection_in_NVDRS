# Implementation Recommendations for IPV Detection Optimization

## 1. Immediate Changes (High Impact, Low Risk)

### Update settings.yml
- Replace forensic_template with optimized version
- Adjust weights: CME=0.65, LE=0.35, threshold=0.6
- Add evidence-specific reliability scores

### Add Validation Layer
```r
validate_llm_response <- function(response) {
  required_fields <- c("ipv_detected", "confidence", "evidence_found")
  
  if (!all(required_fields %in% names(response))) {
    return(create_error_response("Missing required fields"))
  }
  
  if (response$confidence < 0 || response$confidence > 1) {
    return(create_error_response("Invalid confidence score"))
  }
  
  return(response)
}
```

## 2. Medium-term Changes (Moderate Impact, Moderate Risk)

### Implement Dynamic Evidence Weighting
```r
calculate_evidence_score <- function(evidence_list) {
  total_weight <- 0
  total_reliability <- 0
  
  for (evidence in evidence_list) {
    weight <- get_evidence_weight(evidence$type, evidence$item)
    reliability <- evidence$reliability_score
    total_weight <- total_weight + (weight * reliability)
    total_reliability <- total_reliability + weight
  }
  
  return(total_weight / total_reliability)
}

get_evidence_weight <- function(type, item) {
  weights_map <- list(
    "strangulation_marks" = 0.95,
    "defensive_wounds" = 0.90,
    "restraining_orders" = 0.85,
    # ... more mappings
  )
  
  return(weights_map[[item]] %||% 0.5)  # Default moderate weight
}
```

### Enhanced Reconciliation Logic
```r
reconcile_results <- function(le_result, cme_result, config) {
  if (is.null(le_result) && is.null(cme_result)) {
    return(create_no_data_response())
  }
  
  if (!is.null(le_result) && !is.null(cme_result)) {
    confidence_diff <- abs(le_result$confidence - cme_result$confidence)
    
    if (confidence_diff > 0.4) {
      return(create_conflict_flagged_response(le_result, cme_result))
    }
    
    # Use evidence-weighted approach instead of simple average
    return(evidence_weighted_reconciliation(le_result, cme_result))
  }
  
  # Single source
  return(validate_single_source_result(le_result %||% cme_result))
}
```

## 3. Long-term Enhancements (High Impact, Higher Risk)

### Adaptive Confidence Thresholds
- Monitor false positive/negative rates
- Adjust thresholds based on narrative type and quality
- Implement feedback loop from manual validation

### Multi-model Consensus
- Run critical cases through multiple LLM models
- Use ensemble voting for high-stakes decisions
- Fallback to human review when models disagree significantly

### Temporal Pattern Detection
- Track escalation patterns across time
- Weight recent evidence more heavily
- Identify trigger events (separations, legal actions)

## 4. Testing Strategy

### Unit Tests
- Test each evidence type with known reliability scores
- Validate edge case handling (empty narratives, contradictions)
- Verify JSON structure compliance

### Integration Tests  
- Test with real NVDRS narratives
- Compare against manual IPV flags
- Measure precision/recall across different confidence thresholds

### Performance Benchmarks
- Response time under different narrative lengths
- Memory usage with large batch processing
- API reliability under various failure conditions

## 5. Monitoring and Quality Control

### Automated Alerts
- Trigger when confidence scores cluster at extremes (0.0-0.1 or 0.9-1.0)
- Alert on high contradiction rates
- Flag when evidence scoring seems inconsistent

### Quality Metrics Dashboard
- Track confidence distribution over time
- Monitor evidence type frequency
- Measure prediction accuracy when validation data available

### Manual Review Triggers
- Confidence difference between LE/CME >0.5
- High contradiction count (>3 major conflicts)
- Low narrative completeness (<0.3) with high confidence
- Novel evidence types not in training patterns