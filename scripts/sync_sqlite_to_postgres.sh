#!/usr/bin/env bash

# Copy the local SQLite experiment database into a PostgreSQL instance.
# Usage:
#   scripts/sync_sqlite_to_postgres.sh [sqlite_path]
#   PG_CONN_STR=postgresql://user:pass@host:port/db scripts/sync_sqlite_to_postgres.sh
#
# Configuration:
#   Reads PG_CONN_STR from .env file in repository root (recommended)
#   Or set PG_CONN_STR environment variable to override
#
# Environment variables:
#   PG_CONN_STR          - PostgreSQL connection string (reads from .env by default)
#   FULL_REFRESH=1       - Drop and recreate tables (default: 0 for incremental UPSERT)
#   DELETE_ORPHANS=1     - Remove rows in Postgres not in SQLite (default: 0)
#   BATCH_SIZE=1000      - Rows per batch for streaming (default: 1000)

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

# Load environment variables from .env if present
if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  source "$REPO_ROOT/.env"
  set +a
fi

SQLITE_DB=${1:-"$REPO_ROOT/data/experiments.db"}
if [[ ! -f "$SQLITE_DB" ]]; then
  echo "❌ SQLite database not found: $SQLITE_DB" >&2
  exit 1
fi

# Use PG_CONN_STR from environment (.env file loaded above) or fallback to default
if [[ -z "$PG_CONN_STR" ]]; then
  echo "⚠️  PG_CONN_STR not set in .env file, using default connection" >&2
  PG_CONN_STR="postgresql://postgres:k14I12d1@memini.lan:5433/postgres"
fi
FULL_REFRESH=${FULL_REFRESH:-0}
DELETE_ORPHANS=${DELETE_ORPHANS:-0}
BATCH_SIZE=${BATCH_SIZE:-1000}

if ! command -v python3 >/dev/null 2>&1; then
  echo "❌ python3 not found on PATH" >&2
  exit 1
fi

export SQLITE_DB="$SQLITE_DB"
export PG_CONN_STR
export FULL_REFRESH
export DELETE_ORPHANS
export BATCH_SIZE

START_TIME=$(date +%s)

python3 - <<'PY'
import os
import sqlite3
import time

try:
    import psycopg
except ImportError as exc:
    raise SystemExit("❌ psycopg (psycopg3) is required. Install with: pip3 install --user psycopg[binary]") from exc

sqlite_path = os.environ["SQLITE_DB"]
pg_conn_str = os.environ["PG_CONN_STR"]
full_refresh = int(os.environ.get("FULL_REFRESH", "0"))
delete_orphans = int(os.environ.get("DELETE_ORPHANS", "0"))
batch_size = int(os.environ.get("BATCH_SIZE", "1000"))

def fetch_all(conn, query):
    conn.row_factory = sqlite3.Row
    cur = conn.execute(query)
    rows = [dict(row) for row in cur.fetchall()]
    cur.close()
    return rows

def stream_batches(conn, query, batch_size=1000):
    """Generator that yields batches of rows to avoid loading entire table into memory."""
    conn.row_factory = sqlite3.Row
    cur = conn.execute(query)
    while True:
        batch = cur.fetchmany(batch_size)
        if not batch:
            break
        yield [dict(row) for row in batch]
    cur.close()

sconn = sqlite3.connect(sqlite_path)

pconn = psycopg.connect(pg_conn_str)

with pconn.cursor() as cur:
    cur.execute("SET search_path TO public")
    cur.execute(
        "SELECT COALESCE(SUM(pg_relation_size(oid)), 0) FROM pg_class WHERE relkind='r' AND relnamespace = 'public'::regnamespace"
    )
    pg_size_before = cur.fetchone()[0]
    
    # Check if tables exist
    cur.execute("""
        SELECT COUNT(*) FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'experiments'
    """)
    tables_exist = cur.fetchone()[0] > 0
    
    if tables_exist:
        cur.execute("SELECT COUNT(*) FROM experiments")
        exp_before = cur.fetchone()[0]
        cur.execute("SELECT COUNT(*) FROM narrative_results")
        res_before = cur.fetchone()[0]
        cur.execute("SELECT COUNT(*) FROM source_narratives")
        src_before = cur.fetchone()[0]
    else:
        exp_before = res_before = src_before = 0
        full_refresh = 1  # Force full refresh if tables don't exist

if full_refresh:
    print("🔄 FULL REFRESH mode: dropping and recreating tables")
    with pconn.cursor() as cur:
        cur.execute("DROP TABLE IF EXISTS narrative_results")
        cur.execute("DROP TABLE IF EXISTS source_narratives")
        cur.execute("DROP TABLE IF EXISTS experiments")

