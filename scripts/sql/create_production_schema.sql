CREATE TABLE source_narratives (
      narrative_id INTEGER PRIMARY KEY AUTOINCREMENT,
      incident_id TEXT NOT NULL,
      narrative_type TEXT NOT NULL,
      narrative_text TEXT,
      manual_flag_ind INTEGER,
      manual_flag INTEGER,
      data_source TEXT,
      loaded_at TEXT NOT NULL,
      UNIQUE(incident_id, narrative_type)
    );
CREATE TABLE sqlite_sequence(name,seq);
CREATE INDEX idx_source_incident ON source_narratives(incident_id);
CREATE INDEX idx_source_type ON source_narratives(narrative_type);
CREATE INDEX idx_source_manual ON source_narratives(manual_flag_ind);
CREATE TABLE experiments (
      experiment_id TEXT PRIMARY KEY,
      experiment_name TEXT NOT NULL,
      status TEXT DEFAULT 'running',
      model_name TEXT NOT NULL,
      model_provider TEXT,
      temperature REAL NOT NULL,
      system_prompt TEXT NOT NULL,
      user_template TEXT NOT NULL,
      prompt_version TEXT,
      prompt_author TEXT,
      run_seed INTEGER,
      data_file TEXT,
      n_narratives_total INTEGER,
      n_narratives_processed INTEGER,
      n_narratives_skipped INTEGER,
      start_time TEXT NOT NULL,
      end_time TEXT,
      total_runtime_sec REAL,
      avg_time_per_narrative_sec REAL,
      api_url TEXT,
      r_version TEXT,
      os_info TEXT,
      hostname TEXT,
      n_positive_detected INTEGER,
      n_negative_detected INTEGER,
      n_positive_manual INTEGER,
      n_negative_manual INTEGER,
      accuracy REAL,
      precision_ipv REAL,
      recall_ipv REAL,
      f1_ipv REAL,
      n_false_positive INTEGER,
      n_false_negative INTEGER,
      n_true_positive INTEGER,
      n_true_negative INTEGER,
      pct_overlap_with_manual REAL,
      csv_file TEXT,
      json_file TEXT,
      log_dir TEXT,
      created_at TEXT NOT NULL,
      notes TEXT
    );
CREATE INDEX idx_status ON experiments(status);
CREATE INDEX idx_model_name ON experiments(model_name);
CREATE INDEX idx_prompt_version ON experiments(prompt_version);
CREATE INDEX idx_created_at ON experiments(created_at);
CREATE TABLE narrative_results (
      result_id INTEGER PRIMARY KEY AUTOINCREMENT,
      experiment_id TEXT NOT NULL,
      incident_id TEXT NOT NULL,
      narrative_type TEXT NOT NULL,
      row_num INTEGER,
      narrative_text TEXT,
      manual_flag_ind INTEGER,
      manual_flag INTEGER,
      detected INTEGER,
      confidence REAL,
      indicators TEXT,
      rationale TEXT,
      reasoning_steps TEXT,
      raw_response TEXT,
      response_sec REAL,
      processed_at TEXT,
      error_occurred INTEGER DEFAULT 0,
      error_message TEXT,
      is_true_positive INTEGER,
      is_true_negative INTEGER,
      is_false_positive INTEGER,
      is_false_negative INTEGER, prompt_tokens INTEGER, completion_tokens INTEGER, tokens_used INTEGER,
      FOREIGN KEY (experiment_id) REFERENCES experiments(experiment_id)
    );
CREATE INDEX idx_experiment_id ON narrative_results(experiment_id);
CREATE INDEX idx_incident_id ON narrative_results(incident_id);
CREATE INDEX idx_narrative_type ON narrative_results(narrative_type);
CREATE INDEX idx_manual_flag_ind ON narrative_results(manual_flag_ind);
CREATE INDEX idx_detected ON narrative_results(detected);
CREATE INDEX idx_error ON narrative_results(error_occurred);
CREATE INDEX idx_false_positive ON narrative_results(is_false_positive);
CREATE INDEX idx_false_negative ON narrative_results(is_false_negative);
CREATE INDEX idx_exp_tokens ON narrative_results(experiment_id, tokens_used);
