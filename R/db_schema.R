#' Initialize Experiment Tracking Database
#'
#' Creates SQLite database with experiments, narrative_results, and source_narratives tables
#'
#' @param db_path Path to SQLite database file. If NULL, uses centralized config.
#' @return DBI connection object
#' @export
#' @examples
#' \dontrun{
#'   conn <- init_experiment_db()  # Uses centralized config
#'   conn <- init_experiment_db("custom.db")  # Custom path
#'   dbDisconnect(conn)
#' }
init_experiment_db <- function(db_path = NULL) {
  if (is.null(db_path)) {
    db_path <- get_experiments_db_path()
  }
  if (!requireNamespace("DBI", quietly = TRUE)) {
    stop("Package 'DBI' is required but not installed.")
  }
  if (!requireNamespace("RSQLite", quietly = TRUE)) {
    stop("Package 'RSQLite' is required but not installed.")
  }
  
  conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  
  # Enable foreign keys
  DBI::dbExecute(conn, "PRAGMA foreign_keys = ON")
  
  # Table 0: source_narratives
  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS source_narratives (
      narrative_id INTEGER PRIMARY KEY AUTOINCREMENT,
      incident_id TEXT NOT NULL,
      narrative_type TEXT NOT NULL,
      narrative_text TEXT,
      manual_flag_ind INTEGER,
      manual_flag INTEGER,
      data_source TEXT,
      loaded_at TEXT NOT NULL,
      UNIQUE(incident_id, narrative_type)
    )
  ")
  
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_source_incident ON source_narratives(incident_id)")
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_source_type ON source_narratives(narrative_type)")
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_source_manual ON source_narratives(manual_flag_ind)")
  
  # Table 1: experiments
  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS experiments (
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
    )
  ")
  
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_status ON experiments(status)")
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_model_name ON experiments(model_name)")
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_prompt_version ON experiments(prompt_version)")
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_created_at ON experiments(created_at)")
  
  # Table 2: narrative_results
  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS narrative_results (
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
      is_false_negative INTEGER,
      FOREIGN KEY (experiment_id) REFERENCES experiments(experiment_id)
    )
  ")
  
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_experiment_id ON narrative_results(experiment_id)")
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_incident_id ON narrative_results(incident_id)")
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_narrative_type ON narrative_results(narrative_type)")
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_manual_flag_ind ON narrative_results(manual_flag_ind)")
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_detected ON narrative_results(detected)")
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_error ON narrative_results(error_occurred)")
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_false_positive ON narrative_results(is_false_positive)")
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_false_negative ON narrative_results(is_false_negative)")
  
  return(conn)
}

#' Get Database Connection
#'
#' Opens connection to experiment database with error handling
#'
#' @param db_path Path to SQLite database file. If NULL, uses centralized config.
#' @return DBI connection object
#' @export
get_db_connection <- function(db_path = NULL) {
  if (is.null(db_path)) {
    db_path <- get_experiments_db_path()
  }
  if (!file.exists(db_path)) {
    stop("Database not found at: ", db_path, "\nPlease run init_experiment_db() first.")
  }
  
  conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  DBI::dbExecute(conn, "PRAGMA foreign_keys = ON")
  
  return(conn)
}