else:
    print("⚡ INCREMENTAL mode: using UPSERT for existing tables")

# Create tables if they don't exist (idempotent)
with pconn.cursor() as cur:
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS source_narratives (
                narrative_id INTEGER PRIMARY KEY,
                incident_id TEXT,
                narrative_type TEXT NOT NULL,
                narrative_text TEXT,
                manual_flag_ind INTEGER,
                manual_flag INTEGER,
                data_source TEXT,
                loaded_at TIMESTAMP,
                UNIQUE (incident_id, narrative_type)
            )
            """
        )

    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS experiments (
                experiment_id TEXT PRIMARY KEY,
                experiment_name TEXT NOT NULL,
                status TEXT,
                model_name TEXT NOT NULL,
                model_provider TEXT,
                temperature DOUBLE PRECISION,
                system_prompt TEXT NOT NULL,
                user_template TEXT NOT NULL,
                prompt_version TEXT,
                prompt_author TEXT,
                run_seed INTEGER,
                data_file TEXT,
                n_narratives_total INTEGER,
                n_narratives_processed INTEGER,
                n_narratives_skipped INTEGER,
                start_time TIMESTAMP NOT NULL,
                end_time TIMESTAMP,
                total_runtime_sec DOUBLE PRECISION,
                avg_time_per_narrative_sec DOUBLE PRECISION,
                api_url TEXT,
                r_version TEXT,
                os_info TEXT,
                hostname TEXT,
                n_positive_detected INTEGER,
                n_negative_detected INTEGER,
                n_positive_manual INTEGER,
                n_negative_manual INTEGER,
                accuracy DOUBLE PRECISION,
                precision_ipv DOUBLE PRECISION,
                recall_ipv DOUBLE PRECISION,
                f1_ipv DOUBLE PRECISION,
                n_false_positive INTEGER,
                n_false_negative INTEGER,
                n_true_positive INTEGER,
                n_true_negative INTEGER,
                pct_overlap_with_manual DOUBLE PRECISION,
                csv_file TEXT,
                json_file TEXT,
                log_dir TEXT,
                created_at TIMESTAMP NOT NULL,
                notes TEXT
            )
            """
        )

    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS narrative_results (
                result_id INTEGER PRIMARY KEY,
                experiment_id TEXT REFERENCES experiments(experiment_id),
                incident_id TEXT,
                narrative_type TEXT NOT NULL,
                row_num INTEGER,
                narrative_text TEXT,
                manual_flag_ind INTEGER,
                manual_flag INTEGER,
                detected INTEGER,
                confidence DOUBLE PRECISION,
                indicators TEXT,
                rationale TEXT,
                reasoning_steps TEXT,
                raw_response TEXT,
                response_sec DOUBLE PRECISION,
                processed_at TIMESTAMP,
                error_occurred INTEGER,
                error_message TEXT,
                prompt_tokens INTEGER,
                completion_tokens INTEGER,
                tokens_used INTEGER,
                is_true_positive INTEGER,
                is_true_negative INTEGER,
                is_false_positive INTEGER,
                is_false_negative INTEGER
            )
            """
        )

pconn.commit()

# Sync data with UPSERT or INSERT
upsert_source = """
    INSERT INTO source_narratives (
        narrative_id, incident_id, narrative_type, narrative_text,
        manual_flag_ind, manual_flag, data_source, loaded_at
    )
    VALUES (
        %(narrative_id)s, %(incident_id)s, %(narrative_type)s, %(narrative_text)s,
        %(manual_flag_ind)s, %(manual_flag)s, %(data_source)s, %(loaded_at)s
    )
    ON CONFLICT (narrative_id) DO UPDATE SET
        incident_id = EXCLUDED.incident_id,
        narrative_type = EXCLUDED.narrative_type,
        narrative_text = EXCLUDED.narrative_text,
        manual_flag_ind = EXCLUDED.manual_flag_ind,
        manual_flag = EXCLUDED.manual_flag,
        data_source = EXCLUDED.data_source,
        loaded_at = EXCLUDED.loaded_at
