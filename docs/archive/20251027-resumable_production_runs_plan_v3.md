# Resumable Production Runs: Spec v3 (Decision‑Focused)

Date: 2025-10-27
Version: 3.0 (Spec)
Owner: Research/Engineering
Scope: Reliable resume for ~42k narratives (20,946 cases × 2) production runs

## Objectives

- Resume long runs safely with the same `experiment_id` without reprocessing completed narratives.
- Read source narratives exclusively from the database after initial ingest.
- Ensure idempotency, data integrity, and clear operator visibility (progress, ETA).
- Prevent concurrent resumes of the same experiment.
- Minimize invasive changes; remain backward compatible.

## Out of Scope

- Multi-host distributed workers and heartbeats.
- Real-time web dashboards.

## Architecture Decisions

- Single source of truth for inputs
  - Load Excel once into `source_narratives` and reference DB only thereafter.
  - On subsequent runs, skip reloading if `data_source` already present and checksum matches.

- Resume by `experiment_id`
  - On resume, load canonical configuration from the existing experiment record (DB is authoritative).
  - Ignore YAML differences except to warn the operator about drift.

- Remaining work selection
  - Missing only: rows in `source_narratives` with no matching result for the `experiment_id`.
  - Retry errors only (optional): restrict to rows with `error_occurred = 1` for the `experiment_id`.

- Idempotency guard
  - Enforce one result per `(experiment_id, incident_id, narrative_type)` via a unique index.

- Concurrency control
  - Prevent two resume processes for the same `experiment_id` on a single host via a PID lock file under `data/.resume_lock_<experiment_id>.pid`.

- Data integrity
  - Persist an MD5 checksum of the source file alongside ingested records; fail resume if checksum mismatches.

- Progress reporting
  - Update progress and ETA in the `experiments` table periodically (e.g., every 100 narratives) and log to file.

- Durability
  - Commit DB writes in batches (e.g., every 100 narratives) and on clean shutdown; ensure robust finalize on completion.

## Data Model Changes (What and Why)

- `narrative_results`
  - UNIQUE constraint on `(experiment_id, incident_id, narrative_type)` to make inserts idempotent.
  - Optional diagnostics (future-friendly): `attempt_count`, `first_error_message`, `last_attempt_at`, `error_category`.

- `source_narratives`
  - Add `data_checksum TEXT` to detect input drift across resumes.

- `experiments`
  - Add `n_narratives_completed INTEGER`, `last_progress_update TEXT`, `estimated_completion_time TEXT` to expose progress/ETA.

- Migration script
  - Path: `scripts/sql/migration_resumable_v3.sql` (contains DDL and safe backfills).

## External Interfaces

- Environment variables (preferred)
  - `RESUME=1` enables resume mode.
  - `EXPERIMENT_ID=<uuid>` target experiment to resume (required when `RESUME=1`).
  - `RETRY_ERRORS_ONLY=1` reprocesses rows with `error_occurred = 1` only (optional).

- YAML (optional convenience)
  - `run.resume`, `run.experiment_id`, `run.retry_errors_only` (ignored when ENV is set; DB stays authoritative on resume).

- CLI and helpers
  - Standard entry: `Rscript scripts/run_experiment.R <config.yaml>`.
  - Optional helper: `scripts/resume_experiment.sh` to discover and resume the latest incomplete production experiment.

## High‑Level Flow

- New experiment
  - Load Excel into `source_narratives` if not present; capture `data_checksum`.
  - Create experiment (status: running); select narratives from DB; process; export; finalize.

- Resume experiment (same `experiment_id`)
  - Validate experiment status (allow: running/failed; disallow: completed).
  - Acquire resume lock; verify source file presence and checksum.
  - Build remaining set (missing only or retry errors only).
  - Process remaining narratives with batched commits and periodic progress updates.
  - Finalize experiment; release lock.

Pseudocode (concise)
- If `RESUME=1` and `EXPERIMENT_ID` set:
  - Load experiment from DB; guard status; acquire lock; verify checksum; build remaining set.
  - For each remaining narrative: call LLM, parse, log result; every N: commit and update progress.
  - Finalize metrics; release lock.
- Else: run current new‑experiment path.

## Operator Guidance (Summary)

- Monitoring
  - Query `experiments` for `n_narratives_completed`, `estimated_completion_time`, `status`.
  - Check `logs/experiments/<experiment_id>/*` for API, performance, and error logs.

- Disk space and backups
  - Ensure ≥300MB free for DB growth and backups before starting long runs.
  - Shell runner performs timestamped DB backups before overwriting/continuing production DBs.

- Handling crashes / stale locks
  - If a crash leaves a lock file, verify the PID is not active and remove `data/.resume_lock_<experiment_id>.pid` before resuming.

## Risks and Mitigations

- YAML/Config drift on resume → Use DB record as source of truth; warn on differences.
- Duplicate writes on retry → Unique index prevents duplicates; on retries, delete‑then‑insert or upsert.
- Long‑running transaction risk → Commit in small batches; keep transactions short.
- Input drift (Excel modifications) → Checksum validation; abort if changed.
- Concurrent resumes → PID lock; optionally escalate to DB‑level lock later.

## Test Matrix (Acceptance)

1) Resume after controlled kill: partial → full completion without duplicates.
2) Idempotency: re‑run a processed narrative; no new row appears; unique constraint holds.
3) Checksum mismatch: resume fails fast with clear error.
4) Retry errors only: only previously errored narratives are reprocessed; errors cleared.
5) Concurrent resume prevention: second resume attempt is rejected while first holds the lock.
6) Progress updates: `n_narratives_completed` and ETA advance regularly; finalize sets final metrics.

## Rollout Plan

- Apply DB migration `scripts/sql/migration_resumable_v3.sql` to production DB.
- Implement code changes in:
  - `scripts/run_experiment.R` (resume path, env flags, lock and checksum use).
  - `R/run_benchmark_core.R` (batched commits, progress updates, idempotent inserts).
  - `R/data_loader.R` (checksum capture/verify, DB‑only reads post‑ingest).
  - `R/experiment_logger.R` (status/lock/progress helpers).
- Smoke test with 200 narratives; verify resume, progress, and exports.
- Launch full production; monitor progress; use resume helper on interruption.

## Acceptance Criteria

- Resume works with the same `experiment_id` without duplication.
- Source Excel is read once per dataset; subsequent runs use DB only.
- Unique index prevents duplicates across resume boundaries.
- Progress and ETA visible in DB and logs during multi‑day runs.
- Concurrent resume attempts are blocked.
- All six test scenarios pass consistently.

## References

- v1: `docs/20251027-resumable_production_runs_plan.md` (initial design)
- v2: `docs/20251027-resumable_production_runs_plan_v2.md` (expanded with code examples)
- Migration (to be added): `scripts/sql/migration_resumable_v3.sql`
- Helper (optional): `scripts/resume_experiment.sh`

