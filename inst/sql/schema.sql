-- SQLite schema for LLM results storage
-- Single table design following Unix philosophy
-- Version: 1

-- Main storage table
CREATE TABLE IF NOT EXISTS llm_results (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    
    -- Narrative identification
    narrative_id TEXT,
    narrative_text TEXT,
    
    -- Core results
    detected BOOLEAN NOT NULL,
    confidence REAL CHECK(confidence >= 0 AND confidence <= 1),
    
    -- Model metadata
    model TEXT,
    prompt_tokens INTEGER,
    completion_tokens INTEGER,
    total_tokens INTEGER,
    response_time_ms INTEGER,
    
    -- Full response for debugging
    raw_response TEXT,
    error_message TEXT,
    
    -- Tracking
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- Prevent exact duplicates
    UNIQUE(narrative_id, narrative_text, model)
);

-- Performance indexes
CREATE INDEX IF NOT EXISTS idx_narrative_id ON llm_results(narrative_id);
CREATE INDEX IF NOT EXISTS idx_detected ON llm_results(detected);
CREATE INDEX IF NOT EXISTS idx_created_at ON llm_results(created_at);
CREATE INDEX IF NOT EXISTS idx_model ON llm_results(model);

-- Set schema version
PRAGMA user_version = 1;