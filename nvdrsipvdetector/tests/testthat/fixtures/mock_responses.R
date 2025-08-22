# tests/testthat/fixtures/mock_responses.R
mock_llm_response <- function(ipv_detected = TRUE) {
  list(
    ipv_detected = ipv_detected,
    confidence = 0.85,
    indicators = c("domestic", "ex-boyfriend"),
    rationale = "Mock response"
  )
}

# Test with:
# - Empty narratives
# - Malformed JSON responses  
# - API timeouts
# - Conflicting LE/CME results
# - Database write failures