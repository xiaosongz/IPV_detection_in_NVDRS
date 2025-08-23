-- Enhanced Test Tracking Database Schema for IPV Detection System
-- This schema extends the basic api_logs table with comprehensive test tracking capabilities

-- Existing table: api_logs (keep as is)
CREATE TABLE IF NOT EXISTS api_logs (
  request_id TEXT PRIMARY KEY,
  incident_id TEXT NOT NULL,
  timestamp INTEGER NOT NULL,
  prompt_type TEXT CHECK(prompt_type IN ('LE', 'CME', 'LE_FORENSIC', 'CME_FORENSIC')),
  prompt_text TEXT NOT NULL,
  raw_response TEXT,
  parsed_response TEXT,
  response_time_ms INTEGER,
  error TEXT
);

-- Test Run Metadata: Track different test runs with parameters
CREATE TABLE IF NOT EXISTS test_runs (
  run_id TEXT PRIMARY KEY,
  run_name TEXT NOT NULL,
  run_timestamp INTEGER NOT NULL,
  prompt_version_id TEXT NOT NULL,
  model_name TEXT NOT NULL,
  model_version TEXT,
  config_hash TEXT NOT NULL, -- SHA256 of config to detect changes
  test_set_name TEXT NOT NULL,
  test_set_size INTEGER NOT NULL,
  description TEXT,
  status TEXT CHECK(status IN ('running', 'completed', 'failed', 'cancelled')) DEFAULT 'running',
  started_by TEXT,
  completed_timestamp INTEGER,
  total_processing_time_ms INTEGER,
  FOREIGN KEY (prompt_version_id) REFERENCES prompt_versions(version_id)
);

-- Prompt Version Tracking: Version control for prompts
CREATE TABLE IF NOT EXISTS prompt_versions (
  version_id TEXT PRIMARY KEY,
  version_name TEXT NOT NULL,
  version_number TEXT NOT NULL, -- e.g., "1.0.0", "1.1.0-beta"
  prompt_type TEXT CHECK(prompt_type IN ('LE', 'CME', 'forensic', 'combined')) NOT NULL,
  prompt_text TEXT NOT NULL,
  system_prompt TEXT,
  template_variables TEXT, -- JSON of variables used in template
  weights TEXT, -- JSON of LE/CME weights and threshold
  created_timestamp INTEGER NOT NULL,
  created_by TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  notes TEXT
);

-- Classification Results: Store predictions for each incident
CREATE TABLE IF NOT EXISTS test_results (
  result_id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL,
  incident_id TEXT NOT NULL,
  narrative_type TEXT CHECK(narrative_type IN ('LE', 'CME')) NOT NULL,
  predicted_ipv BOOLEAN,
  predicted_confidence REAL CHECK(predicted_confidence >= 0 AND predicted_confidence <= 1),
  actual_ipv BOOLEAN, -- ground truth
  indicators TEXT, -- JSON array of detected indicators
  rationale TEXT,
  processing_time_ms INTEGER,
  token_count INTEGER,
  prompt_tokens INTEGER,
  completion_tokens INTEGER,
  api_cost REAL, -- if tracking costs
  error_message TEXT,
  created_timestamp INTEGER NOT NULL,
  FOREIGN KEY (run_id) REFERENCES test_runs(run_id),
  UNIQUE(run_id, incident_id, narrative_type)
);

-- Performance Metrics: Aggregated metrics per test run
CREATE TABLE IF NOT EXISTS performance_metrics (
  metric_id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL,
  narrative_type TEXT CHECK(narrative_type IN ('LE', 'CME', 'combined')),
  accuracy REAL CHECK(accuracy >= 0 AND accuracy <= 1),
  precision REAL CHECK(precision >= 0 AND precision <= 1),
  recall REAL CHECK(recall >= 0 AND recall <= 1),
  f1_score REAL CHECK(f1_score >= 0 AND f1_score <= 1),
  specificity REAL CHECK(specificity >= 0 AND specificity <= 1),
  auc_roc REAL CHECK(auc_roc >= 0 AND auc_roc <= 1),
  true_positives INTEGER DEFAULT 0,
  true_negatives INTEGER DEFAULT 0,
  false_positives INTEGER DEFAULT 0,
  false_negatives INTEGER DEFAULT 0,
  total_cases INTEGER,
  avg_confidence_correct REAL, -- average confidence for correct predictions
  avg_confidence_incorrect REAL, -- average confidence for incorrect predictions
  avg_processing_time_ms REAL,
  total_token_usage INTEGER,
  total_api_cost REAL,
  calculated_timestamp INTEGER NOT NULL,
  FOREIGN KEY (run_id) REFERENCES test_runs(run_id)
);