"""

upsert_experiment = """
    INSERT INTO experiments (
        experiment_id, experiment_name, status,
        model_name, model_provider, temperature,
        system_prompt, user_template, prompt_version, prompt_author,
        run_seed, data_file, n_narratives_total, n_narratives_processed,
        n_narratives_skipped, start_time, end_time, total_runtime_sec,
        avg_time_per_narrative_sec, api_url, r_version, os_info, hostname,
        n_positive_detected, n_negative_detected, n_positive_manual, n_negative_manual,
        accuracy, precision_ipv, recall_ipv, f1_ipv,
        n_false_positive, n_false_negative, n_true_positive, n_true_negative,
        pct_overlap_with_manual, csv_file, json_file, log_dir, created_at, notes
    ) VALUES (
        %(experiment_id)s, %(experiment_name)s, %(status)s,
        %(model_name)s, %(model_provider)s, %(temperature)s,
        %(system_prompt)s, %(user_template)s, %(prompt_version)s, %(prompt_author)s,
        %(run_seed)s, %(data_file)s, %(n_narratives_total)s, %(n_narratives_processed)s,
        %(n_narratives_skipped)s, %(start_time)s, %(end_time)s, %(total_runtime_sec)s,
        %(avg_time_per_narrative_sec)s, %(api_url)s, %(r_version)s, %(os_info)s, %(hostname)s,
        %(n_positive_detected)s, %(n_negative_detected)s, %(n_positive_manual)s, %(n_negative_manual)s,
        %(accuracy)s, %(precision_ipv)s, %(recall_ipv)s, %(f1_ipv)s,
        %(n_false_positive)s, %(n_false_negative)s, %(n_true_positive)s, %(n_true_negative)s,
        %(pct_overlap_with_manual)s, %(csv_file)s, %(json_file)s, %(log_dir)s, %(created_at)s, %(notes)s
    )
    ON CONFLICT (experiment_id) DO UPDATE SET
        experiment_name = EXCLUDED.experiment_name,
        status = EXCLUDED.status,
        model_name = EXCLUDED.model_name,
        model_provider = EXCLUDED.model_provider,
        temperature = EXCLUDED.temperature,
        system_prompt = EXCLUDED.system_prompt,
        user_template = EXCLUDED.user_template,
        prompt_version = EXCLUDED.prompt_version,
        prompt_author = EXCLUDED.prompt_author,
        run_seed = EXCLUDED.run_seed,
        data_file = EXCLUDED.data_file,
        n_narratives_total = EXCLUDED.n_narratives_total,
        n_narratives_processed = EXCLUDED.n_narratives_processed,
        n_narratives_skipped = EXCLUDED.n_narratives_skipped,
        start_time = EXCLUDED.start_time,
        end_time = EXCLUDED.end_time,
        total_runtime_sec = EXCLUDED.total_runtime_sec,
        avg_time_per_narrative_sec = EXCLUDED.avg_time_per_narrative_sec,
        api_url = EXCLUDED.api_url,
        r_version = EXCLUDED.r_version,
        os_info = EXCLUDED.os_info,
        hostname = EXCLUDED.hostname,
        n_positive_detected = EXCLUDED.n_positive_detected,
        n_negative_detected = EXCLUDED.n_negative_detected,
        n_positive_manual = EXCLUDED.n_positive_manual,
        n_negative_manual = EXCLUDED.n_negative_manual,
        accuracy = EXCLUDED.accuracy,
        precision_ipv = EXCLUDED.precision_ipv,
        recall_ipv = EXCLUDED.recall_ipv,
        f1_ipv = EXCLUDED.f1_ipv,
        n_false_positive = EXCLUDED.n_false_positive,
        n_false_negative = EXCLUDED.n_false_negative,
        n_true_positive = EXCLUDED.n_true_positive,
        n_true_negative = EXCLUDED.n_true_negative,
        pct_overlap_with_manual = EXCLUDED.pct_overlap_with_manual,
        csv_file = EXCLUDED.csv_file,
        json_file = EXCLUDED.json_file,
        log_dir = EXCLUDED.log_dir,
        created_at = EXCLUDED.created_at,
        notes = EXCLUDED.notes
