-- Performance Analysis SQL Queries for IPV Detection Testing
-- These queries provide comprehensive analysis of model performance across test runs

-- 1. PERFORMANCE COMPARISON ACROSS TEST RUNS
-- Compare accuracy, precision, recall, F1 across different test runs
SELECT 
    tr.run_name,
    tr.model_name,
    pv.version_name as prompt_version,
    tr.test_set_size,
    pm.narrative_type,
    ROUND(pm.accuracy, 4) as accuracy,
    ROUND(pm.precision, 4) as precision,
    ROUND(pm.recall, 4) as recall,
    ROUND(pm.f1_score, 4) as f1_score,
    ROUND(pm.specificity, 4) as specificity,
    ROUND(pm.auc_roc, 4) as auc_roc,
    pm.true_positives,
    pm.false_positives,
    pm.true_negatives,
    pm.false_negatives,
    ROUND(pm.avg_processing_time_ms, 2) as avg_processing_time_ms,
    DATE(tr.run_timestamp, 'unixepoch') as run_date
FROM test_runs tr
JOIN performance_metrics pm ON tr.run_id = pm.run_id
JOIN prompt_versions pv ON tr.prompt_version_id = pv.version_id
WHERE tr.status = 'completed'
ORDER BY tr.run_timestamp DESC, pm.narrative_type;

-- 2. STATISTICAL SIGNIFICANCE TESTING BETWEEN RUNS
-- Chi-square test components for comparing two test runs
WITH run_comparison AS (
    SELECT 
        'Run A' as run_label,
        pm1.run_id,
        pm1.true_positives,
        pm1.false_positives,
        pm1.true_negatives,
        pm1.false_negatives,
        pm1.accuracy,
        pm1.f1_score
    FROM performance_metrics pm1 
    WHERE pm1.run_id = 'RUN_A_ID' AND pm1.narrative_type = 'combined'
    
    UNION ALL
    
    SELECT 
        'Run B' as run_label,
        pm2.run_id,
        pm2.true_positives,
        pm2.false_positives,
        pm2.true_negatives,
        pm2.false_negatives,
        pm2.accuracy,
        pm2.f1_score
    FROM performance_metrics pm2 
    WHERE pm2.run_id = 'RUN_B_ID' AND pm2.narrative_type = 'combined'
)
SELECT 
    run_label,
    true_positives + false_negatives as total_positives,
    true_negatives + false_positives as total_negatives,
    true_positives + false_positives as total_predicted_positive,
    true_negatives + false_negatives as total_predicted_negative,
    accuracy,
    f1_score,
    -- Effect size (difference in accuracy)
    accuracy - LAG(accuracy) OVER (ORDER BY run_label) as accuracy_difference
FROM run_comparison
ORDER BY run_label;

-- 3. MOST COMMON FALSE POSITIVE/NEGATIVE PATTERNS
-- Identify the most frequent misclassification patterns
SELECT 
    ea.error_type,
    ea.narrative_type,
    ea.misclassification_reason,
    COUNT(*) as occurrence_count,
    ROUND(AVG(ea.predicted_confidence), 3) as avg_confidence,
    ROUND(AVG(nq.length_words), 1) as avg_narrative_length,
    ROUND(AVG(nq.completeness_score), 3) as avg_completeness,
    GROUP_CONCAT(DISTINCT SUBSTR(ea.key_indicators_missed, 1, 50), '; ') as common_missed_indicators
FROM error_analysis ea
LEFT JOIN narrative_quality nq ON ea.run_id = nq.run_id 
    AND ea.incident_id = nq.incident_id 
    AND ea.narrative_type = nq.narrative_type
WHERE ea.run_id = :run_id  -- Parameter to be replaced
GROUP BY ea.error_type, ea.narrative_type, ea.misclassification_reason
HAVING COUNT(*) >= 2  -- Only show patterns that occur at least twice
ORDER BY occurrence_count DESC, ea.error_type;

-- 4. CONFIDENCE SCORE CALIBRATION ANALYSIS
-- Check how well confidence scores predict actual accuracy
SELECT 
    cc.confidence_bin_start || '-' || cc.confidence_bin_end as confidence_range,
    cc.bin_center,
    cc.prediction_count,
    cc.correct_predictions,
    ROUND(cc.accuracy_in_bin, 4) as actual_accuracy,
    ROUND(cc.bin_center, 4) as expected_accuracy,
    ROUND(cc.calibration_error, 4) as calibration_error,
    CASE 
        WHEN cc.calibration_error < 0.05 THEN 'Well Calibrated'
        WHEN cc.calibration_error < 0.10 THEN 'Moderately Calibrated'
        WHEN cc.calibration_error < 0.15 THEN 'Poorly Calibrated'
        ELSE 'Severely Miscalibrated'
    END as calibration_quality,
    cc.narrative_type
