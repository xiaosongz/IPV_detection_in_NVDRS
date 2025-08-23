#!/usr/bin/env Rscript

# REAL TEST WITH ACTUAL API CALLS
# This tests the forensic IPV analysis with actual LLM API calls

cat("=== REAL FORENSIC IPV ANALYSIS TEST ===\n")
cat("Testing with actual API calls to LM Studio\n\n")

# Load the package
library(nvdrsipvdetector)
library(httr2)

# Test API connectivity first
test_api_connection <- function() {
  cat("Testing API connectivity...\n")
  
  config <- load_config()
  base_url <- Sys.getenv("LM_STUDIO_URL", "http://192.168.10.22:1234/v1")
  
  tryCatch({
    # Test with a simple request
    test_resp <- httr2::request(paste0(base_url, "/models")) %>%
      httr2::req_timeout(5) %>%
      httr2::req_perform()
    
    if (httr2::resp_status(test_resp) == 200) {
      cat("✓ API is reachable at:", base_url, "\n\n")
      return(TRUE)
    }
  }, error = function(e) {
    cat("✗ API connection failed:", e$message, "\n")
    cat("Make sure LM Studio is running at:", base_url, "\n\n")
    return(FALSE)
  })
}

# Only proceed if API is available
if (!test_api_connection()) {
  cat("Cannot proceed without API connection\n")
  cat("Please start LM Studio and ensure it's accessible\n")
  quit(status = 1)
}

# Load configuration and enable forensic mode
config <- load_config()
config$processing$use_forensic_analysis <- TRUE

cat("Configuration loaded. Forensic mode:", 
    config$processing$use_forensic_analysis, "\n\n")

# REAL TEST CASES FROM NVDRS DATA

# Case 1: Clear homicide by intimate partner
case1_narrative <- "The victim was shot multiple times by her ex-boyfriend after she obtained a restraining order against him last week. Neighbors reported hearing him threaten to kill her if she didn't come back to him. He had previously strangled her during an argument two months ago. Police found text messages where he said 'If I can't have you, no one can.'"

# Case 2: Suicide used as weapon/control
case2_narrative <- "The decedent shot himself in front of his estranged wife at her parents' home during their daughter's birthday party. He had sent texts saying 'You'll be responsible for my death' and 'Everyone will know you drove me to this.' The wife had filed for divorce after years of financial control and emotional abuse."

# Case 3: Suicide as escape from abuse
case3_narrative <- "The deceased female died by hanging. Multiple healing fractures to ribs and defensive wounds on arms noted. Medical records show 5 ER visits in past year with injuries inconsistent with stated causes. Suicide note stated 'I can't take the beatings anymore. This is my only way out.'"

# TEST 1: Clear Homicide Pattern
cat("=====================================\n")
cat("TEST 1: HOMICIDE BY INTIMATE PARTNER\n")
cat("=====================================\n\n")

result1 <- tryCatch({
  detect_ipv_forensic(
    narrative = case1_narrative,
    type = "LE",
    config = config,
    log_to_db = FALSE
  )
}, error = function(e) {
  cat("Error in detect_ipv_forensic:", e$message, "\n")
  NULL
})

if (!is.null(result1)) {
  cat("API Response Received:\n")
  cat("Death Classification:", result1$death_classification$type, "\n")
  cat("Death Mechanism:", result1$death_classification$mechanism, "\n")
  cat("Directionality:", result1$directionality$primary_direction, "\n")
  cat("Confidence:", result1$directionality$confidence, "\n")
  cat("Perpetrator Indicators Found:", 
      length(result1$directionality$perpetrator_indicators$evidence), "\n")
  cat("Evidence:", paste(result1$directionality$perpetrator_indicators$evidence, 
                        collapse = ", "), "\n\n")
} else {
  cat("Failed to get result for Case 1\n\n")
}

# TEST 2: Coercive Suicide
cat("=====================================\n")
cat("TEST 2: SUICIDE AS WEAPON/CONTROL\n")
cat("=====================================\n\n")

result2 <- tryCatch({
  detect_ipv_forensic(
    narrative = case2_narrative,
    type = "LE",
    config = config,
    log_to_db = FALSE
  )
}, error = function(e) {
  cat("Error:", e$message, "\n")
  NULL
})

if (!is.null(result2)) {
  cat("API Response Received:\n")
  cat("Death Classification:", result2$death_classification$type, "\n")
  cat("Suicide Intent:", result2$suicide_analysis$intent, "\n")
  cat("Suicide Method Type:", result2$suicide_analysis$method, "\n")
  cat("Directionality:", result2$directionality$primary_direction, "\n")
  cat("Precipitating Factors:", 
      paste(result2$suicide_analysis$precipitating_factors, collapse = ", "), "\n\n")
} else {
  cat("Failed to get result for Case 2\n\n")
}

# TEST 3: Suicide as Escape
cat("=====================================\n")
cat("TEST 3: SUICIDE AS ESCAPE FROM ABUSE\n")
cat("=====================================\n\n")

result3 <- tryCatch({
  detect_ipv_forensic(
    narrative = case3_narrative,
    type = "CME",
    config = config,
    log_to_db = FALSE
  )
}, error = function(e) {
  cat("Error:", e$message, "\n")
  NULL
})

if (!is.null(result3)) {
  cat("API Response Received:\n")
  cat("Death Classification:", result3$death_classification$type, "\n")
  cat("Suicide Intent:", result3$suicide_analysis$intent, "\n")
  cat("Suicide Method Type:", result3$suicide_analysis$method, "\n")
  cat("Directionality:", result3$directionality$primary_direction, "\n")
  cat("Victim Indicators Found:", 
      length(result3$directionality$victim_indicators$evidence), "\n")
  cat("Physical Evidence Weight:", result3$evidence_matrix$physical$weight, "\n")
  cat("Temporal Pattern:", result3$temporal_patterns$pattern_type, "\n\n")
} else {
  cat("Failed to get result for Case 3\n\n")
}

# Summary
cat("=====================================\n")
cat("ANALYSIS SUMMARY\n")
cat("=====================================\n\n")

if (!is.null(result1) && !is.null(result2) && !is.null(result3)) {
  cat("✓ All three cases analyzed successfully\n")
  cat("✓ Forensic analysis is working with API\n\n")
  
  cat("Key Findings:\n")
  cat("- Case 1 Directionality:", result1$directionality$primary_direction, "\n")
  cat("- Case 2 Suicide Intent:", result2$suicide_analysis$intent, 
      "(", result2$suicide_analysis$method, ")\n")
  cat("- Case 3 Suicide Intent:", result3$suicide_analysis$intent,
      "(", result3$suicide_analysis$method, ")\n")
} else {
  cat("✗ Some tests failed - check API connection and configuration\n")
}

cat("\n=== END OF REAL API TEST ===\n")