"""

upsert_result = """
    INSERT INTO narrative_results (
        result_id, experiment_id, incident_id, narrative_type, row_num,
        narrative_text, manual_flag_ind, manual_flag,
        detected, confidence, indicators, rationale, reasoning_steps,
        raw_response, response_sec, processed_at,
        error_occurred, error_message,
        prompt_tokens, completion_tokens, tokens_used,
        is_true_positive, is_true_negative, is_false_positive, is_false_negative
    )
    VALUES (
        %(result_id)s, %(experiment_id)s, %(incident_id)s, %(narrative_type)s, %(row_num)s,
        %(narrative_text)s, %(manual_flag_ind)s, %(manual_flag)s,
        %(detected)s, %(confidence)s, %(indicators)s, %(rationale)s, %(reasoning_steps)s,
        %(raw_response)s, %(response_sec)s, %(processed_at)s,
        %(error_occurred)s, %(error_message)s,
        %(prompt_tokens)s, %(completion_tokens)s, %(tokens_used)s,
        %(is_true_positive)s, %(is_true_negative)s, %(is_false_positive)s, %(is_false_negative)s
    )
    ON CONFLICT (result_id) DO UPDATE SET
        experiment_id = EXCLUDED.experiment_id,
        incident_id = EXCLUDED.incident_id,
        narrative_type = EXCLUDED.narrative_type,
        row_num = EXCLUDED.row_num,
        narrative_text = EXCLUDED.narrative_text,
        manual_flag_ind = EXCLUDED.manual_flag_ind,
        manual_flag = EXCLUDED.manual_flag,
        detected = EXCLUDED.detected,
        confidence = EXCLUDED.confidence,
        indicators = EXCLUDED.indicators,
        rationale = EXCLUDED.rationale,
        reasoning_steps = EXCLUDED.reasoning_steps,
        raw_response = EXCLUDED.raw_response,
        response_sec = EXCLUDED.response_sec,
        processed_at = EXCLUDED.processed_at,
        error_occurred = EXCLUDED.error_occurred,
        error_message = EXCLUDED.error_message,
        prompt_tokens = EXCLUDED.prompt_tokens,
        completion_tokens = EXCLUDED.completion_tokens,
        tokens_used = EXCLUDED.tokens_used,
        is_true_positive = EXCLUDED.is_true_positive,
        is_true_negative = EXCLUDED.is_true_negative,
        is_false_positive = EXCLUDED.is_false_positive,
        is_false_negative = EXCLUDED.is_false_negative