FROM confidence_calibration cc
WHERE cc.run_id = :run_id
ORDER BY cc.confidence_bin_start, cc.narrative_type;

-- 5. INDICATOR EFFECTIVENESS ANALYSIS
-- Which IPV indicators are most predictive and reliable?
SELECT 
    ia.indicator_name,
    ia.indicator_category,
    ia.detection_count,
    ia.true_positive_count,
    ia.false_positive_count,
    ROUND(ia.precision_score, 4) as precision,
    ROUND(ia.recall_in_positives, 4) as recall_in_positives,
    ROUND(ia.avg_confidence_when_detected, 4) as avg_confidence,
    -- Calculate F1-score for this indicator
    ROUND(2.0 * (ia.precision_score * ia.recall_in_positives) / 
          NULLIF(ia.precision_score + ia.recall_in_positives, 0), 4) as indicator_f1,
    ia.narrative_type,
    -- Indicator effectiveness score (precision * detection_rate)
    ROUND(ia.precision_score * (CAST(ia.detection_count AS REAL) / 
          (SELECT COUNT(*) FROM test_results WHERE run_id = ia.run_id)), 4) as effectiveness_score
FROM indicator_analysis ia
WHERE ia.run_id = :run_id
    AND ia.detection_count >= 3  -- Only indicators with sufficient observations
ORDER BY effectiveness_score DESC, ia.precision_score DESC;

-- 6. NARRATIVE QUALITY VS ACCURACY CORRELATION
-- Analyze how narrative quality affects prediction accuracy
SELECT 
    nq.detail_level,
    COUNT(*) as narrative_count,
    SUM(CASE WHEN nq.prediction_accuracy = 1 THEN 1 ELSE 0 END) as correct_predictions,
    ROUND(AVG(CASE WHEN nq.prediction_accuracy = 1 THEN 1.0 ELSE 0.0 END), 4) as accuracy_rate,
    ROUND(AVG(nq.length_words), 1) as avg_length_words,
    ROUND(AVG(nq.completeness_score), 3) as avg_completeness,
    ROUND(AVG(nq.readability_score), 1) as avg_readability,
    ROUND(AVG(nq.confidence_level), 3) as avg_confidence,
    -- Quality indicators
    ROUND(AVG(CASE WHEN nq.contains_timeline = 1 THEN 1.0 ELSE 0.0 END), 3) as timeline_rate,
    ROUND(AVG(CASE WHEN nq.contains_physical_evidence = 1 THEN 1.0 ELSE 0.0 END), 3) as evidence_rate,
    ROUND(AVG(CASE WHEN nq.contains_prior_incidents = 1 THEN 1.0 ELSE 0.0 END), 3) as prior_incidents_rate
FROM narrative_quality nq
WHERE nq.run_id = :run_id
GROUP BY nq.detail_level, nq.narrative_type
ORDER BY accuracy_rate DESC;

