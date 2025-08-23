# Demonstration of Advanced Forensic IPV Analysis
# This showcases the directionality assessment and suicide intent classification

library(nvdrsipvdetector)

# Example narratives with complex IPV dynamics
cat("=== FORENSIC IPV ANALYSIS DEMONSTRATION ===\n\n")

# Case 1: Clear perpetrator-to-victim homicide
le_narrative_1 <- "The victim was shot multiple times by her ex-boyfriend after she obtained a restraining order against him last week. Neighbors reported hearing him threaten to kill her if she didn't come back to him. He had previously strangled her during an argument two months ago, which led to his arrest. Police found text messages where he said 'If I can't have you, no one can.' He waited outside her workplace and shot her as she was leaving."

# Case 2: Coercive suicide (perpetrator using suicide as weapon)
le_narrative_2 <- "The decedent shot himself in front of his estranged wife at her parents' home during their daughter's birthday party. He had sent multiple texts saying 'You'll be responsible for my death' and 'Everyone will know you drove me to this.' The wife had filed for divorce after years of financial control and emotional abuse. He timed the suicide to occur when maximum family members would witness it."

# Case 3: Desperation suicide (victim escaping abuse)
cme_narrative_3 <- "The deceased female, age 32, died by hanging. Multiple healing fractures to ribs and defensive wounds on arms noted. Medical records show 5 ER visits in past year with injuries inconsistent with stated causes. Found suicide note stating 'I can't take the beatings anymore. This is my only way out. Please protect my children.' No blame toward partner expressed."

# Case 4: Bidirectional violence with primary aggressor
le_narrative_4 <- "Both partners had history of physical altercations. However, the male decedent had three prior domestic violence convictions, while the female partner's only arrest was for defending herself with a knife when he was choking her. He controlled all finances and her immigration status. She had multiple documented injuries requiring hospitalization. He died by suicide after she successfully escaped to a shelter."

cat("CASE 1: Clear Perpetrator-to-Victim Pattern\n")
cat("--------------------------------------------\n")

# Load configuration (with forensic mode enabled)
config <- load_config()

# Ensure forensic mode is on
config$processing$use_forensic_analysis <- TRUE

# Analyze Case 1
if (exists("detect_ipv_forensic")) {
  result1 <- detect_ipv_forensic(
    narrative = le_narrative_1,
    type = "LE",
    config = config,
    log_to_db = FALSE
  )
  
  cat("Death Classification:", result1$death_classification$type, "\n")
  cat("Directionality:", result1$directionality$primary_direction, "\n")
  cat("Confidence:", result1$directionality$confidence, "\n\n")
} else {
  cat("Forensic analysis function not yet loaded\n\n")
}

cat("CASE 2: Coercive Suicide (Perpetrator)\n")
cat("---------------------------------------\n")

if (exists("detect_ipv_forensic")) {
  result2 <- detect_ipv_forensic(
    narrative = le_narrative_2,
    type = "LE",
    config = config,
    log_to_db = FALSE
  )
  
  cat("Death Classification:", result2$death_classification$type, "\n")
  cat("Suicide Intent:", result2$suicide_analysis$intent, "\n")
  cat("Suicide Method:", result2$suicide_analysis$method, "\n")
  cat("Directionality:", result2$directionality$primary_direction, "\n\n")
}

cat("CASE 3: Desperation Suicide (Victim)\n")
cat("-------------------------------------\n")

if (exists("detect_ipv_forensic")) {
  result3 <- detect_ipv_forensic(
    narrative = cme_narrative_3,
    type = "CME",
    config = config,
    log_to_db = FALSE
  )
  
  cat("Death Classification:", result3$death_classification$type, "\n")
  cat("Suicide Intent:", result3$suicide_analysis$intent, "\n")
  cat("Suicide Method:", result3$suicide_analysis$method, "\n")
  cat("Evidence of Prior Abuse:", 
      length(result3$directionality$victim_indicators$evidence) > 0, "\n\n")
}

cat("CASE 4: Bidirectional Violence\n")
cat("-------------------------------\n")

if (exists("detect_ipv_forensic")) {
  result4 <- detect_ipv_forensic(
    narrative = le_narrative_4,
    type = "LE",
    config = config,
    log_to_db = FALSE
  )
  
  cat("Bidirectional Score:", result4$directionality$bidirectional_score, "\n")
  cat("Primary Direction:", result4$directionality$primary_direction, "\n")
  cat("Temporal Pattern:", result4$temporal_patterns$pattern_type, "\n\n")
}

cat("=== KEY FORENSIC INSIGHTS ===\n")
cat("1. Directionality matters - not all deaths with IPV history have the decedent as victim\n")
cat("2. Suicide can be weaponized as a form of perpetration\n")
cat("3. Bidirectional violence requires primary aggressor identification\n")
cat("4. Evidence hierarchy helps weight different information sources\n")
cat("5. Temporal patterns reveal escalation dynamics\n\n")

# Demonstrate evidence weighting
cat("=== EVIDENCE WEIGHTING SYSTEM ===\n")
cat("Physical Evidence Weight: 0.9 (medical records, injuries)\n")
cat("Behavioral Evidence Weight: 0.7 (witnessed threats, patterns)\n")
cat("Contextual Evidence Weight: 0.5 (relationship dynamics)\n")
cat("Circumstantial Evidence Weight: 0.3 (single accounts)\n\n")

# Show how to process batch with forensic analysis
cat("=== BATCH PROCESSING ===\n")
cat("For batch processing with forensic analysis:\n")
cat("results <- nvdrs_process_batch_forensic(data, config)\n")
cat("\nResults will include:\n")
cat("- death_type\n")
cat("- directionality_primary\n")
cat("- suicide_intent\n")
cat("- suicide_method\n")
cat("- temporal_pattern\n")
cat("- analysis_confidence\n")