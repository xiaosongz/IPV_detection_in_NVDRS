-- Experiment tracking schema for R&D phase
-- Supplements the existing llm_results table with experiment tracking
-- Version: 1.0

-- Table 1: Prompt versions for tracking different prompt iterations
CREATE TABLE IF NOT EXISTS prompt_versions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    system_prompt TEXT NOT NULL,
    user_prompt_template TEXT NOT NULL,
    prompt_hash TEXT UNIQUE,  -- SHA256(system + user) for deduplication
    version_tag TEXT,         -- Human-readable version like "v1.0_baseline"
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    notes TEXT,               -- Description of changes in this version
    
    -- Index for fast lookups
    CHECK (length(system_prompt) > 0),
    CHECK (length(user_prompt_template) > 0)
);

-- Table 2: Experiments for tracking test batches
CREATE TABLE IF NOT EXISTS experiments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    prompt_version_id INTEGER NOT NULL REFERENCES prompt_versions(id),
    model TEXT NOT NULL,      -- Model identifier like "gpt-4", "claude-3"
    dataset_name TEXT,        -- Which test dataset was used
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP,
    total_narratives INTEGER,
    status TEXT DEFAULT 'running' CHECK(status IN ('running', 'completed', 'failed')),
    notes TEXT,
    
    -- Useful for finding experiments
    CHECK (length(name) > 0),
    CHECK (length(model) > 0)
);

-- Table 3: Results linked to experiments
CREATE TABLE IF NOT EXISTS experiment_results (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    experiment_id INTEGER NOT NULL REFERENCES experiments(id),
    narrative_id TEXT NOT NULL,
    narrative_text TEXT,
    detected BOOLEAN NOT NULL,
    confidence REAL CHECK(confidence >= 0 AND confidence <= 1),
    response_time_ms INTEGER,
    prompt_tokens INTEGER,
    completion_tokens INTEGER,
    total_tokens INTEGER,
    raw_response TEXT,
    error_message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- Prevent duplicate testing within same experiment
    UNIQUE(experiment_id, narrative_id)
);

-- Table 4: Ground truth for evaluation
CREATE TABLE IF NOT EXISTS ground_truth (
    narrative_id TEXT PRIMARY KEY,
    narrative_text TEXT,
    true_ipv BOOLEAN NOT NULL,
    confidence_level INTEGER CHECK(confidence_level IN (1, 2, 3)),  -- 1=low, 3=high
    annotator TEXT,
    annotation_date DATE,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Performance indexes
CREATE INDEX IF NOT EXISTS idx_prompt_hash ON prompt_versions(prompt_hash);
CREATE INDEX IF NOT EXISTS idx_prompt_version ON prompt_versions(version_tag);
CREATE INDEX IF NOT EXISTS idx_experiment_prompt ON experiments(prompt_version_id);
CREATE INDEX IF NOT EXISTS idx_experiment_model ON experiments(model);
CREATE INDEX IF NOT EXISTS idx_experiment_status ON experiments(status);
CREATE INDEX IF NOT EXISTS idx_result_experiment ON experiment_results(experiment_id);
CREATE INDEX IF NOT EXISTS idx_result_narrative ON experiment_results(narrative_id);
CREATE INDEX IF NOT EXISTS idx_result_detected ON experiment_results(detected);

-- Useful views for analysis
CREATE VIEW IF NOT EXISTS experiment_summary AS
SELECT 
    e.id as experiment_id,
    e.name as experiment_name,
    pv.version_tag as prompt_version,
    e.model,
    e.started_at,
    e.completed_at,
    COUNT(er.id) as total_results,
    AVG(er.confidence) as avg_confidence,
    SUM(CASE WHEN er.detected THEN 1 ELSE 0 END) * 100.0 / COUNT(*) as detection_rate,
    AVG(er.response_time_ms) as avg_response_time_ms,
    SUM(er.total_tokens) as total_tokens_used
FROM experiments e
LEFT JOIN prompt_versions pv ON e.prompt_version_id = pv.id
LEFT JOIN experiment_results er ON e.id = er.experiment_id
GROUP BY e.id;

-- View for comparing experiments with ground truth
CREATE VIEW IF NOT EXISTS experiment_accuracy AS
SELECT 
    e.id as experiment_id,
    e.name as experiment_name,
    COUNT(*) as total_evaluated,
    SUM(CASE WHEN er.detected = gt.true_ipv THEN 1 ELSE 0 END) * 100.0 / COUNT(*) as accuracy,
    SUM(CASE WHEN er.detected AND gt.true_ipv THEN 1 ELSE 0 END) * 100.0 / 
        NULLIF(SUM(CASE WHEN gt.true_ipv THEN 1 ELSE 0 END), 0) as recall,
    SUM(CASE WHEN er.detected AND gt.true_ipv THEN 1 ELSE 0 END) * 100.0 / 
        NULLIF(SUM(CASE WHEN er.detected THEN 1 ELSE 0 END), 0) as precision
FROM experiments e
JOIN experiment_results er ON e.id = er.experiment_id
JOIN ground_truth gt ON er.narrative_id = gt.narrative_id
GROUP BY e.id;

-- Set schema version for migrations
PRAGMA user_version = 2;