-- 7. TEMPORAL PERFORMANCE TRENDS
-- Track how performance changes over time or across test runs
SELECT 
    DATE(tr.run_timestamp, 'unixepoch') as test_date,
    tr.run_name,
    pv.version_number,
    pm.narrative_type,
    ROUND(pm.accuracy, 4) as accuracy,
    ROUND(pm.f1_score, 4) as f1_score,
    pm.total_cases,
    ROUND(pm.avg_processing_time_ms, 2) as avg_processing_time,
    -- Calculate moving average over last 3 runs
    ROUND(AVG(pm.accuracy) OVER (
        PARTITION BY pm.narrative_type 
        ORDER BY tr.run_timestamp 
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 4) as moving_avg_accuracy
FROM test_runs tr
JOIN performance_metrics pm ON tr.run_id = pm.run_id
JOIN prompt_versions pv ON tr.prompt_version_id = pv.version_id
WHERE tr.status = 'completed'
ORDER BY tr.run_timestamp, pm.narrative_type;

-- 8. DETAILED MISCLASSIFICATION INVESTIGATION
-- Deep dive into specific misclassification cases for manual review
SELECT 
    tr.incident_id,
    tr.narrative_type,
    tr.predicted_ipv,
    tr.actual_ipv,
    ROUND(tr.predicted_confidence, 4) as confidence,
    SUBSTR(tr.rationale, 1, 200) || '...' as rationale_excerpt,
    ea.misclassification_reason,
    nq.length_words,
    nq.detail_level,
    nq.completeness_score,
    -- Flag high-confidence errors for priority review
    CASE 
        WHEN tr.predicted_ipv != tr.actual_ipv AND tr.predicted_confidence > 0.8 THEN 'HIGH_PRIORITY'
        WHEN tr.predicted_ipv != tr.actual_ipv AND tr.predicted_confidence > 0.6 THEN 'MEDIUM_PRIORITY'
        ELSE 'LOW_PRIORITY'
    END as review_priority
FROM test_results tr
LEFT JOIN error_analysis ea ON tr.run_id = ea.run_id 
    AND tr.incident_id = ea.incident_id 
    AND tr.narrative_type = ea.narrative_type
LEFT JOIN narrative_quality nq ON tr.run_id = nq.run_id 
    AND tr.incident_id = nq.incident_id 
    AND tr.narrative_type = nq.narrative_type
WHERE tr.run_id = :run_id
    AND tr.predicted_ipv != tr.actual_ipv  -- Only misclassifications
ORDER BY 
    tr.predicted_confidence DESC,  -- Review high-confidence errors first
    CASE WHEN tr.predicted_ipv = 1 THEN 0 ELSE 1 END,  -- False positives first
    tr.incident_id;

-- 9. COST-BENEFIT ANALYSIS
-- Analyze API costs vs performance improvements
SELECT 
    tr.run_name,
    tr.model_name,
    pm.accuracy,
    pm.f1_score,
    ROUND(SUM(res.api_cost), 2) as total_api_cost,
    ROUND(AVG(res.api_cost), 4) as avg_cost_per_prediction,
    ROUND(pm.accuracy / NULLIF(AVG(res.api_cost), 0), 2) as accuracy_per_dollar,
    SUM(res.token_count) as total_tokens,
    ROUND(AVG(res.processing_time_ms), 2) as avg_processing_time,
    -- Cost efficiency metrics
    ROUND(pm.f1_score / NULLIF(AVG(res.api_cost), 0), 2) as f1_per_dollar,
    ROUND(1000.0 / NULLIF(AVG(res.processing_time_ms), 0), 2) as predictions_per_second
FROM test_runs tr
JOIN performance_metrics pm ON tr.run_id = pm.run_id
JOIN test_results res ON tr.run_id = res.run_id
WHERE tr.status = 'completed' AND pm.narrative_type = 'combined'
GROUP BY tr.run_id, tr.run_name, tr.model_name, pm.accuracy, pm.f1_score
ORDER BY f1_per_dollar DESC;

-- 10. A/B TEST RESULTS SUMMARY
-- Analyze results of A/B tests between different approaches
SELECT 
    ab.test_name,
    tr_a.run_name as variant_a_name,
    tr_b.run_name as variant_b_name,
    ab.test_metric,
    ROUND(ab.variant_a_score, 4) as variant_a_score,
    ROUND(ab.variant_b_score, 4) as variant_b_score,
    ROUND(ab.variant_b_score - ab.variant_a_score, 4) as improvement,
    ROUND((ab.variant_b_score - ab.variant_a_score) / NULLIF(ab.variant_a_score, 0) * 100, 2) as percent_improvement,
    ROUND(ab.statistical_significance, 6) as p_value,
    CASE 
        WHEN ab.statistical_significance <= 0.01 THEN 'Highly Significant (p≤0.01)'
        WHEN ab.statistical_significance <= 0.05 THEN 'Significant (p≤0.05)'
        WHEN ab.statistical_significance <= 0.10 THEN 'Marginally Significant (p≤0.10)'
        ELSE 'Not Significant (p>0.10)'
    END as significance_level,
    ab.winner,
    ROUND(ab.effect_size, 4) as effect_size,
    ab.sample_size,
    ROUND(ab.test_power, 3) as statistical_power,
    DATE(ab.created_timestamp, 'unixepoch') as test_date
FROM ab_tests ab
JOIN test_runs tr_a ON ab.variant_a_run_id = tr_a.run_id
JOIN test_runs tr_b ON ab.variant_b_run_id = tr_b.run_id
ORDER BY ab.created_timestamp DESC;