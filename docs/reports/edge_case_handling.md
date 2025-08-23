# Edge Case Handling for IPV Detection

## Systematic Fallback Strategy

### Empty/Minimal Narratives
**Trigger**: Narrative <50 characters or only administrative text
**Response**: 
```json
{
  "ipv_detected": false,
  "confidence": 0.0,
  "evidence_found": [],
  "data_quality": {
    "narrative_completeness": 0.0,
    "missing_critical_info": ["entire narrative content"],
    "confidence_factors": "insufficient narrative content for analysis"
  }
}
```

### Contradictory Evidence
**Trigger**: Physical evidence conflicts with stated circumstances
**Logic**:
1. Identify specific contradictions
2. Lower confidence by 0.1-0.3 per major contradiction  
3. Flag in "contradictions" array
4. If contradictions exceed 30% of total evidence → mark as "undetermined"

### Missing Critical Information
**Common gaps**:
- No injury description in homicide case (-0.2 confidence)
- No weapon information (-0.1 confidence)
- No timeline of events (-0.1 confidence)
- Missing witness statements (-0.15 confidence)

**Handling**: Explicitly list in "missing_critical_info" array, adjust confidence accordingly

### Conflicting LE vs CME Results
**Current weighted average approach is flawed**

**Improved reconciliation logic**:
```
IF confidence_difference > 0.4:
    flag_for_manual_review = TRUE
    final_confidence = MIN(le_confidence, cme_confidence) * 0.8
    
IF both_sources_agree_on_ipv_detected:
    final_confidence = MAX(le_confidence, cme_confidence)
    
IF sources_disagree_on_ipv_detected:
    final_confidence = 0.3 + (higher_confidence * 0.3)
    flag_conflict = TRUE
```

## Malformed JSON Recovery

### Strategy
1. **First attempt**: Standard JSON parsing
2. **Second attempt**: Extract key-value pairs using regex
3. **Third attempt**: Return error structure with raw response logged

### Fallback JSON Structure
```json
{
  "ipv_detected": null,
  "confidence": 0.0,
  "parsing_error": true,
  "raw_response_logged": true,
  "data_quality": {
    "narrative_completeness": "unknown",
    "confidence_factors": "LLM response parsing failed"
  }
}
```