"""

# Stream and sync source_narratives
print("📥 Syncing source_narratives...")
source_count = 0
with pconn.cursor() as cur:
    for batch in stream_batches(sconn, "SELECT * FROM source_narratives", batch_size):
        cur.executemany(upsert_source, batch)
        source_count += len(batch)
        if source_count % 10000 == 0:
            print(f"   ... {source_count} rows processed")
pconn.commit()
print(f"✓ source_narratives: {source_count} rows synced")

# Stream and sync experiments
print("📥 Syncing experiments...")
experiment_count = 0
with pconn.cursor() as cur:
    for batch in stream_batches(sconn, "SELECT * FROM experiments", batch_size):
        cur.executemany(upsert_experiment, batch)
        experiment_count += len(batch)
pconn.commit()
print(f"✓ experiments: {experiment_count} rows synced")

# Stream and sync narrative_results
print("📥 Syncing narrative_results...")
result_count = 0
with pconn.cursor() as cur:
    for batch in stream_batches(sconn, "SELECT * FROM narrative_results", batch_size):
        cur.executemany(upsert_result, batch)
        result_count += len(batch)
        if result_count % 10000 == 0:
            print(f"   ... {result_count} rows processed")
pconn.commit()
print(f"✓ narrative_results: {result_count} rows synced")

# Optional: delete orphaned rows in Postgres that don't exist in SQLite
if delete_orphans and not full_refresh:
    print("🧹 Deleting orphaned rows...")
    
    # Get all primary keys from SQLite
    sqlite_source_ids = set()
    for batch in stream_batches(sconn, "SELECT narrative_id FROM source_narratives", batch_size):
        sqlite_source_ids.update(row['narrative_id'] for row in batch)
    
    sqlite_exp_ids = set()
    for batch in stream_batches(sconn, "SELECT experiment_id FROM experiments", batch_size):
        sqlite_exp_ids.update(row['experiment_id'] for row in batch)
    
    sqlite_result_ids = set()
    for batch in stream_batches(sconn, "SELECT result_id FROM narrative_results", batch_size):
        sqlite_result_ids.update(row['result_id'] for row in batch)
    
    with pconn.cursor() as cur:
        # Delete orphaned source_narratives
        cur.execute("SELECT narrative_id FROM source_narratives")
        pg_source_ids = {row[0] for row in cur.fetchall()}
        orphan_sources = pg_source_ids - sqlite_source_ids
        if orphan_sources:
            cur.execute(
                "DELETE FROM source_narratives WHERE narrative_id = ANY(%s)",
                (list(orphan_sources),)
            )
            print(f"  - Deleted {len(orphan_sources)} orphaned source_narratives")
        
        # Delete orphaned experiments (and cascade to results)
        cur.execute("SELECT experiment_id FROM experiments")
        pg_exp_ids = {row[0] for row in cur.fetchall()}
        orphan_exps = pg_exp_ids - sqlite_exp_ids
        if orphan_exps:
            cur.execute(
                "DELETE FROM experiments WHERE experiment_id = ANY(%s)",
                (list(orphan_exps),)
            )
            print(f"  - Deleted {len(orphan_exps)} orphaned experiments")
        
        # Delete orphaned narrative_results
        cur.execute("SELECT result_id FROM narrative_results")
        pg_result_ids = {row[0] for row in cur.fetchall()}
        orphan_results = pg_result_ids - sqlite_result_ids
        if orphan_results:
            # Delete in batches to avoid parameter limits
            for i in range(0, len(orphan_results), 1000):
                batch_orphans = list(orphan_results)[i:i+1000]
                cur.execute(
                    "DELETE FROM narrative_results WHERE result_id = ANY(%s)",
                    (batch_orphans,)
                )
            print(f"  - Deleted {len(orphan_results)} orphaned narrative_results")
    
    pconn.commit()

sconn.close()

# Create indexes (idempotent)
print("📇 Creating indexes...")
with pconn.cursor() as cur:
    cur.execute("CREATE INDEX IF NOT EXISTS idx_source_incident ON source_narratives(incident_id)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_source_type ON source_narratives(narrative_type)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_source_manual ON source_narratives(manual_flag_ind)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_status ON experiments(status)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_model_name ON experiments(model_name)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_prompt_version ON experiments(prompt_version)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_created_at ON experiments(created_at)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_experiment_id ON narrative_results(experiment_id)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_incident_id ON narrative_results(incident_id)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_narrative_type ON narrative_results(narrative_type)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_manual_flag_ind ON narrative_results(manual_flag_ind)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_detected ON narrative_results(detected)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_error ON narrative_results(error_occurred)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_false_positive ON narrative_results(is_false_positive)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_false_negative ON narrative_results(is_false_negative)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_exp_tokens ON narrative_results(experiment_id, tokens_used)")
pconn.commit()

# Final stats
with pconn.cursor() as cur:
    cur.execute(
        "SELECT COALESCE(SUM(pg_relation_size(oid)), 0) FROM pg_class WHERE relkind='r' AND relnamespace = 'public'::regnamespace"
    )
    pg_size_after = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM experiments")
    exp_after = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM narrative_results")
    res_after = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM source_narratives")
    src_after = cur.fetchone()[0]

pconn.close()

def format_bytes(bytes_val):
    """Format bytes as human-readable MB/GB."""
    if bytes_val is None:
        return "N/A"
    mb = bytes_val / (1024 * 1024)
    if mb >= 1024:
        return "{:.2f} GB".format(mb / 1024)
    else:
        return "{:.2f} MB".format(mb)

print("\n" + "="*60)
print("SQLite source: experiments={} narrative_results={} source_narratives={}".format(
    experiment_count, result_count, source_count
))
print("PostgreSQL before/after:")
print("  experiments: {} -> {} (processed {} rows, {} changed)".format(
    exp_before, exp_after, experiment_count, abs(exp_after - exp_before)))
print("  narrative_results: {} -> {} (processed {} rows, {} changed)".format(
    res_before, res_after, result_count, abs(res_after - res_before)))
print("  source_narratives: {} -> {} (processed {} rows, {} changed)".format(
    src_before, src_after, source_count, abs(src_after - src_before)))

# Format size with delta
size_before_str = format_bytes(pg_size_before)
size_after_str = format_bytes(pg_size_after)
if pg_size_after and pg_size_before:
    delta_bytes = pg_size_after - pg_size_before
    delta_str = format_bytes(abs(delta_bytes))
    if delta_bytes >= 0:
        delta_str = "+" + delta_str
    else:
        delta_str = "-" + delta_str
    print("  size: {} -> {} (delta {})".format(size_before_str, size_after_str, delta_str))
else:
    print("  size: {} -> {}".format(size_before_str, size_after_str))

if not full_refresh:
    actual_changes = sum([
        abs(exp_after - exp_before),
        abs(res_after - res_before),
        abs(src_after - src_before)
    ])
    total_processed = experiment_count + result_count + source_count
    print("\n⚡ Incremental sync: processed {} rows, {} actually changed/inserted".format(
        total_processed, actual_changes))
else:
    print("\n🔄 Full refresh completed")

print("="*60)
print("✅ PostgreSQL sync complete.")
PY

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

if (( ELAPSED >= 3600 )); then
  HOURS=$((ELAPSED / 3600))
  MINUTES=$(((ELAPSED % 3600) / 60))
  SECONDS=$((ELAPSED % 60))
  printf 'Sync duration: %02d:%02d:%02d\n' "$HOURS" "$MINUTES" "$SECONDS"
else
  printf 'Sync duration: %d seconds\n' "$ELAPSED"
fi

echo "Done syncing SQLite → PostgreSQL"