-- Error Analysis: Track patterns in misclassifications
CREATE TABLE IF NOT EXISTS error_analysis (
  error_id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL,
  incident_id TEXT NOT NULL,
  narrative_type TEXT CHECK(narrative_type IN ('LE', 'CME')) NOT NULL,
  error_type TEXT CHECK(error_type IN ('false_positive', 'false_negative', 'low_confidence_correct', 'high_confidence_incorrect')) NOT NULL,
  predicted_ipv BOOLEAN,
  actual_ipv BOOLEAN,
  predicted_confidence REAL,
  misclassification_reason TEXT, -- manual classification of why it failed
  narrative_length INTEGER,
  narrative_complexity_score REAL, -- computed complexity measure
  key_indicators_missed TEXT, -- JSON array of indicators that should have been detected
  false_indicators TEXT, -- JSON array of indicators that were incorrectly detected
  reviewer_notes TEXT,
  flagged_for_review BOOLEAN DEFAULT FALSE,
  review_priority TEXT CHECK(review_priority IN ('low', 'medium', 'high', 'critical')) DEFAULT 'medium',
  created_timestamp INTEGER NOT NULL,
  FOREIGN KEY (run_id) REFERENCES test_runs(run_id)
);

-- Confidence Calibration: Track how well confidence scores predict accuracy
CREATE TABLE IF NOT EXISTS confidence_calibration (
  calibration_id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL,
  confidence_bin_start REAL NOT NULL, -- e.g., 0.8 for 80-90% confidence bin
  confidence_bin_end REAL NOT NULL,   -- e.g., 0.9
  bin_center REAL NOT NULL,           -- e.g., 0.85
  prediction_count INTEGER DEFAULT 0,
  correct_predictions INTEGER DEFAULT 0,
  accuracy_in_bin REAL,               -- correct_predictions / prediction_count
  avg_confidence_in_bin REAL,
  calibration_error REAL,             -- |accuracy_in_bin - bin_center|
  narrative_type TEXT CHECK(narrative_type IN ('LE', 'CME', 'combined')),
  calculated_timestamp INTEGER NOT NULL,
  FOREIGN KEY (run_id) REFERENCES test_runs(run_id)
);

-- Indicator Analysis: Track effectiveness of different IPV indicators
CREATE TABLE IF NOT EXISTS indicator_analysis (
  indicator_id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL,
  indicator_name TEXT NOT NULL,
  indicator_category TEXT CHECK(indicator_category IN ('physical', 'behavioral', 'contextual', 'temporal', 'linguistic')) NOT NULL,
  detection_count INTEGER DEFAULT 0,  -- how many times this indicator was detected
  true_positive_count INTEGER DEFAULT 0, -- correctly detected in positive cases
  false_positive_count INTEGER DEFAULT 0, -- detected in negative cases
  precision_score REAL,               -- tp / (tp + fp)
  recall_in_positives REAL,           -- tp / total_positives_with_indicator
  avg_confidence_when_detected REAL,
  narrative_type TEXT CHECK(narrative_type IN ('LE', 'CME', 'combined')),
  calculated_timestamp INTEGER NOT NULL,
  FOREIGN KEY (run_id) REFERENCES test_runs(run_id)
);

-- Narrative Quality Metrics: Assess narrative quality vs accuracy
CREATE TABLE IF NOT EXISTS narrative_quality (
  quality_id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL,
  incident_id TEXT NOT NULL,
  narrative_type TEXT CHECK(narrative_type IN ('LE', 'CME')) NOT NULL,
  length_chars INTEGER,
  length_words INTEGER,
  length_sentences INTEGER,
  readability_score REAL,             -- Flesch reading ease or similar
  completeness_score REAL,            -- 0-1, how complete the narrative seems
  detail_level TEXT CHECK(detail_level IN ('minimal', 'basic', 'detailed', 'comprehensive')),
  contains_timeline BOOLEAN DEFAULT FALSE,
  contains_witness_info BOOLEAN DEFAULT FALSE,
  contains_physical_evidence BOOLEAN DEFAULT FALSE,
  contains_prior_incidents BOOLEAN DEFAULT FALSE,
  medical_terminology_count INTEGER DEFAULT 0,
  legal_terminology_count INTEGER DEFAULT 0,
  prediction_accuracy BOOLEAN,        -- was the prediction correct for this narrative?
  confidence_level REAL,
  created_timestamp INTEGER NOT NULL,
  FOREIGN KEY (run_id) REFERENCES test_runs(run_id)
);

