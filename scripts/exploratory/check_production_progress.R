#!/usr/bin/env Rscript

# Check production 20k database progress and detection rates

library(DBI)
library(RSQLite)
library(dplyr)
library(here)
library(lubridate)

# Connect to database
db_path <- here("data", "production_20k.db")
cat("Connecting to database:", db_path, "\n")

if (!file.exists(db_path)) {
  stop("Production database not found: ", db_path)
}

conn <- dbConnect(RSQLite::SQLite(), db_path)

# Get experiment info
cat("\n=== EXPERIMENT STATUS ===\n")
exp_info <- dbGetQuery(conn, "
  SELECT 
    experiment_id,
    experiment_name,
    status,
    model_name,
    start_time,
    end_time,
    n_narratives_total,
    n_narratives_processed,
    n_narratives_completed,
    n_positive_detected,
    n_negative_detected,
    precision_ipv,
    recall_ipv,
    f1_ipv
  FROM experiments
  ORDER BY created_at DESC
")

print(exp_info)

# Get narrative processing progress
cat("\n=== NARRATIVE PROCESSING PROGRESS ===\n")
progress <- dbGetQuery(conn, "
  SELECT 
    narrative_type,
    COUNT(*) as total,
    SUM(CASE WHEN processed_at IS NOT NULL THEN 1 ELSE 0 END) as processed,
    SUM(CASE WHEN detected IS NOT NULL THEN 1 ELSE 0 END) as has_detection,
    SUM(CASE WHEN error_occurred = 1 THEN 1 ELSE 0 END) as errors,
    ROUND(AVG(CASE WHEN processed_at IS NOT NULL THEN 1 ELSE 0 END) * 100, 2) as completion_pct
  FROM narrative_results
  GROUP BY narrative_type
")

print(progress)

# Overall detection rates
cat("\n=== DETECTION RATES ===\n")
detection_summary <- dbGetQuery(conn, "
  SELECT 
    COUNT(*) as total_processed,
    SUM(detected) as total_positive,
    COUNT(*) - SUM(detected) as total_negative,
    ROUND(AVG(detected) * 100, 2) as detection_rate_pct,
    ROUND(AVG(confidence), 3) as avg_confidence
  FROM narrative_results
  WHERE detected IS NOT NULL
")

print(detection_summary)

# Detection by narrative type
cat("\n=== DETECTION BY NARRATIVE TYPE ===\n")
detection_by_type <- dbGetQuery(conn, "
  SELECT 
    narrative_type,
    COUNT(*) as total,
    SUM(detected) as positive,
    COUNT(*) - SUM(detected) as negative,
    ROUND(AVG(detected) * 100, 2) as detection_rate_pct,
    ROUND(AVG(CASE WHEN detected = 1 THEN confidence END), 3) as avg_confidence_positive,
    ROUND(AVG(CASE WHEN detected = 0 THEN confidence END), 3) as avg_confidence_negative
  FROM narrative_results
  WHERE detected IS NOT NULL
  GROUP BY narrative_type
")

print(detection_by_type)

# Recent progress (last 100 records)
cat("\n=== RECENT PROGRESS (Last 100 processed) ===\n")
recent <- dbGetQuery(conn, "
  SELECT 
    narrative_type,
    incident_id,
    detected,
    confidence,
    processed_at,
    response_sec
  FROM narrative_results
  WHERE processed_at IS NOT NULL
  ORDER BY processed_at DESC
  LIMIT 10
")

print(recent)

# Processing speed
cat("\n=== PROCESSING SPEED ===\n")
speed <- dbGetQuery(conn, "
  SELECT 
    COUNT(*) as total_processed,
    MIN(response_sec) as min_sec,
    MAX(response_sec) as max_sec,
    ROUND(AVG(response_sec), 2) as avg_sec,
    ROUND(MEDIAN(response_sec), 2) as median_sec
  FROM narrative_results
  WHERE response_sec IS NOT NULL
")

print(speed)

# Check for any errors
cat("\n=== ERRORS ===\n")
errors <- dbGetQuery(conn, "
  SELECT 
    COUNT(*) as error_count,
    error_message
  FROM narrative_results
  WHERE error_occurred = 1
    AND error_message IS NOT NULL
  GROUP BY error_message
  ORDER BY error_count DESC
  LIMIT 5
")

if (nrow(errors) > 0) {
  print(errors)
} else {
  cat("No errors found.\n")
}

# Time series of progress
cat("\n=== PROGRESS TIMELINE ===\n")
timeline <- dbGetQuery(conn, "
  SELECT 
    DATE(processed_at) as date,
    narrative_type,
    COUNT(*) as count
  FROM narrative_results
  WHERE processed_at IS NOT NULL
  GROUP BY DATE(processed_at), narrative_type
  ORDER BY date DESC, narrative_type
  LIMIT 20
")

print(timeline)

# Close connection
dbDisconnect(conn)

cat("\n=== CHECK COMPLETE ===\n")
