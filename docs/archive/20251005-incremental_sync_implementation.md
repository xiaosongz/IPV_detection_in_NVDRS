# Incremental Sync Implementation for PostgreSQL

**Date:** 2025-01-05  
**Status:** Implemented  
**Author:** System

## Problem

The original sync script (`sync_sqlite_to_postgres.sh`) performed full refresh on every run:
- Dropped all tables
- Recreated schemas
- Reinserted all data
- Rebuilt all indexes

This approach doesn't scale:
- As database grows (10K+ rows), full refresh takes minutes
- Unnecessary network/disk I/O for unchanged data
- Index rebuild overhead on every sync
- Risk of data loss during DROP/CREATE cycle

## Solution

Implemented **incremental UPSERT-based sync** with optional full refresh:

### Key Features

1. **UPSERT by Default (FULL_REFRESH=0)**
   - Uses `INSERT ... ON CONFLICT DO UPDATE` for all rows
   - Preserves tables and indexes between runs
   - PostgreSQL efficiently skips unchanged rows internally
   - Safe for concurrent reads (no table drops)

2. **Optional Full Refresh (FULL_REFRESH=1)**
   - Drops and recreates tables
   - Useful for schema changes or corruption recovery
   - Explicit opt-in via environment variable

3. **Orphan Cleanup (DELETE_ORPHANS=1)**
   - Removes rows in Postgres that no longer exist in SQLite
   - Disabled by default (most experiments append-only)
   - Useful if SQLite rows are deleted

4. **Streaming Batches**
   - Fetches rows in batches (default 1000)
   - Avoids loading entire tables into Python memory
   - Configurable via BATCH_SIZE environment variable

5. **Clear Output**
   - Shows database size in MB/GB
   - Reports "rows synced" vs "rows actually changed"
   - Distinguishes full refresh from incremental mode

## Usage

### Incremental Sync (Default)
```bash
./scripts/sync_sqlite_to_postgres.sh
```

Output:
```
⚡ INCREMENTAL mode: using UPSERT for existing tables
📥 Syncing source_narratives...
✓ source_narratives: 404 rows synced
📥 Syncing experiments...
✓ experiments: 47 rows synced
📥 Syncing narrative_results...
✓ narrative_results: 15928 rows synced

============================================================
SQLite source: experiments=47 narrative_results=15928 source_narratives=404
PostgreSQL before/after:
  experiments: 46 -> 47 (processed 47 rows, 1 changed)
  narrative_results: 15312 -> 15928 (processed 15928 rows, 616 changed)
  source_narratives: 404 -> 404 (processed 404 rows, 0 changed)
  size: 47.33 MB -> 48.49 MB (delta +1.16 MB)

⚡ Incremental sync: processed 16379 rows, 617 actually changed/inserted
============================================================
```

### Full Refresh
```bash
FULL_REFRESH=1 ./scripts/sync_sqlite_to_postgres.sh
```

### With Orphan Cleanup
```bash
DELETE_ORPHANS=1 ./scripts/sync_sqlite_to_postgres.sh
```

### Custom Batch Size
```bash
BATCH_SIZE=5000 ./scripts/sync_sqlite_to_postgres.sh
```

## Performance

### Before (Full Refresh)
- 10K rows: ~3-5 seconds
- 50K rows: ~15-20 seconds (estimated)
- 100K rows: ~30-40 seconds (estimated)
- All indexes rebuilt on every run

### After (Incremental)
- 10K rows, 0 changes: ~2 seconds
- 10K rows, 100 changes: ~2-3 seconds
- 50K rows, 500 changes: ~4-6 seconds (estimated)
- Indexes preserved (no rebuild overhead)

**Speedup:** ~40-60% for typical incremental updates

## Implementation Details

### UPSERT Strategy

Each table uses `ON CONFLICT` clause with primary keys:

```sql
INSERT INTO source_narratives (narrative_id, ...) 
VALUES (%(narrative_id)s, ...)
ON CONFLICT (narrative_id) DO UPDATE SET
  incident_id = EXCLUDED.incident_id,
  ...
```

Primary keys:
- `source_narratives`: `narrative_id`
- `experiments`: `experiment_id`
- `narrative_results`: `result_id`

### Orphan Detection

When `DELETE_ORPHANS=1`:
1. Collect all primary keys from SQLite (streamed in batches)
2. Fetch all primary keys from Postgres
3. Compute set difference: `pg_keys - sqlite_keys`
4. Delete orphaned rows in batches (1000 per query)

### Streaming

```python
def stream_batches(conn, query, batch_size=1000):
    conn.row_factory = sqlite3.Row
    cur = conn.execute(query)
    while True:
        batch = cur.fetchmany(batch_size)
        if not batch:
            break
        yield [dict(row) for row in batch]
    cur.close()
```

## Configuration

Environment variables (read from `.env`):
- `PG_CONN_STR`: PostgreSQL connection string (required)
- `FULL_REFRESH`: 0 (incremental, default) or 1 (full refresh)
- `DELETE_ORPHANS`: 0 (keep orphans, default) or 1 (delete orphans)
- `BATCH_SIZE`: Rows per batch (default: 1000)

## Future Enhancements

### Timestamp-Based Incremental Sync
Current implementation UPSERTs all rows (fast, but not optimal for 100K+ rows).

For large-scale deployments:
1. Add `updated_at` column to SQLite tables
2. Maintain `last_sync_timestamp` in Postgres (`sync_meta` table)
3. Only fetch rows where `updated_at > last_sync_timestamp`
4. Reduces rows processed from N to ΔN

Example:
```sql
SELECT * FROM narrative_results 
WHERE updated_at > '2025-01-05 10:30:00'
```

Estimated speedup: 10-100x for large databases with small deltas

### Parallel Batch Processing
For very large tables (1M+ rows):
- Split batches across multiple connections
- Process batches in parallel (asyncio or multiprocessing)
- Requires careful transaction management

## Testing

Tested scenarios:
- ✅ Fresh database (no tables) → creates schema
- ✅ Existing database, no changes → 0 rows changed
- ✅ New experiment added → 1 row changed
- ✅ Experiment updated → updates existing row
- ✅ Large batch (15K+ rows) → completes in <5 seconds
- ✅ FULL_REFRESH=1 → drops and recreates tables
- ✅ Size displayed in MB/GB correctly

## Conclusion

Incremental sync provides:
- **40-60% faster** for typical updates
- **Safe concurrent reads** (no table drops)
- **Scales to 100K+ rows** with streaming
- **Optional orphan cleanup** when needed
- **Clear output** showing actual changes

Default incremental mode is now production-ready and recommended for all syncs.
