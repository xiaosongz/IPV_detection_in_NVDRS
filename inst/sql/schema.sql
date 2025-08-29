-- Universal schema for LLM results storage
-- Single table design following Unix philosophy
-- Works with both SQLite and PostgreSQL
-- Version: 1

-- Database-specific schema is handled by ensure_schema() function in db_utils.R
-- This file documents the expected schema structure

-- SQLite version:
-- CREATE TABLE IF NOT EXISTS llm_results (
--     id INTEGER PRIMARY KEY AUTOINCREMENT,
--     narrative_id TEXT,
--     narrative_text TEXT,
--     detected BOOLEAN NOT NULL,
--     confidence REAL CHECK(confidence >= 0 AND confidence <= 1),
--     model TEXT,
--     prompt_tokens INTEGER,
--     completion_tokens INTEGER,
--     total_tokens INTEGER,
--     response_time_ms INTEGER,
--     raw_response TEXT,
--     error_message TEXT,
--     created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
--     UNIQUE(narrative_id, narrative_text, model)
-- );

-- PostgreSQL version:
-- CREATE TABLE IF NOT EXISTS llm_results (
--     id SERIAL PRIMARY KEY,
--     narrative_id TEXT,
--     narrative_text TEXT,
--     detected BOOLEAN NOT NULL,
--     confidence REAL CHECK (confidence >= 0.0 AND confidence <= 1.0),
--     model TEXT,
--     prompt_tokens INTEGER CHECK (prompt_tokens >= 0),
--     completion_tokens INTEGER CHECK (completion_tokens >= 0),
--     total_tokens INTEGER CHECK (total_tokens >= 0),
--     response_time_ms INTEGER CHECK (response_time_ms >= 0),
--     raw_response TEXT,
--     error_message TEXT,
--     created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
--     UNIQUE(narrative_id, narrative_text, model)
-- );

-- Schema is created dynamically by ensure_schema() function
-- which detects database type and creates appropriate version

-- Default SQLite schema for compatibility (fallback)
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

-- Performance indexes (SQLite version)
CREATE INDEX IF NOT EXISTS idx_narrative_id ON llm_results(narrative_id);
CREATE INDEX IF NOT EXISTS idx_detected ON llm_results(detected);
CREATE INDEX IF NOT EXISTS idx_created_at ON llm_results(created_at);
CREATE INDEX IF NOT EXISTS idx_model ON llm_results(model);

-- Set schema version (SQLite only)
PRAGMA user_version = 1;