-- A/B Testing Support: Compare different approaches
CREATE TABLE IF NOT EXISTS ab_tests (
  test_id TEXT PRIMARY KEY,
  test_name TEXT NOT NULL,
  variant_a_run_id TEXT NOT NULL,
  variant_b_run_id TEXT NOT NULL,
  test_metric TEXT NOT NULL, -- 'accuracy', 'f1_score', 'precision', etc.
  variant_a_score REAL,
  variant_b_score REAL,
  statistical_significance REAL, -- p-value
  effect_size REAL,
  winner TEXT CHECK(winner IN ('A', 'B', 'tie', 'inconclusive')),
  test_power REAL,                    -- statistical power of the test
  sample_size INTEGER,
  created_timestamp INTEGER NOT NULL,
  completed_timestamp INTEGER,
  notes TEXT,
  FOREIGN KEY (variant_a_run_id) REFERENCES test_runs(run_id),
  FOREIGN KEY (variant_b_run_id) REFERENCES test_runs(run_id)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_test_results_run_incident ON test_results(run_id, incident_id);
CREATE INDEX IF NOT EXISTS idx_test_results_accuracy ON test_results(run_id, predicted_ipv, actual_ipv);
CREATE INDEX IF NOT EXISTS idx_error_analysis_type ON error_analysis(run_id, error_type);
CREATE INDEX IF NOT EXISTS idx_performance_metrics_run ON performance_metrics(run_id, narrative_type);
CREATE INDEX IF NOT EXISTS idx_test_runs_timestamp ON test_runs(run_timestamp);
CREATE INDEX IF NOT EXISTS idx_prompt_versions_active ON prompt_versions(is_active, prompt_type);
CREATE INDEX IF NOT EXISTS idx_narrative_quality_accuracy ON narrative_quality(run_id, prediction_accuracy);
CREATE INDEX IF NOT EXISTS idx_confidence_calibration ON confidence_calibration(run_id, confidence_bin_start, confidence_bin_end);
CREATE INDEX IF NOT EXISTS idx_indicator_analysis ON indicator_analysis(run_id, indicator_name, indicator_category);

-- Views for common queries
CREATE VIEW IF NOT EXISTS test_run_summary AS
SELECT 
    tr.run_id,
    tr.run_name,
    tr.run_timestamp,
    tr.model_name,
    pv.version_name as prompt_version,
    tr.test_set_size,
    pm_combined.accuracy as overall_accuracy,
    pm_combined.f1_score as overall_f1,
    pm_le.accuracy as le_accuracy,
    pm_cme.accuracy as cme_accuracy,
    tr.total_processing_time_ms,
    tr.status
FROM test_runs tr
LEFT JOIN prompt_versions pv ON tr.prompt_version_id = pv.version_id
LEFT JOIN performance_metrics pm_combined ON tr.run_id = pm_combined.run_id AND pm_combined.narrative_type = 'combined'
LEFT JOIN performance_metrics pm_le ON tr.run_id = pm_le.run_id AND pm_le.narrative_type = 'LE'
LEFT JOIN performance_metrics pm_cme ON tr.run_id = pm_cme.run_id AND pm_cme.narrative_type = 'CME'
ORDER BY tr.run_timestamp DESC;

CREATE VIEW IF NOT EXISTS misclassification_patterns AS
SELECT 
    ea.run_id,
    ea.error_type,
    ea.narrative_type,
    COUNT(*) as error_count,
    AVG(ea.predicted_confidence) as avg_confidence,
    AVG(nq.length_words) as avg_narrative_length,
    AVG(nq.completeness_score) as avg_completeness,
    GROUP_CONCAT(DISTINCT ea.misclassification_reason, '; ') as common_reasons
FROM error_analysis ea
LEFT JOIN narrative_quality nq ON ea.run_id = nq.run_id 
    AND ea.incident_id = nq.incident_id 
    AND ea.narrative_type = nq.narrative_type
GROUP BY ea.run_id, ea.error_type, ea.narrative_type;

CREATE VIEW IF NOT EXISTS confidence_vs_accuracy AS
SELECT 
    tr.run_id,
    tr.narrative_type,
    CASE 
        WHEN tr.predicted_confidence < 0.3 THEN 'Low (<0.3)'
        WHEN tr.predicted_confidence < 0.5 THEN 'Low-Med (0.3-0.5)'
        WHEN tr.predicted_confidence < 0.7 THEN 'Medium (0.5-0.7)'
        WHEN tr.predicted_confidence < 0.9 THEN 'High (0.7-0.9)'
        ELSE 'Very High (0.9+)'
    END as confidence_range,
    COUNT(*) as prediction_count,
    SUM(CASE WHEN tr.predicted_ipv = tr.actual_ipv THEN 1 ELSE 0 END) as correct_count,
    CAST(SUM(CASE WHEN tr.predicted_ipv = tr.actual_ipv THEN 1 ELSE 0 END) AS REAL) / COUNT(*) as accuracy_in_range,
    AVG(tr.predicted_confidence) as avg_confidence
FROM test_results tr
WHERE tr.predicted_confidence IS NOT NULL 
    AND tr.actual_ipv IS NOT NULL
GROUP BY tr.run_id, tr.narrative_type, confidence_range;